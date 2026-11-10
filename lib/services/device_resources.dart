import 'package:flutter/services.dart';

class DeviceMemoryInfo {
  const DeviceMemoryInfo({
    required this.availableBytes,
    required this.totalBytes,
    required this.thresholdBytes,
    required this.lowMemory,
  });

  final int availableBytes;
  final int totalBytes;
  final int thresholdBytes;
  final bool lowMemory;
}

class DeviceStorageInfo {
  const DeviceStorageInfo({
    required this.freeBytes,
    required this.totalBytes,
  });

  final int freeBytes;
  final int totalBytes;
}

class DeviceResources {
  DeviceResources._();

  static final DeviceResources instance = DeviceResources._();

  static const _channel = MethodChannel('linky/device');

  Future<DeviceMemoryInfo?> memoryInfo() async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'getMemoryInfo',
      );
      if (raw == null) return null;
      return DeviceMemoryInfo(
        availableBytes: (raw['availableBytes'] as num?)?.toInt() ?? 0,
        totalBytes: (raw['totalBytes'] as num?)?.toInt() ?? 0,
        thresholdBytes: (raw['thresholdBytes'] as num?)?.toInt() ?? 0,
        lowMemory: raw['lowMemory'] == true,
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<DeviceStorageInfo?> storageInfo() async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'getStorageInfo',
      );
      if (raw == null) return null;
      return DeviceStorageInfo(
        freeBytes: (raw['freeBytes'] as num?)?.toInt() ?? 0,
        totalBytes: (raw['totalBytes'] as num?)?.toInt() ?? 0,
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<Uint8List?> decryptAes128(
    Uint8List data,
    Uint8List key,
    Uint8List iv,
  ) async {
    try {
      return await _channel.invokeMethod<Uint8List>('decryptAes128', {
        'data': data,
        'key': key,
        'iv': iv,
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<List<String>> externalDirectories() async {
    try {
      final raw = await _channel.invokeListMethod<String>('getExternalDirs');
      return raw ?? const [];
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  Future<bool> saveToPublicDownloads(
    String path,
    String displayName,
  ) async {
    try {
      return await _channel.invokeMethod<bool>(
            'saveToPublicDownloads',
            {'path': path, 'displayName': displayName},
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> openFolder(String path) async {
    try {
      return await _channel.invokeMethod<bool>('openFolder', {'path': path}) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> enterPip() async {
    try {
      return await _channel.invokeMethod<bool>('enterPip') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<String?> remuxMedia(String inputPath, String outputPath) async {
    try {
      return await _channel.invokeMethod<String>('remuxMedia', {
        'inputPath': inputPath,
        'outputPath': outputPath,
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<String?> extractAudio(String inputPath, String outputPath) async {
    try {
      return await _channel.invokeMethod<String>('extractAudio', {
        'inputPath': inputPath,
        'outputPath': outputPath,
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<String?> muxMedia(
    String videoPath,
    String audioPath,
    String outputPath,
  ) async {
    try {
      return await _channel.invokeMethod<String>('muxMedia', {
        'videoPath': videoPath,
        'audioPath': audioPath,
        'outputPath': outputPath,
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
