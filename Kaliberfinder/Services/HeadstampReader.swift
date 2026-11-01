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
                guard let ids = index[key] else { continue }
                let s = strength(of: key)
                for id in ids {
                    if let existing = best[id], existing.strength >= s { continue }
                    best[id] = Hit(cartridgeID: id, text: text.trimmingCharacters(in: .whitespaces), strength: s)
                }
            }
        }
        return best.values.sorted {
            $0.strength != $1.strength ? $0.strength > $1.strength : $0.cartridgeID < $1.cartridgeID
        }
    }
}
