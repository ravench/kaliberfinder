import Foundation

/// A value the tests build once per run and reuse: the synthetic photos several tests draw alike,
/// and the analyses of the real photos, which cost 20 to 30 s each on the CI simulator.
enum Once {
    private static var values: [String: Any] = [:]

    static func value<T>(_ key: String, _ make: () throws -> T) rethrows -> T {
        // `values[key] as? T` would read a missing key as a present nil where T is optional.
        if let stored = values[key], let value = stored as? T { return value }
        let value = try make()
        values[key] = value
        return value
    }

    static func value<T>(_ key: String, _ make: () async throws -> T) async rethrows -> T {
        if let stored = values[key], let value = stored as? T { return value }
        let value = try await make()
        values[key] = value
        return value
    }
}
