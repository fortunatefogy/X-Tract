import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/media_item.dart';
import '../../services/bookmarks_service.dart';
import '../../services/download_service.dart';
import '../../services/history_service.dart';
import '../../services/media_extractor.dart';
import '../../services/platform_extractor.dart';
import '../../services/settings_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/media_thumbnail.dart';
import '../bookmarks/bookmarks_screen.dart';
import '../browser/media_browser_screen.dart';
import '../history/history_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onOpenTab});

  final ValueChanged<int>? onOpenTab;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _urlController = TextEditingController();
  final _extractor = MediaExtractor();
  final Set<String> _selectedGroups = {};
  final Map<String, MediaItem> _chosenQuality = {};
  List<MediaItem> _media = [];
  bool _loading = false;
  bool _queueing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    HistoryService.instance.addListener(_refresh);
    BookmarksService.instance.addListener(_refresh);
  }

  @override
  void dispose() {
    HistoryService.instance.removeListener(_refresh);
    BookmarksService.instance.removeListener(_refresh);
    _urlController.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  List<String> _extractUrls(String text) {
    final matches = RegExp(r"""https?://[^\s<>"']+""", caseSensitive: false)
        .allMatches(text);
    final urls = <String>{};
    for (final match in matches) {
      final value = match.group(0)!.replaceAll(RegExp(r'[),.\]}!?;:]+$'), '');
      final uri = Uri.tryParse(value);
      if (uri != null && uri.hasAuthority) urls.add(uri.toString());
    }
    return urls.take(20).toList();
  }

  void _openBrowser() {
    final urls = _extractUrls(_urlController.text);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MediaBrowserScreen(
          initialUrl: urls.isEmpty ? '' : urls.first,
        ),
      ),
    );
  }

  void _clearResults() {
    setState(() {
      _media = [];
      _selectedGroups.clear();
      _chosenQuality.clear();
      _error = null;
    });
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (!mounted) return;
    if (text == null || text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clipboard is empty.')),
      );
      return;
    }
    setState(() => _urlController.text = text);
  }

  Future<void> _extract() async {
    final urls = _extractUrls(_urlController.text);
    if (urls.isEmpty) {
      setState(() => _error = 'Enter a valid http or https link.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _media = [];
      _selectedGroups.clear();
      _chosenQuality.clear();
    });
    try {
      final settings = SettingsService.instance;
      final found = <String, MediaItem>{};
      var failed = 0;
      var skippedBySiteFilter = 0;
      var engineUnavailable = false;
      for (final url in urls) {
        try {
          var extracted = <MediaItem>[];
          final siteAllowed =
              !settings.onlySupportedSites || settings.isSupportedSite(url);
          if (!siteAllowed) skippedBySiteFilter++;
          try {
            if (!siteAllowed) throw const FormatException('site filtered');
            final platformExtractor = PlatformExtractor();
            final cookieText = await platformExtractor.cookieTextFor(url);
            extracted = await platformExtractor.extract(
              url,
              cookieText: cookieText,
            );
          } catch (_) {
            if (siteAllowed) engineUnavailable = true;
          }
          if (extracted.isEmpty && !MediaExtractor.skipHtmlFallback(url)) {
            extracted = await _extractor.extract(url);
          }
          for (final item in extracted) {
            if (!settings.isTypeEnabled(item.type)) continue;
            if (!settings.passesSizeThreshold(item.size)) continue;
            found.putIfAbsent(item.url, () => item);
          }
        } catch (_) {
          failed++;
        }
        if (mounted) setState(() => _media = found.values.toList());
      }
      if (!mounted) return;
      setState(() {
        if (found.isEmpty) {
          _error = skippedBySiteFilter == urls.length
              ? 'Only supported sites is on and none of these links are on the list.'
              : failed == urls.length
                  ? 'Could not inspect these links. Check the connection and try again.'
                  : 'No public media was found at these links.';
        } else if (found.values.every((item) => !item.isDownloadable) &&
            engineUnavailable) {
          _error =
              'On-device yt-dlp could not extract this page. The source may not be supported, or may require access Linky cannot use.';
        } else if (found.values.every((item) => !item.isDownloadable)) {
          _error =
              'No playable format was found. If the page needs a login, open it in the Linky browser, sign in, then scan again.';
        } else if (failed > 0) {
          _error =
              'Found media from ${urls.length - failed} of ${urls.length} links.';
        } else if (urls.length > 1) {
          _error =
              'Checked ${urls.length} links. Duplicate media was combined.';
        }
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_MediaGroup> _groups() {
    final buckets = <String, List<MediaItem>>{};
    for (final item in _media) {
      final key = item.groupTitle != null
          ? '${item.sourcePage ?? ''}|${item.type}|${item.groupTitle}'
          : '${item.type}|${item.url}';
      buckets.putIfAbsent(key, () => []).add(item);
    }
    final groups = buckets.entries.map((entry) {
      final items = entry.value;
      items.sort(_compareOptions);
      final first = items.first;
      return _MediaGroup(
        key: entry.key,
        title: first.groupTitle ??
            first.title ??
            Uri.tryParse(first.url)?.pathSegments.lastOrNull ??
            'Media',
        type: first.type,
        items: items,
      );
    }).toList();
    groups.sort((a, b) {
      final rank = _typeRank(a.type).compareTo(_typeRank(b.type));
      if (rank != 0) return rank;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return groups;
  }

  static int _typeRank(String type) => switch (type) {
        'video' => 0,
        'audio' => 1,
        'image' => 2,
        'document' => 3,
        _ => 4,
      };

  static int _compareOptions(MediaItem a, MediaItem b) {
    if (a.type == 'video') {
      final height = (b.height ?? 0).compareTo(a.height ?? 0);
      if (height != 0) return height;
    }
    final size = (b.size ?? 0).compareTo(a.size ?? 0);
    if (size != 0) return size;
    return (a.qualityLabel ?? a.title ?? '')
        .compareTo(b.qualityLabel ?? b.title ?? '');
  }

  String _optionLabel(MediaItem item) {
    final label = item.qualityLabel ??
        (item.height != null ? '${item.height}p' : 'Original');
    final size = item.size;
    if (size == null || size <= 0) return label;
    return '$label · ${_formatBytes(size)}';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<void> _downloadSelected() async {
    final groups = _groups()
        .where((group) =>
            group.downloadable && _selectedGroups.contains(group.key))
        .toList(growable: false);
    if (groups.isEmpty) return;
    setState(() => _queueing = true);
    var queued = 0;
    String? failure;
    for (final group in groups) {
      final item = _chosenQuality[group.key] ?? group.defaultItem;
      try {
        await DownloadService.instance.enqueue(item);
        queued++;
      } catch (error) {
        failure ??= '$error';
      }
    }
    if (!mounted) return;
    setState(() {
      _queueing = false;
      _selectedGroups.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          queued == 0
              ? 'Could not queue the downloads. $failure'
              : 'Queued $queued download(s). Follow progress in Downloads.',
        ),
        action: queued == 0
            ? null
            : SnackBarAction(
                label: 'View',
                onPressed: () => widget.onOpenTab?.call(1),
              ),
      ),
    );
  }

  int get _selectedBytes => _groups()
      .where((group) => _selectedGroups.contains(group.key) && group.downloadable)
      .map((group) =>
          (_chosenQuality[group.key] ?? group.defaultItem).size ?? 0)
      .fold(0, (sum, size) => sum + size);

  String _groupMeta(_MediaGroup group) {
    final item = group.defaultItem;
    if (!group.downloadable) {
      return '${group.type.toUpperCase()} · platform page';
    }
    final details = <String>[
      _typeTag(group.type),
      if (group.items.length > 1)
        '${group.items.length} qualities'
      else
        _optionLabel(item),
      if (item.durationSeconds != null) _formatDuration(item.durationSeconds!),
    ];
    return details.join(' · ');
  }

  String _typeTag(String type) => switch (type) {
        'video' => 'MP4',
        'audio' => 'Audio',
        'image' => 'Image',
        'document' => 'File',
        _ => 'Media',
      };

  String _typeLabel(String type) => switch (type) {
        'video' => 'Videos',
        'audio' => 'Audio',
        'image' => 'Images',
        'document' => 'Documents',
        _ => 'Media',
      };

  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final remaining =
        duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return duration.inHours > 0
        ? '${duration.inHours}:$minutes:$remaining'
        : '$minutes:$remaining';
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final groups = _groups();
    final selectable =
        groups.where((group) => group.downloadable).toList(growable: false);
    final allSelected = selectable.isNotEmpty &&
        _selectedGroups.length == selectable.length;
    final showActionBar = _selectedGroups.isNotEmpty;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            ListView(
              padding: EdgeInsets.fromLTRB(20, 16, 20, showActionBar ? 120 : 32),
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.link_rounded,
                          size: 18, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    Text('Linky',
                        style: AppText.heading(20,
                            weight: FontWeight.w800)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: palette.accent,
                        borderRadius:
                            BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text('Home',
                          style: AppText.body(11,
                              weight: FontWeight.w700,
                              color: palette.accentForeground)),
                    ),
                    const Spacer(),
                    RoundIconButton(
                      icon: Icons.bookmark_border_rounded,
                      tooltip: 'Bookmarks',
                      size: 40,
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const BookmarksScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$_greeting, welcome back',
                            style: AppText.body(13,
                                color: palette.mutedForeground),
                          ),
                          const SizedBox(height: 2),
                          Text('Find any media',
                              style: AppText.display(30,
                                  color: palette.foreground)),
                        ],
                      ),
                    ),
                    RoundIconButton(
                      icon: Icons.public_rounded,
                      tooltip: 'Open in-app browser',
                      onPressed: _openBrowser,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                AppCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.only(left: 14, right: 6),
                        decoration: BoxDecoration(
                          color: palette.input,
                          borderRadius:
                              BorderRadius.circular(AppRadius.inner),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.link_rounded,
                                size: 20, color: palette.mutedForeground),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _urlController,
                                keyboardType: TextInputType.url,
                                textInputAction: TextInputAction.newline,
                                minLines: 1,
                                maxLines: 3,
                                onSubmitted: (_) => _extract(),
                                style: AppText.body(14),
                                decoration: InputDecoration(
                                  isDense: true,
                                  filled: false,
                                  contentPadding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  hintText: 'Paste a webpage or media link',
                                  hintStyle: AppText.body(14,
                                      color: palette.mutedForeground),
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: _pasteFromClipboard,
                              style: TextButton.styleFrom(
                                backgroundColor: palette.accent,
                                foregroundColor: palette.accentForeground,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.all(
                                      Radius.circular(AppRadius.pill)),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                minimumSize: const Size(0, 32),
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text('Paste'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _loading ? null : _extract,
                          icon: _loading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.search_rounded, size: 18),
                          label: Text(
                              _loading ? 'Looking for media…' : 'Find media'),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_loading)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: _StatusPill(
                      color: AppColors.teal,
                      icon: Icons.autorenew_rounded,
                      message: 'Scanning page for media…',
                    ),
                  )
                else if (_media.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: _StatusPill(
                      color: AppColors.teal,
                      icon: Icons.check_circle_rounded,
                      message:
                          'Link detected · ${groups.length} media item${groups.length == 1 ? '' : 's'}',
                      actionLabel: 'CLEAR',
                      onAction: _clearResults,
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: _StatusPill(
                      color: AppColors.amber,
                      icon: Icons.info_outline_rounded,
                      message: _error!,
                    ),
                  ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _QuickAction(
                        icon: Icons.public_rounded,
                        label: 'Browser',
                        caption: 'Open web pages',
                        onTap: _openBrowser,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _QuickAction(
                        icon: Icons.download_rounded,
                        label: 'Downloads',
                        caption: _activeCaption,
                        onTap: () => widget.onOpenTab?.call(1),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _QuickAction(
                        icon: Icons.history_rounded,
                        label: 'History',
                        caption: '${HistoryService.instance.entries.length} visits',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const HistoryScreen(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _QuickAction(
                        icon: Icons.bookmark_rounded,
                        label: 'Bookmarks',
                        caption:
                            '${BookmarksService.instance.entries.length} saved',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const BookmarksScreen(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const _ActiveDownloadsCard(),
                if (groups.isNotEmpty) ...[
                  const SizedBox(height: 26),
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Text('Detected media',
                                style: AppText.heading(20,
                                    color: palette.foreground)),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: palette.accent,
                                borderRadius:
                                    BorderRadius.circular(AppRadius.pill),
                              ),
                              child: Text(
                                '${groups.length}',
                                style: AppText.body(11,
                                    weight: FontWeight.w700,
                                    color: palette.accentForeground),
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          if (allSelected) {
                            _selectedGroups.clear();
                          } else {
                            _selectedGroups
                              ..clear()
                              ..addAll(selectable.map((group) => group.key));
                          }
                        }),
                        child: Text(allSelected ? 'Clear' : 'Select all'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ..._buildTypeSections(groups),
                ],
                const SizedBox(height: 22),
                _InfoPanel(
                  icon: Icons.shield_outlined,
                  message:
                      'Only public media the source makes accessible can be downloaded. Linky does not bypass logins, DRM, or access controls.',
                ),
              ],
            ),
            if (showActionBar)
              Positioned(
                left: 20,
                right: 20,
                bottom: 16,
                child: _DownloadBar(
                  count: _selectedGroups.length,
                  sizeLabel: _selectedBytes > 0
                      ? _formatBytes(_selectedBytes)
                      : null,
                  busy: _queueing,
                  onDownload: _queueing ? null : _downloadSelected,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String get _activeCaption {
    final active = DownloadService.instance.active.length;
    if (active == 0) return 'Nothing running';
    return '$active active';
  }

  List<Widget> _buildTypeSections(List<_MediaGroup> groups) {
    final palette = context.palette;
    final byType = <String, List<_MediaGroup>>{};
    for (final group in groups) {
      byType.putIfAbsent(group.type, () => []).add(group);
    }
    final types = byType.keys.toList()
      ..sort((a, b) => _typeRank(a).compareTo(_typeRank(b)));
    return [
      for (final type in types) ...[
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Text(
            '${_typeLabel(type)} · ${byType[type]!.length}',
            style: AppText.label(11, color: palette.mutedForeground),
          ),
        ),
        for (final group in byType[type]!) _groupTile(group),
      ],
    ];
  }

  List<MediaItem> _audioOnlyOptions(_MediaGroup group) {
    if (group.type != 'video') return const [];
    final options = <String, MediaItem>{};
    final hasGroupTitle = group.items.any((item) => item.groupTitle != null);
    for (final item in _media) {
      if (item.type != 'audio') continue;
      final sameGroup = hasGroupTitle && item.groupTitle == group.title;
      final samePage = !hasGroupTitle &&
          item.sourcePage != null &&
          item.sourcePage == group.items.first.sourcePage;
      if (!sameGroup && !samePage) continue;
      final key = '${item.formatId ?? ''}|${item.audioUrl ?? item.url}';
      options.putIfAbsent(key, () => item);
    }
    if (options.isEmpty) {
      final paired = _audioOnlyOption(group);
      if (paired != null) options['paired|${paired.url}'] = paired;
    }
    final list = options.values.toList(growable: false)
      ..sort((a, b) => (a.qualityLabel ?? '').compareTo(b.qualityLabel ?? ''));
    return list;
  }

  Future<void> _chooseAudioOnly(_MediaGroup group) async {
    final options = _audioOnlyOptions(group);
    if (options.isEmpty) return;
    if (options.length == 1) {
      await _queueAudioOnly(options.first);
      return;
    }
    final chosen = await showModalBottomSheet<MediaItem>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text('Choose audio format',
                  style: AppText.heading(18)),
            ),
            ...options.map((item) {
              final details = <String>[
                if (item.qualityLabel != null) item.qualityLabel!,
                if (item.size != null && item.size! > 0)
                  _formatBytes(item.size!),
                if (item.durationSeconds != null)
                  _formatDuration(item.durationSeconds!),
              ];
              return ListTile(
                leading: const Icon(Icons.audiotrack_rounded),
                title: Text(
                  details.isEmpty ? 'Audio' : details.first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: details.length > 1
                    ? Text(details.skip(1).join(' · '))
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(item),
              );
            }),
          ],
        ),
      ),
    );
    if (chosen != null) await _queueAudioOnly(chosen);
  }

  MediaItem? _audioOnlyOption(_MediaGroup group) {
    if (group.type != 'video') return null;
    for (final item in group.items) {
      final audioUrl = item.audioUrl;
      final audioFormatId = item.audioFormatId;
      if (audioUrl == null && audioFormatId == null) continue;
      final direct =
          audioFormatId == null || audioFormatId.startsWith('direct-');
      return MediaItem(
        url: audioUrl ?? item.url,
        type: 'audio',
        title: '${group.title} (audio)',
        mimeType: item.audioMimeType ?? 'audio/mp4',
        thumbnail: item.thumbnail,
        sourcePage: item.sourcePage,
        foundIn: 'audio only',
        requestHeaders: item.requestHeaders,
        durationSeconds: item.durationSeconds,
        uploader: item.uploader,
        formatId: direct ? null : audioFormatId,
        groupTitle: group.title,
        qualityLabel: 'Audio only',
        requiresExtractor: !direct,
      );
    }
    return null;
  }

  Future<void> _queueAudioOnly(MediaItem item) async {
    try {
      await DownloadService.instance.enqueue(item);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Audio-only download queued.'),
          action: SnackBarAction(
            label: 'View',
            onPressed: () => widget.onOpenTab?.call(1),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not queue audio download: $error')),
      );
    }
  }

  Widget _groupTile(_MediaGroup group) {
    final palette = context.palette;
    final selected = _selectedGroups.contains(group.key);
    final chosen = _chosenQuality[group.key] ?? group.defaultItem;
    final item = chosen;
    final previewUrl =
        item.thumbnail ?? (item.type == 'image' ? item.url : null);
    final showQualityPicker = group.items.length > 1;
    final audioOptions = _audioOnlyOptions(group);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        onTap: group.downloadable
            ? () => setState(() {
                  if (selected) {
                    _selectedGroups.remove(group.key);
                  } else {
                    _selectedGroups.add(group.key);
                  }
                })
            : null,
        color: selected ? palette.accent : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _thumb(item, previewUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body(14, weight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _groupMeta(group),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body(12,
                            color: palette.mutedForeground),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _SelectBox(
                  selected: selected,
                  enabled: group.downloadable,
                  onTap: group.downloadable
                      ? () => setState(() {
                            if (selected) {
                              _selectedGroups.remove(group.key);
                            } else {
                              _selectedGroups.add(group.key);
                            }
                          })
                      : null,
                ),
              ],
            ),
            if (showQualityPicker)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 68),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<MediaItem>(
                    value: item,
                    isDense: true,
                    isExpanded: true,
                    borderRadius: BorderRadius.circular(AppRadius.inner),
                    style: AppText.body(12, color: palette.foreground),
                    icon: Icon(Icons.expand_more_rounded,
                        size: 18, color: palette.mutedForeground),
                    items: group.items
                        .map((option) => DropdownMenuItem<MediaItem>(
                              value: option,
                              child: Text(
                                _optionLabel(option),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                        .toList(growable: false),
                    onChanged: group.downloadable
                        ? (option) {
                            if (option == null) return;
                            setState(() => _chosenQuality[group.key] = option);
                          }
                        : null,
                  ),
                ),
              ),
            if (audioOptions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 60),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _chooseAudioOnly(group),
                    icon: const Icon(Icons.audiotrack_rounded, size: 16),
                    label: Text(audioOptions.length > 1
                        ? 'Audio only (${audioOptions.length} formats)'
                        : 'Download audio only'),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _thumb(MediaItem item, String? previewUrl) {
    if (item.type == 'image' || item.type == 'video') {
      return MediaThumbnail(
        type: item.type,
        url: item.url,
        poster: item.thumbnail,
        headers: item.requestHeaders,
        size: 56,
        fallback: _mediaIcon(item),
      );
    }
    if (previewUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.inner),
        child: Image.network(
          previewUrl,
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _mediaIcon(item),
        ),
      );
    }
    return _mediaIcon(item);
  }

  Widget _mediaIcon(MediaItem item) => Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: context.palette.muted,
          borderRadius: BorderRadius.circular(AppRadius.inner),
        ),
        child: Icon(
          item.type == 'image'
              ? Icons.image_outlined
              : item.type == 'audio'
                  ? Icons.audiotrack_rounded
                  : item.type == 'document'
                      ? Icons.description_outlined
                      : Icons.movie_outlined,
          color: context.palette.mutedForeground,
        ),
      );
}

class _MediaGroup {
  const _MediaGroup({
    required this.key,
    required this.title,
    required this.type,
    required this.items,
  });

  final String key;
  final String title;
  final String type;
  final List<MediaItem> items;

  bool get downloadable => items.any((item) => item.isDownloadable);

  MediaItem get defaultItem => items.first;
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.caption,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: palette.accent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: palette.accentForeground),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: AppText.heading(15, weight: FontWeight.w700)),
                const SizedBox(height: 1),
                Text(caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(11,
                        color: palette.mutedForeground)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.color,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final Color color;
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
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
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.body(12, weight: FontWeight.w600),
            ),
          ),
          if (actionLabel != null)
            GestureDetector(
              onTap: onAction,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  actionLabel!,
                  style: AppText.label(10,
                      color: palette.mutedForeground),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SelectBox extends StatelessWidget {
  const _SelectBox({
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.primary : palette.border,
            width: 1.6,
          ),
        ),
        child: selected
            ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
            : enabled
                ? null
                : Icon(Icons.lock_outline_rounded,
                    size: 13, color: palette.mutedForeground),
      ),
    );
  }
}

