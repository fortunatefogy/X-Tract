"""On-device media extraction and downloading through yt-dlp.

yt-dlp exposes every format a site offers. Most high quality streams are
video-only; this module pairs them with the best compatible audio stream and
merges the two with Android's native MediaMuxer, so no external ffmpeg binary
is required.
"""

import base64
import json
import os
import re
import shutil
import tempfile
import urllib.request
import xml.etree.ElementTree as ET
from html import unescape
from urllib.parse import parse_qs, quote, urljoin, urlparse

from yt_dlp import YoutubeDL

_DIRECT_EXTENSIONS = {
    "mp4",
    "m4v",
    "webm",
    "mkv",
    "mov",
    "3gp",
    "flv",
    "mp3",
    "m4a",
    "aac",
    "ogg",
    "oga",
    "opus",
    "wav",
    "flac",
}

# Android can play these in ExoPlayer and MediaMuxer can write the container
# without re-encoding. Anything else (HLS/DASH manifests, DRM) is skipped.
_IMAGE_EXTENSIONS = {"jpg", "jpeg", "png", "webp", "gif", "avif", "heic", "heif"}

_MP4_VIDEO_CODECS = ("avc1", "h264", "hev1", "hvc1")
_WEBM_VIDEO_CODECS = ("vp9", "vp09", "vp8")
_MP4_AUDIO_CODECS = ("mp4a", "aac")
_WEBM_AUDIO_CODECS = ("opus", "vorbis")


def _mime_for(kind, extension):
    extension = (extension or "").lower()
    if kind == "video":
        return {
            "webm": "video/webm",
            "mov": "video/quicktime",
            "mkv": "video/x-matroska",
            "3gp": "video/3gpp",
        }.get(extension, "video/mp4")
    return {
        "m4a": "audio/mp4",
        "aac": "audio/aac",
        "ogg": "audio/ogg",
        "oga": "audio/ogg",
        "opus": "audio/ogg",
        "webm": "audio/webm",
        "wav": "audio/wav",
        "flac": "audio/flac",
    }.get(extension, "audio/mpeg")


def _is_direct_format(fmt):
    extension = str(fmt.get("ext") or "").lower()
    protocol = str(fmt.get("protocol") or "").lower()
    if extension not in _DIRECT_EXTENSIONS:
        return False
    if not protocol:
        return True
    return protocol in ("http", "https")


def _headers_for(fmt, info):
    raw_headers = fmt.get("http_headers") or info.get("http_headers") or {}
    return {
        str(key): str(value)
        for key, value in raw_headers.items()
        if str(key).lower()
        in {"user-agent", "referer", "origin", "accept", "accept-language"}
    }


def _audio_headers(info):
    return _headers_for(info, info)


def _height_for(fmt):
    height = fmt.get("height")
    if isinstance(height, (int, float)) and height > 0:
        return int(height)
    note = str(fmt.get("format_note") or "")
    match = re.search(r"(\d{3,4})p", note)
    if match:
        return int(match.group(1))
    return None


def _codec_name(fmt, field):
    value = str(fmt.get(field) or "none").lower()
    if value == "none":
        return ""
    return value.split(".")[0]


def _is_combined(fmt):
    return _codec_name(fmt, "vcodec") and _codec_name(fmt, "acodec")


def _has_av_stream(info):
    if _codec_name(info, "vcodec") or _codec_name(info, "acodec"):
        return True
    for fmt in info.get("formats") or []:
        if _codec_name(fmt, "vcodec") or _codec_name(fmt, "acodec"):
            return True
    return False


def _mux_container(video_codec, audio_codec):
    if video_codec in _MP4_VIDEO_CODECS and audio_codec in _MP4_AUDIO_CODECS:
        return "mp4"
    if video_codec in _WEBM_VIDEO_CODECS and audio_codec in _WEBM_AUDIO_CODECS:
        return "webm"
    return None


def _video_rank(fmt):
    codec = _codec_name(fmt, "vcodec")
    if codec in _MP4_VIDEO_CODECS:
        codec_rank = 3
    elif codec in _WEBM_VIDEO_CODECS:
        codec_rank = 2
    else:
        codec_rank = 1
    return (
        codec_rank,
        1 if _is_combined(fmt) else 0,
        float(fmt.get("tbr") or fmt.get("vbr") or 0),
    )


def _audio_rank(fmt, preferred_ext):
    extension = str(fmt.get("ext") or "").lower()
    codec = _codec_name(fmt, "acodec")
    preferred = 1 if extension == preferred_ext else 0
    if preferred_ext == "m4a":
        compatible = 1 if codec in _MP4_AUDIO_CODECS else 0
    else:
        compatible = 1 if codec in _WEBM_AUDIO_CODECS else 0
    return (
        preferred,
        compatible,
        float(fmt.get("abr") or fmt.get("tbr") or 0),
    )


def _best_audio(audio_formats, preferred_ext):
    if not audio_formats:
        return None
    return max(audio_formats, key=lambda fmt: _audio_rank(fmt, preferred_ext))


def _size_of(fmt):
    size = fmt.get("filesize") or fmt.get("filesize_approx")
    if isinstance(size, (int, float)) and size > 0:
        return int(size)
    return None


def _probe_size_url(url, headers):
    if not isinstance(url, str) or urlparse(url).scheme not in ("http", "https"):
        return None
    request = urllib.request.Request(url, method="HEAD", headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            length = response.headers.get("Content-Length")
            if length and length.isdigit() and int(length) > 0:
                return int(length)
    except Exception:
        pass
    return None


def _probe_size(fmt, info):
    return _probe_size_url(fmt.get("url"), _headers_for(fmt, info))


def _dimensions_from_url(url):
    if not isinstance(url, str):
        return None, None
    match = re.search(r"/(\d{2,5})x(\d{2,5})/", url)
    if match:
        return int(match.group(1)), int(match.group(2))
    return None, None


def _encoded_height(url):
    if not isinstance(url, str):
        return None
    token = parse_qs(urlparse(url).query).get("efg", [None])[0]
    if not token:
        return None
    try:
        padded = token + "=" * (-len(token) % 4)
        payload = json.loads(base64.urlsafe_b64decode(padded))
        tag = str(payload.get("vencode_tag") or "")
    except Exception:
        return None
    match = re.search(r"C3\.(\d{3,4})", tag)
    return int(match.group(1)) if match else None


_X_HOSTS = ("x.com", "twitter.com", "mobile.twitter.com", "mobile.x.com")
_INSTAGRAM_HOSTS = ("instagram.com", "www.instagram.com")

_last_extract_error = ""

_IMAGE_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36"
    ),
    "Accept": (
        "text/html,application/xhtml+xml,application/xml;q=0.9,"
        "image/avif,image/webp,*/*;q=0.8"
    ),
    "Accept-Language": "en-US,en;q=0.9",
}


_FACEBOOK_HEADERS = {
    "User-Agent": "Twitterbot/1.0",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
}

_FACEBOOK_CRAWLER_HEADERS = {
    "User-Agent": "facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
}

