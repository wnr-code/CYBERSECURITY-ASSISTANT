package __ANDROID_PACKAGE__

import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest

/**
 * Native identity check. Android Package Manager remains the authority for APK
 * signature verification and same-signer package replacement. The explicit
 * pin is supplied by the release build environment, never guessed in source.
 */
internal object AppIntegrityVerifier {
    private const val CHANNEL = "org.cybersecurityassistant/app_integrity"
    private const val PIN_RESOURCE = "trusted_apk_cert_sha256"

    fun verifyOrThrow(activity: Activity) {
        if (BuildConfig.BUILD_TYPE != "release") return
        val result = inspect(activity, includeComponentsDigest = false)
        if (result["trustedSigner"] != true) {
            throw SecurityException("Trusted APK identity or integrity verification failed; refusing to start.")
        }
    }

    fun attachChannel(activity: Activity, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method != "getInstalledIdentity") {
                result.notImplemented()
            } else {
                result.success(inspect(activity))
            }
        }
    }

    private fun inspect(context: Context, includeComponentsDigest: Boolean = true): Map<String, Any?> {
        return try {
            val packageName = context.packageName
            if (packageName != BuildConfig.APPLICATION_ID) throw SecurityException("Installed application ID differs from the build identity.")
            val packageInfo = context.packageManager.getPackageInfo(
                packageName,
                PackageManager.GET_SIGNING_CERTIFICATES,
            )
            val signingInfo = packageInfo.signingInfo
            val signerDigests = signingInfo?.apkContentsSigners
                ?.map { signer -> MessageDigest.getInstance("SHA-256").digest(signer.toByteArray()).toHex() }
                ?.sorted()
                ?: emptyList()
            val pinText = context.getString(resolvePinResource(context))
            val pins = pinText.split(',')
                .map { value -> value.trim().lowercase() }
                .filter { value -> value.matches(Regex("^[0-9a-f]{64}$")) }
                .toSet()
            val pinConfigured = pins.isNotEmpty()
            val trusted = pinConfigured && signerDigests.size == 1 && signerDigests.single() in pins
            val appInfo = packageInfo.applicationInfo
            val apkPaths = (listOfNotNull(appInfo?.sourceDir) + (appInfo?.splitSourceDirs?.toList() ?: emptyList())).distinct().sorted()
            val apkDigest = if (!includeComponentsDigest || apkPaths.isEmpty()) null else digestApkFiles(apkPaths)
            val installer = installerPackage(context, packageName)
            mapOf(
                "status" to when {
                    !pinConfigured -> "unconfigured"
                    trusted && apkDigest != null -> "trusted"
                    else -> "untrusted"
                },
                "packageName" to packageName,
                "versionCode" to packageInfo.longVersionCode,
                "versionName" to packageInfo.versionName,
                "signerSha256" to signerDigests.singleOrNull(),
                "signerSha256All" to signerDigests,
                "signerPinConfigured" to pinConfigured,
                "trustedSigner" to trusted,
                "installedComponentsSha256" to apkDigest,
                "installerPackageName" to installer,
            )
        } catch (_: Exception) {
            mapOf(
                "status" to "unavailable",
                "packageName" to context.packageName,
                "versionCode" to 0L,
                "signerSha256" to null,
                "signerPinConfigured" to false,
                "trustedSigner" to false,
                "installedComponentsSha256" to null,
                "installerPackageName" to null,
            )
        }
    }

    private fun resolvePinResource(context: Context): Int {
        val id = context.resources.getIdentifier(PIN_RESOURCE, "string", context.packageName)
        if (id == 0) throw IllegalStateException("Trusted APK signer pin resource is missing.")
        return id
    }

    private fun installerPackage(context: Context, packageName: String): String? = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            context.packageManager.getInstallSourceInfo(packageName).installingPackageName
        } else {
            @Suppress("DEPRECATION")
            context.packageManager.getInstallerPackageName(packageName)
        }
    } catch (_: Exception) {
        null
    }

    private fun digestApkFiles(paths: List<String>): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(32 * 1024)
        paths.forEach { path ->
            val file = File(path)
            if (!file.isFile || !file.canRead()) throw SecurityException("Installed APK component is unavailable.")
            digest.update(file.name.toByteArray(Charsets.UTF_8))
            FileInputStream(file).use { input ->
                while (true) {
                    val read = input.read(buffer)
                    if (read < 0) break
                    digest.update(buffer, 0, read)
                }
            }
        }
        return digest.digest().toHex()
    }

    private fun ByteArray.toHex(): String = joinToString(separator = "") { byte -> "%02x".format(byte) }
}
