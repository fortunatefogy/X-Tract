import 'dart:convert';

/// Result of a positive network match.
class AdblockMatch {
  const AdblockMatch(this.rule);

  final String rule;
}

/// A compact uBlock Origin / Adblock Plus compatible filter engine.
///
/// It implements the network rule subset that matters for a WebView:
/// host anchors, substring/wildcard patterns, `^` separators, exceptions,
/// `$important`, domain and party options, resource types and `$badfilter`.
/// It also compiles cosmetic (`##`) rules into a stylesheet injected into the
/// page, mirroring the approach used by Brave's adblock-rust.
class AdblockEngine {
  AdblockEngine._({
    required Map<String, List<_NetworkRule>> hostRules,
    required Map<int, List<_NetworkRule>> tokenRules,
    required List<_NetworkRule> unkeyedRules,
    required List<_CosmeticRule> cosmeticRules,
    required this.networkRuleCount,
    required this.cosmeticRuleCount,
  })  : _hostRules = hostRules,
        _tokenRules = tokenRules,
        _unkeyedRules = unkeyedRules,
        _cosmeticRules = cosmeticRules;

  final Map<String, List<_NetworkRule>> _hostRules;
  final Map<int, List<_NetworkRule>> _tokenRules;
  final List<_NetworkRule> _unkeyedRules;
  final List<_CosmeticRule> _cosmeticRules;

  final int networkRuleCount;
  final int cosmeticRuleCount;

  bool get isEmpty => networkRuleCount == 0 && cosmeticRuleCount == 0;

  factory AdblockEngine.build(
    Iterable<String> lists, {
    Iterable<String> extraHosts = const [],
    Iterable<String> extraRules = const [],
    Iterable<String> extraSelectors = const [],
  }) {
    final builder = _EngineBuilder();
    for (final text in lists) {
      builder.addList(text);
    }
    for (final host in extraHosts) {
      builder.addNetwork('||$host^');
    }
    for (final rule in extraRules) {
      builder.addNetwork(rule);
    }
    for (final selector in extraSelectors) {
      builder.addCosmetic(selector);
    }
    return builder.build();
  }

  AdblockMatch? match(
    Uri url, {
    Uri? documentUri,
    String? resourceType,
  }) {
    if (_hostRules.isEmpty && _tokenRules.isEmpty && _unkeyedRules.isEmpty) {
      return null;
    }
    final rawUrl = url.toString();
    final lowerUrl = rawUrl.toLowerCase();
    final host = url.host.toLowerCase();
    if (host.isEmpty) return null;
    final documentHost = documentUri?.host.toLowerCase();
    final type = resourceType ?? _inferType(url);
    final thirdParty = documentHost == null || documentHost.isEmpty
        ? null
        : !_sameParty(host, documentHost);

    final candidates = <_NetworkRule>[];
    final labels = host.split('.');
    for (var index = 0; index < labels.length; index++) {
      final suffix = labels.sublist(index).join('.');
      final rules = _hostRules[suffix];
      if (rules != null) candidates.addAll(rules);
    }
    if (_tokenRules.isNotEmpty) {
      for (final token in _urlTokens(lowerUrl)) {
        final rules = _tokenRules[token];
        if (rules != null) candidates.addAll(rules);
      }
    }
    if (_unkeyedRules.isNotEmpty) candidates.addAll(_unkeyedRules);

    var blocked = false;
    String? blockedRule;
    var exception = false;
    for (final rule in candidates) {
      if (!_optionsMatch(
        rule,
        host,
        documentHost,
        type,
        thirdParty,
      )) {
        continue;
      }
      if (!rule.matches(rawUrl, lowerUrl, host)) continue;
      if (rule.exception) {
        exception = true;
      } else if (rule.important) {
        return AdblockMatch(rule.description);
      } else {
        blocked = true;
        blockedRule ??= rule.description;
      }
    }
    if (blocked && !exception) {
      return AdblockMatch(blockedRule ?? '');
    }
    return null;
  }

