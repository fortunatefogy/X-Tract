import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/device_media_channel.dart';
import '../../services/download_service.dart';
import '../../services/media_downloader.dart';
import '../../services/storage_service.dart';
import '../../widgets/media_thumbnail.dart';
import 'video_playback_screen.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final _deviceMedia = DeviceMediaChannel();
  final Set<String> _selectedPaths = {};
  late Future<List<File>> _files;
  late Future<int> _totalFuture;
  String _completedSignature = '';
  final Map<String, DateTime> _speedSampledAt = {};
  final Map<String, double> _speedProgress = {};
  final Map<String, double> _speeds = {};

  @override
  void initState() {
    super.initState();
    _assignFiles();
    DownloadService.instance.addListener(_onDownloadsChanged);
  }

  void _assignFiles() {
    final future = _loadFiles();
    _files = future;
    _totalFuture = future.then(_sumSizes);
  }

  Future<int> _sumSizes(List<File> files) async {
    var total = 0;
    for (final file in files) {
      try {
        total += (await file.stat()).size;
      } catch (_) {}
    }
    return total;
  }

  void _sampleSpeeds() {
    final now = DateTime.now();
    for (final record in DownloadService.instance.records
        .where((record) => record.state == DownloadState.running)) {
      final previousProgress = _speedProgress[record.taskId];
      final previousTime = _speedSampledAt[record.taskId];
      if (previousProgress != null &&
          previousTime != null &&
          record.expectedBytes > 0) {
        final seconds = now.difference(previousTime).inMilliseconds / 1000;
        final delta = record.progress - previousProgress;
        if (seconds > 0.2 && delta >= 0) {
          _speeds[record.taskId] = delta * record.expectedBytes / seconds;
        }
      }
      _speedProgress[record.taskId] = record.progress;
      _speedSampledAt[record.taskId] = now;
    }
  }

  @override
  void dispose() {
    DownloadService.instance.removeListener(_onDownloadsChanged);
    super.dispose();
  }

  void _onDownloadsChanged() {
    final signature = DownloadService.instance.records
        .where((record) => record.state == DownloadState.complete)
        .map((record) => record.taskId)
        .join(',');
    if (!mounted) return;
    _sampleSpeeds();
    setState(() {
      if (signature != _completedSignature) {
        _completedSignature = signature;
        _assignFiles();
      }
    });
  }

  Future<List<File>> _loadFiles() async {
    final directory = await StorageService.instance.downloadDirectory();
    if (!await directory.exists()) return [];
    final files = await directory
        .list(followLinks: false)
        .where((entity) => entity is File)
        .cast<File>()
        .toList();
    final modified = <File, DateTime>{};
    for (final file in files) {
      modified[file] = (await file.stat()).modified;
    }
    files.sort((a, b) => modified[b]!.compareTo(modified[a]!));
    return files;
  }

  void _refresh() => setState(_assignFiles);

  Future<void> _openFolder() async {
    final opened = await StorageService.instance.openFolder();
    if (!mounted) return;
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No file manager could open the downloads folder.'),
        ),
      );
    }
  }

  Future<void> _moveDownloads() async {
    if (DownloadService.instance.active.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Finish or cancel active downloads before moving files.'),
        ),
      );
      return;
    }
    try {
      final moved = await StorageService.instance.moveExistingDownloads();
      final target = await StorageService.instance.downloadDirectory();
      await DownloadService.instance.relocateDownloads(target.path);
      if (!mounted) return;
      setState(_assignFiles);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            moved == 0
                ? 'No files needed to be moved.'
                : 'Moved $moved file(s) to the current downloads location.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not move downloads: $error')),
      );
    }
  }

  Future<void> _exportQueue() async {
    final raw = DownloadService.instance.exportQueuedTasks();
    final count = (jsonDecode(raw) as List).length;
    if (count == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No queued downloads to export.')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: raw));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied $count queued task(s) to the clipboard.')),
    );
  }

  Future<void> _importQueue() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = data?.text?.trim();
    if (raw == null || raw.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('The clipboard does not contain a task list.')),
      );
      return;
    }
    try {
      final imported = await DownloadService.instance.importQueuedTasks(raw);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(imported == 0
              ? 'No new tasks were imported.'
              : 'Imported $imported queued task(s).'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not import the task list: $error')),
      );
    }
  }

  Future<void> _delete(File file) async {
    try {
      if (await file.exists()) await file.delete();
      if (!mounted) return;
      setState(() {
        _selectedPaths.remove(file.path);
        _assignFiles();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Download deleted')),
      );
    } on FileSystemException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete file: ${error.message}')),
      );
    }
  }

  Future<void> _share(File file) async {
    try {
      await _deviceMedia.shareFile(file.path);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not share the file: $error')),
      );
    }
  }

  Future<void> _openWith(File file) async {
    try {
      await _deviceMedia.openWithFile(file.path);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No app could open this file: $error')),
      );
    }
  }

  Future<void> _rename(File file) async {
    final originalName = file.uri.pathSegments.last;
    final controller = TextEditingController(text: originalName);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename file'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (value == null || value.isEmpty || !mounted) return;
    var name = MediaDownloader.sanitizeFilename(value);
    if (!name.contains('.')) {
      final dot = originalName.lastIndexOf('.');
      if (dot > 0) name = '$name${originalName.substring(dot)}';
    }
    if (name == originalName) return;
    try {
      var target = File('${file.parent.path}${Platform.pathSeparator}$name');
      var duplicate = 1;
      final dot = name.lastIndexOf('.');
      final stem = dot > 0 ? name.substring(0, dot) : name;
      final extension = dot > 0 ? name.substring(dot) : '';
      while (await target.exists()) {
        target = File(
          '${file.parent.path}${Platform.pathSeparator}$stem ($duplicate)$extension',
        );
        duplicate++;
      }
      await file.rename(target.path);
      if (!mounted) return;
      setState(() {
        _selectedPaths.remove(file.path);
        _assignFiles();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File renamed.')),
      );
    } on FileSystemException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not rename the file: ${error.message}')),
      );
    }
  }

  Future<void> _saveSelectedToGallery() async {
    final selected = _selectedPaths.toList();
    var saved = 0;
    var failed = 0;
    for (final path in selected) {
      try {
        await _deviceMedia.saveToGallery(path);
        saved++;
      } on Exception catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    setState(_selectedPaths.clear);
    final message = saved == 0
        ? 'No files were saved. Select supported image or video files and try again.'
        : failed == 0
            ? 'Saved $saved file(s) to your phone Gallery.'
            : 'Saved $saved file(s); $failed could not be added to Gallery.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _previewImage(File file) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: Text(file.uri.pathSegments.last),
            actions: [
              IconButton(
                tooltip: 'Delete file',
                onPressed: () async {
                  Navigator.pop(context);
                  await _delete(file);
                },
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.file(file, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final downloads = DownloadService.instance;
    final active = downloads.active;
    final failures = downloads.failures;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        actions: [
          TextButton.icon(
            onPressed: _selectedPaths.isEmpty ? null : _saveSelectedToGallery,
            icon: const Icon(Icons.save_alt),
            label: Text(_selectedPaths.isEmpty
                ? 'Save to Gallery'
                : 'Save (${_selectedPaths.length})'),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            tooltip: 'Queue tools',
            onSelected: (value) {
              if (value == 'pauseAll') DownloadService.instance.pauseAll();
              if (value == 'resumeAll') DownloadService.instance.resumeAll();
              if (value == 'retryAll') DownloadService.instance.retryAll();
              if (value == 'export') _exportQueue();
              if (value == 'import') _importQueue();
              if (value == 'openFolder') _openFolder();
              if (value == 'move') _moveDownloads();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'pauseAll',
                enabled: active.any((record) =>
                    record.state == DownloadState.running ||
                    record.state == DownloadState.queued ||
                    record.state == DownloadState.retrying),
                child: const Text('Pause all'),
              ),
              PopupMenuItem(
                value: 'resumeAll',
                enabled: active
                    .any((record) => record.state == DownloadState.paused),
                child: const Text('Resume all'),
              ),
              PopupMenuItem(
                value: 'retryAll',
                enabled: failures.isNotEmpty,
                child: const Text('Retry all failed'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'openFolder',
                child: Text('Open downloads folder'),
              ),
              const PopupMenuItem(
                value: 'move',
                child: Text('Move downloads to current location'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'export',
                child: Text('Export queue to clipboard'),
              ),
              const PopupMenuItem(
                value: 'import',
                child: Text('Import queue from clipboard'),
              ),
            ],
          ),
        ],
      ),
      body: FutureBuilder<List<File>>(
        future: _files,
        builder: (context, snapshot) {
          final loading = snapshot.connectionState != ConnectionState.done;
          final files = snapshot.data ?? const <File>[];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (files.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FutureBuilder<int>(
                    future: _totalFuture,
                    builder: (context, totalSnapshot) => Text(
                      '${files.length} file${files.length == 1 ? '' : 's'} in downloads'
                      '${totalSnapshot.hasData ? ' · ${_formatBytes(totalSnapshot.data!)}' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ),
              if (active.isNotEmpty) ...[
                _sectionHeader('In progress'),
                ...active.map(_transferTile),
                const SizedBox(height: 8),
              ],
              if (failures.isNotEmpty) ...[
                _sectionHeader(
                  'Needs attention',
                  trailing: TextButton(
                    onPressed: downloads.clearFinished,
                    child: const Text('Clear'),
                  ),
                ),
                ...failures.map(_transferTile),
                const SizedBox(height: 8),
              ],
              if (active.isNotEmpty || failures.isNotEmpty)
                const Divider(height: 24),
              if (loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (files.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Your downloads will appear here and stay available offline.',
                    textAlign: TextAlign.center,
                  ),
                )
              else
                ...files.map(_fileTile),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionHeader(String title, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      );

  Widget _transferTile(DownloadRecord record) {
    final active = record.state.isActive;
    final canPause = record.state == DownloadState.running;
    final canResume = record.state == DownloadState.paused;
    final canRetry = record.state == DownloadState.failed ||
        record.state == DownloadState.canceled;
    final canDismiss = record.state.isFinal;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _stateIcon(record.state),
                  color: record.state == DownloadState.failed
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _transferSubtitle(record),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (canPause)
                  IconButton(
                    tooltip: 'Pause',
                    onPressed: () => DownloadService.instance.pause(record),
                    icon: const Icon(Icons.pause),
                  ),
                if (canResume)
                  IconButton(
                    tooltip: 'Resume',
                    onPressed: () => DownloadService.instance.resume(record),
                    icon: const Icon(Icons.play_arrow),
                  ),
                if (canRetry)
                  IconButton(
                    tooltip: 'Retry',
                    onPressed: () => _retry(record),
                    icon: const Icon(Icons.refresh),
                  ),
                if (active)
                  IconButton(
                    tooltip: 'Cancel',
                    onPressed: () => DownloadService.instance.cancel(record),
                    icon: const Icon(Icons.close),
                  )
                else if (canDismiss)
                  IconButton(
                    tooltip: 'Dismiss',
                    onPressed: () => DownloadService.instance.dismiss(record),
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            if (active) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: record.progress > 0 ? record.progress : null,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _retry(DownloadRecord record) async {
    try {
      await DownloadService.instance.retry(record);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not retry the download: $error')),
      );
    }
  }

  String _transferSubtitle(DownloadRecord record) {
    final percent = (record.progress * 100).clamp(0, 100).toStringAsFixed(0);
    final size = record.expectedBytes > 0
        ? ' of ${_formatBytes(record.expectedBytes)}'
        : '';
    final rate = _speeds[record.taskId];
    final speed = rate != null && rate.isFinite && rate > 0
        ? ' · ${_formatSpeed(rate)}'
        : '';
    return switch (record.state) {
      DownloadState.queued => record.error ?? 'Queued',
      DownloadState.running => '$percent%$size$speed',
      DownloadState.paused => 'Paused',
      DownloadState.retrying => 'Waiting to retry…',
      DownloadState.complete => 'Completed',
      DownloadState.failed => record.error ?? 'Failed',
      DownloadState.canceled => 'Canceled',
    };
  }

  IconData _stateIcon(DownloadState state) => switch (state) {
        DownloadState.queued => Icons.schedule,
        DownloadState.running => Icons.downloading,
        DownloadState.paused => Icons.pause_circle_outline,
        DownloadState.retrying => Icons.autorenew,
        DownloadState.complete => Icons.check_circle_outline,
        DownloadState.failed => Icons.error_outline,
        DownloadState.canceled => Icons.cancel_outlined,
      };

  Widget _fileTile(File file) {
    final name = file.uri.pathSegments.last;
    final isImage = RegExp(
      r'\.(jpe?g|png|gif|webp|avif|bmp)$',
      caseSensitive: false,
    ).hasMatch(name);
    final canPlayVideo = RegExp(
      r'\.(mp4|m4v|webm|mov|3gp)$',
      caseSensitive: false,
    ).hasMatch(name);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          leading: isImage || canPlayVideo
              ? MediaThumbnail(
                  type: isImage ? 'image' : 'video',
                  file: file,
                  size: 52,
                  fallback: _fileIcon(canPlayVideo),
                )
              : _fileIcon(false),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: FutureBuilder<FileStat>(
            future: file.stat(),
            builder: (context, stat) {
              if (!stat.hasData) {
                return const Text('Saved on this device');
              }
              return Text(_formatBytes(stat.data!.size));
            },
          ),
          onTap: isImage
              ? () => _previewImage(file)
              : canPlayVideo
                  ? () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => VideoPlaybackScreen(file: file),
                        ),
                      )
                  : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: _selectedPaths.contains(file.path),
                onChanged: (selected) => setState(() {
                  if (selected == true) {
                    _selectedPaths.add(file.path);
                  } else {
                    _selectedPaths.remove(file.path);
                  }
                }),
              ),
              PopupMenuButton<String>(
                tooltip: 'File actions',
                onSelected: (value) {
                  if (value == 'share') _share(file);
                  if (value == 'open') _openWith(file);
                  if (value == 'rename') _rename(file);
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'share', child: Text('Share')),
                  PopupMenuItem(value: 'open', child: Text('Open with')),
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                ],
              ),
              IconButton(
                tooltip: 'Delete file',
                onPressed: () => _delete(file),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fileIcon(bool video) => CircleAvatar(
        child: Icon(
            video ? Icons.movie_outlined : Icons.insert_drive_file_outlined),
      );

  String _formatSpeed(double bytesPerSecond) =>
      '${_formatBytes(bytesPerSecond.round())}/s';

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
