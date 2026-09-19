import Foundation

public final class OrderStore: ObservableObject {
    public static let shared = OrderStore()

    @Published public var orders: [SalesOrder]
    public var defaultSellerEntryID: UUID?
    @Published public var numberPrefix: String = "CD"
    @Published public var numberIncludeYear: Bool = true
    @Published public var numberStart: Int = 1
    @Published public var numberUseSeparator: Bool = true
    /// Format de numérotation propre à une société — voir `InvoiceStore.numberFormatOverrides`,
    /// même rôle et même structure partagée (`InvoiceNumberingFormat`).
    @Published public var numberFormatOverrides: [UUID: InvoiceNumberingFormat] = [:]
    public weak var audit: AuditStore?
    public var actorName: String = "system"

    private let defaults = UserDefaults.standard
    private let env = AppEnvironment.shared
    private var storageKey: String { env.key("orderx.orders.v1") }
    // Nom de clé historique conservé tel quel (valeur déjà persistée chez les
    // utilisateurs) même si la propriété qu'elle alimente a été renommée lors
    // de l'inversion buyer/seller — inutile de migrer un simple UUID de société.
    private var sellerEntryKey: String { env.key("orderx.defaultbuyer.entryid.v1") }
    // Migration one-shot : avant cette version, `buyer` désignait notre société
    // et `seller` le tiers — l'inverse de Devis/Facture. Voir `migrateBuyerSellerSemanticsIfNeeded()`.
    private var buyerSellerMigratedKey: String { env.key("orderx.buyerSellerSemantics.migrated.v1") }
    private var numPrefixKey: String { env.key("orderx.number.prefix.v1") }
    private var numYearKey: String { env.key("orderx.number.includeyear.v1") }
    private var numStartKey: String { env.key("orderx.number.start.v1") }
    private var numSepKey: String { env.key("orderx.number.useseparator.v1") }
    private var numOverridesKey: String { env.key("orderx.number.overrides.bysociety.v1") }

    public init() {
        self.orders = []
        load()
    }

    public func load() {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([SalesOrder].self, from: data) {
            orders = decoded
        }
        defaultSellerEntryID = defaults.string(forKey: sellerEntryKey).flatMap { UUID(uuidString: $0) }
        numberPrefix = defaults.string(forKey: numPrefixKey) ?? "CD"
        numberIncludeYear = defaults.object(forKey: numYearKey) as? Bool ?? true
        numberStart = defaults.object(forKey: numStartKey) as? Int ?? 1
        numberUseSeparator = defaults.object(forKey: numSepKey) as? Bool ?? true
        if let data = defaults.data(forKey: numOverridesKey),
           let decoded = try? JSONDecoder().decode([UUID: InvoiceNumberingFormat].self, from: data) {
            numberFormatOverrides = decoded
        }
        migrateBuyerSellerSemanticsIfNeeded()
        fixInconsistentVATCategories()
    }

    /// Voir `InvoiceStore.fixInconsistentVATCategories()` — même correction, même bug
    /// d'origine (sélecteurs de taux ne recalant pas la catégorie de TVA).
    private func fixInconsistentVATCategories() {
        var changed = false
        for idx in orders.indices {
            for lineIdx in orders[idx].lines.indices {
                let line = orders[idx].lines[lineIdx]
                if line.vatCategory != .standard && line.vatRate != 0 {
                    orders[idx].lines[lineIdx].vatCategory = .standard
                    orders[idx].lines[lineIdx].vatExemptionReason = nil
                    changed = true
                }
            }
        }
        if changed { save() }
    }

    /// Avant cette version, `SalesOrder.buyer` recevait notre société et `.seller`
    /// le tiers — l'inverse de Devis/Facture. Exécuté une seule fois par poste :
    /// permute les deux champs sur toutes les commandes déjà persistées puis pose
    /// un drapeau pour ne jamais rejouer (sinon une commande créée après la migration
    /// serait permutée à nouveau, à tort, au prochain lancement).
    private func migrateBuyerSellerSemanticsIfNeeded() {
        guard !defaults.bool(forKey: buyerSellerMigratedKey) else { return }
        for idx in orders.indices {
            orders[idx].swapBuyerAndSeller()
        }
        save()
        defaults.set(true, forKey: buyerSellerMigratedKey)
    }

