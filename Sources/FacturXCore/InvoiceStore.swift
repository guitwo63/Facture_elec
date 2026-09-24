import Foundation

/// Format de numérotation des factures : préfixe/année/séparateur/numéro de
/// début. Une société sans réglage propre (`InvoiceStore.numberFormatOverrides`)
/// utilise les 4 propriétés `number*` de `InvoiceStore` comme format par défaut
/// — ce qui préserve exactement le comportement d'avant l'ajout des réglages
/// par société (une seule société ⇒ rien ne change).
public struct InvoiceNumberingFormat: Codable, Hashable {
    public var prefix: String
    public var includeYear: Bool
    public var start: Int
    public var useSeparator: Bool

    public init(prefix: String = "", includeYear: Bool = true, start: Int = 1, useSeparator: Bool = true) {
        self.prefix = prefix
        self.includeYear = includeYear
        self.start = start
        self.useSeparator = useSeparator
    }

    private enum CodingKeys: String, CodingKey {
        case prefix, includeYear, start, useSeparator
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        prefix = try c.decodeIfPresent(String.self, forKey: .prefix) ?? ""
        includeYear = try c.decodeIfPresent(Bool.self, forKey: .includeYear) ?? true
        start = try c.decodeIfPresent(Int.self, forKey: .start) ?? 1
        useSeparator = try c.decodeIfPresent(Bool.self, forKey: .useSeparator) ?? true
    }
}

public final class InvoiceStore: ObservableObject {
    public static let shared = InvoiceStore()

    @Published public var invoices: [Invoice]
    @Published public var myCompany: InvoiceParty
    public var defaultSellerEntryID: UUID?
    @Published public var numberPrefix: String = ""
    @Published public var numberIncludeYear: Bool = true
    @Published public var numberStart: Int = 1
    @Published public var numberUseSeparator: Bool = true
    /// Format de numérotation propre à une société (BT-31-like scoping) : une société absente
    /// de ce dictionnaire utilise le format par défaut (`number*` ci-dessus).
    @Published public var numberFormatOverrides: [UUID: InvoiceNumberingFormat] = [:]
    public weak var audit: AuditStore?
    public var actorName: String = "system"
    /// Préréglages de conditions de paiement : l'échéance des factures créées ici (`newDraft`,
    /// `duplicate`, `newDeposit`, `newFinalSettlement`) suit celui de leurs conditions.
    public var paymentTermsPresets: PaymentTermsPresetStore = .shared