  String cosmeticScript(Uri? documentUri, {bool genericOnly = false}) {
    if (_cosmeticRules.isEmpty) return '';
    final host = documentUri?.host.toLowerCase() ?? '';
    final selectors = <String>{};
    final exceptions = <String>{};
    for (final rule in _cosmeticRules) {
      if (genericOnly && rule.include != null) continue;
      if (!rule.appliesTo(host)) continue;
      if (rule.exception) {
        exceptions.add(rule.selector);
      } else {
        selectors.add(rule.selector);
      }
    }
    selectors.removeAll(exceptions);
    return _styleScript(selectors);
  }

  bool _optionsMatch(
    _NetworkRule rule,
    String host,
    String? documentHost,
    String type,
    bool? thirdParty,
  ) {
    if (rule.includeDomains != null) {
      if (documentHost == null || documentHost.isEmpty) return false;
      if (!rule.includeDomains!.any((d) => _hostMatches(documentHost, d))) {
        return false;
      }
    }
    if (rule.excludeDomains.isNotEmpty) {
      if (documentHost == null) return false;
      if (rule.excludeDomains.any((d) => _hostMatches(documentHost, d))) {
        return false;
      }
    }
    if (rule.thirdParty != null) {
      if (thirdParty == null || rule.thirdParty != thirdParty) return false;
    }
    if (rule.resourceTypes != null && !rule.resourceTypes!.contains(type)) {
      return false;
    }
    if (rule.excludeResourceTypes.contains(type)) return false;
    return true;
  }

  static const _imageExtensions = {
    'png',
    'jpg',
    'jpeg',
    'gif',
    'webp',
    'avif',
    'svg',
    'bmp',
    'ico',
    'tif',
    'tiff',
  };
  static const _scriptExtensions = {'js', 'mjs', 'cjs', 'wasm'};
  static const _mediaExtensions = {
    'mp4',
    'm4v',
    'webm',
    'mov',
    'mkv',
    'avi',
    'flv',
    '3gp',
    'mp3',
    'm4a',
    'aac',
    'ogg',
    'oga',
    'opus',
    'wav',
    'flac',
    'ts',
    'm4s',
  };
  static const _fontExtensions = {
    'woff',
    'woff2',
    'ttf',
    'otf',
    'eot',
  };

  static String _inferType(Uri uri) {
    final path = uri.path.toLowerCase();
    final dot = path.lastIndexOf('.');
    final extension =
        dot >= 0 && dot < path.length - 1 ? path.substring(dot + 1) : '';
    if (_scriptExtensions.contains(extension)) return 'script';
    if (extension == 'css') return 'stylesheet';
    if (_imageExtensions.contains(extension)) return 'image';
    if (_mediaExtensions.contains(extension)) return 'media';
    if (_fontExtensions.contains(extension)) return 'font';
    if (extension == 'html' || extension == 'htm' || extension == 'xhtml') {
      return 'subdocument';
    }
    if (extension == 'json' || extension == 'xml') return 'xmlhttprequest';
    return 'other';
  }

  static List<int> _urlTokens(String lowerUrl) {
    final tokens = <int>{};
    var start = -1;
    for (var index = 0; index < lowerUrl.length; index++) {
      final code = lowerUrl.codeUnitAt(index);
      if (_isAlphaNumeric(code)) {
        if (start < 0) start = index;
      } else if (start >= 0) {
        if (index - start >= 3) {
          tokens.add(lowerUrl.substring(start, index).hashCode);
        }
        start = -1;
      }
    }
    if (start >= 0 && lowerUrl.length - start >= 3) {
      tokens.add(lowerUrl.substring(start).hashCode);
    }
    return tokens.toList(growable: false);
  }
}

class _EngineBuilder {
  final List<_NetworkRule> _networkRules = [];
  final List<_CosmeticRule> _cosmeticRules = [];
  int _nextId = 0;

