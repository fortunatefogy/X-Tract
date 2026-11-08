import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class SettingsService extends ChangeNotifier {
  SettingsService._();

  static final SettingsService instance = SettingsService._();

  ThemeMode _themeMode = ThemeMode.system;
  bool _onlyPlayingVideo = true;
  bool _filterJunkMedia = true;
  bool _initialized = false;

  ThemeMode get themeMode => _themeMode;
  bool get onlyPlayingVideo => _onlyPlayingVideo;
  bool get filterJunkMedia => _filterJunkMedia;
  bool get isInitialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final file = await _storeFile();
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          _themeMode = switch (decoded['theme_mode']) {
            'light' => ThemeMode.light,
            'dark' => ThemeMode.dark,
            _ => ThemeMode.system,
          };
          _onlyPlayingVideo = decoded['only_playing_video'] as bool? ?? true;
          _filterJunkMedia = decoded['filter_junk_media'] as bool? ?? true;
        }
      }
    } catch (_) {
      // Keep defaults when the settings file cannot be read.
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    await _save();
  }

  Future<void> setOnlyPlayingVideo(bool value) async {
    if (_onlyPlayingVideo == value) return;
    _onlyPlayingVideo = value;
    notifyListeners();
    await _save();
  }

  Future<void> setFilterJunkMedia(bool value) async {
    if (_filterJunkMedia == value) return;
    _filterJunkMedia = value;
    notifyListeners();
    await _save();
  }

  Future<File> _storeFile() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory('${documents.path}/LinkyDownloads');
    await directory.create(recursive: true);
    return File('${directory.path}/linky_settings.json');
  }

  Future<void> _save() async {
    try {
      final file = await _storeFile();
      await file.writeAsString(jsonEncode({
        'theme_mode': switch (_themeMode) {
          ThemeMode.light => 'light',
          ThemeMode.dark => 'dark',
          ThemeMode.system => 'system',
        },
        'only_playing_video': _onlyPlayingVideo,
        'filter_junk_media': _filterJunkMedia,
      }));
    } catch (_) {}
  }
}
