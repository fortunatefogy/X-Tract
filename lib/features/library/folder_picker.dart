import 'package:flutter/material.dart';

import '../../services/library_folders.dart';
import '../../services/settings_service.dart';
import '../../theme/app_theme.dart';

/// Shows the folder downloads will be saved to and lets the user change it.
/// Used inside download sheets so the destination is visible before saving.
class FolderSelector extends StatefulWidget {
  const FolderSelector({super.key});

  @override
  State<FolderSelector> createState() => _FolderSelectorState();
}

class _FolderSelectorState extends State<FolderSelector> {
  static const _createValue = '\u0000new-folder';

  List<LibraryFolder> _folders = const [];

  @override
  void initState() {
    super.initState();
    LibraryFolders.instance.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    LibraryFolders.instance.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    List<LibraryFolder> folders = const [];
    try {
      folders = await LibraryFolders.instance.all();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _folders = folders);
  }

  Future<void> _select(String value, String current) async {
    if (value == _createValue) {
      await _createFolder(current);
      return;
    }
    await SettingsService.instance.setDownloadFolder(value);
  }

  Future<void> _createFolder(String parent) async {
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
    controller.dispose();
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty || !mounted) return;
    await LibraryFolders.instance.create(trimmed, parent: parent);
    final safe = LibraryFolders.sanitize(trimmed);
    final path = parent.isEmpty ? safe : '$parent/$safe';
    await SettingsService.instance.setDownloadFolder(path);
    await _load();
  }

  Widget _option(
    AppPalette palette, {
    required String label,
    required bool active,
    IconData icon = Icons.folder_rounded,
    double indent = 0,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 17,
          color: active ? AppColors.primary : palette.mutedForeground,
        ),
        SizedBox(width: 8 + indent),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.body(
              13,
              weight: active ? FontWeight.w700 : FontWeight.w500,
              color: palette.foreground,
            ),
          ),
        ),
        if (active)
          Icon(Icons.check_rounded, size: 17, color: AppColors.primary),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (context, _) {
        final palette = context.palette;
        final folder = SettingsService.instance.downloadFolder;
        final label = folder.isEmpty ? 'Library (root)' : folder;
        return PopupMenuButton<String>(
          tooltip: 'Choose download folder',
          position: PopupMenuPosition.under,
          initialValue: folder,
          onOpened: _load,
          onSelected: (value) => _select(value, folder),
          itemBuilder: (menuContext) => [
            PopupMenuItem<String>(
              value: '',
              height: 44,
              child: _option(
                palette,
                label: 'Library (root)',
                active: folder.isEmpty,
                icon: Icons.folder_outlined,
              ),
            ),
            for (final item in _folders)
              PopupMenuItem<String>(
                value: item.relativePath,
                height: 44,
                child: _option(
                  palette,
                  label: item.name,
                  active: item.relativePath == folder,
                  indent: (item.depth - 1) * 14.0,
                ),
              ),
            const PopupMenuDivider(),
            PopupMenuItem<String>(
              value: _createValue,
              height: 44,
              child: _option(
                palette,
                label: 'New folder',
                active: false,
                icon: Icons.create_new_folder_outlined,
              ),
            ),
          ],
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: palette.input,
              borderRadius: BorderRadius.circular(AppRadius.small),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              children: [
                Icon(Icons.folder_outlined, size: 17, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'Save to',
                  style: AppText.body(12, color: palette.mutedForeground),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(12,
                        weight: FontWeight.w700, color: palette.foreground),
                  ),
                ),
                Icon(Icons.expand_more_rounded,
                    size: 18, color: palette.mutedForeground),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Lets the user pick (or create) a destination folder inside the library.
/// Returns the relative folder path ('' for the root) or null if cancelled.
Future<String?> showFolderPicker(
  BuildContext context, {
  String selected = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _FolderPickerDialog(
      initial: LibraryFolders.normalize(selected),
    ),
  );
}

class _FolderPickerDialog extends StatefulWidget {
  const _FolderPickerDialog({required this.initial});

  final String initial;

  @override
  State<_FolderPickerDialog> createState() => _FolderPickerDialogState();
}

class _FolderPickerDialogState extends State<_FolderPickerDialog> {
  late String _selected = widget.initial;
  List<LibraryFolder>? _folders;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final folders = await LibraryFolders.instance.all();
    if (!mounted) return;
    setState(() => _folders = folders);
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
    setState(() => _creating = true);
    final parent = _selected;
    await LibraryFolders.instance.create(name, parent: parent);
    final safe = LibraryFolders.sanitize(name);
    final path = parent.isEmpty ? safe : '$parent/$safe';
    _selected = LibraryFolders.normalize(path);
    await _load();
    if (mounted) setState(() => _creating = false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final folders = _folders;
    return AlertDialog(
      title: const Text('Save to folder'),
      contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: folders == null
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  _option(
                    context,
                    label: 'Library (root)',
                    value: '',
                    icon: Icons.folder_outlined,
                  ),
                  for (final folder in folders)
                    _option(
                      context,
                      label: folder.name,
                      value: folder.relativePath,
                      icon: Icons.folder_rounded,
                      indent: (folder.depth - 1) * 16.0,
                    ),
                  if (folders.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text(
                        'No folders yet. Create one below.',
                        style: AppText.body(12, color: palette.mutedForeground),
                      ),
                    ),
                  const SizedBox(height: 4),
                  TextButton.icon(
                    onPressed: _creating ? null : _createFolder,
                    icon:
                        const Icon(Icons.create_new_folder_outlined, size: 18),
                    label: const Text('New folder'),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selected),
          child: const Text('Save here'),
        ),
      ],
    );
  }

  Widget _option(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    double indent = 0,
  }) {
    final palette = context.palette;
    final active = _selected == value;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.only(left: 12 + indent, right: 8),
      leading: Icon(icon,
          color: active ? AppColors.primary : palette.mutedForeground),
      title: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppText.body(13,
            weight: active ? FontWeight.w700 : FontWeight.w500),
      ),
      trailing: active
          ? Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 20)
          : null,
      onTap: () => setState(() => _selected = value),
    );
  }
}
