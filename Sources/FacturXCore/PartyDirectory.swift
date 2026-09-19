import Foundation

public enum DirectoryEntryKind: String, Codable, CaseIterable {
    case client
    case societe
    case fournisseur
    case interco
    /// Ancien cas "Client / Fournisseur" d'avant le multi-sélecteur — conservé uniquement
    /// pour décoder les anciennes données (`DirectoryEntry.kind` au singulier) et les
    /// anciennes préférences de couleur ; jamais proposé à la sélection ni assigné à un
    /// nouveau tiers (voir `DirectoryEntryKind.selectable`). Un tiers "both" existant est
    /// développé en `[.client, .fournisseur]` dès la lecture — voir `DirectoryEntry.init(from:)`.
    case both

    public var label: String {
        switch self {
        case .client: return "Client"
        case .societe: return "Société"
        case .fournisseur: return "Fournisseur"
        case .interco: return "Interco"
        case .both: return "Client / Fournisseur"
        }
    }

    public var defaultHexColor: String {
        switch self {
        case .client: return "2A6EBB"
        case .societe: return "2E8B57"
        case .fournisseur: return "B07A2A"
        case .interco: return "1E8A8A"
        case .both: return "8A4FBD"
        }
    }

    /// Les types proposés à la sélection sur un tiers — exclut `.both`, remplacé par la
    /// combinaison `.client` + `.fournisseur` depuis le passage au multi-sélecteur.
    public static var selectable: [DirectoryEntryKind] {
        allCases.filter { $0 != .both }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = DirectoryEntryKind(rawValue: raw) ?? .client
    }
}

public enum RoutingAddressFormat: String, Codable, CaseIterable {
    case siren
    case sirenSiret
    case sirenSuffixe
    case sirenSiretCodeRoutage

    public var label: String {
        switch self {
        case .siren: return "SIREN"
        case .sirenSiret: return "SIREN_SIRET"
        case .sirenSuffixe: return "SIREN_Suffixe"
        case .sirenSiretCodeRoutage: return "SIREN_SIRET_CodeRoutage"
        }
    }

    public var help: String {
        switch self {
        case .siren: return "Adresse de niveau unité légale (9 chiffres)"
        case .sirenSiret: return "Adresse d'établissement (14 chiffres)"
        case .sirenSuffixe: return "Suffixe rattaché au SIREN (ex. SIREN_SUFFIXE)"
        case .sirenSiretCodeRoutage: return "Code routage rattaché au SIRET (ex. SIREN_SIRET_CODE)"
        }
    }
}

public struct PartyRoutingAddress: Codable, Hashable, Identifiable {
    public var id: UUID
    public var format: RoutingAddressFormat
    public var siren: String
    public var siret: String?
    public var suffixe: String?
    public var codeRoutage: String?
    public var label: String?
    public var isActive: Bool
    public var isDefault: Bool

    public init(
        id: UUID = UUID(),
        format: RoutingAddressFormat = .siren,
        siren: String = "",
        siret: String? = nil,
        suffixe: String? = nil,
        codeRoutage: String? = nil,
        label: String? = nil,
        isActive: Bool = true,
        isDefault: Bool = false
    ) {
        self.id = id
        self.format = format
        self.siren = siren
        self.siret = siret
        self.suffixe = suffixe
        self.codeRoutage = codeRoutage
        self.label = label
        self.isActive = isActive
        self.isDefault = isDefault
    }

    public var composedAddress: String {
        switch format {
        case .siren:
            return siren
        case .sirenSiret:
            return [siren, siret].compactMap { $0?.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }.joined(separator: "_")
        case .sirenSuffixe:
            return [siren, suffixe].compactMap { $0?.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }.joined(separator: "_")
        case .sirenSiretCodeRoutage:
            return [siren, siret, codeRoutage].compactMap { $0?.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }.joined(separator: "_")
        }
    }

    public var displayLabel: String {
        let lbl = label?.trimmingCharacters(in: .whitespaces) ?? ""
        let status = isActive ? "active" : "inactive"
        return lbl.isEmpty ? "\(composedAddress) (\(status))" : "\(lbl) — \(composedAddress) (\(status))"
    }

