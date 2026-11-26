package __ANDROID_PACKAGE__

import android.app.Activity
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest
import java.util.concurrent.Executors

/** Flutter/JNI bridge for the pinned llama.cpp CPU runtime. */
internal object LocalAiInferenceBridge {
    private const val CHANNEL = "org.cybersecurityassistant/local_ai_runtime"
    private const val MAX_MODEL_BYTES = 8L * 1024 * 1024 * 1024
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile private var loadedModelName: String? = null
    @Volatile private var loadedModelSha256: String? = null

    // Qwen's user-supplied immutable upstream pin. Runtime installation still
    // verifies the complete file byte count and SHA-256 before JNI sees it.
    // This digest is an identity check, not a guarantee that model content is risk-free.
    private data class ModelPin(val repository: String, val revision: String, val license: String, val size: Long, val sha256: String)
    private val trustedModels = mapOf(
        "qwen2.5-1.5b-instruct-q4_k_m.gguf" to ModelPin(
            repository = "Qwen/Qwen2.5-1.5B-Instruct-GGUF",
            revision = "dd26da440ef0330c47919d1ecae0966d24022222",
            license = "Apache-2.0",
            size = 1_117_320_736L,
            sha256 = "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e",
        ),
    )

    init {
        System.loadLibrary("csa_localai")
    }

    private external fun nativeLoadModel(path: String): Boolean
    private external fun nativeUnloadModel()
    private external fun nativeComplete(roles: Array<ByteArray>, contents: Array<ByteArray>, maxTokens: Int): ByteArray?

