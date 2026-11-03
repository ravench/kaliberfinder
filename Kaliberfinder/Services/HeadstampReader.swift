import Foundation

/// Finds calibres in text read from a photo, e.g. the headstamp "WIN 308" or a box label "9mm Luger".
enum HeadstampReader {
    enum Strength: Int, Comparable {
        /// A short, ambiguous spelling such as "45" or "38" (could be a year or lot number).
        case weak
        /// A distinctive spelling such as "308 WIN" or "9x19".
        case strong

        static func < (a: Strength, b: Strength) -> Bool { a.rawValue < b.rawValue }
    }

    struct Hit: Equatable {
        let cartridgeID: String
        let text: String
        let strength: Strength
    }

    /// Normalised spelling -> cartridge ids, built from names, aliases and headstamps.
    static let index: [String: [String]] = buildIndex(CartridgeCatalog.all)

    static func buildIndex(_ cartridges: [Cartridge]) -> [String: [String]] {
        var index: [String: [String]] = [:]
        for c in cartridges {
            for name in c.allNames {
                let key = CartridgeCatalog.normalized(name)
                guard !key.isEmpty, !(index[key] ?? []).contains(c.id) else { continue }
                index[key, default: []].append(c.id)
            }
        }
        return index
    }

    /// Spellings of up to two characters, or only digits up to three, are weak.
    static func strength(of key: String) -> Strength {
        if key.count <= 2 || (key.count <= 3 && key.allSatisfy(\.isNumber)) { return .weak }
        return .strong
    }

    /// Calibres whose headstamp of the form number + word ("45 AUTO") may be what was read when a
    /// leading digit or the word's first or last letter was missed, as on a worn or stylised stamp:
    /// "5 AUTO", "45 AUT" or "5 AUT". Ambiguous ("5 AUTO" also fits "25 AUTO"), so only ever a weak hit.
    static func partialMatches(_ key: String, index: [String: [String]] = index) -> [String] {
        guard let read = numberAndWord(key) else { return [] }
        var ids: [String] = []
        for (name, nameIDs) in index {
            guard let full = numberAndWord(name), full.word.count >= 3 else { continue }
            let number = full.number == read.number || (full.number.hasSuffix(read.number) && read.number.count < full.number.count)
            let word = full.word == read.word
                || (read.word.count >= 3 && read.word.count == full.word.count - 1 && (full.word.hasPrefix(read.word) || full.word.hasSuffix(read.word)))
            if number && word { ids += nameIDs }
        }
        return Array(Set(ids)).sorted()
    }

    /// "45auto" -> ("45", "auto"); nil unless the key is digits followed by letters.
    static func numberAndWord(_ key: String) -> (number: String, word: String)? {
        let number = key.prefix { $0.isNumber }
        let word = key.dropFirst(number.count)
        guard !number.isEmpty, !word.isEmpty, word.allSatisfy(\.isLetter) else { return nil }
        return (String(number), String(word))
    }

    /// All calibres mentioned in `lines`, strongest first, one hit per calibre.
    /// Each line is tried whole and as runs of up to three neighbouring words.
    static func hits(in lines: [String], index: [String: [String]] = index) -> [Hit] {
        var best: [String: Hit] = [:]
        for line in lines {
            let words = line.split(whereSeparator: \.isWhitespace).map(String.init)
            var candidates = [line]
            for size in 1...3 where words.count >= size {
                for start in 0...(words.count - size) {
                    candidates.append(words[start..<start + size].joined(separator: " "))
                }
            }
            for text in candidates {
                let key = CartridgeCatalog.normalized(text)
                let found = index[key].map { ($0, strength(of: key)) } ?? (partialMatches(key, index: index), Strength.weak)
                for id in found.0 {
                    if let existing = best[id], existing.strength >= found.1 { continue }
                    best[id] = Hit(cartridgeID: id, text: text.trimmingCharacters(in: .whitespaces), strength: found.1)
                }
            }
        }
        return best.values.sorted {
            $0.strength != $1.strength ? $0.strength > $1.strength : $0.cartridgeID < $1.cartridgeID
        }
    }
}
