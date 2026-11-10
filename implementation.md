# Linky Implementation Plan (from feature.md)

Working checklist. Mark items `[x]` when implemented, built, installed and
verified on device. Order = priority by usefulness/effort. Each item lists the
gap it closes relative to SuperX.

Legend: `[ ]` todo, `[~]` in progress, `[x]` done, `[-]` dropped/deferred.

---

## Phase 0 - Foundation

### 0.1 Settings store + Settings screen
- [x] `lib/services/settings_service.dart`: JSON-backed persisted settings
      (theme mode, only-playing-video, junk-media filter) with ChangeNotifier.
- [x] `lib/features/settings/settings_screen.dart`: appearance, browser filters,
      clear cookies action.
- [x] Wire theme mode into `MaterialApp` (light/dark theme).
- [x] Entry point in Home app bar.
- [x] Persist sheet toggles; gate non-playing video filter with the setting.
- Verified: `flutter analyze lib` clean (no new issues), debug APK built +
  installed on c1196d1d, app launches.

---

## Phase 1 - Detection & download core

### 1.1 Detection toggles + thresholds (browser + home)
- [x] Setting: detect images / videos / audio / documents independently.
- [x] Setting: ad/media size threshold (bytes) to ignore small media.
- [x] Apply toggles in browser candidate collection and home platform extraction.
- [x] "Only supported sites" URL list (local default + optional remote JSON).

### 1.2 Detection logs
- [x] In-app ring buffer of detection events (engine, URL, result, error).
      `lib/services/detection_log_service.dart` (300 entries, ChangeNotifier).
- [x] Settings screen entry + `lib/features/detection_logs/detection_logs_screen.dart`
      (view, clear).
- [x] Wired yt-dlp `start` / `discarded` / `found|empty` / `error` events from
      the in-app browser.
- [x] Add network/DOM scan events and size/duration details.
- [x] Helpful when tuning per-site detection.

### 1.3 Audio-only quick action
- [x] "Download audio only" action on video group cards (home), uses the paired
      audio track; direct audio URLs download as files, extractor tracks go
      through yt-dlp.
- [x] Audio tracks already emitted by extractor and downloadable from the
      browser sheet (Audio category) and Home audio group - verified in code.
- [x] Optional: audio format choice (m4a/webm).

### 1.4 Chunked multi-thread downloads
- [x] HTTP Range detection (HEAD/GET); split into N chunks with parallel workers.
- [x] Fallback to single stream when server lacks Range or Range is broken.
- [x] Configurable thread count + max simultaneous downloads in settings.
- [x] Resume across process death (chunk files + metadata), stop-and-save.

### 1.5 Download safety/UX
- [x] Memory guard before starting queued tasks (skip/postpone when low memory).
- [x] Disk-space pre-check and clear error messages.
- [x] Export/import queued task list (optional).

---

## Phase 2 - Streaming engine

### 2.1 HLS (.m3u8) downloader
- [x] Master/media playlist parsing (variants, separate audio, subtitles, live).
- [x] Parallel segment download with retries + segment-level resume.
- [x] AES-128 key download + decryption path.
- [x] fMP4 init segment handling.
- [x] Output: concat via MediaMuxer where possible; FFmpegKit decision required.
      Decision: no FFmpegKit; raw segment concat, MediaMuxer only to merge a
      separate audio rendition.

### 2.2 DASH (.mpd) downloader
- [x] MPD parsing (representations, audio/video tracks, init/media segments).
- [x] Segment template handling, byte ranges.

### 2.3 Live stream recording
- [ ] Continuous playlist/MPD polling; new segment download.
- [ ] "Stop and save" merges captured segments.
- [ ] Live indicator + estimated size/progress.

### 2.4 Subtitles
- [ ] yt-dlp `writesubtitles` toggle, saved alongside media.
- [ ] VTT/SRT selection list in download options.

### 2.5 Post-processing
- [x] Regular download remux option (`-c copy`, `+faststart`, `aac_adtstoasc`).
      MediaMuxer handles the AAC ASC; fast-start rewrites the MP4 index.
- [x] FLV/corrupt stream repair flags (best-effort MediaMuxer remux to MP4).
- [x] Audio-only option: extracts the audio track to M4A. MP3 re-encode needs
      FFmpegKit and stays deferred.

