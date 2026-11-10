package com.example.linky

import android.app.ActivityManager
import android.app.PictureInPictureParams
import android.content.ClipData
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

object ExtractorProgress {
    @Volatile
    var channel: MethodChannel? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    @JvmStatic
    fun report(taskId: String, progress: Double) {
        val current = channel ?: return
        mainHandler.post {
            current.invokeMethod(
                "extractorProgress",
                mapOf("taskId" to taskId, "progress" to progress),
            )
        }
    }
}

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
                "shareFile" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("invalid_path", "A file path is required.", null)
                    } else {
                        try {
                            launchFileIntent(path, Intent.ACTION_SEND)
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("share_failed", error.message, null)
                        }
                    }
                }
                "openWithFile" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("invalid_path", "A file path is required.", null)
                    } else {
                        try {
                            launchFileIntent(path, Intent.ACTION_VIEW)
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("open_with_failed", error.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "linky/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getMemoryInfo" -> {
                        try {
                            val manager =
                                getSystemService(ACTIVITY_SERVICE) as ActivityManager
                            val info = ActivityManager.MemoryInfo()
                            manager.getMemoryInfo(info)
                            result.success(
                                mapOf(
                                    "availableBytes" to info.availMem,
                                    "totalBytes" to info.totalMem,
                                    "thresholdBytes" to info.threshold,
                                    "lowMemory" to info.lowMemory,
                                ),
                            )
                        } catch (error: Exception) {
                            result.error("memory_info_failed", error.message, null)
                        }
                    }
                    "getStorageInfo" -> {
                        try {
                            val stat = StatFs(filesDir.absolutePath)
                            result.success(
                                mapOf(
                                    "freeBytes" to stat.availableBytes,
                                    "totalBytes" to stat.totalBytes,
                                ),
                            )
                        } catch (error: Exception) {
                            result.error("storage_info_failed", error.message, null)
                        }
                    }
                    "getExternalDirs" -> {
                        try {
                            result.success(
                                getExternalFilesDirs(null)
                                    .filterNotNull()
                                    .map { it.absolutePath },
                            )
                        } catch (error: Exception) {
                            result.error("external_dirs_failed", error.message, null)
                        }
                    }
                    "saveToPublicDownloads" -> {
                        val path = call.argument<String>("path")
                        val displayName = call.argument<String>("displayName")
                        if (path == null || displayName == null) {
                            result.error(
                                "invalid_public_download",
                                "File path and display name are required.",
                                null,
                            )
                        } else {
                            try {
                                result.success(
                                    saveToPublicDownloads(File(path), displayName) != null,
                                )
                            } catch (error: Exception) {
                                result.error(
                                    "public_download_failed",
                                    error.message,
                                    null,
                                )
                            }
                        }
                    }
                    "openFolder" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("invalid_path", "A folder path is required.", null)
                        } else {
                            try {
                                val directory = File(path)
                                if (!directory.exists()) directory.mkdirs()
                                val uri = FileProvider.getUriForFile(
                                    this,
                                    "$packageName.fileprovider",
                                    directory,
                                )
                                val intent = Intent(Intent.ACTION_VIEW).apply {
                                    setDataAndType(uri, "vnd.android.document/directory")
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                startActivity(intent)
                                result.success(true)
                            } catch (error: Exception) {
                                result.success(false)
                            }
                        }
                    }
                    "decryptAes128" -> {
                        val data = call.argument<ByteArray>("data")
                        val key = call.argument<ByteArray>("key")
                        val iv = call.argument<ByteArray>("iv")
                        if (data == null || key == null || iv == null) {
                            result.error(
                                "invalid_aes_input",
                                "Encrypted data, key, and IV are required.",
                                null,
                            )
                        } else {
                            try {
                                val cipher = Cipher.getInstance("AES/CBC/PKCS5Padding")
                                cipher.init(
                                    Cipher.DECRYPT_MODE,
                                    SecretKeySpec(key, "AES"),
                                    IvParameterSpec(iv),
                                )
                                result.success(cipher.doFinal(data))
                            } catch (error: Exception) {
                                try {
                                    val cipher = Cipher.getInstance("AES/CBC/NoPadding")
                                    cipher.init(
                                        Cipher.DECRYPT_MODE,
                                        SecretKeySpec(key, "AES"),
                                        IvParameterSpec(iv),
                                    )
                                    result.success(cipher.doFinal(data))
                                } catch (fallback: Exception) {
                                    result.error(
                                        "decrypt_failed",
                                        fallback.message ?: "AES-128 decryption failed.",
                                        null,
                                    )
                                }
                            }
                        }
                    }
                    "remuxMedia" -> {
                        val inputPath = call.argument<String>("inputPath")
                        val outputPath = call.argument<String>("outputPath")
                        if (inputPath == null || outputPath == null) {
                            result.error(
                                "invalid_remux_input",
                                "Input and output paths are required.",
                                null,
                            )
                        } else {
                            try {
                                MediaMuxerHelper.remux(inputPath, outputPath)
                                result.success(outputPath)
                            } catch (error: Exception) {
                                result.error(
                                    "remux_failed",
                                    error.message ?: "The file could not be remuxed.",
                                    null,
                                )
                            }
                        }
                    }
                    "extractAudio" -> {
                        val inputPath = call.argument<String>("inputPath")
                        val outputPath = call.argument<String>("outputPath")
                        if (inputPath == null || outputPath == null) {
                            result.error(
                                "invalid_audio_input",
                                "Input and output paths are required.",
                                null,
                            )
                        } else {
                            try {
                                MediaMuxerHelper.extractAudio(inputPath, outputPath)
                                result.success(outputPath)
                            } catch (error: Exception) {
                                result.error(
                                    "extract_audio_failed",
                                    error.message ?: "The audio track could not be extracted.",
                                    null,
                                )
                            }
                        }
                    }
                    "muxMedia" -> {
                        val videoPath = call.argument<String>("videoPath")
                        val audioPath = call.argument<String>("audioPath")
                        val outputPath = call.argument<String>("outputPath")
                        if (videoPath == null || audioPath == null || outputPath == null) {
                            result.error(
                                "invalid_mux_input",
                                "Video, audio, and output paths are required.",
                                null,
                            )
                        } else {
                            try {
                                MediaMuxerHelper.mux(videoPath, audioPath, outputPath)
                                result.success(outputPath)
                            } catch (error: Exception) {
                                result.error(
                                    "mux_failed",
                                    error.message ?: "The tracks could not be merged.",
                                    null,
                                )
                            }
                        }
                    }
                    "enterPip" -> {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                            result.success(false)
                        } else {
                            try {
                                val params = PictureInPictureParams.Builder().build()
                                result.success(enterPictureInPictureMode(params))
                            } catch (error: Exception) {
                                result.error(
                                    "pip_failed",
                                    error.message ?: "Picture-in-picture failed.",
                                    null,
                                )
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        val extractorChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "linky/extractor")
        ExtractorProgress.channel = extractorChannel
        extractorChannel
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
                val taskId = call.argument<String>("taskId") ?: ""
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
                                taskId,
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

    private fun launchFileIntent(path: String, action: String) {
        val file = File(path)
        if (!file.isFile) {
            throw IllegalArgumentException("The selected file no longer exists.")
        }
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        val extension = file.extension.lowercase()
        val mimeType = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
            ?: "application/octet-stream"
        val intent = Intent(action).apply {
            if (action == Intent.ACTION_SEND) {
                type = mimeType
                putExtra(Intent.EXTRA_STREAM, uri)
                clipData = ClipData.newRawUri(file.name, uri)
            } else {
                setDataAndType(uri, mimeType)
            }
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            if (action == Intent.ACTION_VIEW) {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        }
        startActivity(
            Intent.createChooser(
                intent,
                if (action == Intent.ACTION_SEND) "Share file" else "Open with",
            ),
        )
    }

    private fun saveToPublicDownloads(file: File, displayName: String): Uri? {
        if (!file.isFile) throw IllegalArgumentException("The file no longer exists.")
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val extension = file.extension.lowercase()
        val mimeType = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
            ?: "application/octet-stream"
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, "Download/Linky")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val collection =
            MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val resolver = contentResolver
        val destination = resolver.insert(collection, values)
            ?: throw IllegalStateException("Android could not add the file to Downloads.")
        try {
            val output = resolver.openOutputStream(destination)
                ?: throw IllegalStateException("Android could not open the Downloads file.")
            file.inputStream().use { input -> output.use { input.copyTo(it) } }
            resolver.update(
                destination,
                ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) },
                null,
                null,
            )
            return destination
        } catch (error: Exception) {
            resolver.delete(destination, null, null)
            throw error
        }
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