    public func save() {
        if let data = try? JSONEncoder().encode(orders) {
            defaults.set(data, forKey: storageKey)
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

    /// Format effectif pour une société — voir `InvoiceStore.numberingFormat(for:)`.
    public func numberingFormat(for companyID: UUID?) -> InvoiceNumberingFormat {
        let effectiveID = companyID ?? PartyDirectory.shared.principaleSocieteID
        if let effectiveID, let override = numberFormatOverrides[effectiveID] { return override }
        return InvoiceNumberingFormat(prefix: numberPrefix, includeYear: numberIncludeYear, start: numberStart, useSeparator: numberUseSeparator)
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

    public func upsert(_ order: SalesOrder) {
        let isNew = !orders.contains(where: { $0.id == order.id })
        let previousStatus = orders.first(where: { $0.id == order.id })?.status
        if let idx = orders.firstIndex(where: { $0.id == order.id }) {
            orders[idx] = order
        } else {
            orders.insert(order, at: 0)
        }
        save()
        if let prev = previousStatus, prev != order.status {
            audit?.recordStatusChange(actor: actorName, objectType: .order, objectCode: order.number,
                                      statusFrom: prev.label, statusTo: order.status.label, companyID: order.companyID)
        } else {
            audit?.record(actor: actorName, action: isNew ? "order_created" : "order_updated", target: order.number,
                           objectType: .order, objectCode: order.number, companyID: order.companyID)
        }
    }

    public func delete(_ order: SalesOrder) {
        orders.removeAll { $0.id == order.id }
        save()
        audit?.record(actor: actorName, action: "order_deleted", target: order.number,
                       objectType: .order, objectCode: order.number, companyID: order.companyID)
    }

    public func newDraft(directory: PartyDirectory? = nil, preferredSellerEntryID: UUID? = nil, companyID: UUID? = nil) -> SalesOrder {
        let dir = directory ?? PartyDirectory.shared
        let sellerEntryID = preferredSellerEntryID ?? defaultSellerEntryID
        let seller: InvoiceParty = {
            if let id = sellerEntryID, let entry = dir.entries.first(where: { $0.id == id }) {
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
            return resolveDefaultSeller(from: dir)
                ?? InvoiceParty(name: "", street: "", postcode: "", city: "")
        }()
        let buyer = InvoiceParty(name: "", street: "", postcode: "", city: "")
        return SalesOrder(
            number: nextNumber(companyID: companyID),
            buyer: buyer,
            seller: seller,
            lines: [InvoiceLine(name: "", quantity: 1, unitPrice: 0, vatRate: 20)],
            companyID: companyID
        )
    }

    private func headKey(prefix: String, companyID: UUID?) -> String {
        let format = numberingFormat(for: companyID)
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

    /// Une commande sans `companyID` n'est comptée que dans le chrono sans-société
    /// (`companyID == nil`), pour ne pas mélanger les périmètres — même règle que
    /// pour `InvoiceStore.matchesScope`.
    private func matchesScope(_ order: SalesOrder, companyID: UUID?) -> Bool {
        if order.companyID == companyID { return true }
        if order.companyID == nil && companyID == nil { return true }
        return false
    }

    /// Le plus petit numéro libre à partir du numéro de départ, pas "plus haut numéro + 1" —
    /// voir `InvoiceStore.nextSequence` pour le détail (recycle le numéro d'une commande
    /// supprimée au lieu de le laisser à jamais inutilisé).
    private func nextSequence(headKey: String, companyID: UUID?) -> Int {
        let paddedStart = max(1, numberStart)
        let matching = orders.filter { $0.number.hasPrefix(headKey) && matchesScope($0, companyID: companyID) }
        let usedSeqs = Set(matching.compactMap { Int($0.number.dropFirst(headKey.count)) })
        var candidate = paddedStart
        while usedSeqs.contains(candidate) { candidate += 1 }
        return candidate
    }

    /// `companyID` scope désormais le compteur, comme pour les factures et les devis —
    /// avant, une seule séquence de commandes était partagée par toutes les sociétés,
    /// ce qui n'avait pas de sens dès qu'un compte gère plusieurs sociétés émettrices.
    public func nextNumber(prefix: String = "", companyID: UUID? = nil) -> String {
        let headKey = self.headKey(prefix: prefix, companyID: companyID)
        let chrono = String(format: "%04d", nextSequence(headKey: headKey, companyID: companyID))
        return headKey + chrono
    }

    public func previewNextNumber(prefix: String = "", companyID: UUID? = nil) -> String {
        let headKey = self.headKey(prefix: prefix, companyID: companyID)
        let chrono = String(format: "%04d", nextSequence(headKey: headKey, companyID: companyID))
        return headKey + chrono
    }
}
