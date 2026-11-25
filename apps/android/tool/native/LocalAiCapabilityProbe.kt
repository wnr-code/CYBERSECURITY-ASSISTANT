package __ANDROID_PACKAGE__

import android.app.Activity
import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.Environment
import android.os.StatFs
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Reports Android device resources only; it is not an inference runtime. */
internal object LocalAiCapabilityProbe {
    private const val CHANNEL = "org.cybersecurityassistant/local_ai_capabilities"

    fun attachChannel(activity: Activity, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method != "getDeviceCapabilities") {
                result.notImplemented()
            } else {
                result.success(inspect(activity))
            }
        }
    }

    private fun inspect(context: Context): Map<String, Any> {
        val memory = ActivityManager.MemoryInfo()
        (context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(memory)
        val storage = StatFs(Environment.getDataDirectory().absolutePath)
        val blockSize = storage.blockSizeLong
        return mapOf(
            "supportedAbis" to Build.SUPPORTED_ABIS.toList(),
            "totalRamBytes" to memory.totalMem,
            "availableRamBytes" to memory.availMem,
            "totalStorageBytes" to storage.blockCountLong * blockSize,
            "availableStorageBytes" to storage.availableBlocksLong * blockSize,
            "runtimeAvailable" to false,
            "installedModelCount" to 0,
        )
    }
}