  void addList(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (trimmed.startsWith('[')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is List) {
          for (final entry in decoded) {
            final value = entry.toString().trim();
            if (value.isNotEmpty) addNetwork('||$value^');
          }
          return;
        }
      } catch (_) {}
    }
    for (final rawLine in const LineSplitter().convert(text)) {
      addLine(rawLine);
    }
  }

  void addLine(String rawLine) {
    final line = rawLine.trim();
    if (line.isEmpty) return;
    if (line.startsWith('!') || line.startsWith('[')) return;
    if (line.startsWith('#') && !_looksCosmetic(line)) return;
    if (line.startsWith('0.0.0.0 ') || line.startsWith('127.0.0.1 ')) {
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length >= 2) addNetwork('||${parts.last}^');
      return;
    }
    if (_looksCosmetic(line)) {
      addCosmeticLine(line);
      return;
    }
    if (_bareHostRegExp.hasMatch(line)) {
      addNetwork('||$line^');
      return;
    }
    addNetwork(line);
  }

  void addNetwork(String rawRule) {
    var rule = rawRule.trim();
    if (rule.isEmpty || rule.length > 4096) return;
    var exception = false;
    if (rule.startsWith('@@')) {
      exception = true;
      rule = rule.substring(2);
    }
    if (rule.isEmpty) return;

    final options = _NetworkOptions();
    final dollar = rule.indexOf(r'$');
    if (dollar >= 0) {
      if (!options.parse(rule.substring(dollar + 1))) return;
      rule = rule.substring(0, dollar);
      if (rule.isEmpty) return;
    }
    if (rule.startsWith('/') && rule.endsWith('/') && rule.length > 2) {
      return;
    }

    var hostAnchor = false;
    var startAnchor = false;
    var endAnchor = false;
    var body = rule;
    if (body.startsWith('||')) {
      hostAnchor = true;
      body = body.substring(2);
    } else if (body.startsWith('|')) {
      startAnchor = true;
      body = body.substring(1);
    }
    if (body.endsWith('|')) {
      endAnchor = true;
      body = body.substring(0, body.length - 1);
    }
    if (body.isEmpty) return;

    final entry = _NetworkRule(
      id: _nextId++,
      exception: exception,
      important: options.important,
      badfilter: options.badfilter,
      matchCase: options.matchCase,
      hostAnchor: hostAnchor,
      startAnchor: startAnchor,
      endAnchor: endAnchor,
      body: body,
      includeDomains: options.includeDomains,
      excludeDomains: options.excludeDomains,
      resourceTypes: options.resourceTypes,
      excludeResourceTypes: options.excludeResourceTypes,
      thirdParty: options.thirdParty,
    );
    _networkRules.add(entry);
  }

  void addCosmetic(String selector) {
    final cleaned = selector.trim();
    if (!_validSelector(cleaned)) return;
    _cosmeticRules.add(_CosmeticRule(
      include: null,
      exclude: const {},
      selector: cleaned,
      exception: false,
    ));
  }

  void addCosmeticLine(String line) {
    final marker = _cosmeticMarker(line);
    if (marker == null) return;
    final index = line.indexOf(marker);
    final prefix = line.substring(0, index).trim();
    final selector = line.substring(index + marker.length).trim();
    if (!_validSelector(selector)) return;
    if (marker != '##' && marker != '#@#') {
      // Procedural, scriptlet and style rules need a full uBO runtime and are
      // not representable as plain CSS.
      return;
    }
    final exception = marker == '#@#';
    final include = <String>[];
    final exclude = <String>{};
    if (prefix.isNotEmpty) {
      for (final raw in prefix.split(',')) {
        var domain = raw.trim().toLowerCase();
        if (domain.isEmpty) continue;
        if (domain.startsWith('~')) {
          domain = domain.substring(1);
          if (!_validCosmeticDomain(domain)) return;
          exclude.add(domain);
        } else {
          if (!_validCosmeticDomain(domain)) return;
          include.add(domain);
        }
      }
    }
    _cosmeticRules.add(_CosmeticRule(
      include: include.isEmpty ? null : include,
      exclude: exclude,
      selector: selector,
      exception: exception,
    ));
  }

  AdblockEngine build() {
    final disabled = <String>{
      for (final rule in _networkRules)
        if (rule.badfilter) rule.canonicalKey,
    };
    final seen = <String>{};
    final active = <_NetworkRule>[];
    for (final rule in _networkRules) {
      if (rule.badfilter) continue;
      if (disabled.contains(rule.canonicalKey)) continue;
      if (!seen.add(rule.canonicalKey)) continue;
      active.add(rule);
    }

    final frequencies = <int, int>{};
    final ruleTokens = <List<int>>[];
    for (final rule in active) {
      final tokens = rule.indexTokens;
      ruleTokens.add(tokens);
      for (final token in tokens) {
        frequencies[token] = (frequencies[token] ?? 0) + 1;
      }
    }

    final hostRules = <String, List<_NetworkRule>>{};
    final tokenRules = <int, List<_NetworkRule>>{};
    final unkeyed = <_NetworkRule>[];
    for (var index = 0; index < active.length; index++) {
      final rule = active[index];
      final hostKey = rule.hostKey;
      if (hostKey != null) {
        hostRules.putIfAbsent(hostKey, () => []).add(rule);
        continue;
      }
      var bestToken = -1;
      var bestFrequency = 1 << 62;
      for (final token in ruleTokens[index]) {
        final frequency = frequencies[token] ?? 0;
        if (frequency < bestFrequency) {
          bestFrequency = frequency;
          bestToken = token;
        }
      }
      if (bestToken < 0) {
        unkeyed.add(rule);
      } else {
        tokenRules.putIfAbsent(bestToken, () => []).add(rule);
      }
    }

    final cosmeticSeen = <String>{};
    final cosmetic = <_CosmeticRule>[];
    for (final rule in _cosmeticRules) {
      final key =
          '${rule.exception}|${rule.include?.join(',') ?? ''}|${rule.exclude.join(',')}|${rule.selector}';
      if (cosmeticSeen.add(key)) cosmetic.add(rule);
    }

    return AdblockEngine._(
      hostRules: hostRules,
      tokenRules: tokenRules,
      unkeyedRules: unkeyed,
      cosmeticRules: cosmetic,
      networkRuleCount: active.length,
      cosmeticRuleCount: cosmetic.length,
    );
  }
}