### 2.6 Blob fix (SuperX content-type detection)
- [x] Port `VideoUtils.getContentTypeByUrl` to Dart (`MediaExtractor.probeUrl`):
      GET each resource with the page's own headers, classify by Content-Type
      (mpegurl / dash / video / audio) and by the leading bytes for
      `application/octet-stream`.
- [x] Probe from `shouldInterceptRequest`, matching SuperX's fast-reject of
      `.js/.css/.m4s/.ts` and `blob:` URLs.
- [x] Stop adding raw `blob:` candidates; detected manifest/segment URLs replace
      them (this is how SuperX handles MSE/blob players).
- [x] HLS output is always remuxed to MP4 (native muxer) even without the
      post-processing settings; generic manifest titles (`master.m3u8`, etc.)
      are replaced with the page title for automatic file naming.

---

## Phase 3 - Library, history, player

### 3.1 History
- [x] Persist visited pages (title/url/thumbnail) from browser.
- [x] History screen: open, delete, clear.

### 3.2 Bookmarks
- [x] Add/remove bookmark from browser; bookmarks screen.

### 3.2a Download manager extras
- [x] Pause all / resume all / retry all from the queue tools menu.
- [x] Storage summary (file count + total size) and approximate per-task speed.

### 3.3 Player upgrade
- [x] Remote preview with captured headers (pre-download preview).
- [x] Resume playback position (persist per file).
- [x] Playback speed, aspect/fit toggle, PiP (optional).
- [x] Share / open-with / rename from library.

### 3.4 Storage
- [x] Choose downloads location (app dir / external & SD app folder; public
      Downloads via a MediaStore copy).
- [x] Move existing downloads; open folder.

### 3.5 Export/import
- [ ] JSON export/import of history and bookmarks.

---

## Phase 4 - Browser platform

### 4.1 Multi-tab browser
- [x] Tab model + tab strip, per-tab WebView state and detection.
- [x] New tab / close tab / switch.

### 4.2 Desktop mode
- [x] Per-tab user-agent switch, persisted.

### 4.3 Redirection prompt
- [x] Ask before cross-domain redirects ("don't show again").

### 4.4 Download by URL dialog
- [ ] Paste direct URL; optional audio-only; preview before download.

### 4.4a Pop-up / pop-under blocking
- [x] Port `CustomWebChromeClient.onCreateWindow`: allow a new tab only for a
      real user gesture on an http(s) link; deny JS pop-ups (null request URL).
