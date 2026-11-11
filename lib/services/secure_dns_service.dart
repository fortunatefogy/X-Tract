import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'settings_service.dart';

class SecureDnsService {
  SecureDnsService._();

  static final SecureDnsService instance = SecureDnsService._();

  static const presets = <String, String>{
    'cloudflare': 'https://cloudflare-dns.com/dns-query',
    'google': 'https://dns.google/dns-query',
    'quad9': 'https://dns.quad9.net/dns-query',
    'adguard': 'https://dns.adguard-dns.com/dns-query',
  };

  static const presetLabels = <String, String>{
    'off': 'System DNS',
    'cloudflare': 'Cloudflare (DoH)',
    'google': 'Google (DoH)',
    'quad9': 'Quad9 (DoH)',
    'adguard': 'AdGuard (DoH)',
    'custom': 'Custom DoH / DoT',
  };

  final Map<String, _DnsEntry> _cache = {};

  bool get enabled => SettingsService.instance.secureDnsMode != 'off';

  String? get _endpoint {
    final mode = SettingsService.instance.secureDnsMode;
    if (mode == 'custom') {
      final custom = SettingsService.instance.secureDnsCustom.trim();
      return custom.isEmpty ? null : custom;
    }
    return presets[mode];
  }

  Future<void> configure(HttpClient client) async {
    if (!enabled || _endpoint == null) return;
    client.connectionFactory = (uri, proxyHost, proxyPort) async {
      final direct = proxyHost == null;
      final host = proxyHost ?? uri.host;
      final port = proxyPort ?? uri.port;
      final task = await _connect(host, port);
      // Dart only upgrades connectionFactory sockets to TLS when the request
      // is routed through a proxy. For direct HTTPS we must do it ourselves,
      // otherwise plain HTTP is sent to port 443 and the response fails to
      // parse ("Invalid request method").
      if (!direct || uri.scheme.toLowerCase() != 'https') return task;
      return ConnectionTask.fromSocket(
        task.socket.then(
          (socket) => SecureSocket.secure(socket, host: uri.host),
        ),
        task.cancel,
      );
    };
  }

  Future<ConnectionTask<Socket>> _connect(String host, int port) async {
    final address = await resolve(host);
    return Socket.startConnect(address ?? host, port);
  }

  Future<InternetAddress?> resolve(String host) async {
    final cached = _cache[host];
    if (cached != null && cached.expires.isAfter(DateTime.now())) {
      return cached.address;
    }
    final endpoint = _endpoint;
    if (endpoint == null) return null;
    if (InternetAddress.tryParse(host) != null) {
      return InternetAddress(host);
    }
    try {
      final addresses = endpoint.startsWith('tls://') ||
              endpoint.startsWith('dot://') ||
              endpoint.startsWith('tls:')
          ? await _resolveDoT(host, endpoint)
          : await _resolveDoH(host, endpoint);
      if (addresses.isEmpty) return null;
      final address = addresses.first;
      _cache[host] = _DnsEntry(
        address,
        DateTime.now().add(const Duration(minutes: 5)),
      );
      return address;
    } catch (_) {
      return null;
    }
  }

