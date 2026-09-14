import Foundation

// MARK: - AppEnvironment

public enum AppEnvironmentMode: String, Codable, CaseIterable {
    case test
    case production

    public var label: String { self == .test ? "Test (bac à sable)" : "Production" }
    public var shortLabel: String { self == .test ? "TEST" : "PROD" }
    public var keySuffix: String { self == .test ? "" : ".production" }
}

public final class AppEnvironment: ObservableObject {
    public static let shared = AppEnvironment()

    @Published public var mode: AppEnvironmentMode

    private let defaults = UserDefaults.standard
    private let modeKey = "facturx.env.mode.v1"

    public init() {
        let raw = UserDefaults.standard.string(forKey: "facturx.env.mode.v1")
        switch raw {
        case "production": mode = .production
        case "test": mode = .test
        default: mode = .test
        }
    }

    public func setMode(_ newMode: AppEnvironmentMode) {
        guard newMode != mode else { return }
        mode = newMode
        defaults.set(newMode.rawValue, forKey: modeKey)
    }

    public func key(_ base: String) -> String {
        base + mode.keySuffix
    }

    public var isTest: Bool { mode == .test }
    public var isProduction: Bool { mode == .production }
}
