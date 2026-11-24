import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/biometric_auth.dart';
import '../../services/device_media_channel.dart';
import '../../services/device_resources.dart';
import '../../services/download_service.dart';
import '../../services/library_folders.dart';
import '../../services/library_lock.dart';
import '../../services/media_downloader.dart';
import '../../services/settings_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/media_thumbnail.dart';
import '../downloads/video_playback_screen.dart';
import 'folder_picker.dart';
import 'library_media_viewer.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryData {
  const _LibraryData({
    required this.files,
    required this.folders,
    required this.totalBytes,
    required this.bytesByType,
    required this.sizeByPath,
    required this.freeBytes,
    required this.deviceBytes,
  });

  final List<File> files;
  final List<LibraryFolder> folders;
  final int totalBytes;
  final Map<String, int> bytesByType;
  final Map<String, int> sizeByPath;
  final int freeBytes;
  final int deviceBytes;
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _deviceMedia = DeviceMediaChannel();
  final _searchController = TextEditingController();
  final Set<String> _selectedPaths = {};
  late Future<_LibraryData> _data;
  bool _selecting = false;
  String _filter = 'all';
  String _folder = '';
  String _completedSignature = '';
  bool _locked = false;
  bool _authenticating = false;
  String? _authError;

  @override
  void initState() {
    super.initState();
    _data = _loadData();
    DownloadService.instance.addListener(_onDownloadsChanged);
    SettingsService.instance.addListener(_onSettingsChanged);
    LibraryLockController.instance.addListener(_onLockRequested);
    _searchController.addListener(() => setState(() {}));
    if (SettingsService.instance.libraryLockEnabled) {
      _locked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
    }
  }

  @override
  void dispose() {
    DownloadService.instance.removeListener(_onDownloadsChanged);
    SettingsService.instance.removeListener(_onSettingsChanged);
    LibraryLockController.instance.removeListener(_onLockRequested);
    _searchController.dispose();
    super.dispose();
  }

  void _onLockRequested() {
    if (!mounted || !SettingsService.instance.libraryLockEnabled) return;
    if (!LibraryLockController.instance.active) return;
    if (_authenticating) return;
    if (!_locked) setState(() => _locked = true);
    _authenticate();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    if (!SettingsService.instance.libraryLockEnabled && _locked) {
      setState(() => _locked = false);
    } else {
      setState(() {});
    }
  }

  Future<void> _authenticate() async {
    if (_authenticating || !mounted) return;
    if (!SettingsService.instance.libraryLockEnabled) {
      if (_locked) setState(() => _locked = false);
      return;
    }
    if (!LibraryLockController.instance.active) return;
    _authenticating = true;
    LibraryLockController.instance.authenticating = true;
    try {
      // Let the tab transition finish; a prompt launched while the activity is
      // still switching focus is often dismissed on the first attempt.
      await Future<void>.delayed(const Duration(milliseconds: 320));
      // The user may have left the Library while we were waiting; never show a
      // prompt on top of another screen.
      if (!mounted ||
          !SettingsService.instance.libraryLockEnabled ||
          !LibraryLockController.instance.active) {
        return;
      }
      final outcome = await BiometricAuth.authenticate('Unlock your Library');
      if (!mounted) return;
      if (outcome == BiometricOutcome.success) {
        setState(() {
          _locked = false;
          _authError = null;
        });
      } else if (outcome == BiometricOutcome.unavailable) {
        setState(() => _authError =
            'No fingerprint, face, or screen lock is set up on this device. '
                'Set a screen lock in system settings, then tap Unlock.');
      }
    } finally {
      _authenticating = false;
      LibraryLockController.instance.authenticating = false;
    }
  }

  void _onDownloadsChanged() {
    final signature = DownloadService.instance.records
        .where((record) => record.state == DownloadState.complete)
        .map((record) => record.taskId)
        .join(',');
    if (!mounted || signature == _completedSignature) return;
    setState(() {
      _completedSignature = signature;
      _data = _loadData();
    });
  }

  Future<_LibraryData> _loadData() async {
    final directory = await LibraryFolders.instance.directoryFor(_folder);
    final folders = await LibraryFolders.instance.children(_folder);
    final files = <File>[];
    if (await directory.exists()) {
      try {
        files.addAll(
          await directory
              .list(followLinks: false)
              .where((entity) => entity is File)
              .cast<File>()
              .where((file) {
            final name = file.uri.pathSegments.last;
            return !name.startsWith('.') && !name.startsWith('linky_');
          }).toList(),
        );
      } on FileSystemException {
        // Keep whatever was read before the directory became unavailable.
      }
    }
    final modified = <File, DateTime>{};
    var total = 0;
    final byType = <String, int>{};
    final sizeByPath = <String, int>{};
    final stats = await Future.wait(files.map((file) async {
      try {
        return await file.stat();
      } on FileSystemException {
        return null;
      }
    }));
    final available = <File>[];
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      final stat = stats[i];
      if (stat == null) continue;
      modified[file] = stat.modified;
      final size = stat.size;
      total += size;
      sizeByPath[file.path] = size;
      final type = _category(file.uri.pathSegments.last);
      byType[type] = (byType[type] ?? 0) + size;
      available.add(file);
    }
    available.sort((a, b) => modified[b]!.compareTo(modified[a]!));
    final info = await DeviceResources.instance.storageInfo();
    return _LibraryData(
      files: available,
      folders: folders,
      totalBytes: total,
      bytesByType: byType,
      sizeByPath: sizeByPath,
      freeBytes: info?.freeBytes ?? 0,
      deviceBytes: info?.totalBytes ?? 0,
    );
  }

  Future<bool> _confirm(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.palette.destructive,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _delete(File file) async {
    final name = file.uri.pathSegments.last;
    final confirmed =
        await _confirm('Delete file?', '"$name" will be permanently removed.');
    if (!confirmed || !mounted) return;
    try {
      if (await file.exists()) await file.delete();
      if (!mounted) return;
      setState(() {
        _selectedPaths.remove(file.path);
        _data = _loadData();
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

  Future<void> _shareSelected() async {
    final paths = _selectedPaths
        .where((path) => File(path).existsSync())
        .toList(growable: false);
    if (paths.isEmpty) {
      _toast('No selected files are available to share.');
      return;
    }
    try {
      await _deviceMedia.shareFiles(paths);
    } catch (error) {
      _toast('Could not share the files: $error');
      return;
    }
    if (!mounted) return;
    setState(() {
      _selectedPaths.clear();
      _selecting = false;
    });
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
        _data = _loadData();
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

  Future<void> _deleteSelected() async {
    final selected = _selectedPaths
        .map((path) => File(path))
        .where((file) => file.existsSync())
        .toList(growable: false);
    if (selected.isEmpty) return;
    final confirmed = await _confirm(
      'Delete ${selected.length} file${selected.length == 1 ? '' : 's'}?',
      'The selected file${selected.length == 1 ? '' : 's'} will be permanently removed.',
    );
    if (!confirmed || !mounted) return;
    var deleted = 0;
    var failed = 0;
    for (final file in selected) {
      try {
        await file.delete();
        deleted++;
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() {
      _selectedPaths.clear();
      _selecting = false;
      _data = _loadData();
    });
    _toast(failed == 0
        ? 'Deleted $deleted file${deleted == 1 ? '' : 's'}'
        : 'Deleted $deleted; $failed could not be removed');
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _reload() => setState(() => _data = _loadData());

  void _openFolder(LibraryFolder folder) {
    setState(() {
      _folder = folder.relativePath;
      _filter = 'all';
      _selectedPaths.clear();
      _selecting = false;
      _data = _loadData();
    });
  }

  void _goUp() {
    final parent = _folder.contains('/')
        ? _folder.substring(0, _folder.lastIndexOf('/'))
        : '';
    setState(() {
      _folder = parent;
      _filter = 'all';
      _selectedPaths.clear();
      _selecting = false;
      _data = _loadData();
    });
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Folder name'),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      await LibraryFolders.instance.create(name, parent: _folder);
      if (!mounted) return;
      _reload();
      _toast('Folder created');
    } on FileSystemException catch (error) {
      _toast('Could not create folder: ${error.message}');
    }
  }

  Future<void> _renameFolder(LibraryFolder folder) async {
    final controller = TextEditingController(text: folder.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Folder name'),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
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
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      await LibraryFolders.instance.rename(folder, name);
      if (!mounted) return;
      _reload();
      _toast('Folder renamed');
    } on FileSystemException catch (error) {
      _toast('Could not rename folder: ${error.message}');
    }
  }

  Future<void> _deleteFolder(LibraryFolder folder) async {
    final empty = await LibraryFolders.instance.isEmpty(folder);
    if (!mounted) return;
    final confirmed = await _confirm(
      'Delete folder?',
      empty
          ? '"${folder.name}" will be removed.'
          : '"${folder.name}" and everything inside it will be permanently '
              'removed.',
    );
    if (confirmed != true || !mounted) return;
    try {
      await LibraryFolders.instance.delete(folder);
      if (!mounted) return;
      _reload();
      _toast('Folder deleted');
    } on FileSystemException catch (error) {
      _toast('Could not delete folder: ${error.message}');
    }
  }

  Future<void> _folderOptions(LibraryFolder folder) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline_rounded),
              title: const Text('Rename folder'),
              onTap: () => Navigator.of(sheetContext).pop('rename'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded,
                  color: context.palette.destructive),
              title: Text('Delete folder',
                  style: TextStyle(color: context.palette.destructive)),
              onTap: () => Navigator.of(sheetContext).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (action == 'rename') await _renameFolder(folder);
    if (action == 'delete') await _deleteFolder(folder);
  }

  Future<void> _moveFile(File file) async {
    final target = await showFolderPicker(context, selected: _folder);
    if (target == null || target == _folder || !mounted) return;
    try {
      await LibraryFolders.instance.moveFile(file, target);
      if (!mounted) return;
      setState(() {
        _selectedPaths.remove(file.path);
        _data = _loadData();
      });
      _toast('File moved');
    } on FileSystemException catch (error) {
      _toast('Could not move the file: ${error.message}');
    }
  }

  Future<void> _moveSelected() async {
    final paths = _selectedPaths
        .where((path) => File(path).existsSync())
        .toList(growable: false);
    if (paths.isEmpty) return;
    final target = await showFolderPicker(context, selected: _folder);
    if (target == null || target == _folder || !mounted) return;
    var moved = 0;
    var failed = 0;
    for (final path in paths) {
      try {
        await LibraryFolders.instance.moveFile(File(path), target);
        moved++;
      } on FileSystemException {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() {
      _selectedPaths.clear();
      _selecting = false;
      _data = _loadData();
    });
    _toast(failed == 0
        ? 'Moved $moved file${moved == 1 ? '' : 's'}'
        : 'Moved $moved; $failed could not be moved');
  }

  void _play(File file) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VideoPlaybackScreen(file: file),
      ),
    );
  }

  void _openViewer(List<File> files, int index) {
    if (files.isEmpty) return;
    final safeIndex = index.clamp(0, files.length - 1);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LibraryMediaViewer(
          files: files,
          initialIndex: safeIndex,
        ),
      ),
    );
  }

  String _category(String name) {
    final lower = name.toLowerCase();
    if (RegExp(r'\.(jpe?g|png|gif|webp|avif|bmp|heic|heif)$').hasMatch(lower)) {
      return 'image';
    }
    if (RegExp(r'\.(mp4|m4v|webm|mov|3gp|mkv|avi)$').hasMatch(lower)) {
      return 'video';
    }
    if (RegExp(
      r'\.(mp3|m4a|aac|ogg|oga|opus|wav|flac|weba)$',
    ).hasMatch(lower)) {
      return 'audio';
    }
    return 'document';
  }

  bool _isImage(String name) => _category(name) == 'image';
  bool _isVideo(String name) => _category(name) == 'video';
  bool _isAudio(String name) => _category(name) == 'audio';

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  void _toggleSelect(File file) {
    setState(() {
      _selecting = true;
      if (_selectedPaths.contains(file.path)) {
        _selectedPaths.remove(file.path);
        if (_selectedPaths.isEmpty) _selecting = false;
      } else {
        _selectedPaths.add(file.path);
      }
    });
  }

  Widget _lockedView(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_rounded, size: 64, color: palette.foreground),
                const SizedBox(height: 18),
                Text('Library is locked',
                    style: AppText.display(24, color: palette.foreground)),
                const SizedBox(height: 6),
                Text(
                  'Confirm your fingerprint or screen lock to view your '
                  'saved media.',
                  textAlign: TextAlign.center,
                  style: AppText.body(13, color: palette.mutedForeground),
                ),
                if (_authError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _authError!,
                    textAlign: TextAlign.center,
                    style: AppText.body(11, color: palette.destructive),
                  ),
                ],
                const SizedBox(height: 26),
                FilledButton.icon(
                  onPressed: _authenticate,
                  icon: const Icon(Icons.lock_open_rounded),
                  label: const Text('Unlock'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (_locked && SettingsService.instance.libraryLockEnabled) {
      return _lockedView(context);
    }
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: FutureBuilder<_LibraryData>(
          future: _data,
          builder: (context, snapshot) {
            final loading = snapshot.connectionState != ConnectionState.done;
            final data = snapshot.data ??
                const _LibraryData(
                  files: [],
                  folders: [],
                  totalBytes: 0,
                  bytesByType: {},
                  sizeByPath: {},
                  freeBytes: 0,
                  deviceBytes: 0,
                );
            final query = _searchController.text.trim().toLowerCase();
            final files = data.files.where((file) {
              final name = file.uri.pathSegments.last.toLowerCase();
              if (query.isNotEmpty && !name.contains(query)) return false;
              if (_filter != 'all' && _category(name) != _filter) {
                return false;
              }
              return true;
            }).toList(growable: false);
            final selectedBytes = _selectedPaths.fold<int>(
              0,
              (sum, path) => sum + (data.sizeByPath[path] ?? 0),
            );
            final allVisibleSelected = files.isNotEmpty &&
                files.every((file) => _selectedPaths.contains(file.path));
            void toggleSelectAll() {
              if (files.isEmpty) return;
              setState(() {
                _selecting = true;
                if (allVisibleSelected) {
                  for (final file in files) {
                    _selectedPaths.remove(file.path);
                  }
                  if (_selectedPaths.isEmpty) _selecting = false;
                } else {
                  _selectedPaths.addAll(files.map((file) => file.path));
                }
              });
            }

            return Stack(
              children: [
                RefreshIndicator(
                  onRefresh: () async {
                    setState(() => _data = _loadData());
                    await _data;
                  },
                  child: CustomScrollView(
                    key: const PageStorageKey('library-scroll'),
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate([
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_folder.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        right: 6, top: 2),
                                    child: RoundIconButton(
                                      icon: Icons.arrow_back_rounded,
                                      tooltip: 'Back',
                                      onPressed: _goUp,
                                    ),
                                  ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('Library',
                                          style: AppText.display(30,
                                              color: palette.foreground)),
                                      const SizedBox(height: 2),
                                      Text(
                                        _folder.isEmpty
                                            ? 'Your saved media, available offline.'
                                            : _folder.split('/').join(' / '),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppText.body(13,
                                            color: palette.mutedForeground),
                                      ),
                                    ],
                                  ),
                                ),
                                if (!_selecting)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: RoundIconButton(
                                      icon: Icons.create_new_folder_outlined,
                                      tooltip: 'New folder',
                                      onPressed: _createFolder,
                                    ),
                                  ),
                                if (_selecting)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: RoundIconButton(
                                      icon: allVisibleSelected
                                          ? Icons.deselect_rounded
                                          : Icons.select_all_rounded,
                                      tooltip: allVisibleSelected
                                          ? 'Deselect all'
                                          : 'Select all',
                                      onPressed: files.isEmpty
                                          ? null
                                          : toggleSelectAll,
                                    ),
                                  ),
                                RoundIconButton(
                                  icon: _selecting
                                      ? Icons.check_rounded
                                      : Icons.checklist_rounded,
                                  tooltip: _selecting
                                      ? 'Done selecting'
                                      : 'Select files',
                                  filled: _selecting,
                                  onPressed: () => setState(() {
                                    _selecting = !_selecting;
                                    if (!_selecting) _selectedPaths.clear();
                                  }),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _StorageCard(data: data),
                            const SizedBox(height: 14),
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
                            const SizedBox(height: 14),
                            _FilterPills(
                              data: data,
                              value: _filter,
                              onChanged: (value) =>
                                  setState(() => _filter = value),
                            ),
                            if (_filter == 'all' && data.folders.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Text('Folders',
                                  style: AppText.label(11,
                                      color: palette.mutedForeground)),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  for (final folder in data.folders)
                                    _folderChip(folder),
                                ],
                              ),
                            ],
                            const SizedBox(height: 14),
                          ]),
                        ),
                      ),
                      if (loading)
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 48),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        )
                      else if (files.isEmpty &&
                          (_filter != 'all' || data.folders.isEmpty))
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          sliver: SliverToBoxAdapter(
                            child: _empty(query.isNotEmpty),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          sliver: SliverList.builder(
                            itemCount: files.length + 1,
                            itemBuilder: (context, index) {
                              if (index == 0) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${files.length} file${files.length == 1 ? '' : 's'}',
                                      style: AppText.label(11,
                                          color: palette.mutedForeground),
                                    ),
                                    const SizedBox(height: 10),
                                  ],
                                );
                              }
                              final file = files[index - 1];
                              return _fileCard(
                                file,
                                data.sizeByPath[file.path],
                                files,
                                index - 1,
                              );
                            },
                          ),
                        ),
                      SliverToBoxAdapter(
                        child: SizedBox(height: _selecting ? 120 : 32),
                      ),
                    ],
                  ),
                ),
                if (_selecting)
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 16,
                    child: _SelectionBar(
                      count: _selectedPaths.length,
                      sizeLabel: selectedBytes > 0
                          ? _formatBytes(selectedBytes)
                          : null,
                      allSelected: allVisibleSelected,
                      onSelectAll: files.isEmpty ? null : toggleSelectAll,
                      onSave: _selectedPaths.isEmpty
                          ? null
                          : _saveSelectedToGallery,
                       onShare: _selectedPaths.isEmpty ? null : _shareSelected,
                       onMove: _selectedPaths.isEmpty ? null : _moveSelected,
                       onDelete: _selectedPaths.isEmpty ? null : _deleteSelected,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _folderChip(LibraryFolder folder) {
    final palette = context.palette;
    return GestureDetector(
      onTap: () => _openFolder(folder),
      onLongPress: () => _folderOptions(folder),
      child: Container(
        width: 150,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          children: [
            Icon(Icons.folder_rounded, size: 22, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                folder.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(12, weight: FontWeight.w700),
              ),
            ),
            GestureDetector(
              onTap: () => _folderOptions(folder),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(Icons.more_vert_rounded,
                    size: 16, color: palette.mutedForeground),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty(bool searching) => Padding(
        padding: const EdgeInsets.only(top: 24),
        child: EmptyState(
          icon:
              searching ? Icons.search_off_rounded : Icons.folder_open_rounded,
          title: searching ? 'No matches' : 'Nothing saved yet',
          message: searching
              ? 'Try a different file name or filter.'
              : 'Media you download will live here and stay available offline.',
        ),
      );

  Widget _fileCard(
    File file,
    int? size,
    List<File> files,
    int position,
  ) {
    final palette = context.palette;
    final name = file.uri.pathSegments.last;
    final isImage = _isImage(name);
    final isVideo = _isVideo(name);
    final isAudio = _isAudio(name);
    final selected = _selectedPaths.contains(file.path);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        color: selected ? palette.accent : null,
        onTap: _selecting
            ? () => _toggleSelect(file)
            : () => _openViewer(files, position),
        onLongPress:
            _selecting ? null : () => _toggleSelect(file),
        child: Row(
          children: [
            if (_selecting)
              GestureDetector(
                onTap: () => _toggleSelect(file),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding:
                      const EdgeInsets.only(top: 12, bottom: 12, right: 10),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: selected ? AppColors.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                        color: selected ? AppColors.primary : palette.border,
                        width: 1.6,
                      ),
                    ),
                    child: selected
                        ? const Icon(Icons.check_rounded,
                            size: 14, color: Colors.white)
                        : null,
                  ),
                ),
              ),
            MediaThumbnail(
              type: isImage
                  ? 'image'
                  : isVideo
                      ? 'video'
                      : isAudio
                          ? 'audio'
                          : 'document',
              file: isImage || isVideo ? file : null,
              size: 52,
              fallback: Icon(
                isVideo
                    ? Icons.movie_outlined
                    : isImage
                        ? Icons.image_outlined
                        : isAudio
                            ? Icons.music_note_rounded
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
                    style: AppText.body(13, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    size != null
                        ? '${_formatBytes(size)} · '
                            '${isVideo ? 'Video' : isImage ? 'Image' : isAudio ? 'Audio' : 'File'}'
                        : 'Saved on this device',
                    style: AppText.body(11, color: palette.mutedForeground),
                  ),
                ],
              ),
            ),
            if (!_selecting)
              PopupMenuButton<String>(
                icon: Icon(Icons.more_horiz_rounded,
                    color: palette.mutedForeground),
                onSelected: (value) {
                  if (value == 'play') _play(file);
                  if (value == 'share') _share(file);
                  if (value == 'open') _openWith(file);
                  if (value == 'move') _moveFile(file);
                  if (value == 'rename') _rename(file);
                  if (value == 'delete') _delete(file);
                },
                itemBuilder: (context) => [
                  if (isAudio || isVideo)
                    const PopupMenuItem(value: 'play', child: Text('Play')),
                  const PopupMenuItem(value: 'share', child: Text('Share')),
                  const PopupMenuItem(value: 'open', child: Text('Open with')),
                  const PopupMenuItem(
                      value: 'move', child: Text('Move to folder')),
                  const PopupMenuItem(value: 'rename', child: Text('Rename')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _StorageCard extends StatelessWidget {
  const _StorageCard({required this.data});

  final _LibraryData data;

  String _fmt(int bytes) {
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
    final total = data.totalBytes;
    final hasDevice = data.deviceBytes > 0;
    final segments = <(String, int, Color)>[
      ('video', data.bytesByType['video'] ?? 0, AppColors.primary),
      (
        'audio',
        data.bytesByType['audio'] ?? 0,
        AppColors.primary.withValues(alpha: 0.65)
      ),
      (
        'image',
        data.bytesByType['image'] ?? 0,
        AppColors.primary.withValues(alpha: 0.35)
      ),
      ('document', data.bytesByType['document'] ?? 0, AppColors.amber),
    ];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sd_storage_outlined,
                  size: 18, color: palette.accentForeground),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Local storage',
                    style: AppText.body(13, weight: FontWeight.w700)),
              ),
              Text(
                hasDevice
                    ? '${_fmt(total)} of ${_fmt(data.deviceBytes)}'
                    : '${_fmt(total)} saved',
                style: AppText.body(11, color: palette.mutedForeground),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: SizedBox(
              height: 10,
              child: total <= 0
                  ? ColoredBox(color: palette.secondary)
                  : Row(
                      children: [
                        for (final segment in segments)
                          if (segment.$2 > 0)
                            Expanded(
                              flex: segment.$2,
                              child: ColoredBox(color: segment.$3),
                            ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${data.files.length} file${data.files.length == 1 ? '' : 's'} · ${_fmt(total)} used',
                  style: AppText.body(11, color: palette.mutedForeground),
                ),
              ),
              if (hasDevice)
                Text(
                  '${_fmt(data.freeBytes)} free',
                  style: AppText.body(11,
                      weight: FontWeight.w700, color: palette.accentForeground),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterPills extends StatelessWidget {
  const _FilterPills({
    required this.data,
    required this.value,
    required this.onChanged,
  });

  final _LibraryData data;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final counts = <String, int>{
      'video': 0,
      'audio': 0,
      'image': 0,
      'document': 0,
    };
    for (final file in data.files) {
      final type = _typeOf(file.uri.pathSegments.last);
      counts[type] = (counts[type] ?? 0) + 1;
    }
    final options = <(String, String, int)>[
      ('all', 'All', data.files.length),
      ('video', 'Videos', counts['video'] ?? 0),
      ('audio', 'Audio', counts['audio'] ?? 0),
      ('image', 'Images', counts['image'] ?? 0),
      ('document', 'Docs', counts['document'] ?? 0),
    ];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final option = options[index];
          final selected = value == option.$1;
          return GestureDetector(
            onTap: () => onChanged(option.$1),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : palette.card,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(
                  color: selected ? AppColors.primary : palette.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    option.$2,
                    style: AppText.body(12,
                        weight: selected ? FontWeight.w700 : FontWeight.w600,
                        color: selected ? Colors.white : palette.foreground),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: selected
                          ? Colors.white.withValues(alpha: 0.22)
                          : palette.accent,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      '${option.$3}',
                      style: AppText.body(10,
                          weight: FontWeight.w700,
                          color: selected
                              ? Colors.white
                              : palette.accentForeground),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _typeOf(String name) {
    final lower = name.toLowerCase();
    if (RegExp(r'\.(jpe?g|png|gif|webp|avif|bmp|heic|heif)$').hasMatch(lower)) {
      return 'image';
    }
    if (RegExp(r'\.(mp4|m4v|webm|mov|3gp|mkv|avi)$').hasMatch(lower)) {
      return 'video';
    }
    if (RegExp(
      r'\.(mp3|m4a|aac|ogg|oga|opus|wav|flac|weba)$',
    ).hasMatch(lower)) {
      return 'audio';
    }
    return 'document';
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.sizeLabel,
    required this.allSelected,
    required this.onSelectAll,
    required this.onSave,
    required this.onShare,
    required this.onMove,
    required this.onDelete,
  });

  final int count;
  final String? sizeLabel;
  final bool allSelected;
  final VoidCallback? onSelectAll;
  final VoidCallback? onSave;
  final VoidCallback? onShare;
  final VoidCallback? onMove;
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
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(left: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: Text('$count',
                style: AppText.body(11,
                    weight: FontWeight.w800, color: Colors.white)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              sizeLabel != null
                  ? '$count selected ($sizeLabel)'
                  : '$count selected',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.body(12, weight: FontWeight.w700),
            ),
          ),
          RoundIconButton(
            icon:
                allSelected ? Icons.deselect_rounded : Icons.select_all_rounded,
            tooltip: allSelected ? 'Deselect all' : 'Select all',
            size: 38,
            onPressed: onSelectAll,
          ),
          const SizedBox(width: 4),
          RoundIconButton(
            icon: Icons.photo_library_outlined,
            tooltip: 'Save to Gallery',
            size: 38,
            onPressed: onSave,
          ),
          const SizedBox(width: 4),
          RoundIconButton(
            icon: Icons.drive_file_move_outline,
            tooltip: 'Move to folder',
            size: 38,
            onPressed: onMove,
          ),
          const SizedBox(width: 4),
          RoundIconButton(
            icon: Icons.share_rounded,
            tooltip: 'Share selected',
            size: 38,
            onPressed: onShare,
          ),
          const SizedBox(width: 4),
          RoundIconButton(
            icon: Icons.delete_outline_rounded,
            tooltip: 'Delete selected',
            size: 38,
            color: palette.destructive,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