class _DownloadBar extends StatelessWidget {
  const _DownloadBar({
    required this.count,
    required this.sizeLabel,
    required this.busy,
    required this.onDownload,
  });

  final int count;
  final String? sizeLabel;
  final bool busy;
  final VoidCallback? onDownload;

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
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$count selected${sizeLabel != null ? ' · $sizeLabel' : ''}',
                    style: AppText.body(13, weight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text('Ready to queue',
                      style: AppText.body(10,
                          color: palette.mutedForeground)),
                ],
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: onDownload,
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.download_rounded, size: 18),
            label: const Text('Download'),
          ),
        ],
      ),
    );
  }
}

class _ActiveDownloadsCard extends StatelessWidget {
  const _ActiveDownloadsCard();

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: DownloadService.instance,
        builder: (context, _) {
          final active = DownloadService.instance.active;
          if (active.isEmpty) return const SizedBox.shrink();
          final palette = context.palette;
          final overall = active
                  .map((record) => record.progress)
                  .reduce((a, b) => a + b) /
              active.length;
          final first = active.first;
          final percent = (overall * 100).clamp(0, 100).round();
          final sizeDetail = first.expectedBytes > 0
              ? '${_formatSize(first.expectedBytes * overall)} of ${_formatSize(first.expectedBytes)}'
              : 'Starting…';
          return Padding(
            padding: const EdgeInsets.only(top: 18),
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('Active downloads',
                            style: AppText.heading(16,
                                weight: FontWeight.w600)),
                      ),
                      Text(
                        '${active.length} of ${DownloadService.instance.records.where((r) => !r.state.isFinal).length}',
                        style: AppText.body(12,
                            weight: FontWeight.w700,
                            color: palette.accentForeground),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _ProgressRing(progress: overall, label: '$percent%'),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              first.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.body(14,
                                  weight: FontWeight.w600),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              sizeDetail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.body(12,
                                  color: palette.mutedForeground),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );

  static String _formatSize(num bytes) {
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.progress, required this.label});

  final double progress;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 5,
              backgroundColor: palette.muted,
              strokeCap: StrokeCap.round,
            ),
          ),
          Text(label,
              style: AppText.body(11, weight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(AppRadius.inner),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: palette.mutedForeground),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: AppText.body(12, color: palette.mutedForeground)),
          ),
        ],
      ),
    );
  }
}
