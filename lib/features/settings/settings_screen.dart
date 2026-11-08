import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../services/settings_service.dart';
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

  Future<void> _clearCookies() async {
    await CookieManager.instance().deleteAllCookies();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Browser cookies cleared.')),
    );
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
            const Divider(),
            const _SectionHeader('Diagnostics'),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('Detection logs'),
              subtitle:
                  const Text('Review extraction and detection activity.'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const DetectionLogsScreen(),
                ),
              ),
            ),
            const Divider(),
            const _SectionHeader('Privacy'),
            ListTile(
              leading: const Icon(Icons.cookie_outlined),
              title: const Text('Clear browser cookies'),
              subtitle: const Text('Logs you out of sites in the in-app browser.'),
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
