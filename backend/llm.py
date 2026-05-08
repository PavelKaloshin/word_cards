"""
OpenAI wrappers: text generation (translation + example), vision OCR,
free-text extraction, and image generation fallback.
Web image lookup lives in images.py.
"""
from __future__ import annotations

import base64
import json
import logging
import os
from pathlib import Path
from typing import Optional

import httpx
from openai import OpenAI

logger = logging.getLogger(__name__)


def _client() -> OpenAI:
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        raise RuntimeError("OPENAI_API_KEY environment variable is not set")
    return OpenAI(api_key=api_key)


def generate_translation_and_example(word: str, cfg: dict) -> dict:
    """
    Returns: {translation: str, example_cyr: str, example_lat: str, example_translation: str}
    """
    prompt = f"""You are a Serbian language tutor. For the Serbian word "{word}", produce:
1. A concise English translation (1–4 words; multiple meanings comma-separated).
2. A short example sentence (5–10 words) using the word naturally, in Serbian Cyrillic.
3. The same sentence in Serbian Latin (gajica).
4. The English translation of the sentence.

Respond ONLY with strict JSON. No markdown. Schema:
{{"translation": "...", "example_cyr": "...", "example_lat": "...", "example_translation": "..."}}
"""
    client = _client()
    resp = client.chat.completions.create(
        model=cfg["openai_model_text"],
        messages=[{"role": "user", "content": prompt}],
        response_format={"type": "json_object"},
        temperature=0.7,
    )
    content = resp.choices[0].message.content or "{}"
    return json.loads(content)


def generate_new_example(word: str, prev_examples_cyr: list[str], cfg: dict) -> dict:
    """
    Generate a NEW example, different from the previous ones.
    Returns: {example_cyr, example_lat, example_translation}
    """
    avoid = ""
    if prev_examples_cyr:
        bullet_list = "\n".join(f"- {e}" for e in prev_examples_cyr[-5:])
        avoid = f"\n\nAvoid reusing these previous examples:\n{bullet_list}"
    prompt = f"""You are a Serbian language tutor. Produce a NEW short example sentence (5–10 words)
using the Serbian word "{word}" naturally. Different vocabulary and structure from before.{avoid}

Respond ONLY with strict JSON. Schema:
{{"example_cyr": "...", "example_lat": "...", "example_translation": "..."}}
"""
    client = _client()
    resp = client.chat.completions.create(
        model=cfg["openai_model_text"],
        messages=[{"role": "user", "content": prompt}],
        response_format={"type": "json_object"},
        temperature=0.9,
    )
    content = resp.choices[0].message.content or "{}"
    return json.loads(content)


def extract_phrases_from_text(text: str, cfg: dict) -> list[dict]:
    """
    Pulls Serbian words/phrases out of a free-form text (e.g. chat copy-paste).
    Discards timestamps, sender names, autoreplies, emojis, English commentary, etc.
    Returns: [{word, translation?}, ...]  (translation only if visible in source).
    """
    if not text.strip():
        return []
    prompt = f"""You are processing text the user copied from a chat to extract Serbian
vocabulary they want to learn. The source text contains noise: sender names,
timestamps in parentheses, emoji/object replacement chars, blank lines, English
commentary, etc. Ignore the noise. Keep only Serbian words and phrases.

Rules:
- Preserve the user's original Serbian script (Cyrillic or Latin/gajica).
- Each entry is one word or one short phrase, exactly as the user wrote it.
- Never translate — only include "translation" if the SOURCE text shows one
  (e.g. "kuća — house" or "kuća | house" lines).
- Don't deduplicate; keep order. The server dedupes later.
- Skip entries that are obviously not Serbian (English-only, numbers, names).
- Keep punctuation that's part of the phrase (e.g. "Kako si?").

Source text:
---
{text}
---

Respond ONLY with strict JSON:
{{"entries": [{{"word": "...", "translation": "..."}}, ...]}}
"""
    client = _client()
    resp = client.chat.completions.create(
        model=cfg["openai_model_text"],
        messages=[{"role": "user", "content": prompt}],
        response_format={"type": "json_object"},
        temperature=0.0,
    )
    content = resp.choices[0].message.content or '{"entries":[]}'
    try:
        return json.loads(content).get("entries", [])
    except json.JSONDecodeError:
        logger.warning("text extraction returned invalid json: %s", content[:200])
        return []


