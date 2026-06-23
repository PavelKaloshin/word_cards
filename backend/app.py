"""
FastAPI app: routes for words, sessions, settings, media.
"""
from __future__ import annotations

import hashlib
import logging
import threading
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
from rapidfuzz.distance import Levenshtein

from . import config as cfg_mod
from . import images, llm, normalize, scoring, session as sess_mod, tts
from .models import (
    AddWordsRequest,
    AnswerRequest,
    ParseTextRequest,
    StartSessionRequest,
    TypingCheckRequest,
    WordEntry,
    WordPatch,
)
from .storage import SessionsDB, WordsDB

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log = logging.getLogger("serbian-cards")

ROOT = cfg_mod.ROOT

app = FastAPI(title="Serbian Cards")


@app.middleware("http")
async def no_cache_middleware(request, call_next):
    response = await call_next(request)
    if request.url.path.startswith("/static") or request.url.path == "/":
        response.headers["Cache-Control"] = "no-store"
    return response

words_db = WordsDB(cfg_mod.WORDS_PATH)
sessions_db = SessionsDB(cfg_mod.SESSIONS_PATH)
session_store = sess_mod.SessionStore(cfg_mod.DATA_DIR / "active_sessions.json")
active_sessions: dict[str, sess_mod.Session] = session_store.all()


def get_cfg() -> dict:
    return cfg_mod.load()


# ---------- Words ----------

def _word_skeleton(serbian: str, translation: Optional[str], note: Optional[str]) -> dict:
    cyr, lat = normalize.to_both(serbian)
    return {
        "id": str(uuid.uuid4()),
        "word_cyr": cyr,
        "word_lat": lat,
        "translation": translation or "",
        "example_cyr": "",
        "example_lat": "",
        "example_translation": "",
        "image_path": "",
        "image_hash_history": [],
        "audio_path": "",
        "note": note or "",
        "pos": "",
        "verb_group": "",
        "conjugations": None,
        "created_at": scoring.now_iso(),
        "last_seen_at": None,
        "last_correct_at": None,
        "streak": 0,
        "total_good": 0,
        "total_again": 0,
        "total_hard": 0,
        "forget_count": 0,
        "history": [],
    }


def _media_url(path_str: str) -> str:
    if not path_str:
        return ""
    p = Path(path_str)
    try:
        rel = p.relative_to(cfg_mod.MEDIA_DIR)
    except ValueError:
        rel = Path(p.name)
    return f"/media/{rel.as_posix()}"


def _to_api(word: dict) -> dict:
    return {
        **word,
        "image_url": _media_url(word.get("image_path", "")),
        "audio_url": _media_url(word.get("audio_path", "")),
    }


MAX_IMAGE_HISTORY = 5


def _hash_file(path: Path) -> str:
    h = hashlib.md5()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def _find_acceptable_image(
    word_lat: str,
    translation: str,
    stem: Path,
    cfg: dict,
    skip_hashes: Optional[set[str]] = None,
) -> tuple[Optional[Path], Optional[str]]:
    """
    Iterate candidate URLs, download each, hash-check against `skip_hashes`,
    then evaluate with vision. Return (first accepted path, its md5) or (None, None).
    """
    skip_hashes = skip_hashes or set()
    try:
        urls = images.iter_candidate_urls(word_lat, translation, lang=cfg.get("image_search_lang", "en"))
    except Exception as e:
        log.warning("candidate URL discovery failed for %s: %s", word_lat, e)
        return None, None
    eval_enabled = cfg.get("image_eval_enabled", True)
    # When we have a skip list, look further so we don't run out before a fresh image.
    max_to_check = cfg.get("image_eval_max_candidates", 4) + len(skip_hashes) * 2
    for url in urls[:max_to_check]:
        saved = images.download(url, stem)
        if not saved:
            continue
        try:
            digest = _hash_file(saved)
        except Exception as e:
            log.debug("hash failed for %s: %s", saved, e)
            digest = None
        if digest and digest in skip_hashes:
            log.info("skip duplicate-hash image for %r", word_lat)
            saved.unlink(missing_ok=True)
            continue
        if not eval_enabled:
            return saved, digest
        try:
            verdict = llm.evaluate_image(saved, word_lat, translation, cfg)
        except Exception as e:
            log.warning("eval errored, accepting %s: %s", saved, e)
            return saved, digest
        if verdict.get("ok"):
            return saved, digest
        log.info("rejected image for %r: %s", word_lat, verdict.get("reason"))
        saved.unlink(missing_ok=True)
    return None, None


