import 'package:flutter/material.dart';

import 'app.dart';
import 'services/adblock_service.dart';
import 'services/bookmarks_service.dart';
import 'services/download_service.dart';
import 'services/history_service.dart';
import 'services/playback_position_service.dart';
import 'services/proxy_service.dart';
import 'services/settings_service.dart';
import 'services/storage_service.dart';
import 'services/suggestions_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsService.instance.init();
  await StorageService.instance.init();
  await HistoryService.instance.init();
  await BookmarksService.instance.init();
  await SuggestionsService.instance.init();
  await AdBlockService.instance.init();
  await ProxyService.instance.applyWebView();
  await PlaybackPositionService.instance.init();
  await DownloadService.instance.init();
  runApp(const LinkyApp());
}
