import Foundation

public final class InvoiceStore: ObservableObject {
    public static let shared = InvoiceStore()

    @Published public var invoices: [Invoice]
    @Published public var myCompany: InvoiceParty
    public var defaultSellerEntryID: UUID?

    private let defaults = UserDefaults.standard
    private let storageKey = "facturx.invoices.v1"
    private let companyKey = "facturx.mycompany.v1"
    private let sellerEntryKey = "facturx.defaultseller.entryid.v1"

    public init() {
        self.invoices = []
        self.myCompany = InvoiceStore.defaultCompany()
        self.defaultSellerEntryID = nil
        load()
    }

    public func load() {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([Invoice].self, from: data) {
            invoices = decoded
        }
        if let data = defaults.data(forKey: companyKey),
           let decoded = try? JSONDecoder().decode(InvoiceParty.self, from: data) {
            myCompany = decoded
        }
        defaultSellerEntryID = defaults.string(forKey: sellerEntryKey).flatMap { UUID(uuidString: $0) }
    }

    public func save() {
        if let data = try? JSONEncoder().encode(invoices) {
            defaults.set(data, forKey: storageKey)
        }
        if let data = try? JSONEncoder().encode(myCompany) {
            defaults.set(data, forKey: companyKey)
        }
        if let id = defaultSellerEntryID {
            defaults.set(id.uuidString, forKey: sellerEntryKey)
        } else {
            defaults.removeObject(forKey: sellerEntryKey)
        }
    }

    public func resolveDefaultSeller(from directory: PartyDirectory) -> InvoiceParty? {
        guard let id = defaultSellerEntryID,
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

    public func upsert(_ invoice: Invoice) {
        if let idx = invoices.firstIndex(where: { $0.id == invoice.id }) {
            invoices[idx] = invoice
        } else {
            invoices.insert(invoice, at: 0)
        }
        save()
    }

    public func delete(_ invoice: Invoice) {
        invoices.removeAll { $0.id == invoice.id }
        save()
    }

    public func newDraft(directory: PartyDirectory? = nil) -> Invoice {
        let dir = directory ?? PartyDirectory.shared
        let seller = resolveDefaultSeller(from: dir) ?? myCompany
        return Invoice(
            number: nextNumber(),
            seller: seller,
            buyer: InvoiceParty(name: "", street: "", postcode: "", city: ""),
            lines: [InvoiceLine(name: "", quantity: 1, unitPrice: 0, vatRate: 20)],
            paymentIBAN: seller.iban,
            paymentBIC: seller.bic,
            paymentTerms: seller.paymentTerms
        )
    }

    public func newCreditNote(from invoice: Invoice) -> Invoice {
        var credit = invoice
        credit.id = UUID()
        credit.number = nextNumber(prefix: "AV")
        credit.type = .creditNote
        credit.status = .draft
        credit.issueDate = Date()
        credit.dueDate = Date()
        credit.purchaseOrderRef = nil
        credit.precedingInvoiceRef = invoice.number
        credit.precedingInvoiceDate = invoice.issueDate
        credit.notes = "Avoir relatif à la facture \(invoice.number)"
        credit.lines = invoice.lines.map { line in
            var l = line
            l.id = UUID()
            return l
        }
        return credit
    }

    public func nextNumber(prefix: String = "") -> String {
        let year = Calendar.current.component(.year, from: Date())
        let key = "\(year)-\(prefix)"
        let seq = invoices.filter { $0.number.hasPrefix(key) }.count + 1
        let p = prefix.isEmpty ? "" : "\(prefix)"
        return String(format: "%d-%@%04d", year, p, seq)
    }



    static func defaultCompany() -> InvoiceParty {
        InvoiceParty(name: "", street: "", postcode: "", city: "")
    }
}
