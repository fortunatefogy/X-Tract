import 'package:hugeicons/hugeicons.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  Timer? _searchDebounce;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final value = _searchController.text.trim().toLowerCase();
    if (value == _query) return;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted || value == _query) return;
      setState(() => _query = value);
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear bookmarks?'),
        content: const Text('This removes every saved bookmark from Comet.'),
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
            final query = _query;
            final entries = service.entries
                .where((entry) =>
                    query.isEmpty ||
                    entry.title.toLowerCase().contains(query) ||
                    entry.url.toLowerCase().contains(query))
                .toList(growable: false);
            final rows = <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RoundIconButton(
                    icon: HugeIcons.strokeRoundedArrowLeft01,
                    tooltip: 'Back',
                    size: 40,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Bookmarks',
                            style:
                                AppText.display(30, color: palette.foreground)),
                        const SizedBox(height: 2),
                        Text(
                          '${entries.length} saved page${entries.length == 1 ? '' : 's'}'
                          '${query.isNotEmpty && entries.length != service.entries.length ? ' of ${service.entries.length}' : ''}',
                          style:
                              AppText.body(13, color: palette.mutedForeground),
                        ),
                      ],
                    ),
                  ),
                  RoundIconButton(
                    icon: HugeIcons.strokeRoundedDelete02,
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
                  prefixIcon: HugeIcon(icon: HugeIcons.strokeRoundedSearch01,
                      size: 20, color: palette.mutedForeground),
                ),
              ),
              const SizedBox(height: 18),
              if (entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: EmptyState(
                    icon: query.isEmpty
                        ? HugeIcons.strokeRoundedBookmark01
                        : HugeIcons.strokeRoundedSearchRemove,
                    title: query.isEmpty ? 'No bookmarks yet' : 'No matches',
                    message: query.isEmpty
                        ? 'Bookmark pages from the Comet browser to keep them here.'
                        : 'Try a different title or address.',
                  ),
                )
              else
                ..._grouped(entries),
            ];
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              itemCount: rows.length,
              itemBuilder: (context, index) => rows[index],
            );
          },
        ),
      ),
    );
  }

  String _bucket(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final local = time.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return 'This week';
    return 'Earlier';
  }

  List<Widget> _grouped(List<BookmarkEntry> entries) {
    final widgets = <Widget>[];
    String? current;
    for (final entry in entries) {
      final bucket = _bucket(entry.createdAt);
      if (bucket != current) {
        current = bucket;
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 4),
          child: SectionLabel(bucket),
        ));
      }
      widgets.add(_entryCard(entry));
    }
    return widgets;
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
                      style: AppText.body(12, color: palette.mutedForeground)),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Remove bookmark',
              onPressed: () {
                HapticFeedback.selectionClick();
                BookmarksService.instance.remove(entry.id);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Bookmark removed'),
                    action: SnackBarAction(
                      label: 'Undo',
                      onPressed: () => BookmarksService.instance.restore(entry),
                    ),
                  ),
                );
              },
              icon: HugeIcon(icon: HugeIcons.strokeRoundedBookmarkRemove01,
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
        color: palette.accent,
        borderRadius: BorderRadius.circular(AppRadius.inner),
      ),
      child: HugeIcon(icon: HugeIcons.strokeRoundedBookmark02,
          size: 22, color: palette.accentForeground),
    );
    if (thumbnail == null || thumbnail.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.inner),
      child: Image.network(
        thumbnail,
        width: 52,
        height: 52,
        cacheWidth: (52 * MediaQuery.devicePixelRatioOf(context)).round(),
        filterQuality: FilterQuality.medium,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}
