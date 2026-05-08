"""
Image search via free public APIs (no API key needed):
1. Wikipedia REST summary — has 'thumbnail' for many concepts.
2. Wikipedia MediaWiki API (pageimages) — sometimes higher-res.
3. Wikimedia Commons search — last resort.

Returns the saved file path on success, None otherwise.
"""
from __future__ import annotations

import logging
import mimetypes
from pathlib import Path
from typing import Optional
from urllib.parse import urlparse

import httpx

log = logging.getLogger(__name__)

USER_AGENT = (
    "WordCards/0.1 (https://github.com/PavelKaloshin/word_cards; local learning app) python-httpx"
)
TIMEOUT = 15.0


def _client() -> httpx.Client:
    return httpx.Client(timeout=TIMEOUT, headers={"User-Agent": USER_AGENT}, follow_redirects=True)


def _wiki_summary_image(query: str, lang: str) -> Optional[str]:
    if not query.strip():
        return None
    url = f"https://{lang}.wikipedia.org/api/rest_v1/page/summary/{query.strip().replace(' ', '_')}"
    try:
        with _client() as c:
            r = c.get(url)
            if r.status_code != 200:
                return None
            data = r.json()
            # Prefer originalimage over thumbnail
            for key in ("originalimage", "thumbnail"):
                img = data.get(key)
                if img and img.get("source"):
                    return img["source"]
    except Exception as e:
        log.debug("wiki summary failed for %s: %s", query, e)
    return None


def _wiki_pageimage(query: str, lang: str) -> Optional[str]:
    """Use the MediaWiki API to get the page main image."""
    url = f"https://{lang}.wikipedia.org/w/api.php"
    params = {
        "action": "query",
        "format": "json",
        "prop": "pageimages",
        "piprop": "original",
        "titles": query,
        "redirects": 1,
    }
    try:
        with _client() as c:
            r = c.get(url, params=params)
            if r.status_code != 200:
                return None
            pages = r.json().get("query", {}).get("pages", {})
            for page in pages.values():
                src = page.get("original", {}).get("source")
                if src:
                    return src
    except Exception as e:
        log.debug("wiki pageimage failed for %s: %s", query, e)
    return None


def _commons_search(query: str) -> Optional[str]:
    """Search Wikimedia Commons for a relevant image."""
    url = "https://commons.wikimedia.org/w/api.php"
    params = {
        "action": "query",
        "format": "json",
        "generator": "search",
        "gsrsearch": f'filetype:bitmap "{query}"',
        "gsrnamespace": 6,
        "gsrlimit": 1,
        "prop": "imageinfo",
        "iiprop": "url",
        "iiurlwidth": 800,
    }
    try:
        with _client() as c:
            r = c.get(url, params=params)
            if r.status_code != 200:
                return None
            pages = r.json().get("query", {}).get("pages", {})
            for page in pages.values():
                ii = page.get("imageinfo", [])
                if ii:
                    return ii[0].get("thumburl") or ii[0].get("url")
    except Exception as e:
        log.debug("commons search failed for %s: %s", query, e)
    return None


def _ddg_image_urls(query: str, max_results: int = 5) -> list[str]:
    """DuckDuckGo image search (no API key). Returns up to `max_results` URLs."""
    if not query.strip():
        return []
    try:
        from duckduckgo_search import DDGS
    except ImportError:
        log.warning("duckduckgo_search not installed")
        return []
    try:
        with DDGS() as ddgs:
            results = list(
                ddgs.images(
                    keywords=query,
                    safesearch="strict",
                    type_image="photo",
                    max_results=max_results,
                )
            )
        urls = []
        for r in results:
            u = r.get("image") or r.get("thumbnail")
            if u:
                urls.append(u)
        return urls
    except Exception as e:
        log.debug("ddg image search failed for %s: %s", query, e)
        return []


_VALID_EXTS = {".jpg", ".jpeg", ".png", ".gif", ".webp", ".svg"}


def _ext_for(url: str, content_type: str) -> str:
    """Derive a sensible image extension from URL path or Content-Type."""
    path = urlparse(url).path
    ext = Path(path).suffix.lower()
    if ext in _VALID_EXTS:
        return ".jpg" if ext == ".jpeg" else ext
    if content_type:
        guess = mimetypes.guess_extension(content_type.split(";")[0].strip())
        if guess and guess.lower() in _VALID_EXTS:
            return ".jpg" if guess.lower() == ".jpeg" else guess.lower()
    return ".jpg"


def _download(url: str, dest_stem: Path) -> Optional[Path]:
    """dest_stem is a path WITHOUT extension; we add the right one and return the final path."""
    try:
        with _client() as c:
            r = c.get(url)
            r.raise_for_status()
            ext = _ext_for(url, r.headers.get("Content-Type", ""))
            dest = dest_stem.with_suffix(ext)
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(r.content)
            return dest
    except Exception as e:
        log.warning("download failed %s: %s", url, e)
        return None


def iter_candidate_urls(word_serbian: str, translation: str, lang: str = "en") -> list[str]:
    """Return candidate image URLs in priority order, deduplicated."""
    queries: list[str] = []
    if translation:
        queries.append(translation)
    if word_serbian and word_serbian.strip() and word_serbian != translation:
        queries.append(word_serbian)

    urls: list[str] = []
    seen: set[str] = set()

    def push(u: Optional[str]) -> None:
        if u and u not in seen:
            seen.add(u)
            urls.append(u)

    # 1. DuckDuckGo photos
    for q in queries:
        for u in _ddg_image_urls(q, max_results=5):
            push(u)

    # 2. Wikipedia summary/pageimage
    for q in queries:
        l = lang if q == translation else "sr"
        push(_wiki_summary_image(q, l))
        push(_wiki_pageimage(q, l))

    # 3. Commons full-text
    if translation:
        push(_commons_search(translation))

    return urls


def download(url: str, dest_stem: Path) -> Optional[Path]:
    """Download image to dest_stem.<ext> (extension derived). Public alias."""
    return _download(url, dest_stem)


def search_and_save(word_serbian: str, translation: str, dest_stem: Path, lang: str = "en") -> Optional[Path]:
    """
    Convenience: try candidates in order, return first that downloads.
    No content evaluation. Used by /refind-image when caller skips eval.
    """
    for u in iter_candidate_urls(word_serbian, translation, lang):
        saved = _download(u, dest_stem)
        if saved:
            return saved
    return None