class _NetworkOptions {
  bool important = false;
  bool badfilter = false;
  bool matchCase = false;
  bool? thirdParty;
  List<String>? includeDomains;
  final Set<String> excludeDomains = {};
  Set<String>? resourceTypes;
  final Set<String> excludeResourceTypes = {};

  bool parse(String text) {
    for (final rawOption in text.split(',')) {
      var option = rawOption.trim().toLowerCase();
      if (option.isEmpty) continue;
      var negate = false;
      if (option.startsWith('~')) {
        negate = true;
        option = option.substring(1);
      }
      var value = '';
      final equals = option.indexOf('=');
      if (equals >= 0) {
        value = option.substring(equals + 1);
        option = option.substring(0, equals);
      }
      switch (option) {
        case 'third-party':
        case '3p':
          thirdParty = !negate;
          break;
        case 'first-party':
        case '1p':
          thirdParty = negate;
          break;
        case 'important':
          important = true;
          break;
        case 'badfilter':
          badfilter = true;
          break;
        case 'match-case':
          matchCase = true;
          break;
        case 'domain':
        case 'from':
          _parseDomains(value);
          break;
        case 'redirect':
        case 'redirect-rule':
        case 'empty':
        case 'mp4':
        case 'nooptext':
          break;
        case 'script':
          _addType('script', negate);
          break;
        case 'image':
          _addType('image', negate);
          break;
        case 'stylesheet':
        case 'css':
          _addType('stylesheet', negate);
          break;
        case 'object':
        case 'object-subrequest':
          _addType('object', negate);
          break;
        case 'xmlhttprequest':
        case 'xhr':
          _addType('xmlhttprequest', negate);
          break;
        case 'subdocument':
        case 'frame':
        case 'sub_frame':
          _addType('subdocument', negate);
          break;
        case 'document':
        case 'doc':
        case 'main_frame':
          _addType('document', negate);
          break;
        case 'font':
          _addType('font', negate);
          break;
        case 'media':
          _addType('media', negate);
          break;
        case 'websocket':
          _addType('websocket', negate);
          break;
        case 'ping':
        case 'beacon':
          _addType('ping', negate);
          break;
        case 'other':
          _addType('other', negate);
          break;
        case 'popup':
          _addType('popup', negate);
          break;
        case 'all':
        case 'network':
        case 'urlskip':
          break;
        case 'removeparam':
        case 'queryprune':
        case 'csp':
        case 'permissions':
        case 'cookie':
        case 'header':
        case 'replace':
        case 'uritransform':
        case 'elemhide':
        case 'generichide':
        case 'specifichide':
        case 'genericblock':
        case 'inline-script':
        case 'inline-font':
        case 'webrtc':
        case 'method':
        case 'denyallow':
        case 'app':
        case 'sitekey':
        case 'rewrite':
        case 'to':
        case 'strict1p':
        case 'strict3p':
          return false;
        default:
          return false;
      }
    }
    return true;
  }

