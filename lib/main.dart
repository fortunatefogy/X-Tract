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

  PaintingBinding.instance.imageCache
    ..maximumSize = 200
    ..maximumSizeBytes = 256 << 20;

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
  runApp(const LinkyApp());
  unawaited(_initRemaining());
}

Future<void> _initRemaining() async {
  await Future.wait<void>([
    HistoryService.instance.init().catchError((_) {}),
    BookmarksService.instance.init().catchError((_) {}),
    SuggestionsService.instance.init().catchError((_) {}),
    AdBlockService.instance.init().catchError((_) {}),
    ProxyService.instance.applyWebView().catchError((_) {}),
    PlaybackPositionService.instance.init().catchError((_) {}),
    DownloadService.instance.init().catchError((_) {}),
  ]);
}
