import Foundation

/// The unit lengths are shown and typed in. Data and calculations always stay in millimetres;
/// only display and input are converted (1 in = 25.4 mm). Metric is the default.
enum LengthUnit: String, CaseIterable, Identifiable {
    case metric
    case imperial

    /// UserDefaults key, used with @AppStorage so views update when the setting changes.
    static let storageKey = "lengthUnit"
    static let mmPerInch = 25.4

    /// The stored setting, metric when nothing is stored.
    static var current: LengthUnit {
        UserDefaults.standard.string(forKey: storageKey).flatMap(LengthUnit.init(rawValue:)) ?? .metric
    }

    var id: String { rawValue }

    /// German title, used as localization key.
    var title: String {
        switch self {
        case .metric: "Metrisch (mm)"
        case .imperial: "Imperial (Zoll)"
        }
    }

    var symbol: String { self == .metric ? "mm" : "in" }

    /// Converts millimetres to this unit.
    func value(fromMM mm: Double) -> Double { self == .metric ? mm : mm / Self.mmPerInch }

    /// Converts a value in this unit to millimetres.
    func millimetres(_ value: Double) -> Double { self == .metric ? value : value * Self.mmPerInch }

    /// "29.7 mm" or "1.169 in". Inches get 3 decimals, like US load data (2.800 in, 0.308 in); millimetres up
    /// to 2, at least `decimals` (the dimensioned drawing writes 9.0 mm, Raven 2026-11-09).
    func format(_ mm: Double, locale: Locale = .current, decimals: Int = 0) -> String {
        let style: FloatingPointFormatStyle<Double> = self == .metric
            ? .number.precision(.fractionLength(decimals...2))
            : .number.precision(.fractionLength(3))
        return value(fromMM: mm).formatted(style.locale(locale)) + " " + symbol
    }

    /// Reads typed text in this unit and returns millimetres, nil when empty or out of range (0–500 mm).
    func parse(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned) else { return nil }
        let mm = millimetres(value)
        return mm > 0 && mm < 500 ? mm : nil
    }

    /// Rewrites a typed value from one unit into another, so switching units keeps what was entered.
    /// Text that isn't a valid value is kept as it is.
    static func convert(_ text: String, from: LengthUnit, to: LengthUnit) -> String {
        guard from != to, let mm = from.parse(text) else { return text }
        let digits: Int = to == .metric ? 2 : 3
        let style = FloatingPointFormatStyle<Double>(locale: Locale(identifier: "en_US_POSIX"))
            .precision(.fractionLength(0...digits))
            .grouping(.never)
        return to.value(fromMM: mm).formatted(style)
    }
}

/// One tick of the 1:1 ruler. `level` runs from 0 (shortest) to 4 (numbered); labelled ticks carry the number to draw.
struct RulerTick: Equatable {
    let mm: Double
    let level: Int
    let label: String?
}

extension LengthUnit {
    /// Ticks from zero up to `lengthMM`: metric every mm (longer at 5, numbered every cm),
    /// imperial every 1/16 in (longer at 1/8, 1/4, 1/2, numbered every inch).
    func rulerTicks(lengthMM: Double) -> [RulerTick] {
        let step = self == .metric ? 1.0 : Self.mmPerInch / 16
        let count = max(0, Int((lengthMM / step + 1e-9).rounded(.down)))
        var ticks: [RulerTick] = []
        ticks.reserveCapacity(count + 1)
        for i in 0...count {
            ticks.append(tick(i, step: step))
        }
        return ticks
    }

    /// The `i`-th tick: every mm or every 1/16 in.
    private func tick(_ i: Int, step: Double) -> RulerTick {
        let perUnit = self == .metric ? 10 : 16
        let level: Int
        switch self {
        case .metric:
            if i % 10 == 0 { level = 4 } else if i % 5 == 0 { level = 2 } else { level = 0 }
        case .imperial:
            if i % 16 == 0 { level = 4 } else if i % 8 == 0 { level = 3 } else if i % 4 == 0 { level = 2 } else if i % 2 == 0 { level = 1 } else { level = 0 }
        }
        let label: String? = i % perUnit == 0 ? String(i / perUnit) : nil
        return RulerTick(mm: Double(i) * step, level: level, label: label)
    }

    /// Ruler length in mm: the tallest cartridge plus 5 mm, rounded up to a whole cm or inch.
    func rulerLength(tallestMM: Double) -> Double {
        let unitMM: Double = self == .metric ? 10 : Self.mmPerInch
        return ceil((tallestMM + 5) / unitMM) * unitMM
    }

    /// Screen scale for display, e.g. "6.32 pt/mm" or "160.5 pt/in". `precise` adds one decimal (calibration).
    func scaleText(pointsPerMM: Double, precise: Bool = false, locale: Locale = .current) -> String {
        let value: Double = self == .metric ? pointsPerMM : pointsPerMM * Self.mmPerInch
        var digits: Int = self == .metric ? 2 : 1
        if precise { digits += 1 }
        return value.formatted(.number.precision(.fractionLength(digits)).locale(locale)) + " pt/" + symbol
    }
}
