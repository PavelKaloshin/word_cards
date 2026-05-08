"""
Serbian script normalization: Cyrillic <-> Latin, diacritic stripping for fuzzy match.
"""
from __future__ import annotations

import unicodedata

# Serbian Cyrillic to Latin (gajica)
CYR_TO_LAT = {
    "А": "A", "Б": "B", "В": "V", "Г": "G", "Д": "D", "Ђ": "Đ",
    "Е": "E", "Ж": "Ž", "З": "Z", "И": "I", "Ј": "J", "К": "K",
    "Л": "L", "Љ": "Lj", "М": "M", "Н": "N", "Њ": "Nj", "О": "O",
    "П": "P", "Р": "R", "С": "S", "Т": "T", "Ћ": "Ć", "У": "U",
    "Ф": "F", "Х": "H", "Ц": "C", "Ч": "Č", "Џ": "Dž", "Ш": "Š",
    "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "ђ": "đ",
    "е": "e", "ж": "ž", "з": "z", "и": "i", "ј": "j", "к": "k",
    "л": "l", "љ": "lj", "м": "m", "н": "n", "њ": "nj", "о": "o",
    "п": "p", "р": "r", "с": "s", "т": "t", "ћ": "ć", "у": "u",
    "ф": "f", "х": "h", "ц": "c", "ч": "č", "џ": "dž", "ш": "š",
}

# Latin (gajica) digraphs and singletons to Cyrillic.
# Digraphs must be applied before single letters.
LAT_DIGRAPH_TO_CYR = [
    ("Lj", "Љ"), ("LJ", "Љ"), ("lj", "љ"),
    ("Nj", "Њ"), ("NJ", "Њ"), ("nj", "њ"),
    ("Dž", "Џ"), ("DŽ", "Џ"), ("dž", "џ"),
]
LAT_TO_CYR = {
    "A": "А", "B": "Б", "V": "В", "G": "Г", "D": "Д", "Đ": "Ђ",
    "E": "Е", "Ž": "Ж", "Z": "З", "I": "И", "J": "Ј", "K": "К",
    "L": "Л", "M": "М", "N": "Н", "O": "О", "P": "П", "R": "Р",
    "S": "С", "T": "Т", "Ć": "Ћ", "U": "У", "F": "Ф", "H": "Х",
    "C": "Ц", "Č": "Ч", "Š": "Ш",
    "a": "а", "b": "б", "v": "в", "g": "г", "d": "д", "đ": "ђ",
    "e": "е", "ž": "ж", "z": "з", "i": "и", "j": "ј", "k": "к",
    "l": "л", "m": "м", "n": "н", "o": "о", "p": "п", "r": "р",
    "s": "с", "t": "т", "ć": "ћ", "u": "у", "f": "ф", "h": "х",
    "c": "ц", "č": "ч", "š": "ш",
}


def is_cyrillic(s: str) -> bool:
    for ch in s:
        if "А" <= ch <= "ш" or ch in CYR_TO_LAT:
            return True
    return False


def cyr_to_lat(s: str) -> str:
    return "".join(CYR_TO_LAT.get(ch, ch) for ch in s)


def lat_to_cyr(s: str) -> str:
    out = s
    for digraph, replacement in LAT_DIGRAPH_TO_CYR:
        out = out.replace(digraph, replacement)
    return "".join(LAT_TO_CYR.get(ch, ch) for ch in out)


def to_both(s: str) -> tuple[str, str]:
    """Returns (cyrillic, latin) for any Serbian input string."""
    s = s.strip()
    if not s:
        return ("", "")
    if is_cyrillic(s):
        return (s, cyr_to_lat(s))
    return (lat_to_cyr(s), s)


def strip_diacritics(s: str) -> str:
    """Remove Serbian-specific diacritics for fuzzy matching."""
    # First handle Đ -> dj (special: not just an accent)
    s = s.replace("Đ", "Dj").replace("đ", "dj")
    # Then strip combining marks
    nfkd = unicodedata.normalize("NFKD", s)
    return "".join(ch for ch in nfkd if not unicodedata.combining(ch))


def normalize_for_match(s: str, relaxed_diacritics: bool = True) -> str:
    """
    Normalize a string for typing-mode comparison.
    Always: lowercase, trim, transliterate to Latin.
    If relaxed_diacritics: also strip š/č/ć/ž/đ to plain ASCII.
    """
    s = s.strip().lower()
    if is_cyrillic(s):
        s = cyr_to_lat(s)
    if relaxed_diacritics:
        s = strip_diacritics(s)
    return s
