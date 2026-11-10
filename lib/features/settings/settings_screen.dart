import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../services/adblock_service.dart';
import '../../services/download_service.dart';
import '../../services/proxy_service.dart';
import '../../services/secure_dns_service.dart';
import '../../services/settings_service.dart';
import '../../services/storage_service.dart';
import '../../services/suggestions_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_ui.dart';
import '../detection_logs/detection_logs_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settings = SettingsService.instance;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_refresh);
  }

  @override
  void dispose() {
    _settings.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _addProxy() async {
    final controller = TextEditingController();
    final value = await _promptText(
      title: 'Add proxy',
      hint: 'http://host:port or socks5://host:port',
      controller: controller,
      confirm: 'Add',
    );
    if (value == null || value.isEmpty) return;
    final chain = [..._settings.proxyChain, ProxyService.normalise(value)];
    await _settings.setProxyChain(chain);
    await ProxyService.instance.applyWebView();
    if (mounted) setState(() {});
  }

  Future<void> _removeProxy(String value) async {
    final chain = [..._settings.proxyChain]..remove(value);
    await _settings.setProxyChain(chain);
    await ProxyService.instance.applyWebView();
    if (mounted) setState(() {});
  }

  Future<void> _moveProxy(int index, int delta) async {
    final chain = [..._settings.proxyChain];
    final target = index + delta;
    if (target < 0 || target >= chain.length) return;
    final value = chain.removeAt(index);
    chain.insert(target, value);
    await _settings.setProxyChain(chain);
    await ProxyService.instance.applyWebView();
    if (mounted) setState(() {});
  }

  Future<void> _editSecureDnsCustom() async {
    final value = await _promptText(
      title: 'Custom DNS endpoint',
      hint: 'https://dns.example.com/dns-query or tls://1.1.1.1',
      controller: TextEditingController(text: _settings.secureDnsCustom),
    );
    if (value == null) return;
    await _settings.setSecureDnsCustom(value);
  }

  Future<void> _clearCookies() async {
    await CookieManager.instance().deleteAllCookies();
    if (!mounted) return;
    _toast('Browser cookies cleared.');
  }

  Future<void> _editCustomHome() async {
    final value = await _promptText(
      title: 'Custom home page',
      hint: 'https://example.com/',
      controller: TextEditingController(text: _settings.customHomeUrl),
    );
    if (value == null) return;
    await _settings.setCustomHomeUrl(value);
  }

  Future<void> _editCustomSearch() async {
    final value = await _promptText(
      title: 'Custom search URL',
      hint: 'https://example.com/search?q={query}',
      helper: 'Use {query} where the search text goes.',
      controller: TextEditingController(text: _settings.customSearchUrl),
    );
    if (value == null) return;
    await _settings.setCustomSearchUrl(value);
  }

  Future<void> _editSupportedSitesUrl() async {
    final value = await _promptText(
      title: 'Remote supported sites list',
      hint: 'https://example.com/linky-sites.json',
      helper: 'JSON array of hosts or an object with a "sites" key.',
      controller: TextEditingController(text: _settings.supportedSitesUrl),
    );
    if (value != null) await _settings.setSupportedSitesUrl(value);
  }

  Future<void> _openDownloadsFolder() async {
    final opened = await StorageService.instance.openFolder();
    if (!mounted) return;
    _toast(opened
        ? 'Opening the downloads folder.'
        : 'No file manager could open the downloads folder.');
  }

  Future<void> _moveDownloads() async {
    try {
      final moved = await StorageService.instance.moveExistingDownloads();
      final target = await StorageService.instance.downloadDirectory();
      await DownloadService.instance.relocateDownloads(target.path);
      if (!mounted) return;
      _toast(moved == 0 ? 'No files needed moving.' : 'Moved $moved file(s).');
    } catch (error) {
      _toast('Could not move downloads: $error');
    }
  }

  Future<void> _editSuggestionListUrl() async {
    final value = await _promptText(
      title: 'Remote suggestions list',
      hint: 'https://example.com/linky-pages.json',
      helper: 'JSON array of URLs or objects with title and url.',
      controller: TextEditingController(text: _settings.suggestionListUrl),
    );
    if (value != null) await _settings.setSuggestionListUrl(value);
  }

  Future<void> _addAdBlockListUrl() async {
    final value = await _promptText(
      title: 'Add ad-block list URL',
      hint: 'https://example.com/ads.txt',
      helper: 'Hosts, domain lists, or JSON arrays are supported.',
      controller: TextEditingController(),
      confirm: 'Add',
    );
    if (value != null && value.isNotEmpty) {
      await AdBlockService.instance.addListUrl(value);
      if (mounted) setState(() {});
    }
  }

  Future<void> _refreshAdBlock() async {
    try {
      final count = await AdBlockService.instance.refresh();
      if (!mounted) return;
      _toast('Loaded $count blocked host(s).');
    } catch (error) {
      _toast('Could not update ad-block rules: $error');
    }
  }

  Future<void> _refreshSuggestions() async {
    try {
      final count = await SuggestionsService.instance.refreshRemote();
      if (!mounted) return;
      _toast('Loaded $count suggestion(s).');
    } catch (error) {
      _toast('Could not load suggestions: $error');
    }
  }

  Future<void> _refreshSupportedSites() async {
    try {
      final count = await _settings.refreshSupportedSites();
      if (!mounted) return;
      _toast('Loaded $count supported site(s).');
    } catch (error) {
      _toast('Could not load the list: $error');
    }
  }

  Future<String?> _promptText({
    required String title,
    required String hint,
    required TextEditingController controller,
    String? helper,
    String confirm = 'Save',
  }) async {
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          autofocus: true,
          decoration: InputDecoration(
            hintText: hint,
            helperText: helper,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(confirm),
          ),
        ],
      ),
    );
    return value;
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _sizeLabel(int bytes) {
    if (bytes <= 0) return 'Off';
    if (bytes < 1024 * 1024) return '${bytes ~/ 1024} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          children: [
            Text('Settings',
                style: AppText.display(30, color: palette.foreground)),
            const SizedBox(height: 2),
            Text('Tune how Linky finds and saves media.',
                style: AppText.body(13, color: palette.mutedForeground)),
            const SizedBox(height: 22),
            _Group(
              title: 'Appearance',
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Theme',
                          style: AppText.body(14,
                              weight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      PillSegment<ThemeMode>(
                        value: _settings.themeMode,
                        onChanged: (mode) => _settings.setThemeMode(mode),
                        options: const [
                          PillOption(ThemeMode.light, 'Light'),
                          PillOption(ThemeMode.dark, 'Dark'),
                          PillOption(ThemeMode.system, 'System'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            _Group(
              title: 'Browser',
              children: [
                _DropdownRow<String>(
                  title: 'Search engine',
                  subtitle: 'Used for plain-text queries',
                  value: _settings.searchEngine,
                  items: SettingsService.searchEnginePresets
                      .map((engine) => DropdownMenuItem<String>(
                            value: engine,
                            child: Text(
                                SettingsService.searchEngineLabel[engine] ??
                                    engine),
                          ))
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value != null) _settings.setSearchEngine(value);
                  },
                ),
                if (_settings.searchEngine == 'custom') ...[
                  _TapRow(
                    title: 'Custom home page',
                    subtitle: _settings.customHomeUrl.isEmpty
                        ? 'Tap to set the start page address'
                        : _settings.customHomeUrl,
                    onTap: _editCustomHome,
                  ),
                  _TapRow(
                    title: 'Custom search URL',
                    subtitle: _settings.customSearchUrl.isEmpty
                        ? 'Tap to set a URL template with {query}'
                        : _settings.customSearchUrl,
                    onTap: _editCustomSearch,
                  ),
                ],
                _SwitchRow(
                  title: 'Only show the playing video',
                  subtitle:
                      'Hide other video items detected while a video plays',
                  value: _settings.onlyPlayingVideo,
                  onChanged: _settings.setOnlyPlayingVideo,
                ),
                _SwitchRow(
                  title: 'Filter junk media',
                  subtitle: 'Hide icons, thumbnails and small images',
                  value: _settings.filterJunkMedia,
                  onChanged: _settings.setFilterJunkMedia,
                ),
                _SwitchRow(
                  title: 'Ask before cross-site redirects',
                  subtitle: 'Prompt when a page navigates to another site',
                  value: _settings.redirectPromptEnabled,
                  onChanged: _settings.setRedirectPromptEnabled,
                ),
                _SwitchRow(
                  title: 'Block pop-ups and redirect ads',
                  subtitle: 'Stop streaming sites from opening extra windows',
                  value: _settings.blockPopups,
                  onChanged: _settings.setBlockPopups,
                ),
                _SwitchRow(
                  title: 'Desktop mode for new tabs',
                  subtitle: 'Request full websites with a desktop viewport',
                  value: _settings.desktopMode,
                  onChanged: _settings.setDesktopMode,
                ),
              ],
            ),
            _Group(
              title: 'Downloads',
              children: [
                _DropdownRow<String>(
                  title: 'Save location',
                  subtitle: 'Where completed files are saved',
                  value: _settings.downloadLocation,
                  items: [
                    const DropdownMenuItem(
                        value: 'app', child: Text('App storage')),
                    const DropdownMenuItem(
                        value: 'external', child: Text('Device storage')),
                    if (StorageService.instance.hasSdCard)
                      const DropdownMenuItem(
                          value: 'sd', child: Text('SD card')),
                  ],
                  onChanged: (value) {
                    if (value != null) _settings.setDownloadLocation(value);
                  },
                ),
                _DropdownRow<int>(
                  title: 'Parallel downloads',
                  subtitle: 'Files transferring at once',
                  value: _settings.maxSimultaneousDownloads,
                  items: <int>[
                    ...SettingsService.simultaneousDownloadPresets,
                    if (!SettingsService.simultaneousDownloadPresets
                        .contains(_settings.maxSimultaneousDownloads))
                      _settings.maxSimultaneousDownloads,
                  ]
                      .map((count) => DropdownMenuItem<int>(
                            value: count,
                            child: Text('$count'),
                          ))
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value != null) {
                      _settings.setMaxSimultaneousDownloads(value);
                    }
                  },
                ),
                _DropdownRow<int>(
                  title: 'Parallel connections',
                  subtitle: 'Chunks used per download',
                  value: _settings.downloadThreadCount,
                  items: <int>[
                    ...SettingsService.downloadThreadPresets,
                    if (!SettingsService.downloadThreadPresets
                        .contains(_settings.downloadThreadCount))
                      _settings.downloadThreadCount,
                  ]
                      .map((count) => DropdownMenuItem<int>(
                            value: count,
                            child: Text('$count'),
                          ))
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value != null) _settings.setDownloadThreadCount(value);
                  },
                ),
                _SwitchRow(
                  title: 'Copy to public Downloads',
                  subtitle: 'Also place a copy in the system Downloads folder',
                  value: _settings.copyToPublicDownloads,
                  onChanged: _settings.setCopyToPublicDownloads,
                ),
                _TapRow(
                  title: 'Open downloads folder',
                  subtitle: 'Browse saved files with a file manager',
                  onTap: _openDownloadsFolder,
                ),
                _TapRow(
                  title: 'Move existing downloads',
                  subtitle: 'Move saved files to the current location',
                  onTap: _moveDownloads,
                ),
              ],
            ),
            _Group(
              title: 'Post-processing',
              children: [
                _SwitchRow(
                  title: 'Remux videos to MP4',
                  subtitle: 'Copy tracks into MP4 without re-encoding',
                  value: _settings.remuxDownloads,
                  onChanged: _settings.setRemuxDownloads,
                ),
                _SwitchRow(
                  title: 'Fast-start MP4 files',
                  subtitle: 'Move the MP4 index to the start',
                  value: _settings.fastStartDownloads,
                  onChanged: _settings.setFastStartDownloads,
                ),
                _SwitchRow(
                  title: 'Repair FLV and stream containers',
                  subtitle: 'Try to remux FLV, TS and similar files',
                  value: _settings.repairStreams,
                  onChanged: _settings.setRepairStreams,
                ),
                _SwitchRow(
                  title: 'Save audio only (M4A)',
                  subtitle: 'Extract the audio track from videos',
                  value: _settings.audioOnlyDownloads,
                  onChanged: _settings.setAudioOnlyDownloads,
                ),
              ],
            ),
            _Group(
              title: 'Detection',
              children: [
                _SwitchRow(
                  title: 'Detect videos',
                  subtitle: 'Include video and streaming media',
                  value: _settings.detectVideos,
                  onChanged: _settings.setDetectVideos,
                ),
                _SwitchRow(
                  title: 'Detect images',
                  subtitle: 'Include image files and thumbnails',
                  value: _settings.detectImages,
                  onChanged: _settings.setDetectImages,
                ),
                _SwitchRow(
                  title: 'Detect audio',
                  subtitle: 'Include music and audio-only files',
                  value: _settings.detectAudio,
                  onChanged: _settings.setDetectAudio,
                ),
                _SwitchRow(
                  title: 'Detect documents',
                  subtitle: 'Include PDFs, office files and text',
                  value: _settings.detectDocuments,
                  onChanged: _settings.setDetectDocuments,
                ),
                _DropdownRow<int>(
                  title: 'Ignore small media',
                  subtitle:
                      'Skip media smaller than ${_sizeLabel(_settings.minMediaSizeBytes)}',
                  value: _settings.minMediaSizeBytes,
                  items: <int>[
                    ...SettingsService.minMediaSizePresets,
                    if (!SettingsService.minMediaSizePresets
                        .contains(_settings.minMediaSizeBytes))
                      _settings.minMediaSizeBytes,
                  ]
                      .map((bytes) => DropdownMenuItem<int>(
                            value: bytes,
                            child: Text(_sizeLabel(bytes)),
                          ))
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value != null) _settings.setMinMediaSizeBytes(value);
                  },
                ),
              ],
            ),
            _Group(
              title: 'Supported sites',
              children: [
                _SwitchRow(
                  title: 'Only use the supported sites list',
                  subtitle: 'Skip extraction for pages outside the list',
                  value: _settings.onlySupportedSites,
                  onChanged: _settings.setOnlySupportedSites,
                ),
                _TapRow(
                  title: 'Remote list URL',
                  subtitle: _settings.supportedSitesUrl.isEmpty
                      ? 'None · ${SettingsService.defaultSupportedHosts.length} built-in sites'
                      : _settings.supportedSitesUrl,
                  onTap: _editSupportedSitesUrl,
                ),
                _TapRow(
                  title: 'Update remote list',
                  subtitle:
                      '${_settings.remoteSupportedHosts.length} host(s) loaded',
                  enabled: _settings.supportedSitesUrl.isNotEmpty,
                  onTap: _settings.supportedSitesUrl.isEmpty
                      ? null
                      : _refreshSupportedSites,
                ),
              ],
            ),
            _Group(
              title: 'Suggestions',
              children: [
                _TapRow(
                  title: 'Remote suggestions URL',
                  subtitle: _settings.suggestionListUrl.isEmpty
                      ? 'None · using history and bookmarks'
                      : _settings.suggestionListUrl,
                  onTap: _editSuggestionListUrl,
                ),
                _TapRow(
                  title: 'Update suggestions',
                  subtitle: 'Load page suggestions from the remote list',
                  enabled: _settings.suggestionListUrl.isNotEmpty,
                  onTap: _settings.suggestionListUrl.isEmpty
                      ? null
                      : _refreshSuggestions,
                ),
              ],
            ),
            _Group(
              title: 'Ad blocker',
              children: [
                _SwitchRow(
                  title: 'Enable ad blocker',
                  subtitle:
                      'Blocks ${AdBlockService.instance.ruleCount} known ad host(s)',
                  value: _settings.adBlockEnabled,
                  onChanged: _settings.setAdBlockEnabled,
                ),
                for (final listUrl in _settings.adBlockListUrls)
                  _TapRow(
                    title: listUrl,
                    subtitle: 'Rule list',
                    trailing: Icon(Icons.close_rounded,
                        size: 16, color: palette.mutedForeground),
                    onTap: () async {
                      await AdBlockService.instance.removeListUrl(listUrl);
                      if (mounted) setState(() {});
                    },
                  ),
                _TapRow(
                  title: 'Add rule list URL',
                  subtitle: 'Bring your own host blocklist',
                  onTap: _addAdBlockListUrl,
                ),
                _TapRow(
                  title: 'Update ad-block lists',
                  subtitle: 'Download and cache the selected lists',
                  enabled: _settings.adBlockListUrls.isNotEmpty,
                  onTap:
                      _settings.adBlockListUrls.isEmpty ? null : _refreshAdBlock,
                ),
              ],
            ),
            _Group(
              title: 'Proxy & DNS',
              children: [
                _SwitchRow(
                  title: 'Use proxy',
                  subtitle: 'Applies to the browser and HTTP downloads',
                  value: _settings.proxyEnabled,
                  onChanged: (value) async {
                    await _settings.setProxyEnabled(value);
                    await ProxyService.instance.applyWebView();
                  },
                ),
                for (var index = 0;
                    index < _settings.proxyChain.length;
                    index++)
                  _ProxyRow(
                    value: _settings.proxyChain[index],
                    isPrimary: index == 0,
                    index: index,
                    count: _settings.proxyChain.length,
                    onUp: () => _moveProxy(index, -1),
                    onDown: () => _moveProxy(index, 1),
                    onRemove: () => _removeProxy(_settings.proxyChain[index]),
                  ),
                _TapRow(
                  title: 'Add proxy',
                  subtitle: 'HTTP or SOCKS5 with optional auth',
                  onTap: _addProxy,
                ),
                _DropdownRow<String>(
                  title: 'Secure DNS',
                  subtitle: 'Download resolution only',
                  value: _settings.secureDnsMode,
                  items: [
                    for (final entry in SecureDnsService.presetLabels.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) _settings.setSecureDnsMode(value);
                  },
                ),
                if (_settings.secureDnsMode == 'custom')
                  _TapRow(
                    title: 'Custom resolver URL',
                    subtitle: _settings.secureDnsCustom.isEmpty
                        ? 'Not set'
                        : _settings.secureDnsCustom,
                    onTap: _editSecureDnsCustom,
                  ),
              ],
            ),
            _Group(
              title: 'Privacy',
              children: [
                _TapRow(
                  title: 'Clear browser cookies',
                  subtitle: 'Logs you out of sites in the in-app browser',
                  onTap: _clearCookies,
                ),
                _TapRow(
                  title: 'Detection logs',
                  subtitle: 'Review extraction and detection activity',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const DetectionLogsScreen(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Linky 0.1.0',
              textAlign: TextAlign.center,
              style: AppText.body(12, color: palette.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Divider(height: 1, color: palette.border, indent: 16));
      }
      rows.add(children[i]);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(title),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(children: rows),
          ),
        ],
      ),
    );
  }
}