_REDDIT_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Linux; Android 16) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/149.0.0.0 Mobile Safari/537.36"
    ),
    "Accept": "*/*",
}

_REDDIT_POST_HOSTS = (
    "reddit.com",
    "www.reddit.com",
    "old.reddit.com",
    "m.reddit.com",
    "np.reddit.com",
)


def _reddit_video_id(raw_url):
    parsed = urlparse(raw_url)
    if (parsed.hostname or "").lower() != "v.redd.it":
        return None
    part = parsed.path.strip("/").split("/")[0]
    return part if re.fullmatch(r"[A-Za-z0-9]+", part) else None


def _fetch_bytes(url, headers, timeout=20):
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read()


def _fetch_with_final_url(url, headers, timeout=20):
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read(), response.geturl()


def _reddit_dash_items(raw_url):
    video_id = _reddit_video_id(raw_url)
    if not video_id:
        return []
    mpd_url = f"https://v.redd.it/{video_id}/DASHPlaylist.mpd"
    try:
        root = ET.fromstring(_fetch_bytes(mpd_url, _REDDIT_HEADERS))
    except Exception:
        return []

    videos = {}
    audios = []
    for adaptation in root.iter():
        if not adaptation.tag.endswith("AdaptationSet"):
            continue
        content_type = (adaptation.get("contentType") or "").lower()
        mime_type = (adaptation.get("mimeType") or "").lower()
        is_video = content_type == "video" or mime_type.startswith("video/")
        is_audio = content_type == "audio" or mime_type.startswith("audio/")
        for representation in adaptation:
            if not representation.tag.endswith("Representation"):
                continue
            base = next(
                (child for child in representation if child.tag.endswith("BaseURL")),
                None,
            )
            if base is None or not base.text:
                continue
            url = urljoin(mpd_url, base.text.strip())
            bandwidth = int(representation.get("bandwidth") or 0)
            if is_audio:
                audios.append((bandwidth, url))
            elif is_video:
                width = int(representation.get("width") or 0)
                height = int(representation.get("height") or 0)
                current = videos.get(height)
                if current is None or bandwidth > current[0]:
                    videos[height] = (bandwidth, url, width, height)

    if not videos:
        return []

    audio_url = None
    audio_size = None
    if audios:
        audios.sort(reverse=True)
        audio_url = audios[0][1]
        audio_size = _probe_size_url(audio_url, _REDDIT_HEADERS)

    title = f"Reddit video {video_id}"
    items = []
    for height in sorted(videos, reverse=True):
        _, video_url, width, height = videos[height]
        video_size = _probe_size_url(video_url, _REDDIT_HEADERS)
        size = (
            video_size + audio_size
            if video_size is not None and audio_size is not None
            else video_size
        )
        label = f"{height}p" if height else "Original"
        item = {
            "url": video_url,
            "type": "video",
            "title": f"{title} · {label}"[:300],
            "group_title": title,
            "quality_label": label,
            "mime_type": "video/mp4",
            "thumbnail": None,
            "source_page": raw_url,
            "size": size,
            "width": width or None,
            "height": height or None,
            "duration": None,
            "uploader": None,
            "format_id": f"direct-{height or 'original'}",
            "found_in": "Reddit DASH",
            "request_headers": dict(_REDDIT_HEADERS),
            "requires_extractor": True,
            "is_downloadable": True,
        }
        if audio_url:
            item["audio_format_id"] = "direct-audio"
            item["audio_url"] = audio_url
            item["audio_mime_type"] = "audio/mp4"
        items.append(item)
    return items


def _reddit_json_url(raw_url):
    parsed = urlparse(raw_url)
    path = parsed.path.rstrip("/")
    if path.startswith("/gallery/"):
        gallery_id = path.split("/")[-1]
        return f"https://www.reddit.com/comments/{gallery_id}.json?raw_json=1"
    if path.endswith(".json"):
        path = path[:-5]
    url = f"https://www.reddit.com{path}.json?raw_json=1"
    if parsed.query:
        url += f"&{parsed.query}"
    return url


def _cookie_header_for(cookie_text, host):
    if not cookie_text:
        return None
    pairs = []
    for line in cookie_text.splitlines():
        if not line:
            continue
        if line.startswith("#HttpOnly_"):
            line = line[len("#HttpOnly_") :]
        elif line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 7:
            continue
        domain = parts[0].lstrip(".").lower()
        if not (host == domain or host.endswith("." + domain)):
            continue
        pairs.append(f"{parts[5]}={parts[6]}")
    return "; ".join(pairs) if pairs else None


def _reddit_post_id(raw_url):
    match = re.search(
        r"/(?:comments|gallery)/([A-Za-z0-9]+)",
        urlparse(raw_url).path,
    )
    return match.group(1) if match else None


def _reddit_resolve_post(post):
    if not isinstance(post, dict):
        return None
    crossposts = post.get("crosspost_parent_list") or []
    if crossposts and not post.get("is_gallery"):
        parent = crossposts[0]
        if isinstance(parent, dict):
            return parent
    return post


def _reddit_resolve_url(raw_url):
    if _reddit_post_id(raw_url):
        return raw_url
    separator = "&" if "?" in raw_url else "?"
    candidates = [
        raw_url,
        f"{raw_url}{separator}json=1",
        f"{raw_url}{separator}raw_json=1",
    ]
    for candidate in candidates:
        for method in ("HEAD", "GET"):
            try:
                request = urllib.request.Request(
                    candidate, headers=_REDDIT_HEADERS, method=method
                )
                with urllib.request.urlopen(request, timeout=15) as response:
                    final_url = response.geturl()
                    if _reddit_post_id(final_url):
                        return final_url
            except Exception as error:
                final_url = ""
                geturl = getattr(error, "geturl", None)
                if callable(geturl):
                    try:
                        final_url = geturl() or ""
                    except Exception:
                        final_url = ""
                if _reddit_post_id(final_url):
                    return final_url
                response_headers = getattr(error, "headers", None)
                location = (
                    response_headers.get("Location")
                    if response_headers is not None
                    else None
                )
                if location:
                    location_url = urljoin(candidate, location)
                    if _reddit_post_id(location_url):
                        return location_url
    return None


def _reddit_post_data(raw_url, cookie_text="", forced_post_id=""):
    headers = dict(_REDDIT_HEADERS)
    headers["Accept"] = "application/json"
    cookie = _cookie_header_for(cookie_text, "reddit.com")
    if cookie:
        headers["Cookie"] = cookie
    post_id = forced_post_id or _reddit_post_id(raw_url)
    resolved_url = raw_url
    if not post_id:
        resolved = _reddit_resolve_url(raw_url)
        if resolved:
            resolved_url = resolved
            post_id = _reddit_post_id(resolved)

    if post_id:
        try:
            raw = _fetch_bytes(_reddit_json_url(resolved_url), headers)
            data = json.loads(raw.decode("utf-8", "ignore"))
            if isinstance(data, list):
                data = data[0] if data else {}
            if isinstance(data, dict):
                children = (data.get("data") or {}).get("children") or []
                if children and isinstance(children[0], dict):
                    post = _reddit_resolve_post(children[0].get("data"))
                    if post:
                        return post
        except Exception:
            pass

    if not post_id:
        return None
    try:
        archive_url = (
            "https://arctic-shift.photon-reddit.com/api/posts/ids"
            f"?ids={post_id}"
        )
        archive_headers = {
            "User-Agent": _REDDIT_HEADERS["User-Agent"],
            "Accept": "application/json",
        }
        raw = _fetch_bytes(archive_url, archive_headers)
        data = json.loads(raw.decode("utf-8", "ignore"))
        posts = data.get("data") if isinstance(data, dict) else data
        if isinstance(posts, list) and posts:
            return _reddit_resolve_post(posts[0])
    except Exception:
        pass
    return None


