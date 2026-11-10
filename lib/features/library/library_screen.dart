import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/device_media_channel.dart';
import '../../services/download_service.dart';
import '../../services/media_downloader.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/media_thumbnail.dart';
import '../downloads/video_playback_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _deviceMedia = DeviceMediaChannel();
  final _searchController = TextEditingController();
  final Set<String> _selectedPaths = {};
  late Future<List<File>> _files;
  bool _selecting = false;
  String _completedSignature = '';

  @override
  void initState() {
    super.initState();
    _files = _loadFiles();
    DownloadService.instance.addListener(_onDownloadsChanged);
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    DownloadService.instance.removeListener(_onDownloadsChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onDownloadsChanged() {
    final signature = DownloadService.instance.records
        .where((record) => record.state == DownloadState.complete)
        .map((record) => record.taskId)
        .join(',');
    if (!mounted || signature == _completedSignature) return;
    setState(() {
      _completedSignature = signature;
      _files = _loadFiles();
    });
  }

  Future<List<File>> _loadFiles() async {
    final directory = await StorageService.instance.downloadDirectory();
    if (!await directory.exists()) return [];
    final files = await directory
        .list(followLinks: false)
        .where((entity) => entity is File)
        .cast<File>()
        .where((file) {
          final name = file.uri.pathSegments.last;
          return !name.startsWith('.') && !name.startsWith('linky_');
        })
        .toList();
    final modified = <File, DateTime>{};
    for (final file in files) {
      modified[file] = (await file.stat()).modified;
    }
    files.sort((a, b) => modified[b]!.compareTo(modified[a]!));
    return files;
  }

  Future<void> _delete(File file) async {
    try {
      if (await file.exists()) await file.delete();
      if (!mounted) return;
      setState(() {
        _selectedPaths.remove(file.path);
        _files = _loadFiles();
      });
      _toast('File deleted');
    } on FileSystemException catch (error) {
      _toast('Could not delete file: ${error.message}');
    }
  }

  Future<void> _share(File file) async {
    try {
      await _deviceMedia.shareFile(file.path);
    } catch (error) {
      _toast('Could not share the file: $error');
    }
  }

  Future<void> _openWith(File file) async {
    try {
      await _deviceMedia.openWithFile(file.path);
    } catch (error) {
      _toast('No app could open this file: $error');
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
          decoration: const InputDecoration(hintText: 'File name'),
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
        _files = _loadFiles();
      });
      _toast('File renamed');
    } on FileSystemException catch (error) {
      _toast('Could not rename the file: ${error.message}');
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
    setState(() {
      _selectedPaths.clear();
      _selecting = false;
    });
    _toast(
      saved == 0
          ? 'No files were saved. Select image or video files and try again.'
          : failed == 0
              ? 'Saved $saved file(s) to your Gallery.'
              : 'Saved $saved file(s); $failed could not be added to Gallery.',
    );
  }

  void _deleteSelected() {
    final selected = _selectedPaths
        .map((path) => File(path))
        .where((file) => file.existsSync())
        .toList(growable: false);
    setState(() {
      for (final file in selected) {
        try {
          file.deleteSync();
        } catch (_) {}
      }
      _selectedPaths.clear();
      _selecting = false;
      _files = _loadFiles();
    });
    _toast('Deleted ${selected.length} file(s)');
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _previewImage(File file) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
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

  bool _isImage(String name) => RegExp(
        r'\.(jpe?g|png|gif|webp|avif|bmp)$',
        caseSensitive: false,
      ).hasMatch(name);

  bool _isVideo(String name) => RegExp(
        r'\.(mp4|m4v|webm|mov|3gp)$',
        caseSensitive: false,
      ).hasMatch(name);

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: FutureBuilder<List<File>>(
          future: _files,
          builder: (context, snapshot) {
            final loading = snapshot.connectionState != ConnectionState.done;
            final query = _searchController.text.trim().toLowerCase();
            final files = (snapshot.data ?? const <File>[])
                .where((file) =>
                    query.isEmpty ||
                    file.uri.pathSegments.last.toLowerCase().contains(query))
                .toList(growable: false);
            return Stack(
              children: [
                ListView(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    12,
                    20,
                    _selecting ? 120 : 32,
                  ),
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Library',
                                  style: AppText.display(30,
                                      color: palette.foreground)),
                              const SizedBox(height: 2),
                              Text(
                                'Your saved media, available offline.',
                                style: AppText.body(13,
                                    color: palette.mutedForeground),
                              ),
                            ],
                          ),
                        ),
                        RoundIconButton(
                          icon: _selecting
                              ? Icons.check_rounded
                              : Icons.checklist_rounded,
                          tooltip:
                              _selecting ? 'Done selecting' : 'Select files',
                          filled: _selecting,
                          onPressed: () => setState(() {
                            _selecting = !_selecting;
                            if (!_selecting) _selectedPaths.clear();
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search your files',
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: palette.mutedForeground,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 48),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (files.isEmpty)
                      _empty(query.isNotEmpty)
                    else ...[
                      Text(
                        '${files.length} file${files.length == 1 ? '' : 's'}',
                        style: AppText.label(11,
                            color: palette.mutedForeground),
                      ),
                      const SizedBox(height: 10),
                      for (final file in files) _fileCard(file),
                    ],
                  ],
                ),
                if (_selecting)
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 16,
                    child: _SelectionBar(
                      count: _selectedPaths.length,
                      onSave: _selectedPaths.isEmpty
                          ? null
                          : _saveSelectedToGallery,
                      onDelete:
                          _selectedPaths.isEmpty ? null : _deleteSelected,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _empty(bool searching) => Padding(
        padding: const EdgeInsets.only(top: 24),
        child: EmptyState(
          icon: searching ? Icons.search_off_rounded : Icons.folder_open_rounded,
          title: searching ? 'No matches' : 'Nothing saved yet',
          message: searching
              ? 'Try a different file name.'
              : 'Media you download will live here and stay available offline.',
        ),
      );

  Widget _fileCard(File file) {
    final palette = context.palette;
    final name = file.uri.pathSegments.last;
    final isImage = _isImage(name);
    final isVideo = _isVideo(name);
    final selected = _selectedPaths.contains(file.path);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        onTap: _selecting
            ? () => setState(() {
                  if (selected) {
                    _selectedPaths.remove(file.path);
                  } else {
                    _selectedPaths.add(file.path);
                  }
                })
            : isImage
                ? () => _previewImage(file)
                : isVideo
                    ? () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => VideoPlaybackScreen(file: file),
                          ),
                        )
                    : null,
        color: selected ? palette.accent : null,
        child: Row(
          children: [
            MediaThumbnail(
              type: isImage ? 'image' : isVideo ? 'video' : 'document',
              file: isImage || isVideo ? file : null,
              size: 56,
              fallback: Icon(
                isVideo
                    ? Icons.movie_outlined
                    : isImage
                        ? Icons.image_outlined
                        : Icons.insert_drive_file_outlined,
                color: palette.mutedForeground,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(14, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  FutureBuilder<FileStat>(
                    future: file.stat(),
                    builder: (context, stat) => Text(
                      stat.hasData
                          ? '${_formatBytes(stat.data!.size)} · ${isVideo ? 'Video' : isImage ? 'Image' : 'File'}'
                          : 'Saved on this device',
                      style: AppText.body(12,
                          color: palette.mutedForeground),
                    ),
                  ),
                ],
              ),
            ),
            if (_selecting)
              Checkbox(
                value: selected,
                onChanged: (_) => setState(() {
                  if (selected) {
                    _selectedPaths.remove(file.path);
                  } else {
                    _selectedPaths.add(file.path);
                  }
                }),
              )
            else
              PopupMenuButton<String>(
                icon: Icon(Icons.more_horiz_rounded,
                    color: palette.mutedForeground),
                onSelected: (value) {
                  if (value == 'share') _share(file);
                  if (value == 'open') _openWith(file);
                  if (value == 'rename') _rename(file);
                  if (value == 'delete') _delete(file);
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'share', child: Text('Share')),
                  PopupMenuItem(value: 'open', child: Text('Open with')),
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.onSave,
    required this.onDelete,
  });

  final int count;
  final VoidCallback? onSave;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              '$count selected',
              style: AppText.body(13,
                  weight: FontWeight.w600,
                  color: palette.mutedForeground),
            ),
          ),
          const Spacer(),
          RoundIconButton(
            icon: Icons.delete_outline_rounded,
            tooltip: 'Delete selected',
            color: palette.destructive,
            onPressed: onDelete,
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: onSave,
            icon: const Icon(Icons.save_alt_rounded, size: 18),
            label: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
