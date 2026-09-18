import Foundation

public final class QuoteStore: ObservableObject {
    public static let shared = QuoteStore()

    @Published public var quotes: [Quote]
    public weak var audit: AuditStore?
    public var actorName: String = "system"

    private let defaults = UserDefaults.standard
    private let env = AppEnvironment.shared
    private var storageKey: String { env.key("facturx.quotes.v1") }

    public init() {
        self.quotes = []
        load()
    }

    public func load() {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([Quote].self, from: data) {
            quotes = decoded
        }
        fixInconsistentVATCategories()
    }

    /// Voir `InvoiceStore.fixInconsistentVATCategories()` — même correction. Un devis n'émet
    /// pas de XML lui-même, mais toInvoice()/toOrder() recopient les lignes telles quelles.
    private func fixInconsistentVATCategories() {
        var changed = false
        for idx in quotes.indices {
            for lineIdx in quotes[idx].lines.indices {
                let line = quotes[idx].lines[lineIdx]
                if line.vatCategory != .standard && line.vatRate != 0 {
                    quotes[idx].lines[lineIdx].vatCategory = .standard
                    quotes[idx].lines[lineIdx].vatExemptionReason = nil
                    changed = true
                }
            }
        }
        if changed { save() }
    }

    public func save() {
        if let data = try? JSONEncoder().encode(quotes) {
            defaults.set(data, forKey: storageKey)
        }
    }

    public func upsert(_ quote: Quote) {
        let isNew = !quotes.contains(where: { $0.id == quote.id })
        let previousStatus = quotes.first(where: { $0.id == quote.id })?.status
        if let idx = quotes.firstIndex(where: { $0.id == quote.id }) {
            quotes[idx] = quote
        } else {
            quotes.insert(quote, at: 0)
        }
        save()
        if let prev = previousStatus, prev != quote.status {
            audit?.recordStatusChange(actor: actorName, objectType: .quote, objectCode: quote.number,
                                       statusFrom: prev.label, statusTo: quote.status.label, details: "devis")
        } else {
            audit?.record(actor: actorName, action: isNew ? "quote_created" : "quote_updated",
                           target: quote.number, details: "devis", objectType: .quote, objectCode: quote.number)
        }
    }

    public func delete(_ quote: Quote) {
        quotes.removeAll { $0.id == quote.id }
        save()
        audit?.record(actor: actorName, action: "quote_deleted", target: quote.number, details: "devis",
                       objectType: .quote, objectCode: quote.number)
    }

    public func newDraft(seller: InvoiceParty, companyID: UUID? = nil) -> Quote {
        Quote(
            number: nextNumber(companyID: companyID),
            seller: seller,
            buyer: InvoiceParty(name: "", street: "", postcode: "", city: ""),
            companyID: companyID,
            lines: [InvoiceLine(name: "", quantity: 1, unitPrice: 0, vatRate: 20)]
        )
    }

    public func nextNumber(companyID: UUID? = nil) -> String {
        let year = Calendar.current.component(.year, from: Date())
        let scoped = quotes.filter { companyID == nil || $0.companyID == companyID }
        let countThisYear = scoped.filter { Calendar.current.component(.year, from: $0.issueDate) == year }.count
        return "DEV-\(year)-\(String(format: "%03d", countThisYear + 1))"
    }

    public func duplicate(from quote: Quote) -> Quote {
        var copy = quote
        copy.id = UUID()
        copy.number = nextNumber(companyID: quote.companyID)
        copy.status = .draft
        copy.issueDate = Date()
        copy.convertedInvoiceNumber = nil
        return copy
    }
}
