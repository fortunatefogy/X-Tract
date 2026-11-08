package com.example.linky

import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var pendingSharedText: String? = null
    private var shareChannel: MethodChannel? = null
    private val extractorExecutor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingSharedText = sharedText(intent)
        shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "linky/share_intent")
        shareChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialSharedText" -> {
                    result.success(pendingSharedText)
                    pendingSharedText = null
                }
                "saveToGallery" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("invalid_path", "A file path is required.", null)
                    } else {
                        try {
                            result.success(saveToGallery(File(path)).toString())
                        } catch (error: Exception) {
                            result.error("gallery_save_failed", error.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "linky/extractor")
            .setMethodCallHandler { call, result ->
                if (call.method != "extractWithYtDlp" &&
                    call.method != "downloadWithYtDlp") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val url = call.argument<String>("url")
                if (url.isNullOrBlank()) {
                    result.error("invalid_url", "A media page URL is required.", null)
                    return@setMethodCallHandler
                }
                val cookieText = call.argument<String>("cookieText") ?: ""
                val formatId = call.argument<String>("formatId")
                val outputDirectory = call.argument<String>("outputDirectory")
                val audioFormatId = call.argument<String>("audioFormatId") ?: ""
                val videoUrl = call.argument<String>("videoUrl") ?: ""
                val audioUrl = call.argument<String>("audioUrl") ?: ""
                val headers = call.argument<String>("headers") ?: ""
                val outputName = call.argument<String>("outputName") ?: ""
                val videoMimeType = call.argument<String>("videoMimeType") ?: ""
                val audioMimeType = call.argument<String>("audioMimeType") ?: ""
                if (call.method == "downloadWithYtDlp" &&
                    (formatId.isNullOrBlank() || outputDirectory.isNullOrBlank())) {
                    result.error("invalid_download", "The selected media format or download folder is missing.", null)
                    return@setMethodCallHandler
                }
                extractorExecutor.execute {
                    try {
                        if (!Python.isStarted()) {
                            Python.start(AndroidPlatform(applicationContext))
                        }
                        val module = Python.getInstance().getModule("linky_ytdlp")
                        val output = if (call.method == "downloadWithYtDlp") {
                            module.callAttr(
                                "download",
                                url,
                                formatId,
                                outputDirectory,
                                cookieText,
                                audioFormatId,
                                videoUrl,
                                audioUrl,
                                headers,
                                outputName,
                                videoMimeType,
                                audioMimeType,
                            ).toString()
                        } else {
                            module.callAttr("extract", url, cookieText).toString()
                        }
                        runOnUiThread { result.success(output) }
                    } catch (error: Exception) {
                        runOnUiThread {
                            result.error(
                                if (call.method == "downloadWithYtDlp") "download_failed" else "extraction_failed",
                                error.message ?: "On-device yt-dlp request failed.",
                                null,
                            )
                        }
                    }
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        pendingSharedText = sharedText(intent)
        pendingSharedText?.let { shareChannel?.invokeMethod("sharedText", it) }
    }

    private fun sharedText(intent: Intent?): String? {
        val text = intent?.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
        return text?.takeIf { it.isNotBlank() } ?: intent?.data?.toString()
    }

    private fun saveToGallery(file: File): Uri {
        if (!file.isFile) throw IllegalArgumentException("The downloaded file no longer exists.")
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            throw UnsupportedOperationException("Gallery saving requires Android 10 or later.")
        }

        val extension = file.extension.lowercase()
        val mimeType = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
            ?: when (extension) {
                "avif" -> "image/avif"
                "m4v" -> "video/x-m4v"
                "mov" -> "video/quicktime"
                "3gp" -> "video/3gpp"
                else -> throw IllegalArgumentException("This file format cannot be saved to Gallery.")
            }
        val isVideo = mimeType.startsWith("video/")
        if (!isVideo && !mimeType.startsWith("image/")) {
            throw IllegalArgumentException("Only image and video files can be saved to Gallery.")
        }

        val collection = if (isVideo) {
            MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        } else {
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        }
        val relativePath = if (isVideo) "Movies/Linky" else "Pictures/Linky"
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, file.name)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val resolver = contentResolver
        val destination = resolver.insert(collection, values)
            ?: throw IllegalStateException("Android could not add the file to Gallery.")

        try {
            val output = resolver.openOutputStream(destination)
                ?: throw IllegalStateException("Android could not open the Gallery file.")
            file.inputStream().use { input -> output.use { input.copyTo(it) } }
            val publishedValues = ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }
            resolver.update(destination, publishedValues, null, null)
            return destination
        } catch (error: Exception) {
            resolver.delete(destination, null, null)
            throw error
        }
    }
}