    private enum CodingKeys: String, CodingKey {
        case id, format, siren, siret, suffixe, codeRoutage, label, isActive, isDefault
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        format = try c.decodeIfPresent(RoutingAddressFormat.self, forKey: .format) ?? .siren
        siren = try c.decodeIfPresent(String.self, forKey: .siren) ?? ""
        siret = try c.decodeIfPresent(String.self, forKey: .siret)
        suffixe = try c.decodeIfPresent(String.self, forKey: .suffixe)
        codeRoutage = try c.decodeIfPresent(String.self, forKey: .codeRoutage)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
    }
}

public struct PartyContact: Codable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var email: String?
    public var phone: String?
    public var label: String?
    public var isActive: Bool
    public var isDefault: Bool

    public init(
        id: UUID = UUID(),
        name: String = "",
        email: String? = nil,
        phone: String? = nil,
        label: String? = nil,
        isActive: Bool = true,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.phone = phone
        self.label = label
        self.isActive = isActive
        self.isDefault = isDefault
    }

    public var displayLine: String {
        var parts: [String] = []
        let n = name.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { parts.append(n) }
        if let e = email?.trimmingCharacters(in: .whitespaces), !e.isEmpty { parts.append(e) }
        if let p = phone?.trimmingCharacters(in: .whitespaces), !p.isEmpty { parts.append(p) }
        return parts.joined(separator: " • ")
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, email, phone, label, isActive, isDefault
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        email = try c.decodeIfPresent(String.self, forKey: .email)
        phone = try c.decodeIfPresent(String.self, forKey: .phone)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
    }
}

public struct DirectoryEntry: Codable, Hashable, Identifiable {
    public var id: UUID
    /// Un tiers peut cumuler plusieurs types (ex. Client + Interco) depuis le passage au
    /// multi-sélecteur — voir `DirectoryEntryKind.selectable`. Jamais vide en pratique
    /// (`init(from:)` retombe sur `[.client]` si rien n'est décodable).
    public var kinds: Set<DirectoryEntryKind>
    public var party: InvoiceParty
    public var companyID: UUID?
    public var note: String?
    public var routingAddresses: [PartyRoutingAddress]
    public var contacts: [PartyContact]
    public var isArchived: Bool
    public var tagIDs: [UUID]
    public var logoData: Data?
    public var profile: FacturXProfile
    /// Vrai pour au plus une société du périmètre à la fois — sert de repli pour tous les
    /// réglages par société non personnalisés (voir `PartyDirectory.principaleSocieteID`).
    /// L'unicité est garantie par `PartyDirectory.setPrincipale(_:)`, pas par ce champ seul.
    public var isPrincipale: Bool

    public init(
        id: UUID = UUID(),
        kinds: Set<DirectoryEntryKind> = [.client],
        party: InvoiceParty,
        companyID: UUID? = nil,
        note: String? = nil,
        routingAddresses: [PartyRoutingAddress] = [],
        contacts: [PartyContact] = [],
        isArchived: Bool = false,
        tagIDs: [UUID] = [],
        logoData: Data? = nil,
        profile: FacturXProfile = .en16931,
        isPrincipale: Bool = false
    ) {
        self.id = id
        self.kinds = kinds.isEmpty ? [.client] : kinds
        self.party = party
        self.companyID = companyID
        self.note = note
        self.routingAddresses = routingAddresses
        self.contacts = contacts
        self.isArchived = isArchived
        self.tagIDs = tagIDs
        self.logoData = logoData
        self.profile = profile
        self.isPrincipale = isPrincipale
    }

    public var displayName: String {
        party.name.trimmingCharacters(in: .whitespaces).isEmpty
            ? "(sans nom)"
            : party.name
    }

    /// Libellés de tous les types cumulés, dans l'ordre de `DirectoryEntryKind.selectable`
    /// (donc jamais "Client / Fournisseur" : voir la note sur `.both`).
    public var kindsLabel: String {
        DirectoryEntryKind.selectable.filter { kinds.contains($0) }.map(\.label).joined(separator: " / ")
    }

    /// Vrai si ce tiers peut être payé (fournisseur ou société émettrice) — condition
    /// d'affichage des coordonnées bancaires sur sa fiche.
    public var isPayee: Bool {
        kinds.contains(.fournisseur) || kinds.contains(.societe)
    }

    /// Vrai si ce tiers n'a aucune capacité de destinataire (ni client, ni société) en plus
    /// de fournisseur — condition de masquage de l'adresse de facturation électronique, qui
    /// n'a de sens que pour un tiers qu'on peut aussi qualifier de destinataire. `.interco`
    /// n'ajoute pas de capacité destinataire, donc n'influence pas ce calcul.
    public var isSupplierOnly: Bool {
        kinds.contains(.fournisseur) && !kinds.contains(.client) && !kinds.contains(.societe)
    }

