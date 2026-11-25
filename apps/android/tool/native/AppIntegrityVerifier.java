package __ANDROID_PACKAGE__;

import android.app.Activity;
import android.content.Context;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.os.Build;

import java.io.File;
import java.io.FileInputStream;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.HashSet;
import java.util.regex.Pattern;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

/** Native signer and installed APK identity check; updates remain OS/Play Store controlled. */
public final class AppIntegrityVerifier {
    private static final String CHANNEL = "org.cybersecurityassistant/app_integrity";
    private static final Pattern PIN = Pattern.compile("^[0-9a-f]{64}$");

    private AppIntegrityVerifier() {}

    public static void verifyOrThrow(Activity activity) {
        if (!"release".equals(BuildConfig.BUILD_TYPE)) return;
        Map<String, Object> identity = inspect(activity, false);
        if (!Boolean.TRUE.equals(identity.get("trustedSigner"))) {
            throw new SecurityException("Trusted APK identity or integrity verification failed; refusing to start.");
        }
    }

    public static void attachChannel(Activity activity, FlutterEngine engine) {
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    if (!"getInstalledIdentity".equals(call.method)) {
                        result.notImplemented();
                    } else {
                        result.success(inspect(activity));
                    }
                });
    }

    private static Map<String, Object> inspect(Context context) {
        return inspect(context, true);
    }

    private static Map<String, Object> inspect(Context context, boolean includeComponentsDigest) {
        Map<String, Object> result = new HashMap<>();
        try {
            String packageName = context.getPackageName();
            if (!packageName.equals(BuildConfig.APPLICATION_ID)) throw new SecurityException("Application ID mismatch.");
            PackageInfo info = context.getPackageManager().getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES);
            List<String> signerDigests = new ArrayList<>();
            if (info.signingInfo != null && info.signingInfo.getApkContentsSigners() != null) {
                for (android.content.pm.Signature signature : info.signingInfo.getApkContentsSigners()) {
                    signerDigests.add(hex(MessageDigest.getInstance("SHA-256").digest(signature.toByteArray())));
                }
            }
            Collections.sort(signerDigests);
            String rawPins = context.getString(R.string.trusted_apk_cert_sha256);
            Set<String> pins = new HashSet<>();
            for (String value : rawPins.split(",")) {
                String normalized = value.trim().toLowerCase();
                if (PIN.matcher(normalized).matches()) pins.add(normalized);
            }
            boolean configured = !pins.isEmpty();
            String signer = signerDigests.size() == 1 ? signerDigests.get(0) : null;
            boolean trusted = configured && signer != null && pins.contains(signer);
            android.content.pm.ApplicationInfo appInfo = info.applicationInfo;
            List<String> apkPaths = new ArrayList<>();
            if (appInfo != null && appInfo.sourceDir != null) apkPaths.add(appInfo.sourceDir);
            if (appInfo != null && appInfo.splitSourceDirs != null) apkPaths.addAll(Arrays.asList(appInfo.splitSourceDirs));
            Collections.sort(apkPaths);
            String apkDigest = !includeComponentsDigest || apkPaths.isEmpty() ? null : digestApkFiles(apkPaths);
            String installer = installerPackage(context, packageName);
            result.put("status", !configured ? "unconfigured" : (trusted && apkDigest != null ? "trusted" : "untrusted"));
            result.put("packageName", packageName);
            result.put("versionCode", info.getLongVersionCode());
            result.put("versionName", info.versionName);
            result.put("signerSha256", signer);
            result.put("signerSha256All", signerDigests);
            result.put("signerPinConfigured", configured);
            result.put("trustedSigner", trusted);
            result.put("installedComponentsSha256", apkDigest);
            result.put("installerPackageName", installer);
        } catch (Exception error) {
            result.clear();
            result.put("status", "unavailable");
            result.put("packageName", context.getPackageName());
            result.put("versionCode", 0L);
            result.put("signerSha256", null);
            result.put("signerPinConfigured", false);
            result.put("trustedSigner", false);
            result.put("installedComponentsSha256", null);
            result.put("installerPackageName", null);
        }
        return result;
    }

    private static String installerPackage(Context context, String packageName) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                return context.getPackageManager().getInstallSourceInfo(packageName).getInstallingPackageName();
            }
            //noinspection deprecation
            return context.getPackageManager().getInstallerPackageName(packageName);
        } catch (Exception ignored) {
            return null;
        }
    }

    private static String digestApkFiles(List<String> paths) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        byte[] buffer = new byte[32 * 1024];
        for (String path : paths) {
            File file = new File(path);
            if (!file.isFile() || !file.canRead()) throw new SecurityException("Installed APK component is unavailable.");
            digest.update(file.getName().getBytes(java.nio.charset.StandardCharsets.UTF_8));
            try (FileInputStream input = new FileInputStream(file)) {
                int read;
                while ((read = input.read(buffer)) >= 0) digest.update(buffer, 0, read);
            }
        }
        return hex(digest.digest());
    }

    private static String hex(byte[] bytes) {
        StringBuilder output = new StringBuilder(bytes.length * 2);
        for (byte value : bytes) output.append(String.format("%02x", value & 0xff));
        return output.toString();
    }
}
