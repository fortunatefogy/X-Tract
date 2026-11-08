# SuperX (super-video-downloader) - Feature Study & Linky Port Backlog

Source studied: `super-video-downloader-master.zip` + https://github.com/alexch33/super-video-downloader
Package: `com.myAllVideoBrowser` (app name "SuperX"), Kotlin/Android, F-Droid + Play Store.

Purpose of this file: full inventory of every feature in SuperX, its media
detection/fetching method, its optimization techniques, and a gap + roadmap
list so we can port features into Linky one by one.

---

## 1. App snapshot

| Aspect | SuperX |
|---|---|
| Language / UI | Kotlin, Android Views + DataBinding, Material |
| Architecture | MVVM + Repository, Dagger 2 DI |
| Persistence | Room (history, bookmarks, top pages, video info, progress, adblock lists) |
| Concurrency | Coroutines + RxJava 3 + WorkManager |
| Networking | OkHttp (proxy-aware client), Retrofit |
| Download engines | youtube-dl (yausername lib), custom SuperX HLS/DASH parsers, custom multi-thread HTTP downloader, FFmpegKit post-processing |
| Media playback | AndroidX Media3 ExoPlayer with OkHttp data source (custom headers) |
| Privacy | libv2ray (Go) proxy chain, DNS-over-HTTPS/TLS, Rust adblock-rust engine |
| Build | JDK 21, NDK, Go, Rust; ABI splits; reproducible builds |

---

## 2. Complete feature inventory

### 2.1 Browser

- Full in-app browser with **multiple tabs** (WebTab, tab strip, add/close/switch).
- **Home tab**: URL/search box (DuckDuckGo), top pages / bookmarks / suggestions.
- **Desktop mode** (per-WebView user-agent switch, persists).
- **Ask before cross-domain redirection** (dialog, "don't show again").
- **Download by URL** dialog (paste a direct MP4/M3U8 link, optional audio-only).
- **Share intent receiver**: opens `http/https` VIEW links and `text/plain` SEND.
- **Clear browser cookies** setting; cookie handoff to downloader/player.
- **Bot challenge/CAPTCHA aware**: never intercept or strip Cloudflare/Anubis/
  reCAPTCHA/hCaptcha/Arkose/Facebook checkpoint requests.
- **Render process crash handling** (`onRenderProcessGone` -> destroy WebView).
- **Power-save mode warning** (Xiaomi/Doze breaks detection).
- System back/forward/refresh/stop controls with accessibility labels.
- Favicon fetching for history/bookmarks/top pages.

### 2.2 Media / video detection

- **Three detection engines**, independently toggleable:
  1. **URL scanning** ("Check web-sites urls") - inspects page URL / supported-site
     list for embedded media pages (Facebook, TikTok style).
  2. **Regular file detection** - sniffs every network request for MP4/WebM/audio
     media responses; size threshold to ignore ads.
  3. **Stream detection (HLS/DASH)** - detects `.m3u8` / `.mpd` manifests.
     Two implementations: **SuperX parser** (fast, in-app) and **legacy youtube-dl**
     (slower, more compatible).
- **Request interception** via `shouldInterceptRequest` (content-type probing
  with HEAD/GET through proxy-aware OkHttp) plus in-page JS hooks for
  `fetch` and `XMLHttpRequest` (POST/GET) reporting.
- **Detection tuning**:
  - "Check every request on MP4 / M3U8-MPD / audio" toggles.
  - "Only check web-sites urls if in supported list" (remote `supported_pages.json`).
  - **Ads detection threshold** in bytes (ignore small media, e.g. 4 MB default).
  - **Force stream detection** for responses with unknown/`-1` content length.
  - **Interrupt intercepted resources** (return empty body so the page cannot
    play the stream once detected).
- **Detection logs** screen: per-engine START/SUCCESS/FAILED with URL and error -
  used to tune which engine a site needs.
- **Found-video UX**: auto "Video found" dialog (toggleable), floating download
  button (toggleable), per-tab detection state, reload/rescan button.
- Header/cookie capture: detected request headers (cookies, referer, UA) are
  carried into extraction, download and playback.

### 2.3 Format/quality selection

- Download dialog lists all candidate **formats/tracks** (video, audio, muxed)
  with type, resolution/codec, size and URL.
- Title editable before download.
- **"Only Audio"** checkbox (extract audio, output MP3).
- **Preview** the stream in ExoPlayer using captured headers
  (+ "Preview Force" for streams that fail normal preview).
