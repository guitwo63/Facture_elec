import Foundation

public enum DirectoryEntryKind: String, Codable, CaseIterable {
    case client
    case fournisseur
    case both

    public var label: String {
        switch self {
        case .client: return "Client"
        case .fournisseur: return "Fournisseur"
        case .both: return "Client / Fournisseur"
        }
    }

    public var defaultHexColor: String {
        switch self {
        case .client: return "2A6EBB"
        case .fournisseur: return "2E8B57"
        case .both: return "8A4FBD"
        }
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

public struct DirectoryEntry: Codable, Hashable, Identifiable {
    public var id: UUID
    public var kind: DirectoryEntryKind
    public var party: InvoiceParty
    public var note: String?
    public var routingAddresses: [PartyRoutingAddress]
    public var isArchived: Bool
    public var tagIDs: [UUID]

    public init(
        id: UUID = UUID(),
        kind: DirectoryEntryKind = .client,
        party: InvoiceParty,
        note: String? = nil,
        routingAddresses: [PartyRoutingAddress] = [],
        isArchived: Bool = false,
        tagIDs: [UUID] = []
    ) {
        self.id = id
        self.kind = kind
        self.party = party
        self.note = note
        self.routingAddresses = routingAddresses
        self.isArchived = isArchived
        self.tagIDs = tagIDs
    }

    public var displayName: String {
        party.name.trimmingCharacters(in: .whitespaces).isEmpty
            ? "(sans nom)"
            : party.name
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
        case id, kind, party, note, routingAddresses, isArchived, tagIDs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decodeIfPresent(DirectoryEntryKind.self, forKey: .kind) ?? .client
        party = try c.decodeIfPresent(InvoiceParty.self, forKey: .party)
            ?? InvoiceParty(name: "", street: "", postcode: "", city: "")
        note = try c.decodeIfPresent(String.self, forKey: .note)
        routingAddresses = try c.decodeIfPresent([PartyRoutingAddress].self, forKey: .routingAddresses) ?? []
        isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        tagIDs = try c.decodeIfPresent([UUID].self, forKey: .tagIDs) ?? []
    }

    public var defaultRoutingAddress: PartyRoutingAddress? {
        routingAddresses.first(where: { $0.isDefault && $0.isActive })
            ?? routingAddresses.first(where: { $0.isActive })
    }
}

public final class PartyDirectory: ObservableObject {
    public static let shared = PartyDirectory()

    @Published public var entries: [DirectoryEntry]

    private let defaults = UserDefaults.standard
    private let storageKey = "facturx.directory.v1"

    public init() {
        self.entries = []
        load()
    }

    public func load() {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([DirectoryEntry].self, from: data) {
            entries = decoded
        }
    }

    public func save() {
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: storageKey)
        }
    }

    public func upsert(_ entry: DirectoryEntry) {
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[idx] = entry
        } else {
            entries.insert(entry, at: 0)
        }
        save()
    }

    public func delete(_ entry: DirectoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    public func delete(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
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

    private let defaults = UserDefaults.standard
    private let storageKey = "facturx.tags.v1"

    public init() {
        self.tags = []
        load()
    }

    public func load() {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([PartyTag].self, from: data) {
            tags = decoded
        }
    }

    public func save() {
        if let data = try? JSONEncoder().encode(tags) {
            defaults.set(data, forKey: storageKey)
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
}

public final class KindColorStore: ObservableObject {
    public static let shared = KindColorStore()

    @Published public var colors: [DirectoryEntryKind: String]

    private let defaults = UserDefaults.standard
    private let storageKey = "facturx.kindcolors.v1"

    public init() {
        self.colors = [
            .client: DirectoryEntryKind.client.defaultHexColor,
            .fournisseur: DirectoryEntryKind.fournisseur.defaultHexColor,
            .both: DirectoryEntryKind.both.defaultHexColor,
        ]
        load()
    }

    public func load() {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            colors = [
                .client: decoded["client"] ?? DirectoryEntryKind.client.defaultHexColor,
                .fournisseur: decoded["fournisseur"] ?? DirectoryEntryKind.fournisseur.defaultHexColor,
                .both: decoded["both"] ?? DirectoryEntryKind.both.defaultHexColor,
            ]
        }
    }

    public func save() {
        let dict = [
            "client": colors[.client] ?? DirectoryEntryKind.client.defaultHexColor,
            "fournisseur": colors[.fournisseur] ?? DirectoryEntryKind.fournisseur.defaultHexColor,
            "both": colors[.both] ?? DirectoryEntryKind.both.defaultHexColor,
        ]
        if let data = try? JSONEncoder().encode(dict) {
            defaults.set(data, forKey: storageKey)
        }
    }

    public func hexColor(for kind: DirectoryEntryKind) -> String {
        colors[kind] ?? kind.defaultHexColor
    }
}