    public var subtitle: String {
        var parts: [String] = []
        if let siren = party.siren?.trimmingCharacters(in: .whitespaces), !siren.isEmpty {
            parts.append("SIREN \(siren)")
        }
        let city = party.city.trimmingCharacters(in: .whitespaces)
        if !city.isEmpty {
            parts.append(city)
        }
        if let vat = party.vatNumber?.trimmingCharacters(in: .whitespaces), !vat.isEmpty {
            parts.append("TVA \(vat)")
        }
        return parts.joined(separator: " · ")
    }

    private enum CodingKeys: String, CodingKey {
        case id, kinds, kind, party, companyID, note, routingAddresses, contacts, isArchived, tagIDs, logoData, profile, isPrincipale
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        // Données existantes : un seul `kind` (singulier), "both" représentant déjà un
        // cumul client+fournisseur — développé ici une bonne fois pour toutes plutôt que de
        // garder cette ambiguïté dans tout le reste du code.
        if let decodedKinds = try c.decodeIfPresent(Set<DirectoryEntryKind>.self, forKey: .kinds), !decodedKinds.isEmpty {
            kinds = decodedKinds
        } else if let legacy = try c.decodeIfPresent(DirectoryEntryKind.self, forKey: .kind) {
            kinds = legacy == .both ? [.client, .fournisseur] : [legacy]
        } else {
            kinds = [.client]
        }
        party = try c.decodeIfPresent(InvoiceParty.self, forKey: .party)
            ?? InvoiceParty(name: "", street: "", postcode: "", city: "")
        companyID = try c.decodeIfPresent(UUID.self, forKey: .companyID)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        routingAddresses = try c.decodeIfPresent([PartyRoutingAddress].self, forKey: .routingAddresses) ?? []
        contacts = try c.decodeIfPresent([PartyContact].self, forKey: .contacts) ?? []
        isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        tagIDs = try c.decodeIfPresent([UUID].self, forKey: .tagIDs) ?? []
        logoData = try c.decodeIfPresent(Data.self, forKey: .logoData)
        profile = try c.decodeIfPresent(FacturXProfile.self, forKey: .profile) ?? .en16931
        isPrincipale = try c.decodeIfPresent(Bool.self, forKey: .isPrincipale) ?? false
    }

    /// Écrit uniquement `kinds` (au pluriel) — plus jamais l'ancienne clé `kind` au
    /// singulier, dont la lecture reste gérée par `init(from:)` pour les données existantes.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kinds, forKey: .kinds)
        try c.encode(party, forKey: .party)
        try c.encodeIfPresent(companyID, forKey: .companyID)
        try c.encodeIfPresent(note, forKey: .note)
        try c.encode(routingAddresses, forKey: .routingAddresses)
        try c.encode(contacts, forKey: .contacts)
        try c.encode(isArchived, forKey: .isArchived)
        try c.encode(tagIDs, forKey: .tagIDs)
        try c.encodeIfPresent(logoData, forKey: .logoData)
        try c.encode(profile, forKey: .profile)
        try c.encode(isPrincipale, forKey: .isPrincipale)
    }

    public var defaultRoutingAddress: PartyRoutingAddress? {
        routingAddresses.first(where: { $0.isDefault && $0.isActive })
            ?? routingAddresses.first(where: { $0.isActive })
    }

    public var defaultContact: PartyContact? {
        contacts.first(where: { $0.isDefault && $0.isActive })
            ?? contacts.first(where: { $0.isActive })
    }
}

public final class PartyDirectory: ObservableObject {
    public static let shared = PartyDirectory()

    @Published public var entries: [DirectoryEntry]

    private let defaults = UserDefaults.standard
    private let env = AppEnvironment.shared
    private var storageKey: String { env.key("facturx.directory.v1") }
    private var societeIntercoMigratedKey: String { env.key("facturx.directory.societeInterco.migrated.v1") }
    public weak var audit: AuditStore?
    public var actorName: String = "system"

    public init() {
        self.entries = []
        load()
    }

    public func load() {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([DirectoryEntry].self, from: data) {
            entries = decoded.map { migrateContacts($0) }
        }
        migrateSocieteIntercoIfNeeded()
    }