- **Share link** of a selected format via system share sheet.
- Duplicate detection: same video discovered by different engines collapses to
  one entry (URL/format-aware de-dupe, keeps richer metadata).

### 2.4 Download engine

Router picks one of three engines per task (`SystemDownloadManager.getDownloader`):

| Engine | Used for | Mechanics |
|---|---|---|
| `CustomRegularDownloader` | Direct files (MP4/WebM/MP3...) | Range-based multi-thread HTTP download |
| `SuperXDownloader` | HLS `.m3u8` / DASH `.mpd` | Manifest parse, parallel segment fetch, FFmpeg merge |
| `YoutubeDlDownloader` | Everything yt-dlp handles | youtube-dl Android lib per-extractor |

Common capabilities:

- **WorkManager-backed queue** with max simultaneous downloads setting
  (`PENDING`/`DOWNLOADING` flag files in a temp dir; in-process `QueueWorker`
  advances the queue as tasks finish).
- **Pause / resume / cancel / retry / "Stop and Save"** for every task type.
- **Foreground service notifications** with actions, progress, state text
  (preparing/pending/downloading/paused/success/error/canceled).
- **Memory guard**: if device memory is critical, new queue tasks are postponed.
- **Storage locations**: public Downloads, app-private hidden folder, SD-card app
  folder; "Open folder"/"Move downloads"; MediaStore/SAF-aware file moves.
- **Metadata persistence** (`VideoMetadataManager`) so tasks survive restarts.
- **Concurrency limits** configurable per engine (regular threads, HLS/MPD threads).

#### Regular (direct) downloader - `CustomFileDownloader`

- HEAD/GET to get length; **HTTP Range support check**.
- Splits file into N chunks, one worker thread each, writes with
  `RandomAccessFile` + `FileChannel` at chunk offsets (`AtomicLongArray` progress).
- Falls back to **single-threaded streaming** when server lacks Range
  (or user forces stream mode), so broken MP4/stream endpoints still download.
- Pause via flag file, `Stop and Save` mid-stream, cancel deletes temp dir.
- **Force Stream Downloading** toggle for regular live streams.
- Post-processing via **FFmpegKit** (optional): stream copy `-c copy`,
  `aac_adtstoasc`, `+faststart`, FLV `-fflags +discardcorrupt`; audio-only
  re-encode to MP3; applies to all regular downloads or only live recordings.

#### HLS/DASH downloader - `SuperXDownloader`

- Own manifest parsers (`HlsPlaylistParser`, `MpdPlaylistParser`): master/media
  playlists, variants, separate audio renditions, subtitles renditions,
  EXT-X-KEY AES keys, byte ranges, fMP4 init segments, `#EXT-X-ENDLIST`
  (VOD vs live), durations, resolutions, bandwidth.
- **Parallel segment downloads** with coroutine `limitedParallelism(threads)`,
  3 retries per segment with backoff, per-segment file skip for resume.
- **Resume** by scanning already-downloaded segment files (progress recomputed).
- **fMP4 init segment** download and prepend; **encryption key** download.
- **Merge locally with FFmpeg** (concat) into MP4; audio-only extraction skips
  video segments entirely.
- **Live recording** strategies (`HlsLiveDownloader`, `MpdLiveDownloader`):
  continuously poll media playlist/MPD, download new segments, then
  "Stop and Save" merges what was captured.
- Audio/video track pairing for DASH (separate representations).

#### yt-dlp engine - `YoutubeDlDownloaderWorker`

- Runs yt-dlp process with URL + format, monitors progress/temp dir,
  cancellable/destroyable process, stop-and-save partial file.
- **Subtitles download** toggle (yt-dlp subtitle option).
- Format entity passed to the worker (format id / headers / codecs).
- Live stream aware (progress estimation by temp-dir growth).

### 2.5 Library / player

- **Video library** tab: list of downloaded files with size, rename, delete,
  share, "Open with", "Open in folder"; auto-refresh listing.
- **In-app ExoPlayer**: toolbar title, buffering indicator, fullscreen
  (stretch toggle), system back handling; loads remote URLs with captured
  headers (Cookie/Referer) or local files.
- **Playback state persistence** (`PlaybackStateRepository`): remembers current
  URL/position/playing state/title across process death.
- **Progress tab**: all downloads with live percent/speed/size, pause/resume/
  cancel/stop-and-save, multi-select delete/select-all.
- History and bookmarks are separate tabs with search suggestions.

### 2.6 History / bookmarks / suggestions