def _reddit_direct_url(url):
    parsed = urlparse(url)
    host = (parsed.hostname or "").lower()
    if host in ("preview.redd.it", "external-preview.redd.it"):
        name = parsed.path.strip("/").split("/")[-1]
        if name:
            return f"https://i.redd.it/{name}"
    return url


def _reddit_media_item(
    source_page,
    url,
    kind,
    title,
    label,
    index,
    uploader,
    media_id,
    width=None,
    height=None,
):
    if not isinstance(url, str) or not url.startswith(("http://", "https://")):
        return None
    headers = dict(_REDDIT_HEADERS)
    headers["Referer"] = "https://www.reddit.com/"
    is_video = kind == "video"
    return {
        "url": url,
        "type": kind,
        "title": f"{title} · {label}"[:300],
        "group_title": title,
        "quality_label": "Video" if is_video else "Image",
        "mime_type": "video/mp4" if is_video else _image_mime(url),
        "thumbnail": None,
        "source_page": source_page,
        "size": None,
        "width": width,
        "height": height,
        "duration": None,
        "uploader": uploader,
        "format_id": f"reddit-{media_id or index}",
        "found_in": "Reddit gallery",
        "request_headers": headers,
        "requires_extractor": False,
        "is_downloadable": True,
    }


def _reddit_json_items(raw_url, cookie_text="", forced_post_id=""):
    try:
        post = _reddit_post_data(raw_url, cookie_text, forced_post_id)
    except Exception:
        return []
    if not post:
        return []
    title = re.sub(r"\s+", " ", str(post.get("title") or "")).strip()[:160]
    if not title:
        title = "Reddit post"
    uploader = post.get("author")
    permalink = post.get("permalink")
    source_page = (
        f"https://www.reddit.com{permalink}"
        if isinstance(permalink, str) and permalink.startswith("/")
        else raw_url
    )
    gallery_data = post.get("gallery_data")
    gallery = (
        gallery_data.get("items") or []
        if isinstance(gallery_data, dict)
        else []
    )
    metadata = post.get("media_metadata")
    if not isinstance(metadata, dict):
        metadata = {}
    items = []
    index = 0
    for entry in gallery:
        if not isinstance(entry, dict):
            continue
        media_id = str(entry.get("media_id") or "")
        meta = metadata.get(media_id)
        if not isinstance(meta, dict):
            continue
        if str(meta.get("status") or "valid") != "valid":
            continue
        sizes = meta.get("s")
        if not isinstance(sizes, dict):
            sizes = {}
        caption = re.sub(
            r"\s+", " ", str(entry.get("caption") or "")
        ).strip()[:80]
        label = caption or f"Item {index + 1}"
        width = sizes.get("x")
        height = sizes.get("y")
        mp4_url = sizes.get("mp4")
        gif_url = sizes.get("gif")
        image_url = sizes.get("u")
        media_kind = str(meta.get("e") or "")
        media_mime = str(meta.get("m") or "")
        animated = media_kind == "AnimatedImage" or media_mime == "image/gif"
        chosen_url = None
        chosen_kind = "image"
        if animated:
            if isinstance(gif_url, str) and gif_url:
                chosen_url = _reddit_direct_url(unescape(gif_url))
            elif isinstance(mp4_url, str) and mp4_url:
                candidate = unescape(mp4_url)
                if "preview.redd.it" not in candidate:
                    chosen_url = candidate
                    chosen_kind = "video"
        elif (
            isinstance(mp4_url, str)
            and mp4_url
            and (
                media_kind == "RedditVideo"
                or media_mime.startswith("video/")
                or "v.redd.it" in mp4_url
            )
        ):
            chosen_url = unescape(mp4_url)
            chosen_kind = "video"
        elif isinstance(image_url, str) and image_url:
            chosen_url = _reddit_direct_url(unescape(image_url))
        elif isinstance(gif_url, str) and gif_url:
            chosen_url = _reddit_direct_url(unescape(gif_url))
        elif (
            isinstance(mp4_url, str)
            and mp4_url
            and "preview.redd.it" not in mp4_url
        ):
            chosen_url = unescape(mp4_url)
            chosen_kind = "video"
        if chosen_url:
            index += 1
            item = _reddit_media_item(
                source_page,
                chosen_url,
                chosen_kind,
                title,
                label,
                index,
                uploader,
                media_id,
                width,
                height,
            )
            if item:
                items.append(item)
    if items:
        return items

    destination = post.get("url_overridden_by_dest") or post.get("url")
    hint = str(post.get("post_hint") or "")
    if isinstance(destination, str) and destination:
        path = urlparse(destination).path.lower()
        if hint == "image" or re.search(
            r"\.(jpe?g|png|gif|webp|avif)$", path
        ):
            item = _reddit_media_item(
                source_page,
                destination,
                "image",
                title,
                "Image",
                1,
                uploader,
                post.get("id"),
            )
            if item:
                items.append(item)

    if not items:
        secure_media = post.get("secure_media")
        media = post.get("media")
        reddit_video = None
        if isinstance(secure_media, dict):
            reddit_video = secure_media.get("reddit_video")
        if not isinstance(reddit_video, dict) and isinstance(media, dict):
            reddit_video = media.get("reddit_video")
        if isinstance(reddit_video, dict):
            fallback = reddit_video.get("fallback_url")
            hls = reddit_video.get("hls_url")
            if isinstance(fallback, str) and fallback:
                dash_items = _reddit_dash_items(fallback)
                if dash_items:
                    items.extend(dash_items)
            if not items and isinstance(hls, str) and hls:
                item = _reddit_media_item(
                    source_page,
                    hls,
                    "video",
                    title,
                    "Video",
                    1,
                    uploader,
                    post.get("id"),
                    reddit_video.get("width"),
                    reddit_video.get("height"),
                )
                if item:
                    item["mime_type"] = "application/vnd.apple.mpegurl"
                    items.append(item)
    return items


