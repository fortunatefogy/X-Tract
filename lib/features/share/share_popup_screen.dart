import 'package:flutter/material.dart';

import '../../models/media_item.dart';
import '../../services/download_service.dart';
import '../../services/media_extractor.dart';
import '../../services/platform_extractor.dart';
import '../../services/settings_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/media_thumbnail.dart';

class SharePopupScreen extends StatefulWidget {
  const SharePopupScreen({
    super.key,
    required this.initialText,
    required this.onClose,
    required this.onDownloadQueued,
    this.onOpenBrowser,
    this.embedded = false,
  });

  final String? initialText;
  final VoidCallback onClose;
  final ValueChanged<int> onDownloadQueued;
  final ValueChanged<String>? onOpenBrowser;
  final bool embedded;

  @override
  State<SharePopupScreen> createState() => _SharePopupScreenState();
}

class _SharePopupScreenState extends State<SharePopupScreen>
    with SingleTickerProviderStateMixin {
  final _extractor = MediaExtractor();
  final _selected = <String>{};
  late final AnimationController _entrance;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  List<MediaItem> _media = [];
  bool _loading = false;
  bool _queueing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..forward();
    _fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic));
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SharePopupScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialText != widget.initialText) {
      _scan();
    }
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

  Future<void> _scan() async {
    final urls = _extractUrls(widget.initialText ?? '');
    if (urls.isEmpty) {
      setState(() => _error = 'No link was shared with Linky.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _media = [];
      _selected.clear();
    });
    final settings = SettingsService.instance;
    final found = <String, MediaItem>{};
    var failed = 0;
    for (final url in urls) {
      try {
        var extracted = <MediaItem>[];
        final siteAllowed =
            !settings.onlySupportedSites || settings.isSupportedSite(url);
        if (siteAllowed) {
          try {
            final platform = PlatformExtractor();
            final cookieText = await platform.cookieTextFor(url);
            extracted = await platform.extract(url, cookieText: cookieText);
          } catch (_) {}
        }
        if (extracted.isEmpty) extracted = await _extractor.extract(url);
        for (final item in extracted) {
          if (!settings.isTypeEnabled(item.type)) continue;
          if (!settings.passesSizeThreshold(item.size)) continue;
          found.putIfAbsent(item.url, () => item);
        }
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    final items = found.values.toList(growable: false);
    setState(() {
      _loading = false;
      _media = items;
      _selected.addAll(items.where((item) => item.isDownloadable).map(_key));
      if (items.isEmpty) {
        _error = failed == urls.length
            ? 'Could not inspect this link. Open it in the Linky browser to sign in, then try again.'
            : 'No downloadable media was found. Open it in the Linky browser to sign in, then try again.';
      } else if (items.every((item) => !item.isDownloadable)) {
        _error =
            'This media needs a login the sheet cannot use. Open it in the Linky browser, sign in, then download.';
      }
    });
  }

  String? get _primaryUrl {
    final urls = _extractUrls(widget.initialText ?? '');
    return urls.isEmpty ? null : urls.first;
  }

  void _openBrowser() {
    final url = _primaryUrl;
    if (url == null) return;
    final callback = widget.onOpenBrowser;
    if (callback != null) {
      callback(url);
    }
  }

  String _key(MediaItem item) => '${item.url}|${item.formatId ?? ''}';

  List<MediaItem> get _downloadable =>
      _media.where((item) => item.isDownloadable).toList(growable: false);

  List<MediaItem> get _chosen =>
      _downloadable.where((item) => _selected.contains(_key(item))).toList();

  Future<void> _download() async {
    final items = _chosen;
    if (items.isEmpty) return;
    setState(() => _queueing = true);
    var queued = 0;
    for (final item in items) {
      try {
        await DownloadService.instance.enqueue(item);
        queued++;
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _queueing = false);
    if (queued == 0) {
      setState(() => _error = 'Could not queue the downloads. Try again.');
      return;
    }
    widget.onDownloadQueued(queued);
  }

  void _toggle(MediaItem item) {
    final key = _key(item);
    setState(() {
      if (_selected.contains(key)) {
        _selected.remove(key);
      } else {
        _selected.add(key);
      }
    });
  }

  void _toggleAll() {
    final all = _downloadable;
    final allSelected = all.every((item) => _selected.contains(_key(item)));
    setState(() {
      if (allSelected) {
        _selected.removeAll(all.map(_key));
      } else {
        _selected.addAll(all.map(_key));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final chosenCount = _chosen.length;
    final content = Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.72,
        minHeight: 280,
      ),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(24),
        ),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: palette.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.link_rounded,
                      size: 20, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Linky share',
                          style:
                              AppText.heading(17, weight: FontWeight.w800)),
                      Text(
                        _loading
                            ? 'Scanning link for media…'
                            : '${_media.length} media item${_media.length == 1 ? '' : 's'} found',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body(12,
                            color: palette.mutedForeground),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: CircularProgressIndicator(),
            )
          else if (_error != null && _media.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: AppColors.amber, size: 32),
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: AppText.body(13, color: palette.mutedForeground),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      TextButton(
                        onPressed: _scan,
                        child: const Text('Scan again'),
                      ),
                      if (_primaryUrl != null && widget.onOpenBrowser != null)
                        FilledButton.tonalIcon(
                          onPressed: _openBrowser,
                          icon: const Icon(Icons.public_rounded, size: 18),
                          label: const Text('Open in Linky browser'),
                        ),
                    ],
                  ),
                ],
              ),
            )
          else ...[
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  decoration: BoxDecoration(
                    color: AppColors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.inner),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          color: AppColors.amber, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: AppText.body(11,
                              color: palette.mutedForeground),
                        ),
                      ),
                      if (_primaryUrl != null &&
                          widget.onOpenBrowser != null)
                        TextButton(
                          onPressed: _openBrowser,
                          style: TextButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(0, 32),
                            tapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Browser'),
                        ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '$chosenCount selected',
                      style: AppText.body(12,
                          weight: FontWeight.w600,
                          color: palette.mutedForeground),
                    ),
                  ),
                  TextButton(
                    onPressed: _downloadable.isEmpty ? null : _toggleAll,
                    child: const Text('Select all'),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                itemCount: _media.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) =>
                    _itemTile(_media[index]),
              ),
            ),
          ],
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed:
                      chosenCount == 0 || _queueing ? null : _download,
                  icon: _queueing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.download_rounded, size: 18),
                  label: Text(
                    chosenCount == 0
                        ? 'Select media to download'
                        : 'Download $chosenCount · runs in background',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (widget.embedded) return content;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: FadeTransition(
              opacity: _fade,
              child: GestureDetector(
                onTap: widget.onClose,
                child: Container(color: Colors.black54),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: FadeTransition(
              opacity: _fade,
              child: SlideTransition(
                position: _slide,
                child: content,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemTile(MediaItem item) {
    final palette = context.palette;
    final enabled = item.isDownloadable;
    final selected = _selected.contains(_key(item));
    return Material(
      color: selected ? palette.accent : palette.input,
      borderRadius: BorderRadius.circular(AppRadius.inner),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.inner),
        onTap: enabled ? () => _toggle(item) : null,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              MediaThumbnail(
                type: item.type,
                url: item.url,
                poster: item.thumbnail,
                size: 48,
                fallback: Icon(
                  item.type == 'image'
                      ? Icons.image_outlined
                      : item.type == 'audio'
                          ? Icons.audiotrack_rounded
                          : item.type == 'document'
                              ? Icons.description_outlined
                              : Icons.movie_outlined,
                  color: palette.mutedForeground,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title ?? _fileName(item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(13, weight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _meta(item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(11,
                          color: palette.mutedForeground),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                !enabled
                    ? Icons.lock_outline_rounded
                    : selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                size: 22,
                color: !enabled
                    ? palette.mutedForeground
                    : selected
                        ? AppColors.primary
                        : palette.mutedForeground,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fileName(MediaItem item) {
    final segments = Uri.tryParse(item.url)?.pathSegments;
    if (segments != null && segments.isNotEmpty) return segments.last;
    return 'Media';
  }

  String _meta(MediaItem item) {
    final parts = <String>[item.type.toUpperCase()];
    if (item.qualityLabel != null) parts.add(item.qualityLabel!);
    if (item.size != null && item.size! > 0) parts.add(_formatBytes(item.size!));
    if (item.durationSeconds != null) {
      parts.add(_formatDuration(item.durationSeconds!));
    }
    return parts.join(' · ');
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final remaining =
        duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return duration.inHours > 0
        ? '${duration.inHours}:$minutes:$remaining'
        : '$minutes:$remaining';
  }
}