def generate_image(word: str, translation: str, dest_stem: Path, cfg: dict) -> Optional[Path]:
    """
    Last-resort image: ask the OpenAI image model to generate something.
    Saves to dest_stem.<ext>. Returns final path or None on failure.
    """
    model = cfg.get("openai_model_image") or "dall-e-3"
    size = cfg.get("image_size") or "1024x1024"
    visible = translation or word
    prompt = (
        f"A flashcard-style illustration depicting the meaning of '{visible}'. "
        f"Centered subject, simple uncluttered background, soft watercolor or flat illustration. "
        f"CRITICAL: The image MUST NOT contain ANY text, letters, numbers, captions, labels, "
        f"signs, watermarks, logos, alphabet characters, Cyrillic characters, or any written "
        f"symbols whatsoever. This is a vocabulary flashcard — text in the image would reveal the "
        f"answer. Pure visual depiction only."
    )
    try:
        client = _client()
        result = client.images.generate(model=model, prompt=prompt, size=size, n=1)
        item = result.data[0]
        dest = dest_stem.with_suffix(".png")
        dest.parent.mkdir(parents=True, exist_ok=True)
        if getattr(item, "b64_json", None):
            dest.write_bytes(base64.b64decode(item.b64_json))
            return dest
        if getattr(item, "url", None):
            with httpx.Client(timeout=60) as http:
                r = http.get(item.url)
                r.raise_for_status()
                dest.write_bytes(r.content)
                return dest
        return None
    except Exception as e:
        logger.warning("image generation failed for %r: %s", visible, e)
        return None


def evaluate_image(image_path: Path, word: str, translation: str, cfg: dict) -> dict:
    """
    Vision check: is this image suitable as a flashcard for `word` (meaning `translation`)?
    Reject if it contains text/letters/numbers (would reveal the answer), is irrelevant,
    or is inappropriate. Returns {"ok": bool, "reason": str}.
    """
    if not image_path.exists():
        return {"ok": False, "reason": "file missing"}
    try:
        b64 = base64.b64encode(image_path.read_bytes()).decode("ascii")
    except Exception as e:
        return {"ok": False, "reason": f"read error: {e}"}

    ext = image_path.suffix.lstrip(".").lower() or "png"
    mime = {"jpg": "jpeg"}.get(ext, ext)
    target = translation or word
    prompt = f"""You are validating an image for a Serbian-language vocabulary flashcard.
The card teaches the meaning "{target}" (Serbian: "{word}").

REJECT the image if ANY of these are true:
1. The image contains visible TEXT, letters, numbers, captions, labels, signs, or
   watermarks — these would reveal the answer to the learner.
2. The image does not visually depict the meaning "{target}".
3. The image is NSFW, gory, or otherwise inappropriate for a learning app.
4. The image is a screenshot of a webpage, dictionary entry, or text document.

Otherwise ACCEPT.

Respond ONLY with strict JSON:
{{"ok": true|false, "reason": "<brief reason if rejected, empty string if accepted>"}}
"""
    try:
        client = _client()
        resp = client.chat.completions.create(
            model=cfg["openai_model_vision"],
            messages=[
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": prompt},
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": f"data:image/{mime};base64,{b64}",
                                "detail": "low",
                            },
                        },
                    ],
                }
            ],
            response_format={"type": "json_object"},
            temperature=0.0,
        )
        content = resp.choices[0].message.content or '{"ok": false, "reason": "no response"}'
        return json.loads(content)
    except Exception as e:
        logger.warning("image evaluation failed for %s: %s", word, e)
        # Be lenient on failure: don't block the word from getting an image
        return {"ok": True, "reason": "eval failed, accepting"}


def extract_words_from_image(image_bytes: bytes, cfg: dict) -> list[dict]:
    """
    Use vision to extract Serbian words (and translations if present) from a screenshot.
    Returns a list of {word, translation?} dicts.
    """
    b64 = base64.b64encode(image_bytes).decode("ascii")
    prompt = """This image contains a list of Serbian vocabulary, possibly with English (or other) translations.
Extract every Serbian word/phrase and its translation if present.

Respond ONLY with strict JSON. Schema:
{"entries": [{"word": "...", "translation": "..."}, ...]}

If a translation is missing, omit the field. Keep the original Serbian script (Cyrillic or Latin) as-is.
Do not invent words that aren't visible. Do not deduplicate.
"""
    client = _client()
    resp = client.chat.completions.create(
        model=cfg["openai_model_vision"],
        messages=[
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": prompt},
                    {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{b64}"}},
                ],
            }
        ],
        response_format={"type": "json_object"},
        temperature=0.1,
    )
    content = resp.choices[0].message.content or '{"entries":[]}'
    try:
        data = json.loads(content)
        return data.get("entries", [])
    except json.JSONDecodeError:
        logger.warning("vision returned invalid json: %s", content[:200])
        return []