def _remember_image_hash(word: dict, digest: Optional[str]) -> None:
    if not digest:
        return
    history = word.setdefault("image_hash_history", [])
    if digest in history:
        history.remove(digest)
    history.append(digest)
    if len(history) > MAX_IMAGE_HISTORY:
        del history[: len(history) - MAX_IMAGE_HISTORY]


def _enrich_word(word: dict, cfg: dict) -> None:
    """Generate translation/example/image/audio. Mutates in place."""
    serbian_for_prompts = word["word_cyr"]
    needs_translation = not word.get("translation")
    needs_example = not word.get("example_cyr")
    needs_pos = not word.get("pos")
    if needs_translation or needs_example or needs_pos:
        try:
            data = llm.generate_translation_and_example(serbian_for_prompts, cfg)
            if needs_translation:
                word["translation"] = data.get("translation", "")
            word["example_cyr"] = data.get("example_cyr", word.get("example_cyr", ""))
            word["example_lat"] = data.get("example_lat", word.get("example_lat", ""))
            word["example_translation"] = data.get("example_translation", word.get("example_translation", ""))
            if needs_pos:
                word["pos"] = data.get("pos", "")
                word["verb_group"] = data.get("verb_group", "")
        except Exception as e:
            log.warning("text-gen failed for %s: %s", serbian_for_prompts, e)

    # Conjugations for verbs
    if word.get("pos") == "verb" and not word.get("conjugations"):
        try:
            conj = llm.generate_conjugations(word["word_lat"], word.get("translation", ""), cfg)
            if conj:
                word["conjugations"] = conj
        except Exception as e:
            log.warning("conjugations failed for %s: %s", serbian_for_prompts, e)

    if not word.get("image_path"):
        stem = cfg_mod.IMAGES_DIR / word["id"]
        translation = word.get("translation", "")
        skip = set(word.get("image_hash_history") or [])
        saved, digest = _find_acceptable_image(word["word_lat"], translation, stem, cfg, skip)
        if not saved and cfg.get("image_use_llm_fallback"):
            try:
                saved = llm.generate_image(word["word_lat"], translation, stem, cfg)
                if saved:
                    digest = _hash_file(saved)
            except Exception as e:
                log.warning("image generation fallback failed for %s: %s", serbian_for_prompts, e)
        if saved:
            word["image_path"] = str(saved)
            _remember_image_hash(word, digest)
        else:
            log.info("no image found for %s", serbian_for_prompts)

    audio_path = cfg_mod.AUDIO_DIR / f"{word['id']}.mp3"
    if not audio_path.exists():
        try:
            tts.synthesize(word["word_cyr"], cfg["tts_voice"], audio_path)
            word["audio_path"] = str(audio_path)
        except Exception as e:
            log.warning("tts failed for %s: %s", word["word_cyr"], e)


@app.get("/api/words")
def list_words():
    return {"words": [_to_api(w) for w in words_db.all()]}


def _normalized_key(serbian: str) -> str:
    return normalize.normalize_for_match(serbian, relaxed_diacritics=True)


_add_lock = threading.Lock()


@app.post("/api/words/add-one")
def add_one_word(entry: WordEntry):
    """
    Add + enrich a single word. Concurrency-safe: dedup check + skeleton creation
    happen under a global lock; the heavy enrichment (LLM/image/TTS) runs outside it
    so multiple words can be processed in parallel.
    """
    cfg = get_cfg()
    if not entry.word or not entry.word.strip():
        raise HTTPException(400, "empty word")
    with _add_lock:
        key = _normalized_key(entry.word)
        for w in words_db.all():
            if _normalized_key(w["word_lat"]) == key:
                return {"status": "duplicate", "word": _to_api(w)}
        skel = _word_skeleton(entry.word, entry.translation, entry.note)
        words_db.add(skel)
    _enrich_word(skel, cfg)
    words_db.update(skel["id"], skel)
    return {"status": "added", "word": _to_api(skel)}


