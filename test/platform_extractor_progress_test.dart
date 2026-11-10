import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linky/services/platform_extractor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('linky/extractor');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test('forwards native extractor progress to the active listener', () async {
    final started = Completer<Map<Object?, Object?>>();
    final finished = Completer<String>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'downloadWithYtDlp') {
        started.complete(call.arguments as Map<Object?, Object?>);
        return finished.future;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final seen = <double>[];
    final future = PlatformExtractor().download(
      pageUrl: 'https://example.com/watch',
      formatId: '137',
      outputDirectory: Directory.systemTemp,
      taskId: 'task-1',
      onProgress: seen.add,
    );

    final args = await started.future;
    expect(args['taskId'], 'task-1');

    await messenger.handlePlatformMessage(
      'linky/extractor',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('extractorProgress', {
          'taskId': 'task-1',
          'progress': 0.42,
        }),
      ),
      (_) {},
    );

    expect(seen, [0.42]);

    finished.complete('${Directory.systemTemp.path}/video.mp4');
    expect(await future, isA<File>());
  });

  test('ignores progress for unknown or finished tasks', () async {
    final started = Completer<void>();
    final finished = Completer<String>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'downloadWithYtDlp') {
        started.complete();
        return finished.future;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final seen = <double>[];
    final future = PlatformExtractor().download(
      pageUrl: 'https://example.com/watch',
      formatId: '137',
      outputDirectory: Directory.systemTemp,
      taskId: 'task-2',
      onProgress: seen.add,
    );
    await started.future;

    await messenger.handlePlatformMessage(
      'linky/extractor',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('extractorProgress', {
          'taskId': 'other-task',
          'progress': 0.9,
        }),
      ),
      (_) {},
    );
    expect(seen, isEmpty);

    finished.complete('${Directory.systemTemp.path}/video.mp4');
    await future;

    await messenger.handlePlatformMessage(
      'linky/extractor',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('extractorProgress', {
          'taskId': 'task-2',
          'progress': 0.9,
        }),
      ),
      (_) {},
    );
    expect(seen, isEmpty);
  });
}