  void _addType(String type, bool negate) {
    if (negate) {
      excludeResourceTypes.add(type);
    } else {
      (resourceTypes ??= <String>{}).add(type);
    }
  }

  void _parseDomains(String value) {
    if (value.isEmpty) return;
    for (final raw in value.split('|')) {
      var domain = raw.trim();
      if (domain.isEmpty) continue;
      if (domain.startsWith('~')) {
        domain = domain.substring(1);
        if (domain.isNotEmpty) excludeDomains.add(domain);
      } else {
        (includeDomains ??= <String>[]).add(domain);
      }
    }
  }
}

class _NetworkRule {
  _NetworkRule({
    required this.id,
    required this.exception,
    required this.important,
    required this.badfilter,
    required this.matchCase,
    required this.hostAnchor,
    required this.startAnchor,
    required this.endAnchor,
    required this.body,
    required this.includeDomains,
    required this.excludeDomains,
    required this.resourceTypes,
    required this.excludeResourceTypes,
    required this.thirdParty,
  })  : lowerBody = matchCase ? body : body.toLowerCase(),
        _tokens = _tokenize(body, matchCase);

  final int id;
  final bool exception;
  final bool important;
  final bool badfilter;
  final bool matchCase;
  final bool hostAnchor;
  final bool startAnchor;
  final bool endAnchor;
  final String body;
  final String lowerBody;
  final List<String>? includeDomains;
  final Set<String> excludeDomains;
  final Set<String>? resourceTypes;
  final Set<String> excludeResourceTypes;
  final bool? thirdParty;
  final List<int> _tokens;

  String get description => '${hostAnchor ? '||' : startAnchor ? '|' : ''}'
      '$body${endAnchor ? '|' : ''}';

  String get canonicalKey {
    final types = resourceTypes?.toList()?..sort();
    final excluded = excludeResourceTypes.toList()..sort();
    final include = includeDomains?.map((d) => d.toLowerCase()).toList()
      ?..sort();
    final exclude = excludeDomains.map((d) => d.toLowerCase()).toList()..sort();
    return [
      exception,
      important,
      matchCase,
      hostAnchor,
      startAnchor,
      endAnchor,
      body,
      include?.join('|') ?? '',
      exclude.join('|'),
      types?.join('|') ?? '',
      excluded.join('|'),
      thirdParty,
    ].join('\u0001');
  }

  List<int> get indexTokens => _tokens;

  String? get hostKey {
    if (!hostAnchor || body.isEmpty) return null;
    final end = _hostKeyEnd;
    if (end <= 0) return null;
    final host = body.substring(0, end);
    if (!_hostName.hasMatch(host)) return null;
    if (end == body.length) return null;
    final boundary = body.codeUnitAt(end);
    if (boundary != 0x5e && boundary != 0x2f && boundary != 0x3a) {
      return null;
    }
    return host.toLowerCase();
  }

