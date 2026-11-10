import 'package:flutter/material.dart';

import '../../services/bookmarks_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_ui.dart';
import '../browser/media_browser_screen.dart';

class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _clear() async {
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
    final palette = context.palette;
    final service = BookmarksService.instance;
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: service,
          builder: (context, _) {
            final query = _searchController.text.trim().toLowerCase();
            final entries = service.entries
                .where((entry) =>
                    query.isEmpty ||
                    entry.title.toLowerCase().contains(query) ||
                    entry.url.toLowerCase().contains(query))
                .toList(growable: false);
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Bookmarks',
                              style: AppText.display(30,
                                  color: palette.foreground)),
                          const SizedBox(height: 2),
                          Text(
                            '${service.entries.length} saved page${service.entries.length == 1 ? '' : 's'}',
                            style: AppText.body(13,
                                color: palette.mutedForeground),
                          ),
                        ],
                      ),
                    ),
                    RoundIconButton(
                      icon: Icons.delete_sweep_outlined,
                      tooltip: 'Clear bookmarks',
                      color: palette.destructive,
                      onPressed: service.entries.isEmpty ? null : _clear,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search bookmarks',
                    prefixIcon: Icon(Icons.search_rounded,
                        size: 20, color: palette.mutedForeground),
                  ),
                ),
                const SizedBox(height: 18),
                if (entries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: EmptyState(
                      icon: query.isEmpty
                          ? Icons.bookmark_border_rounded
                          : Icons.search_off_rounded,
                      title:
                          query.isEmpty ? 'No bookmarks yet' : 'No matches',
                      message: query.isEmpty
                          ? 'Bookmark pages from the Linky browser to keep them here.'
                          : 'Try a different title or address.',
                    ),
                  )
                else
                  for (final entry in entries) _entryCard(entry),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _entryCard(BookmarkEntry entry) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MediaBrowserScreen(initialUrl: entry.url),
          ),
        ),
        child: Row(
          children: [
            _thumbnail(entry),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(14, weight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(entry.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(12,
                          color: palette.mutedForeground)),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Remove bookmark',
              onPressed: () => BookmarksService.instance.remove(entry.id),
              icon: Icon(Icons.bookmark_remove_outlined,
                  size: 18, color: palette.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumbnail(BookmarkEntry entry) {
    final palette = context.palette;
    final thumbnail = entry.thumbnail;
    final fallback = Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: palette.muted,
        borderRadius: BorderRadius.circular(AppRadius.inner),
      ),
      child: Icon(Icons.bookmark_rounded,
          size: 22, color: palette.mutedForeground),
    );
    if (thumbnail == null || thumbnail.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.inner),
      child: Image.network(
        thumbnail,
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}
