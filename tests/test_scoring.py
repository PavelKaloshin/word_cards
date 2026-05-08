from datetime import datetime, timedelta, timezone

import pytest

from backend import scoring


@pytest.fixture
def cfg():
    return {
        "mastered_threshold": 3,
        "base_intervals_minutes": [10, 1440, 4320, 10080, 30240, 86400, 259200],
        "hard_modifier": 0.5,
        "forget_decay_alpha": 0.4,
        "error_factor_alpha": 4,
        "error_prior": 0.3,
        "review_session_size": 100,
        "reverse_probability": 0.5,
        "due_thresholds": [0.5, 1, 2, 5],
        "due_factors": [0.05, 0.3, 1.5, 3.0, 5.0],
    }


def make_word(**overrides):
    base = {
        "id": "test",
        "streak": 0,
        "total_good": 0,
        "total_again": 0,
        "total_hard": 0,
        "forget_count": 0,
        "last_seen_at": None,
        "history": [],
    }
    base.update(overrides)
    return base


def now_utc():
    return datetime.now(timezone.utc)


def iso_minutes_ago(minutes):
    return (now_utc() - timedelta(minutes=minutes)).isoformat()


class TestIntervals:
    def test_streak_zero_is_short(self, cfg):
        w = make_word(streak=0)
        assert scoring.effective_interval_minutes(w, cfg) == 10

    def test_streak_grows_interval(self, cfg):
        for s, expected in [(1, 1440), (2, 4320), (3, 10080), (4, 30240)]:
            w = make_word(streak=s)
            assert scoring.effective_interval_minutes(w, cfg) == expected

    def test_streak_capped_at_max(self, cfg):
        w = make_word(streak=99)
        assert scoring.effective_interval_minutes(w, cfg) == cfg["base_intervals_minutes"][-1]

    def test_forget_count_shrinks_interval(self, cfg):
        no_forget = make_word(streak=4, forget_count=0)
        once = make_word(streak=4, forget_count=1)
        twice = make_word(streak=4, forget_count=2)
        assert scoring.effective_interval_minutes(once, cfg) < scoring.effective_interval_minutes(no_forget, cfg)
        assert scoring.effective_interval_minutes(twice, cfg) < scoring.effective_interval_minutes(once, cfg)

    def test_hard_grade_halves(self, cfg):
        w = make_word(streak=2)
        good_iv = scoring.effective_interval_minutes(w, cfg, last_grade="good")
        hard_iv = scoring.effective_interval_minutes(w, cfg, last_grade="hard")
        assert hard_iv == pytest.approx(good_iv * cfg["hard_modifier"])


class TestErrorFactor:
    def test_no_attempts_uses_prior(self, cfg):
        w = make_word()
        ef = scoring.error_factor(w, cfg)
        # 1 + alpha * prior
        assert ef == pytest.approx(1 + cfg["error_factor_alpha"] * cfg["error_prior"])

    def test_all_correct_minimum(self, cfg):
        w = make_word(total_good=20, total_again=0, total_hard=0)
        # confidence saturates at 1.0, smoothed = 0
        assert scoring.error_factor(w, cfg) == pytest.approx(1.0)

    def test_all_wrong_max(self, cfg):
        w = make_word(total_good=0, total_again=20, total_hard=0)
        assert scoring.error_factor(w, cfg) == pytest.approx(1 + cfg["error_factor_alpha"])

    def test_hard_counts_as_half_error(self, cfg):
        all_good = make_word(total_good=10)
        all_hard = make_word(total_hard=10)
        all_again = make_word(total_again=10)
        assert scoring.error_factor(all_good, cfg) < scoring.error_factor(all_hard, cfg) < scoring.error_factor(all_again, cfg)

    def test_low_attempts_blended_toward_prior(self, cfg):
        # 1 attempt all wrong: confidence=0.2, smoothed = 0.2 * 1 + 0.8 * 0.3 = 0.44
        w = make_word(total_again=1)
        ef = scoring.error_factor(w, cfg)
        assert ef == pytest.approx(1 + cfg["error_factor_alpha"] * 0.44)


class TestDueFactor:
    def test_never_seen_is_max_due(self, cfg):
        w = make_word()
        assert scoring.due_factor(w, cfg, now_utc()) == cfg["due_factors"][-1]

    def test_just_seen_is_minimum(self, cfg):
        # ratio < 0.5 of an interval -> first bucket
        w = make_word(streak=2, last_seen_at=iso_minutes_ago(60))  # interval ~ 4320 min
        assert scoring.due_factor(w, cfg, now_utc()) == cfg["due_factors"][0]

    def test_overdue_is_high(self, cfg):
        # streak=1 -> 1d interval. Last seen 10d ago -> ratio=10 -> last bucket
        w = make_word(streak=1, last_seen_at=iso_minutes_ago(60 * 24 * 10))
        assert scoring.due_factor(w, cfg, now_utc()) == cfg["due_factors"][-1]

    def test_exactly_due(self, cfg):
        # streak=1 -> 1d (1440min). last_seen 1440min ago -> ratio=1 -> 3rd bucket
        w = make_word(streak=1, last_seen_at=iso_minutes_ago(1440))
        assert scoring.due_factor(w, cfg, now_utc()) == cfg["due_factors"][2]


