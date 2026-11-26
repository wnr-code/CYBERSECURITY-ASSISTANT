package __ANDROID_PACKAGE__

import android.app.Activity
import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Handler
import android.provider.Settings
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

/** Flutter/JNI bridge for the pinned llama.cpp CPU runtime. */
internal object LocalAiInferenceBridge {
    private const val CHANNEL = "org.cybersecurityassistant/local_ai_runtime"
    private const val MAX_MODEL_BYTES = 8L * 1024 * 1024 * 1024
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val inferenceRunning = AtomicBoolean(false)
    private val inferenceRequestId = AtomicLong(0)
    @Volatile private var loadedModelName: String? = null
    @Volatile private var loadedModelSha256: String? = null
    @Volatile private var loadedPublisherMetadataVerified: Boolean = false
    @Volatile private var loadedInferenceSucceeded: Boolean = false
    @Volatile private var loadedOfflineInferenceSucceeded: Boolean = false
    private const val MODEL_RECEIPT_PREFERENCES = "local_ai_verified_model_receipt"

    // App-pinned immutable upstream revision. Runtime installation still
    // verifies publisher metadata and complete file bytes before JNI sees it.
    // This digest is an identity check, not a guarantee that model content is risk-free.
    private data class ModelPin(val repository: String, val revision: String, val license: String, val size: Long, val sha256: String)
    private val trustedModels = mapOf(
        "qwen2.5-1.5b-instruct-q4_k_m.gguf" to ModelPin(
            repository = "Qwen/Qwen2.5-1.5B-Instruct-GGUF",
            revision = "91cad51170dc346986eccefdc2dd33a9da36ead9",
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
    private external fun nativeCancelInference()
    private external fun nativeResetInferenceCancellation()

    fun attachChannel(activity: Activity, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getRuntimeStatus" -> runOnWorker(result) { restorePersistedModel(activity); statusMap(activity) }
                "getDiagnosticStatus" -> runOnWorker(result) { restorePersistedModel(activity); statusMap(activity, includeInventory = true) }
                "loadVerifiedModel" -> runOnWorker(result) { loadVerifiedModel(activity, call) }
                "deleteInstalledModel" -> runOnWorker(result) { deleteInstalledModel(activity) }
                "cancelInference" -> {
                    inferenceRequestId.incrementAndGet()
                    nativeCancelInference()
                    result.success(true)
                }
                "unloadModel" -> runOnWorker(result) {
                    nativeUnloadModel()
                    loadedModelName = null
                    loadedModelSha256 = null
                    loadedPublisherMetadataVerified = false
                    loadedInferenceSucceeded = false
                    loadedOfflineInferenceSucceeded = false
                    true
                }
                "complete" -> {
                    if (!inferenceRunning.compareAndSet(false, true)) {
                        result.error("local_ai_unavailable", "A local inference request is already running.", null)
                    } else {
                        val requestId = inferenceRequestId.incrementAndGet()
                        nativeResetInferenceCancellation()
                        runOnWorker(result) {
                            try { complete(activity, call, requestId) } finally { inferenceRunning.set(false) }
                        }
                    }
                }
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
        "publisherMetadataVerified" to loadedPublisherMetadataVerified,
        "inferenceSucceeded" to loadedInferenceSucceeded,
        "offlineInferenceSucceeded" to loadedOfflineInferenceSucceeded,
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
                    "trusted" to (loadedPublisherMetadataVerified && trustedModels[file.name]?.let { it.sha256 == actual && it.size == file.length() } == true),
                )
            }?.toList() ?: emptyList()
    }

    /** Restore only a receipt that exactly matches this build's static pin, and rehash the private file before JNI load. */
    private fun restorePersistedModel(activity: Activity): Boolean {
        if (loadedModelName != null && loadedPublisherMetadataVerified) return true
        val pin = trustedModels.values.firstOrNull() ?: return false
        val receipt = activity.getSharedPreferences(MODEL_RECEIPT_PREFERENCES, Context.MODE_PRIVATE)
        val receiptMatches = receipt.getString("fileName", null) == trustedModels.entries.firstOrNull { it.value == pin }?.key &&
            receipt.getString("repository", null) == pin.repository &&
            receipt.getString("author", null) == pin.repository.substringBefore('/') &&
            receipt.getString("revision", null) == pin.revision &&
            receipt.getString("license", null)?.equals(pin.license, ignoreCase = true) == true &&
            receipt.getLong("sizeBytes", -1L) == pin.size &&
            receipt.getString("sha256", null)?.equals(pin.sha256, ignoreCase = true) == true
        if (!receiptMatches) return false
        val name = trustedModels.entries.firstOrNull { it.value == pin }?.key ?: return false
        val modelRoot = File(activity.filesDir, "local_ai/models").canonicalFile
        val modelFile = File(modelRoot, name).canonicalFile
        if (modelFile.parentFile != modelRoot || !modelFile.isFile || modelFile.length() != pin.size || modelFile.length() > MAX_MODEL_BYTES) {
            loadedPublisherMetadataVerified = false
            return false
        }
        val actual = sha256(modelFile)
        if (!MessageDigest.isEqual(actual.toByteArray(), pin.sha256.toByteArray())) {
            loadedPublisherMetadataVerified = false
            return false
        }
        loadedPublisherMetadataVerified = true
        if (loadedModelName == name && loadedModelSha256 == actual) return true
        nativeUnloadModel()
        loadedModelName = null
        loadedModelSha256 = null
        loadedInferenceSucceeded = false
        loadedOfflineInferenceSucceeded = false
        if (!nativeLoadModel(modelFile.absolutePath)) return false
        loadedModelName = name
        loadedModelSha256 = actual
        return true
    }