- [x] Port `shouldOverrideUrlLoading` scheme rule: cancel all non-http(s)
      navigations (intent://, market://, app schemes).
- [x] Block synthetic (`event.isTrusted == false`) and cross-site `_blank`
      clicks; cancel gesture-less cross-site redirects (pop-unders).
- [x] Setting "Block pop-ups and redirect ads" (on by default) controls the
      strict gesture requirement.

### 4.5 Captcha/bot-challenge safety
- [x] Allowlist of challenge hosts (Cloudflare, reCAPTCHA, hCaptcha, FB checkpoint)
      so interception never blocks login/challenge flows.

### 4.5a Search engine / homepage
- [x] Search engine presets (Google, DuckDuckGo, Bing, Custom home + search URL
      template). Browser start page and address-bar searches use the setting.

### 4.5b Clear browsing data
- [x] Browser menu dialog to clear cookies, cache, site data, and history.

### 4.6 Suggestions / top pages
- [x] Local top pages + optional remote list; URL bar suggestions.

---

## Phase 5 - Privacy

### 5.1 WebRTC leak block
- [x] Inject JS stub for RTCPeerConnection in browser pages.

### 5.2 Ad blocker
- [x] Rule list storage + `shouldInterceptRequest` matching (start Dart, native
      engine only if needed).
- [x] Settings: enable/disable, manage lists, update.

### 5.3 Proxy
- [x] HTTP/SOCKS5 proxy config, applied to WebView and HTTP downloads.
      Dart's HttpClient applies HTTP proxies; SOCKS applies to the WebView.
- [x] Optional proxy chain ordering.

### 5.4 Secure DNS
- [x] DoH/DoT presets + custom resolver, applied to HTTP downloads. WebView
      traffic still uses the system resolver.

---

## Deferred / explicitly not planned
- [-] Bundling FFmpegKit - APK size cost; revisit only if HLS/DASH + remux
      cannot be done with MediaMuxer.
- [-] YouTube cookie-based extraction - intentionally disabled in Linky.
- [-] DRM/paywall bypass - out of scope.
- [-] MP3 audio re-encode - Android has no MP3 encoder; M4A extraction is
      provided instead. Revisit only with FFmpegKit.

---

## Completed log
| Date | Item | Notes |
|---|---|---|
| 2026-11-09 | 0.1 Settings store + screen | JSON-backed prefs, theme mode, browser filter toggles, clear cookies |
| 2026-11-09 | 1.2 Detection logs | Ring buffer service, log screen, settings entry, yt-dlp events |
| 2026-11-09 | 1.3 Audio-only quick action | Home video cards queue the paired audio track |
| 2026-11-09 | 1.1 Detection toggles + thresholds | Per-type toggles, min media size, supported-sites list (built + installed) |
| 2026-11-09 | 1.2 Detection logs | DOM scan summaries, browser/network found events with size + duration details |
| 2026-11-09 | 1.3 Audio format choice | Home audio-only action lists extractor audio formats (m4a/webm) |
| 2026-11-09 | 1.4 Chunked downloads | Range probing, parallel chunk workers, single-stream fallback, resumable parts, queue limits |
| 2026-11-09 | 1.5 Download safety/UX | Memory guard, disk pre-check, clipboard queue export/import (built; installed) |
| 2026-11-09 | 2.1 HLS downloader | Master/media parsing, parallel segments, AES-128 via native cipher, fMP4 init, raw concat; host smoke test passed |
| 2026-11-09 | 2.2 DASH downloader | MPD parsing, templates/timeline/lists/base, byte ranges, parallel resumable segments, audio/video mux; host smoke test passed |
| 2026-11-09 | 2.5 Post-processing | Native remux/audio extraction, Dart MP4 fast-start rewrite, repair best-effort, settings toggles; fast-start test passed |
| 2026-11-09 | 3.1 History | JSON-backed visit history, thumbnails from page media/favicon, open/delete/clear screen |
| 2026-11-09 | 3.2 Bookmarks | Browser bookmark toggle, JSON-backed list, thumbnails, open/remove/clear screen |
| 2026-11-09 | 3.3 Player upgrade | Remote preview w/ headers, resume position, speed/fit/PiP, share/open-with/rename via FileProvider |
| 2026-11-09 | 3.4 Storage | App/external/SD location, MediaStore public Downloads copy, move files, open folder |
| 2026-11-09 | 4.1 Multi-tab browser | Per-tab WebView/candidates/yt-dlp/blob state, chip tab strip, new/close/switch |
| 2026-11-09 | 4.2 Desktop mode | Per-tab desktop UA/viewport switch, remembered for new tabs |
| 2026-11-09 | 4.3 Redirect prompt | Cross-site navigation confirmation with "don't ask again" |
| 2026-11-09 | 4.5 Challenge safety | Cloudflare/reCAPTCHA/hCaptcha/FB challenge allowlist bypasses prompts and detection |
| 2026-11-09 | 4.6 Suggestions | Visit counts, local top pages + bookmarks, optional remote list, URL bar suggestions |
| 2026-11-09 | 5.1 WebRTC block | Document-start RTCPeerConnection stub |
| 2026-11-09 | 5.2 Ad blocker | Built-in host rules + remote lists, interception, settings management |
| 2026-11-09 | 5.3 Proxy | WebView proxy override + HTTP download proxy, ordered chain |
| 2026-11-09 | 5.4 Secure DNS | DoH/DoT presets and custom endpoint for download resolution |
| 2026-11-08 | 4.4a Pop-up blocking | SuperX port: onCreateWindow gesture/http gate, non-http scheme cancel, setting |
| 2026-11-08 | 2.6 Blob fix | SuperX port: VideoUtils.getContentTypeByUrl probe from shouldInterceptRequest; blob URLs skipped |