@app.post("/api/words/add")
def add_words(req: AddWordsRequest):
    cfg = get_cfg()
    existing_keys = {_normalized_key(w["word_lat"]) for w in words_db.all()}
    added: list[dict] = []
    skipped: list[dict] = []
    seen_in_batch: set[str] = set()
    for entry in req.entries:
        if not entry.word or not entry.word.strip():
            continue
        key = _normalized_key(entry.word)
        if key in existing_keys or key in seen_in_batch:
            skipped.append({"word": entry.word, "reason": "duplicate"})
            continue
        seen_in_batch.add(key)
        skel = _word_skeleton(entry.word, entry.translation, entry.note)
        words_db.add(skel)  # save shell first so partial enrichment isn't lost
        _enrich_word(skel, cfg)
        words_db.update(skel["id"], skel)
        added.append(_to_api(skel))
    return {"added": added, "skipped": skipped}


@app.post("/api/words/{word_id}/classify")
def classify_one_word(word_id: str):
    """Re-classify a single word's pos / verb_group. If newly classified as verb,
    also generate the conjugation table."""
    cfg = get_cfg()
    w = words_db.get(word_id)
    if not w:
        raise HTTPException(404, "word not found")
    entries = [{"word_lat": w.get("word_lat", ""), "translation": w.get("translation", "")}]
    try:
        results = llm.classify_words(entries, cfg)
    except Exception as e:
        raise HTTPException(500, f"classification failed: {e}")
    if not results:
        raise HTTPException(500, "empty classification result")
    r = results[0]
    was_verb = w.get("pos") == "verb"
    w["pos"] = r.get("pos", "")
    w["verb_group"] = r.get("verb_group", "")
    if w["pos"] == "verb":
        # Generate conjugations if newly verb or missing
        if not was_verb or not w.get("conjugations"):
            try:
                conj = llm.generate_conjugations(w.get("word_lat", ""), w.get("translation", ""), cfg)
                if conj:
                    w["conjugations"] = conj
            except Exception as e:
                log.warning("conjugation regen failed: %s", e)
    else:
        w["conjugations"] = None
    words_db.update(word_id, w)
    return _to_api(w)


@app.post("/api/words/{word_id}/mark-non-verb")
def mark_non_verb(word_id: str):
    """User explicitly marks a misclassified verb as non-verb."""
    w = words_db.get(word_id)
    if not w:
        raise HTTPException(404, "word not found")
    # Use "other" so a future classify pass doesn't override; user-set wins.
    w["pos"] = "other"
    w["verb_group"] = ""
    w["conjugations"] = None  # stale if it was previously a verb
    words_db.update(word_id, w)
    return _to_api(w)


@app.get("/api/words/unclassified")
def list_unclassified():
    """IDs of words missing `pos`. Frontend can drive a per-word loop with progress."""
    ids = [w["id"] for w in words_db.all() if not w.get("pos")]
    return {"ids": ids, "count": len(ids)}


@app.get("/api/tts")
def tts_for_text(text: str = ""):
    """On-demand TTS for arbitrary Serbian text. Caches by md5(voice+text)."""
    text = (text or "").strip()
    if not text:
        raise HTTPException(400, "empty text")
    cfg = get_cfg()
    voice = cfg.get("tts_voice", "sr-RS-NicholasNeural")
    key = hashlib.md5(f"{voice}::{text}".encode("utf-8")).hexdigest()
    cache_dir = cfg_mod.MEDIA_DIR / "tts_cache"
    cache_dir.mkdir(parents=True, exist_ok=True)
    cache_file = cache_dir / f"{key}.mp3"
    if not cache_file.exists():
        try:
            tts.synthesize(text, voice, cache_file)
        except Exception as e:
            log.warning("on-demand TTS failed for %r: %s", text, e)
            raise HTTPException(500, f"TTS failed: {e}")
    return FileResponse(str(cache_file), media_type="audio/mpeg", headers={"Cache-Control": "public, max-age=86400"})


@app.get("/api/words/missing-conjugations")
def list_missing_conjugations():
    """IDs of verbs lacking conjugation tables."""
    ids = [
        w["id"]
        for w in words_db.all()
        if w.get("pos") == "verb" and not w.get("conjugations")
    ]
    return {"ids": ids, "count": len(ids)}


