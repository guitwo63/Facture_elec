import Foundation

public final class QuoteStore: ObservableObject {
    public static let shared = QuoteStore()

    @Published public var quotes: [Quote]
    @Published public var numberPrefix: String = "DEV"
    @Published public var numberIncludeYear: Bool = true
    @Published public var numberStart: Int = 1
    @Published public var numberUseSeparator: Bool = true
    public weak var audit: AuditStore?
    public var actorName: String = "system"

    private let defaults = UserDefaults.standard
    private let env = AppEnvironment.shared
    private var storageKey: String { env.key("facturx.quotes.v1") }
    private var numPrefixKey: String { env.key("facturx.quotes.number.prefix.v1") }
    private var numYearKey: String { env.key("facturx.quotes.number.includeyear.v1") }
    private var numStartKey: String { env.key("facturx.quotes.number.start.v1") }
    private var numSepKey: String { env.key("facturx.quotes.number.useseparator.v1") }

    public init() {
        self.quotes = []
        load()
    }

    public func load() {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([Quote].self, from: data) {
            quotes = decoded
        }
        numberPrefix = defaults.string(forKey: numPrefixKey) ?? "DEV"
        numberIncludeYear = defaults.object(forKey: numYearKey) as? Bool ?? true
        numberStart = defaults.object(forKey: numStartKey) as? Int ?? 1
        numberUseSeparator = defaults.object(forKey: numSepKey) as? Bool ?? true
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
        defaults.set(numberPrefix, forKey: numPrefixKey)
        defaults.set(numberIncludeYear, forKey: numYearKey)
        defaults.set(numberStart, forKey: numStartKey)
        defaults.set(numberUseSeparator, forKey: numSepKey)
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

    private func headKey(prefix: String) -> String {
        let sep = numberUseSeparator ? "-" : ""
        let year = String(Calendar.current.component(.year, from: Date()))
        var built: [String] = []
        let textPrefix = prefix.isEmpty ? numberPrefix.trimmingCharacters(in: .whitespaces) : prefix.trimmingCharacters(in: .whitespaces)
        if !textPrefix.isEmpty {
            built.append(textPrefix)
            built.append(sep)
        }
        if numberIncludeYear {
            built.append(year)
            built.append(sep)
        }
        return built.joined()
    }

    /// Un devis sans `companyID` n'est comptée que dans le chrono sans-société —
    /// même règle que `InvoiceStore.matchesScope`/`OrderStore.matchesScope`.
    private func matchesScope(_ quote: Quote, companyID: UUID?) -> Bool {
        if quote.companyID == companyID { return true }
        if quote.companyID == nil && companyID == nil { return true }
        return false
    }

    /// Basé sur le plus haut numéro déjà utilisé, pas sur un compte de devis existants —
    /// voir `InvoiceStore.nextSequence` pour le bug de doublon que ça évite (un compte se
    /// décale dès qu'un devis est supprimé).
    private func nextSequence(headKey: String, companyID: UUID?) -> Int {
        let paddedStart = max(1, numberStart)
        let matching = quotes.filter { $0.number.hasPrefix(headKey) && matchesScope($0, companyID: companyID) }
        let maxExistingSeq = matching.compactMap { Int($0.number.dropFirst(headKey.count)) }.max() ?? (paddedStart - 1)
        return max(paddedStart, maxExistingSeq + 1)
    }

    /// `companyID` scope le compteur, comme pour les factures et les commandes ;
    /// le format (préfixe, année, séparateur, numéro de début) est configurable
    /// comme pour les commandes, au lieu du format "DEV-AAAA-NNN" figé.
    public func nextNumber(prefix: String = "", companyID: UUID? = nil) -> String {
        let headKey = self.headKey(prefix: prefix)
        let chrono = String(format: "%04d", nextSequence(headKey: headKey, companyID: companyID))
        return headKey + chrono
    }

    public func previewNextNumber(prefix: String = "", companyID: UUID? = nil) -> String {
        let headKey = self.headKey(prefix: prefix)
        let chrono = String(format: "%04d", nextSequence(headKey: headKey, companyID: companyID))
        return headKey + chrono
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
