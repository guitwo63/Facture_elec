import Foundation

public struct InvoiceStatusOverride: Codable, Hashable, Identifiable {
    public var id: String
    public var label: String
    public var systemImage: String
    public var hexColor: String
    public var reformCode: String?
    public var transitionCodes: [String]

    public init(id: String, label: String, systemImage: String, hexColor: String, reformCode: String? = nil, transitionCodes: [String] = []) {
        self.id = id
        self.label = label
        self.systemImage = systemImage
        self.hexColor = hexColor
        self.reformCode = reformCode
        self.transitionCodes = transitionCodes
    }

    public var isReformStatus: Bool { reformCode != nil }
}

public final class InvoiceStatusStore: ObservableObject {
    public static let shared = InvoiceStatusStore()

    @Published public var overrides: [InvoiceStatusOverride]

    private let defaults = UserDefaults.standard
    private let env = AppEnvironment.shared
    private var storageKey: String { env.key("facturx.invoiceStatuses.v1") }

    public static var defaults: [InvoiceStatusOverride] {
        InvoiceStatus.allCases.map { s in
            InvoiceStatusOverride(
                id: s.rawValue,
                label: s.label,
                systemImage: s.systemImage,
                hexColor: s.hexColor,
                reformCode: InvoiceStatusStore.reformCode(for: s),
                transitionCodes: s.allowedTransitions().map { $0.rawValue }
            )
        }
    }

    private static func reformCode(for status: InvoiceStatus) -> String? {
        switch status {
        case .paid: return "fr:212"
        case .cancelled: return "fr:320"
        case .accepted: return "fr:310"
        case .rejected: return "fr:311"
        case .sentToPDP: return "200"
        default: return nil
        }
    }

    public init() {
        self.overrides = InvoiceStatusStore.defaults
        load()
    }

    public func load() {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([InvoiceStatusOverride].self, from: data),
           !decoded.isEmpty {
            var byID = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
            for d in InvoiceStatusStore.defaults where byID[d.id] == nil {
                byID[d.id] = d
            }
            overrides = InvoiceStatus.allCases.compactMap { byID[$0.rawValue] }
            let standard = Set(InvoiceStatus.allCases.map { $0.rawValue })
            overrides.append(contentsOf: decoded.filter { !standard.contains($0.id) })
        }
    }

    public func save() {
        if let data = try? JSONEncoder().encode(overrides) {
            defaults.set(data, forKey: storageKey)
        }
    }

    public func reset() {
        overrides = InvoiceStatusStore.defaults
        defaults.removeObject(forKey: storageKey)
    }

    public func remove(at idx: Int) {
        guard overrides.indices.contains(idx) else { return }
        guard !overrides[idx].isReformStatus else { return }
        overrides.remove(at: idx)
        save()
    }

    public func append(_ override: InvoiceStatusOverride) {
        overrides.append(override)
        save()
    }
}
