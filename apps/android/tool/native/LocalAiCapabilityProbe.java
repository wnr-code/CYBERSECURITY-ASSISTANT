package __ANDROID_PACKAGE__;

import android.app.Activity;
import android.app.ActivityManager;
import android.content.Context;
import android.os.Build;
import android.os.Environment;
import android.os.StatFs;

import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

/** Reports Android device resources only; it is not an inference runtime. */
public final class LocalAiCapabilityProbe {
    private static final String CHANNEL = "org.cybersecurityassistant/local_ai_capabilities";

    private LocalAiCapabilityProbe() {}

    public static void attachChannel(Activity activity, FlutterEngine engine) {
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    if (!"getDeviceCapabilities".equals(call.method)) {
                        result.notImplemented();
                    } else {
                        result.success(inspect(activity));
                    }
                });
    }

    private static Map<String, Object> inspect(Context context) {
        ActivityManager.MemoryInfo memory = new ActivityManager.MemoryInfo();
        ActivityManager manager = (ActivityManager) context.getSystemService(Context.ACTIVITY_SERVICE);
        manager.getMemoryInfo(memory);
        StatFs storage = new StatFs(Environment.getDataDirectory().getAbsolutePath());
        long blockSize = storage.getBlockSizeLong();
        Map<String, Object> values = new HashMap<>();
        values.put("supportedAbis", Arrays.asList(Build.SUPPORTED_ABIS));
        values.put("totalRamBytes", memory.totalMem);
        values.put("availableRamBytes", memory.availMem);
        values.put("totalStorageBytes", storage.getBlockCountLong() * blockSize);
        values.put("availableStorageBytes", storage.getAvailableBlocksLong() * blockSize);
        // This build does not bundle/integrate a Local AI engine or model manager.
        values.put("runtimeAvailable", false);
        values.put("installedModelCount", 0);
        return values;
    }
}