def _extract_items(info, raw_url):
    title = str(info.get("title") or "Video")[:280]
    thumbnail = info.get("thumbnail")
    source_page = str(info.get("webpage_url") or raw_url)
    duration = info.get("duration")
    uploader = info.get("uploader") or info.get("channel")
    video_formats = []
    audio_formats = []

    for fmt in info.get("formats") or []:
        if fmt.get("has_drm"):
            continue
        media_url = fmt.get("url")
        if not isinstance(media_url, str):
            continue
        if urlparse(media_url).scheme not in ("http", "https"):
            continue
        if not _is_direct_format(fmt):
            # HLS/DASH needs a manifest downloader (ffmpeg); not available.
            continue
        if _codec_name(fmt, "vcodec"):
            video_formats.append(fmt)
        elif _codec_name(fmt, "acodec"):
            audio_formats.append(fmt)

    results = []
    best_by_height = {}
    for fmt in video_formats:
        height = _height_for(fmt)
        if height is None:
            continue
        current = best_by_height.get(height)
        if current is None or _video_rank(fmt) > _video_rank(current):
            best_by_height[height] = fmt

    for height in sorted(best_by_height, reverse=True):
        fmt = best_by_height[height]
        combined = _is_combined(fmt)
        extension = str(fmt.get("ext") or "mp4").lower()
        if combined:
            kind = "video"
            audio = None
            size = _size_of(fmt)
            mime_type = fmt.get("mime_type") or _mime_for(kind, extension)
            requires_extractor = not _is_direct_format(fmt)
        else:
            video_codec = _codec_name(fmt, "vcodec")
            preferred_audio = (
                "webm" if video_codec in _WEBM_VIDEO_CODECS else "m4a"
            )
            audio = _best_audio(audio_formats, preferred_audio)
            if audio is None:
                continue
            output_extension = _mux_container(
                video_codec, _codec_name(audio, "acodec")
            )
            if output_extension is None:
                continue
            mime_type = _mime_for("video", output_extension)
            video_size = _size_of(fmt)
            audio_size = _size_of(audio)
            size = (
                video_size + audio_size
                if video_size is not None and audio_size is not None
                else None
            )
            requires_extractor = True

        label = f"{height}p"
        item = {
            "url": fmt.get("url"),
            "type": "video",
            "title": f"{title} · {label}"[:300],
            "group_title": title,
            "quality_label": label,
            "mime_type": mime_type,
            "thumbnail": thumbnail,
            "source_page": source_page,
            "size": size,
            "width": fmt.get("width"),
            "height": height,
            "duration": duration,
            "uploader": uploader,
            "format_id": fmt.get("format_id"),
            "found_in": "yt-dlp on device",
            "request_headers": _headers_for(fmt, info),
            "requires_extractor": requires_extractor,
            "is_downloadable": True,
        }
        if audio is not None:
            item["audio_format_id"] = audio.get("format_id")
            item["audio_url"] = audio.get("url")
            item["audio_mime_type"] = audio.get("mime_type") or _mime_for(
                "audio", audio.get("ext")
            )
        results.append(item)

    if not any(item.get("type") == "video" for item in results):
        progressive = [
            fmt
            for fmt in info.get("formats") or []
            if str(fmt.get("ext") or "").lower() in ("mp4", "mov", "m4v")
            and _is_direct_format(fmt)
            and not _codec_name(fmt, "vcodec")
            and not _codec_name(fmt, "acodec")
            and isinstance(fmt.get("url"), str)
        ]
        best_progressive = {}
        for fmt in progressive:
            width, height = _dimensions_from_url(fmt.get("url"))
            width = fmt.get("width") or width
            height = (
                fmt.get("height")
                or height
                or _height_for(fmt)
                or _encoded_height(fmt.get("url"))
            )
            key = (width, height)
            current = best_progressive.get(key)
            if current is None or float(fmt.get("tbr") or 0) > float(
                current.get("tbr") or 0
            ):
                best_progressive[key] = fmt
        for width, height in sorted(
            best_progressive, key=lambda key: (key[1] or 0, key[0] or 0), reverse=True
        ):
            fmt = best_progressive[(width, height)]
            label = f"{height}p" if height else "Original"
            results.append(
                {
                    "url": fmt.get("url"),
                    "type": "video",
                    "title": f"{title} · {label}"[:300],
                    "group_title": title,
                    "quality_label": label,
                    "mime_type": fmt.get("mime_type")
                    or _mime_for("video", fmt.get("ext")),
                    "thumbnail": thumbnail,
                    "source_page": source_page,
                    "size": _probe_size(fmt, info) or _size_of(fmt),
                    "width": width,
                    "height": height,
                    "duration": duration,
                    "uploader": uploader,
                    "format_id": fmt.get("format_id"),
                    "found_in": "yt-dlp on device",
                    "request_headers": _headers_for(fmt, info),
                    "requires_extractor": False,
                    "is_downloadable": True,
                }
            )

    audio_options = []
    for preferred_ext in ("m4a", "webm"):
        audio = _best_audio(audio_formats, preferred_ext)
        if audio is None:
            continue
        extension = str(audio.get("ext") or preferred_ext).lower()
        if any(entry["format_id"] == audio.get("format_id") for entry in audio_options):
            continue
        label = f"Audio ({extension.upper()})"
        audio_options.append(
            {
                "url": audio.get("url"),
                "type": "audio",
                "title": f"{title} · {label}"[:300],
                "group_title": title,
                "quality_label": label,
                "mime_type": audio.get("mime_type") or _mime_for("audio", extension),
                "thumbnail": thumbnail,
                "source_page": source_page,
                "size": _size_of(audio),
                "width": None,
                "height": None,
                "duration": duration,
                "uploader": uploader,
                "format_id": audio.get("format_id"),
                "found_in": "yt-dlp on device",
                "request_headers": _audio_headers(info),
                "requires_extractor": not _is_direct_format(audio),
                "is_downloadable": True,
            }
        )
    results.extend(audio_options)

    if not results and not _has_av_stream(info):
        page_host = (urlparse(source_page).hostname or "").lower()
        raw_host = (urlparse(raw_url).hostname or "").lower()
        if page_host in _INSTAGRAM_HOSTS or raw_host in _INSTAGRAM_HOSTS:
            image_url = None
            thumbnails = info.get("thumbnails") or []
            if thumbnails:
                image_url = thumbnails[-1].get("url")
            if not image_url:
                candidate = info.get("url")
                extension = str(info.get("ext") or "").lower()
                mime_type = str(info.get("mime_type") or "").lower()
                if isinstance(candidate, str) and (
                    extension in _IMAGE_EXTENSIONS
                    or mime_type.startswith("image/")
                ):
                    image_url = candidate
            item = _thumbnail_image_item(
                source_page, image_url, title, 1, uploader
            )
            if item:
                results.append(item)

    if not results and isinstance(info.get("url"), str):
        media_url = str(info["url"])
        vcodec = _codec_name(info, "vcodec")
        acodec = _codec_name(info, "acodec")
        kind = "video" if vcodec and acodec else "audio" if acodec else None
        if kind and urlparse(media_url).scheme in ("http", "https"):
            extension = str(info.get("ext") or ("mp4" if kind == "video" else "m4a"))
            label = "Original"
            results.append(
                {
                    "url": media_url,
                    "type": kind,
                    "title": f"{title} · {label}"[:300],
                    "group_title": title,
                    "quality_label": label,
                    "mime_type": info.get("mime_type") or _mime_for(kind, extension),
                    "thumbnail": thumbnail,
                    "source_page": source_page,
                    "size": _probe_size(info, info) or _size_of(info),
                    "width": info.get("width"),
                    "height": info.get("height"),
                    "duration": duration,
                    "uploader": uploader,
                    "format_id": info.get("format_id"),
                    "found_in": "yt-dlp on device",
                    "request_headers": _headers_for(info, info),
                    "requires_extractor": not _is_direct_format(info),
                    "is_downloadable": True,
                }
            )
    return results


