import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../services/adblock_service.dart';
import '../../services/download_service.dart';
import '../../services/proxy_service.dart';
import '../../services/secure_dns_service.dart';
import '../../services/settings_service.dart';
import '../../services/storage_service.dart';
import '../../services/suggestions_service.dart';
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
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add proxy'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'http://host:port or socks5://host:port',
            border: OutlineInputBorder(),
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
            child: const Text('Add'),
          ),
        ],
      ),
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
    final controller = TextEditingController(text: _settings.secureDnsCustom);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Custom DNS endpoint'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://dns.example.com/dns-query or tls://1.1.1.1',
            border: OutlineInputBorder(),
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
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value == null) return;
    await _settings.setSecureDnsCustom(value);
  }

  Future<void> _clearCookies() async {
    await CookieManager.instance().deleteAllCookies();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Browser cookies cleared.')),
    );
  }

  Future<void> _editCustomHome() async {
    final controller = TextEditingController(text: _settings.customHomeUrl);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Custom home page'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://example.com/',
            border: OutlineInputBorder(),
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
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value == null) return;
    await _settings.setCustomHomeUrl(value);
  }

  Future<void> _editCustomSearch() async {
    final controller = TextEditingController(text: _settings.customSearchUrl);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Custom search URL'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://example.com/search?q={query}',
            helperText: 'Use {query} where the search text goes.',
            border: OutlineInputBorder(),
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
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value == null) return;
    await _settings.setCustomSearchUrl(value);
  }

  String _sizeLabel(int bytes) {
    if (bytes <= 0) return 'Off (detect all sizes)';
    if (bytes < 1024 * 1024) return '${bytes ~/ 1024} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _editSupportedSitesUrl() async {
    final controller = TextEditingController(text: _settings.supportedSitesUrl);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remote supported sites list'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://example.com/linky-sites.json',
            helperText: 'JSON array of hosts or an object with a "sites" key.',
            border: OutlineInputBorder(),
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
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value != null) await _settings.setSupportedSitesUrl(value);
  }

  Future<void> _openDownloadsFolder() async {
    final opened = await StorageService.instance.openFolder();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          opened
              ? 'Opening the downloads folder.'
              : 'No file manager could open the downloads folder.',
        ),
      ),
    );
  }

  Future<void> _moveDownloads() async {
    try {
      final moved = await StorageService.instance.moveExistingDownloads();
      final target = await StorageService.instance.downloadDirectory();
      await DownloadService.instance.relocateDownloads(target.path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            moved == 0 ? 'No files needed moving.' : 'Moved $moved file(s).',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not move downloads: $error')),
      );
    }
  }

  Future<void> _editSuggestionListUrl() async {
    final controller = TextEditingController(text: _settings.suggestionListUrl);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remote suggestions list'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://example.com/linky-pages.json',
            helperText: 'JSON array of URLs or objects with title and url.',
            border: OutlineInputBorder(),
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
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value != null) await _settings.setSuggestionListUrl(value);
  }

  Future<void> _addAdBlockListUrl() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add ad-block list URL'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://example.com/ads.txt',
            helperText: 'Hosts, domain lists, or JSON arrays are supported.',
            border: OutlineInputBorder(),
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
            child: const Text('Add'),
          ),
        ],
      ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Loaded $count blocked host(s).')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update ad-block rules: $error')),
      );
    }
  }

  Future<void> _refreshSuggestions() async {
    try {
      final count = await SuggestionsService.instance.refreshRemote();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Loaded $count suggestion(s).')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load suggestions: $error')),
      );
    }
  }

  Future<void> _refreshSupportedSites() async {
    try {
      final count = await _settings.refreshSupportedSites();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Loaded $count supported site(s).')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load the list: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: ListView(
          children: [
            const _SectionHeader('Appearance'),
            RadioListTile<ThemeMode>(
              value: ThemeMode.system,
              groupValue: _settings.themeMode,
              title: const Text('Follow system'),
              onChanged: (mode) => _settings.setThemeMode(mode!),
            ),
            RadioListTile<ThemeMode>(
              value: ThemeMode.light,
              groupValue: _settings.themeMode,
              title: const Text('Light'),
              onChanged: (mode) => _settings.setThemeMode(mode!),
            ),
            RadioListTile<ThemeMode>(
              value: ThemeMode.dark,
              groupValue: _settings.themeMode,
              title: const Text('Dark'),
              onChanged: (mode) => _settings.setThemeMode(mode!),
            ),
            const Divider(),
            const _SectionHeader('Search engine'),
            ListTile(
              leading: const Icon(Icons.search),
              title: const Text('Search engine'),
              subtitle: const Text(
                  'Used for the browser start page and address-bar searches.'),
              trailing: DropdownButton<String>(
                value: _settings.searchEngine,
                onChanged: (value) {
                  if (value != null) _settings.setSearchEngine(value);
                },
                items: SettingsService.searchEnginePresets
                    .map((engine) => DropdownMenuItem<String>(
                          value: engine,
                          child: Text(
                              SettingsService.searchEngineLabel[engine] ??
                                  engine),
                        ))
                    .toList(growable: false),
              ),
            ),
            if (_settings.searchEngine == 'custom') ...[
              ListTile(
                leading: const Icon(Icons.home_outlined),
                title: const Text('Custom home page'),
                subtitle: Text(
                  _settings.customHomeUrl.isEmpty
                      ? 'Tap to set the start page address'
                      : _settings.customHomeUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: _editCustomHome,
              ),
              ListTile(
                leading: const Icon(Icons.link),
                title: const Text('Custom search URL'),
                subtitle: Text(
                  _settings.customSearchUrl.isEmpty
                      ? 'Tap to set a URL template with {query}'
                      : _settings.customSearchUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: _editCustomSearch,
              ),
            ],
            const Divider(),
            const _SectionHeader('Browser downloads'),
            SwitchListTile(
              value: _settings.onlyPlayingVideo,
              title: const Text('Only show the playing video'),
              subtitle: const Text(
                  'Hide other video items detected on the page while a video plays.'),
              onChanged: _settings.setOnlyPlayingVideo,
            ),
            SwitchListTile(
              value: _settings.filterJunkMedia,
              title: const Text('Filter junk media'),
              subtitle: const Text(
                  'Hide icons, thumbnails, UI images and small placeholder images.'),
              onChanged: _settings.setFilterJunkMedia,
            ),
            SwitchListTile(
              value: _settings.redirectPromptEnabled,
              title: const Text('Ask before cross-site redirects'),
              subtitle: const Text(
                  'Show a prompt when a page navigates to another website.'),
              onChanged: _settings.setRedirectPromptEnabled,
            ),
            SwitchListTile(
              value: _settings.blockPopups,
              title: const Text('Block pop-ups and redirect ads'),
              subtitle: const Text(
                  'Stop streaming sites from opening extra windows or redirecting when you press play. Reload the page after changing this.'),
              onChanged: _settings.setBlockPopups,
            ),
            SwitchListTile(
              value: _settings.desktopMode,
              title: const Text('Desktop mode for new tabs'),
              subtitle: const Text(
                  'Use a desktop user agent and wide viewport by default.'),
              onChanged: _settings.setDesktopMode,
            ),
            const Divider(),
            const _SectionHeader('Downloads'),
            ListTile(
              leading: const Icon(Icons.call_split),
              title: const Text('Parallel connections'),
              subtitle: const Text(
                  'Chunks used per download when the server supports ranges.'),
              trailing: DropdownButton<int>(
                value: _settings.downloadThreadCount,
                onChanged: (value) {
                  if (value != null) _settings.setDownloadThreadCount(value);
                },
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
              ),
            ),
            ListTile(
              leading: const Icon(Icons.downloading),
              title: const Text('Simultaneous downloads'),
              subtitle: const Text(
                  'Maximum number of downloads running at the same time.'),
              trailing: DropdownButton<int>(
                value: _settings.maxSimultaneousDownloads,
                onChanged: (value) {
                  if (value != null) {
                    _settings.setMaxSimultaneousDownloads(value);
                  }
                },
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
              ),
            ),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Downloads location'),
              subtitle:
                  const Text('Where completed files are saved on this device.'),
              trailing: DropdownButton<String>(
                value: _settings.downloadLocation,
                onChanged: (value) {
                  if (value != null) _settings.setDownloadLocation(value);
                },
                items: [
                  const DropdownMenuItem(
                    value: 'app',
                    child: Text('App storage'),
                  ),
                  const DropdownMenuItem(
                    value: 'external',
                    child: Text('Device storage'),
                  ),
                  if (StorageService.instance.hasSdCard)
                    const DropdownMenuItem(
                      value: 'sd',
                      child: Text('SD card'),
                    ),
                ],
              ),
            ),
            SwitchListTile(
              value: _settings.copyToPublicDownloads,
              title: const Text('Copy to public Downloads'),
              subtitle: const Text(
                  'Also place a copy in the system Downloads folder.'),
              onChanged: _settings.setCopyToPublicDownloads,
            ),
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text('Open downloads folder'),
              onTap: _openDownloadsFolder,
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outline),
              title: const Text('Move existing downloads'),
              subtitle: const Text(
                  'Move saved files to the current downloads location.'),
              onTap: _moveDownloads,
            ),
            const Divider(),
            const _SectionHeader('Post-processing'),
            SwitchListTile(
              value: _settings.remuxDownloads,
              title: const Text('Remux videos to MP4'),
              subtitle: const Text(
                  'Copy tracks into an MP4 container without re-encoding.'),
              onChanged: _settings.setRemuxDownloads,
            ),
            SwitchListTile(
              value: _settings.fastStartDownloads,
              title: const Text('Fast-start MP4 files'),
              subtitle: const Text(
                  'Move the MP4 index to the start for quicker playback.'),
              onChanged: _settings.setFastStartDownloads,
            ),
            SwitchListTile(
              value: _settings.repairStreams,
              title: const Text('Repair FLV and stream containers'),
              subtitle: const Text(
                  'Try to remux FLV, TS, and similar files when they are saved.'),
              onChanged: _settings.setRepairStreams,
            ),
            SwitchListTile(
              value: _settings.audioOnlyDownloads,
              title: const Text('Save audio only (M4A)'),
              subtitle: const Text(
                  'Extract the audio track from downloaded videos instead of keeping the video.'),
              onChanged: _settings.setAudioOnlyDownloads,
            ),
            const Divider(),
            const _SectionHeader('Detection'),
            SwitchListTile(
              value: _settings.detectVideos,
              title: const Text('Detect videos'),
              subtitle: const Text('Include video and streaming media.'),
              onChanged: _settings.setDetectVideos,
            ),
            SwitchListTile(
              value: _settings.detectImages,
              title: const Text('Detect images'),
              subtitle: const Text('Include image files and thumbnails.'),
              onChanged: _settings.setDetectImages,
            ),
            SwitchListTile(
              value: _settings.detectAudio,
              title: const Text('Detect audio'),
              subtitle: const Text('Include music and audio-only files.'),
              onChanged: _settings.setDetectAudio,
            ),
            SwitchListTile(
              value: _settings.detectDocuments,
              title: const Text('Detect documents'),
              subtitle: const Text('Include PDFs, office files and text.'),
              onChanged: _settings.setDetectDocuments,
            ),
            ListTile(
              leading: const Icon(Icons.filter_alt_outlined),
              title: const Text('Ignore small media'),
              subtitle: Text(
                  'Skip media smaller than ${_sizeLabel(_settings.minMediaSizeBytes)}.'),
              trailing: DropdownButton<int>(
                value: _settings.minMediaSizeBytes,
                onChanged: (value) {
                  if (value != null) _settings.setMinMediaSizeBytes(value);
                },
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
              ),
            ),
            const Divider(),
            const _SectionHeader('Supported sites'),
            SwitchListTile(
              value: _settings.onlySupportedSites,
              title: const Text('Only use the supported sites list'),
              subtitle: const Text(
                  'Skip on-device extraction for pages outside the list.'),
              onChanged: _settings.setOnlySupportedSites,
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Remote list URL'),
              subtitle: Text(
                _settings.supportedSitesUrl.isEmpty
                    ? 'None · using ${SettingsService.defaultSupportedHosts.length} built-in sites'
                    : _settings.supportedSitesUrl,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: _editSupportedSitesUrl,
            ),
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('Update remote list'),
              subtitle: Text(
                  '${_settings.remoteSupportedHosts.length} host(s) loaded from the remote list.'),
              trailing: const Icon(Icons.download_outlined),
              enabled: _settings.supportedSitesUrl.isNotEmpty,
              onTap: _settings.supportedSitesUrl.isEmpty
                  ? null
                  : _refreshSupportedSites,
            ),
            const Divider(),
            const _SectionHeader('Suggestions'),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Remote suggestions URL'),
              subtitle: Text(
                _settings.suggestionListUrl.isEmpty
                    ? 'None · using history and bookmarks'
                    : _settings.suggestionListUrl,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: _editSuggestionListUrl,
            ),
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('Update suggestions'),
              subtitle:
                  const Text('Load page suggestions from the remote list.'),
              trailing: const Icon(Icons.download_outlined),
              enabled: _settings.suggestionListUrl.isNotEmpty,
              onTap: _settings.suggestionListUrl.isEmpty
                  ? null
                  : _refreshSuggestions,
            ),
            const Divider(),
            const _SectionHeader('Ad blocker'),
            SwitchListTile(
              value: _settings.adBlockEnabled,
              title: const Text('Enable ad blocker'),
              subtitle: Text(
                'Blocks ${AdBlockService.instance.ruleCount} known ad host(s) in the browser.',
              ),
              onChanged: _settings.setAdBlockEnabled,
            ),
            for (final listUrl in _settings.adBlockListUrls)
              ListTile(
                leading: const Icon(Icons.list_alt),
                title: Text(
                  listUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  tooltip: 'Remove list',
                  onPressed: () async {
                    await AdBlockService.instance.removeListUrl(listUrl);
                    if (mounted) setState(() {});
                  },
                  icon: const Icon(Icons.close),
                ),
              ),
            ListTile(
              leading: const Icon(Icons.add_link),
              title: const Text('Add rule list URL'),
              onTap: _addAdBlockListUrl,
            ),
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('Update ad-block lists'),
              subtitle:
                  const Text('Download and cache the selected rule lists.'),
              trailing: const Icon(Icons.download_outlined),
              enabled: _settings.adBlockListUrls.isNotEmpty,
              onTap: _settings.adBlockListUrls.isEmpty ? null : _refreshAdBlock,
            ),
            const Divider(),
            const _SectionHeader('Diagnostics'),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('Detection logs'),
              subtitle: const Text('Review extraction and detection activity.'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const DetectionLogsScreen(),
                ),
              ),
            ),
            const Divider(),
            const _SectionHeader('Proxy & DNS'),
            SwitchListTile(
              value: _settings.proxyEnabled,
              title: const Text('Use proxy'),
              subtitle:
                  const Text('Applies to the browser and HTTP downloads.'),
              onChanged: (value) async {
                await _settings.setProxyEnabled(value);
                await ProxyService.instance.applyWebView();
              },
            ),
            for (var index = 0; index < _settings.proxyChain.length; index++)
              ListTile(
                leading: const Icon(Icons.lan_outlined),
                title: Text(_settings.proxyChain[index]),
                subtitle: Text(
                    index == 0 ? 'Primary · tried first' : 'Fallback $index'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Move up',
                      onPressed:
                          index == 0 ? null : () => _moveProxy(index, -1),
                      icon: const Icon(Icons.arrow_upward),
                    ),
                    IconButton(
                      tooltip: 'Move down',
                      onPressed: index == _settings.proxyChain.length - 1
                          ? null
                          : () => _moveProxy(index, 1),
                      icon: const Icon(Icons.arrow_downward),
                    ),
                    IconButton(
                      tooltip: 'Remove',
                      onPressed: () =>
                          _removeProxy(_settings.proxyChain[index]),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            ListTile(
              leading: const Icon(Icons.add_link),
              title: const Text('Add proxy'),
              onTap: _addProxy,
            ),
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: const Text('Secure DNS'),
              subtitle: Text(
                  'Download resolution only · ${SecureDnsService.presetLabels[_settings.secureDnsMode] ?? _settings.secureDnsMode}'),
              trailing: DropdownButton<String>(
                value: _settings.secureDnsMode,
                onChanged: (value) {
                  if (value != null) _settings.setSecureDnsMode(value);
                },
                items: [
                  for (final entry in SecureDnsService.presetLabels.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
              ),
            ),
            if (_settings.secureDnsMode == 'custom')
              ListTile(
                leading: const Icon(Icons.link),
                title: const Text('Custom resolver URL'),
                subtitle: Text(
                  _settings.secureDnsCustom.isEmpty
                      ? 'Not set'
                      : _settings.secureDnsCustom,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: _editSecureDnsCustom,
              ),
            const Divider(),
            const _SectionHeader('Privacy'),
            ListTile(
              leading: const Icon(Icons.cookie_outlined),
              title: const Text('Clear browser cookies'),
              subtitle:
                  const Text('Logs you out of sites in the in-app browser.'),
              onTap: () => _clearCookies(),
            ),
          ],
        ),
      );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      );
}
