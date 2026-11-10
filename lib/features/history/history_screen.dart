import 'package:flutter/material.dart';

import '../../services/history_service.dart';
import '../browser/media_browser_screen.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  Future<void> _clear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text('This removes every visited page from Linky.'),
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
    if (confirmed == true) await HistoryService.instance.clear();
  }

  String _relativeTime(DateTime time) {
    final difference = DateTime.now().difference(time);
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inHours < 1) return '${difference.inMinutes}m ago';
    if (difference.inDays < 1) return '${difference.inHours}h ago';
    if (difference.inDays < 7) return '${difference.inDays}d ago';
    final local = time.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final service = HistoryService.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          IconButton(
            tooltip: 'Clear history',
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
              child: Text('Pages you open in the Linky browser appear here.'),
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
                  '${entry.url}\n${_relativeTime(entry.visitedAt)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                isThreeLine: true,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MediaBrowserScreen(initialUrl: entry.url),
                  ),
                ),
                trailing: IconButton(
                  tooltip: 'Remove',
                  onPressed: () => service.remove(entry.id),
                  icon: const Icon(Icons.close),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _thumbnail(HistoryEntry entry, BuildContext context) {
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
        child: const Icon(Icons.public),
      );
}
