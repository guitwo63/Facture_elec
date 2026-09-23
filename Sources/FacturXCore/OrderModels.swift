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
    case orderChange = "230"
    case orderResponse = "231"

    /// Order-X n'admet que 220, 230 et 231 (`ORDERX_code2type` de la bibliothèque de référence
    /// factur-x). Jusqu'au 2026-09-23, la modification et la réponse partaient en 221 et 222,
    /// « commande ouverte » et « commande ponctuelle » dans l'UNTDID 1001 : une commande
    /// enregistrée avec ces codes est relue en 230 / 231. Sans cette relecture, `OrderStore`,
    /// qui décode la liste d'un bloc, perdrait toutes les commandes.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "221": self = .orderChange
        case "222": self = .orderResponse
        default: self = OrderTypeCode(rawValue: raw) ?? .order
        }
    }

    public var label: String {
        switch self {
        case .order: return "Commande (220)"
        case .orderChange: return "Modification de commande (230)"
        case .orderResponse: return "Réponse à commande (231)"
        }
    }

    /// Nom du document dans les métadonnées XMP, comme la bibliothèque factur-x : en titre
    /// (« Order Change ») et, en majuscules, dans `fx:DocumentType` (« ORDER_CHANGE »).
    public var xmpName: String {
        switch self {
        case .order: return "Order"
        case .orderChange: return "Order Change"
        case .orderResponse: return "Order Response"
        }
    }
}

public enum OrderStatus: String, Codable, CaseIterable {
    case draft
    case issued
    case sentToSociete
    case accepted
    case amended
    case rejected
    case cancelled
    case confirmed

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "sentToSupplier": self = .sentToSociete
        default: self = OrderStatus(rawValue: raw) ?? .draft
        }
    }

    public var label: String {
        switch self {
        case .draft: return "Brouillon"
        case .issued: return "Émise"
        case .sentToSociete: return "Envoyée au client"
        case .accepted: return "Acceptée par le client"
        case .amended: return "Modifiée"
        case .rejected: return "Rejetée par le client"
        case .cancelled: return "Annulée"
        case .confirmed: return "Confirmée"
        }
    }

    public var systemImage: String {
        switch self {
        case .draft: return "doc"
        case .issued: return "doc.fill"
        case .sentToSociete: return "paperplane.fill"
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
        case .sentToSociete: return "B07A2A"
        case .accepted: return "2E8B57"
        case .amended: return "8A4FBD"
        case .rejected: return "C0392B"
        case .cancelled: return "8C8C8C"
        case .confirmed: return "1E7E34"
        }
    }

    /// Verrouille la commande en édition (comme `InvoiceStatus.locksInvoice`) une fois
    /// le cycle de vie arrivé à son terme.
    public var locksOrder: Bool {
        switch self {
        case .confirmed, .cancelled: return true
        default: return false
        }
    }

    /// Transitions par défaut du cycle de vie normé (avant toute personnalisation en
    /// Réglages > Statuts des commandes).
    public func allowedTransitions() -> [OrderStatus] {
        switch self {
        case .draft:
            return [.issued]
        case .issued:
            return [.sentToSociete, .cancelled]
        case .sentToSociete:
            return [.accepted, .rejected, .amended]
        case .accepted:
            return [.confirmed, .cancelled]
        case .amended:
            return [.sentToSociete, .cancelled]
        case .rejected:
            return [.amended, .cancelled]
        case .confirmed:
            return []
        case .cancelled:
            return []
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
    public var customStatusID: String?
    public var attachments: [Attachment]
    /// Distinct de `notes` : remarque interne à l'équipe, jamais incluse dans le XML généré.
    public var internalComment: String?

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
        companyID: UUID? = nil,
        customStatusID: String? = nil,
        attachments: [Attachment] = [],
        internalComment: String? = nil
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
        self.customStatusID = customStatusID
        self.attachments = attachments
        self.internalComment = internalComment
    }

    private enum CodingKeys: String, CodingKey {
        case id, number, type, status, issueDate, requestedDeliveryDate, currency, profile, buyer, seller
        case buyerReference, quotationRef, contractRef, blanketOrderRef, previousOrderChangeRef, previousOrderResponseRef
        case lines, notes, requestedResponseTypeCode, companyID, customStatusID, attachments, internalComment
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
        customStatusID = try c.decodeIfPresent(String.self, forKey: .customStatusID)
        companyID = try c.decodeIfPresent(UUID.self, forKey: .companyID)
        attachments = try c.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
        internalComment = try c.decodeIfPresent(String.self, forKey: .internalComment)
    }

    public var lineTotal: Double {
        lines.reduce(0) { $0 + $1.lineTotal }.rounded(toPlaces: 2)
    }

    public var vatBreakdown: [(rate: Double, category: VATCategory, exemptionReason: String?, basis: Double, amount: Double)] {
        struct Key: Hashable { let rate: Double; let category: VATCategory }
        var basisByKey: [Key: Double] = [:]
        var reasonByKey: [Key: String] = [:]
        for line in lines {
            let key = Key(rate: line.vatRate, category: line.vatCategory)
            basisByKey[key, default: 0] += line.lineTotal
            if reasonByKey[key] == nil,
               let reason = line.vatExemptionReason?.trimmingCharacters(in: .whitespaces), !reason.isEmpty {
                reasonByKey[key] = reason
            }
        }
        return basisByKey.map { (key, basis) in
            let basisR = basis.rounded(toPlaces: 2)
            let amount = (basisR * key.rate / 100).rounded(toPlaces: 2)
            return (key.rate, key.category, reasonByKey[key], basisR, amount)
        }.sorted { $0.rate < $1.rate }
    }

    public var taxTotal: Double {
        vatBreakdown.reduce(0) { $0 + $1.amount }.rounded(toPlaces: 2)
    }

    public var grandTotal: Double {
        (lineTotal + taxTotal).rounded(toPlaces: 2)
    }

    public func toInvoice(number: String) -> Invoice {
        let mappedLines = lines.map { line in
            InvoiceLine(
                id: line.id,
                name: line.name,
                description: line.description,
                quantity: line.quantity,
                unit: line.unit,
                unitPrice: line.unitPrice,
                vatRate: line.vatRate,
                orderReference: line.orderReference ?? self.number
            )
        }
        var invoice = Invoice(
            number: number,
            type: .commercialInvoice,
            status: .draft,
            issueDate: Date(),
            dueDate: Date().addingTimeInterval(30 * 86400),
            currency: currency,
            profile: .en16931,
            seller: seller,
            buyer: buyer,
            companyID: companyID,
            buyerReference: buyerReference,
            purchaseOrderRef: quotationRef,
            lines: mappedLines,
            paymentIBAN: seller.iban,
            paymentBIC: seller.bic,
            paymentTerms: seller.paymentTerms,
            notes: notes,
            billingMode: .m1
        )
        if let contractRef, !contractRef.trimmingCharacters(in: .whitespaces).isEmpty {
            invoice.contractRef = contractRef
        }
        return invoice
    }
}

