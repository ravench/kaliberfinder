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

    /// "29.7 mm" or "1.169 in". Inches get 3 decimals, like US load data (2.800 in, 0.308 in).
    func format(_ mm: Double, locale: Locale = .current) -> String {
        let style: FloatingPointFormatStyle<Double> = self == .metric
            ? .number.precision(.fractionLength(0...2))
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
        let digits = to == .metric ? 2 : 3
        return to.value(fromMM: mm).formatted(.number.precision(.fractionLength(0...digits)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
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
        switch self {
        case .metric:
            return (0...max(0, Int(lengthMM.rounded(.down)))).map { i in
                RulerTick(mm: Double(i), level: i % 10 == 0 ? 4 : (i % 5 == 0 ? 2 : 0), label: i % 10 == 0 ? "\(i / 10)" : nil)
            }
        case .imperial:
            let step = Self.mmPerInch / 16
            let count = Int((lengthMM / step + 1e-9).rounded(.down))
            return (0...max(0, count)).map { i in
                let level = i % 16 == 0 ? 4 : (i % 8 == 0 ? 3 : (i % 4 == 0 ? 2 : (i % 2 == 0 ? 1 : 0)))
                return RulerTick(mm: Double(i) * step, level: level, label: i % 16 == 0 ? "\(i / 16)" : nil)
            }
        }
    }

    /// Ruler length in mm: the tallest cartridge plus 5 mm, rounded up to a whole cm or inch.
    func rulerLength(tallestMM: Double) -> Double {
        let unitMM = self == .metric ? 10 : Self.mmPerInch
        return ceil((tallestMM + 5) / unitMM) * unitMM
    }

    /// Screen scale for display, e.g. "6.32 pt/mm" or "160.5 pt/in". `precise` adds one decimal (calibration).
    func scaleText(pointsPerMM: Double, precise: Bool = false, locale: Locale = .current) -> String {
        let value = self == .metric ? pointsPerMM : pointsPerMM * Self.mmPerInch
        let digits = (self == .metric ? 2 : 1) + (precise ? 1 : 0)
        return value.formatted(.number.precision(.fractionLength(digits)).locale(locale)) + " pt/" + symbol
    }
}