- Room-backed **browser history** (title, URL, favicon), clear history,
  search/filter, delete entry, open.
- **Bookmarks** list with add/edit/delete, favicon resolution.
- **Export / import history and bookmarks** (JSON to Downloads, with result
  toasts).
- **Top pages / suggestions**: remote `supported_pages.json` feed + local top
  pages, search suggestions, history suggestions in the URL bar.

### 2.7 Ad blocking

- **Rust adblock engine** (`adblock-rust` via JNI) with a **built-in Easylist**
  (`osid.txt`) and **user lists** (name + URL, download/update, enable/disable,
  last-updated).
- Applies at `shouldInterceptRequest` with resource-type classification
  (script/stylesheet/image/media/xhr/subdocument) and at POST level by patching
  `fetch`/XHR in JS (`AndroidBridge.shouldInterceptPost`).
- Compiled engine binary cache (`adblock_engine.bin`) keyed by enabled lists for
  fast startup; never blocks CAPTCHA/bot-challenge hosts.
- Toggle on/off in settings.

### 2.8 Privacy / networking

- **Proxy chains**: multiple HTTP / SOCKS5 proxies with auth, ordered chain,
  "Add Proxy", saved list, current chain display.
- Applies to WebView (`CustomProxyController`) and all OkHttp traffic
  (`OkHttpProxyClient`, retry interceptor).
- **Secure DNS**: DoH and DoT presets (Cloudflare, Quad9, AdGuard) and custom
  `sdns://` stamps (`DnsStampHelper`), powered by libv2ray.
- Foreground "Background proxy" service.
- **WebRTC JS disabled** (stubbed `RTCPeerConnection`) to avoid IP leaks.
- Anti-fingerprint? (not implemented; noted for reference)

### 2.9 Settings (full list from `strings.xml`)

General: videos folder, clear cookies, dark/auto theme, lock portrait,
downloads location, move downloads, queue size, update check, about/help.

Detection: check every request on MP4 / M3U8-MPD / audio, check web-site URLs,
only supported-site list, ads threshold, force stream detection, interrupt
intercepted resources, legacy yt-dlp detection for m3u8/mpd, show video dialog,
floating download button, detection logs.

Downloading: regular thread count, HLS/MPD thread count, force stream download,
post-processing all / live-only regular downloads, download subtitles.

AdBlock: enable, manage lists, add custom list.

Proxy/Network: add HTTP/SOCKS5 proxy, current chain, secure DNS presets/custom.

Diagnostics: detection logs, power-save warning, update checker.

### 2.10 Player / UI extras

- Rename/download title edit before saving.
- Share downloaded file / share format URL.
- Splash screen, bottom navigation (Browser / Progress / Video / Settings).
- Localization (AR, BN, FR, ID, JA, KO, NE, PL, PT-BR, RU, TR, VI, ZH-CN).
- F-Droid reproducible build, fastlane metadata, screenshots.

---

## 3. Media fetching method (end to end)

1. **Page visit**: `WebViewClient.onPageStarted` injects JS hooks that patch
   `fetch`/`XMLHttpRequest` and disables WebRTC. History + detection reset for
   the new URL.
2. **Request interception**: every resource -> `shouldInterceptRequest`.
   - Classify resource type (main frame/script/css/image/media/xhr/html).
   - Adblock check (unless CAPTCHA host) -> return empty response.
   - If enabled, probe content type of candidate URLs by issuing GET through the
     proxy-aware OkHttp client with the request's own headers/cookies
     (`VideoUtils.getContentTypeByUrl`), mapping to M3U8 / MPD / VIDEO / AUDIO.
   - `.m3u8`/`.mpd` -> `verifyLinkStatus` -> SuperX parser (or legacy yt-dlp).
   - MP4/audio -> background `checkRegularVideoOrAudio` with dedupe and
     threshold filtering; only one job per URL; stale jobs per page disposed.
3. **Manifest parsing (SuperX engine)**: fetch manifest text, parse
   master/media playlists or MPD (variants, audio groups, subtitles, encryption,
   byte ranges, live/VOD), fetch first media playlist for duration/live flag.
   Builds `VideoInfo` with formats/tracks, headers, size estimates.
4. **Extraction (yt-dlp engine)**: `VideoService` -> youtubedl-android returns
   formats/metadata; used for regular URL detection and as download engine.
5. **State fan-out**: detected `VideoInfo` pushed to the shared detection model
   -> download button state, auto dialog, floating button, detected-video tab.
