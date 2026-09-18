import SwiftUI
import FacturXCore

/// Pendant de `PartySection` côté achats. Copie indépendante plutôt qu'extension de
/// `PartySection.Role` : ce dernier a ses conditions de rôle en ternaires `==` (pas des
/// switch exhaustifs) à plusieurs endroits — un 3ᵉ cas y tomberait silencieusement dans la
/// mauvaise branche au lieu d'une erreur de compilation, un risque réel sur l'éditeur
/// facture ventes qui n'a aucun test UI automatisé. `OrderPartySection` avait déjà établi
/// ce même précédent (copie indépendante plutôt qu'extension).
struct PurchasePartySection: View {
    enum Role {
        case supplier, buyer
        var title: String { self == .supplier ? "Fournisseur" : "Notre société" }
        var defaultKind: DirectoryEntryKind { self == .supplier ? .fournisseur : .societe }
    }

    @Binding var party: InvoiceParty
    let role: Role
    var onPartyPicked: ((InvoiceParty) -> Void)? = nil
    var locked: Bool = false
    @EnvironmentObject var directory: PartyDirectory
    @EnvironmentObject var superPDPSettings: SuperPDPSettings
    @State private var showPicker = false
    @State private var showSaveSheet = false
    @State private var showSuperPDPSearch = false
    @State private var showFrenchDirectorySearch = false
    @State private var saveName = ""
    @State private var pendingEntry: DirectoryEntry?
    @State private var duplicateMatches: [PartyDirectory.DuplicateMatch]?
    @State private var lookingUpElectronicAddress = false
    @State private var electronicAddressLookupNote: String?
    @State private var electronicAddressChoices: [SuperPDPDirectoryEntry] = []
    @State private var pendingPartyForAddressChoice: InvoiceParty?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !locked {
                HStack {
                    Button {
                        showPicker = true
                    } label: {
                        Label("Choisir dans l'annuaire", systemImage: "person.crop.circle.badge.plus")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        saveName = party.name
                        showSaveSheet = true
                    } label: {
                        Label("Enregistrer dans l'annuaire", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .disabled(party.name.trimmingCharacters(in: .whitespaces).isEmpty)
                    // Recherche d'adresse électronique côté fournisseur (pas buyer, contrairement
                    // à PartySection) : sur un achat, c'est l'adresse de routage du fournisseur
                    // qu'on cherche à identifier, pas la nôtre.
                    if role == .supplier {
                        Button {
                            showSuperPDPSearch = true
                        } label: {
                            Label("SUPER PDP", systemImage: "paperplane")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!superPDPSettings.credentials.isConfigured)
                        .help("Rechercher le fournisseur dans l'annuaire SUPER PDP")
                        Button {
                            showFrenchDirectorySearch = true
                        } label: {
                            Label("Annuaire FR", systemImage: "building.2")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!superPDPSettings.credentials.isConfigured)
                        .help("Rechercher une entreprise dans l'annuaire français (SIREN, adresse Peppol)")
                    }
                    Spacer()
                }
            }

            // isSociete: le fournisseur est payé sur ce document — c'est donc son IBAN/BIC
            // qui doit apparaître, même logique que PartySection affichant les coordonnées
            // bancaires côté émetteur (celui qui est payé) pour une facture de vente.
            PartyEditorView(party: $party, isSociete: role == .supplier, locked: locked, directory: directory, onPickContact: { updatePartyFromContact($0) }, onPickRouting: { updatePartyFromRouting($0) }, onPartyPicked: { p in onPartyPicked?(p) })
        }
        .padding(8)
        .sheet(isPresented: $showSuperPDPSearch) {
            SuperPDPSearchSheet(initialQuery: party.siren ?? party.siret ?? party.name) { picked in
                party = picked
                onPartyPicked?(picked)
            }
        }
        .sheet(isPresented: $showFrenchDirectorySearch) {
            SuperPDPFrenchDirectorySheet { picked in
                party = picked
                onPartyPicked?(picked)
            }
        }
        .sheet(isPresented: $showPicker) {
            PurchasePartyPickerSheet(role: role) { selected in
                var p = selected.party
                if let routing = selected.defaultRoutingAddress, routing.isActive {
                    let composed = routing.composedAddress.trimmingCharacters(in: .whitespaces)
                    if !composed.isEmpty {
                        p.endpointID = composed
                        p.endpointSchemeID = "0225"
                    }
                }
                if let contact = selected.defaultContact, contact.isActive {
                    p.contactName = contact.name.trimmingCharacters(in: .whitespaces).isEmpty ? nil : contact.name
                    p.contactEmail = (contact.email?.trimmingCharacters(in: .whitespaces) ?? "").isEmpty ? nil : contact.email
                    p.contactPhone = (contact.phone?.trimmingCharacters(in: .whitespaces) ?? "").isEmpty ? nil : contact.phone
                }
                party = p
                onPartyPicked?(p)
                showPicker = false
            }
        }
        .sheet(isPresented: $showSaveSheet) {
            VStack(spacing: 12) {
                Text("Enregistrer dans l'annuaire").font(.headline)
                TextField("Nom affiché", text: $saveName).frame(width: 320)
                if role == .supplier, superPDPSettings.credentials.isConfigured {
                    if lookingUpElectronicAddress {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Recherche de l'adresse électronique sur SUPER PDP…")
                        }.font(.caption).foregroundStyle(.secondary)
                    } else if let note = electronicAddressLookupNote {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button("Annuler") { showSaveSheet = false }
                        .keyboardShortcut(.cancelAction)
                    Button("Enregistrer") {
                        saveToDirectory()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(lookingUpElectronicAddress)
                }
            }.padding(20).frame(minWidth: 360)
        }
        .sheet(isPresented: Binding(
            get: { !electronicAddressChoices.isEmpty },
            set: { if !$0 { electronicAddressChoices = []; pendingPartyForAddressChoice = nil } }
        )) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Plusieurs adresses électroniques trouvées").font(.headline).padding(12)
                Text("Ce SIREN/SIRET correspond à plusieurs établissements sur SUPER PDP. Choisissez celle à enregistrer pour ce tiers.")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12)
                Divider().padding(.top, 8)
                List(electronicAddressChoices) { entry in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.name ?? entry.routingAddress ?? "(sans nom)").font(.body.bold())
                        Text(entry.routingAddress ?? "").font(.caption.monospaced()).foregroundStyle(.secondary)
                        if let addr = entry.addressLine, !addr.isEmpty {
                            Text([addr, entry.postcode, entry.city].compactMap { $0 }.joined(separator: " "))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { applyElectronicAddressChoice(entry) }
                }
            }
            .frame(width: 420, height: 340)
        }
        .alert("Tiers potentiellement en doublon", isPresented: Binding(
            get: { duplicateMatches != nil },
            set: { if !$0 { duplicateMatches = nil; pendingEntry = nil } }
        )) {
            Button("Enregistrer quand même", role: .destructive) {
                if let entry = pendingEntry {
                    directory.upsert(entry)
                }
                showSaveSheet = false
                duplicateMatches = nil
                pendingEntry = nil
            }
            Button("Annuler", role: .cancel) {
                duplicateMatches = nil
                pendingEntry = nil
            }
        } message: {
            if let matches = duplicateMatches, !matches.isEmpty {
                let lines = matches.map { m in
                    "• \(m.entry.displayName) — \(m.reasons.joined(separator: ", "))"
                }.joined(separator: "\n")
                Text("Un ou plusieurs tiers existants semblent correspondre :\n\(lines)")
            }
        }
    }

    private func saveToDirectory() {
        var p = party
        p.name = saveName.trimmingCharacters(in: .whitespaces).isEmpty ? party.name : saveName
        let siren = (p.siren ?? "").filter { $0.isNumber }
        let siret = (p.siret ?? "").filter { $0.isNumber }
        let currentEndpoint = (p.endpointID ?? "").trimmingCharacters(in: .whitespaces)
        let isPlaceholderSirenFallback = !siren.isEmpty && currentEndpoint == siren
        let hasRealElectronicAddress = !currentEndpoint.isEmpty && !isPlaceholderSirenFallback
        guard role == .supplier, superPDPSettings.credentials.isConfigured, !hasRealElectronicAddress,
              (siren.count == 9 || siret.count == 14) else {
            finishSaveToDirectory(p)
            return
        }
        lookingUpElectronicAddress = true
        electronicAddressLookupNote = nil
        let query = siret.count == 14 ? siret : siren
        Task {
            do {
                let results = try await SuperPDPService().searchRecipient(siretOrSiren: query, credentials: superPDPSettings.credentials)
                let withAddress = results.filter { !($0.routingAddress ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
                let distinctAddresses = Set(withAddress.map { $0.routingAddress ?? "" })
                if distinctAddresses.count > 1 {
                    lookingUpElectronicAddress = false
                    pendingPartyForAddressChoice = p
                    electronicAddressChoices = withAddress
                    return
                } else if let match = withAddress.first {
                    p.endpointID = match.routingAddress
                    p.endpointSchemeID = match.routingScheme?.trimmingCharacters(in: .whitespaces).isEmpty == false ? match.routingScheme! : "0225"
                    electronicAddressLookupNote = "Adresse électronique trouvée sur SUPER PDP."
                } else {
                    electronicAddressLookupNote = "Aucune adresse électronique trouvée sur SUPER PDP pour ce SIREN/SIRET."
                }
            } catch {
                electronicAddressLookupNote = "Recherche SUPER PDP indisponible : \(error.localizedDescription)"
            }
            lookingUpElectronicAddress = false
            finishSaveToDirectory(p)
        }
    }

    private func applyElectronicAddressChoice(_ match: SuperPDPDirectoryEntry) {
        guard var p = pendingPartyForAddressChoice else { return }
        p.endpointID = match.routingAddress
        p.endpointSchemeID = match.routingScheme?.trimmingCharacters(in: .whitespaces).isEmpty == false ? match.routingScheme! : "0225"
        electronicAddressChoices = []
        pendingPartyForAddressChoice = nil
        finishSaveToDirectory(p)
    }

    private func finishSaveToDirectory(_ p: InvoiceParty) {
        var entry = DirectoryEntry(kind: role.defaultKind, party: p)
        let siren = (p.siren ?? "").filter { $0.isNumber }
        let siret = (p.siret ?? "").filter { $0.isNumber }
        let endpoint = (p.endpointID ?? "").trimmingCharacters(in: .whitespaces)
        if !endpoint.isEmpty, !siren.isEmpty {
            let format: RoutingAddressFormat = siret.count == 14 ? .sirenSiret : .siren
            entry.routingAddresses = [PartyRoutingAddress(
                format: format, siren: siren, siret: siret.count == 14 ? siret : nil,
                label: "SUPER PDP", isActive: true, isDefault: true
            )]
        }
        let dup = directory.findDuplicates(of: entry)
        if dup.isEmpty {
            directory.upsert(entry)
            showSaveSheet = false
        } else {
            pendingEntry = entry
            duplicateMatches = dup
        }
    }

    private func updatePartyFromContact(_ contact: PartyContact) {
        var p = party
        p.contactName = contact.name.trimmingCharacters(in: .whitespaces).isEmpty ? nil : contact.name
        p.contactEmail = (contact.email?.trimmingCharacters(in: .whitespaces) ?? "").isEmpty ? nil : contact.email
        p.contactPhone = (contact.phone?.trimmingCharacters(in: .whitespaces) ?? "").isEmpty ? nil : contact.phone
        party = p
        onPartyPicked?(p)
    }

    private func updatePartyFromRouting(_ routing: PartyRoutingAddress) {
        var p = party
        let composed = routing.composedAddress.trimmingCharacters(in: .whitespaces)
        if !composed.isEmpty {
            p.endpointID = composed
            p.endpointSchemeID = "0225"
        }
        party = p
        onPartyPicked?(p)
    }
}

/// Pendant de `PartyPickerSheet` — filtre sur `.fournisseur`/`.both` au lieu de
/// `.client`/`.both`, retypé sur `PurchasePartySection.Role`.
struct PurchasePartyPickerSheet: View {
    let role: PurchasePartySection.Role
    let onPick: (DirectoryEntry) -> Void

    @EnvironmentObject var directory: PartyDirectory
    @EnvironmentObject var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var creatingNew = false
    @State private var editingEntry: DirectoryEntry?

    var filtered: [DirectoryEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var active = directory.entries.filter {
            !$0.isArchived && (role == .buyer ? $0.kind == .societe : ($0.kind == .fournisseur || $0.kind == .both))
        }
        if role == .buyer, let scope = auth.visibleDirectoryEntryIDs(for: auth.currentUser) {
            active = active.filter { scope.contains($0.id) }
        }
        let base: [DirectoryEntry]
        if q.isEmpty {
            base = active
        } else {
            base = active.filter {
                $0.displayName.lowercased().contains(q)
                    || ($0.party.siren ?? "").lowercased().contains(q)
                    || ($0.party.vatNumber ?? "").lowercased().contains(q)
                    || $0.party.city.lowercased().contains(q)
            }
        }
        return base.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var canCreateNew: Bool {
        if role == .buyer { return auth.currentUser?.isAdmin == true }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Annuaire — choisir \(role.title.lowercased())").font(.headline)
                Spacer()
                if canCreateNew {
                    Button {
                        creatingNew = true
                    } label: { Label("Nouveau", systemImage: "plus") }
                        .buttonStyle(.bordered)
                }
                Button("Fermer") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)

            TextField("Rechercher (nom, SIREN, ville…)", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12).padding(.bottom, 8)

            Divider()

            if filtered.isEmpty {
                Text("Aucun tiers. Cliquez « Nouveau » pour en créer un.")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                List {
                    ForEach(filtered) { entry in
                        HStack {
                            Button {
                                onPick(entry)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.displayName).font(.body.weight(.medium))
                                        Text(entry.subtitle).font(.caption).foregroundStyle(.secondary)
                                        if let routing = entry.defaultRoutingAddress, routing.isActive {
                                            Text("Adresse de routage : \(routing.composedAddress)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(entry.kind.label).font(.caption2)
                                            .padding(.horizontal, 6).padding(.vertical, 1)
                                            .background(.quaternary, in: Capsule())
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Button {
                                editingEntry = entry
                            } label: { Image(systemName: "pencil") }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .help("Modifier le tiers")
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minWidth: 460, minHeight: 420)
        .sheet(isPresented: $creatingNew) {
            DirectoryEditorView(initialKind: role.defaultKind) { newEntry in
                directory.upsert(newEntry)
                creatingNew = false
                onPick(newEntry)
            }
        }
        .sheet(item: $editingEntry) { entry in
            DirectoryEditorView(entry: entry, onSave: { updated in
                directory.upsert(updated)
                editingEntry = nil
            }, onDelete: { toDelete in
                directory.delete(toDelete)
                editingEntry = nil
            })
        }
    }
}
