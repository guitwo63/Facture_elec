import Foundation

public final class InvoiceStore: ObservableObject {
    public static let shared = InvoiceStore()

    @Published public var invoices: [Invoice]
    @Published public var myCompany: InvoiceParty

    private let defaults = UserDefaults.standard
    private let storageKey = "facturx.invoices.v1"
    private let companyKey = "facturx.mycompany.v1"

    public init() {
        self.invoices = []
        self.myCompany = InvoiceStore.defaultCompany()
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
    }

    public func save() {
        if let data = try? JSONEncoder().encode(invoices) {
            defaults.set(data, forKey: storageKey)
        }
        if let data = try? JSONEncoder().encode(myCompany) {
            defaults.set(data, forKey: companyKey)
        }
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

    public func newDraft() -> Invoice {
        Invoice(
            number: nextNumber(),
            seller: myCompany,
            buyer: InvoiceParty(name: "", street: "", postcode: "", city: ""),
            lines: [InvoiceLine(name: "", quantity: 1, unitPrice: 0, vatRate: 20)]
        )
    }

    public func nextNumber() -> String {
        let year = Calendar.current.component(.year, from: Date())
        let seq = invoices.filter { $0.number.hasPrefix("\(year)-") }.count + 1
        return String(format: "%d-%04d", year, seq)
    }

    static func defaultCompany() -> InvoiceParty {
        InvoiceParty(name: "", street: "", postcode: "", city: "")
    }
}