class _TapRow extends StatelessWidget {
  const _TapRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool enabled;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(
                      14,
                      weight: FontWeight.w600,
                      color: enabled
                          ? palette.foreground
                          : palette.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(12,
                        color: palette.mutedForeground),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing ??
                Icon(Icons.chevron_right_rounded,
                    size: 20, color: palette.mutedForeground),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppText.body(14, weight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: AppText.body(12,
                        color: palette.mutedForeground)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _DropdownRow<T> extends StatelessWidget {
  const _DropdownRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppText.body(14, weight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(12,
                        color: palette.mutedForeground)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 170),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: value,
                isDense: true,
                borderRadius: BorderRadius.circular(AppRadius.inner),
                icon: Icon(Icons.expand_more_rounded,
                    size: 18, color: palette.mutedForeground),
                style: AppText.body(13, color: palette.foreground),
                items: items,
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProxyRow extends StatelessWidget {
  const _ProxyRow({
    required this.value,
    required this.isPrimary,
    required this.index,
    required this.count,
    required this.onUp,
    required this.onDown,
    required this.onRemove,
  });

  final String value;
  final bool isPrimary;
  final int index;
  final int count;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(13, weight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(isPrimary ? 'Primary · tried first' : 'Fallback $index',
                    style: AppText.body(11,
                        color: palette.mutedForeground)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Move up',
            visualDensity: VisualDensity.compact,
            onPressed: index == 0 ? null : onUp,
            icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 20),
          ),
          IconButton(
            tooltip: 'Move down',
            visualDensity: VisualDensity.compact,
            onPressed: index == count - 1 ? null : onDown,
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
          ),
          IconButton(
            tooltip: 'Remove',
            visualDensity: VisualDensity.compact,
            onPressed: onRemove,
            icon: Icon(Icons.close_rounded,
                size: 18, color: palette.destructive),
          ),
        ],
      ),
    );
  }
}
