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

    // Fail closed until an immutable publisher revision, exact filename, license,
    // byte length, and digest have been reviewed and pinned in app-owned source.
    private val trustedModelDigests = emptyMap<String, String>()

    init {
        System.loadLibrary("csa_localai")
    }

    private external fun nativeLoadModel(path: String): Boolean
    private external fun nativeUnloadModel()
    private external fun nativeComplete(roles: Array<ByteArray>, contents: Array<ByteArray>, maxTokens: Int): ByteArray?

    fun attachChannel(activity: Activity, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getRuntimeStatus" -> result.success(statusMap())
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

    private fun statusMap(): Map<String, Any?> = mapOf(
        "sourceCommit" to "ea722948146befb23c9529c1ec7f59fb2f34911f",
        "runtimeLoaded" to true,
        "modelLoaded" to (loadedModelName != null),
        "modelName" to loadedModelName,
        "modelSha256" to loadedModelSha256,
        "abi" to "arm64-v8a",
        "backend" to "cpu",
    )

    private fun loadVerifiedModel(activity: Activity, call: MethodCall): Map<String, Any?> {
        val name = call.argument<String>("fileName") ?: throw IllegalArgumentException("Model filename is required.")
        val expected = call.argument<String>("sha256")?.lowercase() ?: throw IllegalArgumentException("Trusted model digest is required.")
        if (!name.matches(Regex("[A-Za-z0-9._-]{1,180}\\.gguf")) || !expected.matches(Regex("[0-9a-f]{64}"))) {
            throw IllegalArgumentException("Model filename or trusted digest is malformed.")
        }
        val pinnedDigest = trustedModelDigests[name]
            ?: throw IllegalStateException("No publisher-verified Local AI model is enabled in this build.")
        if (expected != pinnedDigest) throw SecurityException("Requested model digest is not in the app-owned trust manifest.")
        val modelRoot = File(activity.filesDir, "local_ai/models").canonicalFile
        if (!modelRoot.exists() || !modelRoot.isDirectory) throw IllegalStateException("No verified Local AI model is installed.")
        val modelFile = File(modelRoot, name).canonicalFile
        if (modelFile.parentFile != modelRoot || !modelFile.isFile || modelFile.length() <= 0L || modelFile.length() > MAX_MODEL_BYTES) {
            throw IllegalStateException("Model file is missing or outside the private model store.")
        }
        val actual = sha256(modelFile)
        if (!MessageDigest.isEqual(actual.toByteArray(), expected.toByteArray())) {
            modelFile.delete()
            throw SecurityException("Installed model digest does not match the trusted manifest; the file was removed.")
        }
        nativeUnloadModel()
        if (!nativeLoadModel(modelFile.absolutePath)) throw IllegalStateException("llama.cpp could not load the verified GGUF model.")
        loadedModelName = name
        loadedModelSha256 = actual
        return statusMap()
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
