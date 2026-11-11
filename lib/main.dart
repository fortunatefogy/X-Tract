import 'dart:async';

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

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final startMode = args.isNotEmpty ? args.first : 'main';
  final sharedText =
      args.length > 1 && args[1].trim().isNotEmpty ? args[1] : null;

  if (startMode == 'share') {
    await SettingsService.instance.init();
    await StorageService.instance.init();
    runApp(
      LinkyApp(
        startInShareMode: true,
        initialShareText: sharedText,
      ),
    );
    unawaited(_initRemaining());
    return;
  }

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

Future<void> _initRemaining() async {
  for (final init in [
    HistoryService.instance.init,
    BookmarksService.instance.init,
    SuggestionsService.instance.init,
    AdBlockService.instance.init,
    ProxyService.instance.applyWebView,
    PlaybackPositionService.instance.init,
    DownloadService.instance.init,
  ]) {
    try {
      await init();
    } catch (_) {}
  }
}