    /// Une société du périmètre est toujours aussi une partie liée aux autres sociétés
    /// gérées dans l'app — voir `DirectoryEditorView.init(initialKind:)` pour les sociétés
    /// créées après l'ajout du type Interco. Rattrapage unique pour celles déjà existantes,
    /// jamais rejoué ensuite : l'utilisateur doit pouvoir décocher Interco sur une société
    /// précise sans se le voir réimposer au lancement suivant.
    private func migrateSocieteIntercoIfNeeded() {
        guard !defaults.bool(forKey: societeIntercoMigratedKey) else { return }
        var changed = false
        for idx in entries.indices where entries[idx].kinds.contains(.societe) && !entries[idx].kinds.contains(.interco) {
            entries[idx].kinds.insert(.interco)
            changed = true
        }
        if changed { save() }
        defaults.set(true, forKey: societeIntercoMigratedKey)
    }

    private func migrateContacts(_ entry: DirectoryEntry) -> DirectoryEntry {
        var e = entry
        if e.contacts.isEmpty {
            let cn = e.party.contactName?.trimmingCharacters(in: .whitespaces) ?? ""
            let ce = e.party.contactEmail?.trimmingCharacters(in: .whitespaces) ?? ""
            let cp = e.party.contactPhone?.trimmingCharacters(in: .whitespaces) ?? ""
            if !cn.isEmpty || !ce.isEmpty || !cp.isEmpty {
                e.contacts = [PartyContact(name: cn, email: ce.isEmpty ? nil : ce, phone: cp.isEmpty ? nil : cp, isActive: true, isDefault: true)]
            }
        }
        return e
    }

