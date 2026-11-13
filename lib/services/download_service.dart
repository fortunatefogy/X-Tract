import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/media_item.dart';
import 'chunked_downloader.dart';
import 'dash_downloader.dart';
import 'device_resources.dart';
import 'hls_downloader.dart';
import 'media_downloader.dart';
import 'notification_service.dart';
import 'platform_extractor.dart';
import 'post_processor.dart';
import 'settings_service.dart';
import 'storage_service.dart';

enum DownloadState {
  queued,
  running,
  paused,
  retrying,
  complete,
  failed,
  canceled
}

extension DownloadStateIsFinal on DownloadState {
  bool get isFinal =>
      this == DownloadState.complete ||
      this == DownloadState.failed ||
      this == DownloadState.canceled;
  bool get isActive => !isFinal;
}

class DownloadRecord {
  const DownloadRecord({
    required this.taskId,
    required this.url,
    required this.filename,
    required this.title,
    required this.type,
    required this.createdAt,
    this.state = DownloadState.queued,
    this.progress = 0,
    this.expectedBytes = -1,
    this.error,
    this.filePath,
    this.sourcePage,
    this.formatId,
    this.audioFormatId,
    this.audioUrl,
    this.audioMimeType,
    this.mimeType,
    this.requestHeaders = const {},
    this.fallbackAttempted = false,
    this.requiresExtractor = false,
    this.isLive = false,
  });

  final String taskId;
  final String url;
  final String filename;
  final String title;
  final String type;
  final DateTime createdAt;
  final DownloadState state;
  final double progress;
  final int expectedBytes;
  final String? error;
  final String? filePath;
  final String? sourcePage;
  final String? formatId;
  final String? audioFormatId;
  final String? audioUrl;
  final String? audioMimeType;
  final String? mimeType;
  final Map<String, String> requestHeaders;
  final bool fallbackAttempted;
  final bool requiresExtractor;
  final bool isLive;

  DownloadRecord copyWith({
    String? taskId,
    String? filename,
    String? title,
    DownloadState? state,
    double? progress,
    int? expectedBytes,
    Object? error = _unset,
    Object? filePath = _unset,
    Map<String, String>? requestHeaders,
    bool? fallbackAttempted,
    bool? isLive,
  }) =>
      DownloadRecord(
        taskId: taskId ?? this.taskId,
        url: url,
        filename: filename ?? this.filename,
        title: title ?? this.title,
        type: type,
        createdAt: createdAt,
        state: state ?? this.state,
        progress: progress ?? this.progress,
        expectedBytes: expectedBytes ?? this.expectedBytes,
        error: identical(error, _unset) ? this.error : error as String?,
        filePath:
            identical(filePath, _unset) ? this.filePath : filePath as String?,
        sourcePage: sourcePage,
        formatId: formatId,
        audioFormatId: audioFormatId,
        audioUrl: audioUrl,
        audioMimeType: audioMimeType,
        mimeType: mimeType,
        requestHeaders: requestHeaders ?? this.requestHeaders,
        fallbackAttempted: fallbackAttempted ?? this.fallbackAttempted,
        requiresExtractor: requiresExtractor,
        isLive: isLive ?? this.isLive,
      );

  MediaItem toMediaItem() => MediaItem(
        url: url,
        type: type,
        title: title,
        mimeType: mimeType,
        sourcePage: sourcePage,
        formatId: formatId,
        audioFormatId: audioFormatId,
        audioUrl: audioUrl,
        audioMimeType: audioMimeType,
        requestHeaders: requestHeaders,
        requiresExtractor: requiresExtractor,
      );

  Map<String, dynamic> toJson() => {
        'taskId': taskId,
        'url': url,
        'filename': filename,
        'title': title,
        'type': type,
        'createdAt': createdAt.toIso8601String(),
        'state': state.name,
        'progress': progress,
        'expectedBytes': expectedBytes,
        'error': error,
        'filePath': filePath,
        'sourcePage': sourcePage,
        'formatId': formatId,
        'audioFormatId': audioFormatId,
        'audioUrl': audioUrl,
        'audioMimeType': audioMimeType,
        'mimeType': mimeType,
        'requestHeaders': {
          for (final entry in requestHeaders.entries)
            if (entry.key.toLowerCase() != 'cookie') entry.key: entry.value,
        },
        'fallbackAttempted': fallbackAttempted,
        'requiresExtractor': requiresExtractor,
        'isLive': isLive,
      };

  factory DownloadRecord.fromJson(Map<String, dynamic> json) => DownloadRecord(
        taskId: json['taskId'] as String? ?? '',
        url: json['url'] as String? ?? '',
        filename: json['filename'] as String? ?? 'media',
        title: json['title'] as String? ?? 'Media',
        type: json['type'] as String? ?? 'unknown',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        state: DownloadState.values.firstWhere(
          (value) => value.name == json['state'],
          orElse: () => DownloadState.queued,
        ),
        progress: (json['progress'] as num?)?.toDouble() ?? 0,
        expectedBytes: (json['expectedBytes'] as num?)?.toInt() ?? -1,
        error: json['error'] as String?,
        filePath: json['filePath'] as String?,
        sourcePage: json['sourcePage'] as String?,
        formatId: json['formatId'] as String?,
        audioFormatId: json['audioFormatId'] as String?,
        audioUrl: json['audioUrl'] as String?,
        audioMimeType: json['audioMimeType'] as String?,
        mimeType: json['mimeType'] as String?,
        requestHeaders: (json['requestHeaders'] as Map<String, dynamic>? ?? {})
            .map((key, value) => MapEntry(key, value.toString())),
        fallbackAttempted: json['fallbackAttempted'] as bool? ?? false,
        requiresExtractor: json['requiresExtractor'] as bool? ?? false,
        isLive: json['isLive'] as bool? ?? false,
      );
}