def _image_mime(url):
    path = urlparse(url).path.lower()
    if path.endswith(".png"):
        return "image/png"
    if path.endswith(".webp"):
        return "image/webp"
    if path.endswith(".gif"):
        return "image/gif"
    if path.endswith(".avif"):
        return "image/avif"
    return "image/jpeg"


def _image_item(raw_url, url, title, index, width=None, height=None):
    if not isinstance(url, str) or not url.startswith(("http://", "https://")):
        return None
    return {
        "url": url,
        "type": "image",
        "title": title[:300],
        "quality_label": "Image",
        "mime_type": _image_mime(url),
        "thumbnail": None,
        "source_page": raw_url,
        "size": _probe_size_url(url, _IMAGE_HEADERS),
        "width": width,
        "height": height,
        "duration": None,
        "uploader": None,
        "format_id": f"image-{index}",
        "found_in": "post images",
        "request_headers": dict(_IMAGE_HEADERS),
        "requires_extractor": False,
        "is_downloadable": True,
    }


def _thumbnail_image_item(raw_url, url, title, index, uploader=None):
    if not isinstance(url, str) or not url.startswith(("http://", "https://")):
        return None
    return {
        "url": url,
        "type": "image",
        "title": title[:300],
        "quality_label": "Image",
        "mime_type": _image_mime(url),
        "thumbnail": None,
        "source_page": raw_url,
        "size": None,
        "width": None,
        "height": None,
        "duration": None,
        "uploader": uploader,
        "format_id": f"image-{index}",
        "found_in": "post images",
        "request_headers": dict(_IMAGE_HEADERS),
        "requires_extractor": False,
        "is_downloadable": True,
    }


def _x_image_items(raw_url):
    match = re.search(r"/status/(\d+)", raw_url)
    if not match:
        return []
    api_url = (
        "https://cdn.syndication.twimg.com/tweet-result"
        f"?id={match.group(1)}&lang=en&token=x"
    )
    try:
        data = json.loads(_fetch_bytes(api_url, _IMAGE_HEADERS))
    except Exception:
        return []
    if data.get("__typename") == "TweetTombstone":
        return []
    text = re.sub(r"https?://t\.co/\S+", "", str(data.get("text") or ""))
    text = re.sub(r"\s+", " ", text).strip()[:120] or "X post"
    items = []
    for index, media in enumerate(data.get("mediaDetails") or [], start=1):
        if media.get("type") != "photo":
            continue
        media_url = media.get("media_url_https")
        if not media_url:
            continue
        separator = "&" if "?" in media_url else "?"
        original = f"{media_url}{separator}name=orig"
        size = media.get("original_info") or {}
        item = _image_item(
            raw_url,
            original,
            f"{text} · Photo {index}",
            index,
            size.get("width"),
            size.get("height"),
        )
        if item:
            items.append(item)
    return items