    public func save() {
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: storageKey)
        }
    }

    /// La société qui sert de repli pour tous les réglages par société non personnalisés
    /// (remplace l'ancien « défaut global » abstrait — voir `SocietyScopedCatalog`). `nil`
    /// avant qu'une société principale ait été désignée.
    public var principaleSocieteID: UUID? {
        entries.first { $0.kinds.contains(.societe) && $0.isPrincipale }?.id
    }

    /// Désigne `id` comme société principale, en retirant l'indicateur de toutes les autres
    /// au préalable — garantit l'unicité au niveau du store plutôt que de faire confiance à
    /// l'UI seule.
    public func setPrincipale(_ id: UUID) {
        for idx in entries.indices {
            entries[idx].isPrincipale = (entries[idx].id == id)
        }
        save()
    }

    /// Retire l'indicateur de société principale partout (aucune société principale désignée).
    public func clearPrincipale() {
        for idx in entries.indices where entries[idx].isPrincipale {
            entries[idx].isPrincipale = false
        }
        save()
    }

    public func upsert(_ entry: DirectoryEntry) {
        let isNew = !entries.contains(where: { $0.id == entry.id })
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[idx] = entry
        } else {
            entries.insert(entry, at: 0)
        }
        save()
        audit?.record(actor: actorName, action: isNew ? "directory_entry_created" : "directory_entry_updated", target: entry.displayName, objectType: .party, objectCode: entry.displayName)
    }

    public func delete(_ entry: DirectoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
        audit?.record(actor: actorName, action: "directory_entry_deleted", target: entry.displayName, objectType: .party, objectCode: entry.displayName)
    }

    public func delete(at offsets: IndexSet) {
        let sorted = offsets.sorted(by: >)
        for i in sorted where entries.indices.contains(i) {
            entries.remove(at: i)
        }
        save()
    }

    public func entries(matching query: String) -> [DirectoryEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return entries }
        return entries.filter { e in
            e.displayName.lowercased().contains(q)
                || (e.party.siren ?? "").lowercased().contains(q)
                || (e.party.vatNumber ?? "").lowercased().contains(q)
                || (e.party.city.lowercased()).contains(q)
        }
    }

    public struct DuplicateMatch: Hashable {
        public var entry: DirectoryEntry
        public var reasons: [String]

        public init(entry: DirectoryEntry, reasons: [String]) {
            self.entry = entry
            self.reasons = reasons
        }
    }

    public func findDuplicates(of entry: DirectoryEntry) -> [DuplicateMatch] {
        let p = entry.party
        let name = p.name.trimmingCharacters(in: .whitespaces).lowercased()
        let siren = (p.siren ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        let siret = (p.siret ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        let vat = (p.vatNumber ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        let endpoint = (p.endpointID ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        let city = p.city.trimmingCharacters(in: .whitespaces).lowercased()
        let postcode = p.postcode.trimmingCharacters(in: .whitespaces).lowercased()

        var matches: [DuplicateMatch] = []
        for existing in entries {
            guard existing.id != entry.id else { continue }
            let ep = existing.party
            var reasons: [String] = []
            let eName = ep.name.trimmingCharacters(in: .whitespaces).lowercased()
            let eSiren = (ep.siren ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            let eSiret = (ep.siret ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            let eVat = (ep.vatNumber ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            let eEndpoint = (ep.endpointID ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            if !name.isEmpty && name == eName { reasons.append("nom identique") }
            if !siren.isEmpty && siren == eSiren { reasons.append("SIREN identique") }
            if !siret.isEmpty && siret == eSiret { reasons.append("SIRET identique") }
            if !vat.isEmpty && vat == eVat { reasons.append("n° TVA identique") }
            if !endpoint.isEmpty && endpoint == eEndpoint { reasons.append("identifiant électronique identique") }
            if !postcode.isEmpty && !city.isEmpty
                && postcode == ep.postcode.trimmingCharacters(in: .whitespaces).lowercased()
                && city == ep.city.trimmingCharacters(in: .whitespaces).lowercased() {
                reasons.append("ville + code postal identiques")
            }
            if !reasons.isEmpty {
                matches.append(DuplicateMatch(entry: existing, reasons: reasons))
            }
        }
        return matches
    }
}

public struct PartyTag: Codable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var hexColor: String

    public init(id: UUID = UUID(), name: String, hexColor: String = "555555") {
        self.id = id
        self.name = name
        self.hexColor = hexColor
    }
}

public final class TagStore: ObservableObject {
    public static let shared = TagStore()

    @Published public var tags: [PartyTag]
    /// Surcharge éparse par société (Réglages > Tables) — voir `SocietyScopedCatalog`. Une
    /// société peut personnaliser un tag existant (même id, ex. changer sa couleur) ou en
    /// ajouter un qui lui est propre.
    @Published public var tagsBySociety: [UUID: [PartyTag]] = [:]

    private let defaults = UserDefaults.standard
    private let env = AppEnvironment.shared
    private var storageKey: String { env.key("facturx.tags.v1") }
    private var tagsBySocietyKey: String { env.key("facturx.tags.bysociety.v1") }

    public init() {
        self.tags = []
        load()
    }

    public func load() {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([PartyTag].self, from: data) {
            tags = decoded
        }
        if let data = defaults.data(forKey: tagsBySocietyKey),
           let decoded = try? JSONDecoder().decode([UUID: [PartyTag]].self, from: data) {
            tagsBySociety = decoded
        }
    }

    public func save() {
        if let data = try? JSONEncoder().encode(tags) {
            defaults.set(data, forKey: storageKey)
        }
        if let data = try? JSONEncoder().encode(tagsBySociety) {
            defaults.set(data, forKey: tagsBySocietyKey)
        }
    }

    public func upsert(_ tag: PartyTag) {
        if let idx = tags.firstIndex(where: { $0.id == tag.id }) {
            tags[idx] = tag
        } else {
            tags.append(tag)
        }
        save()
    }

    public func delete(_ tag: PartyTag) {
        tags.removeAll { $0.id == tag.id }
        save()
    }

    /// Liste effective pour une société : le réglage global, avec les tags de la société
    /// superposés par id. `companyID == nil` résout sur la société principale si une a été
    /// désignée (voir `PartyDirectory.principaleSocieteID`), sinon le réglage global.
    public func list(for companyID: UUID?) -> [PartyTag] {
        guard let effectiveID = companyID ?? PartyDirectory.shared.principaleSocieteID else { return tags }
        return SocietyScopedCatalog.resolvedList(global: tags, overrideForSociety: tagsBySociety[effectiveID])
    }

    /// Un tag précis par id, résolu pour une société — pour l'affichage d'un tag déjà
    /// assigné à un tiers (`DirectoryEntry.tagIDs`), qui peut référencer un tag propre à la
    /// société de ce tiers.
    public func tag(id: UUID, companyID: UUID?) -> PartyTag? {
        let effectiveID = companyID ?? PartyDirectory.shared.principaleSocieteID
        if let effectiveID, let match = SocietyScopedCatalog.resolvedElement(id: id, overrideForSociety: tagsBySociety[effectiveID]) {
            return match
        }
        return tags.first { $0.id == id }
    }

    /// Commence (ou remplace) la personnalisation de ce tag pour cette société.
    public func setOverride(_ tag: PartyTag, companyID: UUID) {
        var list = tagsBySociety[companyID] ?? []
        if let idx = list.firstIndex(where: { $0.id == tag.id }) {
            list[idx] = tag
        } else {
            list.append(tag)
        }
        tagsBySociety[companyID] = list
        save()
    }

    /// Revient au réglage global pour ce tag sur cette société.
    public func removeOverride(id: UUID, companyID: UUID) {
        tagsBySociety[companyID]?.removeAll { $0.id == id }
        if tagsBySociety[companyID]?.isEmpty == true {
            tagsBySociety.removeValue(forKey: companyID)
        }
        save()
    }
}

public final class KindColorStore: ObservableObject {
    public static let shared = KindColorStore()

    @Published public var colors: [DirectoryEntryKind: String]
    /// Surcharge éparse par société (Réglages > Tables) — voir `SocietyScopedCatalog`.
    @Published public var colorsBySociety: [UUID: [DirectoryEntryKind: String]] = [:]

    private let defaults = UserDefaults.standard
    private let env = AppEnvironment.shared
    private var storageKey: String { env.key("facturx.kindcolors.v1") }
    private var colorsBySocietyKey: String { env.key("facturx.kindcolors.bysociety.v1") }

    public init() {
        self.colors = [
            .client: DirectoryEntryKind.client.defaultHexColor,
            .societe: DirectoryEntryKind.societe.defaultHexColor,
            .fournisseur: DirectoryEntryKind.fournisseur.defaultHexColor,
            .interco: DirectoryEntryKind.interco.defaultHexColor,
            .both: DirectoryEntryKind.both.defaultHexColor,
        ]
        load()
    }

    public func load() {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            colors = [
                .client: decoded["client"] ?? DirectoryEntryKind.client.defaultHexColor,
                .societe: decoded["societe"] ?? decoded["fournisseur"] ?? DirectoryEntryKind.societe.defaultHexColor,
                .fournisseur: decoded["fournisseur_new"] ?? DirectoryEntryKind.fournisseur.defaultHexColor,
                .interco: decoded["interco"] ?? DirectoryEntryKind.interco.defaultHexColor,
                .both: decoded["both"] ?? DirectoryEntryKind.both.defaultHexColor,
            ]
        }
        if let data = defaults.data(forKey: colorsBySocietyKey),
           let decoded = try? JSONDecoder().decode([UUID: [DirectoryEntryKind: String]].self, from: data) {
            colorsBySociety = decoded
        }
    }

    public func save() {
        let dict = [
            "client": colors[.client] ?? DirectoryEntryKind.client.defaultHexColor,
            "societe": colors[.societe] ?? DirectoryEntryKind.societe.defaultHexColor,
            "fournisseur_new": colors[.fournisseur] ?? DirectoryEntryKind.fournisseur.defaultHexColor,
            "interco": colors[.interco] ?? DirectoryEntryKind.interco.defaultHexColor,
            "both": colors[.both] ?? DirectoryEntryKind.both.defaultHexColor,
        ]
        if let data = try? JSONEncoder().encode(dict) {
            defaults.set(data, forKey: storageKey)
        }
        if let data = try? JSONEncoder().encode(colorsBySociety) {
            defaults.set(data, forKey: colorsBySocietyKey)
        }
    }

    public func hexColor(for kind: DirectoryEntryKind) -> String {
        colors[kind] ?? kind.defaultHexColor
    }

    /// Variante par société — voir `InvoiceStatusStore.override(for:companyID:)`.
    public func hexColor(for kind: DirectoryEntryKind, companyID: UUID?) -> String {
        let effectiveID = companyID ?? PartyDirectory.shared.principaleSocieteID
        if let effectiveID, let color = colorsBySociety[effectiveID]?[kind] {
            return color
        }
        return hexColor(for: kind)
    }

    /// Commence (ou remplace) la personnalisation de cette couleur pour cette société.
    public func setOverride(hexColor: String, for kind: DirectoryEntryKind, companyID: UUID) {
        colorsBySociety[companyID, default: [:]][kind] = hexColor
        save()
    }

    /// Revient au réglage global pour cette couleur sur cette société.
    public func removeOverride(for kind: DirectoryEntryKind, companyID: UUID) {
        colorsBySociety[companyID]?.removeValue(forKey: kind)
        if colorsBySociety[companyID]?.isEmpty == true {
            colorsBySociety.removeValue(forKey: companyID)
        }
        save()
    }
}