@app.post("/api/words/{word_id}/conjugate")
def conjugate_one(word_id: str):
    """Generate / regenerate the present-tense conjugation table for one verb."""
    cfg = get_cfg()
    w = words_db.get(word_id)
    if not w:
        raise HTTPException(404, "word not found")
    try:
        conj = llm.generate_conjugations(w.get("word_lat", ""), w.get("translation", ""), cfg)
    except Exception as e:
        raise HTTPException(500, f"conjugation failed: {e}")
    if not conj:
        raise HTTPException(500, "empty conjugation result")
    w["conjugations"] = conj
    words_db.update(word_id, w)
    return _to_api(w)


@app.post("/api/words/classify-missing")
def classify_missing(force: bool = False):
    """
    Backfill `pos` and `verb_group`. With force=true, re-classifies ALL words
    (useful after prompt improvements). Otherwise only words missing `pos`.
    Batches in chunks of 30.
    """
    cfg = get_cfg()
    targets = words_db.all() if force else [w for w in words_db.all() if not w.get("pos")]
    if not targets:
        return {"classified": 0, "remaining": 0, "total": 0}
    CHUNK = 30
    classified = 0
    for i in range(0, len(targets), CHUNK):
        chunk = targets[i : i + CHUNK]
        entries = [
            {"word_lat": w.get("word_lat", ""), "translation": w.get("translation", "")}
            for w in chunk
        ]
        try:
            results = llm.classify_words(entries, cfg)
        except Exception as e:
            log.warning("classify batch failed: %s", e)
            continue
        for w, r in zip(chunk, results):
            if not isinstance(r, dict):
                continue
            pos = r.get("pos", "")
            verb_group = r.get("verb_group", "")
            if not pos:
                continue
            w["pos"] = pos
            w["verb_group"] = verb_group
            words_db.update(w["id"], w)
            classified += 1
    remaining = sum(1 for w in words_db.all() if not w.get("pos"))
    return {"classified": classified, "remaining": remaining, "total": len(targets)}


@app.post("/api/words/parse-text")
def parse_text(req: ParseTextRequest):
    cfg = get_cfg()
    try:
        entries = llm.extract_phrases_from_text(req.text, cfg)
    except Exception as e:
        log.exception("text extraction failed")
        raise HTTPException(status_code=500, detail=f"extraction failed: {e}")
    # Tag duplicates so the UI can preselect / mark them, but still return all.
    existing_keys = {_normalized_key(w["word_lat"]) for w in words_db.all()}
    out = []
    seen: set[str] = set()
    for e in entries:
        word = (e.get("word") or "").strip()
        if not word:
            continue
        key = _normalized_key(word)
        is_duplicate = key in existing_keys or key in seen
        seen.add(key)
        out.append({
            "word": word,
            "translation": (e.get("translation") or "").strip() or None,
            "duplicate": is_duplicate,
        })
    return {"entries": out}


@app.post("/api/words/from-screenshot")
async def from_screenshot(image: UploadFile = File(...)):
    cfg = get_cfg()
    raw = await image.read()
    try:
        entries = llm.extract_words_from_image(raw, cfg)
    except Exception as e:
        log.exception("vision OCR failed")
        raise HTTPException(status_code=500, detail=f"OCR failed: {e}")
    existing_keys = {_normalized_key(w["word_lat"]) for w in words_db.all()}
    seen: set[str] = set()
    out = []
    for e in entries:
        word = (e.get("word") or "").strip()
        if not word:
            continue
        key = _normalized_key(word)
        out.append({
            "word": word,
            "translation": (e.get("translation") or "").strip() or None,
            "duplicate": key in existing_keys or key in seen,
        })
        seen.add(key)
    return {"entries": out}


@app.patch("/api/words/{word_id}")
def patch_word(word_id: str, patch: WordPatch):
    update_dict = patch.model_dump(exclude_unset=True)
    w = words_db.update(word_id, update_dict)
    if not w:
        raise HTTPException(404, "word not found")
    return _to_api(w)


