package com.example.linky

import android.app.ActivityManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.content.ClipData
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import androidx.core.app.NotificationCompat
import androidx.core.content.FileProvider
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
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

object LinkyEngine {
    const val ID = "linky"
}

abstract class LinkyFlutterActivity : FlutterActivity() {
    private var pendingSharedText: String? = null
    private var pendingBrowserUrl: String? = null
    private var shareChannel: MethodChannel? = null
    private val extractorExecutor = Executors.newSingleThreadExecutor()

    protected open val shareModeName: String get() = "main"
    protected open val supportsShare: Boolean get() = false

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun provideFlutterEngine(context: Context): FlutterEngine {
        val cache = FlutterEngineCache.getInstance()
        cache.get(LinkyEngine.ID)?.let { return it }
        val engine = FlutterEngine(context)
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault(),
            listOf(shareModeName, sharedText(intent) ?: ""),
        )
        cache.put(LinkyEngine.ID, engine)
        return engine
    }

    protected open fun announceMode() {
        shareChannel?.invokeMethod("shareModeChanged", shareModeName == "share")
    }

    protected open fun onShareReady() {}

    protected fun announceHidden(hidden: Boolean) {
        shareChannel?.invokeMethod("appHidden", hidden)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingSharedText = sharedText(intent)
        pendingBrowserUrl = intent?.getStringExtra("browser_url")
        intent?.removeExtra("browser_url")
        shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "linky/share_intent")
        shareChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getLaunchMode" -> {
                    result.success(shareModeName)
                }
                "minimizeSharePopup" -> {
                    moveTaskToBack(true)
                    result.success(true)
                }
                "shareReady" -> {
                    onShareReady()
                    result.success(true)
                }
                "closeSharePopup" -> {
                    result.success(true)
                    finish()
                }
                "getInitialSharedText" -> {
                    result.success(pendingSharedText)
                    pendingSharedText = null
                }
                "openInBrowser" -> {
                    val url = call.argument<String>("url")
                    if (url.isNullOrBlank()) {
                        result.error("invalid_url", "A page URL is required.", null)
                    } else if (supportsShare) {
                        startActivity(
                            Intent(this, MainActivity::class.java).apply {
                                addFlags(
                                    Intent.FLAG_ACTIVITY_NEW_TASK or
                                        Intent.FLAG_ACTIVITY_SINGLE_TOP,
                                )
                                putExtra("browser_url", url)
                            },
                        )
                        result.success(true)
                        finish()
                    } else {
                        shareChannel?.invokeMethod("openBrowser", url)
                        result.success(true)
                    }
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
                "shareFiles" -> {
                    val paths = call.argument<List<String>>("paths")
                    if (paths.isNullOrEmpty()) {
                        result.error("invalid_path", "At least one file path is required.", null)
                    } else {
                        try {
                            launchFilesIntent(paths)
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "linky/notifications")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "downloadProgress" -> {
                            val taskId = call.argument<String>("taskId")
                            if (taskId.isNullOrBlank()) {
                                result.error(
                                    "invalid_task",
                                    "A download task id is required.",
                                    null,
                                )
                            } else {
                                showDownloadProgress(
                                    taskId = taskId,
                                    title = call.argument<String>("title")
                                        ?: "Media download",
                                    progress = call.argument<Int>("progress") ?: 0,
                                    indeterminate =
                                        call.argument<Boolean>("indeterminate")
                                            ?: false,
                                )
                                result.success(true)
                            }
                        }
                        "downloadComplete" -> {
                            showDownloadComplete(
                                title = call.argument<String>("title")
                                    ?: "Media download",
                                taskId = call.argument<String>("taskId"),
                            )
                            result.success(true)
                        }
                        "dismissNotification" -> {
                            val taskId = call.argument<String>("taskId")
                            if (!taskId.isNullOrBlank()) dismissNotification(taskId)
                            result.success(true)
                        }
                        "startDownloadService" -> {
                            DownloadForegroundService.start(this)
                            result.success(true)
                        }
                        "stopDownloadService" -> {
                            DownloadForegroundService.stop(this)
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("notification_failed", error.message, null)
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
        announceMode()
        if (supportsShare) {
            pendingSharedText?.let { shareChannel?.invokeMethod("sharedText", it) }
        } else {
            pendingBrowserUrl?.let { shareChannel?.invokeMethod("openBrowser", it) }
            pendingBrowserUrl = null
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (supportsShare && isShareIntent(intent)) {
            pendingSharedText = sharedText(intent)
            announceMode()
            pendingSharedText?.let { shareChannel?.invokeMethod("sharedText", it) }
            return
        }
        announceMode()
        val browserUrl = intent.getStringExtra("browser_url")
        if (browserUrl != null) {
            intent.removeExtra("browser_url")
            shareChannel?.invokeMethod("openBrowser", browserUrl)
            return
        }
        if (intent.getBooleanExtra("open_downloads", false)) {
            shareChannel?.invokeMethod("openDownloads", true)
        }
    }

    protected fun isShareIntent(intent: Intent?): Boolean {
        if (intent == null) return false
        return intent.action == Intent.ACTION_SEND ||
            intent.action == Intent.ACTION_SEND_MULTIPLE ||
            (intent.action == Intent.ACTION_VIEW && intent.data != null)
    }

    private fun sharedText(intent: Intent?): String? {
        val text = intent?.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
        return text?.takeIf { it.isNotBlank() } ?: intent?.data?.toString()
    }

    private fun showDownloadProgress(
        taskId: String,
        title: String,
        progress: Int,
        indeterminate: Boolean,
    ) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channelId = "linky_download_progress"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    channelId,
                    "Download progress",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    setSound(null, null)
                    enableVibration(false)
                },
            )
        }
        val builder = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(title)
            .setContentText(if (indeterminate) "Downloading…" else "$progress%")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(downloadsPendingIntent())
        if (indeterminate) {
            builder.setProgress(0, 0, true)
        } else {
            builder.setProgress(100, progress.coerceIn(0, 100), false)
        }
        manager.notify(notificationId(taskId), builder.build())
    }

    private fun showDownloadComplete(title: String, taskId: String?) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channelId = "linky_downloads"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    channelId,
                    "Downloads",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ),
            )
        }
        val notification = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle("Download complete")
            .setContentText(title)
            .setAutoCancel(true)
            .setContentIntent(downloadsPendingIntent())
            .build()
        manager.notify(
            if (taskId.isNullOrBlank()) title.hashCode() else notificationId(taskId),
            notification,
        )
    }

    private fun dismissNotification(taskId: String) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(notificationId(taskId))
    }

    private fun notificationId(taskId: String): Int = taskId.hashCode()

    private fun downloadsPendingIntent(): PendingIntent {
        val openIntent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)
            putExtra("open_downloads", true)
        }
        return PendingIntent.getActivity(
            this,
            0,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
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

    private fun launchFilesIntent(paths: List<String>) {
        val files = paths.map { File(it) }
        if (files.any { !it.isFile }) {
            throw IllegalArgumentException("One or more selected files no longer exist.")
        }
        val uris = ArrayList<Uri>(files.size)
        val mimes = ArrayList<String>(files.size)
        for (file in files) {
            uris.add(FileProvider.getUriForFile(this, "$packageName.fileprovider", file))
            val extension = file.extension.lowercase()
            mimes.add(
                MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
                    ?: "application/octet-stream",
            )
        }
        val first = mimes.first()
        val type = when {
            mimes.all { it == first } -> first
            mimes.all { it.substringBefore('/') == first.substringBefore('/') } ->
                "${first.substringBefore('/')}/*"
            else -> "*/*"
        }
        val clip = ClipData.newRawUri(files.first().name, uris.first())
        for (index in 1 until uris.size) {
            clip.addItem(ClipData.Item(uris[index]))
        }
        val intent = Intent(Intent.ACTION_SEND_MULTIPLE).apply {
            this.type = type
            putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
            clipData = clip
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(intent, "Share files"))
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
