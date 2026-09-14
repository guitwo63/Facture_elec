import Foundation

public enum OrderXProfile: String, Codable, CaseIterable {
    case basic = "BASIC"
    case comfort = "COMFORT"
    case extended = "EXTENDED"

    public var urn: String {
        switch self {
        case .basic: return "urn:order-x.eu:1p0:basic"
        case .comfort: return "urn:order-x.eu:1p0:comfort"
        case .extended: return "urn:order-x.eu:1p0:extended"
        }
    }

    public var conformanceLevel: String {
        switch self {
        case .basic: return "BASIC"
        case .comfort: return "COMFORT"
        case .extended: return "EXTENDED"
        }
    }
}

public enum OrderTypeCode: String, Codable, CaseIterable {
    case order = "220"
    case orderChange = "221"
    case orderResponse = "222"

    public var label: String {
        switch self {
        case .order: return "Commande (220)"
        case .orderChange: return "Modification de commande (221)"
        case .orderResponse: return "Réponse à commande (222)"
        }
    }
}

public enum OrderStatus: String, Codable, CaseIterable {
    case draft
    case issued
    case sentToSupplier
    case accepted
    case amended
    case rejected
    case cancelled
    case confirmed

    public var label: String {
        switch self {
        case .draft: return "Brouillon"
        case .issued: return "Émise"
        case .sentToSupplier: return "Transmise au fournisseur"
        case .accepted: return "Acceptée par le fournisseur"
        case .amended: return "Modifiée"
        case .rejected: return "Rejetée par le fournisseur"
        case .cancelled: return "Annulée"
        case .confirmed: return "Confirmée"
        }
    }

    public var systemImage: String {
        switch self {
        case .draft: return "doc"
        case .issued: return "doc.fill"
        case .sentToSupplier: return "paperplane.fill"
        case .accepted: return "checkmark.seal.fill"
        case .amended: return "pencil.line"
        case .rejected: return "xmark.octagon.fill"
        case .cancelled: return "minus.circle.fill"
        case .confirmed: return "checkmark.circle.fill"
        }
    }

    public var hexColor: String {
        switch self {
        case .draft: return "6E6E73"
        case .issued: return "2A6EBB"
        case .sentToSupplier: return "B07A2A"
        case .accepted: return "2E8B57"
        case .amended: return "8A4FBD"
        case .rejected: return "C0392B"
        case .cancelled: return "8C8C8C"
        case .confirmed: return "1E7E34"
        }
    }
}

public struct SalesOrder: Codable, Hashable, Identifiable {
    public var id: UUID
    public var number: String
    public var type: OrderTypeCode
    public var status: OrderStatus
    public var issueDate: Date
    public var requestedDeliveryDate: Date
    public var currency: String
    public var profile: OrderXProfile
    public var buyer: InvoiceParty
    public var seller: InvoiceParty
    public var buyerReference: String?
    public var quotationRef: String?
    public var contractRef: String?
    public var blanketOrderRef: String?
    public var previousOrderChangeRef: String?
    public var previousOrderResponseRef: String?
    public var lines: [InvoiceLine]
    public var notes: String?
    public var requestedResponseTypeCode: String
    public var companyID: UUID?

    public init(
        id: UUID = UUID(),
        number: String,
        type: OrderTypeCode = .order,
        status: OrderStatus = .draft,
        issueDate: Date = Date(),
        requestedDeliveryDate: Date = Date().addingTimeInterval(15 * 86400),
        currency: String = "EUR",
        profile: OrderXProfile = .comfort,
        buyer: InvoiceParty,
        seller: InvoiceParty,
        buyerReference: String? = nil,
        quotationRef: String? = nil,
        contractRef: String? = nil,
        blanketOrderRef: String? = nil,
        previousOrderChangeRef: String? = nil,
        previousOrderResponseRef: String? = nil,
        lines: [InvoiceLine] = [],
        notes: String? = nil,
        requestedResponseTypeCode: String = "AC",
        companyID: UUID? = nil
    ) {
        self.id = id
        self.number = number
        self.type = type
        self.status = status
        self.issueDate = issueDate
        self.requestedDeliveryDate = requestedDeliveryDate
        self.currency = currency
        self.profile = profile
        self.buyer = buyer
        self.seller = seller
        self.buyerReference = buyerReference
        self.quotationRef = quotationRef
        self.contractRef = contractRef
        self.blanketOrderRef = blanketOrderRef
        self.previousOrderChangeRef = previousOrderChangeRef
        self.previousOrderResponseRef = previousOrderResponseRef
        self.lines = lines
        self.notes = notes
        self.requestedResponseTypeCode = requestedResponseTypeCode
        self.companyID = companyID
    }