@app.delete("/api/words/{word_id}")
def delete_word(word_id: str):
    w = words_db.get(word_id)
    if not w:
        raise HTTPException(404, "word not found")
    for key in ("image_path", "audio_path"):
        p = w.get(key)
        if p:
            try:
                Path(p).unlink(missing_ok=True)
            except Exception:
                pass
    words_db.delete(word_id)
    # Scrub from active sessions so progress bars / queues stay consistent
    changed = False
    for sess in active_sessions.values():
        if word_id in sess.queue:
            sess.queue = [x for x in sess.queue if x != word_id]
            changed = True
        if word_id in sess.learn_word_ids:
            sess.learn_word_ids = [x for x in sess.learn_word_ids if x != word_id]
            sess.learn_initial_total = len(sess.learn_word_ids)
            changed = True
        if word_id in sess.learn_correct_count:
            sess.learn_correct_count.pop(word_id, None)
            changed = True
        if word_id in sess.new_mastered_ids:
            sess.new_mastered_ids.discard(word_id)
            changed = True
    if changed:
        for sess in active_sessions.values():
            session_store.put(sess)
    return {"ok": True}


@app.post("/api/words/{word_id}/regenerate-example")
def regenerate_example(word_id: str):
    cfg = get_cfg()
    w = words_db.get(word_id)
    if not w:
        raise HTTPException(404, "word not found")
    prev = [w.get("example_cyr")] if w.get("example_cyr") else []
    try:
        data = llm.generate_new_example(w["word_cyr"], prev, cfg)
    except Exception as e:
        raise HTTPException(500, f"generation failed: {e}")
    w["example_cyr"] = data.get("example_cyr", "")
    w["example_lat"] = data.get("example_lat", "")
    w["example_translation"] = data.get("example_translation", "")
    words_db.update(word_id, w)
    return _to_api(w)


@app.post("/api/words/{word_id}/refind-image")
def refind_image(word_id: str):
    cfg = get_cfg()
    w = words_db.get(word_id)
    if not w:
        raise HTTPException(404, "word not found")
    # Build skip set from history. Also include current image's hash if we have it.
    skip: set[str] = set(w.get("image_hash_history") or [])
    old = w.get("image_path")
    if old:
        try:
            current_hash = _hash_file(Path(old))
            skip.add(current_hash)
        except Exception:
            pass
        try:
            Path(old).unlink(missing_ok=True)
        except Exception:
            pass
        w["image_path"] = ""
    stem = cfg_mod.IMAGES_DIR / w["id"]
    translation = w.get("translation", "")
    saved, digest = _find_acceptable_image(w["word_lat"], translation, stem, cfg, skip)
    if not saved and cfg.get("image_use_llm_fallback"):
        try:
            saved = llm.generate_image(w["word_lat"], translation, stem, cfg)
            if saved:
                digest = _hash_file(saved)
        except Exception as e:
            log.warning("image gen fallback failed: %s", e)
    if not saved:
        words_db.update(word_id, w)
        raise HTTPException(404, "no fresh image found")
    w["image_path"] = str(saved)
    _remember_image_hash(w, digest)
    words_db.update(word_id, w)
    return _to_api(w)


# ---------- Stats ----------

@app.get("/api/stats")
def stats():
    cfg = get_cfg()
    now = datetime.now(timezone.utc)
    total = 0
    new_count = 0
    due_count = 0
    mastered_count = 0
    for w in words_db.all():
        total += 1
        if scoring.is_new(w):
            new_count += 1
        elif scoring.is_due(w, cfg, now):
            due_count += 1
        if scoring.is_mastered(w, cfg):
            mastered_count += 1
    return {"total": total, "new": new_count, "due": due_count, "mastered": mastered_count}


# ---------- Sessions ----------

@app.get("/api/sessions/active")
def list_active_sessions():
    out = []
    for sess in active_sessions.values():
        if sess.current is None:
            continue
        out.append({
            "id": sess.id,
            "mode": sess.mode,
            "started_at": sess.started_at,
            "remaining": len(sess.queue) + 1,
        })
    return {"sessions": out}


@app.post("/api/sessions/start")
def start_session(req: StartSessionRequest):
    cfg = get_cfg()
    words = words_db.all()
    if req.mode == "learn":
        sess = sess_mod.start_learn_session(words, cfg, max_size=req.size)
    else:
        sess = sess_mod.start_review_session(words, cfg, size=req.size)
    active_sessions[sess.id] = sess
    session_store.put(sess)
    return _session_state(sess)