    private let defaults = AppPersistence.defaults
    private let env = AppEnvironment.shared
    private var storageKey: String { env.key("facturx.invoices.v1") }
    private var companyKey: String { env.key("facturx.mycompany.v1") }
    private var sellerEntryKey: String { env.key("facturx.defaultseller.entryid.v1") }
    private var numPrefixKey: String { env.key("facturx.number.prefix.v1") }
    private var numYearKey: String { env.key("facturx.number.includeyear.v1") }
    private var numStartKey: String { env.key("facturx.number.start.v1") }
    private var numSepKey: String { env.key("facturx.number.useseparator.v1") }
    private var numOverridesKey: String { env.key("facturx.number.overrides.bysociety.v1") }

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
        numberPrefix = defaults.string(forKey: numPrefixKey) ?? ""
        numberIncludeYear = defaults.object(forKey: numYearKey) as? Bool ?? true
        numberStart = defaults.object(forKey: numStartKey) as? Int ?? 1
        numberUseSeparator = defaults.object(forKey: numSepKey) as? Bool ?? true
        if let data = defaults.data(forKey: numOverridesKey),
           let decoded = try? JSONDecoder().decode([UUID: InvoiceNumberingFormat].self, from: data) {
            numberFormatOverrides = decoded
        }
        fixInconsistentVATCategories()
        replaceLegacyUnitCodesInDrafts()
    }

    /// Brouillons dont une ligne porte encore un ancien code d'unité, refusé par le Schematron
    /// (BR-CL-23) et proposé par le sélecteur jusqu'au 2026-09-24 (PCE « Pièce »…) : le code
    /// passe au code admis pour la même unité (`NormRefs.legacyUnitReplacements`). Une facture
    /// émise garde le code avec lequel elle est partie ; BR-CL-23 la signale. Idempotent,
    /// comme `fixInconsistentVATCategories()`.
    private func replaceLegacyUnitCodesInDrafts() {
        var changed = false
        for idx in invoices.indices where invoices[idx].status == .draft {
            if invoices[idx].lines.replaceLegacyUnitCodes() { changed = true }
        }
        if changed { save() }
    }

    /// Corrige les lignes dont la catégorie de TVA est restée non standard (ex. "Z") alors
    /// que le taux est non nul — séquelle du bug (corrigé le 2026-09-18) où certains
    /// sélecteurs de taux (assistant "Facture guidée", devis) ne recalaient pas la catégorie
    /// au changement de taux, produisant des factures rejetées par le validateur EN16931
    /// (BR-Z-05/BR-Z-09) sans que l'UI ne permette de voir/corriger la catégorie devenue
    /// incohérente (le sélecteur de catégorie n'est visible qu'à taux 0 %). Idempotent :
    /// rejoué à chaque chargement plutôt que gardé derrière un drapeau one-shot.
    private func fixInconsistentVATCategories() {
        var changed = false
        for idx in invoices.indices {
            for lineIdx in invoices[idx].lines.indices {
                let line = invoices[idx].lines[lineIdx]
                if line.vatCategory != .standard && line.vatRate != 0 {
                    invoices[idx].lines[lineIdx].vatCategory = .standard
                    invoices[idx].lines[lineIdx].vatExemptionReason = nil
                    changed = true
                }
            }
        }
        if changed { save() }
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
        defaults.set(numberPrefix, forKey: numPrefixKey)
        defaults.set(numberIncludeYear, forKey: numYearKey)
        defaults.set(numberStart, forKey: numStartKey)
        defaults.set(numberUseSeparator, forKey: numSepKey)
        if let data = try? JSONEncoder().encode(numberFormatOverrides) {
            defaults.set(data, forKey: numOverridesKey)
        }
    }

    /// Le format par défaut lui-même (« Toutes » dans Réglages > Application), sans aucune
    /// surcharge par société — pas même celle de la société principale.
    public var defaultNumberingFormat: InvoiceNumberingFormat {
        InvoiceNumberingFormat(prefix: numberPrefix, includeYear: numberIncludeYear, start: numberStart, useSeparator: numberUseSeparator)
    }

    /// Format effectif pour une société : son réglage propre s'il existe, sinon le format par
    /// défaut — une société n'hérite jamais du format de la société principale. Seul
    /// `companyID == nil` (document sans société) résout sur la société principale si une a
    /// été désignée (voir `PartyDirectory.principaleSocieteID`).
    public func numberingFormat(for companyID: UUID?) -> InvoiceNumberingFormat {
        let effectiveID = companyID ?? PartyDirectory.shared.principaleSocieteID
        if let effectiveID, let override = numberFormatOverrides[effectiveID] { return override }
        return defaultNumberingFormat
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
        let isNew = !invoices.contains(where: { $0.id == invoice.id })
        let previousStatus = invoices.first(where: { $0.id == invoice.id })?.status
        if let idx = invoices.firstIndex(where: { $0.id == invoice.id }) {
            invoices[idx] = invoice
        } else {
            invoices.insert(invoice, at: 0)
        }
        save()
        if let prev = previousStatus, prev != invoice.status {
            audit?.recordStatusChange(actor: actorName, objectType: .invoice, objectCode: invoice.number,
                                      statusFrom: prev.label, statusTo: invoice.status.label,
                                      details: invoice.type.isCreditNote ? "avoir" : "facture", companyID: invoice.companyID)
        } else {
            audit?.record(actor: actorName, action: isNew ? "invoice_created" : "invoice_updated",
                           target: invoice.number, details: invoice.type.isCreditNote ? "avoir" : "facture",
                           objectType: .invoice, objectCode: invoice.number, companyID: invoice.companyID)
        }
    }

    public func delete(_ invoice: Invoice) {
        invoices.removeAll { $0.id == invoice.id }
        save()
        audit?.record(actor: actorName, action: "invoice_deleted", target: invoice.number, details: invoice.type.isCreditNote ? "avoir" : "facture",
                       objectType: .invoice, objectCode: invoice.number, companyID: invoice.companyID)
    }

    public func newDraft(directory: PartyDirectory? = nil, companyID: UUID? = nil, preferredSellerEntryID: UUID? = nil) -> Invoice {
        let dir = directory ?? PartyDirectory.shared
        let sellerEntryID = preferredSellerEntryID ?? defaultSellerEntryID
        let sellerEntry: DirectoryEntry? = {
            if let id = sellerEntryID, let entry = dir.entries.first(where: { $0.id == id }) {
                return entry
            }
            return nil
        }()
        let seller: InvoiceParty = {
            if let entry = sellerEntry {
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
            return resolveDefaultSeller(from: dir) ?? myCompany
        }()
        // À défaut d'une condition propre à la société émettrice, "30 jours net" sert de
        // condition standard par défaut plutôt qu'un champ vide à chaque nouvelle facture.
        let defaultPaymentTerms = PaymentTermsPresetStore.defaults.first(where: { $0.id == "net30" })?.text ?? "Paiement à 30 jours"
        var draft = Invoice(
            number: nextNumber(companyID: companyID),
            profile: (sellerEntry?.profile ?? .en16931).forNewInvoice,
            seller: seller,
            buyer: InvoiceParty(name: "", street: "", postcode: "", city: ""),
            companyID: companyID,
            lines: [InvoiceLine(name: "", quantity: 1, unitPrice: 0, vatRate: 20)],
            paymentIBAN: seller.iban,
            paymentBIC: seller.bic,
            paymentTerms: seller.paymentTerms ?? defaultPaymentTerms
        )
        // L'échéance suit le préréglage de ces conditions s'il fixe un délai, comme quand on
        // le choisit dans l'éditeur : « 30 jours fin de mois » ne tombe pas sur les 30 jours
        // nets de l'échéance par défaut. Sans cela, l'éditeur afficherait « Personnalisé » dès
        // la création (voir `PaymentTermsPresetStore.matchingPreset(for:)`).
        if let preset = paymentTermsPresets.matchingPreset(for: draft.paymentTerms, companyID: companyID),
           preset.dueRule.computesDueDate {
            draft.dueDate = preset.dueRule.dueDate(from: draft.issueDate)
        }
        return draft
    }

    /// Échéance d'une facture tirée de `source` (copie, acompte, solde) et datée `issueDate`.
    /// Si la source suit un préréglage à délai (`PaymentTermsPresetStore.matchingPreset(for:)`),
    /// la nouvelle facture le suit aussi, depuis sa propre date : « 30 jours fin de mois » ne
    /// fait pas le même nombre de jours d'un mois à l'autre. Sinon, notamment pour une
    /// échéance saisie à la main (« Personnalisé »), elle garde le délai de la source.
    private func dueDate(forCopyOf source: Invoice, issuedOn issueDate: Date) -> Date {
        if let preset = paymentTermsPresets.matchingPreset(for: source), preset.dueRule.computesDueDate {
            return preset.dueRule.dueDate(from: issueDate)
        }
        return issueDate.addingTimeInterval(source.dueDate.timeIntervalSince(source.issueDate))
    }

    public func duplicate(from invoice: Invoice) -> Invoice {
        var copy = invoice
        copy.id = UUID()
        copy.number = nextNumber(companyID: invoice.companyID)
        copy.status = .draft
        copy.profile = invoice.profile.forNewInvoice
        copy.issueDate = Date()
        copy.dueDate = dueDate(forCopyOf: invoice, issuedOn: copy.issueDate)
        copy.precedingInvoiceRef = nil
        copy.precedingInvoiceDate = nil
        copy.linkedSettlementRef = nil
        copy.clearExchangeRateForNewDate()
        copy.lines = invoice.lines.map { line in
            var l = line
            l.id = UUID()
            return l
        }
        // La copie d'une facture émise avec un ancien code d'unité (PCE…) serait rejetée
        // (BR-CL-23) : le brouillon reçoit le code admis, l'original garde le sien. De même
        // pour l'avoir, l'acompte et le solde ci-dessous.
        copy.lines.replaceLegacyUnitCodes()
        return copy
    }

    public func newCreditNote(from invoice: Invoice) -> Invoice {
        var credit = invoice
        credit.id = UUID()
        credit.number = nextNumber(companyID: invoice.companyID)
        credit.type = .creditNote
        credit.status = .draft
        credit.profile = invoice.profile.forNewInvoice
        credit.issueDate = Date()
        credit.dueDate = Date()
        credit.purchaseOrderRef = nil
        credit.precedingInvoiceRef = invoice.number
        credit.precedingInvoiceDate = invoice.issueDate
        credit.linkedSettlementRef = nil
        // Le taux de change de la facture est gardé : l'avoir annule la TVA en euros qu'elle a
        // déclarée (même choix que le SaaS ARVERNX).
        credit.notes = "Avoir relatif à la facture \(invoice.number)"
        credit.lines = invoice.lines.map { line in
            var l = line
            l.id = UUID()
            return l
        }
        credit.lines.replaceLegacyUnitCodes()
        return credit
    }

    public func newDeposit(from invoice: Invoice) -> Invoice {
        var deposit = invoice
        deposit.id = UUID()
        deposit.number = nextNumber(companyID: invoice.companyID)
        deposit.type = .deposit
        deposit.status = .draft
        deposit.profile = invoice.profile.forNewInvoice
        deposit.issueDate = Date()
        deposit.dueDate = dueDate(forCopyOf: invoice, issuedOn: deposit.issueDate)
        deposit.precedingInvoiceRef = nil
        deposit.precedingInvoiceDate = nil
        deposit.linkedSettlementRef = nil
        deposit.clearExchangeRateForNewDate()
        deposit.notes = "Facture d'acompte"
        deposit.prepaidAmount = 0
        deposit.billingMode = invoice.billingMode.forDeposit
        deposit.lines.replaceLegacyUnitCodes()
        return deposit
    }

    public func newFinalSettlement(from invoice: Invoice, deposits: [Invoice]) -> Invoice {
        var final = invoice
        final.id = UUID()
        final.number = nextNumber(companyID: invoice.companyID)
        final.type = .finalSettlement
        final.status = .draft
        final.profile = invoice.profile.forNewInvoice
        final.issueDate = Date()
        final.dueDate = dueDate(forCopyOf: invoice, issuedOn: final.issueDate)
        final.precedingInvoiceRef = deposits.first?.number
        final.precedingInvoiceDate = deposits.first?.issueDate
        final.linkedSettlementRef = nil
        final.clearExchangeRateForNewDate()
        final.prepaidAmount = deposits.reduce(0) { $0 + $1.grandTotal }.rounded(toPlaces: 2)
        final.notes = "Facture de solde"
        final.billingMode = invoice.billingMode.forFinalSettlement
        final.lines.replaceLegacyUnitCodes()
        return final
    }

    private func headKey(prefix: String, format: InvoiceNumberingFormat) -> String {
        let sep = format.useSeparator ? "-" : ""
        let year = String(Calendar.current.component(.year, from: Date()))
        var built: [String] = []
        let textPrefix = prefix.isEmpty ? format.prefix.trimmingCharacters(in: .whitespaces) : prefix.trimmingCharacters(in: .whitespaces)
        if !textPrefix.isEmpty {
            built.append(textPrefix)
            built.append(sep)
        }
        if format.includeYear {
            built.append(year)
            built.append(sep)
        }
        return built.joined()
    }

    private func matchesScope(_ invoice: Invoice, companyID: UUID?) -> Bool {
        // La société émettrice (vendeur) est rattachée à une fiche annuaire dont l'id
        // correspond au companyID. Une facture sans companyID n'est comptée que dans
        // le chrono sans-société (companyID == nil), pour ne pas mélanger les périmètres.
        if invoice.companyID == companyID { return true }
        if invoice.companyID == nil && companyID == nil { return true }
        return false
    }

    /// Le plus petit numéro libre à partir du numéro de départ, pas "plus haut numéro + 1" :
    /// supprimer une facture du milieu de la séquence (brouillon abandonné, par ex.) libère
    /// son numéro, qui est recyclé pour la prochaine facture au lieu de rester à jamais
    /// inutilisé. Évite aussi le doublon que produisait l'ancien calcul par simple compte
    /// (numéro de départ + nombre de factures existantes) quand une facture de numéro plus
    /// élevé restait présente après suppression.
    private func nextSequence(headKey: String, companyID: UUID?, start: Int) -> Int {
        let paddedStart = max(1, start)
        let matching = invoices.filter { $0.number.hasPrefix(headKey) && matchesScope($0, companyID: companyID) }
        let usedSeqs = Set(matching.compactMap { Int($0.number.dropFirst(headKey.count)) })
        var candidate = paddedStart
        while usedSeqs.contains(candidate) { candidate += 1 }
        return candidate
    }

    public func nextNumber(prefix: String = "", companyID: UUID? = nil) -> String {
        let format = numberingFormat(for: companyID)
        let headKey = self.headKey(prefix: prefix, format: format)
        let chrono = String(format: "%04d", nextSequence(headKey: headKey, companyID: companyID, start: format.start))
        return headKey + chrono
    }

    /// `format` : prévisualise ce format précis plutôt que le format effectif de `companyID`
    /// — Réglages > Application montre ainsi le format par défaut qu'il affiche, alors que
    /// `companyID == nil` résoudrait sur la société principale.
    public func previewNextNumber(prefix: String = "", companyID: UUID? = nil, format: InvoiceNumberingFormat? = nil) -> String {
        let resolved = format ?? numberingFormat(for: companyID)
        let headKey = self.headKey(prefix: prefix, format: resolved)
        let chrono = String(format: "%04d", nextSequence(headKey: headKey, companyID: companyID, start: resolved.start))
        return headKey + chrono
    }



    static func defaultCompany() -> InvoiceParty {
        InvoiceParty(name: "", street: "", postcode: "", city: "")
    }
}
