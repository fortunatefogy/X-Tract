import 'dart:io';

import 'device_resources.dart';
import 'mp4_faststart.dart';
import 'settings_service.dart';

class PostProcessResult {
  const PostProcessResult({required this.file, this.warning});

  final File file;
  final String? warning;
}

class PostProcessor {
  static const _repairExtensions = {
    'flv',
    'ts',
    'm2ts',
    'mts',
    'mkv',
    'avi',
    'mov',
    'wmv',
    '3gp',
    'webm',
    'm4v',
  };

  Future<PostProcessResult> process(
    File file, {
    required String type,
  }) async {
    if (type != 'video' && type != 'audio') {
      return PostProcessResult(file: file);
    }
    final settings = SettingsService.instance;
    var current = file;
    String? warning;

    if (settings.audioOnlyDownloads &&
        type == 'video' &&
        !_isAudioFile(current)) {
      final target = File('${_stem(current.path)}-audio.m4a');
      final output = await DeviceResources.instance.extractAudio(
        current.path,
        target.path,
      );
      if (output != null && await File(output).exists()) {
        await _deleteQuietly(current);
        current = File(output);
      } else {
        warning = 'Could not extract the audio track; kept the video file.';
      }
    } else {
      final repair = settings.repairStreams && _needsRepair(current);
      if ((settings.remuxDownloads || repair) &&
          !current.path.toLowerCase().endsWith('.mp4')) {
        final target = File('${_stem(current.path)}.mp4');
        final output = await DeviceResources.instance.remuxMedia(
          current.path,
          target.path,
        );
        if (output != null && await File(output).exists()) {
          await _deleteQuietly(current);
          current = File(output);
        } else {
          warning = 'Could not remux this file; kept the original download.';
        }
      }
    }

    final lower = current.path.toLowerCase();
    if (settings.fastStartDownloads &&
        (lower.endsWith('.mp4') || lower.endsWith('.m4a'))) {
      try {
        await Mp4FastStart.apply(current);
      } catch (_) {
        warning ??= 'Could not fast-start the MP4 file.';
      }
    }
    return PostProcessResult(file: current, warning: warning);
  }

  bool _isAudioFile(File file) {
    final name = file.path.toLowerCase();
    return RegExp(r'\.(mp3|m4a|aac|ogg|oga|opus|wav|flac|weba)$')
        .hasMatch(name);
  }

  bool _needsRepair(File file) {
    final name = file.path.toLowerCase();
    final dot = name.lastIndexOf('.');
    if (dot < 0) return true;
    return _repairExtensions.contains(name.substring(dot + 1));
  }

  String _stem(String path) {
    final dot = path.lastIndexOf('.');
    return dot > 0 ? path.substring(0, dot) : path;
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