6. **Download**: user picks format in dialog; `SystemDownloadManager` saves
   metadata, creates PENDING flag, queue starts up to N tasks, routes to the
   right engine (regular chunks / HLS-DASH segments / yt-dlp).
7. **Post-process**: FFmpeg remux/audio extract when configured; move to
   chosen storage; progress + notification updates; library refresh.
8. **Playback**: offline file or remote stream preview via ExoPlayer with
   captured headers; playback state persisted.

---

## 4. Optimization methods worth noting

| Optimization | Where | Why it matters |
|---|---|---|
| Content-type probing through the same cookies/headers | `VideoUtils` | Avoids false negatives on CDN/stream URLs |
| Regex fast-reject (`.js/.css/.m4s/.ts/blob:`) before network probe | `VideoUtils` | Skips most requests cheaply |
| One verification job per URL + job map, dispose on nav | `GlobalVideoDetectionModel` | No duplicate extraction storms |
| Per-page regular-check job storage, disposed on URL change | `CustomWebViewClient` | Prevents leaks across SPA navigation |
| Ads size threshold | settings | Kills ad/pre-roll false positives |
| "Only supported sites" URL list (remote JSON) | `ConfigService` | Cheap URL-based detection, fewer probes |
| Fast in-app manifest parsers vs yt-dlp | `VideoServiceSuperX` | Sub-second HLS/DASH detection |
| Detection engines independently toggleable + logs | settings/logs | Per-site tuning, less CPU |
| Chunked multi-thread download with Range + fallback | `CustomFileDownloader` | Speed, resumability, robustness |
| Segment-level resume (skip existing files) | `HlsDownloader` | Resume HLS/DASH without rework |
| Interleaved video/audio segment downloads | `HlsDownloader` | Better throughput/parallelism |
| Audio-only path skips video segments | `HlsDownloader` | Half the bandwidth for MP3 extract |
| Init-segment (fMP4) support | `HlsDownloader` | Correct fragmented-MP4 output |
| AES key fetch for encrypted HLS | `DownloaderUtils` | Wider site support |
| FLV `-fflags +discardcorrupt`, `aac_adtstoasc`, `+faststart` | `FfmpegProcessor` | Plays broken/partial captures |
| Memory-critical guard before starting tasks | `SystemDownloadManager` | Avoids OOM kills mid-download |
| Flag-file queue + WorkManager | `SystemDownloadManager` | Survives process death, simple state |
| Header/cookie compression + Base64 into WorkManager Data | downloaders | Passes headers safely to workers |
| Binary cache for adblock engine | `AdBlockEngine` | Fast cold start |
| WebRTC stubbing | `CustomWebViewClient` | IP leak prevention |
| CAPTCHA host allowlist | `CustomWebViewClient` | Never break logins/anti-bot |
| `onRenderProcessGone` cleanup | `CustomWebViewClient` | Recovers from WebView crashes |
| Remote config for supported pages / updates | `ConfigService` | Update detection logic without app update |
| Dedupe detected videos by URL/format with merge | `GlobalVideoDetectionModel` | Clean dialog list |

---

## 5. Linky status vs SuperX

Legend: YES = present, PARTIAL = limited/indirect, NO = missing.

| Feature | Linky | Notes |
|---|---|---|
| Multi-tab browser | NO | Single browser screen |
| URL/address bar, nav buttons | YES | |
| Desktop mode / UA switch | NO | |
| Ask-before-redirect | NO | |
| Home screen paste links | YES | Different from SuperX home tab |
| Share intent link handling | YES | `SharedLinkChannel` (debug markers too) |
| Download by URL | YES | Home screen |
| In-page media detection (DOM scan) | YES | JS monitor in `media_browser_screen.dart` |
| Network request detection | PARTIAL | `onLoadResource` / `shouldInterceptRequest` feed candidates |
| yt-dlp extraction | YES | Chaquopy, `linky_ytdlp.py` |
| Custom HLS/DASH manifest parsing | NO | Only Reddit DASH special-case; HLS/DASH skipped |
| Live stream recording | NO | |
| Detection toggles + ads threshold | NO | Hard-coded junk filters |
| Detection logs | NO | |
| Auto "video found" dialog | PARTIAL | Playing strip + sheet |
| Floating download button | NO | Bottom sheet bar exists |
| Format list w/ sizes | YES | Quality variants, sizes, mux plan |
| Audio-only extraction | NO | Audio track shown but muxed download only |
| Preview stream in player | PARTIAL | Downloads then local playback only |
| Share format URL | NO | |
| Chunked multi-thread HTTP download | NO | `MediaDownloader` single stream |
| Pause/resume/cancel/retry UI | YES | FileDownloader-backed |
| Stop-and-save mid-download | NO | |
| WorkManager queue + concurrency limit | PARTIAL | FileDownloader queue, no user limit |
| Memory guard | NO | |
| Storage location options | PARTIAL | App dir + gallery save |
| FFmpeg remux/post-process | NO | Native MediaMuxer for AV merge only |
| FLV/corrupt file handling | NO | |
| Subtitles download | NO | |
| Offline video library w/ rename/share | PARTIAL | Downloads list + delete + gallery save |
| In-app player | YES | `video_player` (local files only) |
| Playback state persistence | NO | |
| Download progress list with actions | YES | |
| History | NO | |
| Bookmarks | NO | |
| Top pages / suggestions | NO | |
| Export/import data | NO | |
| Ad blocker | NO | |
| Proxy chain | NO | |
| DoH/DoT | NO | |
| WebRTC leak block | NO | |
| Settings screen | NO | No user settings at all |
| Locales | NO | English only |
| In-app update check | NO | |
| Captcha-host safety | PARTIAL | No special handling (login walls respected) |

