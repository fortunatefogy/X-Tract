import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../models/media_item.dart';
import '../../services/adblock_service.dart';
import '../../services/bookmarks_service.dart';
import '../../services/challenge_hosts.dart';
import '../../services/download_service.dart';
import '../../services/history_service.dart';
import '../../services/media_downloader.dart';
import '../../services/media_extractor.dart';
import '../../services/platform_extractor.dart';
import '../../services/settings_service.dart';
import '../../services/storage_service.dart';
import '../../services/suggestions_service.dart';
import '../../services/detection_log_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/media_thumbnail.dart';
import '../bookmarks/bookmarks_screen.dart';
import '../downloads/downloads_screen.dart';
import '../downloads/remote_preview_screen.dart';
import '../history/history_screen.dart';
import '../settings/settings_screen.dart';

class MediaBrowserScreen extends StatefulWidget {
  const MediaBrowserScreen({required this.initialUrl, super.key});

  final String initialUrl;

  @override
  State<MediaBrowserScreen> createState() => _MediaBrowserScreenState();
}

class _MediaBrowserScreenState extends State<MediaBrowserScreen> {
  static const _desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36';
  static const _mobileUserAgent =
      'Mozilla/5.0 (Linux; Android 16) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/149.0.0.0 Mobile Safari/537.36';

  static const _webrtcBlockScript = r'''(() => {
    try {
      const blocked = function () {
        throw new DOMException('WebRTC is disabled by Linky.', 'NotAllowedError');
      };
      const Stub = function () {
        this.createDataChannel = blocked;
        this.createOffer = blocked;
        this.createAnswer = blocked;
        this.setLocalDescription = blocked;
        this.setRemoteDescription = blocked;
        this.addIceCandidate = blocked;
        this.getStats = function () { return Promise.resolve(new Map()); };
        this.close = function () {};
        this.addEventListener = function () {};
        this.removeEventListener = function () {};
      };
      window.RTCPeerConnection = Stub;
      window.webkitRTCPeerConnection = Stub;
      window.mozRTCPeerConnection = Stub;
    } catch (_) {}
  })()''';

  static const _popupGuardScript = r'''(() => {
    if (window.__linkyPopupGuard) return;
    window.__linkyPopupGuard = true;
    let lastClickHref = '';
    let lastClickAt = 0;
    try {
      window.open = function (url) {
        try {
          if (!url) return null;
          const target = new URL(String(url), location.href).href;
          const recentClick = Date.now() - lastClickAt < 2000;
          const sameAsClick = lastClickHref &&
            (target === lastClickHref || new URL(lastClickHref).host === new URL(target).host);
          if (!recentClick || !sameAsClick) return null;
          try {
            window.flutter_inappwebview?.callHandler('linkyOpenTab', target);
          } catch (_) {}
        } catch (_) {}
        return null;
      };
    } catch (_) {}
    try {
      document.addEventListener('click', function (event) {
        try {
          const anchor = event.target && event.target.closest ? event.target.closest('a[href]') : null;
          if (!anchor) return;
          const resolved = new URL(anchor.href, location.href);
          const target = String(anchor.getAttribute('target') || '').toLowerCase();
          if (event.isTrusted && /^https?:/i.test(resolved.href)) {
            lastClickHref = resolved.href;
            lastClickAt = Date.now();
            try {
              window.flutter_inappwebview?.callHandler(
                'linkyClickedLink',
                JSON.stringify({url: resolved.href, ts: Date.now()})
              );
            } catch (_) {}
          }
          if (target !== '_blank' && target !== '_new') return;
          if (!event.isTrusted) {
            event.preventDefault();
            event.stopImmediatePropagation();
          }
        } catch (_) {}
      }, true);
    } catch (_) {}
  })()''';

  static const _monitorScript = r'''(() => {
    if (!window.__linkyMediaHooks) {
      window.__linkyMediaHooks = true;
      const report = (url, type) => { try { window.flutter_inappwebview?.callHandler('linkyFoundMedia', JSON.stringify({url, type})); } catch (_) {} };
      const originalFetch = window.fetch;
      window.fetch = async function(...args) { const response = await originalFetch.apply(this, args); const type = response.headers.get('content-type') || ''; if (/video|audio|image|mpegurl|dash\+xml|pdf|msword|officedocument|text\/plain/i.test(type)) report(response.url, type); return response; };
      const originalOpen = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function(method, url, ...rest) { this.__linkyUrl = url; this.addEventListener('load', function() { const type = this.getResponseHeader('content-type') || ''; if (/video|audio|image|mpegurl|dash\+xml|pdf|msword|officedocument|text\/plain/i.test(type)) report(new URL(this.responseURL || this.__linkyUrl, location.href).href, type); }); return originalOpen.call(this, method, url, ...rest); };
    }
    const found = new Map();
    const add = (url, kind, details = {}) => {
      if (!url || typeof url !== 'string') return;
      try {
        const resolved = new URL(url, document.baseURI).href;
        if (!/^(https?:|blob:)/i.test(resolved)) return;
        const previous = found.get(resolved) || {};
        const merged = {url: resolved, kind, ...previous, ...details};
        if (!('isPlaying' in details) && 'isPlaying' in previous) merged.isPlaying = previous.isPlaying;
        if (!('foundIn' in details) && 'foundIn' in previous) merged.foundIn = previous.foundIn;
        found.set(resolved, merged);
      } catch (_) {}
    };
    add(location.href, 'page');
    const roots = [document];
    const all = selector => roots.flatMap(root => { try { return Array.from(root.querySelectorAll(selector)); } catch (_) { return []; } });
    const addSrcset = (value, kind) => (value || '').split(',').forEach(part => add(part.trim().split(/\s+/)[0], kind));
    const hasPlayingVideo = all('video').some(media => !media.paused && !media.ended && media.readyState >= 2);
    all('video,audio').forEach(media => {
      const kind = media.tagName.toLowerCase();
      const playing = kind === 'video' && !media.paused && !media.ended && media.readyState >= 2;
      const details = kind === 'video' ? {isPlaying: playing, foundIn: 'video element', ...(media.poster ? {thumbnail: new URL(media.poster, document.baseURI).href} : {})} : {};
      add(media.currentSrc || media.src, kind, details);
      media.querySelectorAll('source,track').forEach(source => add(source.src, source.tagName === 'TRACK' ? 'subtitle' : kind));
    });
    all('img,picture source').forEach(el => {
      try {
        if (el.tagName === 'IMG') {
          const width = Number(el.naturalWidth || el.width) || 0;
          const height = Number(el.naturalHeight || el.height) || 0;
          const label = String((el.className && el.className.baseVal !== undefined ? el.className.baseVal : el.className) || '') + ' ' + String(el.id || '');
          if (el.offsetParent === null && el.getClientRects().length === 0) return;
          if (width && height && (width < 200 || height < 200)) return;
          if (/icon|logo|avatar|emoji|sprite|badge|button/i.test(label)) return;
          if (el.closest && el.closest('header,nav,footer')) return;
        }
      } catch (_) {}
      const details = {title: el.title || '', alt: el.alt || '', width: Number(el.naturalWidth || el.width) || null, height: Number(el.naturalHeight || el.height) || null, foundIn: el.srcset ? 'srcset' : el.dataset.src || el.dataset.lazySrc || el.dataset.original ? 'lazy image' : 'img'};
      add(el.currentSrc || el.src || el.dataset.src || el.dataset.lazySrc || el.dataset.original || el.dataset.originalSrc || el.dataset.actualsrc || el.dataset.url || el.dataset.echo, 'image', details);
      addSrcset(el.srcset || el.dataset.srcset || el.dataset.lazySrcset, 'image');
    });
    all('iframe').forEach(el => add(el.src, 'embed'));
    all('a[href],link[href]').forEach(el => add(el.href, 'link'));
    all('meta[property^="og:"],meta[name^="twitter:"]').forEach(el => {
      const prop = el.getAttribute('property') || el.name || '';
      if (hasPlayingVideo && /image/i.test(prop)) return;
      if (/image|video|audio|player/i.test(prop)) add(el.content, /image/i.test(prop) ? 'image' : /audio/i.test(prop) ? 'audio' : /video|player/i.test(prop) ? 'video' : 'metadata');
    });
    all('[style*="url("]').forEach(el => {
      const css = el.getAttribute('style') || '';
      for (const match of css.matchAll(/url\(["']?([^"')]+)["']?\)/gi)) add(match[1], 'image');
    });
    all('script[type="application/ld+json"]').forEach(script => {
      try {
        const walk = value => {
          if (!value) return;
          if (Array.isArray(value)) return value.forEach(walk);
          if (typeof value !== 'object') return;
          for (const [key, child] of Object.entries(value)) {
            if (/contentUrl|thumbnailUrl|embedUrl|(^|:)image|(^|:)video|(^|:)audio/i.test(key) && typeof child === 'string') add(child, /image/i.test(key) ? 'image' : /embed/i.test(key) ? 'embed' : 'metadata');
            else walk(child);
          }
        };
        walk(JSON.parse(script.textContent || 'null'));
      } catch (_) {}
    });
    performance.getEntriesByType('resource').forEach(entry => {
      if (/\.(mp4|m4v|webm|mov|3gp|m3u8|mpd|ts|m4s|ism|isml|flv|mkv|avi|ogv|mp3|m4a|aac|ogg|oga|opus|wav|flac|weba|jpg|jpeg|png|webp|gif|avif|heic|bmp|svg|vtt|srt|ttml|ass|ssa|pdf|docx?|xlsx?|pptx?|txt)(?:$|[?#])/i.test(entry.name)) {
        add(entry.name, entry.initiatorType || 'resource');
      }
    });
    all('video').forEach(v => { if (v.currentSrc?.startsWith('blob:')) add(v.currentSrc, 'blob video'); });
    return Array.from(found.values());
  })()''';

  final _addressController = TextEditingController();
  final _addressFocus = FocusNode();
  final List<_BrowserTab> _tabs = [];
  List<UrlSuggestion> _suggestions = const [];
  int _activeIndex = 0;
  bool _downloading = false;
  int _tabCounter = 0;
  final _mediaExtractor = MediaExtractor();

  _BrowserTab get _tab => _tabs[_activeIndex];

  Map<String, MediaItem> get _candidates => _tab.candidates;
  InAppWebViewController? get _webController => _tab.controller;
  String? get _error => _tab.error;
  set _error(String? value) => _tab.error = value;

  @override
  void initState() {
    super.initState();
    _tabs.add(
      _BrowserTab(
        id: 'tab-${_tabCounter++}',
        url: widget.initialUrl,
        desktopMode: SettingsService.instance.desktopMode,
      ),
    );
    _addressController.text = _tab.url;
    _addressFocus.addListener(_onAddressFocusChanged);
    BookmarksService.instance.addListener(_onBookmarksChanged);
  }

  void _onAddressFocusChanged() {
    if (!mounted) return;
    if (_addressFocus.hasFocus) {
      _updateSuggestions();
    } else {
      setState(() => _suggestions = const []);
    }
  }

  void _updateSuggestions() {
    final suggestions =
        SuggestionsService.instance.suggest(_addressController.text);
    if (!mounted) return;
    setState(() => _suggestions = suggestions);
  }

  void _addTab([String url = '']) {
    final tab = _BrowserTab(
      id: 'tab-${_tabCounter++}',
      url: url,
      desktopMode: SettingsService.instance.desktopMode,
    );
    setState(() {
      _tabs.add(tab);
      _activeIndex = _tabs.length - 1;
      _addressController.text = tab.url;
    });
  }

