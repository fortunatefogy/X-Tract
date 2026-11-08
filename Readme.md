Universal Media Downloader & Telegram Publisher
 
A Flutter-based Android application that extracts publicly accessible images and videos from shared webpage links, downloads them to your device, and optionally publishes them directly to your Telegram channel.
 
Overview
 
Universal Media Downloader simplifies collecting media from different websites.
 
Instead of manually downloading images and videos from individual platforms, users can share a webpage link with the application. The app identifies available media, extracts downloadable resources, provides a preview, and allows users to download and publish the media to Telegram.
 
The application aims to provide an IDM-style media detection experience through a simple link-sharing workflow.
 
Core Workflow
 
1. Find an image or video on any supported website.
2. Tap the Share button and select the application.
3. The application receives and analyzes the shared URL.
4. The extraction engine identifies available images and videos.
5. Preview detected media and select the required files.
6. Download the selected media to local storage.
7. Automatically publish the downloaded media to a configured Telegram channel.
 
Website
   |
   v
Share URL
   |
   v
Flutter Application
   |
   v
URL Detection
   |
   v
Media Extraction Engine
   |
   v
Media Preview
   |
   v
Download Manager
   |
   v
Local Storage
   |
   v
Telegram Bot API
   |
   v
Telegram Channel
 
Supported Platforms
 
Initial platform targets:
 
- X (Twitter)
- Instagram
- Reddit
- Pinterest
- TikTok
- Facebook
- Direct image URLs
- Direct video URLs
- Other supported websites
 
Note: Website compatibility depends on the extraction method, authentication requirements, media format, and access restrictions. Not every website or video can be downloaded.
 
Features
 
1. Universal Link Sharing
 
- Receive shared URLs from other Android applications.
- Support Android Share Intent.
- Detect copied URLs through clipboard integration.
- Automatically identify supported website domains.
 
2. Media Detection
 
- Detect publicly accessible images.
- Detect HTML5 video resources.
- Identify direct MP4 video URLs.
- Detect HLS streams (".m3u8").
- Identify DASH manifests (".mpd").
- Extract multiple media files from supported posts.
- Retrieve available video quality options.
 
3. Media Preview
 
- Display extracted images and videos.
- Show thumbnails and media metadata.
- Display file size when available.
- Select individual or multiple media files.
- Choose available video quality.
 
4. Download Manager
 
- Download images and videos.
- Track download progress.
- Support multiple download tasks.
- Retry failed downloads.
- Save media locally.
- Maintain download history.
- Detect duplicate downloads.
 
5. Telegram Integration
 
- Connect a Telegram bot.
- Configure one or more Telegram channels.
- Automatically publish downloaded media.
- Add custom captions.
- Include original source links.
- Track publishing status.
- Handle failed uploads and retries.
 
6. Offline Support
 
The application will support offline access to locally stored information.
 
Functionality| Offline Support
View downloaded media| Yes
Download history| Yes
Manage local files| Yes
Clipboard URL detection| Yes
Website media extraction| No
Download online media| No
Telegram publishing| No
 
Local extraction may reduce backend dependency, but accessing online media still requires internet connectivity.
 
Technology Stack
 
Technology| Purpose
Flutter| Android application development
Dart| Application programming language
GetX| State management and navigation
Android Share Intent| Receive shared webpage links
Dio| HTTP requests and API communication
yt-dlp| Supported website media extraction
Flutter InAppWebView| Webpage and media inspection
HLS / DASH parsers| Stream metadata detection
background_downloader| Media download management
Hive / Isar| Local database
Python| Backend development
FastAPI| Extraction API
Telegram Bot API| Telegram channel publishing
 
System Architecture
 
                    ANDROID APP
                         |
             +-----------+-----------+
             |                       |
        Share Handler           Clipboard
             |                       |
             +-----------+-----------+
                         |
                    URL Detector
                         |
                  Extractor Manager
                         |
          +--------------+--------------+
          |              |              |
       Backend       WebView        Direct URL
       Extractor     Inspector      Extractor
          |              |              |
          +--------------+--------------+
                         |
                  Media Detection
                         |
                  Preview Interface
                         |
                  Download Manager
                         |
                   Local Storage
                         |
                  Telegram Publisher
                         |
                    Telegram API
                         |
                   Target Channel
 
Extractor Architecture
 
The application will use a modular extractor system.
 
Each extractor will be responsible for handling a particular platform or media source.
 
Planned extractors:
 
- DirectMediaExtractor
- TwitterExtractor
- InstagramExtractor
- RedditExtractor
- PinterestExtractor
- TikTokExtractor
- FacebookExtractor
- GenericWebExtractor
 