  int get _hostKeyEnd {
    for (var index = 0; index < body.length; index++) {
      final code = body.codeUnitAt(index);
      if (code == 0x5e || code == 0x2f || code == 0x3a) return index;
      if (code == 0x2a || code == 0x7c || code == 0x3f || code == 0x2e) {
        if (code == 0x2e) continue;
        return -1;
      }
    }
    return body.length;
  }

  bool matches(String rawUrl, String lowerUrl, String host) {
    final url = matchCase ? rawUrl : lowerUrl;
    final pattern = lowerBody;
    if (hostAnchor) {
      final hostStart = url.indexOf(host);
      if (hostStart < 0) return false;
      var index = hostStart;
      final hostEnd = hostStart + host.length;
      while (index <= hostEnd) {
        if (_matchAt(pattern, 0, url, index, endAnchor)) return true;
        final dot = url.indexOf('.', index);
        if (dot < 0 || dot >= hostEnd) break;
        index = dot + 1;
      }
      return false;
    }
    if (startAnchor) {
      return _matchAt(pattern, 0, url, 0, endAnchor);
    }
    if (!pattern.contains('*') && !pattern.contains('^')) {
      return url.contains(pattern);
    }
    for (var index = 0; index < url.length; index++) {
      if (_matchAt(pattern, 0, url, index, endAnchor)) return true;
    }
    return false;
  }

  static List<int> _tokenize(String pattern, bool matchCase) {
    final lower = matchCase ? pattern : pattern.toLowerCase();
    final tokens = <int>{};
    var start = -1;
    for (var index = 0; index < lower.length; index++) {
      final code = lower.codeUnitAt(index);
      if (_isAlphaNumeric(code)) {
        if (start < 0) start = index;
      } else if (start >= 0) {
        _addRun(lower, start, index, tokens);
        start = -1;
      }
    }
    if (start >= 0) _addRun(lower, start, lower.length, tokens);
    return tokens.toList(growable: false);
  }

  static void _addRun(
    String value,
    int start,
    int end,
    Set<int> tokens,
  ) {
    if (end - start < 3) return;
    if (start > 0 && value[start - 1] == '*') return;
    if (end < value.length && value[end] == '*') return;
    tokens.add(value.substring(start, end).hashCode);
  }
}

class _CosmeticRule {
  const _CosmeticRule({
    required this.include,
    required this.exclude,
    required this.selector,
    required this.exception,
  });

  final List<String>? include;
  final Set<String> exclude;
  final String selector;
  final bool exception;

  bool appliesTo(String host) {
    if (include != null) {
      if (!include!
          .any((domain) => domain == '*' || _hostMatches(host, domain))) {
        return false;
      }
    }
    if (exclude.any((domain) => _hostMatches(host, domain))) return false;
    return true;
  }
}

bool _hostMatches(String host, String domain) {
  if (domain.isEmpty) return false;
  if (domain == '*') return true;
  if (host == domain) return true;
  return host.endsWith('.$domain');
}

bool _isAlphaNumeric(int code) =>
    (code >= 0x61 && code <= 0x7a) ||
    (code >= 0x41 && code <= 0x5a) ||
    (code >= 0x30 && code <= 0x39);

bool _isSeparator(int code) =>
    !_isAlphaNumeric(code) &&
    code != 0x5f &&
    code != 0x2d &&
    code != 0x2e &&
    code != 0x25;

bool _matchAt(String pattern, int patternStart, String text, int textStart,
    bool endAnchor) {
  var p = patternStart;
  var t = textStart;
  var starPattern = -1;
  var starText = -1;
  while (true) {
    if (p < pattern.length) {
      final code = pattern.codeUnitAt(p);
      if (code == 0x2a) {
        starPattern = p++;
        starText = t;
        continue;
      }
      if (code == 0x5e) {
        if (t == text.length) {
          p++;
          continue;
        }
        if (_isSeparator(text.codeUnitAt(t))) {
          p++;
          t++;
          continue;
        }
      } else if (t < text.length && text.codeUnitAt(t) == code) {
        p++;
        t++;
        continue;
      }
      if (starPattern >= 0) {
        p = starPattern + 1;
        t = ++starText;
        if (t > text.length) return false;
        continue;
      }
      return false;
    }
    if (t == text.length) return true;
    if (!endAnchor) return true;
    if (starPattern >= 0) {
      p = starPattern + 1;
      t = ++starText;
      if (t > text.length) return false;
      continue;
    }
    return false;
  }
}