def _probe_final_image(url):
    request = urllib.request.Request(
        url, headers={**_IMAGE_HEADERS, "Range": "bytes=0-0"}
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            final_url = response.geturl()
            content_type = (response.headers.get("Content-Type") or "").lower()
            if not content_type.startswith("image/"):
                return None
            length = response.headers.get("Content-Length")
            content_range = response.headers.get("Content-Range") or ""
            total = content_range.rsplit("/", 1)[-1] if "/" in content_range else ""
            size = int(total) if total.isdigit() else (
                int(length) if length and length.isdigit() else None
            )
            response.read(1)
            return final_url, size
    except Exception:
        return None


def _instagram_image_items(raw_url):
    api_url = (
        "https://www.instagram.com/api/v1/oembed/?url="
        + quote(raw_url, safe="")
    )
    try:
        data = json.loads(_fetch_bytes(api_url, _IMAGE_HEADERS))
    except Exception:
        return []
    title = re.sub(r"\s+", " ", str(data.get("title") or "")).strip()
    if not title:
        title = str(data.get("author_name") or "Instagram post")
    thumbnail = data.get("thumbnail_url")
    width = data.get("thumbnail_width")
    height = data.get("thumbnail_height")

    match = re.search(r"/(?:p|reel|tv)/([A-Za-z0-9_-]+)", raw_url)
    if match:
        probed = _probe_final_image(
            f"https://www.instagram.com/p/{match.group(1)}/media/?size=l"
        )
        if probed:
            thumbnail, size = probed
            if width and height:
                original_width = max(width, 1)
                height = max(1, round(height * 1080 / original_width))
                width = 1080
            item = _image_item(
                raw_url,
                thumbnail,
                f"{title[:120]} · Image",
                1,
                width,
                height,
            )
            if item:
                item["size"] = item["size"] or size
                return [item]

    if not thumbnail:
        return []
    item = _image_item(
        raw_url,
        thumbnail,
        f"{title[:120]} · Image",
        1,
        width,
        height,
    )
    return [item] if item else []


def _generic_image_items(raw_url):
    try:
        page = _fetch_bytes(raw_url, _IMAGE_HEADERS).decode("utf-8", "ignore")
    except Exception:
        return []
    page = unescape(page).replace("\\/", "/")
    urls = []
    for tag in re.findall(r"<meta\b[^>]*>", page, re.I):
        if not re.search(
            r'(?:property|name)=["\'](?:og:image(?::url)?|twitter:image(?::src)?)["\']',
            tag,
            re.I,
        ):
            continue
        content = re.search(r'content=["\']([^"\']+)', tag, re.I)
        if content:
            urls.append(content.group(1))
    if not urls:
        if "facebook.com" in (urlparse(raw_url).hostname or "").lower():
            return []
        urls.extend(
            re.findall(
                r'https?://[^\s"\'<>\\]+?\.(?:jpe?g|png|webp|avif|gif)'
                r'(?:\?[^\s"\'<>\\]*)?',
                page,
                re.I,
            )
        )
    title_match = re.search(
        r'<meta[^>]+property=["\']og:title["\'][^>]+content=["\']([^"\']+)',
        page,
        re.I,
    ) or re.search(r"<title[^>]*>(.*?)</title>", page, re.I | re.S)
    title = re.sub(r"\s+", " ", unescape(title_match.group(1))).strip() if title_match else ""
    title = title[:120] or "Image"

    skipped = (
        "logo",
        "icon",
        "avatar",
        "profile_pic",
        "profilepic",
        "sprite",
        "emoji",
        "favicon",
        "placeholder",
        "pixel",
        "1x1",
    )
    seen = set()
    results = []
    for url in urls:
        url = unescape(url).strip()
        if not url.startswith(("http://", "https://")):
            continue
        lowered = url.lower()
        if any(hint in lowered for hint in skipped):
            continue
        if (
            "static.cdninstagram.com" in lowered
            or "static.xx.fbcdn.net" in lowered
            or "/rsrc.php/" in lowered
            or "abs.twimg.com" in lowered
        ):
            continue
        if url in seen:
            continue
        seen.add(url)
        item = _image_item(raw_url, url, f"{title} · Image {len(results) + 1}", len(results) + 1)
        if item:
            results.append(item)
        if len(results) >= 20:
            break
    return results


def _is_facebook_host(host):
    return (
        host == "facebook.com"
        or host.endswith(".facebook.com")
        or host == "fb.watch"
    )


def _is_facebook_video_url(raw_url):
    return bool(
        re.search(
            r"/videos?/|/watch/?\?v=|/reel/|/share/v/|fb\.watch",
            raw_url,
            re.I,
        )
    )


def _facebook_title(raw_url):
    parts = [part for part in urlparse(raw_url).path.split("/") if part]
    if len(parts) >= 2 and parts[-1].isdigit():
        slug = parts[-2]
    elif parts:
        slug = parts[-1]
    else:
        slug = ""
    title = re.sub(r"[-_]+", " ", slug).strip().title()
    return (title or "Facebook video")[:160]


def _facebook_video_items(raw_url):
    if not _is_facebook_video_url(raw_url):
        return []
    embed_url = (
        "https://www.facebook.com/plugins/video.php?href="
        + quote(raw_url, safe="")
        + "&show_text=false&width=720"
    )
    try:
        page = _fetch_bytes(embed_url, _FACEBOOK_HEADERS).decode("utf-8", "ignore")
    except Exception:
        return []
    page = unescape(page).replace("\\/", "/")
    title = _facebook_title(raw_url)
    thumbnail = None
    thumb_match = re.search(
        r'"(?:thumbnail_url|preview_image)":"(https://scontent[^"]+)"', page
    )
    if thumb_match:
        thumbnail = thumb_match.group(1).replace("\\/", "/")
    headers = dict(_IMAGE_HEADERS)
    headers["Referer"] = "https://www.facebook.com/"
    results = []
    for label, key in (("HD", "hd_src"), ("SD", "sd_src")):
        match = re.search(rf'"{key}":"(https:[^"]+)"', page)
        if not match:
            continue
        media_url = unescape(match.group(1)).replace("\\/", "/")
        if not media_url.startswith(("http://", "https://")):
            continue
        if any(item["url"] == media_url for item in results):
            continue
        results.append(
            {
                "url": media_url,
                "type": "video",
                "title": f"{title} · {label}"[:300],
                "group_title": title,
                "quality_label": label,
                "mime_type": "video/mp4",
                "thumbnail": thumbnail,
                "source_page": raw_url,
                "size": None,
                "width": None,
                "height": None,
                "duration": None,
                "uploader": None,
                "format_id": f"facebook-{key}",
                "found_in": "facebook embed",
                "request_headers": headers,
                "requires_extractor": False,
                "is_downloadable": True,
            }
        )
    return results


def _facebook_crawler_image_items(raw_url):
    try:
        page = _fetch_bytes(raw_url, _FACEBOOK_CRAWLER_HEADERS).decode(
            "utf-8", "ignore"
        )
    except Exception:
        return []
    page = unescape(page).replace("\\/", "/")
    media_ids = []
    for marker in re.finditer(r'"all_subattachments"', page):
        window = page[marker.start() : marker.start() + 250000]
        for match in re.finditer(r'"id":"(\d+)","__isMedia":"Photo"', window):
            media_id = match.group(1)
            if media_id not in media_ids:
                media_ids.append(media_id)
    if not media_ids:
        for match in re.finditer(
            r'"photo_image":\{"uri":"https://lookaside\.fbsbx\.com/'
            r'lookaside/crawler/media/\?media_id=(\d+)"',
            page,
        ):
            media_id = match.group(1)
            if media_id not in media_ids:
                media_ids.append(media_id)
    if not media_ids:
        return []
    title_match = re.search(
        r'<meta[^>]+property=["\']og:title["\'][^>]+content=["\']([^"\']+)',
        page,
        re.I,
    )
    title = (
        re.sub(r"\s+", " ", unescape(title_match.group(1))).strip()
        if title_match
        else "Facebook photo"
    )
    title = (title or "Facebook photo")[:160]
    headers = dict(_FACEBOOK_HEADERS)
    headers["Referer"] = "https://www.facebook.com/"
    results = []
    for index, media_id in enumerate(media_ids[:20], start=1):
        image_url = (
            "https://lookaside.fbsbx.com/lookaside/crawler/media/"
            f"?media_id={media_id}"
        )
        item = _thumbnail_image_item(
            raw_url,
            image_url,
            f"{title} · Photo {index}",
            index,
        )
        if item:
            item["title"] = f"{title} · Photo {index}"[:300]
            item["format_id"] = f"facebook-photo-{media_id}"
            item["request_headers"] = headers
            results.append(item)
    return results


def _facebook_image_items(raw_url):
    crawler_items = _facebook_crawler_image_items(raw_url)
    if crawler_items:
        return crawler_items
    urls_to_try = [
        raw_url,
        "https://www.facebook.com/plugins/post.php?href="
        + quote(raw_url, safe="")
        + "&width=500&show_text=true",
    ]
    page = None
    for url in urls_to_try:
        try:
            page = _fetch_bytes(url, _FACEBOOK_HEADERS).decode("utf-8", "ignore")
            if page:
                break
        except Exception:
            continue
    if not page:
        return []
    page = unescape(page).replace("\\/", "/")

    candidates = []
    for tag in re.findall(r"<meta\b[^>]*>", page, re.I):
        if not re.search(
            r'(?:property|name)=["\'](?:og:image(?::url)?|twitter:image(?::src)?)["\']',
            tag,
            re.I,
        ):
            continue
        content = re.search(r'content=["\']([^"\']+)', tag, re.I)
        if content:
            candidates.append(content.group(1))
    candidates.extend(
        re.findall(
            r'"image(?:_url)?":\{"uri":"(https://scontent[^"]+)"',
            page,
            re.I,
        )
    )
    candidates.extend(
        re.findall(r'"image_url":"(https://scontent[^"]+)"', page, re.I)
    )
    candidates.extend(
        re.findall(
            r'https://scontent[^"\'\\\s<>]+?\.(?:jpe?g|webp)'
            r'(?:\?[^"\'\\\s<>]*)?',
            page,
            re.I,
        )
    )

    title_match = re.search(
        r'<meta[^>]+property=["\']og:title["\'][^>]+content=["\']([^"\']+)',
        page,
        re.I,
    )
    title = re.sub(
        r"\s+", " ", unescape(title_match.group(1))
    ).strip() if title_match else "Facebook photo"
    title = (title or "Facebook photo")[:160]

    seen = set()
    results = []
    for url in candidates:
        url = unescape(url).strip()
        if not url.startswith(("http://", "https://")):
            continue
        if url in seen:
            continue
        seen.add(url)
        lowered = url.lower()
        if "static.xx.fbcdn.net" in lowered or "rsrc.php" in lowered:
            continue
        if lowered.split("?")[0].endswith(".png"):
            continue
        if "t39.30808-1" in lowered or "t15.5256-10" in lowered:
            continue
        item = _image_item(
            raw_url,
            url,
            f"{title} · Photo {len(results) + 1}",
            len(results) + 1,
        )
        if item:
            results.append(item)
        if len(results) >= 20:
            break
    return results


def _facebook_items(raw_url):
    items = _facebook_video_items(raw_url)
    if not items:
        items = _facebook_image_items(raw_url)
    return items


def _image_items(raw_url):
    host = (urlparse(raw_url).hostname or "").lower()
    if _is_facebook_host(host):
        return _facebook_image_items(raw_url)
    if host in _X_HOSTS:
        return _x_image_items(raw_url)
    if host in ("instagram.com", "www.instagram.com"):
        return _instagram_image_items(raw_url)
    return _generic_image_items(raw_url)


def _write_cookie_file(cookie_text):
    if not cookie_text:
        return None
    if len(cookie_text) > 512 * 1024 or not cookie_text.startswith("# Netscape HTTP Cookie File"):
        raise ValueError("The browser cookie data is invalid.")
    handle, path = tempfile.mkstemp(prefix="linky-cookies-", suffix=".txt")
    with os.fdopen(handle, "w", encoding="utf-8", newline="\n") as cookie_file:
        cookie_file.write(cookie_text)
    return path


def _extract_info(raw_url, cookie_path):
    global _last_extract_error
    _last_extract_error = ""
    options = {
        "quiet": True,
        "no_warnings": True,
        "noplaylist": False,
        "playlistend": 20,
        "ignoreerrors": True,
        "ignore_no_formats_error": True,
        "skip_download": True,
        "socket_timeout": 20,
        "extractor_retries": 1,
        "retries": 1,
        "cachedir": False,
    }
    if cookie_path:
        options["cookiefile"] = cookie_path
    with YoutubeDL(options) as ydl:
        info = ydl.extract_info(raw_url, download=False)
    if info is not None:
        return info
    retry_options = dict(options)
    retry_options["ignoreerrors"] = False
    try:
        with YoutubeDL(retry_options) as ydl:
            return ydl.extract_info(raw_url, download=False)
    except Exception as error:
        message = str(error)
        _last_extract_error = message
        if (
            "There is no video" not in message
            and "No video could be found" not in message
        ):
            print(f"linky-ytdlp: extraction failed: {message}", flush=True)
        return None


def _items_from_info(info, raw_url):
    if not isinstance(info, dict):
        return []
    entries = info.get("entries")
    if entries is None:
        return _extract_items(info, raw_url)
    items = []
    for entry in entries:
        if isinstance(entry, dict):
            items.extend(_extract_items(entry, raw_url))
            if len(items) >= 300:
                break
    unique = {}
    for item in items:
        key = (
            item.get("source_page"),
            item.get("type"),
            item.get("quality_label"),
            item.get("url") or item.get("title"),
        )
        unique.setdefault(key, item)
    result = list(unique.values())[:300]
    photo_index = 0
    for item in result:
        if item.get("type") != "image":
            continue
        photo_index += 1
        base = re.sub(r"^Video by ", "Photo by ", str(item.get("title") or "Photo"))
        item["title"] = f"{base} · Photo {photo_index}"[:300]
    return result


def extract(raw_url, cookie_text=""):
    parsed = urlparse(raw_url)
    if parsed.scheme not in ("http", "https") or not parsed.hostname:
        raise ValueError("Enter a valid public http or https media page.")

    host = (parsed.hostname or "").lower()
    is_youtube = host.endswith("youtube.com") or host == "youtu.be"
    is_reddit = host in _REDDIT_POST_HOSTS and (
        "/comments/" in parsed.path
        or parsed.path.startswith("/gallery/")
        or re.search(r"/s/[A-Za-z0-9]+", parsed.path) is not None
    )

    if host == "i.redd.it" and re.search(
        r"\.(jpe?g|png|gif|webp|avif)$", parsed.path, re.I
    ):
        item = _image_item(raw_url, raw_url, "Reddit image", 1)
        if item:
            item["request_headers"] = {
                **_REDDIT_HEADERS,
                "Referer": "https://www.reddit.com/",
            }
            print(
                f"linky-ytdlp: {parsed.hostname} -> 1 playable format(s)",
                flush=True,
            )
            return json.dumps({"media": [item], "source": "reddit-image"})

    reddit_items = _reddit_dash_items(raw_url)
    if reddit_items:
        print(
            f"linky-ytdlp: {parsed.hostname} -> {len(reddit_items)} playable format(s)",
            flush=True,
        )
        return json.dumps({"media": reddit_items, "source": "reddit-dash"})

    cookie_path = None if is_youtube else _write_cookie_file(cookie_text)
    try:
        info = _extract_info(raw_url, cookie_path)
        items = _items_from_info(info, raw_url)
        if is_reddit:
            existing_urls = {str(item.get("url")) for item in items}
            try:
                reddit_extra = _reddit_json_items(raw_url, cookie_text)
            except Exception:
                reddit_extra = []
            if not reddit_extra:
                match = re.search(
                    r"\[Reddit\]\s+([A-Za-z0-9]+):", _last_extract_error
                )
                if match:
                    try:
                        reddit_extra = _reddit_json_items(
                            raw_url, cookie_text, match.group(1)
                        )
                    except Exception:
                        reddit_extra = []
            for item in reddit_extra:
                if item.get("url") not in existing_urls:
                    items.append(item)
                    existing_urls.add(str(item.get("url")))
            items = items[:300]
        elif _is_facebook_host(host):
            existing_urls = {str(item.get("url")) for item in items}
            extras = (
                _facebook_items(raw_url)
                if not items
                else (
                    []
                    if _is_facebook_video_url(raw_url)
                    else _facebook_image_items(raw_url)
                )
            )
            for item in extras:
                if item.get("url") not in existing_urls:
                    items.append(item)
                    existing_urls.add(str(item.get("url")))
            items = items[:300]
        elif not is_youtube:
            if not items:
                items = _image_items(raw_url)
            elif host in _X_HOSTS:
                # yt-dlp returns only the video tracks for mixed X posts, so
                # add the photos from the same post alongside them.
                existing_urls = {str(item.get("url")) for item in items}
                for image in _x_image_items(raw_url):
                    if image.get("url") not in existing_urls:
                        items.append(image)
                        existing_urls.add(str(image.get("url")))
                items = items[:300]
        print(
            f"linky-ytdlp: {parsed.hostname} -> {len(items)} playable format(s)",
            flush=True,
        )
        return json.dumps({"media": items, "source": "yt-dlp"})
    finally:
        if cookie_path and os.path.exists(cookie_path):
            os.remove(cookie_path)


def _safe_name(text, fallback="media"):
    name = re.sub(r'[\\/:*?"<>|\r\n\t]+', " ", str(text or "")).strip()
    name = re.sub(r"\s{2,}", " ", name).strip(" .")
    return (name or fallback)[:150]


def _destination_path(output_directory, output_name, extension):
    stem = os.path.splitext(os.path.basename(output_name or ""))[0]
    stem = _safe_name(stem)
    name = f"{stem}.{extension}"
    destination = os.path.join(output_directory, name)
    duplicate = 1
    while os.path.exists(destination):
        destination = os.path.join(output_directory, f"{stem} ({duplicate}).{extension}")
        duplicate += 1
    return destination


class _ProgressReporter:
    """Relays download progress to the Flutter UI through a Kotlin bridge."""

    def __init__(self, task_id):
        self.task_id = str(task_id or "")
        self._bridge = None
        self._last = -1
        if not self.task_id:
            return
        try:
            from java import jclass

            self._bridge = jclass("com.example.linky.ExtractorProgress")
        except Exception:
            self._bridge = None

    def report(self, fraction):
        if self._bridge is None:
            return
        try:
            fraction = max(0.0, min(1.0, float(fraction)))
        except (TypeError, ValueError):
            return
        step = int(fraction * 100)
        if step == self._last:
            return
        self._last = step
        try:
            self._bridge.report(self.task_id, step / 100.0)
        except Exception:
            pass

    def hook(self, start, end):
        def on_progress(status):
            state = status.get("status")
            if state == "finished":
                self.report(end)
                return
            if state != "downloading":
                return
            downloaded = status.get("downloaded_bytes") or 0
            total = (
                status.get("total_bytes")
                or status.get("total_bytes_estimate")
                or 0
            )
            if not total:
                return
            self.report(start + (end - start) * (downloaded / total))

        return on_progress


def _ytdlp_options(cookie_path):
    options = {
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "skip_download": False,
        "socket_timeout": 60,
        "retries": 2,
        "cachedir": False,
        "noprogress": True,
    }
    if cookie_path:
        options["cookiefile"] = cookie_path
    return options


def _download_format(
    raw_url,
    format_id,
    temporary_directory,
    label,
    cookie_path,
    reporter=None,
    start=0.0,
    end=1.0,
):
    options = _ytdlp_options(cookie_path)
    options["format"] = format_id
    options["outtmpl"] = os.path.join(
        temporary_directory, f"{label}-%(format_id)s.%(ext)s"
    )
    if reporter is not None:
        options["progress_hooks"] = [reporter.hook(start, end)]
    with YoutubeDL(options) as ydl:
        info = ydl.extract_info(raw_url, download=True)
        filename = ydl.prepare_filename(info)
    if not os.path.isfile(filename):
        raise RuntimeError("yt-dlp finished without producing a media stream.")
    return filename


def _download_direct(url, destination, headers, reporter=None, start=0.0, end=1.0):
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=60) as response:
        length = response.headers.get("Content-Length")
        total = int(length) if length and length.isdigit() else 0
        downloaded = 0
        with open(destination, "wb") as handle:
            while True:
                chunk = response.read(1024 * 512)
                if not chunk:
                    break
                handle.write(chunk)
                downloaded += len(chunk)
                if reporter is not None and total > 0:
                    reporter.report(
                        start + (end - start) * (downloaded / total)
                    )
    if not os.path.isfile(destination) or os.path.getsize(destination) <= 0:
        raise RuntimeError("The media stream could not be downloaded.")
    return destination