@app.get("/api/sessions/{session_id}")
def get_session(session_id: str):
    sess = active_sessions.get(session_id)
    if not sess:
        raise HTTPException(404, "session not found")
    return _session_state(sess)


@app.post("/api/sessions/{session_id}/answer")
def answer_session(session_id: str, req: AnswerRequest):
    cfg = get_cfg()
    sess = active_sessions.get(session_id)
    if not sess:
        raise HTTPException(404, "session not found")
    if sess.current is None:
        raise HTTPException(400, "no current card")
    sess_mod.answer(sess, words_db, cfg, req.grade)
    session_store.put(sess)
    return _session_state(sess)


@app.post("/api/sessions/{session_id}/skip")
def skip_card(session_id: str):
    """Advance past the current card without grading.
    Used after the underlying word is deleted from the dictionary."""
    cfg = get_cfg()
    sess = active_sessions.get(session_id)
    if not sess:
        raise HTTPException(404, "session not found")
    if sess.current is not None:
        direction = "forward" if sess.mode == "learn" else scoring.random_direction(cfg)
        sess_mod._advance(sess, direction)
        session_store.put(sess)
    return _session_state(sess)


@app.post("/api/sessions/{session_id}/end")
def end_session(session_id: str):
    sess = active_sessions.get(session_id)
    if not sess:
        raise HTTPException(404, "session not found")
    sess_mod.end(sess)
    summary = sess_mod.to_summary(sess, words_db)
    sessions_db.append(summary)
    active_sessions.pop(session_id, None)
    session_store.remove(session_id)
    return summary


@app.post("/api/sessions/{session_id}/typing-check")
def typing_check(session_id: str, req: TypingCheckRequest):
    cfg = get_cfg()
    sess = active_sessions.get(session_id)
    if not sess:
        raise HTTPException(404, "session not found")
    word = words_db.get(req.word_id)
    if not word:
        raise HTTPException(404, "word not found")
    relaxed = cfg.get("typing_relaxed_diacritics", True)
    norm_typed = normalize.normalize_for_match(req.typed, relaxed_diacritics=relaxed)
    norm_target = normalize.normalize_for_match(word["word_lat"], relaxed_diacritics=relaxed)
    distance = Levenshtein.distance(norm_typed, norm_target)
    threshold = cfg.get("typing_hard_levenshtein_threshold", 2)
    if distance == 0:
        suggested = "good"
    elif distance <= threshold:
        suggested = "hard"
    else:
        suggested = "again"
    return {
        "distance": distance,
        "suggested_grade": suggested,
        "expected_cyr": word["word_cyr"],
        "expected_lat": word["word_lat"],
    }


def _current_card_payload(sess: sess_mod.Session) -> Optional[dict]:
    if not sess.current:
        return None
    word = words_db.get(sess.current.word_id)
    if not word:
        return None
    return {"word": _to_api(word), "direction": sess.current.direction}


def _session_state(sess: sess_mod.Session) -> dict:
    cfg = get_cfg()
    return {
        "id": sess.id,
        "mode": sess.mode,
        "card": _current_card_payload(sess),
        "hud": sess_mod.hud(sess, words_db=words_db, cfg=cfg),
        "finished": sess.current is None,
    }


@app.get("/api/sessions")
def list_sessions():
    return {"sessions": sessions_db.recent(50)}


# ---------- Settings ----------

@app.get("/api/config")
def read_config():
    return get_cfg()


@app.put("/api/config")
def write_config(new_cfg: dict):
    # Light validation: keep keys that already exist, ignore extras to be safe.
    current = get_cfg()
    current.update({k: v for k, v in new_cfg.items() if k in current})
    cfg_mod.save(current)
    return current


# ---------- Media ----------

# Serve generated images/audio
app.mount("/media", StaticFiles(directory=str(cfg_mod.MEDIA_DIR)), name="media")


# ---------- Frontend (static) ----------

FRONTEND_DIR = ROOT / "frontend"


_NO_CACHE = {"Cache-Control": "no-store, no-cache, must-revalidate", "Pragma": "no-cache"}


@app.get("/")
def index():
    return FileResponse(str(FRONTEND_DIR / "index.html"), headers=_NO_CACHE)


app.mount("/static", StaticFiles(directory=str(FRONTEND_DIR)), name="static")
