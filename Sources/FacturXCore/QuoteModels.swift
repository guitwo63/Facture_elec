import Foundation

/// Statut simple d'un devis : pas de moteur de transitions configurable comme
/// pour Invoice/Order, un devis n'a pas de cycle de vie SUPER PDP à respecter.
public enum QuoteStatus: String, Codable, CaseIterable {
    case draft
    case sent
    case accepted
    case refused
    case expired

    public var label: String {
        switch self {
        case .draft: return "Brouillon"
        case .sent: return "Envoyé"
        case .accepted: return "Accepté"
        case .refused: return "Refusé"
        case .expired: return "Expiré"
        }
    }

    public var systemImage: String {
        switch self {
        case .draft: return "pencil"
        case .sent: return "paperplane.fill"
        case .accepted: return "checkmark.circle.fill"
        case .refused: return "xmark.circle.fill"
        case .expired: return "clock.badge.exclamationmark.fill"
        }
    }

    public var hexColor: String {
        switch self {
        case .draft: return "#8E8E93"
        case .sent: return "#007AFF"
        case .accepted: return "#34C759"
        case .refused: return "#FF3B30"
        case .expired: return "#FF9500"
        }
    }

    public var locksQuote: Bool {
        self == .accepted || self == .refused
    }

    public func allowedTransitions() -> [QuoteStatus] {
        switch self {
        case .draft: return [.sent]
        case .sent: return [.accepted, .refused, .expired]
        case .accepted, .refused, .expired: return []
        }
    }
}

/// Un devis très proche d'Invoice : mêmes InvoiceLine, mêmes parties (InvoiceParty).
/// Se convertit en Invoice en recopiant directement les lignes, sans ressaisie.
public struct Quote: Codable, Hashable, Identifiable {
    public var id: UUID
    public var number: String
    public var status: QuoteStatus
    public var issueDate: Date
    public var validUntil: Date
    public var currency: String
    public var seller: InvoiceParty
    public var buyer: InvoiceParty
    public var companyID: UUID?
    public var lines: [InvoiceLine]
    public var notes: String?
    public var convertedInvoiceNumber: String?
    public var convertedOrderNumber: String?
    public var attachments: [Attachment]
    /// Distinct de `notes` : remarque interne à l'équipe, jamais incluse sur le document.
    public var internalComment: String?

    public init(
        id: UUID = UUID(),
        number: String,
        status: QuoteStatus = .draft,
        issueDate: Date = Date(),
        validUntil: Date = Date().addingTimeInterval(30 * 86400),
        currency: String = "EUR",
        seller: InvoiceParty,
        buyer: InvoiceParty,
        companyID: UUID? = nil,
        lines: [InvoiceLine] = [],
        notes: String? = nil,
        convertedInvoiceNumber: String? = nil,
        convertedOrderNumber: String? = nil,
        attachments: [Attachment] = [],
        internalComment: String? = nil
    ) {
        self.id = id
        self.number = number
        self.status = status
        self.issueDate = issueDate
        self.validUntil = validUntil
        self.currency = currency
        self.seller = seller
        self.buyer = buyer
        self.companyID = companyID
        self.lines = lines
        self.notes = notes
        self.convertedInvoiceNumber = convertedInvoiceNumber
        self.convertedOrderNumber = convertedOrderNumber
        self.attachments = attachments
        self.internalComment = internalComment
    }

    private enum CodingKeys: String, CodingKey {
        case id, number, status, issueDate, validUntil, currency, seller, buyer, companyID, lines, notes
        case convertedInvoiceNumber, convertedOrderNumber, attachments, internalComment
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        number = try c.decode(String.self, forKey: .number)
        status = try c.decodeIfPresent(QuoteStatus.self, forKey: .status) ?? .draft
        issueDate = try c.decodeIfPresent(Date.self, forKey: .issueDate) ?? Date()
        validUntil = try c.decodeIfPresent(Date.self, forKey: .validUntil) ?? Date().addingTimeInterval(30 * 86400)
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? "EUR"
        seller = try c.decode(InvoiceParty.self, forKey: .seller)
        buyer = try c.decode(InvoiceParty.self, forKey: .buyer)
        companyID = try c.decodeIfPresent(UUID.self, forKey: .companyID)
        lines = try c.decodeIfPresent([InvoiceLine].self, forKey: .lines) ?? []
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        convertedInvoiceNumber = try c.decodeIfPresent(String.self, forKey: .convertedInvoiceNumber)
        convertedOrderNumber = try c.decodeIfPresent(String.self, forKey: .convertedOrderNumber)
        attachments = try c.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
        internalComment = try c.decodeIfPresent(String.self, forKey: .internalComment)
    }

    public var lineTotal: Double {
        lines.reduce(0) { $0 + $1.lineTotal }.rounded(toPlaces: 2)
    }

    /// Un sous-total par couple (taux, catégorie) : voir `VATBreakdownEntry`.
    public var vatBreakdown: [VATBreakdownEntry] {
        VATBreakdownEntry.breakdown(of: lines)
    }

    public var taxTotal: Double {
        vatBreakdown.reduce(0) { $0 + $1.amount }.rounded(toPlaces: 2)
    }

    public var grandTotal: Double {
        (lineTotal + taxTotal).rounded(toPlaces: 2)
    }

    /// Calculé, pas stocké : un devis envoyé dont la validité est dépassée.
    public var isExpiredByDate: Bool {
        status == .sent && validUntil < Date()
    }

    public func toInvoice(number: String) -> Invoice {
        Invoice(
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
            lines: lines,
            paymentIBAN: seller.iban,
            paymentBIC: seller.bic,
            paymentTerms: seller.paymentTerms,
            notes: notes,
            billingMode: .m1
        )
    }

    /// Miroir de `toInvoice`, pour le parcours devis accepté → commande → facture
    /// (au lieu de facturer le devis directement, en court-circuitant la commande).
    /// `quotationRef` conserve la traçabilité vers le devis d'origine.
    public func toOrder(number: String) -> SalesOrder {
        SalesOrder(
            number: number,
            status: .draft,
            currency: currency,
            buyer: buyer,
            seller: seller,
            quotationRef: self.number,
            lines: lines,
            notes: notes,
            companyID: companyID
        )
    }
}
