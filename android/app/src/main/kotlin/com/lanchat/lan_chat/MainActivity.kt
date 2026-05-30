package com.lanchat.lan_chat

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lanchat/open_file").setMethodCallHandler { call, result ->
            if (call.method != "open") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val path = call.argument<String>("path")
            if (path.isNullOrBlank()) {
                result.error("bad_path", "文件路径无效", null)
                return@setMethodCallHandler
            }
            openWithSystem(path, result)
        }
    }

    private fun openWithSystem(path: String, result: MethodChannel.Result) {
        val file = File(path)
        if (!file.exists()) {
            result.error("missing", "文件不存在", null)
            return
        }
        val mime = mimeType(file)
        val uri = try {
            FileProvider.getUriForFile(this, "$packageName.lanchat_file_provider", file)
        } catch (error: Exception) {
            result.error("provider_failed", "FileProvider 无法处理路径：$path · ${error.message}", null)
            return
        }
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mime)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val candidates = packageManager.queryIntentActivities(intent, 0)
        for (candidate in candidates) {
            grantUriPermission(candidate.activityInfo.packageName, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        try {
            startActivity(Intent.createChooser(intent, "打开文件"))
            result.success(true)
        } catch (_: ActivityNotFoundException) {
            result.error("no_app", "没有可打开此文件的应用", null)
        } catch (error: Exception) {
            result.error("open_failed", error.message ?: "打开失败", null)
        }
    }

    private fun mimeType(file: File): String {
        val extension = file.extension.lowercase()
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension) ?: "*/*"
    }
}
