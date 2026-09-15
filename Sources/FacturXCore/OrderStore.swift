import Foundation

public final class OrderStore: ObservableObject {
    public static let shared = OrderStore()

    @Published public var orders: [SalesOrder]
    public var defaultBuyerEntryID: UUID?
    @Published public var numberPrefix: String = "CD"
    @Published public var numberIncludeYear: Bool = true
    @Published public var numberStart: Int = 1
    @Published public var numberUseSeparator: Bool = true
    public weak var audit: AuditStore?
    public var actorName: String = "system"

    private let defaults = UserDefaults.standard
    private let env = AppEnvironment.shared
    private var storageKey: String { env.key("orderx.orders.v1") }
    private var buyerEntryKey: String { env.key("orderx.defaultbuyer.entryid.v1") }
    private var numPrefixKey: String { env.key("orderx.number.prefix.v1") }
    private var numYearKey: String { env.key("orderx.number.includeyear.v1") }
    private var numStartKey: String { env.key("orderx.number.start.v1") }
    private var numSepKey: String { env.key("orderx.number.useseparator.v1") }

    public init() {
        self.orders = []
        load()
    }

    public func load() {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([SalesOrder].self, from: data) {
            orders = decoded
        }
        defaultBuyerEntryID = defaults.string(forKey: buyerEntryKey).flatMap { UUID(uuidString: $0) }
        numberPrefix = defaults.string(forKey: numPrefixKey) ?? "CD"
        numberIncludeYear = defaults.object(forKey: numYearKey) as? Bool ?? true
        numberStart = defaults.object(forKey: numStartKey) as? Int ?? 1
        numberUseSeparator = defaults.object(forKey: numSepKey) as? Bool ?? true
    }

    public func save() {
        if let data = try? JSONEncoder().encode(orders) {
            defaults.set(data, forKey: storageKey)
        }
        if let id = defaultBuyerEntryID {
            defaults.set(id.uuidString, forKey: buyerEntryKey)
        } else {
            defaults.removeObject(forKey: buyerEntryKey)
        }
        defaults.set(numberPrefix, forKey: numPrefixKey)
        defaults.set(numberIncludeYear, forKey: numYearKey)
        defaults.set(numberStart, forKey: numStartKey)
        defaults.set(numberUseSeparator, forKey: numSepKey)
    }

    public func resolveDefaultBuyer(from directory: PartyDirectory) -> InvoiceParty? {
        guard let id = defaultBuyerEntryID,
              let entry = directory.entries.first(where: { $0.id == id }) else { return nil }
        var p = entry.party
        if let routing = entry.defaultRoutingAddress, routing.isActive {
            let composed = routing.composedAddress.trimmingCharacters(in: .whitespaces)
            if !composed.isEmpty {
                p.endpointID = composed
                p.endpointSchemeID = "0225"
            }
        }
        if let contact = entry.defaultContact, contact.isActive {
            p.contactName = contact.name.trimmingCharacters(in: .whitespaces).isEmpty ? nil : contact.name
            p.contactEmail = (contact.email?.trimmingCharacters(in: .whitespaces) ?? "").isEmpty ? nil : contact.email
            p.contactPhone = (contact.phone?.trimmingCharacters(in: .whitespaces) ?? "").isEmpty ? nil : contact.phone
        }
        return p
    }

    public func upsert(_ order: SalesOrder) {
        let isNew = !orders.contains(where: { $0.id == order.id })
        let previousStatus = orders.first(where: { $0.id == order.id })?.status
        if let idx = orders.firstIndex(where: { $0.id == order.id }) {
            orders[idx] = order
        } else {
            orders.insert(order, at: 0)
        }
        save()
        audit?.record(actor: actorName, action: isNew ? "order_created" : "order_updated", target: order.number,
                       objectType: .order, objectCode: order.number)
        if let prev = previousStatus, prev != order.status {
            audit?.recordStatusChange(actor: actorName, objectType: .order, objectCode: order.number,
                                      statusFrom: prev.label, statusTo: order.status.label)
        }
    }

    public func delete(_ order: SalesOrder) {
        orders.removeAll { $0.id == order.id }
        save()
        audit?.record(actor: actorName, action: "order_deleted", target: order.number,
                       objectType: .order, objectCode: order.number)
    }

    public func newDraft(directory: PartyDirectory? = nil, preferredBuyerEntryID: UUID? = nil, companyID: UUID? = nil) -> SalesOrder {
        let dir = directory ?? PartyDirectory.shared
        let buyerEntryID = preferredBuyerEntryID ?? defaultBuyerEntryID
        let buyer: InvoiceParty = {
            if let id = buyerEntryID, let entry = dir.entries.first(where: { $0.id == id }) {
                var p = entry.party
                if let routing = entry.defaultRoutingAddress, routing.isActive {
                    let composed = routing.composedAddress.trimmingCharacters(in: .whitespaces)
                    if !composed.isEmpty {
                        p.endpointID = composed
                        p.endpointSchemeID = "0225"
                    }
                }
                if let contact = entry.defaultContact, contact.isActive {
                    p.contactName = contact.name.trimmingCharacters(in: .whitespaces).isEmpty ? nil : contact.name
                    p.contactEmail = (contact.email?.trimmingCharacters(in: .whitespaces) ?? "").isEmpty ? nil : contact.email
                    p.contactPhone = (contact.phone?.trimmingCharacters(in: .whitespaces) ?? "").isEmpty ? nil : contact.phone
                }
                return p
            }
            return resolveDefaultBuyer(from: dir)
                ?? InvoiceParty(name: "", street: "", postcode: "", city: "")
        }()
        let seller = InvoiceParty(name: "", street: "", postcode: "", city: "")
        return SalesOrder(
            number: nextNumber(),
            buyer: buyer,
            seller: seller,
            lines: [InvoiceLine(name: "", quantity: 1, unitPrice: 0, vatRate: 20)],
            companyID: companyID
        )
    }

    public func nextNumber(prefix: String = "") -> String {
        let sep = numberUseSeparator ? "-" : ""
        let year = String(Calendar.current.component(.year, from: Date()))
        var built: [String] = []
        let textPrefix = prefix.isEmpty ? (numberPrefix.trimmingCharacters(in: .whitespaces)) : prefix.trimmingCharacters(in: .whitespaces)
        if !textPrefix.isEmpty {
            built.append(textPrefix)
            built.append(sep)
        }
        if numberIncludeYear {
            built.append(year)
            built.append(sep)
        }
        let headKey = built.joined()
        let paddedStart = max(1, numberStart)
        let existing = orders.filter { $0.number.hasPrefix(headKey) }.count
        let seq = paddedStart + existing
        let chrono = String(format: "%04d", seq)
        return headKey + chrono
    }

    public func previewNextNumber(prefix: String = "") -> String {
        let sep = numberUseSeparator ? "-" : ""
        let year = String(Calendar.current.component(.year, from: Date()))
        var built: [String] = []
        let textPrefix = prefix.isEmpty ? (numberPrefix.trimmingCharacters(in: .whitespaces)) : prefix.trimmingCharacters(in: .whitespaces)
        if !textPrefix.isEmpty {
            built.append(textPrefix)
            built.append(sep)
        }
        if numberIncludeYear {
            built.append(year)
            built.append(sep)
        }
        let headKey = built.joined()
        let chrono = String(format: "%04d", max(1, numberStart))
        return headKey + chrono
    }
}
