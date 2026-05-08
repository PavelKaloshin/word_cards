"""
Session manager tests. Uses a mock words DB so we don't touch disk.
"""
from datetime import datetime, timedelta, timezone

import pytest

from backend import scoring, session as sess_mod


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
        "max_new_per_session": None,
        "reverse_probability": 0.0,  # deterministic for tests
        "due_thresholds": [0.5, 1, 2, 5],
        "due_factors": [0.05, 0.3, 1.5, 3.0, 5.0],
    }


class FakeWordsDB:
    def __init__(self, words):
        self._w = {w["id"]: w for w in words}

    def get(self, wid):
        return self._w.get(wid)

    def update(self, wid, patch):
        self._w[wid].update(patch)
        return self._w[wid]

    def all(self):
        return list(self._w.values())


def make_word(wid, **overrides):
    base = {
        "id": wid,
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


class TestLearnSession:
    def test_starts_with_only_new_words(self, cfg):
        words = [
            make_word("new1"),
            make_word("new2"),
            make_word("seen", total_good=2, last_seen_at="2020-01-01T00:00:00+00:00"),
        ]
        sess = sess_mod.start_learn_session(words, cfg)
        # current is set; queue + current covers all 2 new words
        all_ids = sess.queue + ([sess.current.word_id] if sess.current else [])
        assert set(all_ids) == {"new1", "new2"}
        assert "seen" not in all_ids

    def test_finishes_when_all_mastered(self, cfg):
        # one new word, mastered_threshold=3 -> after 3 goods it's done
        cfg["mastered_threshold"] = 3
        word = make_word("w1")
        db = FakeWordsDB([word])
        sess = sess_mod.start_learn_session(db.all(), cfg)
        for _ in range(3):
            sess_mod.answer(sess, db, cfg, "good")
        assert sess.current is None
        assert "w1" in sess.new_mastered_ids

    def test_again_re_queues_near_front(self, cfg):
        words = [make_word(f"w{i}") for i in range(5)]
        db = FakeWordsDB(words)
        sess = sess_mod.start_learn_session(db.all(), cfg)
        first = sess.current.word_id
        sess_mod.answer(sess, db, cfg, "again")
        # The word should still be in queue or be the next current
        ids_left = ([sess.current.word_id] if sess.current else []) + sess.queue
        assert first in ids_left
        # And it should reappear within a few cards (position <= 3)
        idx = ids_left.index(first)
        assert idx <= 3

    def test_good_re_queues_to_end(self, cfg):
        words = [make_word(f"w{i}") for i in range(3)]
        db = FakeWordsDB(words)
        sess = sess_mod.start_learn_session(db.all(), cfg)
        first = sess.current.word_id
        sess_mod.answer(sess, db, cfg, "good")
        # streak=1, not mastered yet -> should be at end of queue
        if sess.queue:
            assert sess.queue[-1] == first

    def test_max_new_per_session_caps(self, cfg):
        cfg["max_new_per_session"] = 2
        words = [make_word(f"w{i}") for i in range(10)]
        sess = sess_mod.start_learn_session(words, cfg)
        all_ids = sess.queue + ([sess.current.word_id] if sess.current else [])
        assert len(all_ids) == 2

    def test_increments_total_good(self, cfg):
        word = make_word("w1")
        db = FakeWordsDB([word])
        sess = sess_mod.start_learn_session(db.all(), cfg)
        sess_mod.answer(sess, db, cfg, "good")
        assert db.get("w1")["total_good"] == 1


class TestReviewSession:
    def test_only_seen_words(self, cfg):
        words = [
            make_word("new1"),
            make_word("seen1", total_good=1, last_seen_at="2020-01-01T00:00:00+00:00"),
            make_word("seen2", total_good=1, last_seen_at="2020-01-01T00:00:00+00:00"),
        ]
        sess = sess_mod.start_review_session(words, cfg, size=10)
        all_ids = sess.queue + ([sess.current.word_id] if sess.current else [])
        assert "new1" not in all_ids

    def test_size_caps_queue(self, cfg):
        words = [
            make_word(f"w{i}", total_good=1, last_seen_at="2020-01-01T00:00:00+00:00")
            for i in range(50)
        ]
        sess = sess_mod.start_review_session(words, cfg, size=5)
        all_ids = sess.queue + ([sess.current.word_id] if sess.current else [])
        assert len(all_ids) == 5

    def test_finishes_after_n_answers(self, cfg):
        words = [
            make_word(f"w{i}", total_good=1, last_seen_at="2020-01-01T00:00:00+00:00")
            for i in range(5)
        ]
        db = FakeWordsDB(words)
        sess = sess_mod.start_review_session(db.all(), cfg, size=5)
        answers_given = 0
        while sess.current and answers_given < 100:
            sess_mod.answer(sess, db, cfg, "good")
            answers_given += 1
        assert sess.current is None
        assert answers_given == 5


class TestSerialization:
    def test_roundtrip(self, cfg):
        words = [make_word(f"w{i}") for i in range(3)]
        sess = sess_mod.start_learn_session(words, cfg)
        sess.new_mastered_ids.add("w0")
        sess.good_count = 2
        sess.again_count = 1

        d = sess.to_dict()
        restored = sess_mod.Session.from_dict(d)

        assert restored.id == sess.id
        assert restored.mode == sess.mode
        assert restored.queue == sess.queue
        assert restored.new_mastered_ids == sess.new_mastered_ids
        assert restored.good_count == 2
        assert restored.again_count == 1
        if sess.current:
            assert restored.current.word_id == sess.current.word_id
            assert restored.current.direction == sess.current.direction


class TestHud:
    def test_review_progress_counts_done_vs_remaining(self, cfg):
        words = [
            make_word(f"w{i}", total_good=1, last_seen_at="2020-01-01T00:00:00+00:00")
            for i in range(3)
        ]
        db = FakeWordsDB(words)
        sess = sess_mod.start_review_session(db.all(), cfg, size=3)
        h = sess_mod.hud(sess)
        assert h["total"] == 3
        assert h["position"] == 0
        sess_mod.answer(sess, db, cfg, "good")
        h = sess_mod.hud(sess)
        assert h["position"] == 1

    def test_learn_progress_counts_mastered(self, cfg):
        cfg["mastered_threshold"] = 1
        words = [make_word("w1")]
        db = FakeWordsDB(words)
        sess = sess_mod.start_learn_session(db.all(), cfg)
        h = sess_mod.hud(sess)
        assert h["total"] == 1
        assert h["position"] == 0
        sess_mod.answer(sess, db, cfg, "good")
        h = sess_mod.hud(sess)
        # mastered_threshold=1, one good -> mastered
        assert h["position"] == 1
