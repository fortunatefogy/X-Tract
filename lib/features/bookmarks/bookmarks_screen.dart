import 'package:flutter/material.dart';

import '../../services/bookmarks_service.dart';
import '../browser/media_browser_screen.dart';

class BookmarksScreen extends StatelessWidget {
  const BookmarksScreen({super.key});

  Future<void> _clear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear bookmarks?'),
        content: const Text('This removes every saved bookmark from Linky.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) await BookmarksService.instance.clear();
  }

  @override
  Widget build(BuildContext context) {
    final service = BookmarksService.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bookmarks'),
        actions: [
          IconButton(
            tooltip: 'Clear bookmarks',
            onPressed: () => _clear(context),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: service,
        builder: (context, _) {
          final entries = service.entries;
          if (entries.isEmpty) {
            return const Center(
              child: Text('Bookmark pages from the Linky browser.'),
            );
          }
          return ListView.separated(
            itemCount: entries.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final entry = entries[index];
              return ListTile(
                leading: _thumbnail(entry, context),
                title: Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  entry.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MediaBrowserScreen(initialUrl: entry.url),
                  ),
                ),
                trailing: IconButton(
                  tooltip: 'Remove bookmark',
                  onPressed: () => service.remove(entry.id),
                  icon: const Icon(Icons.bookmark_remove_outlined),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _thumbnail(BookmarkEntry entry, BuildContext context) {
    final thumbnail = entry.thumbnail;
    if (thumbnail == null || thumbnail.isEmpty) {
      return _fallback(context);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        thumbnail,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(context),
      ),
    );
  }

  Widget _fallback(BuildContext context) => CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: const Icon(Icons.bookmark_outline),
      );
}
