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
}

public struct DirectoryEntry: Codable, Hashable, Identifiable {
    public var id: UUID
    public var kind: DirectoryEntryKind
    public var party: InvoiceParty
    public var note: String?

    public init(
        id: UUID = UUID(),
        kind: DirectoryEntryKind = .client,
        party: InvoiceParty,
        note: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.party = party
        self.note = note
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
        case id, kind, party, note
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decodeIfPresent(DirectoryEntryKind.self, forKey: .kind) ?? .client
        party = try c.decodeIfPresent(InvoiceParty.self, forKey: .party)
            ?? InvoiceParty(name: "", street: "", postcode: "", city: "")
        note = try c.decodeIfPresent(String.self, forKey: .note)
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
}
