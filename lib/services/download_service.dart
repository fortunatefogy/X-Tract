import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/media_item.dart';
import 'media_downloader.dart';
import 'platform_extractor.dart';

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
  final _random = Random();
  StreamSubscription<TaskUpdate>? _updates;
  Timer? _persistTimer;
  bool _initialized = false;
  bool _available = false;
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
  }

  Future<DownloadRecord> enqueue(
    MediaItem item, {
    Map<String, String> extraHeaders = const {},
  }) async {
    await init();
    if (!_available) {
      throw StateError('Background downloads are unavailable on this device.');
    }
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

    if (record.requiresExtractor &&
        record.formatId != null &&
        record.sourcePage != null) {
      _schedulePersist();
      unawaited(_extractorFallback(record));
      return _records[taskId] ?? record;
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
    _records[record.taskId] = record.copyWith(state: DownloadState.canceled);
    _notify(force: true);
    await FileDownloader().cancelTaskWithId(record.taskId);
    _schedulePersist();
  }

  Future<void> pause(DownloadRecord record) async {
    await FileDownloader().pause(_taskFromRecord(record));
  }

  Future<void> resume(DownloadRecord record) async {
    await FileDownloader().resume(_taskFromRecord(record));
  }

  Future<void> retry(DownloadRecord record) async {
    final media = record.toMediaItem();
    _records.remove(record.taskId);
    _notify(force: true);
    _schedulePersist();
    await enqueue(media, extraHeaders: record.requestHeaders);
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
      unawaited(_extractorFallback(next));
    }
  }

  Future<void> _extractorFallback(DownloadRecord record) async {
    final current = _records[record.taskId];
    if (current == null ||
        current.fallbackAttempted ||
        (current.state != DownloadState.failed &&
            current.state != DownloadState.queued)) {
      return;
    }
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
      );
      _records[record.taskId] = current.copyWith(
        state: DownloadState.complete,
        progress: 1,
        filePath: file.path,
        error: null,
        fallbackAttempted: true,
      );
    } catch (error) {
      _records[record.taskId] = current.copyWith(
        state: DownloadState.failed,
        error: 'Download failed: $error',
        fallbackAttempted: true,
      );
    }
    _notify(force: true);
    _schedulePersist();
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
            activeIds.contains(record.taskId)) {
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

  Future<Directory> _directory() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory('${documents.path}/$_folder');
    await directory.create(recursive: true);
    return directory;
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

  void _notify({bool force = false}) {
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