    private fun deleteInstalledModel(activity: Activity): Boolean {
        val name = trustedModels.keys.singleOrNull() ?: throw IllegalStateException("No single pinned Local AI model is configured.")
        val modelRoot = File(activity.filesDir, "local_ai/models").canonicalFile
        if (!modelRoot.exists() && !modelRoot.mkdirs()) throw IllegalStateException("Could not access the private Local AI model directory.")
        val targets = listOf(File(modelRoot, name), File(modelRoot, "$name.part"))
        targets.forEach { file ->
            val canonical = file.canonicalFile
            if (canonical.parentFile != modelRoot) throw SecurityException("Model removal path escaped private storage.")
        }
        nativeUnloadModel()
        loadedModelName = null
        loadedModelSha256 = null
        loadedPublisherMetadataVerified = false
        loadedInferenceSucceeded = false
        loadedOfflineInferenceSucceeded = false
        var removed = false
        for (file in targets) {
            if (file.exists()) {
                if (!file.delete()) throw IllegalStateException("Could not remove the pinned model file from private storage.")
                removed = true
            }
        }
        activity.getSharedPreferences(MODEL_RECEIPT_PREFERENCES, Context.MODE_PRIVATE).edit().clear().commit()
        return removed
    }

    private fun persistVerifiedReceipt(activity: Activity, name: String, pin: ModelPin): Boolean =
        activity.getSharedPreferences(MODEL_RECEIPT_PREFERENCES, Context.MODE_PRIVATE).edit()
            .putString("fileName", name)
            .putString("repository", pin.repository)
            .putString("author", pin.repository.substringBefore('/'))
            .putString("revision", pin.revision)
            .putString("license", pin.license)
            .putLong("sizeBytes", pin.size)
            .putString("sha256", pin.sha256)
            .commit()

    private fun loadVerifiedModel(activity: Activity, call: MethodCall): Map<String, Any?> {
        val name = call.argument<String>("fileName") ?: throw IllegalArgumentException("Model filename is required.")
        val expected = call.argument<String>("sha256")?.lowercase() ?: throw IllegalArgumentException("Trusted model digest is required.")
        if (!name.matches(Regex("[A-Za-z0-9._-]{1,180}\\.gguf")) || !expected.matches(Regex("[0-9a-f]{64}"))) {
            throw IllegalArgumentException("Model filename or trusted digest is malformed.")
        }
        val pin = trustedModels[name]
            ?: throw IllegalStateException("No publisher-pinned Local AI model is enabled in this build.")
        if (expected != pin.sha256) throw SecurityException("Requested model digest is not in the app-owned trust manifest.")
        val publisherRepository = call.argument<String>("publisherRepository")
        val publisherAuthor = call.argument<String>("publisherAuthor")
        val publisherRevision = call.argument<String>("publisherRevision")
        val publisherLicense = call.argument<String>("publisherLicense")
        val publisherSizeBytes = (call.argument<Number>("publisherSizeBytes"))?.toLong()
        val publisherSha256 = call.argument<String>("publisherSha256")?.lowercase()
        if (publisherRepository != pin.repository || publisherAuthor != pin.repository.substringBefore('/') ||
            publisherRevision != pin.revision || publisherLicense?.lowercase() != pin.license.lowercase() ||
            publisherSizeBytes != pin.size || publisherSha256 != pin.sha256) {
            throw SecurityException("Official publisher metadata verification did not match the native model pin.")
        }
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
        loadedPublisherMetadataVerified = true
        loadedInferenceSucceeded = false
        loadedOfflineInferenceSucceeded = false
        if (!persistVerifiedReceipt(activity, name, pin)) {
            loadedPublisherMetadataVerified = false
            throw IllegalStateException("Could not persist the verified model receipt in app-private storage.")
        }
        if (!nativeLoadModel(modelFile.absolutePath)) throw IllegalStateException("llama.cpp could not load the verified GGUF model.")
        loadedModelName = name
        loadedModelSha256 = actual
        return statusMap(activity)
    }

    private fun complete(activity: Activity, call: MethodCall, requestId: Long): String {
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
        val maxTokens = (call.argument<Int>("maxTokens") ?: 96).coerceIn(1, 96)
        val offlineBefore = isNetworkIsolated(activity)
        val output = nativeComplete(roles.toTypedArray(), contents.toTypedArray(), maxTokens)
            ?: throw IllegalStateException("Local inference failed or was stopped; no cloud fallback was attempted.")
        if (requestId != inferenceRequestId.get()) {
            throw IllegalStateException("Local inference was cancelled; no cloud fallback was attempted.")
        }
        val response = output.toString(Charsets.UTF_8).take(12_000)
        if (response.isNotBlank()) {
            loadedInferenceSucceeded = true
            if (offlineBefore && isNetworkIsolated(activity)) loadedOfflineInferenceSucceeded = true
        }
        return response
    }

    private fun isNetworkIsolated(context: Context): Boolean = runCatching {
        val airplaneMode = Settings.Global.getInt(context.contentResolver, Settings.Global.AIRPLANE_MODE_ON, 0) == 1
        val connectivity = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val activeNetwork = connectivity.activeNetwork
        if (!airplaneMode) {
            false
        } else if (activeNetwork == null) {
            true
        } else {
            val capabilities = connectivity.getNetworkCapabilities(activeNetwork)
            capabilities != null && !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        }
    }.getOrDefault(false)

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
