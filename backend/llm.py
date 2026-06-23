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
    Returns: {translation, example_cyr, example_lat, example_translation, pos, verb_group}
    """
    prompt = f"""You are a Serbian language tutor. For the Serbian word/phrase "{word}", produce:
1. A concise English translation (1–4 words; multiple meanings comma-separated).
2. A short example sentence (5–10 words) using the word naturally, in Serbian Cyrillic.
3. The same sentence in Serbian Latin (gajica).
4. The English translation of the sentence.
5. Part of speech: one of [verb, noun, adjective, adverb, pronoun, numeral, preposition, conjunction, interjection, phrase, other].
6. If part of speech is "verb", classify the conjugation group based on the 1st-person singular present:
   - "I"   for -am verbs (a-type, e.g. gledati → gledam)
   - "II"  for -im verbs (i-type, e.g. raditi → radim)
   - "III" for -em verbs (e-type, e.g. piti → pijem)
   - "irregular" for fundamentally irregular verbs (e.g. biti, hteti, jesti)
   Otherwise leave empty.

Respond ONLY with strict JSON. No markdown. Schema:
{{"translation": "...", "example_cyr": "...", "example_lat": "...", "example_translation": "...", "pos": "...", "verb_group": "..."}}
"""
    client = _client()
    resp = client.chat.completions.create(
        model=cfg["openai_model_text"],
        messages=[{"role": "user", "content": prompt}],
        response_format={"type": "json_object"},
        temperature=0.7,
    )
    content = resp.choices[0].message.content or "{}"
    data = json.loads(content)
    if "verb_group" in data:
        data["verb_group"] = _normalize_verb_group(str(data.get("verb_group", "")))
    if "pos" in data:
        data["pos"] = str(data.get("pos", "")).strip().lower()
    return data


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
    Pulls Serbian vocabulary out of free-form text. Handles MIXED input:
    keeps existing Serbian content as-is and TRANSLATES Russian/English items
    into Serbian. Discards noise (timestamps, sender names, ￼ chars, etc.).
    Returns: [{word: "<Serbian>", translation: "<source if RU/EN, else empty>"}, ...]
    """
    if not text.strip():
        return []
    model = cfg.get("openai_model_extract") or cfg.get("openai_model_text")
    prompt = f"""You are extracting INDIVIDUAL Serbian VOCABULARY WORDS (lemmas / dictionary
forms) from a mixed-language paste (Serbian + Russian + English + chat noise).
The user wants WORDS to memorize, NOT phrases or sentences.

For EVERY content word in the source, output ONE entry in dictionary form:
- nouns:      nominative singular (e.g. "grad", "kuća", "student")
- verbs:      infinitive ending in -ti or -ći (e.g. "čitati", "živeti", "ići")
- adjectives: masculine nominative singular (e.g. "lep", "dobar")
- adverbs:    as-is (e.g. "uvek", "danas")

Entry schema:
- "word": Serbian lemma (translated if source was Russian/English; lemmatized if it was a conjugated/declined form)
- "translation": corresponding Russian (or English) lemma. Empty string if input was already Serbian without translation.

Strict rules:
1. From every Russian/English sentence: translate, then split into Serbian lemmas.
2. From every Serbian sentence: split into Serbian lemmas.
3. Strip "1.", "2." numbering from list lines.
4. Keep order; don't deduplicate.
5. Serbian Latin (gajica) for translated content by default.

SKIP these:
- Stop-words: ja, ti, on, ona, ono, mi, vi, oni, one, sebi, sebe, svoj, ovo, ono, taj, ova, te, ti
- Prepositions: u, na, sa, s, o, do, od, iz, za, po, pri, pre, posle, pred, kroz, kod, među, nad, pod
- Conjunctions: i, a, ali, ili, jer, da, što, kako, ako, dok, kada, kad
- Particles/clitics: se, li, ne, će, sam (auxiliary), je (auxiliary)
- Numerals written as digits
- Noise: sender names with timestamps, ￼, blank lines, page numbers

Idiomatic multi-word phrases that work as a unit MAY be kept whole only if
they're genuinely idiomatic and not decomposable (e.g. "žao mi je", "kako si",
"boli me ruka"). Default to individual lemmas.

Few-shot example:

Source:
```
1. Студент читает.
2. Я живу в городе.
3. Žao mi je.
Stranac
```

Correct output:
```
{{"entries": [
  {{"word": "student", "translation": "студент"}},
  {{"word": "čitati", "translation": "читать"}},
  {{"word": "živeti", "translation": "жить"}},
  {{"word": "grad", "translation": "город"}},
  {{"word": "žao mi je", "translation": ""}},
  {{"word": "stranac", "translation": ""}}
]}}
```

Source text:
---
{text}
---

Respond ONLY with strict JSON:
{{"entries": [{{"word": "<Serbian lemma>", "translation": "<Russian/English lemma or empty>"}}, ...]}}
"""
    client = _client()
    resp = client.chat.completions.create(
        model=model,
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
    model = cfg.get("openai_model_image") or "gpt-image-1"
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


_VERB_GROUP_NORMALIZE = {
    "i": "I", "1": "I", "1st": "I", "first": "I", "one": "I", "a": "I",
    "ii": "II", "2": "II", "2nd": "II", "second": "II", "two": "II",
    "iii": "III", "3": "III", "3rd": "III", "third": "III", "three": "III", "e": "III",
}


def _normalize_verb_group(g: str) -> str:
    g = (g or "").strip().lower()
    if not g:
        return ""
    if g in _VERB_GROUP_NORMALIZE:
        return _VERB_GROUP_NORMALIZE[g]
    if "irreg" in g:
        return "irregular"
    # GPT sometimes returns a 1sg present form (e.g. "volim") instead of a label;
    # infer the group from the ending.
    no_diacritic = (
        g.replace("š", "s").replace("č", "c").replace("ć", "c")
         .replace("ž", "z").replace("đ", "dj")
    )
    if no_diacritic.endswith("am"):
        return "I"
    if no_diacritic.endswith("im"):
        return "II"
    if no_diacritic.endswith("em") or no_diacritic.endswith("jem"):
        return "III"
    return g  # unknown, return as-is


_IRREGULAR_PRESENT_FORMS = {
    "sam", "jesam", "ću", "hoću", "mogu", "jedem",  # biti, hteti, moći, jesti
}


def _derive_group_from_present(present: str) -> str:
    """Map a 1sg present form to a conjugation group."""
    p = (present or "").strip().lower()
    if not p:
        return ""
    if p in _IRREGULAR_PRESENT_FORMS:
        return "irregular"
    # Strip diacritics so endings comparison is robust
    p2 = (
        p.replace("š", "s").replace("č", "c").replace("ć", "c")
         .replace("ž", "z").replace("đ", "dj")
    )
    if p2.endswith("am"):
        return "I"
    if p2.endswith("im"):
        return "II"
    if p2.endswith("em") or p2.endswith("jem"):
        return "III"
    return ""


def classify_words(entries: list[dict], cfg: dict) -> list[dict]:
    """
    Batch classification. `entries` is a list of {"word_lat", "translation"}.
    Returns list of {pos, verb_group} in same order. Empty list on failure.

    Strategy: ask GPT for the 1sg present form (which it knows reliably),
    then derive the conjugation group deterministically from the ending.
    """
    if not entries:
        return []
    items = "\n".join(
        f"{i + 1}. {e.get('word_lat', '')}"
        + (f" — {e.get('translation')}" if e.get("translation") else "")
        for i, e in enumerate(entries)
    )
    prompt = f"""You are a Serbian grammar helper. For each item below, identify:
- pos: one of [verb, noun, adjective, adverb, pronoun, numeral, preposition, conjunction, interjection, phrase, other]
- present_1sg: ONLY if pos=="verb", the 1st-person singular present tense form.
  Examples:
    čitati → "čitam", raditi → "radim", piti → "pijem", pisati → "pišem",
    znati → "znam", voleti → "volim", učiti → "učim", pušiti → "pušim",
    putovati → "putujem", biti → "jesam", hteti → "hoću", moći → "mogu",
    jesti → "jedem", ići → "idem".
  For multi-word phrases (e.g. "Žao mi je", "Boli me ruka", "Kako se zoveš?"),
  return the 1sg present of the main verb (biti → "sam"; boleti → "bolim";
  zvati se → "zovem se").
  For non-verbs, return empty string "".

Items:
{items}

Respond ONLY with strict JSON (same order):
{{"items": [{{"pos": "...", "present_1sg": "..."}}, ...]}}
"""
    client = _client()
    resp = client.chat.completions.create(
        model=cfg["openai_model_text"],
        messages=[{"role": "user", "content": prompt}],
        response_format={"type": "json_object"},
        temperature=0.0,
    )
    content = resp.choices[0].message.content or '{"items":[]}'
    try:
        data = json.loads(content)
        items_out = data.get("items", [])
        result: list[dict] = []
        for i in range(len(entries)):
            if i < len(items_out) and isinstance(items_out[i], dict):
                pos = str(items_out[i].get("pos", "")).strip().lower()
                present = str(items_out[i].get("present_1sg", "")).strip()
                vg = _derive_group_from_present(present) if pos == "verb" else ""
                result.append({"pos": pos, "verb_group": vg})
            else:
                result.append({"pos": "", "verb_group": ""})
        return result
    except json.JSONDecodeError:
        logger.warning("classify_words returned invalid json: %s", content[:200])
        return [{"pos": "", "verb_group": ""} for _ in entries]


def generate_conjugations(word_lat: str, translation: str, cfg: dict) -> Optional[dict]:
    """
    For a Serbian verb, return present-tense conjugation table with both
    Cyrillic and Latin spellings:
    {
      "1sg": {"cyr": "идем",  "lat": "idem"},
      "2sg": {"cyr": "идеш",  "lat": "ideš"},
      "3sg": {"cyr": "иде",   "lat": "ide"},
      "1pl": {"cyr": "идемо", "lat": "idemo"},
      "2pl": {"cyr": "идете", "lat": "idete"},
      "3pl": {"cyr": "иду",   "lat": "idu"}
    }
    Returns None if the model declines or response is malformed.
    """
    if not word_lat.strip():
        return None
    prompt = f"""For the Serbian verb "{word_lat}" (meaning: "{translation or "?"}"), produce
the PRESENT TENSE conjugation table. Return BOTH Cyrillic and Latin (gajica)
spellings for every form, lowercase, no extra punctuation.

Persons:
- 1sg: ja (I)
- 2sg: ti (you, singular)
- 3sg: on/ona/ono (he/she/it)
- 1pl: mi (we)
- 2pl: vi (you, plural)
- 3pl: oni/one/ona (they)

For a multi-word phrase containing a verb, conjugate the main verb (keep
auxiliary clitics/pronouns in their place, e.g. "Žao mi je" → 1sg "žao mi je",
2sg "žao ti je", etc.).

Respond ONLY with strict JSON:
{{"1sg": {{"cyr": "...", "lat": "..."}},
  "2sg": {{"cyr": "...", "lat": "..."}},
  "3sg": {{"cyr": "...", "lat": "..."}},
  "1pl": {{"cyr": "...", "lat": "..."}},
  "2pl": {{"cyr": "...", "lat": "..."}},
  "3pl": {{"cyr": "...", "lat": "..."}}}}
"""
    try:
        client = _client()
        resp = client.chat.completions.create(
            model=cfg["openai_model_text"],
            messages=[{"role": "user", "content": prompt}],
            response_format={"type": "json_object"},
            temperature=0.0,
        )
        content = resp.choices[0].message.content or "{}"
        data = json.loads(content)
        # sanity-check: ensure all 6 keys present
        keys = ("1sg", "2sg", "3sg", "1pl", "2pl", "3pl")
        out: dict = {}
        for k in keys:
            entry = data.get(k) or {}
            cyr = str(entry.get("cyr", "")).strip()
            lat = str(entry.get("lat", "")).strip()
            if not cyr and not lat:
                return None  # incomplete table
            out[k] = {"cyr": cyr, "lat": lat}
        return out
    except Exception as e:
        logger.warning("conjugations failed for %r: %s", word_lat, e)
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


