"""
Session state. Two flavors:
- learn: Leitner-style queue, runs until all words mastered.
- review: weighted sample of N words, sequential.

Sessions are kept in-memory but mirrored to disk via SessionStore so they
survive a server restart.
"""
from __future__ import annotations

import json
import random
import uuid
from dataclasses import asdict, dataclass, field
from typing import Optional

from . import scoring
from .storage import JsonStore


@dataclass
class CurrentCard:
    word_id: str
    direction: str  # "forward" | "reverse"


@dataclass
class Session:
    id: str
    mode: str  # "learn" | "review"
    started_at: str
    ended_at: Optional[str] = None
    queue: list[str] = field(default_factory=list)  # list of word ids
    review_results: list[dict] = field(default_factory=list)
    current: Optional[CurrentCard] = None
    new_mastered_ids: set[str] = field(default_factory=set)
    learn_initial_total: int = 0  # for HUD progress in learn mode
    learn_word_ids: list[str] = field(default_factory=list)  # initial set of new words
    # session-local correct count per word (good/hard +1, capped at threshold).
    # Used for the monotonic progress bar above the card.
    learn_correct_count: dict[str, int] = field(default_factory=dict)

    # cumulative HUD counters
    good_count: int = 0
    hard_count: int = 0
    again_count: int = 0

    def to_dict(self) -> dict:
        d = asdict(self)
        d["new_mastered_ids"] = list(self.new_mastered_ids)
        return d

    @classmethod
    def from_dict(cls, d: dict) -> "Session":
        cur = d.get("current")
        return cls(
            id=d["id"],
            mode=d["mode"],
            started_at=d["started_at"],
            ended_at=d.get("ended_at"),
            queue=list(d.get("queue", [])),
            review_results=list(d.get("review_results", [])),
            current=CurrentCard(**cur) if cur else None,
            new_mastered_ids=set(d.get("new_mastered_ids", [])),
            learn_initial_total=d.get("learn_initial_total", 0),
            learn_word_ids=list(d.get("learn_word_ids", [])),
            learn_correct_count=dict(d.get("learn_correct_count", {})),
            good_count=d.get("good_count", 0),
            hard_count=d.get("hard_count", 0),
            again_count=d.get("again_count", 0),
        )


class SessionStore:
    """Persists active (in-progress) sessions to disk. Use on every mutation."""

    def __init__(self, path):
        self._store = JsonStore(path, default={"active": {}})

    def all(self) -> dict[str, "Session"]:
        return {sid: Session.from_dict(d) for sid, d in self._store.data["active"].items()}

    def put(self, sess: "Session") -> None:
        self._store.data["active"][sess.id] = sess.to_dict()
        self._store.save()

    def remove(self, session_id: str) -> None:
        self._store.data["active"].pop(session_id, None)
        self._store.save()


def new_id() -> str:
    return str(uuid.uuid4())


def start_learn_session(words: list[dict], cfg: dict, max_size: Optional[int] = None) -> Session:
    new_words = [w for w in words if scoring.is_new(w)]
    random.shuffle(new_words)
    cap = max_size if max_size is not None else cfg.get("max_new_per_session")
    if cap is not None:
        new_words = new_words[:cap]
    word_ids = [w["id"] for w in new_words]
    sess = Session(
        id=new_id(),
        mode="learn",
        started_at=scoring.now_iso(),
        queue=list(word_ids),
        learn_initial_total=len(new_words),
        learn_word_ids=list(word_ids),
    )
    _advance(sess, "forward")
    return sess


def start_review_session(words: list[dict], cfg: dict, size: Optional[int] = None) -> Session:
    n = size or cfg["review_session_size"]
    picks = scoring.pick_review_words(words, cfg, n)
    sess = Session(
        id=new_id(),
        mode="review",
        started_at=scoring.now_iso(),
        queue=[w["id"] for w in picks],
    )
    _advance(sess, scoring.random_direction(cfg))
    return sess


def _advance(sess: Session, direction: str) -> None:
    """Pop next word from queue into `current`, or set current=None if empty."""
    if not sess.queue:
        sess.current = None
        return
    next_id = sess.queue.pop(0)
    sess.current = CurrentCard(word_id=next_id, direction=direction)


def answer(sess: Session, words_db, cfg: dict, grade: str) -> Optional[CurrentCard]:
    """
    Apply grade to current word and advance to next. Returns next CurrentCard or None.
    Also persists the word.
    """
    if sess.current is None:
        return None
    word_id = sess.current.word_id
    direction = sess.current.direction
    word = words_db.get(word_id)
    if word is None:
        _advance(sess, scoring.random_direction(cfg) if sess.mode == "review" else "forward")
        return sess.current

    was_mastered = scoring.is_mastered(word, cfg)
    scoring.apply_grade(word, grade, cfg, direction)
    words_db.update(word_id, word)

    # HUD counters
    if grade == "good":
        sess.good_count += 1
    elif grade == "hard":
        sess.hard_count += 1
    elif grade == "again":
        sess.again_count += 1

    # Monotonic correct-count for the learn-mode progress bar
    if sess.mode == "learn" and grade in ("good", "hard") and word_id in sess.learn_word_ids:
        threshold = int(cfg.get("mastered_threshold", 3))
        cur = sess.learn_correct_count.get(word_id, 0)
        sess.learn_correct_count[word_id] = min(cur + 1, threshold)

    sess.review_results.append(
        {"word_id": word_id, "grade": grade, "direction": direction, "ts": scoring.now_iso()}
    )

    is_mastered_now = scoring.is_mastered(word, cfg)
    if is_mastered_now and not was_mastered:
        sess.new_mastered_ids.add(word_id)

    # Re-queue logic for learn mode
    if sess.mode == "learn":
        if not is_mastered_now:
            _reinsert_learn(sess, word_id, grade)
        # if mastered, don't re-queue
        _advance(sess, "forward")
    else:
        _advance(sess, scoring.random_direction(cfg))
    return sess.current