class TestRecencyDampener:
    def test_just_seen_is_zero(self, cfg):
        w = make_word(last_seen_at=iso_minutes_ago(0.5))
        assert scoring.recency_dampener(w, now_utc()) == 0.0

    def test_a_few_minutes_ago_low(self, cfg):
        w = make_word(last_seen_at=iso_minutes_ago(5))
        assert scoring.recency_dampener(w, now_utc()) == 0.2

    def test_long_ago_full_weight(self, cfg):
        w = make_word(last_seen_at=iso_minutes_ago(60))
        assert scoring.recency_dampener(w, now_utc()) == 1.0

    def test_never_seen_full_weight(self, cfg):
        assert scoring.recency_dampener(make_word(), now_utc()) == 1.0


class TestApplyGrade:
    def test_good_increments_streak_and_total(self, cfg):
        w = make_word(streak=1)
        scoring.apply_grade(w, "good", cfg)
        assert w["streak"] == 2
        assert w["total_good"] == 1
        assert w["last_seen_at"] is not None
        assert w["last_correct_at"] == w["last_seen_at"]
        assert w["history"][-1]["grade"] == "good"

    def test_hard_increments_streak_and_total_hard(self, cfg):
        w = make_word(streak=1)
        scoring.apply_grade(w, "hard", cfg)
        assert w["streak"] == 2
        assert w["total_hard"] == 1
        assert w["last_correct_at"] == w["last_seen_at"]

    def test_again_resets_streak(self, cfg):
        w = make_word(streak=2)
        scoring.apply_grade(w, "again", cfg)
        assert w["streak"] == 0
        assert w["total_again"] == 1

    def test_again_after_mastered_increments_forget(self, cfg):
        w = make_word(streak=4, total_good=4)
        assert scoring.is_mastered(w, cfg)
        scoring.apply_grade(w, "again", cfg)
        assert w["forget_count"] == 1
        assert w["streak"] == 0

    def test_again_pre_mastered_no_forget(self, cfg):
        w = make_word(streak=2, total_good=2)
        scoring.apply_grade(w, "again", cfg)
        assert w["forget_count"] == 0

    def test_unknown_grade_raises(self, cfg):
        w = make_word()
        with pytest.raises(ValueError):
            scoring.apply_grade(w, "skip", cfg)

    def test_history_records_direction(self, cfg):
        w = make_word()
        scoring.apply_grade(w, "good", cfg, direction="reverse")
        assert w["history"][-1]["direction"] == "reverse"


class TestStateClassifiers:
    def test_is_new(self, cfg):
        assert scoring.is_new(make_word())
        assert not scoring.is_new(make_word(total_good=1))
        assert not scoring.is_new(make_word(total_again=1))
        assert not scoring.is_new(make_word(total_hard=1))

    def test_is_mastered(self, cfg):
        assert not scoring.is_mastered(make_word(streak=2), cfg)
        assert scoring.is_mastered(make_word(streak=3), cfg)
        assert scoring.is_mastered(make_word(streak=99), cfg)

    def test_is_due_new_word_not_due(self, cfg):
        assert not scoring.is_due(make_word(), cfg, now_utc())

    def test_is_due_overdue(self, cfg):
        w = make_word(streak=1, total_good=1, last_seen_at=iso_minutes_ago(2 * 1440))
        assert scoring.is_due(w, cfg, now_utc())

    def test_is_due_recent(self, cfg):
        w = make_word(streak=1, total_good=1, last_seen_at=iso_minutes_ago(60))
        assert not scoring.is_due(w, cfg, now_utc())


class TestPickReviewWords:
    def test_excludes_new_words(self, cfg):
        words = [make_word(id="new1"), make_word(id="seen1", total_good=1, last_seen_at=iso_minutes_ago(99999))]
        picked = scoring.pick_review_words(words, cfg, n=10)
        ids = {w["id"] for w in picked}
        assert "new1" not in ids
        assert "seen1" in ids

    def test_returns_at_most_n(self, cfg):
        words = [make_word(id=f"w{i}", total_good=1, last_seen_at=iso_minutes_ago(99999)) for i in range(20)]
        picked = scoring.pick_review_words(words, cfg, n=5)
        assert len(picked) == 5
        # no duplicates
        assert len({w["id"] for w in picked}) == 5

    def test_problematic_more_likely_than_easy(self, cfg):
        # Run many times, count how often each word is picked as the FIRST sample
        problematic = make_word(id="bad", total_good=1, total_again=10, last_seen_at=iso_minutes_ago(99999))
        easy = make_word(id="ok", total_good=10, total_again=0, last_seen_at=iso_minutes_ago(99999))
        bad_count = 0
        N = 500
        for _ in range(N):
            picks = scoring.pick_review_words([problematic, easy], cfg, n=1)
            if picks and picks[0]["id"] == "bad":
                bad_count += 1
        # The bad word should dominate strongly (its weight is much higher)
        assert bad_count / N > 0.7

    def test_just_seen_words_excluded(self, cfg):
        # recency dampener at 0 -> weight = 0 -> not picked
        recent = make_word(id="recent", total_good=1, last_seen_at=iso_minutes_ago(1))
        old = make_word(id="old", total_good=1, last_seen_at=iso_minutes_ago(99999))
        for _ in range(50):
            picks = scoring.pick_review_words([recent, old], cfg, n=1)
            assert picks == [] or picks[0]["id"] == "old"

    def test_empty_list(self, cfg):
        assert scoring.pick_review_words([], cfg, n=10) == []


class TestRandomDirection:
    def test_zero_probability_always_forward(self, cfg):
        cfg["reverse_probability"] = 0.0
        for _ in range(50):
            assert scoring.random_direction(cfg) == "forward"

    def test_one_probability_always_reverse(self, cfg):
        cfg["reverse_probability"] = 1.0
        for _ in range(50):
            assert scoring.random_direction(cfg) == "reverse"
