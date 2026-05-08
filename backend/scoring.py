"""
Word selection algorithm. See SCORING.md for the math and rationale.
"""
from __future__ import annotations

import random
from datetime import datetime, timezone


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def parse_iso(s: str | None) -> datetime | None:
    if not s:
        return None
    return datetime.fromisoformat(s)


def base_interval_minutes(streak: int, base_intervals: list[int]) -> float:
    idx = max(0, min(streak, len(base_intervals) - 1))
    return float(base_intervals[idx])


def effective_interval_minutes(word: dict, cfg: dict, last_grade: str | None = None) -> float:
    """Interval until next show, given current state and the last grade given."""
    streak = word.get("streak", 0)
    forget = word.get("forget_count", 0)
    base = base_interval_minutes(streak, cfg["base_intervals_minutes"])
    decay = 1.0 / (1.0 + forget * cfg["forget_decay_alpha"])
    hard_mod = cfg["hard_modifier"] if last_grade == "hard" else 1.0
    return base * decay * hard_mod


def error_factor(word: dict, cfg: dict) -> float:
    g = word.get("total_good", 0)
    a = word.get("total_again", 0)
    h = word.get("total_hard", 0)
    attempts = g + a + h
    error_rate = (a + 0.5 * h) / max(1, attempts)
    confidence = min(1.0, attempts / 5.0)
    smoothed = confidence * error_rate + (1.0 - confidence) * cfg["error_prior"]
    return 1.0 + cfg["error_factor_alpha"] * smoothed


def due_factor(word: dict, cfg: dict, now: datetime) -> float:
    last_seen = parse_iso(word.get("last_seen_at"))
    if last_seen is None:
        return cfg["due_factors"][-1]  # never seen reviewable -> very due
    interval = effective_interval_minutes(word, cfg)
    if interval <= 0:
        return cfg["due_factors"][-1]
    minutes_since = (now - last_seen).total_seconds() / 60.0
    ratio = minutes_since / interval

    thresholds = cfg["due_thresholds"]
    factors = cfg["due_factors"]
    # factors has len(thresholds)+1 buckets
    for i, t in enumerate(thresholds):
        if ratio < t:
            return factors[i]
    return factors[-1]


def recency_dampener(word: dict, now: datetime) -> float:
    last_seen = parse_iso(word.get("last_seen_at"))
    if last_seen is None:
        return 1.0
    minutes_since = (now - last_seen).total_seconds() / 60.0
    if minutes_since < 2:
        return 0.0
    if minutes_since < 10:
        return 0.2
    return 1.0


def review_weight(word: dict, cfg: dict, now: datetime) -> float:
    return error_factor(word, cfg) * due_factor(word, cfg, now) * recency_dampener(word, now)


def is_new(word: dict) -> bool:
    return (word.get("total_good", 0) + word.get("total_again", 0) + word.get("total_hard", 0)) == 0


def is_mastered(word: dict, cfg: dict) -> bool:
    return word.get("streak", 0) >= cfg["mastered_threshold"]


def is_due(word: dict, cfg: dict, now: datetime) -> bool:
    """For the home-screen 'due count' indicator."""
    if is_new(word):
        return False
    last_seen = parse_iso(word.get("last_seen_at"))
    if last_seen is None:
        return True
    interval = effective_interval_minutes(word, cfg)
    minutes_since = (now - last_seen).total_seconds() / 60.0
    return minutes_since >= interval


def pick_review_words(words: list[dict], cfg: dict, n: int) -> list[dict]:
    """Weighted random sample without replacement."""
    now = datetime.now(timezone.utc)
    candidates = [w for w in words if not is_new(w)]
    if not candidates:
        return []
    weights = [review_weight(w, cfg, now) for w in candidates]
    if sum(weights) == 0:
        return random.sample(candidates, min(n, len(candidates)))

    picked: list[dict] = []
    pool = list(zip(candidates, weights))
    for _ in range(min(n, len(pool))):
        total = sum(w for _, w in pool)
        if total == 0:
            break
        r = random.random() * total
        acc = 0.0
        for i, (cand, w) in enumerate(pool):
            acc += w
            if acc >= r:
                picked.append(cand)
                pool.pop(i)
                break
    return picked


def apply_grade(word: dict, grade: str, cfg: dict, direction: str = "forward") -> None:
    """Mutates word in-place. Caller is responsible for persisting."""
    was_mastered = is_mastered(word, cfg)
    word["last_seen_at"] = now_iso()

    if grade == "good":
        word["streak"] = word.get("streak", 0) + 1
        word["total_good"] = word.get("total_good", 0) + 1
        word["last_correct_at"] = word["last_seen_at"]
    elif grade == "hard":
        word["streak"] = word.get("streak", 0) + 1
        word["total_hard"] = word.get("total_hard", 0) + 1
        word["last_correct_at"] = word["last_seen_at"]
    elif grade == "again":
        if was_mastered:
            word["forget_count"] = word.get("forget_count", 0) + 1
        word["streak"] = 0
        word["total_again"] = word.get("total_again", 0) + 1
    else:
        raise ValueError(f"unknown grade: {grade}")

    history = word.setdefault("history", [])
    history.append({"ts": word["last_seen_at"], "grade": grade, "direction": direction})


def random_direction(cfg: dict) -> str:
    return "reverse" if random.random() < cfg["reverse_probability"] else "forward"
