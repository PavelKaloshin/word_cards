import Foundation

/// Serbian script normalization: Cyrillic <-> Latin, diacritic stripping for fuzzy match.
/// Port of backend/normalize.py
enum NormalizeService {

    // MARK: - Character mapping tables

    /// Serbian Cyrillic to Latin (gajica)
    static let cyrToLat: [Character: String] = [
        "\u{0410}": "A", "\u{0411}": "B", "\u{0412}": "V", "\u{0413}": "G",
        "\u{0414}": "D", "\u{0402}": "\u{0110}", // Ђ -> Đ
        "\u{0415}": "E", "\u{0416}": "\u{017D}", // Ж -> Ž
        "\u{0417}": "Z", "\u{0418}": "I", "\u{0408}": "J", "\u{041A}": "K",
        "\u{041B}": "L", "\u{0409}": "Lj", // Љ -> Lj
        "\u{041C}": "M", "\u{041D}": "N", "\u{040A}": "Nj", // Њ -> Nj
        "\u{041E}": "O", "\u{041F}": "P", "\u{0420}": "R", "\u{0421}": "S",
        "\u{0422}": "T", "\u{040B}": "\u{0106}", // Ћ -> Ć
        "\u{0423}": "U", "\u{0424}": "F", "\u{0425}": "H",
        "\u{0426}": "C", "\u{0427}": "\u{010C}", // Ч -> Č
        "\u{040F}": "D\u{017E}", // Џ -> Dž
        "\u{0428}": "\u{0160}", // Ш -> Š
        // Lowercase
        "\u{0430}": "a", "\u{0431}": "b", "\u{0432}": "v", "\u{0433}": "g",
        "\u{0434}": "d", "\u{0452}": "\u{0111}", // ђ -> đ
        "\u{0435}": "e", "\u{0436}": "\u{017E}", // ж -> ž
        "\u{0437}": "z", "\u{0438}": "i", "\u{0458}": "j", "\u{043A}": "k",
        "\u{043B}": "l", "\u{0459}": "lj", // љ -> lj
        "\u{043C}": "m", "\u{043D}": "n", "\u{045A}": "nj", // њ -> nj
        "\u{043E}": "o", "\u{043F}": "p", "\u{0440}": "r", "\u{0441}": "s",
        "\u{0442}": "t", "\u{045B}": "\u{0107}", // ћ -> ć
        "\u{0443}": "u", "\u{0444}": "f", "\u{0445}": "h",
        "\u{0446}": "c", "\u{0447}": "\u{010D}", // ч -> č
        "\u{045F}": "d\u{017E}", // џ -> dž
        "\u{0448}": "\u{0161}", // ш -> š
    ]

    /// Latin (gajica) digraphs to Cyrillic. Applied before single-letter mapping.
    static let latDigraphToCyr: [(String, String)] = [
        ("Lj", "\u{0409}"), ("LJ", "\u{0409}"), ("lj", "\u{0459}"),
        ("Nj", "\u{040A}"), ("NJ", "\u{040A}"), ("nj", "\u{045A}"),
        ("D\u{017E}", "\u{040F}"), ("D\u{017D}", "\u{040F}"), ("d\u{017E}", "\u{045F}"),
    ]

    /// Latin (gajica) single-letter to Cyrillic
    static let latToCyr: [Character: Character] = [
        "A": "\u{0410}", "B": "\u{0411}", "V": "\u{0412}", "G": "\u{0413}",
        "D": "\u{0414}", "\u{0110}": "\u{0402}", // Đ -> Ђ
        "E": "\u{0415}", "\u{017D}": "\u{0416}", // Ž -> Ж
        "Z": "\u{0417}", "I": "\u{0418}", "J": "\u{0408}", "K": "\u{041A}",
        "L": "\u{041B}", "M": "\u{041C}", "N": "\u{041D}", "O": "\u{041E}",
        "P": "\u{041F}", "R": "\u{0420}", "S": "\u{0421}", "T": "\u{0422}",
        "\u{0106}": "\u{040B}", // Ć -> Ћ
        "U": "\u{0423}", "F": "\u{0424}", "H": "\u{0425}",
        "C": "\u{0426}", "\u{010C}": "\u{0427}", // Č -> Ч
        "\u{0160}": "\u{0428}", // Š -> Ш
        // Lowercase
        "a": "\u{0430}", "b": "\u{0431}", "v": "\u{0432}", "g": "\u{0433}",
        "d": "\u{0434}", "\u{0111}": "\u{0452}", // đ -> ђ
        "e": "\u{0435}", "\u{017E}": "\u{0436}", // ž -> ж
        "z": "\u{0437}", "i": "\u{0438}", "j": "\u{0458}", "k": "\u{043A}",
        "l": "\u{043B}", "m": "\u{043C}", "n": "\u{043D}", "o": "\u{043E}",
        "p": "\u{043F}", "r": "\u{0440}", "s": "\u{0441}", "t": "\u{0442}",
        "\u{0107}": "\u{045B}", // ć -> ћ
        "u": "\u{0443}", "f": "\u{0444}", "h": "\u{0445}",
        "c": "\u{0446}", "\u{010D}": "\u{0447}", // č -> ч
        "\u{0161}": "\u{0448}", // š -> ш
    ]

