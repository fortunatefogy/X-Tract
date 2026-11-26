import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';
import 'services/adblock_service.dart';
import 'services/bookmarks_service.dart';
import 'services/browser_session_service.dart';
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

  PaintingBinding.instance.imageCache
    ..maximumSize = 200
    ..maximumSizeBytes = 256 << 20;

  if (startMode == 'share') {
    await SettingsService.instance.init();
    await StorageService.instance.init();
    runApp(
      CometApp(
        startInShareMode: true,
        initialShareText: sharedText,
      ),
    );
    // The share popup runs in its own engine (separate from the main activity).
    // Skip the download-manager init here so two isolates never track the same
    // background tasks; DownloadService initialises lazily if a download starts.
    return;
  }

  await SettingsService.instance.init();
  await StorageService.instance.init();
  runApp(const CometApp());
  unawaited(_initRemaining());
}

Future<void> _initRemaining() async {
  await Future.wait<void>([
    HistoryService.instance.init().catchError((_) {}),
    BookmarksService.instance.init().catchError((_) {}),
    BrowserSessionService.instance.load().catchError((_) {}),
    SuggestionsService.instance.init().catchError((_) {}),
    AdBlockService.instance.init().catchError((_) {}),
    ProxyService.instance.applyWebView().catchError((_) {}),
    PlaybackPositionService.instance.init().catchError((_) {}),
    DownloadService.instance.init().catchError((_) {}),
  ]);
}
