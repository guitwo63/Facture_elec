import Foundation

public enum BillingMode: String, Codable, CaseIterable {
    case b1 = "B1", s1 = "S1", m1 = "M1"
    case b2 = "B2", s2 = "S2", m2 = "M2"
    case s3 = "S3"
    case b4 = "B4", s4 = "S4", m4 = "M4"
    case s5 = "S5", s6 = "S6"
    case b7 = "B7", s7 = "S7"
    case b8 = "B8", s8 = "S8", m8 = "M8"
    case b9 = "B9", s9 = "S9", m9 = "M9"

    public var label: String {
        switch self {
        case .b1: return "Facturation papier (B1)"
        case .s1: return "Portail public de facturation (S1)"
        case .m1: return "Dématérialisation (M1)"
        case .b2: return "Facturation papier (B2)"
        case .s2: return "Portail public (S2)"
        case .m2: return "Dématérialisation (M2)"
        case .s3: return "Portail public (S3)"
        case .b4: return "Facturation papier (B4)"
        case .s4: return "Portail public (S4)"
        case .m4: return "Dématérialisation (M4)"
        case .s5: return "Portail public (S5)"
        case .s6: return "Portail public (S6)"
        case .b7: return "Facturation papier (B7)"
        case .s7: return "Portail public (S7)"
        case .b8: return "Facturation papier (B8)"
        case .s8: return "Portail public (S8)"
        case .m8: return "Dématérialisation (M8)"
        case .b9: return "Facturation papier (B9)"
        case .s9: return "Portail public (S9)"
        case .m9: return "Dématérialisation (M9)"
        }
    }
}

public struct InvoiceParty: Codable, Hashable {
    public var name: String
    public var street: String
    public var postcode: String
    public var city: String
    public var country: String
    public var vatNumber: String?
    public var siren: String?
    public var legalSchemeID: String
    public var contactName: String?
    public var contactEmail: String?
    public var contactPhone: String?
    public var endpointID: String?
    public var endpointSchemeID: String

    public init(
        name: String,
        street: String,
        postcode: String,
        city: String,
        country: String = "FR",
        vatNumber: String? = nil,
        siren: String? = nil,
        legalSchemeID: String = "0002",
        contactName: String? = nil,
        contactEmail: String? = nil,
        contactPhone: String? = nil,
        endpointID: String? = nil,
        endpointSchemeID: String = "FR:SIRENE"
    ) {
        self.name = name
        self.street = street
        self.postcode = postcode
        self.city = city
        self.country = country
        self.vatNumber = vatNumber
        self.siren = siren
        self.legalSchemeID = legalSchemeID
        self.contactName = contactName
        self.contactEmail = contactEmail
        self.contactPhone = contactPhone
        self.endpointID = endpointID
        self.endpointSchemeID = endpointSchemeID
    }
}

public struct InvoiceLine: Codable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var description: String?
    public var quantity: Double
    public var unit: String
    public var unitPrice: Double
    public var vatRate: Double

    public init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        quantity: Double,
        unit: String = "C62",
        unitPrice: Double,
        vatRate: Double = 20.0
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.quantity = quantity
        self.unit = unit
        self.unitPrice = unitPrice
        self.vatRate = vatRate
    }

    public var lineTotal: Double {
        (quantity * unitPrice).rounded(toPlaces: 2)
    }
}

public enum FacturXProfile: String, Codable, CaseIterable {
    case minimum = "MINIMUM"
    case basicWL = "BASIC WL"
    case basic = "BASIC"
    case en16931 = "EN 16931"
    case extended = "EXTENDED"

    public var urn: String {
        switch self {
        case .minimum: return "urn:factur-x.eu:1p0:minimum"
        case .basicWL: return "urn:factur-x.eu:1p0:basicwl"
        case .basic: return "urn:cen.eu:en16931:2017#compliant#urn:factur-x.eu:1p0:basic"
        case .en16931: return "urn:cen.eu:en16931:2017"
        case .extended: return "urn:cen.eu:en16931:2017#conformant#urn:factur-x.eu:1p0:extended"
        }
    }

    public var conformanceLevel: String {
        switch self {
        case .minimum: return "MINIMUM"
        case .basicWL: return "BASIC WL"
        case .basic: return "BASIC"
        case .en16931: return "EN 16931"
        case .extended: return "EXTENDED"
        }
    }
}

public enum InvoiceTypeCode: String, Codable, CaseIterable {
    case commercialInvoice = "380"
    case correction = "384"
    case creditNote = "381"

    public var label: String {
        switch self {
        case .commercialInvoice: return "Facture commerciale (380)"
        case .correction: return "Facture rectificative (384)"
        case .creditNote: return "Avoir (381)"
        }
    }
}

public struct Invoice: Codable, Hashable, Identifiable {
    public var id: UUID
    public var number: String
    public var type: InvoiceTypeCode
    public var issueDate: Date
    public var dueDate: Date
    public var currency: String
    public var profile: FacturXProfile
    public var seller: InvoiceParty
    public var buyer: InvoiceParty
    public var buyerReference: String?
    public var purchaseOrderRef: String?
    public var lines: [InvoiceLine]
    public var paymentIBAN: String?
    public var paymentBIC: String?
    public var paymentTerms: String?
    public var notes: String?
    public var billingMode: BillingMode
    public var legalNotePMT: String
    public var legalNotePMD: String
    public var legalNoteAAB: String

    public init(
        id: UUID = UUID(),
        number: String,
        type: InvoiceTypeCode = .commercialInvoice,
        issueDate: Date = Date(),
        dueDate: Date = Date().addingTimeInterval(30 * 86400),
        currency: String = "EUR",
        profile: FacturXProfile = .en16931,
        seller: InvoiceParty,
        buyer: InvoiceParty,
        buyerReference: String? = nil,
        purchaseOrderRef: String? = nil,
        lines: [InvoiceLine] = [],
        paymentIBAN: String? = nil,
        paymentBIC: String? = nil,
        paymentTerms: String? = nil,
        notes: String? = nil,
        billingMode: BillingMode = .m1,
        legalNotePMT: String = "Indemnité forfaitaire pour frais de recouvrement due à compter du 1er jour de retard : 40 EUR",
        legalNotePMD: String = "Taux d'intérêt des pénalités de retard : 3 fois le taux légal en vigueur",
        legalNoteAAB: String = "Escompte pour paiement anticipé : aucun"
    ) {
        self.id = id
        self.number = number
        self.type = type
        self.issueDate = issueDate
        self.dueDate = dueDate
        self.currency = currency
        self.profile = profile
        self.seller = seller
        self.buyer = buyer
        self.buyerReference = buyerReference
        self.purchaseOrderRef = purchaseOrderRef
        self.lines = lines
        self.paymentIBAN = paymentIBAN
        self.paymentBIC = paymentBIC
        self.paymentTerms = paymentTerms
        self.notes = notes
        self.billingMode = billingMode
        self.legalNotePMT = legalNotePMT
        self.legalNotePMD = legalNotePMD
        self.legalNoteAAB = legalNoteAAB
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

public extension Double {
    func rounded(toPlaces places: Int = 2) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded(.toNearestOrEven) / factor
    }

    func formatted(amount: Bool = true) -> String {
        let value = String(format: "%.2f", self)
        return value
    }
}
