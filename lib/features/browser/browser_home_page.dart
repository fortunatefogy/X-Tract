import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../services/bookmarks_service.dart';
import '../../services/browser_session_service.dart';
import '../../services/history_service.dart';
import '../../services/settings_service.dart';
import '../../services/suggestions_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/site_favicon.dart';

class BrowserHomePage extends StatefulWidget {
  const BrowserHomePage({
    super.key,
    required this.onNavigate,
    required this.onOpenUrl,
    this.onOpenInNewTab,
  });

  final ValueChanged<String> onNavigate;
  final ValueChanged<String> onOpenUrl;
  final ValueChanged<String>? onOpenInNewTab;

  @override
  State<BrowserHomePage> createState() => _BrowserHomePageState();
}

class _BrowserHomePageState extends State<BrowserHomePage> {
  static const _tints = [
    Color(0xFFB9A4FF),
    Color(0xFF7FD8E8),
    Color(0xFFF4B860),
    Color(0xFFE98BA8),
    Color(0xFF9F7BFF),
    Color(0xFF74D9B6),
  ];

  final _bookmarks = BookmarksService.instance;
  final _history = HistoryService.instance;
  late final Listenable _feedListenable;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _feedListenable = Listenable.merge([_bookmarks, _history]);
    _scrollController = ScrollController()..addListener(_onScroll);
    _restoreScroll();
  }

  @override
  void dispose() {
    if (_scrollController.hasClients) {
      BrowserSessionService.instance.updateHomeScroll(_scrollController.offset);
    }
    unawaited(BrowserSessionService.instance.flush());
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    BrowserSessionService.instance.updateHomeScroll(_scrollController.offset);
  }

  Future<void> _restoreScroll() async {
    await BrowserSessionService.instance.load();
    final offset = BrowserSessionService.instance.homeScrollOffset;
    if (!mounted || offset <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      _scrollController.jumpTo(offset.clamp(0, max).toDouble());
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return ColoredBox(
      color: AppColors.forest,
      child: Stack(
        children: [
          Positioned(
            top: -180,
            left: -80,
            right: -80,
            child: IgnorePointer(
              child: Container(
                height: 400,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    radius: 0.8,
                    colors: [
                      AppColors.primary.withValues(alpha: 0.26),
                      AppColors.forest.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -150,
            right: -110,
            child: IgnorePointer(
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.heroStart.withValues(alpha: 0.10),
                      AppColors.forest.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          CustomScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _brandRow(),
                      const SizedBox(height: 24),
                      _HomeSearch(
                        onNavigate: widget.onNavigate,
                        onOpenUrl: widget.onOpenUrl,
                      ),
                    ],
                  ),
                ),
              ),
              _feedsSliver(),
              SliverToBoxAdapter(
                child: SizedBox(height: 28 + bottomInset),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _brandRow() {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.heroStart, AppColors.heroEnd],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            Icons.travel_explore_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Comet Browser',
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
    );
  }

  Widget _feedsSliver() {
    return ListenableBuilder(
      listenable: _feedListenable,
      builder: (context, _) {
        final bookmarks = _bookmarks.entries;
        final bookmarkedUrls = bookmarks.map((entry) => entry.url).toSet();
        final frequent = _history
            .topPages(limit: 20)
            .where((entry) => !bookmarkedUrls.contains(entry.url))
            .take(12)
            .toList(growable: false);

        return SliverMainAxisGroup(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 26, 20, 10),
              sliver: SliverToBoxAdapter(
                child: _sectionHeader('Bookmarks', bookmarks.length),
              ),
            ),
            if (bookmarks.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverToBoxAdapter(
                  child: _emptyHint('Bookmarked pages will appear here.'),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverToBoxAdapter(
                  child: SizedBox(
                    height: 104,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      itemCount: bookmarks.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        final entry = bookmarks[index];
                        return _siteTile(
                          url: entry.url,
                          title: entry.title,
                          width: 156,
                          removeLabel: 'Remove bookmark',
                          onRemove: () =>
                              unawaited(_bookmarks.remove(entry.id)),
                        );
                      },
                    ),
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 26, 20, 10),
              sliver: SliverToBoxAdapter(
                child: _sectionHeader('Frequently visited', frequent.length),
              ),
            ),
            if (frequent.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverToBoxAdapter(
                  child: _emptyHint('Sites you visit will appear here.'),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    mainAxisExtent: 104,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final entry = frequent[index];
                      return _siteTile(
                        url: entry.url,
                        title: entry.title,
                        removeLabel: 'Remove from history',
                        onRemove: () => unawaited(_history.remove(entry.id)),
                      );
                    },
                    childCount: frequent.length,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _sectionHeader(String title, int count) {
    return Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title.toUpperCase(),
              style: AppText.label(11, color: AppColors.forestMuted),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$count',
            style: AppText.label(10, color: AppColors.forestAccent),
          ),
        ),
      ],
    );
  }

  Widget _emptyHint(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.forestSurface,
        borderRadius: BorderRadius.circular(18),
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
    double? width,
    required String removeLabel,
    required VoidCallback onRemove,
  }) {
    final uri = Uri.tryParse(url);
    final host = (uri?.host ?? url).replaceFirst(RegExp(r'^www\.'), '');
    final label = title.trim().isNotEmpty ? title.trim() : host;
    final initial = label.isNotEmpty ? label[0].toUpperCase() : '?';
    final tint = _tints[label.hashCode.abs() % _tints.length];
    final tile = Material(
      color: AppColors.forestSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.forestBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => widget.onOpenUrl(url),
        onLongPress: () => _showSiteActions(
          url: url,
          title: label,
          removeLabel: removeLabel,
          onRemove: onRemove,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SiteFavicon(
                host: host,
                size: 30,
                radius: 10,
                background: tint.withValues(alpha: 0.2),
                fallback: Text(
                  initial,
                  style: AppText.body(13, weight: FontWeight.w800, color: tint),
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
    );
    return RepaintBoundary(
      child: Semantics(
        button: true,
        label: 'Open $label. $host. Long press for options.',
        child: width == null ? tile : SizedBox(width: width, child: tile),
      ),
    );
  }

  Future<void> _showSiteActions({
    required String url,
    required String title,
    required String removeLabel,
    required VoidCallback onRemove,
  }) async {
    HapticFeedback.selectionClick();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppPalette.dark.card,
      builder: (sheetContext) => Theme(
        data: AppTheme.dark,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        AppText.heading(16, color: AppPalette.dark.foreground),
                  ),
                ),
              ),
              if (widget.onOpenInNewTab != null)
                ListTile(
                  leading: const Icon(Icons.open_in_new_rounded),
                  title: const Text('Open in new tab'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    widget.onOpenInNewTab!(url);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Copy link'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await Clipboard.setData(ClipboardData(text: url));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Link copied.')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: Text(removeLabel),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onRemove();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeSearch extends StatefulWidget {
  const _HomeSearch({
    required this.onNavigate,
    required this.onOpenUrl,
  });

  final ValueChanged<String> onNavigate;
  final ValueChanged<String> onOpenUrl;

  @override
  State<_HomeSearch> createState() => _HomeSearchState();
}

class _HomeSearchState extends State<_HomeSearch> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _settings = SettingsService.instance;
  final _bookmarks = BookmarksService.instance;
  final _history = HistoryService.instance;
  final _speech = SpeechToText();

  List<UrlSuggestion> _suggestions = const [];
  bool _focused = false;
  bool _listening = false;
  bool _speechInitialized = false;
  bool _speechAvailable = false;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_refresh);
    _bookmarks.addListener(_refreshSuggestions);
    _history.addListener(_refreshSuggestions);
    _focus.addListener(_onFocusChanged);
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _settings.removeListener(_refresh);
    _bookmarks.removeListener(_refreshSuggestions);
    _history.removeListener(_refreshSuggestions);
    _focus.removeListener(_onFocusChanged);
    _controller.removeListener(_onTextChanged);
    unawaited(_stopSpeech());
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _stopSpeech() async {
    try {
      await _speech.stop();
    } catch (_) {}
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _onFocusChanged() {
    if (!mounted) return;
    setState(() => _focused = _focus.hasFocus);
    _refreshSuggestions();
  }

  void _onTextChanged() {
    if (!mounted) return;
    setState(() {});
    _refreshSuggestions();
  }

  void _refreshSuggestions() {
    if (!mounted) return;
    if (!_focused) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = const []);
      return;
    }
    final query = _controller.text.trim();
    final next = query.isEmpty
        ? _history
            .topPages(limit: 5)
            .map((entry) => UrlSuggestion(
                  title: entry.title,
                  url: entry.url,
                  source: 'Recent',
                ))
            .toList(growable: false)
        : SuggestionsService.instance.suggest(query, limit: 6);
    setState(() => _suggestions = next);
  }

  void _submit([String? value]) {
    final text = (value ?? _controller.text).trim();
    if (text.isEmpty) return;
    _controller.clear();
    _focus.unfocus();
    widget.onNavigate(text);
  }

  void _openSuggestion(UrlSuggestion suggestion) {
    _controller.clear();
    _focus.unfocus();
    widget.onOpenUrl(suggestion.url);
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (!mounted) return;
    if (text == null || text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clipboard is empty.')),
      );
      return;
    }
    _controller.text = text;
    _controller.selection =
        TextSelection.collapsed(offset: _controller.text.length);
    _focus.requestFocus();
    _refreshSuggestions();
  }

  Future<void> _toggleVoice() async {
    try {
      if (_listening) {
        await _speech.stop();
        if (mounted) setState(() => _listening = false);
        return;
      }
      if (!_speechInitialized) {
        _speechInitialized = true;
        _speechAvailable = await _speech.initialize(
          onStatus: (status) {
            if (status == 'done' || status == 'notListening') {
              if (mounted) setState(() => _listening = false);
            }
          },
          onError: (_) {
            if (mounted) setState(() => _listening = false);
          },
        );
      }
      if (!_speechAvailable) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Voice search is not available on this device.'),
          ),
        );
        return;
      }
      if (!mounted) return;
      setState(() => _listening = true);
      await _speech.listen(
        listenOptions: SpeechListenOptions(
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 3),
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.search,
        ),
        onResult: (result) {
          final words = result.recognizedWords.trim();
          if (words.isEmpty) return;
          _controller.text = words;
          _controller.selection = TextSelection.collapsed(offset: words.length);
          _refreshSuggestions();
          if (result.finalResult) {
            if (mounted) setState(() => _listening = false);
            _submit(words);
          }
        },
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _listening = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start voice search.')),
      );
    }
  }

  Future<void> _pickSearchEngine() async {
    final value = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppPalette.dark.card,
      builder: (sheetContext) => Theme(
        data: AppTheme.dark,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  'Search engine',
                  style: AppText.heading(18, color: AppPalette.dark.foreground),
                ),
              ),
              for (final entry in SettingsService.searchEngineLabel.entries)
                ListTile(
                  leading: const Icon(Icons.search_rounded),
                  title: Text(entry.value),
                  trailing: _settings.searchEngine == entry.key
                      ? Icon(Icons.check_rounded, color: AppColors.forestAccent)
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(entry.key),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (value != null) await _settings.setSearchEngine(value);
  }

  Widget _barAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color? color,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      padding: EdgeInsets.zero,
      icon: Icon(icon, size: 19, color: color ?? AppColors.forestMuted),
    );
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focused;
    final accent = AppColors.primary;
    final hasText = _controller.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.forestSurface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: focused
                  ? accent.withValues(alpha: 0.85)
                  : AppColors.forestBorder,
              width: focused ? 1.4 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: focused ? 0.26 : 0.10),
                blurRadius: focused ? 22 : 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              const SizedBox(width: 16),
              Icon(
                Icons.search_rounded,
                color: focused ? accent : AppColors.forestMuted,
                size: 21,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _submit(),
                  style: AppText.body(14, color: AppColors.forestText),
                  cursorColor: AppColors.forestAccent,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: 'Search or type a website',
                    hintStyle: AppText.body(14, color: AppColors.forestMuted),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              if (hasText)
                _barAction(
                  icon: Icons.close_rounded,
                  tooltip: 'Clear search',
                  onTap: () {
                    _controller.clear();
                    _focus.requestFocus();
                  },
                ),
              _barAction(
                icon: _listening
                    ? Icons.stop_circle_rounded
                    : Icons.mic_none_rounded,
                tooltip: _listening ? 'Stop voice search' : 'Voice search',
                color: _listening ? accent : null,
                onTap: _toggleVoice,
              ),
              const SizedBox(width: 4),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  gradient: LinearGradient(
                    colors: [AppColors.heroStart, AppColors.heroEnd],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.38),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(13),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _submit,
                    child: const Tooltip(
                      message: 'Search',
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: focused && _suggestions.isNotEmpty
              ? _suggestionsCard()
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            TextButton.icon(
              onPressed: _paste,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.forestMuted,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 40),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.content_paste_rounded, size: 15),
              label: Text(
                'Paste',
                style: AppText.body(12, color: AppColors.forestMuted),
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _pickSearchEngine,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.forestText,
                backgroundColor: AppColors.forestSurface,
                side: const BorderSide(color: AppColors.forestBorder),
                shape: const StadiumBorder(),
                minimumSize: const Size(0, 40),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
              icon: Icon(
                Icons.public_rounded,
                size: 15,
                color: AppColors.forestAccent,
              ),
              label: Text(
                'Search with ${_settings.searchEngineName}',
                style: AppText.body(12, color: AppColors.forestMuted),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _suggestionsCard() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: AppColors.forestSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.forestBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final suggestion in _suggestions)
            InkWell(
              onTap: () => _openSuggestion(suggestion),
              child: Semantics(
                button: true,
                label:
                    '${suggestion.title}. ${suggestion.source}. ${suggestion.url}',
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      Icon(
                        suggestion.source == 'Bookmark'
                            ? Icons.bookmark_outline_rounded
                            : suggestion.source == 'Recent' ||
                                    suggestion.source == 'History'
                                ? Icons.history_rounded
                                : Icons.public_rounded,
                        size: 17,
                        color: AppColors.forestAccent,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              suggestion.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.body(13,
                                  weight: FontWeight.w600,
                                  color: AppColors.forestText),
                            ),
                            Text(
                              suggestion.url,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.body(10,
                                  color: AppColors.forestMuted),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.north_west_rounded,
                        size: 14,
                        color: AppColors.forestMuted.withValues(alpha: 0.7),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
