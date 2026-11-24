import 'package:flutter/material.dart';

import '../../services/library_folders.dart';
import '../../services/settings_service.dart';
import '../../theme/app_theme.dart';

/// Shows the folder downloads will be saved to and lets the user change it.
/// Used inside download sheets so the destination is visible before saving.
class FolderSelector extends StatelessWidget {
  const FolderSelector({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (context, _) {
        final palette = context.palette;
        final folder = SettingsService.instance.downloadFolder;
        final label = folder.isEmpty ? 'Library (root)' : folder;
        return InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: () async {
            final picked = await showFolderPicker(context, selected: folder);
            if (picked != null) {
              await SettingsService.instance.setDownloadFolder(picked);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.folder_outlined,
                    size: 17, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Save to: $label',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(12,
                        weight: FontWeight.w600,
                        color: palette.mutedForeground),
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
                        style: AppText.body(12,
                            color: palette.mutedForeground),
                      ),
                    ),
                  const SizedBox(height: 4),
                  TextButton.icon(
                    onPressed: _creating ? null : _createFolder,
                    icon: const Icon(Icons.create_new_folder_outlined, size: 18),
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
          ? Icon(Icons.check_circle_rounded,
              color: AppColors.primary, size: 20)
          : null,
      onTap: () => setState(() => _selected = value),
    );
  }
}
