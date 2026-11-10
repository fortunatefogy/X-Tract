import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:linky/services/mp4_faststart.dart';

Uint8List _box(String type, List<int> payload) {
  final size = 8 + payload.length;
  final data = ByteData(size);
  data.setUint32(0, size);
  for (var index = 0; index < 4; index++) {
    data.setUint8(4 + index, type.codeUnitAt(index));
  }
  for (var index = 0; index < payload.length; index++) {
    data.setUint8(8 + index, payload[index]);
  }
  return data.buffer.asUint8List();
}

Uint8List _stco(int offset) {
  final payload = ByteData(12);
  payload.setUint32(0, 0);
  payload.setUint32(4, 1);
  payload.setUint32(8, offset);
  return _box('stco', payload.buffer.asUint8List());
}

Uint8List _moov(int offset) => _box('moov', _stco(offset));

void main() {
  test('moves moov before mdat and rewrites stco offsets', () async {
    final directory = await Directory.systemTemp.createTemp('linky-faststart');
    addTearDown(() => directory.delete(recursive: true));
    final ftyp = _box('ftyp', List<int>.filled(8, 0));
    final mdat = _box('mdat', [9, 9, 9, 9]);
    final originalStcoOffset = ftyp.length + 8;
    final moov = _moov(originalStcoOffset);
    final file = File('${directory.path}/movie.mp4');
    await file.writeAsBytes([...ftyp, ...mdat, ...moov]);

    final changed = await Mp4FastStart.apply(file);
    expect(changed, isTrue);

    final bytes = await file.readAsBytes();
    expect(String.fromCharCodes(bytes.sublist(4, 8)), 'ftyp');
    expect(String.fromCharCodes(bytes.sublist(20, 24)), 'moov');
    final newMdatOffset = ftyp.length + moov.length;
    expect(String.fromCharCodes(bytes.sublist(newMdatOffset + 4, newMdatOffset + 8)), 'mdat');
    final stcoEntry = ByteData.sublistView(bytes).getUint32(ftyp.length + 8 + 16);
    expect(stcoEntry, originalStcoOffset + moov.length);
  });
}
