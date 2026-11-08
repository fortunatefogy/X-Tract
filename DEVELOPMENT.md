# Development setup

## Run Linky on an Android device

Install Flutter and Android Studio, connect the phone, then run from the repository root:

```powershell
flutter pub get
flutter run
```

The app runs extraction on the phone and does not require a separate server. It embeds yt-dlp using Chaquopy for supported site links, and falls back to public HTML/WebView inspection. Paste or share one or more links; multiple URLs are deduplicated and checked in sequence, up to 20 at a time. Yt-dlp playlist links are capped at 20 entries. Results include extracted thumbnails, duration/uploader metadata, and progressive quality choices when the site exposes them. In the in-app browser, actively playing HTML5 videos appear in a strip above the page and at the top of the Videos results. HTML inspection also covers common image, video, audio, subtitle, and document formats; page tags and links; responsive and lazy image sources; inline/computed CSS backgrounds; Open Graph/Twitter metadata; JSON-LD; browser resource requests; and fetch/XHR responses. Results are deduplicated and grouped by type.

Selected media downloads stay in Linky's app storage. Open Downloads to play saved video files, view images, delete files, or select items and save copies to the phone Gallery.

Site support varies with the embedded yt-dlp version and each site's current behavior. YouTube's current full extraction may require a JavaScript runtime not yet packaged with Linky, so some YouTube links or quality levels may still fail. The app offers directly playable progressive formats; split adaptive streams needing ffmpeg merging are not assembled on the phone. Login-only media, DRM, and encrypted streams are not bypassed. HLS/DASH manifests, embedded players, and subtitles can be detected where exposed, but segmented stream assembly, embed traversal, and subtitle export are not implemented. A browser `blob:` video can be saved when the page exposes it as a readable Blob, up to 512 MB; MediaSource streams and protected player data remain unavailable. WebView request monitoring also has platform limits and cannot see every service worker or protected player request. URL warnings identify suspicious patterns but are not a full threat scanner.

Telegram integration remains deferred. Its bot token must stay on the backend.