String _styleScript(Set<String> selectors) {
  if (selectors.isEmpty) return '';
  final limited = <String>[];
  var totalLength = 0;
  for (final selector in selectors) {
    if (limited.length >= 20000) break;
    if (totalLength + selector.length > 400000) break;
    limited.add(selector);
    totalLength += selector.length + 32;
  }
  final css = limited.map((s) => '$s{display:none!important}').join('\n');
  final payload = jsonEncode(css);
  return '(function(){try{'
      "var id='linky-adblock-style';"
      'var css=$payload;'
      'var style=document.getElementById(id);'
      'if(!style){style=document.createElement("style");style.id=id;'
      '(document.head||document.documentElement).appendChild(style);}'
      'style.textContent=css;'
      '}catch(e){}})();';
}

const _bareHost = r'^[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z]{2,}$';
final _hostName = RegExp(r'^[a-z0-9.-]+$');
final _bareHostRegExp = RegExp(_bareHost);

const _cosmeticMarkers = <String>[
  '#@?#',
  '#?@#',
  r'#@$#',
  '#@%#',
  r'#$#',
  '#%#',
  '#?#',
  '#@#',
  '##',
];

String? _cosmeticMarker(String line) {
  for (final marker in _cosmeticMarkers) {
    if (line.contains(marker)) return marker;
  }
  return null;
}

bool _looksCosmetic(String line) => _cosmeticMarker(line) != null;

bool _validCosmeticDomain(String domain) {
  if (domain == '*') return true;
  if (!domain.contains('.')) return false;
  return RegExp(r'^[a-z0-9*][a-z0-9.*-]*$').hasMatch(domain);
}

bool _validSelector(String selector) {
  if (selector.isEmpty || selector.length > 4000) return false;
  if (selector.contains('\n') || selector.contains('\r')) return false;
  if (selector.contains('{') || selector.contains('}')) return false;
  if (selector.contains('+js(') ||
      selector.contains(':style(') ||
      selector.contains(':remove(') ||
      selector.contains(':has-text(') ||
      selector.contains(':matches-') ||
      selector.contains(':xpath(')) {
    return false;
  }
  return true;
}

