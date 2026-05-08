"""
Tests the normalization-based dedup key used by the /api/words/add endpoint.
We replicate the helper here directly to keep tests independent of FastAPI.
"""
from backend.normalize import normalize_for_match


def key(s):
    return normalize_for_match(s, relaxed_diacritics=True)


class TestDedupKey:
    def test_same_word_collides(self):
        assert key("hleb") == key("hleb")

    def test_cyrillic_and_latin_collide(self):
        assert key("хлеб") == key("hleb")

    def test_diacritic_relaxed_collides(self):
        assert key("šahovnica") == key("sahovnica")
        assert key("ćao") == key("cao")

    def test_dj_normalizes(self):
        assert key("Đak") == key("djak")
        assert key("Ђак") == key("djak")

    def test_case_insensitive(self):
        assert key("HLEB") == key("hleb")

    def test_phrase(self):
        # multi-word phrase
        assert key("Kako si?") == key("kako si?")
        assert key("Како си?") == key("Kako si?")

    def test_distinct_words_dont_collide(self):
        assert key("kuća") != key("pas")

    def test_whitespace_trimmed(self):
        assert key("  hleb  ") == key("hleb")

    def test_empty(self):
        assert key("") == ""

    def test_dedup_logic(self):
        """Simulate the actual /api/words/add dedup loop."""
        existing = [{"word_lat": "hleb"}, {"word_lat": "kuća"}]
        existing_keys = {key(w["word_lat"]) for w in existing}

        new_entries = [
            "Hleb",         # dup (case)
            "хлеб",          # dup (script)
            "kuca",         # dup (diacritic)
            "voda",         # new
            "voda",         # within-batch dup
            "VODA",         # within-batch dup (case)
            "Kako si?",     # new (phrase)
        ]

        added = []
        skipped = []
        seen_in_batch = set()
        for w in new_entries:
            k = key(w)
            if k in existing_keys or k in seen_in_batch:
                skipped.append(w)
                continue
            seen_in_batch.add(k)
            added.append(w)

        assert added == ["voda", "Kako si?"]
        assert skipped == ["Hleb", "хлеб", "kuca", "voda", "VODA"]