  void _selectTab(int index) {
    if (index == _activeIndex || index < 0 || index >= _tabs.length) return;
    setState(() {
      _activeIndex = index;
      _addressController.text = _tab.url;
    });
  }

  void _closeTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    final closing = _tabs[index];
    closing.monitorTimer?.cancel();
    unawaited(_abortBlobCapture(closing, 'Tab closed.'));
    setState(() {
      _tabs.removeAt(index);
      if (_tabs.isEmpty) {
        final tab = _BrowserTab(
          id: 'tab-${_tabCounter++}',
          url: '',
          desktopMode: SettingsService.instance.desktopMode,
        );
        _tabs.add(tab);
      }
      if (_activeIndex >= _tabs.length) _activeIndex = _tabs.length - 1;
      if (_activeIndex > index) _activeIndex--;
      _addressController.text = _tab.url;
    });
  }

  void _onBookmarksChanged() {
    if (mounted) setState(() {});
  }

  Uri? _webUri(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > 8192) return null;
    final withScheme = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(withScheme);
    if (uri == null ||
        !uri.hasAuthority ||
        !{'http', 'https'}.contains(uri.scheme.toLowerCase())) {
      return null;
    }
    return uri;
  }

  Future<void> _navigate() async {
    final input = _addressController.text.trim();
    if (input.isEmpty) {
      setState(() => _error = 'Enter a website address or search terms.');
      return;
    }
    final looksLikeAddress = input.contains('://') ||
        (input.contains('.') && !input.contains(RegExp(r'\s')));
    final uri = looksLikeAddress ? _webUri(input) : null;
    final destination = uri ?? _searchUri(input);
    _addressController.text = destination.toString();
    _tab.allowNextNavigation = true;
    _addressFocus.unfocus();
    setState(() {
      _error = null;
      _suggestions = const [];
    });
    await _webController?.loadUrl(
      urlRequest: URLRequest(url: WebUri(destination.toString())),
    );
  }

  Uri _searchUri(String query) => SettingsService.instance.searchUri(query);

  void _considerUrl(_BrowserTab tab, String? rawUrl,
      {String? initiator,
      String? title,
      String? alt,
      String? thumbnail,
      bool isPlaying = false,
      Map<String, String> requestHeaders = const {},
      int? width,
      int? height,
      String? foundIn}) {
    if (!mounted || rawUrl == null || rawUrl.isEmpty || rawUrl.length > 8192)
      return;
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return;
    if (ChallengeHosts.isChallenge(uri)) return;
    if (AdBlockService.instance.shouldBlock(uri)) return;
    final scheme = uri.scheme.toLowerCase();
    // SuperX skips blob: URLs (VideoUtils.getContentTypeByUrl fast-reject).
    // The real media request behind the blob is detected by content-type.
    if (scheme == 'blob') return;
    if (!{'http', 'https'}.contains(scheme)) return;
    final extension = _mediaExtension(uri);
    const videoExtensions = {
      'mp4',
      'm4v',
      'webm',
      'mov',
      '3gp',
      'm3u8',
      'mpd',
      'ts',
      'm4s',
      'ism',
      'isml',
      'flv',
      'mkv',
      'avi',
      'ogv',
      '3g2',
      'asf',
      'wmv',
      'mpg',
      'mpeg',
      'm2v',
      'm2ts',
      'mts',
      'vob',
      'mxf',
      'f4v',
      'rm',
      'rmvb',
      'dv',
      'ogm',
      'nut',
      'mjpeg',
      '3gpp',
      '3gp2',
      'f4p',
      'wtv',
      'dvr-ms',
      'gxf',
      'lxf',
      'pva',
      'roq',
      'smk',
      'bik',
      'viv',
      'yuv',
      'y4m',
      'h264',
      'h265',
      'hevc',
      'vc1',
      'mpegts'
    };
    const audioExtensions = {
      'mp3',
      'm4a',
      'aac',
      'ogg',
      'oga',
      'opus',
      'wav',
      'flac',
      'weba',
      'amr',
      'ac3',
      'eac3',
      'caf',
      'aiff',
      'aif',
      'wma',
      'mka',
      'm4b',
      'm4p',
      'mid',
      'midi',
      'f4a',
      'f4b',
      'aifc',
      'au',
      'snd',
      'ra',
      'ram',
      'rmi',
      'mpc',
      'ape',
      'tak',
      'tta',
      'wv',
      'spx',
      'voc',
      '8svx',
      'pls',
      'asx'
    };
    const imageExtensions = {
      'jpg',
      'jpeg',
      'png',
      'webp',
      'gif',
      'avif',
      'heic',
      'bmp',
      'svg',
      'tif',
      'tiff',
      'ico',
      'jfif',
      'jxl',
      'psd',
      'dng',
      'apng',
      'jp2',
      'j2k',
      'jpf',
      'jpx',
      'jpm',
      'mj2',
      'pcx',
      'tga',
      'wbmp',
      'xbm',
      'dib',
      'emf',
      'wmf',
      'ras',
      'icns',
      'cur',
      'fpx',
      'bpg',
      'qoi',
      'hdr',
      'exr',
      'pbm',
      'pgm',
      'ppm',
      'pam'
    };
    const subtitleExtensions = {'vtt', 'srt', 'ttml', 'ass', 'ssa'};
    const documentExtensions = {
      'pdf',
      'doc',
      'docx',
      'xls',
      'xlsx',
      'ppt',
      'pptx',
      'txt',
      'rtf',
      'odt',
      'ods',
      'odp',
      'csv',
      'epub',
      'mobi'
    };
    final kind = videoExtensions.contains(extension)
        ? 'video'
        : audioExtensions.contains(extension)
            ? 'audio'
            : imageExtensions.contains(extension)
                ? 'image'
                : subtitleExtensions.contains(extension)
                    ? 'subtitle'
                    : documentExtensions.contains(extension)
                        ? 'document'
                        : (initiator == 'video' ||
                                initiator == 'audio' ||
                                initiator == 'image' ||
                                initiator == 'subtitle' ||
                                initiator == 'document' ||
                                initiator == 'embed' ||
                                initiator == 'metadata')
                            ? initiator!
                            : '';
    if (kind.isEmpty) {
      if (initiator == 'page') {
        final platformType = _platformType(uri);
        if (platformType != null) {
          _addCandidate(
              tab,
              uri.toString(),
              'platform-$platformType',
              '${platformType[0].toUpperCase()}${platformType.substring(1)} page · ${uri.host}',
              '',
              foundIn: 'supported platform link',
              downloadable: false);
        }
      }
      return;
    }
    if (kind == 'image' &&
        ((width != null && height != null && width <= 1 && height <= 1) ||
            RegExp(r'(?:pixel|beacon|tracker|spacer)(?:[./_-]|$)',
                    caseSensitive: false)
                .hasMatch(uri.path))) {
      return;
    }

    final mime = switch (extension) {
      'webm' => 'video/webm',
      'mov' => 'video/quicktime',
      'avi' => 'video/x-msvideo',
      'mkv' => 'video/x-matroska',
      'flv' || 'f4v' => 'video/x-flv',
      '3gp' => 'video/3gpp',
      'svg' => 'image/svg+xml',
      'avif' => 'image/avif',
      'm3u8' => 'application/vnd.apple.mpegurl',
      'mpd' => 'application/dash+xml',
      'mp3' => 'audio/mpeg',
      'm4a' => 'audio/mp4',
      'aac' => 'audio/aac',
      'ogg' || 'oga' || 'opus' => 'audio/ogg',
      'wav' => 'audio/wav',
      'pls' => 'audio/x-scpls',
      'asx' => 'video/x-ms-asf',
      'flac' => 'audio/flac',
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      'vtt' => 'text/vtt',
      'srt' => 'application/x-subrip',
      'pdf' => 'application/pdf',
      'doc' => 'application/msword',
      'docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls' => 'application/vnd.ms-excel',
      'xlsx' =>
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'ppt' => 'application/vnd.ms-powerpoint',
      'pptx' =>
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'txt' => 'text/plain',
      _ => kind == 'audio'
          ? 'audio/*'
          : kind == 'image'
              ? 'image/*'
              : kind == 'document'
                  ? 'application/octet-stream'
                  : 'video/mp4',
    };
    final normalizedUrl =
        uri.hasFragment ? uri.replace(fragment: '').toString() : uri.toString();
    final fallbackTitle = title?.isNotEmpty == true
        ? title!
        : (uri.pathSegments.isEmpty ? kind : uri.pathSegments.last);
    _addCandidate(
      tab,
      normalizedUrl,
      kind,
      kind == 'video'
          ? _streamTitle(tab, uri, fallback: fallbackTitle)
          : fallbackTitle,
      mime,
      alt: alt,
      width: width,
      height: height,
      foundIn: foundIn ?? initiator,
      thumbnail: thumbnail,
      isPlaying: isPlaying,
      requestHeaders: requestHeaders,
    );
  }

  Future<void> _probeMediaRequest(
    _BrowserTab tab,
    String url,
    Map<String, String> headers,
  ) async {
    final settings = SettingsService.instance;
    if (!settings.detectVideos && !settings.detectAudio) return;
    if (url.length > 8192) return;
    final uri = Uri.tryParse(url);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme.toLowerCase())) {
      return;
    }
    if (ChallengeHosts.isChallenge(uri)) return;
    if (AdBlockService.instance.shouldBlock(uri)) return;
    // URLs with a known media extension are already detected by the extension
    // scan. Probing them again downloads/consumes the media link before the
    // user taps Download, which breaks one-time/signed URLs (HTTP 400).
    if (_mediaExtension(uri).isNotEmpty) return;
    if (RegExp(
      r'\.(png|jpe?g|gif|webp|avif|svg|ico|bmp|css|js|woff2?|ttf|otf|eot|html?)$',
      caseSensitive: false,
    ).hasMatch(uri.path)) {
      return;
    }
    if (tab.probingUrls.contains(url) || tab.probingUrls.length >= 24) return;
    tab.probingUrls.add(url);
    try {
      final probe = await _mediaExtractor.probeUrl(url, headers: headers);
      if (!mounted || !probe.found) return;
      if (probe.kind == 'video' && !settings.detectVideos) return;
      if (probe.kind == 'audio' && !settings.detectAudio) return;
      final fallbackTitle =
          uri.pathSegments.isEmpty || uri.pathSegments.last.isEmpty
              ? probe.kind
              : Uri.decodeComponent(uri.pathSegments.last);
      final title = probe.kind == 'video'
          ? _streamTitle(tab, uri, fallback: fallbackTitle)
          : fallbackTitle;
      _addCandidate(
        tab,
        url,
        probe.kind,
        title,
        probe.mimeType ?? (probe.kind == 'video' ? 'video/mp4' : 'audio/*'),
        foundIn: 'content-type probe',
        requestHeaders: headers,
      );
      if (probe.kind == 'video') _removeBlobCandidates(tab);
    } finally {
      tab.probingUrls.remove(url);
    }
  }

  bool _isStreamCandidate(MediaItem item) {
    if (item.type != 'video') return false;
    final mime = item.mimeType?.toLowerCase() ?? '';
    if (mime.contains('mpegurl') || mime.contains('dash+xml')) return true;
    final path = Uri.tryParse(item.url)?.path.toLowerCase() ?? '';
    return path.endsWith('.m3u8') ||
        path.endsWith('.m3u') ||
        path.endsWith('.mpd');
  }

  bool _isGenericStreamTitle(String value) {
    final title = value.trim().toLowerCase();
    if (title.isEmpty) return true;
    if (title == 'master' ||
        title == 'index' ||
        title == 'playlist' ||
        title == 'manifest') {
      return true;
    }
    return RegExp(
      r'^(master|index|playlist|manifest|stream|video|media|output|chunk|seg|segment)[-_]?\d*\.(m3u8|m3u|mpd|ts|m4s|mp4)$',
    ).hasMatch(title);
  }

  String _streamTitle(_BrowserTab tab, Uri uri, {String? fallback}) {
    final candidate = fallback?.trim().isNotEmpty == true
        ? fallback!.trim()
        : (uri.pathSegments.isEmpty || uri.pathSegments.last.isEmpty
            ? 'video'
            : Uri.decodeComponent(uri.pathSegments.last));
    final pageTitle = tab.title.trim();
    if (_isGenericStreamTitle(candidate) &&
        pageTitle.isNotEmpty &&
        pageTitle != 'New tab') {
      return pageTitle;
    }
    return candidate;
  }

  void _retitleStreamCandidates(_BrowserTab tab) {
    final pageTitle = tab.title.trim();
    if (pageTitle.isEmpty || pageTitle == 'New tab') return;
    var changed = false;
    for (final entry in tab.candidates.entries.toList(growable: false)) {
      final item = entry.value;
      if (!_isStreamCandidate(item)) continue;
      if (!_isGenericStreamTitle(item.title ?? '')) continue;
      tab.candidates[entry.key] = item.withTitle(pageTitle);
      changed = true;
    }
    if (changed && tab == _tab) setState(() {});
  }

  void _removeBlobCandidates(_BrowserTab tab) {
    if (!tab.candidates.values.any((item) => item.url.startsWith('blob:'))) {
      return;
    }
    void remove() {
      tab.candidates.removeWhere((key, value) => value.url.startsWith('blob:'));
      tab.candidateKeys.removeWhere((key, value) => value.startsWith('blob:'));
    }

    if (tab == _tab) {
      setState(remove);
    } else {
      remove();
    }
  }

  String _mediaExtension(Uri uri) {
    final path = uri.path.toLowerCase();
    final pathExtension =
        path.contains('.') ? path.substring(path.lastIndexOf('.') + 1) : '';
    const known = {
      'jpg',
      'jpeg',
      'jpe',
      'jfif',
      'png',
      'gif',
      'webp',
      'svg',
      'bmp',
      'ico',
      'avif',
      'heic',
      'heif',
      'tif',
      'tiff',
      'apng',
      'jp2',
      'j2k',
      'jpf',
      'jpx',
      'jpm',
      'mj2',
      'pcx',
      'tga',
      'wbmp',
      'xbm',
      'dib',
      'emf',
      'wmf',
      'ras',
      'icns',
      'cur',
      'fpx',
      'bpg',
      'qoi',
      'hdr',
      'exr',
      'pbm',
      'pgm',
      'ppm',
      'pam',
      'dng',
      'psd',
      'mp4',
      'm4v',
      'webm',
      'mkv',
      'avi',
      'mov',
      'wmv',
      'flv',
      'ogv',
      '3gp',
      '3g2',
      'mpg',
      'mpeg',
      'm3u8',
      'm3u',
      'mpd',
      'ts',
      'm4s',
      'ism',
      'isml',
      'rm',
      'rmvb',
      'mxf',
      'm2ts',
      'mts',
      'vob',
      'f4v',
      'f4p',
      'wtv',
      'dvr-ms',
      'gxf',
      'lxf',
      'pva',
      'roq',
      'smk',
      'bik',
      'viv',
      'yuv',
      'y4m',
      'h264',
      'h265',
      'hevc',
      'vc1',
      'mpegts',
      'mp3',
      'wav',
      'ogg',
      'oga',
      'flac',
      'aac',
      'm4a',
      'wma',
      'aiff',
      'aif',
      'opus',
      'weba',
      'amr',
      'ac3',
      'eac3',
      'caf',
      'mka',
      'm4b',
      'm4p',
      'mid',
      'midi',
      'f4a',
      'f4b',
      'aifc',
      'au',
      'snd',
      'ra',
      'ram',
      'rmi',
      'mpc',
      'ape',
      'tak',
      'tta',
      'wv',
      'spx',
      'voc',
      '8svx',
      'pls',
      'asx',
      'pdf',
      'doc',
      'docx',
      'xls',
      'xlsx',
      'ppt',
      'pptx',
      'txt',
      'rtf',
      'odt',
      'ods',
      'odp',
      'csv',
      'epub',
      'mobi',
      'vtt',
      'srt',
      'ttml',
      'ass',
      'ssa',
    };
    if (known.contains(pathExtension)) return pathExtension;
    for (final key in ['format', 'f', 'type', 'output', 'fm', 'ext']) {
      final value =
          uri.queryParameters[key]?.toLowerCase().replaceFirst('.', '');
      if (value != null && known.contains(value)) return value;
    }
    return '';
  }

  String? _securityHint(Uri uri) {
    final host = uri.host.toLowerCase();
    if (uri.userInfo.isNotEmpty)
      return 'URL contains embedded login information · check source';
    if (uri.scheme == 'http')
      return 'Unencrypted HTTP · check source before downloading';
    if (host.startsWith('localhost') ||
        host.endsWith('.local') ||
        host == '::1' ||
        host.startsWith('fc') ||
        host.startsWith('fd') ||
        host.startsWith('fe80') ||
        host.startsWith('10.') ||
        host.startsWith('192.168.') ||
        host.startsWith('127.') ||
        host.startsWith('169.254.') ||
        RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(host)) {
      return 'Local network address · check source before downloading';
    }
    if (host.startsWith('xn--') ||
        host.split('.').any((label) => label.startsWith('xn--'))) {
      return 'Internationalized domain · check the address';
    }
    if (RegExp(r'[^\x00-\x7F]').hasMatch(host)) {
      return 'Unicode domain · verify the spelling';
    }
    if (uri.queryParametersAll.length > 50) {
      return 'Unusually many URL parameters · check source';
    }
    const suspiciousTlds = {
      'tk',
      'ml',
      'ga',
      'cf',
      'gq',
      'xyz',
      'top',
      'club',
      'work',
      'date',
      'racing',
      'win',
      'bid',
      'stream',
      'download',
      'loan',
      'men',
      'click',
      'link',
      'trade',
      'party',
      'science',
      'review',
      'country',
      'kim',
      'cricket',
      'webcam',
      'faith',
      'accountant',
    };
    if (suspiciousTlds.contains(host.split('.').last)) {
      return 'This domain ending is often abused · check source';
    }
    if (RegExp(r'%(?:[0-9a-f]{2})', caseSensitive: false)
                .allMatches(uri.toString())
                .length *
            3 /
            uri.toString().length >
        .3) {
      return 'Heavily encoded URL · check source';
    }
    var decodedUrl = uri.toString().toLowerCase();
    try {
      decodedUrl = Uri.decodeComponent(decodedUrl);
    } catch (_) {}
    if (decodedUrl.contains('javascript:') ||
        decodedUrl.contains('<script') ||
        RegExp(r'on[a-z]{1,20}\s*=').hasMatch(decodedUrl)) {
      return 'URL contains script-like content · check source';
    }
    if (host == 'bit.ly' ||
        host == 'tinyurl.com' ||
        host == 't.co' ||
        host == 'goo.gl' ||
        host == 'ow.ly' ||
        host == 'is.gd') {
      return 'Shortened URL hides its destination · check source';
    }
    return null;
  }

  String? _platformType(Uri uri) {
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    final path = '${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}';
    final videoHosts = {
      'youtu.be',
      'youtube.com',
      'vimeo.com',
      'player.vimeo.com',
      'dailymotion.com',
      'twitch.tv',
      'clips.twitch.tv',
      'tiktok.com',
      'facebook.com',
      'instagram.com',
      'twitter.com',
      'x.com',
    };
    final audioHosts = {
      'spotify.com',
      'open.spotify.com',
      'soundcloud.com',
      'bandcamp.com',
      'mixcloud.com',
      'audiomack.com',
      'podcasts.apple.com',
      'anchor.fm',
    };
    final documentHosts = {
      'docs.google.com',
      'drive.google.com',
      'dropbox.com',
      'scribd.com',
      'slideshare.net',
      'issuu.com',
      'box.com',
    };
    if (videoHosts.contains(host)) {
      if (host == 'youtube.com' &&
          !(path.startsWith('/watch?') ||
              path.startsWith('/embed/') ||
              path.startsWith('/v/'))) return null;
      if (host == 'vimeo.com' && !RegExp(r'^/\d+|^/video/').hasMatch(path))
        return null;
      if (host == 'dailymotion.com' &&
          !RegExp(r'^/video/|^/embed/').hasMatch(path)) return null;
      if (host == 'twitch.tv' && !RegExp(r'^/videos/|^/clip/').hasMatch(path))
        return null;
      if (host == 'tiktok.com' && !RegExp(r'^/@[\w.-]+/video/').hasMatch(path))
        return null;
      if ((host == 'facebook.com' ||
              host == 'instagram.com' ||
              host == 'twitter.com' ||
              host == 'x.com') &&
          !RegExp(r'/watch/|/videos/|/reel/|/tv/|/status/').hasMatch(path))
        return null;
      return 'video';
    }
    if (audioHosts.contains(host) || host.endsWith('.bandcamp.com')) {
      if (host == 'spotify.com' &&
          !RegExp(r'/track/|/episode/|/album/').hasMatch(path)) return null;
      return 'audio';
    }
    if (host == 'docs.google.com' &&
        !RegExp(r'^/document/|^/spreadsheets/|^/presentation/|^/viewer')
            .hasMatch(path)) return null;
    if (host == 'drive.google.com' &&
        !RegExp(r'^/file/|^/viewer').hasMatch(path)) return null;
    if (host == 'dropbox.com' && !RegExp(r'^/s/').hasMatch(path)) return null;
    if (host == 'scribd.com' && !RegExp(r'^/document/|^/doc/').hasMatch(path))
      return null;
    if (host == 'box.com' && !RegExp(r'^/s/|^/file/').hasMatch(path))
      return null;
    if (host.endsWith('.sharepoint.com') &&
        !RegExp(r'^/_layouts/|^/Documents/').hasMatch(path)) return null;
    if (documentHosts.contains(host) || host.endsWith('.sharepoint.com'))
      return 'document';
    return null;
  }

  bool _isJunkImage(String url, int? width, int? height, String? foundIn) {
    if (foundIn == 'post images') return false;
    if ((width != null && width > 0 && width < 200) ||
        (height != null && height > 0 && height < 200)) {
      return true;
    }
    final uri = Uri.tryParse(url);
    final host = uri?.host.toLowerCase() ?? '';
    if (host == 'static.xx.fbcdn.net' ||
        host == 'static.cdninstagram.com' ||
        host == 'fonts.gstatic.com' ||
        host == 'ssl.gstatic.com' ||
        host == 'www.gstatic.com' ||
        host == 'fonts.googleapis.com' ||
        host == 'abs.twimg.com') {
      return true;
    }
    final path = uri?.path.toLowerCase() ?? url.toLowerCase();
    return RegExp(
      r'/icons?/|/sprites?/|/buttons?/|/arrows?/|/logos?/|/avatars?/|'
      r'rsrc\.php|thumbnail|_thumb\.|-thumb\.|_small\.|-small\.|'
      r'placeholder|spinner|loading|tracking|analytics|doubleclick|'
      r'googlesyndication|advert|banner[^/]*ad|favicon|emoji|'
      r'checkmark|/24px|/16px|/32px|\.svg$|\.ico$',
      caseSensitive: false,
    ).hasMatch(path);
  }

  void _addCandidate(
      _BrowserTab tab, String url, String kind, String title, String mime,
      {String? alt,
      String? thumbnail,
      bool isPlaying = false,
      Map<String, String> requestHeaders = const {},
      int? width,
      int? height,
      int? size,
      int? durationSeconds,
      String? uploader,
      String? foundIn,
      bool downloadable = true,
      bool requiresExtractor = false,
      String? formatId,
      String? audioFormatId,
      String? audioUrl,
      String? audioMimeType,
      String? groupTitle,
      String? qualityLabel,
      String? sourcePage}) {
    if (!SettingsService.instance.isTypeEnabled(kind)) return;
    if (!SettingsService.instance.passesSizeThreshold(size)) return;
    if (kind == 'image' && _isJunkImage(url, width, height, foundIn)) {
      return;
    }
    if (kind == 'video' && url.startsWith('blob:')) {
      final hasExtractorVideo = tab.candidates.values.any((item) =>
          item.type == 'video' && item.formatId != null && item.isDownloadable);
      final host = Uri.tryParse(tab.url.trim())?.host.toLowerCase() ?? '';
      final isYouTube = host.endsWith('youtube.com') || host == 'youtu.be';
      if (hasExtractorVideo || isYouTube) {
        if (tab.blobVideoPlaying != isPlaying) {
          if (tab == _tab) {
            setState(() => tab.blobVideoPlaying = isPlaying);
          } else {
            tab.blobVideoPlaying = isPlaying;
          }
        }
        return;
      }
    }
    final candidate = MediaItem(
      url: url,
      type: kind,
      title: title,
      mimeType: mime,
      thumbnail: thumbnail,
      isPlaying: isPlaying,
      requestHeaders: requestHeaders,
      sourcePage: sourcePage ?? tab.url,
      alt: alt,
      width: width,
      height: height,
      size: size,
      durationSeconds: durationSeconds,
      uploader: uploader,
      foundIn: foundIn,
      isDownloadable: downloadable,
      formatId: formatId,
      audioFormatId: audioFormatId,
      audioUrl: audioUrl,
      audioMimeType: audioMimeType,
      groupTitle: groupTitle,
      qualityLabel: qualityLabel,
      requiresExtractor: requiresExtractor,
    );
    _updateHistoryThumbnail(candidate);
    final key = _normalizedCandidateKey(candidate.url);
    final existingUrl = tab.candidateKeys[key];
    final existing = existingUrl == null ? null : tab.candidates[existingUrl];
    if (existing != null) {
      if (((existing.width == null || existing.width == 0) &&
              ((candidate.width ?? 0) > 0 || (candidate.height ?? 0) > 0)) ||
          (existing.thumbnail == null && candidate.thumbnail != null) ||
          (existing.requestHeaders.isEmpty &&
              candidate.requestHeaders.isNotEmpty) ||
          (existing.formatId == null && candidate.formatId != null) ||
          (existing.audioFormatId == null && candidate.audioFormatId != null) ||
          (candidate.foundIn == 'video element' &&
              existing.isPlaying != candidate.isPlaying)) {
        final updated = MediaItem(
          url: existing.url,
          type: existing.type,
          title: candidate.foundIn == 'yt-dlp on device'
              ? candidate.title
              : existing.title,
          mimeType: candidate.mimeType ?? existing.mimeType,
          thumbnail: existing.thumbnail ?? candidate.thumbnail,
          isPlaying: candidate.foundIn == 'video element'
              ? candidate.isPlaying
              : existing.isPlaying,
          sourcePage: existing.sourcePage,
          size: candidate.size ?? existing.size,
          alt: candidate.alt?.isNotEmpty == true ? candidate.alt : existing.alt,
          width: candidate.width ?? existing.width,
          height: candidate.height ?? existing.height,
          durationSeconds:
              candidate.durationSeconds ?? existing.durationSeconds,
          uploader: candidate.uploader ?? existing.uploader,
          formatId: candidate.formatId ?? existing.formatId,
          audioFormatId: candidate.audioFormatId ?? existing.audioFormatId,
          audioUrl: candidate.audioUrl ?? existing.audioUrl,
          audioMimeType: candidate.audioMimeType ?? existing.audioMimeType,
          groupTitle: candidate.groupTitle ?? existing.groupTitle,
          qualityLabel: candidate.qualityLabel ?? existing.qualityLabel,
          foundIn: candidate.foundIn ?? existing.foundIn,
          requestHeaders: candidate.requestHeaders.isNotEmpty
              ? candidate.requestHeaders
              : existing.requestHeaders,
          isDownloadable: existing.isDownloadable,
          requiresExtractor:
              candidate.requiresExtractor || existing.requiresExtractor,
        );
        if (tab == _tab) {
          setState(() => tab.candidates[existing.url] = updated);
        } else {
          tab.candidates[existing.url] = updated;
        }
      }
      return;
    }
    if (tab.candidates.length >= 500) return;
    if (foundIn != 'yt-dlp on device') {
      DetectionLogService.instance.log(
        'browser',
        'found',
        candidate.url,
        detail: _logDetail(kind, foundIn, size, durationSeconds),
      );
    }
    void add() {
      tab.candidates[candidate.url] = candidate;
      tab.candidateKeys[key] = candidate.url;
    }

    if (tab == _tab) {
      setState(add);
    } else {
      add();
    }
  }

  String _normalizedCandidateKey(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || uri.scheme == 'blob') return rawUrl;
    final sorted = <String, dynamic>{};
    final keys = uri.queryParametersAll.keys.toList()..sort();
    for (final key in keys) {
      final values = uri.queryParametersAll[key]!;
      sorted[key] = values.length == 1 ? values.single : values;
    }
    return uri
        .replace(queryParameters: sorted.isEmpty ? null : sorted, fragment: '')
        .toString();
  }

  Future<void> _scanPage(_BrowserTab tab) async {
    final controller = tab.controller;
    if (controller == null) return;
    try {
      final result =
          await controller.evaluateJavascript(source: _monitorScript);
      if (result is! List) return;
      final before = tab.candidateKeys.length;
      for (final entry in result) {
        if (entry is! Map) continue;
        _considerUrl(
          tab,
          entry['url']?.toString(),
          initiator: entry['kind']?.toString(),
          title: entry['title']?.toString(),
          alt: entry['alt']?.toString(),
          width: entry['width'] is num ? (entry['width'] as num).toInt() : null,
          height:
              entry['height'] is num ? (entry['height'] as num).toInt() : null,
          foundIn: entry['foundIn']?.toString(),
          thumbnail: entry['thumbnail']?.toString(),
          isPlaying: entry['isPlaying'] == true,
        );
      }
      final added = tab.candidateKeys.length - before;
      if (added > 0) {
        DetectionLogService.instance.log(
          'DOM',
          'scan',
          tab.url.trim(),
          detail: '${result.length} element(s) scanned · $added new',
        );
      }
    } catch (_) {
      // The page can navigate or close while a scan is in flight.
    }
  }

  void _onClickedLink(_BrowserTab tab, String message) {
    try {
      final data = jsonDecode(message);
      if (data is! Map) return;
      final url = data['url']?.toString();
      if (url == null) return;
      final uri = Uri.tryParse(url);
      if (uri == null ||
          !{'http', 'https'}.contains(uri.scheme.toLowerCase())) {
        return;
      }
      tab.lastClickedUrl = url;
      tab.lastClickedAt = DateTime.now();
    } catch (_) {}
  }

  String? _recentClickedUrl(_BrowserTab tab) {
    final at = tab.lastClickedAt;
    final url = tab.lastClickedUrl;
    if (at == null || url == null) return null;
    if (DateTime.now().difference(at) > const Duration(seconds: 20)) {
      return null;
    }
    return url;
  }

  void _clearClickedLink(_BrowserTab tab) {
    tab.lastClickedUrl = null;
    tab.lastClickedAt = null;
  }

  void _onScriptMedia(_BrowserTab tab, String message) {
    try {
      final data = jsonDecode(message) as Map<String, dynamic>;
      final mime = (data['type'] ?? '').toString().toLowerCase();
      final kind = mime.startsWith('audio/')
          ? 'audio'
          : mime.startsWith('image/')
              ? 'image'
              : mime.contains('mpegurl') ||
                      mime.contains('dash+xml') ||
                      mime.startsWith('video/')
                  ? 'video'
                  : 'document';
      final uri = Uri.tryParse((data['url'] ?? '').toString());
      if (uri != null && {'http', 'https'}.contains(uri.scheme)) {
        _addCandidate(tab, uri.toString(), kind,
            uri.pathSegments.isEmpty ? kind : uri.pathSegments.last, mime,
            foundIn: 'fetch/XHR');
      }
    } catch (_) {}
  }

  void _startMonitoring(_BrowserTab tab) {
    tab.monitorTimer?.cancel();
    _scanPage(tab);
    tab.monitorTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _scanPage(tab),
    );
  }

  void _resetCandidates([_BrowserTab? target]) {
    final tab = target ?? _tab;
    tab.generation++;
    if (tab.candidates.isEmpty &&
        tab.candidateKeys.isEmpty &&
        !tab.blobVideoPlaying) {
      return;
    }
    void clear() {
      tab.candidates.clear();
      tab.candidateKeys.clear();
      tab.blobVideoPlaying = false;
    }

    if (tab == _tab) {
      setState(clear);
    } else {
      clear();
    }
  }

  bool _sameSite(String first, String second) {
    final firstHost = Uri.tryParse(first)?.host.toLowerCase() ?? '';
    final secondHost = Uri.tryParse(second)?.host.toLowerCase() ?? '';
    if (firstHost.isEmpty || secondHost.isEmpty) return false;
    String bare(String host) => host.replaceFirst(RegExp(r'^www\.'), '');
    String base(String host) {
      final parts = host.split('.');
      return parts.length >= 2
          ? parts.sublist(parts.length - 2).join('.')
          : host;
    }

    final firstBare = bare(firstHost);
    final secondBare = bare(secondHost);
    if (firstBare == secondBare) return true;
    final firstBase = base(firstBare);
    final secondBase = base(secondBare);
    if (firstBase == secondBase) return true;
    const youtubeHosts = {'youtube.com', 'youtu.be', 'youtube-nocookie.com'};
    return youtubeHosts.contains(firstBase) &&
        youtubeHosts.contains(secondBase);
  }

  void _scheduleYtDlpRetry(_BrowserTab tab, String pageUrl) {
    if (!tab.ytDlpRetried.add(pageUrl)) return;
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (!mounted || tab.url.trim() != pageUrl) return;
      _extractPageWithYtDlp(tab, pageUrl);
    });
  }

  Future<void> _extractPageWithYtDlp(
    _BrowserTab tab,
    String pageUrl,
  ) async {
    final uri = Uri.tryParse(pageUrl);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) return;
    if (SettingsService.instance.onlySupportedSites &&
        !SettingsService.instance.isSupportedSite(pageUrl)) {
      DetectionLogService.instance.log(
        'yt-dlp',
        'skipped',
        pageUrl,
        detail: 'Site is not in the supported list.',
      );
      return;
    }
    if (tab.ytDlpInspectedUrl == pageUrl) return;
    tab.ytDlpInspectedUrl = pageUrl;
    final generation = tab.generation;
    DetectionLogService.instance.log('yt-dlp', 'start', pageUrl);
    try {
      final cookieText = await PlatformExtractor().cookieTextFor(
        pageUrl,
        webViewController: tab.controller,
      );
      final results = await PlatformExtractor().extract(
        pageUrl,
        cookieText: cookieText,
      );
      if (!mounted ||
          generation != tab.generation ||
          !_sameSite(tab.url.trim(), pageUrl)) {
        DetectionLogService.instance
            .log('yt-dlp', 'discarded', pageUrl, detail: 'Stale page state.');
        return;
      }
      final summary = results
          .take(3)
          .map((item) => _logDetail(
                item.type,
                item.qualityLabel,
                item.size,
                item.durationSeconds,
              ))
          .join(' | ');
      DetectionLogService.instance.log(
        'yt-dlp',
        results.isEmpty ? 'empty' : 'found',
        pageUrl,
        detail: results.isEmpty
            ? '0 item(s)'
            : results.length > 3
                ? '$summary | +${results.length - 3} more'
                : summary,
      );
      if (results.isEmpty) {
        tab.ytDlpInspectedUrl = null;
        _scheduleYtDlpRetry(tab, pageUrl);
      }
      final hadPlayingVideo = tab.candidates.values
          .any((item) => item.type == 'video' && item.isPlaying);
      var markedPlaying = false;
      for (final item in results) {
        final markPlaying = item.type == 'video' &&
            item.isDownloadable &&
            hadPlayingVideo &&
            !markedPlaying;
        if (markPlaying) markedPlaying = true;
        _addCandidate(
          tab,
          item.url,
          item.type,
          item.title ?? item.type,
          item.mimeType ?? (item.type == 'video' ? 'video/mp4' : 'audio/*'),
          thumbnail: item.thumbnail,
          requestHeaders: item.requestHeaders,
          width: item.width,
          height: item.height,
          size: item.size,
          durationSeconds: item.durationSeconds,
          uploader: item.uploader,
          foundIn: item.foundIn ?? 'yt-dlp on device',
          downloadable: item.isDownloadable,
          requiresExtractor: item.requiresExtractor,
          formatId: item.formatId,
          audioFormatId: item.audioFormatId,
          audioUrl: item.audioUrl,
          audioMimeType: item.audioMimeType,
          groupTitle: item.groupTitle,
          qualityLabel: item.qualityLabel,
          sourcePage: item.sourcePage ?? pageUrl,
          isPlaying: markPlaying,
        );
      }
      if (results.any((item) => item.type == 'video' && item.isDownloadable)) {
        final removedPlayingBlob = tab.candidates.values.any((value) =>
            value.type == 'video' &&
            value.url.startsWith('blob:') &&
            value.isPlaying);
        void prune() {
          if (removedPlayingBlob) tab.blobVideoPlaying = true;
          tab.candidates.removeWhere((key, value) =>
              value.type == 'video' && value.url.startsWith('blob:'));
          tab.candidateKeys
              .removeWhere((key, value) => value.startsWith('blob:'));
        }

        if (tab == _tab) {
          setState(prune);
        } else {
          prune();
        }
      }
    } catch (error) {
      DetectionLogService.instance
          .log('yt-dlp', 'error', pageUrl, detail: '$error');
      tab.ytDlpInspectedUrl = null;
      _scheduleYtDlpRetry(tab, pageUrl);
    }
  }

  List<MediaItem> get _playingVideos {
    final playing = _candidates.values
        .where((item) => item.type == 'video' && item.isPlaying)
        .toList(growable: false);
    if (playing.isNotEmpty) return playing;
    if (!_tab.blobVideoPlaying) return const [];
    final videos = _candidates.values
        .where((item) =>
            item.type == 'video' &&
            item.isDownloadable &&
            item.formatId != null)
        .toList()
      ..sort(_compareCandidateOptions);
    return videos.isEmpty ? const [] : [videos.first];
  }

  Widget _playingVideoStrip() => SizedBox(
        key: const ValueKey('linky-browser-playing-strip'),
        height: 76,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          children: _playingVideos
              .map((item) => Card(
                    margin: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _showCandidates(videosOnly: true),
                      child: SizedBox(
                        width: 250,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            children: [
                              MediaThumbnail(
                                type: 'video',
                                url: item.url,
                                poster: item.thumbnail,
                                size: 48,
                                fallback: const Icon(Icons.movie_outlined),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.title ?? 'Video playing',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600),
                                    ),
                                    Text(
                                      'PLAYING · Tap for download options',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ))
              .toList(),
        ),
      );

  Future<void> _toggleBookmark() async {
    final url = _addressController.text.trim();
    final uri = Uri.tryParse(url);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) return;
    final service = BookmarksService.instance;
    if (service.isBookmarked(url)) {
      await service.removeByUrl(url);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bookmark removed.')),
      );
      return;
    }
    String? title;
    try {
      title = await _webController?.getTitle();
    } catch (_) {}
    await service.add(url: url, title: title);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bookmark added.')),
    );
  }

  Future<void> _recordVisit(
    WebUri? url,
    InAppWebViewController controller,
  ) async {
    final raw = url?.toString();
    if (raw == null || raw.isEmpty) return;
    final uri = Uri.tryParse(raw);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) return;
    String? title;
    try {
      title = await controller.getTitle();
    } catch (_) {}
    await HistoryService.instance.addVisit(
      url: raw,
      title: title,
      thumbnail: uri.host.isEmpty
          ? null
          : Uri(
              scheme: uri.scheme,
              host: uri.host,
              port: uri.hasPort ? uri.port : null,
              path: '/favicon.ico',
            ).toString(),
    );
  }

  void _updateHistoryThumbnail(MediaItem candidate) {
    final page = candidate.sourcePage ?? _addressController.text.trim();
    final uri = Uri.tryParse(page);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) return;
    String? thumbnail;
    if (candidate.thumbnail != null && candidate.thumbnail!.isNotEmpty) {
      thumbnail = candidate.thumbnail;
    } else if (candidate.type == 'image' &&
        (candidate.width ?? 0) >= 400 &&
        candidate.url.startsWith('http')) {
      thumbnail = candidate.url;
    }
    if (thumbnail == null) return;
    unawaited(HistoryService.instance.setThumbnail(page, thumbnail));
    unawaited(BookmarksService.instance.setThumbnail(page, thumbnail));
  }

  Future<void> _updateNavigationState(_BrowserTab tab) async {
    final controller = tab.controller;
    if (controller == null) return;
    final canGoBack = await controller.canGoBack();
    final canGoForward = await controller.canGoForward();
    if (!mounted) return;
    if (tab == _tab) {
      setState(() {
        tab.canGoBack = canGoBack;
        tab.canGoForward = canGoForward;
      });
    } else {
      tab.canGoBack = canGoBack;
      tab.canGoForward = canGoForward;
    }
  }

  Future<Map<String, String>> _headersFor(MediaItem item) async {
    final headers = <String, String>{...item.requestHeaders};
    try {
      final cookies = await CookieManager.instance().getCookies(
        url: WebUri(item.url),
        webViewController: _webController,
      );
      final cookieHeader =
          cookies.map((cookie) => '${cookie.name}=${cookie.value}').join('; ');
      if (cookieHeader.isNotEmpty &&
          !headers.keys.any((key) => key.toLowerCase() == 'cookie')) {
        headers['Cookie'] = cookieHeader;
      }
    } catch (_) {}
    final page = item.sourcePage ?? _addressController.text.trim();
    if (page.isNotEmpty &&
        !headers.keys.any((key) => key.toLowerCase() == 'referer')) {
      headers['Referer'] = page;
    }
    if (!headers.keys.any((key) => key.toLowerCase() == 'user-agent')) {
      headers['User-Agent'] =
          _tab.desktopMode ? _desktopUserAgent : _mobileUserAgent;
    }
    final pageUri = Uri.tryParse(page);
    if (pageUri != null &&
        {'http', 'https'}.contains(pageUri.scheme.toLowerCase()) &&
        !headers.keys.any((key) => key.toLowerCase() == 'origin')) {
      final port = pageUri.hasPort ? ':${pageUri.port}' : '';
      headers['Origin'] = '${pageUri.scheme}://${pageUri.host}$port';
    }
    return headers;
  }

  Future<void> _previewCandidate(MediaItem item) async {
    final uri = Uri.tryParse(item.url);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This item cannot be previewed.')),
      );
      return;
    }
    final headers = await _headersFor(item);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RemotePreviewScreen(
          url: item.url,
          title: item.groupTitle ?? item.title ?? 'Preview',
          headers: headers,
        ),
      ),
    );
  }

  Future<void> _downloadCandidate(MediaItem item) async {
    if (Uri.tryParse(item.url)?.scheme == 'blob') {
      await _downloadReadableBlob(_tab, item);
      return;
    }
    final extension = Uri.parse(item.url).path.toLowerCase();
    final playlist = extension.endsWith('.pls') ||
        extension.endsWith('.asx') ||
        item.mimeType?.toLowerCase().contains('scpls') == true;
    if (playlist && item.formatId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This playlist format is not supported yet.'),
        ),
      );
      return;
    }
    setState(() => _downloading = true);
    try {
      final headers = await _headersFor(item);
      final record = await DownloadService.instance.enqueue(
        item,
        extraHeaders: headers,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Queued ${record.filename} for download.'),
          action: SnackBarAction(
            label: 'Downloads',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const DownloadsScreen(),
              ),
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start the download: $error')),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _downloadReadableBlob(
    _BrowserTab tab,
    MediaItem item,
  ) async {
    final controller = tab.controller;
    if (controller == null) return;
    setState(() => _downloading = true);
    final capture = Completer<File>();
    tab.blobCapture = capture;
    tab.blobBytesReceived = 0;
    try {
      final urlJson = jsonEncode(item.url);
      const maximumBytes = 512 * 1024 * 1024;
      await controller.evaluateJavascript(source: '''(async () => {
        const url = $urlJson;
        try {
          const response = await fetch(url);
          if (!response.ok) throw new Error(`Browser could not read this blob (\${response.status}).`);
          const blob = await response.blob();
          if (!blob.size) throw new Error('The browser returned an empty media blob.');
          if (blob.size > $maximumBytes) throw new Error('This media file is larger than Linky’s 512 MB capture limit.');
          const bridge = window.flutter_inappwebview;
          if (!bridge) throw new Error('The page capture bridge is unavailable.');
          await bridge.callHandler('linkyBlobStart', JSON.stringify({size: blob.size, mime: blob.type || 'video/mp4'}));
          const chunkSize = 64 * 1024;
          for (let offset = 0; offset < blob.size; offset += chunkSize) {
            const buffer = await blob.slice(offset, offset + chunkSize).arrayBuffer();
            const bytes = new Uint8Array(buffer);
            let binary = '';
            for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
            await bridge.callHandler('linkyBlobChunk', btoa(binary));
          }
          await bridge.callHandler('linkyBlobEnd', '');
        } catch (error) {
          try { await window.flutter_inappwebview?.callHandler('linkyBlobError', String(error?.message || error)); } catch (_) {}
        }
      })()''');
      final file = await capture.future.timeout(const Duration(minutes: 10));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Saved ${file.uri.pathSegments.last} to Downloads.')));
    } catch (error) {
      await _abortBlobCapture(_tab, error);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Could not save this browser video. Press play, let it buffer for a few seconds, then try again. ($error)')));
    } finally {
      tab.blobCapture = null;
      tab.blobSink = null;
      tab.blobFile = null;
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<bool> _startBlobCapture(
    _BrowserTab tab,
    String rawMetadata,
  ) async {
    try {
      final metadata = jsonDecode(rawMetadata) as Map<String, dynamic>;
      final size = (metadata['size'] as num?)?.toInt() ?? 0;
      if (size <= 0 || size > 512 * 1024 * 1024) {
        throw const FormatException(
            'The video size is invalid or exceeds 512 MB.');
      }
      final mime = (metadata['mime'] as String?) ?? 'video/mp4';
      if (!mime.toLowerCase().startsWith('video/')) {
        throw const FormatException('The browser blob is not a video file.');
      }
      final directory = await StorageService.instance.downloadDirectory();
      final extension = MediaDownloader.extensionForMime(mime);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      var file = File('${directory.path}/browser-video-$timestamp.$extension');
      var duplicate = 1;
      while (await file.exists()) {
        file = File(
            '${directory.path}/browser-video-$timestamp ($duplicate).$extension');
        duplicate++;
      }
      tab.blobFile = file;
      tab.blobSink = file.openWrite();
      tab.blobBytesReceived = 0;
      return true;
    } catch (error) {
      await _abortBlobCapture(tab, error);
      return false;
    }
  }

  Future<bool> _writeBlobChunk(_BrowserTab tab, String base64Chunk) async {
    try {
      final sink = tab.blobSink;
      if (sink == null)
        throw const FormatException('No video capture is active.');
      final bytes = base64Decode(base64Chunk);
      tab.blobBytesReceived += bytes.length;
      if (tab.blobBytesReceived > 512 * 1024 * 1024) {
        throw const FormatException(
            'The video exceeded Linky’s 512 MB capture limit.');
      }
      sink.add(bytes);
      return true;
    } catch (error) {
      await _abortBlobCapture(tab, error);
      return false;
    }
  }

  Future<bool> _finishBlobCapture(_BrowserTab tab) async {
    final sink = tab.blobSink;
    final file = tab.blobFile;
    if (sink == null || file == null) {
      await _abortBlobCapture(
        tab,
        const FormatException('The video capture ended unexpectedly.'),
      );
      return false;
    }
    await sink.flush();
    await sink.close();
    tab.blobSink = null;
    final capture = tab.blobCapture;
    if (capture != null && !capture.isCompleted) capture.complete(file);
    return true;
  }

  Future<void> _abortBlobCapture(_BrowserTab tab, Object error) async {
    try {
      await tab.blobSink?.close();
    } catch (_) {}
    tab.blobSink = null;
    final file = tab.blobFile;
    if (file != null && await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }
    final capture = tab.blobCapture;
    if (capture != null && !capture.isCompleted) capture.completeError(error);
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _logDetail(String kind, String? foundIn, int? size, int? duration) {
    final parts = <String>[kind];
    if (foundIn != null && foundIn.isNotEmpty) parts.add(foundIn);
    if (size != null && size > 0) parts.add(_formatBytes(size));
    if (duration != null && duration > 0) {
      parts.add(_formatDuration(duration));
    }
    return parts.join(' · ');
  }

  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final remaining =
        duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return duration.inHours > 0
        ? '${duration.inHours}:$minutes:$remaining'
        : '$minutes:$remaining';
  }

  int _compareCandidateOptions(MediaItem a, MediaItem b) {
    if (a.isPlaying != b.isPlaying) return a.isPlaying ? -1 : 1;
    if (a.type == 'video') {
      final height = (b.height ?? 0).compareTo(a.height ?? 0);
      if (height != 0) return height;
    }
    final size = (b.size ?? 0).compareTo(a.size ?? 0);
    if (size != 0) return size;
    return (a.qualityLabel ?? a.title ?? '')
        .compareTo(b.qualityLabel ?? b.title ?? '');
  }

  String _candidateOptionLabel(MediaItem item) {
    final label = item.qualityLabel ??
        (item.height != null ? '${item.height}p' : 'Original');
    final size = item.size;
    if (size == null || size <= 0) return label;
    if (size < 1024 * 1024) return '$label · ${(size / 1024).round()} KB';
    return '$label · ${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _showCandidates({bool videosOnly = false}) {
    const categoryOrder = [
      'video',
      'image',
      'audio',
      'document',
      'subtitle',
      'embed',
      'platform',
      'other'
    ];
    const categoryLabels = {
      'video': 'Videos',
      'image': 'Images',
      'audio': 'Audio',
      'document': 'Documents',
      'subtitle': 'Subtitles',
      'embed': 'Embedded players',
      'platform': 'Supported platform pages',
      'other': 'Other media',
    };
    var filterUnwanted = SettingsService.instance.filterJunkMedia;
    final picked = <String, MediaItem>{};
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final grouped = <String, Map<String, List<MediaItem>>>{};
          final playingVideos = _playingVideos;
          final hasPlayingVideo = playingVideos.isNotEmpty;
          final playingGroups = <String>{
            for (final item in playingVideos)
              if (item.groupTitle != null) item.groupTitle!,
          };
          final playingKeys = <String>{
            for (final item in playingVideos) _normalizedCandidateKey(item.url),
          };
          for (final item in _candidates.values) {
            if (videosOnly && item.type != 'video') continue;
            if (!SettingsService.instance.isTypeEnabled(item.type)) continue;
            if (!SettingsService.instance.passesSizeThreshold(item.size)) {
              continue;
            }
            final lowQualityImage = item.type == 'image' &&
                _isJunkImage(item.url, item.width, item.height, item.foundIn);
            final hideImageForPlaying = hasPlayingVideo &&
                item.type == 'image' &&
                item.foundIn != 'post images';
            final hideVideoForPlaying =
                SettingsService.instance.onlyPlayingVideo &&
                    hasPlayingVideo &&
                    item.type == 'video' &&
                    !item.isPlaying &&
                    !playingKeys.contains(_normalizedCandidateKey(item.url)) &&
                    (item.groupTitle == null ||
                        !playingGroups.contains(item.groupTitle));
            if (hideVideoForPlaying) {
              continue;
            }
            if (filterUnwanted && (lowQualityImage || hideImageForPlaying)) {
              continue;
            }
            final baseType = item.type.replaceFirst('platform-', '');
            final category = item.type.startsWith('platform-')
                ? 'platform'
                : categoryLabels.containsKey(baseType)
                    ? baseType
                    : 'other';
            final groupKey = item.groupTitle != null
                ? '${item.sourcePage}|${item.type}|${item.groupTitle}'
                : '${item.type}|${item.url}';
            grouped
                .putIfAbsent(category, () => {})
                .putIfAbsent(groupKey, () => [])
                .add(item);
          }
          for (final bucket in grouped.values) {
            for (final options in bucket.values) {
              options.sort(_compareCandidateOptions);
            }
            final ordered = bucket.entries.toList()
              ..sort((a, b) {
                final aPlaying = a.value.any((item) => item.isPlaying);
                final bPlaying = b.value.any((item) => item.isPlaying);
                if (aPlaying != bPlaying) return aPlaying ? -1 : 1;
                return _compareCandidateOptions(a.value.first, b.value.first);
              });
            bucket
              ..clear()
              ..addEntries(ordered);
          }
          return SafeArea(
            child: SizedBox(
              height: 500,
              child: ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          videosOnly ? 'Video options' : 'Media found',
                          style: AppText.heading(20,
                              color: context.palette.foreground),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_candidates.length} item${_candidates.length == 1 ? '' : 's'} on this page',
                          style: AppText.body(12,
                              color: context.palette.mutedForeground),
                        ),
                      ],
                    ),
                  ),
                  SwitchListTile(
                    title:
                        const Text('Filter icons, thumbnails, and UI images'),
                    value: filterUnwanted,
                    onChanged: (value) {
                      setSheetState(() => filterUnwanted = value);
                      SettingsService.instance.setFilterJunkMedia(value);
                    },
                  ),
                  ...categoryOrder
                      .where(grouped.containsKey)
                      .expand((category) => [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                              child: Text(
                                '${categoryLabels[category]} (${grouped[category]!.length})',
                                style: Theme.of(sheetContext)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            ...grouped[category]!.entries.expand((entry) {
                              final options = entry.value;
                              final pickKey = '$category|${entry.key}';
                              final item = picked[pickKey] ?? options.first;
                              final uri = Uri.parse(item.url);
                              final hls =
                                  uri.path.toLowerCase().endsWith('.m3u8') ||
                                      uri.path.toLowerCase().endsWith('.m3u') ||
                                      item.mimeType
                                              ?.toLowerCase()
                                              .contains('mpegurl') ==
                                          true;
                              final dash =
                                  uri.path.toLowerCase().endsWith('.mpd') ||
                                      item.mimeType
                                              ?.toLowerCase()
                                              .contains('dash+xml') ==
                                          true;
                              final dashSegmented =
                                  uri.path.toLowerCase().endsWith('.pls') ||
                                      uri.path.toLowerCase().endsWith('.asx') ||
                                      item.mimeType
                                              ?.toLowerCase()
                                              .contains('scpls') ==
                                          true;
                              final unavailable =
                                  (dashSegmented && item.formatId == null) ||
                                      item.type == 'embed' ||
                                      item.type == 'subtitle' ||
                                      item.type.startsWith('platform-') ||
                                      !item.isDownloadable;
                              final canPreview = (item.type == 'video' ||
                                      item.type == 'audio') &&
                                  uri.scheme != 'blob' &&
                                  !dash &&
                                  !dashSegmented &&
                                  !unavailable;
                              final securityHint = _securityHint(uri);
                              final details = <String>[
                                if (options.length == 1)
                                  _candidateOptionLabel(item),
                                if (item.isPlaying) 'PLAYING NOW',
                                if (item.durationSeconds != null)
                                  _formatDuration(item.durationSeconds!),
                                if (item.uploader?.isNotEmpty == true)
                                  item.uploader!,
                                if (item.width != null &&
                                    item.height != null &&
                                    item.width! > 0 &&
                                    item.height! > 0)
                                  '${item.width} × ${item.height}',
                                if (item.alt?.isNotEmpty == true) item.alt!,
                                if (item.foundIn?.isNotEmpty == true)
                                  'Found in ${item.foundIn}',
                                if (securityHint != null) securityHint,
                              ];
                              return [
                                ListTile(
                                  leading: item.type == 'image' ||
                                          item.type == 'video'
                                      ? MediaThumbnail(
                                          type: item.type,
                                          url: item.url,
                                          poster: item.thumbnail,
                                          size: 48,
                                          fallback: Icon(item.type == 'image'
                                              ? Icons.image_outlined
                                              : Icons.movie_outlined),
                                        )
                                      : Icon(item.type == 'audio'
                                          ? Icons.audiotrack
                                          : item.type == 'document'
                                              ? Icons.description_outlined
                                              : Icons.movie_outlined),
                                  title: Text(
                                      item.groupTitle ??
                                          item.title ??
                                          categoryLabels[category]!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  isThreeLine:
                                      details.isNotEmpty || options.length > 1,
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(hls
                                          ? 'HLS stream · segments saved by the on-device downloader'
                                          : dash
                                              ? 'DASH stream · segments saved by the on-device downloader'
                                              : dashSegmented
                                                  ? 'Playlist stream · not supported yet'
                                                  : uri.scheme == 'blob'
                                                      ? 'Browser blob · page-side capture available if readable'
                                                      : item.type == 'embed'
                                                          ? 'Embedded player · open it to detect its media'
                                                          : item.type.startsWith(
                                                                      'platform-') ||
                                                                  !item
                                                                      .isDownloadable
                                                              ? 'Platform page detected · direct media URL not exposed'
                                                              : item.type ==
                                                                      'subtitle'
                                                                  ? 'Subtitle track'
                                                                  : uri.host),
                                      if (options.length > 1)
                                        DropdownButtonHideUnderline(
                                          child: DropdownButton<MediaItem>(
                                            value: item,
                                            isDense: true,
                                            isExpanded: true,
                                            items: options
                                                .map((option) =>
                                                    DropdownMenuItem<MediaItem>(
                                                      value: option,
                                                      child: Text(
                                                        _candidateOptionLabel(
                                                            option),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ))
                                                .toList(growable: false),
                                            onChanged: (option) {
                                              if (option == null) return;
                                              setSheetState(() =>
                                                  picked[pickKey] = option);
                                            },
                                          ),
                                        ),
                                      ...details.map((line) => Text(line,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              color: securityHint != null &&
                                                      line == securityHint
                                                  ? Theme.of(sheetContext)
                                                      .colorScheme
                                                      .error
                                                  : null))),
                                    ],
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (canPreview)
                                        IconButton(
                                          tooltip: 'Preview stream',
                                          onPressed: () =>
                                              _previewCandidate(item),
                                          icon: const Icon(
                                            Icons.play_circle_outline,
                                          ),
                                        ),
                                      IconButton(
                                        tooltip: unavailable
                                            ? 'Not directly downloadable'
                                            : 'Download ${item.type}',
                                        onPressed: unavailable || _downloading
                                            ? null
                                            : () => _downloadCandidate(item),
                                        icon: _downloading
                                            ? const SizedBox(
                                                width: 20,
                                                height: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2))
                                            : const Icon(Icons.download),
                                      ),
                                    ],
                                  ),
                                ),
                              ];
                            }),
                          ]),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _tabLabel(_BrowserTab tab) {
    if (tab.title.isNotEmpty && tab.title != 'New tab') return tab.title;
    if (tab.url.isEmpty) return 'New tab';
    final host = Uri.tryParse(tab.url)?.host ?? '';
    return host.isNotEmpty ? host : tab.url;
  }

  void _showTabsSheet() {
    final palette = context.palette;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                          child: Text('Tabs', style: AppText.heading(18))),
                      TextButton.icon(
                        onPressed: () => setSheetState(() => _addTab()),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('New tab'),
                      ),
                    ],
                  ),
                ),
                for (var i = 0; i < _tabs.length; i++)
                  ListTile(
                    selected: i == _activeIndex,
                    selectedTileColor: palette.accent,
                    leading: Icon(
                      Icons.public_rounded,
                      color: i == _activeIndex
                          ? AppColors.primary
                          : palette.mutedForeground,
                    ),
                    title: Text(
                      _tabLabel(_tabs[i]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(
                        14,
                        weight: i == _activeIndex
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    trailing: IconButton(
                      tooltip: 'Close tab',
                      onPressed: () => setSheetState(() {
                        _closeTab(i);
                      }),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                    onTap: () {
                      setSheetState(() => _selectTab(i));
                      Navigator.of(sheetContext).pop();
                    },
                  ),
                Divider(height: 20, color: palette.border),
                ListTile(
                  leading: Icon(
                    _tab.desktopMode
                        ? Icons.phone_iphone_rounded
                        : Icons.desktop_windows_rounded,
                  ),
                  title: Text(
                    _tab.desktopMode
                        ? 'Switch to mobile site'
                        : 'Switch to desktop site',
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _toggleDesktopMode();
                  },
                ),
                ListTile(
                  leading: Icon(
                    BookmarksService.instance
                            .isBookmarked(_addressController.text.trim())
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                  ),
                  title: Text(
                    BookmarksService.instance
                            .isBookmarked(_addressController.text.trim())
                        ? 'Remove bookmark'
                        : 'Bookmark this page',
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _toggleBookmark();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Browser settings'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _showBrowserMenu();
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    BookmarksService.instance.removeListener(_onBookmarksChanged);
    for (final tab in _tabs) {
      tab.monitorTimer?.cancel();
      unawaited(_abortBlobCapture(tab, 'Browser closed.'));
    }
    _addressFocus.dispose();
    _addressController.dispose();
    super.dispose();
  }

  InAppWebViewSettings _webSettings(_BrowserTab tab) => InAppWebViewSettings(
        javaScriptEnabled: true,
        mediaPlaybackRequiresUserGesture: true,
        allowsInlineMediaPlayback: true,
        supportMultipleWindows: true,
        useOnLoadResource: true,
        useShouldInterceptRequest: true,
        userAgent: tab.desktopMode ? _desktopUserAgent : _mobileUserAgent,
        useWideViewPort: tab.desktopMode,
        loadWithOverviewMode: tab.desktopMode,
        supportZoom: true,
        isTextInteractionEnabled: true,
      );

  Future<void> _toggleDesktopMode() async {
    final tab = _tab;
    final value = !tab.desktopMode;
    tab.desktopMode = value;
    await SettingsService.instance.setDesktopMode(value);
    try {
      await tab.controller?.setSettings(settings: _webSettings(tab));
    } catch (_) {}
    if (!mounted) return;
    setState(() {});
    try {
      await tab.controller?.reload();
    } catch (_) {}
  }

  Future<(bool, bool)> _confirmRedirect(
    String currentUrl,
    String targetUrl,
  ) async {
    var dontAsk = false;
    final currentHost = Uri.tryParse(currentUrl)?.host ?? currentUrl;
    final targetHost = Uri.tryParse(targetUrl)?.host ?? targetUrl;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('Leave $currentHost?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('This navigation goes to $targetHost.'),
              CheckboxListTile(
                value: dontAsk,
                onChanged: (value) =>
                    setDialogState(() => dontAsk = value ?? false),
                title: const Text("Don't ask again"),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Stay'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
    return (result == true, dontAsk);
  }

  Future<NavigationActionPolicy> _decideNavigation(
    _BrowserTab tab,
    NavigationAction action,
  ) async {
    final uri = action.request.url;
    if (uri == null) return NavigationActionPolicy.ALLOW;
    final target = uri.toString();
    final scheme = uri.scheme.toLowerCase();
    if (!{'http', 'https'}.contains(scheme)) {
      // App links (mailto:, tel:, intent:, etc.) are allowed only when the
      // user actually initiated them; automatic app-store redirects stay
      // blocked.
      return action.hasGesture == true
          ? NavigationActionPolicy.ALLOW
          : NavigationActionPolicy.CANCEL;
    }
    if (ChallengeHosts.isChallenge(uri)) {
      return NavigationActionPolicy.ALLOW;
    }
    if (tab.allowNextNavigation) {
      tab.allowNextNavigation = false;
      return NavigationActionPolicy.ALLOW;
    }
    if (action.isForMainFrame != true) return NavigationActionPolicy.ALLOW;

    // Only follow the destination of the link the user actually clicked.
    // A navigation to any other site while a link click is pending is a
    // redirect/pop-under attempt and is blocked.
    final clicked = _recentClickedUrl(tab);
    if (clicked != null) {
      final matches = target == clicked || _sameSite(clicked, target);
      _clearClickedLink(tab);
      if (matches) return NavigationActionPolicy.ALLOW;
      DetectionLogService.instance.log(
        'browser',
        'blocked',
        target,
        detail: 'Blocked a redirect that does not match the clicked link.',
      );
      return NavigationActionPolicy.CANCEL;
    }

    // Server-side redirect chains are part of a legitimate navigation.
    if (action.isRedirect == true) return NavigationActionPolicy.ALLOW;
    if (!SettingsService.instance.redirectPromptEnabled) {
      return NavigationActionPolicy.ALLOW;
    }
    final current = tab.url;
    if (current.isEmpty || _sameSite(current, target)) {
      return NavigationActionPolicy.ALLOW;
    }
    if (tab.redirectApproved.contains(target)) {
      return NavigationActionPolicy.ALLOW;
    }
    final decision = await _confirmRedirect(current, target);
    if (decision.$2) {
      await SettingsService.instance.setRedirectPromptEnabled(false);
    }
    if (decision.$1) {
      tab.redirectApproved.add(target);
      return NavigationActionPolicy.ALLOW;
    }
    return NavigationActionPolicy.CANCEL;
  }

  Widget _buildWebView(_BrowserTab tab) => InAppWebView(
        key: ValueKey('linky-browser-webview-${tab.id}'),
        initialUrlRequest: URLRequest(url: WebUri(tab.initialUrl)),
        initialSettings: _webSettings(tab),
        initialUserScripts: UnmodifiableListView([
          UserScript(
            source: _webrtcBlockScript,
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          ),
          if (SettingsService.instance.blockPopups)
            UserScript(
              source: _popupGuardScript,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              forMainFrameOnly: false,
            ),
        ]),
        onCreateWindow: (controller, action) async {
          final url = action.request.url?.toString();
          if (url == null || !url.startsWith('http')) return false;
          if (!SettingsService.instance.blockPopups) {
            _clearClickedLink(tab);
            _addTab(url);
            return false;
          }
          // Open a new tab only when it is the link the user clicked.
          final clicked = _recentClickedUrl(tab);
          _clearClickedLink(tab);
          if (clicked == null || (url != clicked && !_sameSite(clicked, url))) {
            DetectionLogService.instance.log(
              'browser',
              'blocked',
              url,
              detail: 'Blocked a popup that is not the clicked link.',
            );
            return false;
          }
          _addTab(url);
          return false;
        },
        onWebViewCreated: (controller) {
          tab.controller = controller;
          controller.addJavaScriptHandler(
            handlerName: 'linkyFoundMedia',
            callback: (args) {
              if (args.isNotEmpty) _onScriptMedia(tab, args.first.toString());
            },
          );
          controller.addJavaScriptHandler(
            handlerName: 'linkyClickedLink',
            callback: (args) {
              if (args.isNotEmpty) _onClickedLink(tab, args.first.toString());
            },
          );
          controller.addJavaScriptHandler(
            handlerName: 'linkyOpenTab',
            callback: (args) {
              if (args.isEmpty) return;
              final url = args.first.toString();
              final uri = Uri.tryParse(url);
              if (uri == null ||
                  !{'http', 'https'}.contains(uri.scheme.toLowerCase())) {
                return;
              }
              final clicked = _recentClickedUrl(tab);
              if (clicked == null ||
                  (url != clicked && !_sameSite(clicked, url))) {
                return;
              }
              _clearClickedLink(tab);
              _addTab(url);
            },
          );
          controller.addJavaScriptHandler(
            handlerName: 'linkyBlobStart',
            callback: (args) => _startBlobCapture(tab, args.first as String),
          );
          controller.addJavaScriptHandler(
            handlerName: 'linkyBlobChunk',
            callback: (args) => _writeBlobChunk(tab, args.first as String),
          );
          controller.addJavaScriptHandler(
            handlerName: 'linkyBlobEnd',
            callback: (_) => _finishBlobCapture(tab),
          );
          controller.addJavaScriptHandler(
            handlerName: 'linkyBlobError',
            callback: (args) => _abortBlobCapture(
              tab,
              args.isEmpty ? 'Video capture failed.' : args.first.toString(),
            ),
          );
        },
        onLoadStart: (controller, url) {
          if (!mounted) return;
          tab.ytDlpInspectedUrl = null;
          tab.ytDlpRetried.clear();
          tab.generation++;
          tab.candidates.clear();
          tab.candidateKeys.clear();
          _clearClickedLink(tab);
          tab.blobVideoPlaying = false;
          tab.loading = true;
          tab.progress = 0;
          if (url != null) tab.url = url.toString();
          if (tab == _tab) {
            _addressController.text = tab.url;
            setState(() {});
          }
        },
        onProgressChanged: (controller, progress) {
          if (!mounted) return;
          tab.progress = progress / 100;
          tab.loading = progress < 100;
          if (tab == _tab) setState(() {});
        },
        onLoadStop: (controller, url) {
          if (!mounted) return;
          tab.loading = false;
          tab.progress = 1;
          if (url != null) tab.url = url.toString();
          if (tab == _tab) {
            _addressController.text = tab.url;
            setState(() {});
          }
          _recordVisit(url, controller);
          controller.getTitle().then((title) {
            if (!mounted || title == null || title.isEmpty) return;
            if (tab.title != title) {
              tab.title = title;
              setState(() {});
              _retitleStreamCandidates(tab);
            }
          });
          _startMonitoring(tab);
          _extractPageWithYtDlp(tab, url?.toString() ?? tab.url);
          _updateNavigationState(tab);
        },
        onUpdateVisitedHistory: (controller, url, isReload) {
          if (url == null) return;
          final next = url.toString();
          final previous = tab.url;
          tab.url = next;
          if (tab == _tab) _addressController.text = next;
          if (next != previous) {
            tab.ytDlpInspectedUrl = null;
            tab.ytDlpRetried.clear();
            _resetCandidates(tab);
            _recordVisit(url, controller);
          }
          _extractPageWithYtDlp(tab, next);
          _updateNavigationState(tab);
          if (tab == _tab) setState(() {});
        },
        onLoadResource: (controller, resource) {
          _considerUrl(
            tab,
            resource.url?.toString(),
            initiator: resource.initiatorType,
          );
        },
        shouldInterceptRequest: (controller, request) async {
          if (request.isForMainFrame != true &&
              AdBlockService.instance.shouldBlock(request.url)) {
            return WebResourceResponse(
              contentType: 'text/plain',
              data: Uint8List(0),
            );
          }
          _considerUrl(
            tab,
            request.url.toString(),
            initiator: 'resource',
            requestHeaders: request.headers ?? const {},
          );
          unawaited(_probeMediaRequest(
            tab,
            request.url.toString(),
            request.headers ?? const {},
          ));
          return null;
        },
        shouldOverrideUrlLoading: (controller, action) =>
            _decideNavigation(tab, action),
        onReceivedError: (controller, request, error) {
          if (request.isForMainFrame == true && mounted) {
            tab.error = 'Could not load this webpage.';
            if (tab == _tab) setState(() {});
          }
        },
      );

  void _showBrowserMenu() {
    final settings = SettingsService.instance;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          void open(Widget screen) {
            Navigator.of(sheetContext).pop();
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => screen),
            );
          }

          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sheetContext).size.height * 0.85,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Text(
                      'Browser settings',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.history),
                    title: const Text('History'),
                    onTap: () => open(const HistoryScreen()),
                  ),
                  ListTile(
                    leading: const Icon(Icons.bookmark_border),
                    title: const Text('Bookmarks'),
                    onTap: () => open(const BookmarksScreen()),
                  ),
                  ListTile(
                    leading: const Icon(Icons.download_outlined),
                    title: const Text('Downloads'),
                    onTap: () => open(const DownloadsScreen()),
                  ),
                  ListTile(
                    leading: const Icon(Icons.tune),
                    title: const Text('All settings'),
                    subtitle:
                        const Text('Detection, storage, proxy, DNS and more'),
                    onTap: () => open(const SettingsScreen()),
                  ),
                  ListTile(
                    leading: const Icon(Icons.cleaning_services_outlined),
                    title: const Text('Clear browsing data'),
                    subtitle:
                        const Text('Cookies, cache, site data and history'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _showClearBrowsingData();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.search),
                    title: Text('Search engine: ${settings.searchEngineName}'),
                    subtitle:
                        const Text('Change the start page and search engine'),
                    onTap: () => open(const SettingsScreen()),
                  ),
                  const Divider(),
                  SwitchListTile(
                    secondary: const Icon(Icons.shield_outlined),
                    value: settings.adBlockEnabled,
                    title: const Text('Ad blocker'),
                    subtitle: const Text(
                        'Block ad and pop-under hosts while browsing.'),
                    onChanged: (value) async {
                      await settings.setAdBlockEnabled(value);
                      setSheetState(() {});
                    },
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.block),
                    value: settings.blockPopups,
                    title: const Text('Block pop-ups and redirect ads'),
                    subtitle:
                        const Text('Applies to newly opened pages and tabs.'),
                    onChanged: (value) async {
                      await settings.setBlockPopups(value);
                      setSheetState(() {});
                    },
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.open_in_new),
                    value: settings.redirectPromptEnabled,
                    title: const Text('Ask before cross-site redirects'),
                    onChanged: (value) async {
                      await settings.setRedirectPromptEnabled(value);
                      setSheetState(() {});
                    },
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.play_circle_outline),
                    value: settings.onlyPlayingVideo,
                    title: const Text('Only show the playing video'),
                    onChanged: (value) async {
                      await settings.setOnlyPlayingVideo(value);
                      setSheetState(() {});
                    },
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.filter_alt_outlined),
                    value: settings.filterJunkMedia,
                    title: const Text('Filter junk media'),
                    onChanged: (value) async {
                      await settings.setFilterJunkMedia(value);
                      setSheetState(() {});
                    },
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.desktop_windows_outlined),
                    value: _tab.desktopMode,
                    title: const Text('Desktop site'),
                    subtitle:
                        const Text('Use a desktop user agent and viewport.'),
                    onChanged: (_) async {
                      await _toggleDesktopMode();
                      setSheetState(() {});
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showClearBrowsingData() async {
    var cookies = true;
    var cache = true;
    var siteData = true;
    var history = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Clear browsing data'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(
                value: cookies,
                onChanged: (value) =>
                    setDialogState(() => cookies = value ?? false),
                title: const Text('Cookies'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
              CheckboxListTile(
                value: cache,
                onChanged: (value) =>
                    setDialogState(() => cache = value ?? false),
                title: const Text('Cache'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
              CheckboxListTile(
                value: siteData,
                onChanged: (value) =>
                    setDialogState(() => siteData = value ?? false),
                title: const Text('Site data (local storage)'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
              CheckboxListTile(
                value: history,
                onChanged: (value) =>
                    setDialogState(() => history = value ?? false),
                title: const Text('History'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Clear'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      if (cookies) await CookieManager.instance().deleteAllCookies();
      if (cache) {
        for (final tab in _tabs) {
          try {
            await tab.controller?.clearCache();
          } catch (_) {}
        }
      }
      if (siteData) await WebStorageManager.instance().deleteAllData();
      if (history) await HistoryService.instance.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Browsing data cleared.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not clear all browsing data: $error')),
      );
    }
  }

  Future<void> _handleBack() async {
    final tab = _tab;
    if (tab.canGoBack) {
      try {
        await _webController?.goBack();
      } catch (_) {}
      await _updateNavigationState(tab);
      return;
    }
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final canGoBack = _tab.canGoBack;
    return PopScope(
      canPop: !canGoBack,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 60,
          leadingWidth: 100,
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Back',
                onPressed: _handleBack,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              IconButton(
                tooltip: 'Forward',
                onPressed: _tab.canGoForward
                    ? () async {
                        await _webController?.goForward();
                        await _updateNavigationState(_tab);
                      }
                    : null,
                icon: const Icon(Icons.arrow_forward_rounded),
              ),
            ],
          ),
          titleSpacing: 0,
          title: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: context.palette.input,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_rounded, size: 15, color: AppColors.teal),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _addressController,
                    focusNode: _addressFocus,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.go,
                    onChanged: (_) => _updateSuggestions(),
                    onSubmitted: (_) => _navigate(),
                    style: AppText.body(13),
                    decoration: const InputDecoration(
                      isDense: true,
                      filled: false,
                      hintText: 'Search or enter address',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => _webController?.reload(),
                  child: Icon(
                    Icons.refresh_rounded,
                    size: 17,
                    color: context.palette.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: RoundIconButton(
                icon: Icons.tab_rounded,
                tooltip: 'Tabs and options',
                badge: _tabs.length > 1 ? '${_tabs.length}' : null,
                onPressed: _showTabsSheet,
              ),
            ),
          ],
          bottom: _tab.loading
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(3),
                  child: LinearProgressIndicator(
                      value: _tab.progress == 0 ? null : _tab.progress),
                )
              : null,
        ),
        body: Column(
          children: [
            const SizedBox(height: 6),
            if (_addressFocus.hasFocus && _suggestions.isNotEmpty)
              Material(
                elevation: 3,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final suggestion in _suggestions)
                        ListTile(
                          dense: true,
                          leading: Icon(
                            suggestion.source == 'History'
                                ? Icons.history
                                : suggestion.source == 'Bookmark'
                                    ? Icons.bookmark_outline
                                    : Icons.public,
                          ),
                          title: Text(
                            suggestion.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${suggestion.source} · ${suggestion.url}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () {
                            _addressController.text = suggestion.url;
                            _navigate();
                          },
                        ),
                    ],
                  ),
                ),
              ),
            if (_error != null)
              MaterialBanner(
                key: const ValueKey('linky-browser-error-banner'),
                content: Text(_error!),
                actions: [
                  TextButton(
                      onPressed: () => setState(() => _error = null),
                      child: const Text('Dismiss'))
                ],
              ),
            _playingVideos.isEmpty
                ? const SizedBox.shrink(
                    key: ValueKey('linky-browser-playing-strip'),
                  )
                : _playingVideoStrip(),
            Expanded(
              key: const ValueKey('linky-browser-webview-slot'),
              child: IndexedStack(
                index: _activeIndex,
                children: [
                  for (final tab in _tabs) _buildWebView(tab),
                ],
              ),
            ),
            if (_candidates.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Material(
                  color: context.palette.card,
                  shape: StadiumBorder(
                    side: BorderSide(color: context.palette.border),
                  ),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: _showCandidates,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: context.palette.accent,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.download_rounded,
                              size: 17,
                              color: context.palette.accentForeground,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${_candidates.length} media item${_candidates.length == 1 ? '' : 's'} found',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.body(13,
                                  weight: FontWeight.w700),
                            ),
                          ),
                          Icon(Icons.keyboard_arrow_up_rounded,
                              size: 20,
                              color: context.palette.mutedForeground),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BrowserTab {
  _BrowserTab({
    required this.id,
    required String url,
    this.desktopMode = false,
  })  : initialUrl =
            url.trim().isEmpty ? SettingsService.instance.startPageUrl : url,
        url = url.trim().isEmpty ? SettingsService.instance.startPageUrl : url;

  final String id;
  final String initialUrl;
  String url;
  String title = 'New tab';
  bool desktopMode;
  bool allowNextNavigation = false;
  final Set<String> redirectApproved = {};
  InAppWebViewController? controller;
  final Map<String, MediaItem> candidates = {};
  final Map<String, String> candidateKeys = {};
  Timer? monitorTimer;
  double progress = 0;
  bool loading = false;
  bool canGoBack = false;
  bool canGoForward = false;
  String? error;
  String? ytDlpInspectedUrl;
  final Set<String> ytDlpRetried = {};
  String? lastClickedUrl;
  DateTime? lastClickedAt;
  bool blobVideoPlaying = false;
  int generation = 0;
  Completer<File>? blobCapture;
  IOSink? blobSink;
  File? blobFile;
  int blobBytesReceived = 0;
  final Set<String> probingUrls = {};
}