---

## 6. Linky port backlog (implement one by one)

Ordered by value / effort. Each item is self-contained.

### Phase 1 - quick wins (detection + downloads)

- [ ] **Settings screen** (first app-wide settings store; needed by everything else).
- [ ] **Audio-only download** (yt-dlp bestaudio / mux audio only). High user value.
- [ ] **Ad/exact-size threshold + detection toggles** (MP4 / HLS / audio / URL),
      plus junk filtering consolidated from the browser.
- [ ] **Chunked multi-thread downloader** with Range support + single-stream
      fallback (replace/augment `MediaDownloader`).
- [ ] **Stop-and-save** and **resume after process death** for active downloads.
- [ ] **Queue concurrency limit** setting (currently fixed by FileDownloader).
- [ ] **Detection logs screen/log buffer** to tune per-site behavior.

### Phase 2 - streaming engine

- [ ] **HLS/DASH download engine**: manifest parser + parallel segment fetch +
      AES keys + fMP4 init segments + resume by segment files.
- [ ] **Merge/output step**: keep MediaMuxer where possible; consider bundling
      FFmpegKit for concat/remux/FLV repair (big APK cost - decide explicitly).
- [ ] **Live stream recording** (HLS/MPD polling + stop-and-save merge).
- [ ] **Subtitle download** via yt-dlp.

### Phase 3 - library & player

- [ ] **History** (local DB) with clear/delete.
- [ ] **Bookmarks**.
- [ ] **Player upgrade**: remote preview with captured headers, playback state
      persistence, rename/share/open-with, speed/aspect controls.
- [ ] **Storage locations**: public Downloads vs app dir vs SD; move downloads.
- [ ] **Export/import** history & bookmarks (JSON).

### Phase 4 - browser platform

- [ ] **Multi-tab browser** with per-tab detection state.
- [ ] **Desktop mode / UA switching** per tab.
- [ ] **Ask before cross-domain redirect**.
- [ ] **Download by URL dialog** with audio-only and format preview.
- [ ] **Top pages / suggestions** (start local, remote list optional).
- [ ] **Captcha/bot-challenge allowlist** so interception never breaks logins.

### Phase 5 - privacy

- [ ] **Ad blocker** (start with a Dart/HTML-level blocklist; native Rust engine
      only if needed).
- [ ] **Proxy support** (HTTP/SOCKS5 single proxy first, chains later).
- [ ] **DoH/DoT** for resolver security.
- [ ] **WebRTC block** JS injection (cheap, high value).

---

## 7. Notes / constraints for Linky

- Linky deliberately has **no FFmpeg**; native `MediaMuxerHelper` merges A/V.
  HLS/DASH support realistically requires either FFmpegKit or a pure-Dart TS/fMP4
  concatenator - decide before Phase 2.
- YouTube cookie policy in Linky is intentional (logged-in cookies caused
  "Requested format is not available"). Keep SuperX-style header capture for
  non-YouTube sites only.
- Android 16 Xiaomi blocks adb input injection; automated UI tests must use
  CDP into the WebView + share markers (existing `LINKY_*` helpers).
- WebView/list layout lesson already learned: keep the WebView slot stable
  (no conditional siblings) or it remounts and reloads the initial URL.
