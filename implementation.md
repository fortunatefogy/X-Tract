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
- [ ] Setting: detect images / videos / audio / documents independently.
- [ ] Setting: ad/media size threshold (bytes) to ignore small media.
- [ ] Apply toggles in browser candidate collection and home platform extraction.
- [ ] "Only supported sites" URL list (local default + optional remote JSON).

### 1.2 Detection logs
- [x] In-app ring buffer of detection events (engine, URL, result, error).
      `lib/services/detection_log_service.dart` (300 entries, ChangeNotifier).
- [x] Settings screen entry + `lib/features/detection_logs/detection_logs_screen.dart`
      (view, clear).
- [x] Wired yt-dlp `start` / `discarded` / `found|empty` / `error` events from
      the in-app browser.
- [ ] Add network/DOM scan events and size/duration details.
- [ ] Helpful when tuning per-site detection.

### 1.3 Audio-only quick action
- [x] "Download audio only" action on video group cards (home), uses the paired
      audio track; direct audio URLs download as files, extractor tracks go
      through yt-dlp.
- [x] Audio tracks already emitted by extractor and downloadable from the
      browser sheet (Audio category) and Home audio group - verified in code.
- [ ] Optional: audio format choice (m4a/webm).

### 1.4 Chunked multi-thread downloads
- [ ] HTTP Range detection (HEAD/GET); split into N chunks with parallel workers.
- [ ] Fallback to single stream when server lacks Range or Range is broken.
- [ ] Configurable thread count + max simultaneous downloads in settings.
- [ ] Resume across process death (chunk files + metadata), stop-and-save.

### 1.5 Download safety/UX
- [ ] Memory guard before starting queued tasks (skip/postpone when low memory).
- [ ] Disk-space pre-check and clear error messages.
- [ ] Export/import queued task list (optional).

---

## Phase 2 - Streaming engine

### 2.1 HLS (.m3u8) downloader
- [ ] Master/media playlist parsing (variants, separate audio, subtitles, live).
- [ ] Parallel segment download with retries + segment-level resume.
- [ ] AES-128 key download + decryption path.
- [ ] fMP4 init segment handling.
- [ ] Output: concat via MediaMuxer where possible; FFmpegKit decision required.

### 2.2 DASH (.mpd) downloader
- [ ] MPD parsing (representations, audio/video tracks, init/media segments).
- [ ] Segment template handling, byte ranges.

### 2.3 Live stream recording
- [ ] Continuous playlist/MPD polling; new segment download.
- [ ] "Stop and save" merges captured segments.
- [ ] Live indicator + estimated size/progress.

### 2.4 Subtitles
- [ ] yt-dlp `writesubtitles` toggle, saved alongside media.
- [ ] VTT/SRT selection list in download options.

### 2.5 Post-processing
- [ ] Regular download remux option (`-c copy`, `+faststart`, `aac_adtstoasc`).
- [ ] FLV/corrupt stream repair flags.
- [ ] Audio-only re-encode option (MP3).

---

## Phase 3 - Library, history, player

### 3.1 History
- [ ] Persist visited pages (title/url/thumbnail) from browser.
- [ ] History screen: open, delete, clear.

### 3.2 Bookmarks
- [ ] Add/remove bookmark from browser; bookmarks screen.

### 3.3 Player upgrade
- [ ] Remote preview with captured headers (pre-download preview).
- [ ] Resume playback position (persist per file).
- [ ] Playback speed, aspect/fit toggle, PiP (optional).
- [ ] Share / open-with / rename from library.

### 3.4 Storage
- [ ] Choose downloads location (app dir / public Downloads / SD).
- [ ] Move existing downloads; open folder.

### 3.5 Export/import
- [ ] JSON export/import of history and bookmarks.

---

## Phase 4 - Browser platform

### 4.1 Multi-tab browser
- [ ] Tab model + tab strip, per-tab WebView state and detection.
- [ ] New tab / close tab / switch.

### 4.2 Desktop mode
- [ ] Per-tab user-agent switch, persisted.

### 4.3 Redirection prompt
- [ ] Ask before cross-domain redirects ("don't show again").

### 4.4 Download by URL dialog
- [ ] Paste direct URL; optional audio-only; preview before download.

### 4.5 Captcha/bot-challenge safety
- [ ] Allowlist of challenge hosts (Cloudflare, reCAPTCHA, hCaptcha, FB checkpoint)
      so interception never blocks login/challenge flows.

### 4.6 Suggestions / top pages
- [ ] Local top pages + optional remote list; URL bar suggestions.

---

## Phase 5 - Privacy

### 5.1 WebRTC leak block
- [ ] Inject JS stub for RTCPeerConnection in browser pages.

### 5.2 Ad blocker
- [ ] Rule list storage + `shouldInterceptRequest` matching (start Dart, native
      engine only if needed).
- [ ] Settings: enable/disable, manage lists, update.

### 5.3 Proxy
- [ ] HTTP/SOCKS5 proxy config, applied to WebView and HTTP downloads.
- [ ] Optional proxy chain ordering.

### 5.4 Secure DNS
- [ ] DoH/DoT presets + custom resolver.

---

## Deferred / explicitly not planned
- [-] Bundling FFmpegKit - APK size cost; revisit only if HLS/DASH + remux
      cannot be done with MediaMuxer.
- [-] YouTube cookie-based extraction - intentionally disabled in Linky.
- [-] DRM/paywall bypass - out of scope.

---

## Completed log
| Date | Item | Notes |
|---|---|---|
| 2026-11-09 | 0.1 Settings store + screen | JSON-backed prefs, theme mode, browser filter toggles, clear cookies |
| 2026-11-09 | 1.2 Detection logs | Ring buffer service, log screen, settings entry, yt-dlp events |
| 2026-11-09 | 1.3 Audio-only quick action | Home video cards queue the paired audio track |