const _unset = Object();

class DownloadService extends ChangeNotifier {
  DownloadService._();

  static final DownloadService instance = DownloadService._();

  static const _group = 'linky';
  static const _folder = 'LinkyDownloads';
  static final _mediaExtension = RegExp(
    r'\.(mp4|m4v|webm|mov|mkv|avi|flv|3gp|mp3|m4a|aac|ogg|oga|opus|wav|flac|'
    r'jpg|jpeg|png|gif|webp|avif|svg|bmp|tiff|heic|heif|pdf|docx?|xlsx?|'
    r'pptx?|txt|rtf|csv|epub|vtt|srt|ttml)$',
    caseSensitive: false,
  );

  final _records = <String, DownloadRecord>{};
  final _pending = <String>[];
  final _chunked = <String, _ChunkHandle>{};
  final _runningExtractors = <String>{};
  final _random = Random();
  final _postProcessor = PostProcessor();
  StreamSubscription<TaskUpdate>? _updates;
  Timer? _persistTimer;
  Timer? _resourceRetry;
  final _resourceBlocked = <String>{};
  int _starting = 0;
  bool _initialized = false;
  bool _available = false;
  bool _foregroundStarted = false;
  Future<void> _foregroundOp = Future<void>.value();
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);

  bool get isAvailable => _available;

  List<DownloadRecord> get records {
    final list = _records.values.toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  List<DownloadRecord> get active =>
      records.where((record) => record.state.isActive).toList();

  List<DownloadRecord> get failures => records
      .where((record) =>
          record.state == DownloadState.failed ||
          record.state == DownloadState.canceled)
      .toList();

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await _loadPersisted();
    try {
      final downloader = FileDownloader();
      await downloader.ready;
      await downloader.configure(
        globalConfig: (Config.useCacheDir, Config.never),
        androidConfig: (Config.runInForeground, Config.always),
      );
      downloader.configureNotificationForGroup(
        _group,
        running: const TaskNotification(
          'Downloading',
          '{displayName} · {progress}',
        ),
        complete: const TaskNotification('Download complete', '{filename}'),
        error: const TaskNotification('Download failed', '{filename}'),
        paused: const TaskNotification('Download paused', '{filename}'),
        canceled: const TaskNotification('Download canceled', '{filename}'),
        progressBar: true,
      );
      _updates = downloader.updates.listen(_onUpdate);
      await downloader.trackTasks();
      await downloader.resumeFromBackground();
      _available = true;
      _notify(force: true);
      Timer(const Duration(seconds: 3), _reconcile);
    } catch (_) {
      _available = false;
    }
    _resumePending();
  }

  Future<DownloadRecord> enqueue(
    MediaItem item, {
    Map<String, String> extraHeaders = const {},
  }) async {
    await init();
    if (!item.isDownloadable) {
      throw StateError('This item does not expose a downloadable media file.');
    }
    await _ensureNotificationPermission();

    final headers = <String, String>{
      for (final entry in item.requestHeaders.entries) entry.key: entry.value,
      for (final entry in extraHeaders.entries) entry.key: entry.value,
    };
    if (!headers.keys.any((key) => key.toLowerCase() == 'user-agent')) {
      headers['User-Agent'] = 'Linky/0.1 (Android)';
    }

    final filename = await _uniqueFilename(item);
    final taskId =
        '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 20)}';
    final title = _displayTitle(item);
    final record = DownloadRecord(
      taskId: taskId,
      url: item.url,
      filename: filename,
      title: title,
      type: item.type,
      createdAt: DateTime.now(),
      expectedBytes: item.size ?? -1,
      sourcePage: item.sourcePage,
      formatId: item.formatId,
      audioFormatId: item.audioFormatId,
      audioUrl: item.audioUrl,
      audioMimeType: item.audioMimeType,
      mimeType: item.mimeType,
      requestHeaders: headers,
      requiresExtractor: item.requiresExtractor,
    );
    _records[taskId] = record;
    _notify(force: true);

    if (_isChunked(record) || _isExtractor(record)) {
      _pending.add(taskId);
      _schedulePersist();
      _pumpQueue();
      return _records[taskId] ?? record;
    }

    if (!_available) {
      _records.remove(taskId);
      throw StateError('Background downloads are unavailable on this device.');
    }
    final task = _taskFromRecord(record);
    final queued = await FileDownloader().enqueue(task);
    if (!queued) {
      _records[taskId] = record.copyWith(
        state: DownloadState.failed,
        error: 'The download could not be queued.',
      );
      _schedulePersist();
      _notify(force: true);
      throw StateError('The download could not be queued.');
    }
    _schedulePersist();
    return _records[taskId] ?? record;
  }

  Future<void> cancel(DownloadRecord record) async {
    final id = record.taskId;
    _pending.remove(id);
    _resourceBlocked.remove(id);
    final handle = _chunked[id];
    if (handle != null) {
      handle.stopRequested = true;
      handle.canceled = true;
    }
    _records[id] = record.copyWith(
      state: DownloadState.canceled,
      error: 'Download canceled.',
    );
    _notify(force: true);
    if (handle == null) {
      await FileDownloader().cancelTaskWithId(id);
    }
    _schedulePersist();
    _dismissNotification(id);
  }

  Future<void> pause(DownloadRecord record) async {
    final id = record.taskId;
    final wasQueued = _pending.remove(id);
    final wasBlocked = _resourceBlocked.remove(id);
    if (wasQueued || wasBlocked) {
      _records[id] = record.copyWith(
        state: DownloadState.paused,
        error: 'Paused. Tap resume to continue.',
      );
      _notify(force: true);
      _schedulePersist();
      _dismissNotification(id);
      return;
    }
    final handle = _chunked[id];
    if (handle != null) {
      handle.paused = true;
      handle.stopRequested = true;
      _records[id] = record.copyWith(
        state: DownloadState.paused,
        error: 'Paused. Tap resume to continue.',
      );
      _notify(force: true);
      _schedulePersist();
      _dismissNotification(id);
      return;
    }
    await FileDownloader().pause(_taskFromRecord(record));
  }

  Future<void> resume(DownloadRecord record) async {
    final id = record.taskId;
    if (_isChunked(record) || _isExtractor(record)) {
      if (_pending.contains(id) || _chunked.containsKey(id)) return;
      _resourceBlocked.remove(id);
      _records[id] = record.copyWith(
        state: DownloadState.queued,
        error: null,
      );
      _pending.add(id);
      _notify(force: true);
      _schedulePersist();
      _pumpQueue();
      return;
    }
    await FileDownloader().resume(_taskFromRecord(record));
  }

  Future<void> retry(DownloadRecord record) async {
    final media = record.toMediaItem();
    _records.remove(record.taskId);
    _pending.remove(record.taskId);
    _resourceBlocked.remove(record.taskId);
    _notify(force: true);
    _schedulePersist();
    await _deleteParts(record.taskId);
    await enqueue(media, extraHeaders: record.requestHeaders);
  }

  Future<void> pauseAll() async {
    final running = records
        .where((record) =>
            record.state == DownloadState.running ||
            record.state == DownloadState.queued ||
            record.state == DownloadState.retrying)
        .toList(growable: false);
    for (final record in running) {
      try {
        await pause(record);
      } catch (_) {}
    }
  }

  Future<void> resumeAll() async {
    final paused = records
        .where((record) => record.state == DownloadState.paused)
        .toList(growable: false);
    for (final record in paused) {
      try {
        await resume(record);
      } catch (_) {}
    }
  }

  Future<void> retryAll() async {
    final failed = records
        .where((record) =>
            record.state == DownloadState.failed ||
            record.state == DownloadState.canceled)
        .toList(growable: false);
    for (final record in failed) {
      try {
        await retry(record);
      } catch (_) {}
    }
  }

  Future<void> _deleteParts(String taskId) async {
    final directory = await _directory();
    for (final name in ['.linky-parts', '.linky-hls', '.linky-dash']) {
      try {
        await Directory(
          '${directory.path}${Platform.pathSeparator}$name'
          '${Platform.pathSeparator}$taskId',
        ).delete(recursive: true);
      } catch (_) {}
    }
  }

  void dismiss(DownloadRecord record) {
    if (!record.state.isFinal) return;
    _records.remove(record.taskId);
    _notify(force: true);
    _schedulePersist();
  }

  void clearFinished() {
    _records.removeWhere((_, record) => record.state.isFinal);
    _notify(force: true);
    _schedulePersist();
  }

  String exportQueuedTasks() => jsonEncode([
        for (final record in records)
          if (!record.state.isFinal) record.toJson(),
      ]);

  Future<int> importQueuedTasks(String raw) async {
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('The task list must be a JSON array.');
    }
    final activeKeys = _records.values
        .where((record) => !record.state.isFinal)
        .map((record) => '${record.url}|${record.formatId ?? ''}')
        .toSet();
    var imported = 0;
    for (final entry in decoded) {
      if (entry is! Map) continue;
      final item = _mediaItemFromImport(
        Map<String, dynamic>.from(entry),
      );
      if (item == null) continue;
      final key = '${item.url}|${item.formatId ?? ''}';
      if (!activeKeys.add(key)) continue;
      try {
        await enqueue(item);
        imported++;
      } catch (_) {}
    }
    return imported;
  }

  MediaItem? _mediaItemFromImport(Map<String, dynamic> json) {
    final url = json['url'] as String?;
    if (url == null || url.isEmpty) return null;
    final expected = (json['expectedBytes'] as num?)?.toInt() ?? -1;
    final headers = <String, String>{};
    final rawHeaders = json['requestHeaders'];
    if (rawHeaders is Map) {
      for (final entry in rawHeaders.entries) {
        headers[entry.key.toString()] = entry.value.toString();
      }
    }
    return MediaItem(
      url: url,
      type: json['type'] as String? ?? 'video',
      title: json['title'] as String?,
      mimeType: json['mimeType'] as String?,
      sourcePage: json['sourcePage'] as String?,
      size: expected > 0 ? expected : null,
      formatId: json['formatId'] as String?,
      audioFormatId: json['audioFormatId'] as String?,
      audioUrl: json['audioUrl'] as String?,
      audioMimeType: json['audioMimeType'] as String?,
      requestHeaders: headers,
      requiresExtractor: json['requiresExtractor'] as bool? ?? false,
    );
  }

  DownloadTask _taskFromRecord(DownloadRecord record) => DownloadTask(
        taskId: record.taskId,
        url: record.url,
        headers: record.requestHeaders,
        filename: record.filename,
        directory: _folder,
        baseDirectory: BaseDirectory.applicationDocuments,
        group: _group,
        updates: Updates.statusAndProgress,
        retries: 3,
        allowPause: true,
        displayName: record.title,
        metaData: jsonEncode({'title': record.title, 'type': record.type}),
      );

  void _onUpdate(TaskUpdate update) async {
    try {
      await _handleUpdate(update);
    } catch (_) {}
  }

  Future<void> _handleUpdate(TaskUpdate update) async {
    final task = update.task;
    if (task.group != _group) return;
    final record = _records[task.taskId];
    if (record == null) return;

    if (record.state.isFinal) return;

    if (update is TaskProgressUpdate) {
      _records[task.taskId] = record.copyWith(
        progress: update.progress.clamp(0.0, 1.0).toDouble(),
        expectedBytes: update.expectedFileSize >= 0
            ? update.expectedFileSize
            : record.expectedBytes,
      );
      _notify();
      return;
    }
    if (update is! TaskStatusUpdate) return;

    final state = _stateFor(update.status);
    var next = record.copyWith(
      state: state,
      progress: state == DownloadState.complete ? 1 : record.progress,
      error: _errorFor(update),
    );
    _records[task.taskId] = next;

    if (state == DownloadState.complete) {
      final resolved = next.filePath ?? (await _pathFor(next));
      final file = File(resolved);
      if (await file.exists()) {
        next = next.copyWith(filePath: file.path);
        _records[task.taskId] = next;
      }
    }
    _notify(force: true);
    _schedulePersist();

    if (state == DownloadState.failed &&
        !next.fallbackAttempted &&
        next.formatId != null &&
        next.sourcePage != null) {
      _enqueueExtractor(next);
    }
  }

  bool _isExtractor(DownloadRecord record) =>
      record.requiresExtractor &&
      record.formatId != null &&
      record.sourcePage != null;

  bool _isChunked(DownloadRecord record) =>
      !_isExtractor(record) &&
      (record.url.startsWith('http://') || record.url.startsWith('https://'));

  bool _isHls(DownloadRecord record) {
    final path = Uri.tryParse(record.url)?.path.toLowerCase() ?? '';
    final mime = record.mimeType?.toLowerCase() ?? '';
    return path.endsWith('.m3u8') ||
        path.endsWith('.m3u') ||
        mime.contains('mpegurl');
  }

  bool _isDash(DownloadRecord record) {
    final path = Uri.tryParse(record.url)?.path.toLowerCase() ?? '';
    final mime = record.mimeType?.toLowerCase() ?? '';
    return path.endsWith('.mpd') || mime.contains('dash+xml');
  }

  int get _activeDownloads =>
      _chunked.length + _runningExtractors.length + _starting;

  void _enqueueExtractor(DownloadRecord record) {
    final current = _records[record.taskId];
    if (current == null || current.fallbackAttempted) return;
    if (_pending.contains(record.taskId) ||
        _runningExtractors.contains(record.taskId)) {
      return;
    }
    _records[record.taskId] = current.copyWith(
      state: DownloadState.queued,
      error: null,
    );
    _pending.add(record.taskId);
    _notify(force: true);
    _schedulePersist();
    _pumpQueue();
  }

  void _resumePending() {
    for (final record in _records.values.toList()) {
      if (record.state == DownloadState.paused || record.state.isFinal) {
        continue;
      }
      if (!_isChunked(record) && !_isExtractor(record)) continue;
      if (_pending.contains(record.taskId) ||
          _chunked.containsKey(record.taskId) ||
          _runningExtractors.contains(record.taskId)) {
        continue;
      }
      _records[record.taskId] = record.copyWith(
        state: DownloadState.queued,
        error: null,
      );
      _pending.add(record.taskId);
    }
    _pumpQueue();
  }

  void _pumpQueue() {
    final limit =
        SettingsService.instance.maxSimultaneousDownloads.clamp(1, 16);
    while (_pending.isNotEmpty && _activeDownloads < limit) {
      final id = _pending.removeAt(0);
      final record = _records[id];
      if (record == null || record.state.isFinal) continue;
      _starting++;
      unawaited(_startQueued(record).whenComplete(() {
        _starting--;
        _pumpQueue();
      }));
    }
  }

  Future<void> _startQueued(DownloadRecord record) async {
    final id = record.taskId;
    final block = await _resourceBlock(record);
    if (block != null) {
      final current = _records[id];
      if (current == null || current.state.isFinal) return;
      _records[id] = current.copyWith(
        state: block.storage ? DownloadState.failed : DownloadState.queued,
        error: block.message,
      );
      _notify(force: true);
      _schedulePersist();
      if (!block.storage) _scheduleResourceRetry(id);
      return;
    }
    final current = _records[id];
    if (current == null ||
        current.state.isFinal ||
        current.state == DownloadState.paused) {
      return;
    }
    _resourceBlocked.remove(id);
    if (_isExtractor(current)) {
      _runningExtractors.add(id);
      _records[id] = current.copyWith(
        state: DownloadState.running,
        progress: 0,
        error: null,
      );
      _notify(force: true);
      _reportProgress(current, 0, indeterminate: true);
      unawaited(_runExtractor(current).whenComplete(() {
        _runningExtractors.remove(id);
        _notify(force: true);
        _schedulePersist();
        _pumpQueue();
      }));
    } else if (_isChunked(current)) {
      final handle = _ChunkHandle();
      _chunked[id] = handle;
      _records[id] = current.copyWith(
        state: DownloadState.running,
        progress: 0,
        error: null,
      );
      _notify(force: true);
      _reportProgress(current, 0, indeterminate: true);
      final task = _isHls(current)
          ? _runHls(current, handle)
          : _isDash(current)
              ? _runDash(current, handle)
              : _runChunked(current, handle);
      unawaited(task.whenComplete(() {
        _chunked.remove(id);
        _schedulePersist();
        _pumpQueue();
      }));
    }
  }

  Future<_ResourceBlock?> _resourceBlock(DownloadRecord record) async {
    final memory = await DeviceResources.instance.memoryInfo();
    if (memory != null && memory.availableBytes > 0) {
      final minimum =
          max(memory.thresholdBytes, 64 * 1024 * 1024) + 32 * 1024 * 1024;
      if (memory.lowMemory || memory.availableBytes < minimum) {
        return const _ResourceBlock(
          'Waiting for free memory before starting this download.',
          storage: false,
        );
      }
    }
    final storage = await DeviceResources.instance.storageInfo();
    if (storage != null && storage.freeBytes > 0) {
      final required = _requiredBytes(record);
      if (storage.freeBytes < required) {
        return _ResourceBlock(
          'Not enough free storage: ${_formatBytes(required)} needed, '
          '${_formatBytes(storage.freeBytes)} available.',
          storage: true,
        );
      }
    }
    return null;
  }

  int _requiredBytes(DownloadRecord record) {
    const margin = 32 * 1024 * 1024;
    if (record.expectedBytes > 0) {
      return record.expectedBytes * 2 + margin;
    }
    return 96 * 1024 * 1024;
  }

  void _scheduleResourceRetry(String id) {
    _resourceBlocked.add(id);
    if (_resourceRetry?.isActive == true) return;
    _resourceRetry = Timer(const Duration(seconds: 20), () {
      _resourceRetry = null;
      final blocked = _resourceBlocked.toList();
      _resourceBlocked.clear();
      for (final taskId in blocked) {
        final record = _records[taskId];
        if (record == null ||
            record.state.isFinal ||
            record.state == DownloadState.paused ||
            _pending.contains(taskId) ||
            _chunked.containsKey(taskId) ||
            _runningExtractors.contains(taskId)) {
          continue;
        }
        _pending.add(taskId);
      }
      _pumpQueue();
    });
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<void> _runHls(
    DownloadRecord record,
    _ChunkHandle handle,
  ) async {
    final id = record.taskId;
    try {
      final directory = await _directory();
      final destination = File(
        '${directory.path}${Platform.pathSeparator}${record.filename}',
      );
      final work = Directory(
        '${directory.path}${Platform.pathSeparator}.linky-hls'
        '${Platform.pathSeparator}$id',
      );
      final result = await HlsDownloader(
        workers: SettingsService.instance.downloadThreadCount,
      ).download(
        url: record.url,
        destination: destination,
        workDirectory: work,
        headers: record.requestHeaders,
        isCancelled: () => handle.stopRequested,
        audioOnly: SettingsService.instance.audioOnlyDownloads,
        onLiveDetected: () => _markLive(id),
        onProgress: (completed, total) {
          final current = _records[id];
          if (current == null) return;
          final ratio = total > 0
              ? (completed / total).clamp(0.0, 1.0).toDouble()
              : current.progress;
          _records[id] = current.copyWith(
            state: DownloadState.running,
            progress: ratio,
          );
          _reportProgress(current, ratio, indeterminate: total <= 0);
          _notify();
        },
      );
      final current = _records[id];
      if (current == null) return;
      if (current.state == DownloadState.canceled) {
        try {
          await result.file.delete();
        } catch (_) {}
        return;
      }
      // Always deliver HLS as an MP4 video file. TS captures are remuxed with
      // the native muxer; fragmented-MP4 captures already have the .mp4 name.
      var mediaFile = result.file;
      String? remuxWarning;
      final lowerMedia = mediaFile.path.toLowerCase();
      if (!lowerMedia.endsWith('.mp4') && !lowerMedia.endsWith('.m4a')) {
        final dot = mediaFile.path.lastIndexOf('.');
        final targetPath = dot > 0
            ? '${mediaFile.path.substring(0, dot)}.mp4'
            : '${mediaFile.path}.mp4';
        try {
          final remuxed = await DeviceResources.instance.remuxMedia(
            mediaFile.path,
            targetPath,
          );
          if (remuxed != null) {
            final remuxFile = File(remuxed);
            if (await remuxFile.exists() && await remuxFile.length() > 0) {
              try {
                await mediaFile.delete();
              } catch (_) {}
              mediaFile = remuxFile;
            }
          }
        } catch (_) {}
        if (!mediaFile.path.toLowerCase().endsWith('.mp4')) {
          remuxWarning =
              'Saved the HLS stream as-is because the MP4 remux failed.';
        }
      }
      final post = await _postProcess(
        record,
        mediaFile,
        result.warning ??
            remuxWarning ??
            (result.isLive ? 'Live recording saved.' : null),
      );
      _records[id] = current.copyWith(
        state: DownloadState.complete,
        progress: 1,
        expectedBytes: await post.$1.length(),
        filePath: post.$1.path,
        error: post.$2,
        isLive: result.isLive,
      );
      _notify(force: true);
      _schedulePersist();
      unawaited(
          NotificationService.downloadComplete(current.title, taskId: id));
    } on HlsCanceled {
      final current = _records[id];
      if (current != null) {
        _records[id] = current.copyWith(
          state:
              handle.canceled ? DownloadState.canceled : DownloadState.paused,
          error: handle.canceled
              ? 'Download canceled.'
              : 'Paused. Tap resume to continue.',
        );
      }
      if (handle.canceled) {
        final directory = await _directory();
        try {
          await Directory(
            '${directory.path}${Platform.pathSeparator}.linky-hls'
            '${Platform.pathSeparator}$id',
          ).delete(recursive: true);
        } catch (_) {}
      }
      _notify(force: true);
      _schedulePersist();
      _dismissNotification(id);
    } catch (error) {
      final current = _records[id];
      if (current != null) {
        _records[id] = current.copyWith(
          state: DownloadState.failed,
          error: 'Download failed: $error',
        );
      }
      _notify(force: true);
      _schedulePersist();
      _dismissNotification(id);
    }
  }

  Future<void> _runDash(
    DownloadRecord record,
    _ChunkHandle handle,
  ) async {
    final id = record.taskId;
    try {
      final directory = await _directory();
      final destination = File(
        '${directory.path}${Platform.pathSeparator}${record.filename}',
      );
      final work = Directory(
        '${directory.path}${Platform.pathSeparator}.linky-dash'
        '${Platform.pathSeparator}$id',
      );
      final result = await DashDownloader(
        workers: SettingsService.instance.downloadThreadCount,
      ).download(
        url: record.url,
        destination: destination,
        workDirectory: work,
        headers: record.requestHeaders,
        isCancelled: () => handle.stopRequested,
        audioOnly: SettingsService.instance.audioOnlyDownloads,
        onLiveDetected: () => _markLive(id),
        preferredFormatId: record.formatId,
        onProgress: (completed, total) {
          final current = _records[id];
          if (current == null) return;
          final ratio = total > 0
              ? (completed / total).clamp(0.0, 1.0).toDouble()
              : current.progress;
          _records[id] = current.copyWith(
            state: DownloadState.running,
            progress: ratio,
          );
          _reportProgress(current, ratio, indeterminate: total <= 0);
          _notify();
        },
      );
      final current = _records[id];
      if (current == null) return;
      if (current.state == DownloadState.canceled) {
        try {
          await result.file.delete();
        } catch (_) {}
        return;
      }
      final post = await _postProcess(
        record,
        result.file,
        result.warning ?? (result.isLive ? 'Live recording saved.' : null),
      );
      _records[id] = current.copyWith(
        state: DownloadState.complete,
        progress: 1,
        expectedBytes: await post.$1.length(),
        filePath: post.$1.path,
        error: post.$2,
        isLive: result.isLive,
      );
      _notify(force: true);
      _schedulePersist();
      unawaited(
          NotificationService.downloadComplete(current.title, taskId: id));
    } on DashCanceled {
      final current = _records[id];
      if (current != null) {
        _records[id] = current.copyWith(
          state:
              handle.canceled ? DownloadState.canceled : DownloadState.paused,
          error: handle.canceled
              ? 'Download canceled.'
              : 'Paused. Tap resume to continue.',
        );
      }
      if (handle.canceled) {
        final directory = await _directory();
        try {
          await Directory(
            '${directory.path}${Platform.pathSeparator}.linky-dash'
            '${Platform.pathSeparator}$id',
          ).delete(recursive: true);
        } catch (_) {}
      }
      _notify(force: true);
      _schedulePersist();
      _dismissNotification(id);
    } catch (error) {
      final current = _records[id];
      if (current != null) {
        _records[id] = current.copyWith(
          state: DownloadState.failed,
          error: 'Download failed: $error',
        );
      }
      _notify(force: true);
      _schedulePersist();
      _dismissNotification(id);
    }
  }

  Future<void> _runChunked(
    DownloadRecord record,
    _ChunkHandle handle,
  ) async {
    final id = record.taskId;
    try {
      final directory = await _directory();
      final destination = File(
        '${directory.path}${Platform.pathSeparator}${record.filename}',
      );
      final work = Directory(
        '${directory.path}${Platform.pathSeparator}.linky-parts'
        '${Platform.pathSeparator}$id',
      );
      final file = await ChunkedDownloader(
        threadCount: SettingsService.instance.downloadThreadCount,
      ).download(
        url: record.url,
        destination: destination,
        workDirectory: work,
        headers: record.requestHeaders,
        expectedBytes: record.expectedBytes > 0 ? record.expectedBytes : null,
        isCancelled: () => handle.stopRequested,
        onProgress: (received, total) {
          final current = _records[id];
          if (current == null) return;
          final ratio = total != null && total > 0
              ? (received / total).clamp(0.0, 1.0).toDouble()
              : current.progress;
          _records[id] = current.copyWith(
            state: DownloadState.running,
            progress: ratio,
            expectedBytes:
                total != null && total > 0 ? total : current.expectedBytes,
          );
          _reportProgress(current, ratio,
              indeterminate: total == null || total <= 0);
          _notify();
        },
      );
      final current = _records[id];
      if (current == null) return;
      if (current.state == DownloadState.canceled) {
        try {
          await file.delete();
        } catch (_) {}
        return;
      }
      final post = await _postProcess(record, file, null);
      _records[id] = current.copyWith(
        state: DownloadState.complete,
        progress: 1,
        expectedBytes: await post.$1.length(),
        filePath: post.$1.path,
        error: post.$2,
      );
      _notify(force: true);
      _schedulePersist();
      unawaited(
          NotificationService.downloadComplete(current.title, taskId: id));
    } on ChunkedDownloadCanceled {
      final current = _records[id];
      if (current != null) {
        _records[id] = current.copyWith(
          state:
              handle.canceled ? DownloadState.canceled : DownloadState.paused,
          error: handle.canceled
              ? 'Download canceled.'
              : 'Paused. Tap resume to continue.',
        );
      }
      if (handle.canceled) {
        final directory = await _directory();
        try {
          await Directory(
            '${directory.path}${Platform.pathSeparator}.linky-parts'
            '${Platform.pathSeparator}$id',
          ).delete(recursive: true);
        } catch (_) {}
      }
      _notify(force: true);
      _schedulePersist();
      _dismissNotification(id);
    } catch (error) {
      final current = _records[id];
      if (current != null) {
        _records[id] = current.copyWith(
          state: DownloadState.failed,
          error: 'Download failed: $error',
        );
      }
      _notify(force: true);
      _schedulePersist();
      _dismissNotification(id);
    }
  }

  Future<void> _runExtractor(DownloadRecord record) async {
    final current = _records[record.taskId];
    if (current == null || current.state.isFinal) return;
    _records[record.taskId] = current.copyWith(
      state: DownloadState.running,
      error: null,
      progress: 0,
      fallbackAttempted: true,
    );
    _notify(force: true);
    try {
      final directory = await _directory();
      final cookieText =
          await PlatformExtractor().cookieTextFor(current.sourcePage!);
      final file = await PlatformExtractor().download(
        pageUrl: current.sourcePage!,
        formatId: current.formatId!,
        outputDirectory: directory,
        cookieText: cookieText,
        audioFormatId: current.audioFormatId,
        videoUrl: current.url,
        audioUrl: current.audioUrl,
        videoMimeType: current.mimeType,
        audioMimeType: current.audioMimeType,
        outputName: current.filename,
        headers: current.requestHeaders,
        taskId: current.taskId,
        onProgress: (progress) {
          final latest = _records[record.taskId];
          if (latest == null || latest.state.isFinal) return;
          final ratio = progress.clamp(0.0, 1.0).toDouble();
          _records[record.taskId] = latest.copyWith(
            state: DownloadState.running,
            progress: ratio,
          );
          _reportProgress(latest, ratio);
          _notify();
        },
      );
      if (_records[record.taskId]?.state == DownloadState.canceled) return;
      final post = await _postProcess(current, file, null);
      if (_records[record.taskId]?.state == DownloadState.canceled) return;
      _records[record.taskId] = current.copyWith(
        state: DownloadState.complete,
        progress: 1,
        expectedBytes: await post.$1.length(),
        filePath: post.$1.path,
        error: post.$2,
        fallbackAttempted: true,
      );
      unawaited(NotificationService.downloadComplete(
        current.title,
        taskId: record.taskId,
      ));
    } catch (error) {
      if (_records[record.taskId]?.state == DownloadState.canceled) return;
      _records[record.taskId] = current.copyWith(
        state: DownloadState.failed,
        error: 'Download failed: $error',
        fallbackAttempted: true,
      );
      _dismissNotification(record.taskId);
    }
    _notify(force: true);
    _schedulePersist();
  }

  Future<(File, String?)> _postProcess(
    DownloadRecord record,
    File file,
    String? warning,
  ) async {
    try {
      final processed = await _postProcessor.process(file, type: record.type);
      final warnings = <String>[
        if (warning != null && warning.isNotEmpty) warning,
        if (processed.warning != null && processed.warning!.isNotEmpty)
          processed.warning!,
      ];
      if (SettingsService.instance.copyToPublicDownloads) {
        final copied = await DeviceResources.instance.saveToPublicDownloads(
          processed.file.path,
          processed.file.uri.pathSegments.last,
        );
        if (!copied) {
          warnings.add('Could not copy the file to public Downloads.');
        }
      }
      return (processed.file, warnings.isEmpty ? null : warnings.join(' '));
    } catch (_) {
      return (file, warning);
    }
  }

  Future<void> _reconcile() async {
    try {
      final activeIds = (await FileDownloader().allTasks(group: _group))
          .map((task) => task.taskId)
          .toSet();
      var changed = false;
      for (final record in _records.values.toList()) {
        if (!record.state.isActive ||
            record.state == DownloadState.paused ||
            activeIds.contains(record.taskId) ||
            _isChunked(record) ||
            _isExtractor(record) ||
            _pending.contains(record.taskId) ||
            _chunked.containsKey(record.taskId) ||
            _runningExtractors.contains(record.taskId)) {
          continue;
        }
        final path = await _pathFor(record);
        final file = File(path);
        final exists = await file.exists() && await file.length() > 0;
        _records[record.taskId] = exists
            ? record.copyWith(
                state: DownloadState.complete,
                progress: 1,
                filePath: path,
              )
            : record.copyWith(
                state: DownloadState.failed,
                error: 'The download was interrupted. Tap retry.',
              );
        changed = true;
      }
      if (changed) {
        _notify(force: true);
        _schedulePersist();
      }
    } catch (_) {}
  }

  Future<void> _ensureNotificationPermission() async {
    try {
      final downloader = FileDownloader();
      final status =
          await downloader.permissions.status(PermissionType.notifications);
      if (status != PermissionStatus.granted) {
        await downloader.permissions.request(PermissionType.notifications);
      }
    } catch (_) {}
  }

  DownloadState _stateFor(TaskStatus status) => switch (status) {
        TaskStatus.enqueued => DownloadState.queued,
        TaskStatus.running => DownloadState.running,
        TaskStatus.complete => DownloadState.complete,
        TaskStatus.paused => DownloadState.paused,
        TaskStatus.waitingToRetry => DownloadState.retrying,
        TaskStatus.notFound => DownloadState.failed,
        TaskStatus.failed => DownloadState.failed,
        TaskStatus.canceled => DownloadState.canceled,
      };

  String? _errorFor(TaskStatusUpdate update) {
    if (update.status == TaskStatus.notFound) {
      return 'The file was not found on the server.';
    }
    if (update.status == TaskStatus.failed) {
      return update.exception?.description.isNotEmpty == true
          ? update.exception!.description
          : 'The download failed.';
    }
    return null;
  }

  Future<Directory> _directory() async =>
      StorageService.instance.downloadDirectory();

  Future<void> relocateDownloads(String targetPath) async {
    for (final record in _records.values.toList()) {
      if (record.state.isActive || record.filePath == null) continue;
      final name = File(record.filePath!).uri.pathSegments.last;
      final candidate = File('$targetPath${Platform.pathSeparator}$name');
      if (await candidate.exists()) {
        _records[record.taskId] = record.copyWith(
          filePath: candidate.path,
        );
      }
    }
    _notify(force: true);
    _schedulePersist();
  }

  Future<String> _pathFor(DownloadRecord record) async {
    final directory = await _directory();
    return '${directory.path}${Platform.pathSeparator}${record.filename}';
  }

  Future<String> _uniqueFilename(MediaItem item) async {
    final directory = await _directory();
    final base = MediaDownloader.sanitizeFilename(_baseName(item));
    final name = _ensureExtension(base, item);
    final reserved = _records.values
        .where((record) => record.state.isActive)
        .map((record) => record.filename.toLowerCase())
        .toSet();
    var candidate = name;
    var counter = 1;
    while (reserved.contains(candidate.toLowerCase()) ||
        await File('${directory.path}/$candidate').exists()) {
      final dot = name.lastIndexOf('.');
      final stem = dot > 0 ? name.substring(0, dot) : name;
      final extension = dot > 0 ? name.substring(dot) : '';
      candidate = '$stem ($counter)$extension';
      counter++;
    }
    return candidate;
  }

  String _baseName(MediaItem item) {
    final title = item.title?.trim();
    if (title != null && title.isNotEmpty) return title;
    final uri = Uri.tryParse(item.url);
    final segment =
        uri?.pathSegments.isNotEmpty == true ? uri!.pathSegments.last : '';
    if (segment.trim().isNotEmpty) return segment;
    return uri?.host.isNotEmpty == true ? uri!.host : 'media';
  }

  String _ensureExtension(String name, MediaItem item) {
    if (_mediaExtension.hasMatch(name)) return name;
    final path = Uri.tryParse(item.url)?.path.toLowerCase() ?? '';
    final mime = item.mimeType?.toLowerCase() ?? '';
    if (path.endsWith('.m3u8') ||
        path.endsWith('.m3u') ||
        mime.contains('mpegurl')) {
      return '$name.mp4';
    }
    if (path.endsWith('.mpd') || mime.contains('dash+xml')) {
      return '$name.mp4';
    }
    var extension = MediaDownloader.extensionForMime(
      item.mimeType,
      fallback: '',
    );
    if (extension.isEmpty) {
      extension = switch (item.type) {
        'image' => 'jpg',
        'audio' => 'mp3',
        'document' => 'bin',
        'subtitle' => 'vtt',
        _ => 'mp4',
      };
    }
    return '$name.$extension';
  }

  String _displayTitle(MediaItem item) {
    final title = item.title?.trim();
    if (title != null && title.isNotEmpty) return title;
    return Uri.tryParse(item.url)?.pathSegments.lastOrNull ?? 'Media';
  }

  Future<File> _storeFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/linky_transfers.json');
  }

  Future<void> _loadPersisted() async {
    try {
      final file = await _storeFile();
      if (!await file.exists()) return;
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) return;
      for (final entry in raw) {
        if (entry is Map<String, dynamic>) {
          final record = DownloadRecord.fromJson(entry);
          if (record.taskId.isNotEmpty && record.url.isNotEmpty) {
            _records[record.taskId] = record;
          }
        }
      }
    } catch (_) {}
  }

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 400), _persist);
  }

  Future<void> _persist() async {
    try {
      final file = await _storeFile();
      final cutoff = DateTime.now().subtract(const Duration(days: 14));
      final list = records
          .where((record) =>
              !record.state.isFinal || record.createdAt.isAfter(cutoff))
          .take(100)
          .map((record) => record.toJson())
          .toList();
      await file.writeAsString(jsonEncode(list));
    } catch (_) {}
  }

  void _markLive(String id) {
    final current = _records[id];
    if (current == null || current.isLive || current.state.isFinal) return;
    _records[id] = current.copyWith(isLive: true);
    _notify(force: true);
  }

  void _reportProgress(
    DownloadRecord record,
    double progress, {
    bool indeterminate = false,
  }) {
    unawaited(NotificationService.downloadProgress(
      record.taskId,
      record.title,
      progress,
      indeterminate: indeterminate,
    ));
  }

  void _dismissNotification(String taskId) {
    unawaited(NotificationService.dismiss(taskId));
  }

  void _syncForeground() {
    final needed = _records.values.any(
      (record) =>
          record.state.isActive &&
          record.state != DownloadState.paused &&
          (_isChunked(record) || _isExtractor(record)),
    );
    if (needed == _foregroundStarted) return;
    _foregroundStarted = needed;
    _foregroundOp = _foregroundOp.then((_) => _applyForeground(needed));
  }

  Future<void> _applyForeground(bool needed) async {
    final applied = needed
        ? await NotificationService.startDownloadService()
        : await NotificationService.stopDownloadService();
    if (!applied) _foregroundStarted = !needed;
  }

  void _notify({bool force = false}) {
    _syncForeground();
    final now = DateTime.now();
    if (!force &&
        now.difference(_lastNotify) < const Duration(milliseconds: 100)) {
      return;
    }
    _lastNotify = now;
    notifyListeners();
  }

  @override
  void dispose() {
    _updates?.cancel();
    _persistTimer?.cancel();
    super.dispose();
  }
}

extension _LastOrNull<T> on List<T> {
  T? get lastOrNull => isEmpty ? null : last;
}

class _ChunkHandle {
  bool stopRequested = false;
  bool paused = false;
  bool canceled = false;
}

class _ResourceBlock {
  const _ResourceBlock(this.message, {required this.storage});

  final String message;
  final bool storage;
}
