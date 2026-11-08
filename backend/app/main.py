from __future__ import annotations

import ipaddress
import os
import re
import socket
from urllib.parse import urljoin, urlparse

import httpx
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from starlette.concurrency import run_in_threadpool

app = FastAPI(title="Linky API", version="0.1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)

MAX_PAGE_BYTES = 3_000_000
URL_RE = re.compile(r'''(?:src|href|content)\s*=\s*["']([^"']+)["']''', re.I)


class ExtractRequest(BaseModel):
    url: str = Field(min_length=8, max_length=4096)


class PublishRequest(BaseModel):
    media_url: str = Field(min_length=8, max_length=4096)
    caption: str = Field(default="", max_length=1024)
    chat_id: str | None = Field(default=None, max_length=128)


def validate_public_url(url: str) -> str:
    parsed = urlparse(url)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise HTTPException(400, "Only http and https URLs are supported.")
    try:
        addresses = socket.getaddrinfo(parsed.hostname, parsed.port or (443 if parsed.scheme == "https" else 80))
        if not addresses:
            raise ValueError("no addresses")
        for address in addresses:
            ip = ipaddress.ip_address(address[4][0])
            if not ip.is_global:
                raise HTTPException(400, "Private and local network URLs are not allowed.")
    except HTTPException:
        raise
    except (OSError, ValueError):
        raise HTTPException(400, "The URL host could not be resolved.")
    return url


def classify(url: str, content_type: str = "") -> str | None:
    path = urlparse(url).path.lower()
    kind = content_type.lower()
    if kind.startswith("image/") or re.search(r"\.(jpg|jpeg|png|gif|webp|avif)(?:$)", path):
        return "image"
    if kind.startswith("video/") or re.search(r"\.(mp4|webm|mov|m4v|m3u8|mpd)(?:$)", path):
        return "video"
    return None


def _yt_dlp_extract(url: str) -> list[dict]:
    """Extract directly downloadable, progressive media with yt-dlp."""
    from yt_dlp import YoutubeDL

    options = {
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "skip_download": True,
        "socket_timeout": 20,
        "extractor_retries": 1,
        "retries": 1,
        "cachedir": False,
    }
    with YoutubeDL(options) as ydl:
        info = ydl.extract_info(url, download=False)
    if not isinstance(info, dict):
        return []

    title = str(info.get("title") or "Video")[:300]
    thumbnail = info.get("thumbnail")
    source_page = str(info.get("webpage_url") or url)
    formats = info.get("formats") or []
    candidates: dict[tuple[str, int | None], dict] = {}
    for fmt in formats:
        media_url = fmt.get("url")
        if not isinstance(media_url, str) or urlparse(media_url).scheme not in {"http", "https"}:
            continue
        vcodec = fmt.get("vcodec") or "none"
        acodec = fmt.get("acodec") or "none"
        if vcodec == "none" and acodec == "none":
            continue
        # Only return a video stream if it already contains audio. Split
        # video/audio formats need server-side muxing and ffmpeg.
        kind = "video" if vcodec != "none" and acodec != "none" else "audio" if vcodec == "none" else None
        if kind is None:
            continue
        height = int(fmt["height"]) if fmt.get("height") else None
        format_title = f"{title} · {height}p" if kind == "video" and height else f"{title} · audio" if kind == "audio" else title
        raw_headers = fmt.get("http_headers") or info.get("http_headers") or {}
        safe_headers = {
            str(key): str(value)
            for key, value in raw_headers.items()
            if str(key).lower() in {"user-agent", "referer", "origin", "accept", "accept-language"}
        }
        item = {
            "url": media_url,
            "type": kind,
            "title": format_title[:300],
            "mime_type": fmt.get("mime_type") or ("video/mp4" if kind == "video" else "audio/mpeg"),
            "thumbnail": thumbnail,
            "source_page": source_page,
            "size": fmt.get("filesize") or fmt.get("filesize_approx"),
            "width": fmt.get("width"),
            "height": height,
            "found_in": "yt-dlp",
            "request_headers": safe_headers,
            "is_downloadable": True,
        }
        key = (kind, height if kind == "video" else None)
        current = candidates.get(key)
        if current is None or (fmt.get("tbr") or 0) > (current.get("_tbr") or 0):
            item["_tbr"] = fmt.get("tbr") or 0
            candidates[key] = item

    results = list(candidates.values())
    if not results and info.get("url"):
        media_url = str(info["url"])
        kind = classify(media_url, str(info.get("mime_type") or ""))
        if kind and urlparse(media_url).scheme in {"http", "https"}:
            results.append({
                "url": media_url,
                "type": kind,
                "title": title,
                "mime_type": info.get("mime_type"),
                "thumbnail": thumbnail,
                "source_page": source_page,
                "width": info.get("width"),
                "height": info.get("height"),
                "found_in": "yt-dlp",
                "request_headers": {},
                "is_downloadable": True,
            })
    results.sort(key=lambda item: (item["type"] != "video", -(item.get("height") or 0)))
    for item in results:
        item.pop("_tbr", None)
    return results[:20]


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/api/extract")
async def extract(request: ExtractRequest) -> dict:
    url = validate_public_url(request.url)
    media: dict[str, dict] = {}
    direct_type = classify(url)
    if direct_type:
        media[url] = {"url": url, "type": direct_type, "source_page": url}
        return {"media": list(media.values()), "source": "direct"}

    # Try yt-dlp first for social/video sites and other supported extractors.
    # Fall back to generic HTML scanning for ordinary public pages.
    try:
        extracted = await run_in_threadpool(_yt_dlp_extract, url)
        if extracted:
            return {"media": extracted, "source": "yt-dlp"}
    except Exception:
        pass

    try:
        async with httpx.AsyncClient(
            follow_redirects=False,
            timeout=20,
            headers={"User-Agent": "Linky/0.1 (+public media discovery)"},
        ) as client:
            current_url = url
            for _ in range(6):
                validate_public_url(current_url)
                response = await client.get(current_url)
                if response.is_redirect:
                    location = response.headers.get("location")
                    if not location:
                        raise HTTPException(422, "The webpage returned an invalid redirect.")
                    current_url = urljoin(str(response.url), location)
                    continue
                response.raise_for_status()
                break
            else:
                raise HTTPException(422, "The webpage redirected too many times.")
    except httpx.HTTPError as exc:
        raise HTTPException(422, f"Could not read the public webpage: {exc.__class__.__name__}")
    content_type = response.headers.get("content-type", "")
    if classify(str(response.url), content_type):
        final_url = str(response.url)
        media[final_url] = {"url": final_url, "type": classify(final_url, content_type), "source_page": url}
    elif "html" in content_type.lower():
        body_bytes = bytearray()
        async for chunk in response.aiter_bytes():
            remaining = MAX_PAGE_BYTES - len(body_bytes)
            if remaining <= 0:
                break
            body_bytes.extend(chunk[:remaining])
            if len(chunk) > remaining:
                break
        body = bytes(body_bytes).decode(response.encoding or "utf-8", errors="ignore")
        for match in URL_RE.finditer(body):
            candidate = urljoin(str(response.url), match.group(1).replace("&amp;", "&"))
            kind = classify(candidate)
            if kind and urlparse(candidate).scheme in {"http", "https"}:
                media.setdefault(candidate, {"url": candidate, "type": kind, "source_page": url})
        # Include Open Graph media URLs and common video/source tags by explicit patterns.
        for match in re.finditer(r'''<meta[^>]+(?:property|name)=["'](?:og:image|og:video|twitter:image|twitter:player:stream)["'][^>]+content=["']([^"']+)''', body, re.I):
            candidate = urljoin(str(response.url), match.group(1).replace("&amp;", "&"))
            kind = classify(candidate)
            if kind:
                media.setdefault(candidate, {"url": candidate, "type": kind, "source_page": url})
    return {"media": list(media.values())[:100], "source": "generic"}


@app.post("/api/telegram/publish")
async def publish(request: PublishRequest) -> dict:
    token = os.getenv("TELEGRAM_BOT_TOKEN")
    chat_id = request.chat_id or os.getenv("TELEGRAM_DEFAULT_CHAT_ID")
    if not token or not chat_id:
        raise HTTPException(503, "Telegram publishing is not configured on the backend.")
    media_url = validate_public_url(request.media_url)
    media_type = classify(media_url)
    method = "sendPhoto" if media_type == "image" else "sendVideo" if media_type == "video" else None
    if not method:
        raise HTTPException(415, "Only direct image and video URLs can be published.")
    async with httpx.AsyncClient(timeout=60) as client:
        response = await client.post(
            f"https://api.telegram.org/bot{token}/{method}",
            data={
                "chat_id": chat_id,
                "caption": request.caption,
                "photo" if method == "sendPhoto" else "video": media_url,
            },
        )
    if response.is_error or not response.json().get("ok"):
        raise HTTPException(502, "Telegram could not publish this media.")
    return {"status": "published", "message_id": response.json()["result"]["message_id"]}