    fun attachChannel(activity: Activity, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getRuntimeStatus" -> runOnWorker(result) { statusMap(activity) }
                "getDiagnosticStatus" -> runOnWorker(result) { statusMap(activity, includeInventory = true) }
                "loadVerifiedModel" -> runOnWorker(result) { loadVerifiedModel(activity, call) }
                "unloadModel" -> runOnWorker(result) {
                    nativeUnloadModel()
                    loadedModelName = null
                    loadedModelSha256 = null
                    true
                }
                "complete" -> runOnWorker(result) { complete(call) }
                else -> result.notImplemented()
            }
        }
    }

    private fun statusMap(activity: Activity, includeInventory: Boolean = false): Map<String, Any?> = mapOf(
        "sourceCommit" to "ea722948146befb23c9529c1ec7f59fb2f34911f",
        "runtimeLoaded" to true,
        "modelLoaded" to (loadedModelName != null),
        "modelName" to loadedModelName,
        "modelSha256" to loadedModelSha256,
        "pinnedModelRepository" to trustedModels.values.firstOrNull()?.repository,
        "pinnedModelRevision" to trustedModels.values.firstOrNull()?.revision,
        "pinnedModelLicense" to trustedModels.values.firstOrNull()?.license,
        "installedModels" to if (includeInventory) installedModelInventory(activity) else emptyList<Map<String, Any?>>(),
        "abi" to "arm64-v8a",
        "backend" to "cpu",
    )

    private fun installedModelInventory(activity: Activity): List<Map<String, Any?>> {
        val modelRoot = File(activity.filesDir, "local_ai/models").canonicalFile
        if (!modelRoot.exists() || !modelRoot.isDirectory) return emptyList()
        return modelRoot.listFiles()?.asSequence()
            ?.filter { it.isFile && it.name.matches(Regex("[A-Za-z0-9._-]{1,180}\\.gguf")) && it.length() in 1..MAX_MODEL_BYTES }
            ?.map { file ->
                val actual = sha256(file)
                mapOf(
                    "fileName" to file.name,
                    "sizeBytes" to file.length(),
                    "sha256" to actual,
                    "trusted" to (trustedModels[file.name]?.let { it.sha256 == actual && it.size == file.length() } == true),
                )
            }?.toList() ?: emptyList()
    }

    private fun loadVerifiedModel(activity: Activity, call: MethodCall): Map<String, Any?> {
        val name = call.argument<String>("fileName") ?: throw IllegalArgumentException("Model filename is required.")
        val expected = call.argument<String>("sha256")?.lowercase() ?: throw IllegalArgumentException("Trusted model digest is required.")
        if (!name.matches(Regex("[A-Za-z0-9._-]{1,180}\\.gguf")) || !expected.matches(Regex("[0-9a-f]{64}"))) {
            throw IllegalArgumentException("Model filename or trusted digest is malformed.")
        }
        val pin = trustedModels[name]
            ?: throw IllegalStateException("No publisher-pinned Local AI model is enabled in this build.")
        if (expected != pin.sha256) throw SecurityException("Requested model digest is not in the app-owned trust manifest.")
        val modelRoot = File(activity.filesDir, "local_ai/models").canonicalFile
        if (!modelRoot.exists() || !modelRoot.isDirectory) throw IllegalStateException("No verified Local AI model is installed.")
        val modelFile = File(modelRoot, name).canonicalFile
        if (modelFile.parentFile != modelRoot || !modelFile.isFile || modelFile.length() != pin.size || modelFile.length() > MAX_MODEL_BYTES) {
            throw IllegalStateException("Model file is missing, outside the private model store, or its size differs from the pinned manifest.")
        }
        val actual = sha256(modelFile)
        if (!MessageDigest.isEqual(actual.toByteArray(), pin.sha256.toByteArray())) {
            modelFile.delete()
            throw SecurityException("Installed model digest does not match the trusted manifest; the file was removed.")
        }
        nativeUnloadModel()
        loadedModelName = null
        loadedModelSha256 = null
        if (!nativeLoadModel(modelFile.absolutePath)) throw IllegalStateException("llama.cpp could not load the verified GGUF model.")
        loadedModelName = name
        loadedModelSha256 = actual
        return statusMap(activity)
    }

    private fun complete(call: MethodCall): String {
        if (loadedModelName == null) throw IllegalStateException("Local AI is Not Ready: no verified model is loaded.")
        val input = call.argument<List<Map<String, String>>>("messages") ?: throw IllegalArgumentException("Chat messages are required.")
        if (input.isEmpty() || input.size > 32) throw IllegalArgumentException("Conversation exceeds the safe turn limit.")
        val roles = ArrayList<ByteArray>(input.size)
        val contents = ArrayList<ByteArray>(input.size)
        var totalBytes = 0
        for (message in input) {
            val role = message["role"] ?: throw IllegalArgumentException("Message role is missing.")
            val content = message["content"] ?: throw IllegalArgumentException("Message content is missing.")
            if (role !in setOf("user", "assistant", "system") || content.length > 8000) {
                throw IllegalArgumentException("Message is not supported by the local inference bridge.")
            }
            val roleBytes = role.toByteArray(Charsets.UTF_8)
            val contentBytes = content.toByteArray(Charsets.UTF_8)
            totalBytes += roleBytes.size + contentBytes.size
            if (totalBytes > 16 * 1024) throw IllegalArgumentException("Conversation exceeds the safe byte limit.")
            roles.add(roleBytes)
            contents.add(contentBytes)
        }
        val maxTokens = (call.argument<Int>("maxTokens") ?: 256).coerceIn(1, 512)
        val output = nativeComplete(roles.toTypedArray(), contents.toTypedArray(), maxTokens)
            ?: throw IllegalStateException("Local inference failed; no cloud fallback was attempted.")
        return output.toString(Charsets.UTF_8).take(12_000)
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        FileInputStream(file).use { input ->
            val buffer = ByteArray(1024 * 1024)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) }
    }

    private fun runOnWorker(result: MethodChannel.Result, operation: () -> Any?) {
        executor.execute {
            try {
                val value = operation()
                mainHandler.post { result.success(value) }
            } catch (error: Throwable) {
                val safeCode = when (error) {
                    is SecurityException -> "local_ai_integrity_error"
                    is IllegalArgumentException -> "local_ai_invalid_request"
                    else -> "local_ai_unavailable"
                }
                val safeMessage = error.message?.take(240) ?: "Local AI operation failed. No cloud fallback was attempted."
                mainHandler.post { result.error(safeCode, safeMessage, null) }
            }
        }
    }
}