A central "ExtractorManager" will identify the appropriate extractor based on the shared URL and available extraction capabilities.
 
If a platform-specific extractor fails, the application can attempt an alternative supported extraction method.
 
Proposed Flutter Project Structure
 
lib/
|
+-- main.dart
|
+-- app/
|   +-- routes/
|   +-- theme/
|   +-- bindings/
|
+-- core/
|   +-- constants/
|   +-- utils/
|   +-- services/
|   +-- network/
|
+-- features/
|   |
|   +-- sharing/
|   |   +-- controllers/
|   |   +-- services/
|   |
|   +-- extraction/
|   |   +-- extractors/
|   |   +-- models/
|   |   +-- services/
|   |
|   +-- downloads/
|   |   +-- controllers/
|   |   +-- services/
|   |   +-- models/
|   |
|   +-- preview/
|   |   +-- controllers/
|   |   +-- screens/
|   |
|   +-- telegram/
|   |   +-- controllers/
|   |   +-- services/
|   |
|   +-- history/
|   |   +-- controllers/
|   |   +-- screens/
|   |
|   +-- settings/
|       +-- controllers/
|       +-- screens/
|
+-- shared/
    +-- widgets/
    +-- models/
    +-- components/
 
Backend Architecture
 
The backend will handle extraction tasks that require server-side processing.
 
Proposed backend structure:
 
backend/
|
+-- app/
|   +-- main.py
|   |
|   +-- api/
|   |   +-- routes/
|   |
|   +-- extractors/
|   |   +-- base_extractor.py
|   |   +-- twitter.py
|   |   +-- instagram.py
|   |   +-- reddit.py
|   |   +-- generic.py
|   |
|   +-- services/
|   |   +-- extraction_service.py
|   |   +-- media_service.py
|   |   +-- telegram_service.py
|   |
|   +-- models/
|   |
|   +-- utils/
|
+-- requirements.txt
+-- Dockerfile
 
Telegram Setup
 
1. Create a Telegram bot using BotFather.
2. Obtain the bot token.
3. Add the bot as an administrator to your Telegram channel.
4. Grant permission to post messages.
5. Configure the channel ID in the application backend.
6. Test publishing an image and video.
 
Security: Never expose the Telegram bot token inside the Flutter application. Store it securely on the backend.
 
API Design (Proposed)
 
Method| Endpoint| Description
POST| "/api/extract"| Extract media from a shared URL
GET| "/api/extract/{id}"| Retrieve extraction results
POST| "/api/download"| Start a download task
GET| "/api/download/{id}"| Check download status
POST| "/api/telegram/publish"| Publish media to Telegram
GET| "/api/telegram/channels"| Retrieve configured channels
 
Development Roadmap
 
- [ ] Initialize Flutter project.
- [ ] Implement application theme and navigation.
- [ ] Implement Android Share Intent.
- [ ] Implement clipboard detection.
- [ ] Develop URL detection service.
- [ ] Implement direct image extraction.
- [ ] Implement direct video extraction.
- [ ] Develop generic webpage media detection.
- [ ] Integrate yt-dlp for supported websites.
- [ ] Implement WebView media inspection.
- [ ] Develop media preview interface.
- [ ] Implement video quality selection.
- [ ] Integrate download manager.
- [ ] Implement local database and download history.
- [ ] Integrate Telegram Bot API.
- [ ] Implement automatic Telegram publishing.
- [ ] Add retry and error handling.
- [ ] Test supported websites and devices.
- [ ] Prepare Android release.
 
Limitations and Considerations
 
- Not all websites expose downloadable media.
- Some platforms require authentication.
- Some videos use DRM or encrypted streams.
- HLS and DASH streams may require additional processing.
- Shared webpage URLs do not automatically carry browser session cookies.
- WebView inspection can detect accessible media requests but cannot guarantee extraction.
- Large videos may exceed Telegram Bot API upload limits.
- Website terms, copyright, privacy and content permissions must be respected.
 
The application will not attempt to bypass DRM or access controls.
 
Future Enhancements
 
- Automatic media categorization.
- Multiple Telegram channel management.
- Background extraction and downloads.
- Scheduled publishing.
- Custom download rules.
- Media compression.
- Automatic thumbnail generation.
- Duplicate detection using file hashes.
- Download statistics.
- Additional website extractors.
 
Project Goal
 
Build a reliable, modular, offline-capable Android media management application that combines universal link sharing, IDM-style media detection, media downloading and automated Telegram publishing in one place.
 
---
 
Project Type: Personal Android Utility
 
Frontend: Flutter
 
Backend: Python / FastAPI
 
Integration: Telegram Bot API
 
Platform: Android (initial release)
# X-Tract
