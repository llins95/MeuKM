package br.com.meukm

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            APP_UPDATE_CHANNEL_NAME,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "canRequestPackageInstalls" -> result.success(canRequestPackageInstalls())
                "openInstallPermissionSettings" -> {
                    openInstallPermissionSettings()
                    result.success(null)
                }
                "installApk" -> {
                    val path = call.argument<String>("path")
                    try {
                        result.success(path != null && openApkInstaller(path))
                    } catch (error: Exception) {
                        result.error("INSTALLER_ERROR", error.message ?: "Não foi possível abrir o instalador.", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun canRequestPackageInstalls(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packageManager.canRequestPackageInstalls()
    }

    private fun openInstallPermissionSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        startActivity(
            Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName"),
            ),
        )
    }

    private fun openApkInstaller(path: String): Boolean {
        if (!canRequestPackageInstalls()) {
            openInstallPermissionSettings()
            return false
        }

        val updateDirectory = File(cacheDir, "updates").canonicalFile
        val apk = File(path).canonicalFile
        require(apk.isFile && apk.parentFile == updateDirectory) {
            "O APK não pertence ao diretório seguro de atualizações."
        }

        val contentUri = FileProvider.getUriForFile(this, "$packageName.updates", apk)
        val installIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(contentUri, APK_MIME_TYPE)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(installIntent)
        return true
    }

    companion object {
        private const val APP_UPDATE_CHANNEL_NAME = "br.com.meukm/app_updates"
        private const val APK_MIME_TYPE = "application/vnd.android.package-archive"
    }
}
