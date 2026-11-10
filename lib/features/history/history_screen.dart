import 'package:flutter/material.dart';

import '../../services/history_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_ui.dart';
import '../browser/media_browser_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
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
    final palette = context.palette;
    final service = HistoryService.instance;
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
                    RoundIconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Back',
                      size: 40,
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('History',
                              style: AppText.display(30,
                                  color: palette.foreground)),
                          const SizedBox(height: 2),
                          Text(
                            '${service.entries.length} visited page${service.entries.length == 1 ? '' : 's'}',
                            style: AppText.body(13,
                                color: palette.mutedForeground),
                          ),
                        ],
                      ),
                    ),
                    RoundIconButton(
                      icon: Icons.delete_sweep_outlined,
                      tooltip: 'Clear history',
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
                    hintText: 'Search history',
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
                          ? Icons.history_rounded
                          : Icons.search_off_rounded,
                      title: query.isEmpty ? 'No history yet' : 'No matches',
                      message: query.isEmpty
                          ? 'Pages you open in the Linky browser appear here.'
                          : 'Try a different title or address.',
                    ),
                  )
                else
                  ..._grouped(entries),
              ],
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

  List<Widget> _grouped(List<HistoryEntry> entries) {
    final widgets = <Widget>[];
    String? current;
    for (final entry in entries) {
      final bucket = _bucket(entry.visitedAt);
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

  Widget _entryCard(HistoryEntry entry) {
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
                  const SizedBox(height: 2),
                  Text(_relativeTime(entry.visitedAt),
                      style: AppText.body(11,
                          color: palette.mutedForeground)),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Remove',
              onPressed: () => HistoryService.instance.remove(entry.id),
              icon: Icon(Icons.close_rounded,
                  size: 18, color: palette.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumbnail(HistoryEntry entry) {
    final palette = context.palette;
    final thumbnail = entry.thumbnail;
    final fallback = Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: palette.muted,
        borderRadius: BorderRadius.circular(AppRadius.inner),
      ),
      child: Icon(Icons.public_rounded,
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