  Future<List<InternetAddress>> _resolveDoH(String host, String endpoint) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..userAgent = 'Linky Android';
    try {
      final addresses = <InternetAddress>[];
      for (final type in ['A', 'AAAA']) {
        final uri = Uri.parse(endpoint).replace(
          queryParameters: {'name': host, 'type': type},
        );
        final request = await client.getUrl(uri);
        request.headers.set(HttpHeaders.acceptHeader, 'application/dns-json');
        final response = await request.close().timeout(
              const Duration(seconds: 10),
            );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          await response.drain<void>();
          continue;
        }
        final body = await response
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 10));
        final decoded = jsonDecode(body);
        final answers = decoded is Map ? decoded['Answer'] : null;
        if (answers is! List) continue;
        for (final answer in answers) {
          if (answer is! Map) continue;
          final data = answer['data']?.toString();
          if (data == null) continue;
          final address = InternetAddress.tryParse(data);
          if (address != null) addresses.add(address);
        }
      }
      return addresses;
    } finally {
      client.close(force: true);
    }
  }

  Future<List<InternetAddress>> _resolveDoT(
    String host,
    String endpoint,
  ) async {
    final hostPart = endpoint
        .replaceFirst(RegExp(r'^(tls://|dot://|tls:)'), '')
        .split('/')
        .first
        .split(':')
        .first;
    if (hostPart.isEmpty) return const [];
    final socket = await SecureSocket.connect(
      hostPart,
      853,
      timeout: const Duration(seconds: 10),
    );
    final iterator = StreamIterator<Uint8List>(socket);
    final buffer = BytesBuilder();
    Future<Uint8List?> readExactly(int length) async {
      while (buffer.length < length) {
        if (!await iterator.moveNext()) return null;
        buffer.add(iterator.current);
      }
      final all = buffer.takeBytes();
      final result = all.sublist(0, length);
      if (all.length > length) {
        buffer.add(all.sublist(length));
      }
      return result;
    }

    try {
      final addresses = <InternetAddress>[];
      for (final type in [1, 28]) {
        final query = _buildQuery(host, type);
        final length = ByteData(2)..setUint16(0, query.length);
        socket.add(length.buffer.asUint8List());
        socket.add(query);
        await socket.flush();
        final sizeData = await readExactly(2);
        if (sizeData == null) break;
        final size = ByteData.sublistView(sizeData).getUint16(0);
        final response = await readExactly(size);
        if (response == null) break;
        addresses.addAll(_parseAnswers(response));
      }
      return addresses;
    } finally {
      await iterator.cancel();
      await socket.close();
      socket.destroy();
    }
  }

  Uint8List _buildQuery(String host, int type) {
    final builder = BytesBuilder();
    final id = Random().nextInt(65536);
    builder.add([id >> 8, id & 0xff, 0x01, 0x00, 0x00, 0x01]);
    builder.add([0, 0, 0, 0, 0, 0]);
    for (final label in host.split('.')) {
      final bytes = utf8.encode(label);
      if (bytes.isEmpty || bytes.length > 63) continue;
      builder.addByte(bytes.length);
      builder.add(bytes);
    }
    builder.addByte(0);
    builder.add([type >> 8, type & 0xff, 0x00, 0x01]);
    return builder.takeBytes();
  }

  List<InternetAddress> _parseAnswers(Uint8List data) {
    if (data.length < 12) return const [];
    final view = ByteData.sublistView(data);
    final questionCount = view.getUint16(4);
    final answerCount = view.getUint16(6);
    var offset = 12;
    for (var index = 0; index < questionCount && offset < data.length; index++) {
      while (offset < data.length && data[offset] != 0) {
        offset += data[offset] + 1;
      }
      offset += 5;
    }
    final addresses = <InternetAddress>[];
    for (var index = 0; index < answerCount && offset + 10 <= data.length; index++) {
      if ((data[offset] & 0xc0) == 0xc0) {
        offset += 2;
      } else {
        while (offset < data.length && data[offset] != 0) {
          offset += data[offset] + 1;
        }
        offset++;
      }
      if (offset + 10 > data.length) break;
      final answerView = ByteData.sublistView(data, offset);
      final answerType = answerView.getUint16(0);
      final length = answerView.getUint16(8);
      offset += 10;
      if (offset + length > data.length) break;
      final payload = data.sublist(offset, offset + length);
      if (answerType == 1 && length == 4) {
        addresses.add(InternetAddress(payload.join('.'), type: InternetAddressType.IPv4));
      } else if (answerType == 28 && length == 16) {
        final parts = <String>[];
        for (var part = 0; part < 16; part += 2) {
          parts.add(
            ((payload[part] << 8) | payload[part + 1]).toRadixString(16),
          );
        }
        addresses.add(InternetAddress(parts.join(':'), type: InternetAddressType.IPv6));
      }
      offset += length;
    }
    return addresses;
  }
}

class _DnsEntry {
  const _DnsEntry(this.address, this.expires);

  final InternetAddress address;
  final DateTime expires;
}