    // MARK: - Detection

    /// Returns true if the string contains any Serbian Cyrillic characters.
    static func isCyrillic(_ s: String) -> Bool {
        for ch in s {
            if cyrToLat[ch] != nil {
                return true
            }
        }
        return false
    }

    // MARK: - Conversion

    /// Convert Cyrillic string to Latin.
    static func cyrToLatString(_ s: String) -> String {
        var result = ""
        for ch in s {
            if let mapped = cyrToLat[ch] {
                result += mapped
            } else {
                result.append(ch)
            }
        }
        return result
    }

    /// Convert Latin string to Cyrillic.
    static func latToCyrString(_ s: String) -> String {
        var out = s
        // Apply digraphs first (order matters)
        for (digraph, replacement) in latDigraphToCyr {
            out = out.replacingOccurrences(of: digraph, with: replacement)
        }
        var result = ""
        for ch in out {
            if let mapped = latToCyr[ch] {
                result.append(mapped)
            } else {
                result.append(ch)
            }
        }
        return result
    }

    /// Returns (cyrillic, latin) for any Serbian input string.
    static func toBoth(_ s: String) -> (String, String) {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return ("", "")
        }
        if isCyrillic(trimmed) {
            return (trimmed, cyrToLatString(trimmed))
        }
        return (latToCyrString(trimmed), trimmed)
    }

    // MARK: - Diacritic handling

    /// Remove Serbian-specific diacritics for fuzzy matching.
    static func stripDiacritics(_ s: String) -> String {
        // Handle Đ -> Dj specially (not just an accent)
        var result = s.replacingOccurrences(of: "\u{0110}", with: "Dj")
            .replacingOccurrences(of: "\u{0111}", with: "dj")
        // Strip combining marks via NFKD normalization
        let nfkd = result.decomposedStringWithCompatibilityMapping
        result = String(nfkd.unicodeScalars.filter { !CharacterSet.combiningMarks.contains($0) })
        return result
    }

    /// Normalize a string for typing-mode comparison.
    /// Always: lowercase, trim, transliterate to Latin.
    /// If relaxedDiacritics: also strip š/č/ć/ž/đ to plain ASCII.
    static func normalizeForMatch(_ s: String, relaxedDiacritics: Bool = true) -> String {
        var result = s.trimmingCharacters(in: .whitespaces).lowercased()
        if isCyrillic(result) {
            result = cyrToLatString(result)
        }
        if relaxedDiacritics {
            result = stripDiacritics(result)
        }
        return result
    }
}

private extension CharacterSet {
    /// Unicode combining marks category (Mn, Mc, Me).
    static let combiningMarks: CharacterSet = {
        var set = CharacterSet()
        // Combining Diacritical Marks: U+0300 to U+036F
        set.insert(charactersIn: Unicode.Scalar(0x0300)!...Unicode.Scalar(0x036F)!)
        // Combining Diacritical Marks Extended: U+1AB0 to U+1AFF
        set.insert(charactersIn: Unicode.Scalar(0x1AB0)!...Unicode.Scalar(0x1AFF)!)
        // Combining Diacritical Marks Supplement: U+1DC0 to U+1DFF
        set.insert(charactersIn: Unicode.Scalar(0x1DC0)!...Unicode.Scalar(0x1DFF)!)
        return set
    }()
}
