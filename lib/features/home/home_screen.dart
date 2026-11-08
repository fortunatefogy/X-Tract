import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/media_item.dart';
import '../../services/download_service.dart';
import '../../services/media_extractor.dart';
import '../../services/platform_extractor.dart';
import '../../services/shared_link_channel.dart';
import '../browser/media_browser_screen.dart';
import '../downloads/downloads_screen.dart';
import '../settings/settings_screen.dart';
import '../../widgets/media_thumbnail.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _urlController = TextEditingController();
  final _extractor = MediaExtractor();
  final _sharing = SharedLinkChannel();
  final Set<String> _selectedGroups = {};
  final Map<String, MediaItem> _chosenQuality = {};
  List<MediaItem> _media = [];
  bool _loading = false;
  bool _queueing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sharing.onSharedText = _handleSharedText;
    _sharing.getInitialText().then((text) {
      if (text != null) _handleSharedText(text);
    });
  }

  Future<void> _handleSharedText(String text) async {
    var payload = text;
    String? autoQuality;
    if (kDebugMode) {
      final browserMarker = RegExp(
        r'^\s*LINKY_OPEN_BROWSER\s+',
        caseSensitive: false,
      ).firstMatch(payload);
      if (browserMarker != null) {
        final url = payload.substring(browserMarker.end).trim();
        if (url.isNotEmpty && mounted) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => MediaBrowserScreen(initialUrl: url),
            ),
          );
        }
        return;
      }
      final marker = RegExp(
        r'^\s*LINKY_AUTO_DOWNLOAD(?:_([A-Za-z0-9]+))?\s+',
        caseSensitive: false,
      ).firstMatch(payload);
      if (marker != null) {
        autoQuality = marker.group(1) ?? 'best';
        payload = payload.substring(marker.end);
      }
    }
    final urls = _extractUrls(payload);
    if (urls.isEmpty) return;
    _urlController.text = urls.join('\n');
    await _extract();
    if (autoQuality != null && mounted) await _autoDownload(autoQuality);
  }

  Future<void> _autoDownload(String quality) async {
    final groups =
        _groups().where((group) => group.downloadable).toList(growable: false);
    if (groups.isEmpty) return;
    for (final group in groups.take(1)) {
      final item = _pickQuality(group, quality) ?? group.defaultItem;
      try {
        await DownloadService.instance.enqueue(item);
        debugPrint('linky-debug: queued ${item.title}');
      } catch (error) {
        debugPrint('linky-debug: queue failed $error');
      }
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
      final found = <String, MediaItem>{};
      var failed = 0;
      var engineUnavailable = false;
      for (final url in urls) {
        try {
          var extracted = <MediaItem>[];
          try {
            final platformExtractor = PlatformExtractor();
            final cookieText = await platformExtractor.cookieTextFor(url);
            extracted = await platformExtractor.extract(
              url,
              cookieText: cookieText,
            );
          } catch (_) {
            engineUnavailable = true;
          }
          if (extracted.isEmpty) extracted = await _extractor.extract(url);
          for (final item in extracted) {
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
          _error = failed == urls.length
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

  MediaItem? _pickQuality(_MediaGroup group, String quality) {
    final wanted = quality.toLowerCase();
    if (wanted == 'best' || wanted.isEmpty) return group.defaultItem;
    for (final item in group.items) {
      final label = item.qualityLabel?.toLowerCase();
      if (label == null) continue;
      if (label == wanted ||
          label.startsWith(wanted) ||
          label == '${wanted}p') {
        return item;
      }
    }
    return null;
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
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const DownloadsScreen(),
                  ),
                ),
              ),
      ),
    );
  }

  String _groupSubtitle(_MediaGroup group) {
    final item = group.defaultItem;
    if (!group.downloadable) {
      return '${group.type.toUpperCase()} platform page · direct media URL not exposed';
    }
    final details = <String>[
      group.type.toUpperCase(),
      if (group.items.length > 1) '${group.items.length} qualities',
      if (item.durationSeconds != null) _formatDuration(item.durationSeconds!),
      if (item.uploader?.isNotEmpty == true) item.uploader!,
    ];
    return details.join(' · ');
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

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Linky',
              style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [
            IconButton(
              tooltip: 'Open in-app browser',
              onPressed: _openBrowser,
              icon: const Icon(Icons.public),
            ),
            IconButton(
              tooltip: 'Downloads folder',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const DownloadsScreen(),
                ),
              ),
              icon: const Icon(Icons.folder_open_outlined),
            ),
            IconButton(
              tooltip: 'Settings',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SettingsScreen(),
                ),
              ),
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              const Text(
                'Save the media you find.',
                style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Paste one or more links, or share pages to get started.',
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 22),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextField(
                        controller: _urlController,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.newline,
                        minLines: 1,
                        maxLines: 4,
                        onSubmitted: (_) => _extract(),
                        decoration: const InputDecoration(
                          labelText: 'Webpage or media links',
                          hintText: 'Paste one or more http(s) links',
                          prefixIcon: Icon(Icons.link),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _loading ? null : _extract,
                          icon: _loading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.search),
                          label: Text(
                            _loading ? 'Looking for media…' : 'Find media',
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _openBrowser,
                        icon: const Icon(Icons.public),
                        label: const Text('Open page in Linky browser'),
                      ),
                    ],
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                _InfoPanel(icon: Icons.info_outline, message: _error!),
              ],
              const SizedBox(height: 16),
              _ActiveDownloadsCard(),
              if (_media.isNotEmpty) ...[
                const SizedBox(height: 24),
                Builder(builder: (context) {
                  final groups = _groups();
                  final selectable = groups
                      .where((group) => group.downloadable)
                      .map((group) => group.key)
                      .toList(growable: false);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${groups.length} item(s) found',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => setState(() {
                              if (_selectedGroups.length == selectable.length) {
                                _selectedGroups.clear();
                              } else {
                                _selectedGroups
                                  ..clear()
                                  ..addAll(selectable);
                              }
                            }),
                            child: Text(
                              _selectedGroups.length == selectable.length &&
                                      selectable.isNotEmpty
                                  ? 'Clear'
                                  : 'Select all',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...groups.map(_groupTile),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: _selectedGroups.isEmpty || _queueing
                            ? null
                            : _downloadSelected,
                        icon: _queueing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.download),
                        label: Text(
                          'Download selected (${_selectedGroups.length})',
                        ),
                      ),
                    ],
                  );
                }),
              ],
              const SizedBox(height: 24),
              const _InfoPanel(
                icon: Icons.shield_outlined,
                message:
                    'Only public media the source makes accessible can be downloaded. Linky does not bypass logins, DRM, or access controls.',
              ),
            ],
          ),
        ),
      );

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
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const DownloadsScreen(),
              ),
            ),
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
    final selected = _selectedGroups.contains(group.key);
    final chosen = _chosenQuality[group.key] ?? group.defaultItem;
    final item = chosen;
    final previewUrl =
        item.thumbnail ?? (item.type == 'image' ? item.url : null);
    final showQualityPicker = group.items.length > 1;
    final audioOption = _audioOnlyOption(group);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: CheckboxListTile(
          value: selected,
          onChanged: group.downloadable
              ? (value) => setState(() {
                    if (value == true) {
                      _selectedGroups.add(group.key);
                    } else {
                      _selectedGroups.remove(group.key);
                    }
                  })
              : null,
          secondary: item.type == 'image' || item.type == 'video'
              ? MediaThumbnail(
                  type: item.type,
                  url: item.url,
                  poster: item.thumbnail,
                  size: 52,
                  fallback: _mediaIcon(item),
                )
              : previewUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        previewUrl,
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _mediaIcon(item),
                      ),
                    )
                  : _mediaIcon(item),
          title: Text(
            group.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          isThreeLine: showQualityPicker,
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_groupSubtitle(group)),
              if (showQualityPicker)
                DropdownButtonHideUnderline(
                  child: DropdownButton<MediaItem>(
                    value: item,
                    isDense: true,
                    isExpanded: true,
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
                )
              else if (group.downloadable)
                Text(
                  _optionLabel(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              if (audioOption != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _queueAudioOnly(audioOption),
                    icon: const Icon(Icons.audiotrack, size: 18),
                    label: const Text('Download audio only'),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
            ],
          ),
          controlAffinity: ListTileControlAffinity.trailing,
        ),
      ),
    );
  }

  Widget _mediaIcon(MediaItem item) => CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Icon(
          item.type == 'image'
              ? Icons.image_outlined
              : item.type == 'audio'
                  ? Icons.audiotrack
                  : item.type == 'document'
                      ? Icons.description_outlined
                      : Icons.movie_outlined,
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

class _ActiveDownloadsCard extends StatelessWidget {
  const _ActiveDownloadsCard();

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: DownloadService.instance,
        builder: (context, _) {
          final active = DownloadService.instance.active;
          if (active.isEmpty) return const SizedBox.shrink();
          final overall =
              active.map((record) => record.progress).reduce((a, b) => a + b) /
                  active.length;
          return Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.downloading,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${active.length} download(s) in progress',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const DownloadsScreen(),
                            ),
                          ),
                          child: const Text('Open'),
                        ),
                      ],
                    ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: overall),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child:
                  Text(message, style: TextStyle(color: Colors.grey.shade700)),
            ),
          ],
        ),
      );
}