    private enum CodingKeys: String, CodingKey {
        case id, number, type, status, issueDate, requestedDeliveryDate, currency, profile, buyer, seller
        case buyerReference, quotationRef, contractRef, blanketOrderRef, previousOrderChangeRef, previousOrderResponseRef
        case lines, notes, requestedResponseTypeCode, companyID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        number = try c.decodeIfPresent(String.self, forKey: .number) ?? ""
        type = try c.decodeIfPresent(OrderTypeCode.self, forKey: .type) ?? .order
        status = try c.decodeIfPresent(OrderStatus.self, forKey: .status) ?? .draft
        issueDate = try c.decodeIfPresent(Date.self, forKey: .issueDate) ?? Date()
        requestedDeliveryDate = try c.decodeIfPresent(Date.self, forKey: .requestedDeliveryDate) ?? Date().addingTimeInterval(15 * 86400)
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? "EUR"
        profile = try c.decodeIfPresent(OrderXProfile.self, forKey: .profile) ?? .comfort
        buyer = try c.decodeIfPresent(InvoiceParty.self, forKey: .buyer) ?? InvoiceParty(name: "", street: "", postcode: "", city: "")
        seller = try c.decodeIfPresent(InvoiceParty.self, forKey: .seller) ?? InvoiceParty(name: "", street: "", postcode: "", city: "")
        buyerReference = try c.decodeIfPresent(String.self, forKey: .buyerReference)
        quotationRef = try c.decodeIfPresent(String.self, forKey: .quotationRef)
        contractRef = try c.decodeIfPresent(String.self, forKey: .contractRef)
        blanketOrderRef = try c.decodeIfPresent(String.self, forKey: .blanketOrderRef)
        previousOrderChangeRef = try c.decodeIfPresent(String.self, forKey: .previousOrderChangeRef)
        previousOrderResponseRef = try c.decodeIfPresent(String.self, forKey: .previousOrderResponseRef)
        lines = try c.decodeIfPresent([InvoiceLine].self, forKey: .lines) ?? []
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        requestedResponseTypeCode = try c.decodeIfPresent(String.self, forKey: .requestedResponseTypeCode) ?? "AC"
        companyID = try c.decodeIfPresent(UUID.self, forKey: .companyID)
    }

    public var lineTotal: Double {
        lines.reduce(0) { $0 + $1.lineTotal }.rounded(toPlaces: 2)
    }

    public var vatBreakdown: [(rate: Double, basis: Double, amount: Double)] {
        var map: [Double: Double] = [:]
        for line in lines {
            map[line.vatRate, default: 0] += line.lineTotal
        }
        return map.map { (rate, basis) in
            let basisR = basis.rounded(toPlaces: 2)
            let amount = (basisR * rate / 100).rounded(toPlaces: 2)
            return (rate, basisR, amount)
        }.sorted { $0.rate < $1.rate }
    }

    public var taxTotal: Double {
        vatBreakdown.reduce(0) { $0 + $1.amount }.rounded(toPlaces: 2)
    }

    public var grandTotal: Double {
        (lineTotal + taxTotal).rounded(toPlaces: 2)
    }

    public func vatCategory(for rate: Double) -> String {
        if rate == 0 { return "Z" }
        return "S"
    }
}

public struct OrderStatusOverride: Codable, Hashable {
    public var id: String
    public var label: String
    public var systemImage: String
    public var hexColor: String

    public init(id: String, label: String, systemImage: String, hexColor: String) {
        self.id = id
        self.label = label
        self.systemImage = systemImage
        self.hexColor = hexColor
    }
}

public final class OrderStatusStore: ObservableObject {
    public static let shared = OrderStatusStore()

    @Published public var overrides: [OrderStatusOverride]

    private let defaults = UserDefaults.standard
    private let storageKey = "orderx.statuses.v1"

    public static var defaults: [OrderStatusOverride] {
        OrderStatus.allCases.map { s in
            OrderStatusOverride(id: s.rawValue, label: s.label, systemImage: s.systemImage, hexColor: s.hexColor)
        }
    }

    public init() {
        self.overrides = OrderStatusStore.defaults
        load()
    }

    public func load() {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([OrderStatusOverride].self, from: data),
           !decoded.isEmpty {
            var byID = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
            for d in OrderStatusStore.defaults where byID[d.id] == nil {
                byID[d.id] = d
            }
            overrides = OrderStatus.allCases.compactMap { byID[$0.rawValue] }
        }
    }

    public func save() {
        if let data = try? JSONEncoder().encode(overrides) {
            defaults.set(data, forKey: storageKey)
        }
    }

    public func reset() {
        overrides = OrderStatusStore.defaults
        defaults.removeObject(forKey: storageKey)
    }

    public func override(for status: OrderStatus) -> OrderStatusOverride {
        overrides.first { $0.id == status.rawValue } ?? OrderStatusOverride(id: status.rawValue, label: status.label, systemImage: status.systemImage, hexColor: status.hexColor)
    }
}
