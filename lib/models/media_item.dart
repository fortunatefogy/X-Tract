class MediaItem {
  const MediaItem({
    required this.url,
    required this.type,
    this.title,
    this.mimeType,
    this.thumbnail,
    this.sourcePage,
    this.size,
    this.alt,
    this.width,
    this.height,
    this.foundIn,
    this.requestHeaders = const {},
    this.isDownloadable = true,
    this.isPlaying = false,
    this.durationSeconds,
    this.uploader,
    this.formatId,
    this.audioFormatId,
    this.audioUrl,
    this.audioMimeType,
    this.groupTitle,
    this.qualityLabel,
    this.requiresExtractor = false,
  });

  final String url;
  final String type;
  final String? title;
  final String? mimeType;
  final String? thumbnail;
  final String? sourcePage;
  final int? size;
  final String? alt;
  final int? width;
  final int? height;
  final String? foundIn;
  final Map<String, String> requestHeaders;
  final bool isDownloadable;
  final bool isPlaying;
  final int? durationSeconds;
  final String? uploader;
  final String? formatId;
  final String? audioFormatId;
  final String? audioUrl;
  final String? audioMimeType;
  final String? groupTitle;
  final String? qualityLabel;
  final bool requiresExtractor;

  factory MediaItem.fromJson(Map<String, dynamic> json) => MediaItem(
        url: json['url'] as String,
        type: json['type'] as String? ?? 'unknown',
        title: json['title'] as String?,
        mimeType: json['mime_type'] as String?,
        thumbnail: json['thumbnail'] as String?,
        sourcePage: json['source_page'] as String?,
        size: json['size'] as int?,
        alt: json['alt'] as String?,
        width: json['width'] as int?,
        height: json['height'] as int?,
        foundIn: json['found_in'] as String?,
        requestHeaders: (json['request_headers'] as Map<String, dynamic>? ?? {})
            .map((key, value) => MapEntry(key, value.toString())),
        isDownloadable: json['is_downloadable'] as bool? ?? true,
        isPlaying: json['is_playing'] as bool? ?? false,
        durationSeconds: (json['duration'] as num?)?.round(),
        uploader: json['uploader'] as String?,
        formatId: json['format_id'] as String?,
        audioFormatId: json['audio_format_id'] as String?,
        audioUrl: json['audio_url'] as String?,
        audioMimeType: json['audio_mime_type'] as String?,
        groupTitle: json['group_title'] as String?,
        qualityLabel: json['quality_label'] as String?,
        requiresExtractor: json['requires_extractor'] as bool? ?? false,
      );
}