public extension SalesOrder {
    /// Utilisé uniquement pour migrer des commandes créées avant l'inversion de
    /// sens de `buyer`/`seller` (`seller` = notre société, comme Devis/Facture,
    /// depuis cette migration) — jamais en fonctionnement normal.
    mutating func swapBuyerAndSeller() {
        let oldBuyer = buyer
        buyer = seller
        seller = oldBuyer
    }
}

public struct OrderStatusOverride: Codable, Hashable, Identifiable {
    public var id: String
    public var label: String
    public var systemImage: String
    public var hexColor: String
    public var transitionCodes: [String]

    public init(id: String, label: String, systemImage: String, hexColor: String, transitionCodes: [String] = []) {
        self.id = id
        self.label = label
        self.systemImage = systemImage
        self.hexColor = hexColor
        self.transitionCodes = transitionCodes
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, systemImage, hexColor, transitionCodes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        label = try c.decode(String.self, forKey: .label)
        systemImage = try c.decode(String.self, forKey: .systemImage)
        hexColor = try c.decode(String.self, forKey: .hexColor)
        // Nouveau champ : absent des données déjà persistées, donc décodé en tolérant
        // son absence (sinon le decode échoue et l'utilisateur perd ses personnalisations).
        transitionCodes = try c.decodeIfPresent([String].self, forKey: .transitionCodes) ?? []
    }

    private static let pdpKeys: Set<String> = [
        OrderStatus.sentToSociete.rawValue,
        OrderStatus.accepted.rawValue,
        OrderStatus.rejected.rawValue,
        OrderStatus.confirmed.rawValue,
        OrderStatus.cancelled.rawValue
    ]

    public var isPDPStatus: Bool { Self.pdpKeys.contains(id) }
}

public final class OrderStatusStore: ObservableObject {
    public static let shared = OrderStatusStore()

    @Published public var overrides: [OrderStatusOverride]
    /// Surcharge éparse par société (Réglages > Tables) — voir `SocietyScopedCatalog`.
    @Published public var overridesBySociety: [UUID: [OrderStatusOverride]] = [:]

    private let defaults = UserDefaults.standard
    private let env = AppEnvironment.shared
    private var storageKey: String { env.key("orderx.statuses.v1") }
    private var overridesBySocietyKey: String { env.key("orderx.statuses.bysociety.v1") }