def _mux_tracks(video_path, audio_path, output_path):
    try:
        from com.example.linky import MediaMuxerHelper

        MediaMuxerHelper.mux(video_path, audio_path, output_path)
    except Exception as error:
        raise RuntimeError(
            f"This device could not merge the video and audio tracks: {error}"
        ) from error
    if not os.path.isfile(output_path) or os.path.getsize(output_path) <= 0:
        raise RuntimeError("The merged media file could not be written.")


def download(
    raw_url,
    format_id,
    output_directory,
    cookie_text="",
    audio_format_id="",
    video_url="",
    audio_url="",
    headers_json="",
    output_name="",
    video_mime_type="",
    audio_mime_type="",
    task_id="",
):
    parsed = urlparse(raw_url)
    if parsed.scheme not in ("http", "https") or not parsed.hostname:
        raise ValueError("The source page URL is invalid.")
    host = (parsed.hostname or "").lower()
    is_youtube = host.endswith("youtube.com") or host == "youtu.be"
    if not format_id or len(format_id) > 80:
        raise ValueError("The selected media format is invalid.")
    if audio_format_id and len(audio_format_id) > 80:
        raise ValueError("The selected audio format is invalid.")
    if not os.path.isdir(output_directory):
        os.makedirs(output_directory, exist_ok=True)

    request_headers = dict(_REDDIT_HEADERS)
    if headers_json:
        try:
            extra_headers = json.loads(headers_json)
            if isinstance(extra_headers, dict):
                request_headers = {
                    str(key): str(value) for key, value in extra_headers.items()
                }
        except (TypeError, ValueError):
            pass

    cookie_path = None if is_youtube else _write_cookie_file(cookie_text)
    temporary_directory = tempfile.mkdtemp(prefix="linky-download-", dir=output_directory)
    reporter = _ProgressReporter(task_id)
    video_end = 0.9

    try:
        if format_id.startswith("direct-") and video_url:
            video_path = _download_direct(
                video_url,
                os.path.join(temporary_directory, "video.mp4"),
                request_headers,
                reporter,
                0.0,
                video_end if audio_url else 0.98,
            )
            audio_path = (
                _download_direct(
                    audio_url,
                    os.path.join(temporary_directory, "audio.m4a"),
                    request_headers,
                    reporter,
                    video_end,
                    0.98,
                )
                if audio_url
                else None
            )
        else:
            video_path = _download_format(
                raw_url,
                format_id,
                temporary_directory,
                "video",
                cookie_path,
                reporter,
                0.0,
                video_end if audio_format_id else 0.98,
            )
            audio_path = (
                _download_format(
                    raw_url,
                    audio_format_id,
                    temporary_directory,
                    "audio",
                    cookie_path,
                    reporter,
                    video_end,
                    0.98,
                )
                if audio_format_id
                else None
            )

        reporter.report(0.98)
        if audio_path:
            video_mime = (video_mime_type or "").lower()
            if "webm" in video_mime:
                output_extension = "webm"
            elif "mp4" in video_mime:
                output_extension = "mp4"
            else:
                output_extension = (
                    "webm"
                    if os.path.splitext(video_path)[1].lower() == ".webm"
                    else "mp4"
                )
            destination = _destination_path(
                output_directory, output_name, output_extension
            )
            merged = os.path.join(temporary_directory, f"merged.{output_extension}")
            _mux_tracks(video_path, audio_path, merged)
            os.replace(merged, destination)
        else:
            extension = os.path.splitext(video_path)[1].lstrip(".") or "mp4"
            destination = _destination_path(output_directory, output_name, extension)
            os.replace(video_path, destination)
        reporter.report(1.0)
        print(f"linky-ytdlp: downloaded {os.path.basename(destination)}", flush=True)
        return destination
    finally:
        if cookie_path and os.path.exists(cookie_path):
            os.remove(cookie_path)
        try:
            shutil.rmtree(temporary_directory, ignore_errors=True)
        except OSError:
            pass
