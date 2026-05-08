from backend import normalize as n


class TestToBoth:
    def test_cyrillic_input(self):
        assert n.to_both("хлеб") == ("хлеб", "hleb")

    def test_latin_input(self):
        assert n.to_both("hleb") == ("хлеб", "hleb")

    def test_diacritic_latin(self):
        assert n.to_both("Ćao") == ("Ћао", "Ćao")

    def test_diacritic_cyrillic(self):
        assert n.to_both("ћао") == ("ћао", "ćao")

    def test_digraphs_latin_to_cyrillic(self):
        cyr, lat = n.to_both("ljubav")
        assert cyr == "љубав"
        assert lat == "ljubav"

    def test_dz_digraph(self):
        cyr, _ = n.to_both("džak")
        assert cyr == "џак"

    def test_capital_digraph(self):
        cyr, lat = n.to_both("Njuška")
        assert cyr.startswith("Њ")
        assert lat == "Njuška"

    def test_djordje_dj_special(self):
        cyr, lat = n.to_both("Đorđe")
        assert cyr == "Ђорђе"
        assert lat == "Đorđe"

    def test_empty(self):
        assert n.to_both("") == ("", "")

    def test_whitespace_stripped(self):
        assert n.to_both("  hleb  ") == ("хлеб", "hleb")


class TestNormalizeForMatch:
    def test_exact_match(self):
        assert n.normalize_for_match("hleb") == n.normalize_for_match("hleb")

    def test_cyrillic_to_latin(self):
        assert n.normalize_for_match("хлеб") == n.normalize_for_match("hleb")

    def test_diacritic_relaxed(self):
        assert n.normalize_for_match("šahovnica") == n.normalize_for_match("sahovnica")
        assert n.normalize_for_match("ćao") == n.normalize_for_match("cao")

    def test_diacritic_strict(self):
        a = n.normalize_for_match("šahovnica", relaxed_diacritics=False)
        b = n.normalize_for_match("sahovnica", relaxed_diacritics=False)
        assert a != b

    def test_dj_special(self):
        # Đak -> djak in relaxed mode
        assert n.normalize_for_match("Đak") == "djak"
        # In strict mode it preserves the đ
        assert n.normalize_for_match("Đak", relaxed_diacritics=False) == "đak"

    def test_case_insensitive(self):
        assert n.normalize_for_match("HLEB") == n.normalize_for_match("hleb")

    def test_typo_distance_via_levenshtein(self):
        # Sanity: relaxed normalization makes typo distance reasonable
        from rapidfuzz.distance import Levenshtein
        a = n.normalize_for_match("šahovnica")
        b = n.normalize_for_match("sahnvica")  # missing 'o', and 'h' before 'n'
        # We mostly want this to be small, not exactly 0
        assert Levenshtein.distance(a, b) <= 3

    def test_cyrillic_with_diacritic(self):
        # ћ in Cyrillic is the same sound as ć in Latin → both should normalize to "c"
        assert n.normalize_for_match("ћао") == n.normalize_for_match("ćao") == "cao"


class TestIsCyrillic:
    def test_latin_string(self):
        assert not n.is_cyrillic("hleb")

    def test_cyrillic_string(self):
        assert n.is_cyrillic("хлеб")

    def test_mixed_picks_cyrillic(self):
        assert n.is_cyrillic("hleb и xлеб")