const _multiPartSuffixes = <String>{
  'ac.uk',
  'co.uk',
  'gov.uk',
  'ltd.uk',
  'me.uk',
  'net.uk',
  'org.uk',
  'plc.uk',
  'com.au',
  'edu.au',
  'gov.au',
  'net.au',
  'org.au',
  'id.au',
  'co.nz',
  'net.nz',
  'org.nz',
  'govt.nz',
  'co.jp',
  'ne.jp',
  'or.jp',
  'go.jp',
  'ac.jp',
  'co.kr',
  'ne.kr',
  'or.kr',
  'go.kr',
  'com.br',
  'net.br',
  'org.br',
  'gov.br',
  'com.cn',
  'net.cn',
  'org.cn',
  'gov.cn',
  'com.hk',
  'net.hk',
  'org.hk',
  'gov.hk',
  'com.sg',
  'net.sg',
  'org.sg',
  'gov.sg',
  'com.mx',
  'net.mx',
  'org.mx',
  'gob.mx',
  'com.ar',
  'net.ar',
  'org.ar',
  'gob.ar',
  'com.tr',
  'net.tr',
  'org.tr',
  'gov.tr',
  'com.tw',
  'net.tw',
  'org.tw',
  'gov.tw',
  'com.my',
  'net.my',
  'org.my',
  'gov.my',
  'com.ph',
  'net.ph',
  'org.ph',
  'gov.ph',
  'com.pk',
  'net.pk',
  'org.pk',
  'gov.pk',
  'com.ng',
  'net.ng',
  'org.ng',
  'gov.ng',
  'com.eg',
  'net.eg',
  'org.eg',
  'gov.eg',
  'com.sa',
  'net.sa',
  'org.sa',
  'gov.sa',
  'com.ua',
  'net.ua',
  'org.ua',
  'gov.ua',
  'com.pl',
  'net.pl',
  'org.pl',
  'gov.pl',
  'com.ru',
  'net.ru',
  'org.ru',
  'gov.ru',
  'co.in',
  'net.in',
  'org.in',
  'gov.in',
  'ac.in',
  'firm.in',
  'gen.in',
  'ind.in',
  'co.id',
  'net.id',
  'org.id',
  'go.id',
  'co.za',
  'net.za',
  'org.za',
  'gov.za',
  'com.es',
  'net.es',
  'org.es',
  'gob.es',
  'com.it',
  'net.it',
  'org.it',
  'gov.it',
  'com.fr',
  'net.fr',
  'org.fr',
  'gouv.fr',
  'com.de',
  'net.de',
  'org.de',
  'gov.de',
  'co.il',
  'net.il',
  'org.il',
  'gov.il',
  'co.th',
  'net.th',
  'org.th',
  'go.th',
  'co.ve',
  'net.ve',
  'org.ve',
  'gob.ve',
  'com.co',
  'net.co',
  'org.co',
  'gov.co',
  'com.pe',
  'net.pe',
  'org.pe',
  'gob.pe',
  'com.ec',
  'net.ec',
  'org.ec',
  'gob.ec',
  'com.uy',
  'net.uy',
  'org.uy',
  'gub.uy',
  'com.py',
  'net.py',
  'org.py',
  'gov.py',
  'com.bo',
  'net.bo',
  'org.bo',
  'gob.bo',
  'com.do',
  'net.do',
  'org.do',
  'gob.do',
  'com.gt',
  'net.gt',
  'org.gt',
  'gob.gt',
  'com.sv',
  'net.sv',
  'org.sv',
  'gob.sv',
  'com.hn',
  'net.hn',
  'org.hn',
  'gob.hn',
  'com.ni',
  'net.ni',
  'org.ni',
  'gob.ni',
  'com.pa',
  'net.pa',
  'org.pa',
  'gob.pa',
  'com.cr',
  'net.cr',
  'org.cr',
  'go.cr',
  'com.gh',
  'net.gh',
  'org.gh',
  'gov.gh',
  'com.ke',
  'net.ke',
  'org.ke',
  'go.ke',
  'com.tz',
  'net.tz',
  'org.tz',
  'go.tz',
  'com.ug',
  'net.ug',
  'org.ug',
  'go.ug',
  'co.mz',
  'net.mz',
  'org.mz',
  'gov.mz',
  'com.et',
  'net.et',
  'org.et',
  'gov.et',
  'com.bd',
  'net.bd',
  'org.bd',
  'gov.bd',
  'com.lk',
  'net.lk',
  'org.lk',
  'gov.lk',
  'com.np',
  'net.np',
  'org.np',
  'gov.np',
  'com.kh',
  'net.kh',
  'org.kh',
  'gov.kh',
  'com.la',
  'net.la',
  'org.la',
  'gov.la',
  'com.mm',
  'net.mm',
  'org.mm',
  'gov.mm',
  'com.vn',
  'net.vn',
  'org.vn',
  'gov.vn',
  'com.bn',
  'net.bn',
  'org.bn',
  'gov.bn',
  'com.mo',
  'net.mo',
  'org.mo',
  'gov.mo',
};

String _registrableDomain(String host) {
  final labels = host.split('.');
  if (labels.length <= 2) return host;
  final lastTwo = labels.sublist(labels.length - 2).join('.');
  if (_multiPartSuffixes.contains(lastTwo) && labels.length >= 3) {
    return labels.sublist(labels.length - 3).join('.');
  }
  return lastTwo;
}

bool _sameParty(String requestHost, String documentHost) {
  return _registrableDomain(requestHost) == _registrableDomain(documentHost);
}
