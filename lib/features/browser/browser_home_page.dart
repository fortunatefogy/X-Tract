import 'package:flutter/material.dart';

import '../../services/bookmarks_service.dart';
import '../../services/history_service.dart';
import '../../services/settings_service.dart';
import '../../theme/app_theme.dart';

class BrowserHomePage extends StatefulWidget {
  const BrowserHomePage({
    super.key,
    required this.onNavigate,
    required this.onOpenUrl,
  });

  final ValueChanged<String> onNavigate;
  final ValueChanged<String> onOpenUrl;

  @override
  State<BrowserHomePage> createState() => _BrowserHomePageState();
}

class _BrowserHomePageState extends State<BrowserHomePage> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _settings = SettingsService.instance;
  final _bookmarks = BookmarksService.instance;
  final _history = HistoryService.instance;

  static const _tints = [
    Color(0xFF61B795),
    Color(0xFF58A6D6),
    Color(0xFFD8A657),
    Color(0xFFD67C8C),
    Color(0xFF9A8CD6),
    Color(0xFF6FCF97),
  ];

  @override
  void initState() {
    super.initState();
    _settings.addListener(_refresh);
    _bookmarks.addListener(_refresh);
    _history.addListener(_refresh);
  }

  @override
  void dispose() {
    _settings.removeListener(_refresh);
    _bookmarks.removeListener(_refresh);
    _history.removeListener(_refresh);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _submit() {
    final value = _searchController.text.trim();
    if (value.isEmpty) return;
    _searchController.clear();
    _searchFocus.unfocus();
    widget.onNavigate(value);
  }

  Future<void> _pickSearchEngine() async {
    final value = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                'Search engine',
                style: AppText.heading(18, color: context.palette.foreground),
              ),
            ),
            for (final entry in SettingsService.searchEngineLabel.entries)
              ListTile(
                leading: const Icon(Icons.search_rounded),
                title: Text(entry.value),
                trailing: _settings.searchEngine == entry.key
                    ? const Icon(Icons.check_rounded, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(entry.key),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (value != null) await _settings.setSearchEngine(value);
  }

  @override
  Widget build(BuildContext context) {
    final bookmarks = _bookmarks.entries;
    final bookmarkedUrls = bookmarks.map((entry) => entry.url).toSet();
    final frequent = _history
        .topPages(limit: 20)
        .where((entry) => !bookmarkedUrls.contains(entry.url))
        .take(12)
        .toList(growable: false);
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return ColoredBox(
      color: AppColors.forest,
      child: ListView(
        padding: EdgeInsets.fromLTRB(20, 26, 20, 28 + bottomInset),
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.forestSurface,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.forestBorder),
                ),
                child: const Icon(
                  Icons.travel_explore_rounded,
                  color: AppColors.forestAccent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Linky Browser',
                      style: AppText.display(25, color: AppColors.forestText),
                    ),
                    Text(
                      'Search, browse, and save any media',
                      style: AppText.body(12, color: AppColors.forestMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            decoration: BoxDecoration(
              color: AppColors.forestSurface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.forestBorder),
            ),
            child: Row(
              children: [
                const SizedBox(width: 14),
                const Icon(
                  Icons.search_rounded,
                  color: AppColors.forestAccent,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _submit(),
                    style: AppText.body(14, color: AppColors.forestText),
                    cursorColor: AppColors.forestAccent,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'Search or type a website',
                      hintStyle: AppText.body(13, color: AppColors.forestMuted),
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Search',
                  onPressed: _submit,
                  icon: const Icon(
                    Icons.arrow_forward_rounded,
                    color: AppColors.forestAccent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: _pickSearchEngine,
              style: OutlinedButton.styleFrom(
                backgroundColor: AppColors.forestSurface,
                side: const BorderSide(color: AppColors.forestBorder),
                foregroundColor: AppColors.forestText,
                shape: const StadiumBorder(),
              ),
              icon: const Icon(
                Icons.public_rounded,
                size: 16,
                color: AppColors.forestMuted,
              ),
              label: Text(
                'Search with ${_settings.searchEngineName}',
                style: AppText.body(12, color: AppColors.forestMuted),
              ),
            ),
          ),
          const SizedBox(height: 26),
          _sectionHeader(
            icon: Icons.bookmark_rounded,
            title: 'Bookmarks',
            count: bookmarks.length,
          ),
          const SizedBox(height: 10),
          if (bookmarks.isEmpty)
            _emptyHint('Bookmarked pages will appear here.')
          else
            SizedBox(
              height: 104,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: bookmarks.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final entry = bookmarks[index];
                  return _siteTile(
                    url: entry.url,
                    title: entry.title,
                    width: 156,
                  );
                },
              ),
            ),
          const SizedBox(height: 26),
          _sectionHeader(
            icon: Icons.history_rounded,
            title: 'Frequently visited',
            count: frequent.length,
          ),
          const SizedBox(height: 10),
          if (frequent.isEmpty)
            _emptyHint('Sites you visit will appear here.')
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final width = (constraints.maxWidth - 10) / 2;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final entry in frequent)
                      _siteTile(
                        url: entry.url,
                        title: entry.title,
                        width: width,
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required int count,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.forestAccent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: AppText.body(14,
                weight: FontWeight.w800, color: AppColors.forestText),
          ),
        ),
        Text(
          '$count',
          style: AppText.body(11,
              weight: FontWeight.w700, color: AppColors.forestMuted),
        ),
      ],
    );
  }

  Widget _emptyHint(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.forestSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.forestBorder),
      ),
      child: Text(
        message,
        style: AppText.body(12, color: AppColors.forestMuted),
      ),
    );
  }

  Widget _siteTile({
    required String url,
    required String title,
    required double width,
  }) {
    final uri = Uri.tryParse(url);
    final host = (uri?.host ?? url).replaceFirst(RegExp(r'^www\.'), '');
    final label = title.trim().isNotEmpty ? title.trim() : host;
    final initial = label.isNotEmpty ? label[0].toUpperCase() : '?';
    final tint = _tints[label.hashCode.abs() % _tints.length];
    return SizedBox(
      width: width,
      height: 104,
      child: Material(
        color: AppColors.forestSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.forestBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => widget.onOpenUrl(url),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    initial,
                    style:
                        AppText.body(13, weight: FontWeight.w800, color: tint),
                  ),
                ),
                const Spacer(),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(12,
                      weight: FontWeight.w700, color: AppColors.forestText),
                ),
                const SizedBox(height: 2),
                Text(
                  host,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(10, color: AppColors.forestMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