def _reinsert_learn(sess: Session, word_id: str, grade: str) -> None:
    """
    Leitner-style position by grade:
      again -> position 2 (return soon, but not immediately)
      hard  -> middle of queue
      good  -> end of queue
    """
    q = sess.queue
    if grade == "again":
        pos = min(2, len(q))
    elif grade == "hard":
        pos = max(1, len(q) // 2)
    else:
        pos = len(q)
    q.insert(pos, word_id)


def end(sess: Session) -> None:
    sess.ended_at = scoring.now_iso()
    sess.current = None


def to_summary(sess: Session, words_db) -> dict:
    shown = sess.good_count + sess.hard_count + sess.again_count
    accuracy = (sess.good_count + sess.hard_count) / shown if shown else 0.0
    # find the worst words (most "again" in this session)
    again_per_word: dict[str, int] = {}
    for r in sess.review_results:
        if r["grade"] == "again":
            again_per_word[r["word_id"]] = again_per_word.get(r["word_id"], 0) + 1
    hardest = sorted(again_per_word.items(), key=lambda x: -x[1])[:5]
    hardest_words = []
    for wid, count in hardest:
        w = words_db.get(wid)
        if w:
            hardest_words.append({"id": wid, "word_cyr": w["word_cyr"], "word_lat": w["word_lat"], "again_count": count})
    return {
        "id": sess.id,
        "mode": sess.mode,
        "started_at": sess.started_at,
        "ended_at": sess.ended_at,
        "results": sess.review_results,
        "summary": {
            "shown": shown,
            "good": sess.good_count,
            "hard": sess.hard_count,
            "again": sess.again_count,
            "accuracy": round(accuracy, 3),
            "new_mastered": len(sess.new_mastered_ids),
            "hardest": hardest_words,
        },
    }


def hud(sess: Session, words_db=None, cfg: Optional[dict] = None) -> dict:
    """Live HUD numbers."""
    pos: int
    total: int
    learn_progress: Optional[dict] = None
    if sess.mode == "learn":
        # how many of the initial new words have become mastered
        pos = len(sess.new_mastered_ids)
        total = sess.learn_initial_total
        if words_db is not None and cfg is not None:
            learn_progress = _compute_learn_progress(sess, words_db, cfg)
    else:
        # we know the total = items already done + items still in queue + (1 if current)
        done = sess.good_count + sess.hard_count + sess.again_count
        remaining = len(sess.queue) + (1 if sess.current else 0)
        total = done + remaining
        pos = done
    shown = sess.good_count + sess.hard_count + sess.again_count
    accuracy = (sess.good_count + sess.hard_count) / shown if shown else 0.0
    out = {
        "good": sess.good_count + sess.hard_count,  # combined "ok" count for ✓
        "hard": sess.hard_count,
        "again": sess.again_count,
        "accuracy": round(accuracy, 3),
        "position": pos,
        "total": total,
        "mode": sess.mode,
    }
    if learn_progress is not None:
        out["learn_progress"] = learn_progress
    return out


def _compute_learn_progress(sess: Session, words_db, cfg: dict) -> dict:
    """
    Monotonic learn-session progress: each correct answer (good/hard) on a session
    word contributes 1, capped at threshold per word. `again` doesn't change anything.
    Bar fills as the user advances; never decreases.
    """
    threshold = int(cfg.get("mastered_threshold", 3))
    word_ids = sess.learn_word_ids or sess.queue
    items: list[dict] = []
    total_correct = 0
    for wid in word_ids:
        w = words_db.get(wid)
        if w is None:
            continue
        correct = int(sess.learn_correct_count.get(wid, 0))
        correct = min(correct, threshold)
        total_correct += correct
        items.append({
            "id": wid,
            "word_cyr": w.get("word_cyr", ""),
            "word_lat": w.get("word_lat", ""),
            "translation": w.get("translation", ""),
            "image_url": _media_url(w.get("image_path", "")),
            "correct_count": correct,
            "streak": int(w.get("streak", 0)),
            "completed": correct >= threshold,
        })
    completed = sum(1 for w in items if w["completed"])
    return {
        "threshold": threshold,
        "total_correct": total_correct,
        "max_correct": threshold * len(items),
        "completed_words": completed,
        "remaining_words": len(items) - completed,
        "total_words": len(items),
        "words": items,
    }


def _media_url(path_str: str) -> str:
    """Mirror of app._media_url to avoid importing app from session."""
    if not path_str:
        return ""
    from pathlib import Path as _P
    from . import config as _cfg
    p = _P(path_str)
    try:
        rel = p.relative_to(_cfg.MEDIA_DIR)
    except ValueError:
        rel = _P(p.name)
    return f"/media/{rel.as_posix()}"
