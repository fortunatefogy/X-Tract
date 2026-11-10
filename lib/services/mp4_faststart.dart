import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

class Mp4FastStart {
  static const _containers = {
    'moov',
    'trak',
    'mdia',
    'minf',
    'stbl',
    'edts',
    'mvex',
    'moof',
    'traf',
  };

  static Future<bool> apply(File file) async {
    final lower = file.path.toLowerCase();
    if (!lower.endsWith('.mp4') && !lower.endsWith('.m4a')) return false;
    final length = await file.length();
    if (length < 16) return false;
    final source = await file.open(mode: FileMode.read);
    IOSink? sink;
    File? temporary;
    var sourceClosed = false;
    try {
      final boxes = <_Mp4Box>[];
      var offset = 0;
      while (offset + 8 <= length) {
        await source.setPosition(offset);
        final header = await source.read(8);
        if (header.length < 8) break;
        final size32 = _u32(header, 0);
        final type = String.fromCharCodes(header.sublist(4, 8));
        var size = size32;
        var headerSize = 8;
        if (size32 == 1) {
          final large = await source.read(8);
          if (large.length < 8) break;
          size = _u64(large, 0);
          headerSize = 16;
        } else if (size32 == 0) {
          size = length - offset;
        }
        if (size < headerSize || offset + size > length) break;
        boxes.add(_Mp4Box(offset, size, type));
        offset += size;
      }
      final moovIndex = boxes.indexWhere((box) => box.type == 'moov');
      final mdatIndex = boxes.indexWhere((box) => box.type == 'mdat');
      if (moovIndex < 0 || mdatIndex < 0 || moovIndex < mdatIndex) {
        return false;
      }
      final moov = boxes[moovIndex];
      final mdat = boxes[mdatIndex];
      await source.setPosition(moov.offset);
      final moovBytes = await source.read(moov.size);
      if (moovBytes.length != moov.size) return false;

      final newOrder = <_Mp4Box>[];
      var inserted = false;
      for (final box in boxes) {
        if (box.type == 'moov') continue;
        newOrder.add(box);
        if (!inserted && box.type == 'ftyp') {
          newOrder.add(moov);
          inserted = true;
        }
      }
      if (!inserted) newOrder.insert(0, moov);

      var newMdatOffset = 0;
      for (final box in newOrder) {
        if (identical(box, mdat)) break;
        newMdatOffset += box.size;
      }
      final delta = newMdatOffset - mdat.offset;
      if (delta == 0) return false;
      _patchOffsets(moovBytes, 8, moovBytes.length, delta);

      temporary = File('${file.path}.faststart');
      sink = temporary.openWrite();
      for (final box in newOrder) {
        if (identical(box, moov)) {
          sink.add(moovBytes);
          continue;
        }
        await source.setPosition(box.offset);
        var remaining = box.size;
        while (remaining > 0) {
          final chunk = await source.read(min(remaining, 1024 * 1024));
          if (chunk.isEmpty) {
            throw const FileSystemException('The MP4 file ended unexpectedly.');
          }
          sink.add(chunk);
          remaining -= chunk.length;
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      await source.close();
      sourceClosed = true;
      await file.delete();
      await temporary.rename(file.path);
      temporary = null;
      return true;
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      if (temporary != null && await temporary.exists()) {
        try {
          await temporary.delete();
        } catch (_) {}
      }
      if (!sourceClosed) {
        try {
          await source.close();
        } catch (_) {}
      }
    }
  }

  static void _patchOffsets(
    Uint8List data,
    int start,
    int end,
    int delta,
  ) {
    var position = start;
    while (position + 8 <= end) {
      var size = _u32(data, position);
      final type = String.fromCharCodes(
        data.sublist(position + 4, position + 8),
      );
      var header = 8;
      if (size == 1) {
        if (position + 16 > end) break;
        size = _u64(data, position + 8);
        header = 16;
      } else if (size == 0) {
        size = end - position;
      }
      if (size < header || position + size > end) break;
      if (type == 'stco') {
        final count = _u32(data, position + 12);
        var entry = position + 16;
        for (var index = 0; index < count && entry + 4 <= position + size; index++) {
          _putU32(data, entry, _u32(data, entry) + delta);
          entry += 4;
        }
      } else if (type == 'co64') {
        final count = _u32(data, position + 12);
        var entry = position + 16;
        for (var index = 0; index < count && entry + 8 <= position + size; index++) {
          _putU64(data, entry, _u64(data, entry) + delta);
          entry += 8;
        }
      } else if (_containers.contains(type)) {
        _patchOffsets(data, position + header, position + size, delta);
      }
      position += size;
    }
  }

  static int _u32(Uint8List data, int offset) =>
      (data[offset] << 24) |
      (data[offset + 1] << 16) |
      (data[offset + 2] << 8) |
      data[offset + 3];

  static int _u64(Uint8List data, int offset) =>
      (_u32(data, offset) << 32) | _u32(data, offset + 4);

  static void _putU32(Uint8List data, int offset, int value) {
    data[offset] = (value >> 24) & 0xff;
    data[offset + 1] = (value >> 16) & 0xff;
    data[offset + 2] = (value >> 8) & 0xff;
    data[offset + 3] = value & 0xff;
  }

  static void _putU64(Uint8List data, int offset, int value) {
    _putU32(data, offset, (value >> 32) & 0xffffffff);
    _putU32(data, offset + 4, value & 0xffffffff);
  }
}

class _Mp4Box {
  const _Mp4Box(this.offset, this.size, this.type);

  final int offset;
  final int size;
  final String type;
}
