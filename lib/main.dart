import 'package:flutter/material.dart';

import 'app.dart';
import 'services/download_service.dart';
import 'services/settings_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsService.instance.init();
  await DownloadService.instance.init();
  runApp(const LinkyApp());
}