    public static var defaults: [OrderStatusOverride] {
        OrderStatus.allCases.map { s in
            OrderStatusOverride(
                id: s.rawValue, label: s.label, systemImage: s.systemImage, hexColor: s.hexColor,
                transitionCodes: s.allowedTransitions().map { $0.rawValue }
            )
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
            let migrated = decoded.map { o -> OrderStatusOverride in
                var v = o
                if v.id == "sentToSupplier" { v.id = OrderStatus.sentToSociete.rawValue }
                return v
            }
            var byID = Dictionary(uniqueKeysWithValues: migrated.map { ($0.id, $0) })
            for d in OrderStatusStore.defaults where byID[d.id] == nil {
                byID[d.id] = d
            }
            overrides = OrderStatus.allCases.compactMap { byID[$0.rawValue] }
        }
        if let data = defaults.data(forKey: overridesBySocietyKey),
           let decoded = try? JSONDecoder().decode([UUID: [OrderStatusOverride]].self, from: data) {
            overridesBySociety = decoded
        }
    }

    public func save() {
        if let data = try? JSONEncoder().encode(overrides) {
            defaults.set(data, forKey: storageKey)
        }
        if let data = try? JSONEncoder().encode(overridesBySociety) {
            defaults.set(data, forKey: overridesBySocietyKey)
        }
    }

    /// Commence (ou remplace) la personnalisation de ce statut pour cette société.
    public func setOverride(_ override: OrderStatusOverride, companyID: UUID) {
        var list = overridesBySociety[companyID] ?? []
        if let idx = list.firstIndex(where: { $0.id == override.id }) {
            list[idx] = override
        } else {
            list.append(override)
        }
        overridesBySociety[companyID] = list
        save()
    }

    /// Revient au réglage global pour ce statut sur cette société.
    public func removeOverride(for status: OrderStatus, companyID: UUID) {
        overridesBySociety[companyID]?.removeAll { $0.id == status.rawValue }
        if overridesBySociety[companyID]?.isEmpty == true {
            overridesBySociety.removeValue(forKey: companyID)
        }
        save()
    }

    public func reset() {
        overrides = OrderStatusStore.defaults
        defaults.removeObject(forKey: storageKey)
    }

    public func remove(at idx: Int) {
        guard overrides.indices.contains(idx) else { return }
        guard !overrides[idx].isPDPStatus else { return }
        overrides.remove(at: idx)
        save()
    }

    public func append(_ override: OrderStatusOverride) {
        overrides.append(override)
        save()
    }

    public func override(for status: OrderStatus) -> OrderStatusOverride {
        overrides.first { $0.id == status.rawValue } ?? OrderStatusOverride(id: status.rawValue, label: status.label, systemImage: status.systemImage, hexColor: status.hexColor)
    }

    /// Variante par société — voir `InvoiceStatusStore.override(for:companyID:)`.
    public func override(for status: OrderStatus, companyID: UUID?) -> OrderStatusOverride {
        let effectiveID = companyID ?? PartyDirectory.shared.principaleSocieteID
        if let effectiveID,
           let resolved = SocietyScopedCatalog.resolvedElement(id: status.rawValue, overrideForSociety: overridesBySociety[effectiveID]) {
            return resolved
        }
        return override(for: status)
    }

    public func override(for order: SalesOrder) -> OrderStatusOverride {
        var cid = order.customStatusID
        if cid == "sentToSupplier" { cid = OrderStatus.sentToSociete.rawValue }
        if let cid = cid {
            let effectiveID = order.companyID ?? PartyDirectory.shared.principaleSocieteID
            if let effectiveID,
               let custom = SocietyScopedCatalog.resolvedElement(id: cid, overrideForSociety: overridesBySociety[effectiveID]) {
                return custom
            }
            if let custom = overrides.first(where: { $0.id == cid }) {
                return custom
            }
        }
        return override(for: order.status, companyID: order.companyID)
    }

    /// Transitions autorisées depuis un statut donné, lues depuis la configuration
    /// (paramétrable dans Réglages > Statuts des commandes). Un administrateur peut
    /// en plus forcer n'importe quel autre statut standard ou personnalisé.
    public func allowedTransitions(from status: OrderStatus, isAdmin: Bool) -> [OrderStatus] {
        allowedTransitions(from: status, companyID: nil, isAdmin: isAdmin)
    }

    /// Variante par société — voir `InvoiceStatusStore.allowedTransitions(from:companyID:isAdmin:)`.
    public func allowedTransitions(from status: OrderStatus, companyID: UUID?, isAdmin: Bool) -> [OrderStatus] {
        let configured = override(for: status, companyID: companyID).transitionCodes.compactMap { OrderStatus(rawValue: $0) }
        guard isAdmin else { return configured }
        var extended = configured
        for s in OrderStatus.allCases where s != status && !extended.contains(s) {
            extended.append(s)
        }
        return extended
    }

    /// Statuts personnalisés (hors cycle standard) — pour laisser l'admin les
    /// atteindre malgré l'absence de transition configurée (parité avec l'ancien
    /// sélecteur libre).
    public var customStatuses: [OrderStatusOverride] {
        let standard = Set(OrderStatus.allCases.map { $0.rawValue })
        return overrides.filter { !standard.contains($0.id) }
    }
}
