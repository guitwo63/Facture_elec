import SwiftUI
import FacturXCore

// MARK: - Extrait de FacturXMacApp.swift (découpage par domaine)

struct PartySection: View {
    enum Role {
        case seller, buyer
        var title: String { self == .seller ? "Émetteur" : "Destinataire" }
        var defaultKind: DirectoryEntryKind { self == .seller ? .societe : .client }
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
                    if role == .buyer {
                        Button {
                            showSuperPDPSearch = true
                        } label: {
                            Label("SUPER PDP", systemImage: "paperplane")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!superPDPSettings.credentials.isConfigured)
                        .help("Rechercher un destinataire dans l'annuaire SUPER PDP")
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

            PartyEditorView(party: $party, isSociete: role == .seller, locked: locked, directory: directory, onPickContact: { updatePartyFromContact($0) }, onPickRouting: { updatePartyFromRouting($0) }, onPartyPicked: { p in onPartyPicked?(p) })
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
            PartyPickerSheet(role: role) { selected in
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
                if role == .buyer, superPDPSettings.credentials.isConfigured {
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
        // La recherche DINUM (SireneResult.merged) préremplit endpointID avec le
        // SIREN brut comme repli quand rien n'est renseigné : ce n'est pas une
        // vraie adresse électronique, donc on ne doit pas s'arrêter là.
        let isPlaceholderSirenFallback = !siren.isEmpty && currentEndpoint == siren
        let hasRealElectronicAddress = !currentEndpoint.isEmpty && !isPlaceholderSirenFallback
        guard role == .buyer, superPDPSettings.credentials.isConfigured, !hasRealElectronicAddress,
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
                    // Plusieurs adresses électroniques différentes trouvées pour ce SIREN/SIRET
                    // (plusieurs établissements, par ex.) : on ne peut pas en choisir une au
                    // hasard, l'utilisateur doit trancher — au lieu de prendre silencieusement
                    // la première, ce qui pouvait enregistrer la mauvaise adresse.
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

    /// Choix retenu quand plusieurs adresses électroniques étaient disponibles pour le même
    /// SIREN/SIRET (plusieurs établissements) : reprend le flux normal avec l'adresse choisie.
    private func applyElectronicAddressChoice(_ match: SuperPDPDirectoryEntry) {
        guard var p = pendingPartyForAddressChoice else { return }
        p.endpointID = match.routingAddress
        p.endpointSchemeID = match.routingScheme?.trimmingCharacters(in: .whitespaces).isEmpty == false ? match.routingScheme! : "0225"
        electronicAddressChoices = []
        pendingPartyForAddressChoice = nil
        finishSaveToDirectory(p)
    }

    private func finishSaveToDirectory(_ p: InvoiceParty) {
        var entry = DirectoryEntry(kinds: [role.defaultKind], party: p)
        // L'adresse électronique trouvée était appliquée à `party.endpointID` mais jamais
        // recopiée dans `routingAddresses` (la liste gérée depuis la fiche tiers) : elle
        // semblait alors ne "rien avoir enregistré" une fois le tiers ouvert, malgré un
        // endpointID bien présent en mémoire au moment de la sauvegarde.
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

struct PartyPickerSheet: View {
    let role: PartySection.Role
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
            guard !$0.isArchived else { return false }
            if $0.kinds.contains(.interco) { return true }
            return role == .seller ? $0.kinds.contains(.societe) : $0.kinds.contains(.client)
        }
        if role == .seller, let scope = auth.visibleDirectoryEntryIDs(for: auth.currentUser) {
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
        if role == .seller { return auth.currentUser?.isAdmin == true }
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
                                        Text(entry.kindsLabel).font(.caption2)
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

struct PartyExportSheet: View {
    let entries: [DirectoryEntry]
    @Binding var isPresented: Bool
    @State private var exportLog = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Export des tiers").font(.headline)
                Spacer()
            }.padding(12)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Text("\(entries.count) tier(s) à exporter (selon le filtre et le périmètre).")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Format : CSV compatible Excel (UTF-8, séparateur ;). Toutes les données : raison sociale, type, SIREN, SIRET, TVA, adresse, contact, endpoint, IBAN/BIC, conditions de paiement, note, archive.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(12)
            Spacer()
            Divider()
            HStack {
                Button("Fermer") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if !exportLog.isEmpty {
                    Text(exportLog).font(.caption).foregroundStyle(.secondary)
                }
                Button("Exporter") { runExport() }
                    .buttonStyle(.borderedProminent)
                    .disabled(entries.isEmpty)
            }.padding(12)
        }
        .frame(width: 520, height: 280)
    }

    private func runExport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "tiers.csv"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try ExportGenerator().writeCSV(ExportGenerator().directoryCSV(entries), to: url)
                exportLog = "Exporté : \(url.lastPathComponent)"
            } catch {
                exportLog = "Erreur : \(error)"
            }
        }
    }
}

struct PartyImportSheet: View {
    @Binding var isPresented: Bool
    let onImport: ([DirectoryEntry]) -> Void
    @State private var fileURL: URL?
    @State private var result: ExportGenerator.PartyImportResult?
    @State private var importLog = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Import des tiers").font(.headline)
                Spacer()
            }.padding(12)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Text("Sélectionnez un fichier CSV. Colonnes obligatoires : Raison sociale, SIREN. Toutes les autres colonnes sont optionnelles (Type, SIRET, TVA, Rue, Code postal, Ville, Pays, Contact (nom), Contact (email), Contact (tél.), Endpoint ID, Schéma endpoint, IBAN, BIC, Conditions paiement, Note).")
                    .font(.caption).foregroundStyle(.secondary)
                Button {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.commaSeparatedText]
                    if panel.runModal() == .OK, let url = panel.url {
                        do {
                            let raw = try String(contentsOf: url, encoding: .utf8)
                            let res = ExportGenerator().parseDirectoryCSV(raw)
                            fileURL = url
                            result = res
                            importLog = "\(res.entries.count) tier(s) à importer\(res.errors.isEmpty ? "" : ", \(res.errors.count) avertissement(s)")"
                        } catch {
                            importLog = "Erreur de lecture : \(error)"
                        }
                    }
                } label: { Label("Choisir un fichier CSV…", systemImage: "doc") }
                    .buttonStyle(.bordered)
                if let r = result {
                    if !r.errors.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Avertissements :").font(.caption.bold())
                            ForEach(Array(r.errors.enumerated()), id: \.offset) { _, msg in
                                Text("• \(msg)").font(.caption2).foregroundStyle(.orange)
                            }
                        }
                    }
                    if !r.entries.isEmpty {
                        Text(importLog).font(.caption).foregroundStyle(.secondary)
                    }
                } else if !importLog.isEmpty {
                    Text(importLog).font(.caption).foregroundStyle(.red)
                }
            }.padding(12)
            Spacer()
            Divider()
            HStack {
                Button("Fermer") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Importer") {
                    if let r = result { onImport(r.entries) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(result?.entries.isEmpty ?? true)
            }.padding(12)
        }
        .frame(width: 560, height: 420)
    }
}

private struct KindChipToggle: View {
    let label: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.callout)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(isOn ? Color.accentColor.opacity(0.18) : Color.clear, in: Capsule())
                .overlay(Capsule().stroke(isOn ? Color.accentColor : Color.secondary.opacity(0.4)))
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
    }
}

private struct KindBadges: View {
    let kinds: Set<DirectoryEntryKind>
    let kindColors: KindColorStore
    var font: Font = .caption2

    var body: some View {
        ForEach(DirectoryEntryKind.selectable.filter { kinds.contains($0) }, id: \.self) { kind in
            Text(kind.label).font(font)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(Color(hex: kindColors.hexColor(for: kind)).opacity(0.2), in: Capsule())
                .foregroundColor(Color(hex: kindColors.hexColor(for: kind)))
        }
    }
}

struct DirectoryView: View {
    @EnvironmentObject var directory: PartyDirectory
    @EnvironmentObject var tagStore: TagStore
    @EnvironmentObject var kindColors: KindColorStore
    @EnvironmentObject var auth: AuthStore
    @State private var query = ""
    @State private var editingEntry: DirectoryEntry?
    @State private var creatingNew = false
    @State private var showArchived = false
    @State private var selectedEntry: DirectoryEntry?
    @State private var showExport = false
    @State private var showImport = false
    @State private var importResult: ExportGenerator.PartyImportResult?
    /// Vide = "Tous" (tous les tiers hors sociétés du périmètre, comme avant) ; sinon un
    /// tiers est visible s'il porte au moins un des types cochés ici.
    @State private var kindFilters: Set<DirectoryEntryKind> = []

    private var canManageSocietes: Bool { auth.currentUser?.isAdmin == true }

    var filtered: [DirectoryEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var base = directory.entries.filter { showArchived || !$0.isArchived }
        base = base.filter { kindFilters.isEmpty ? !$0.kinds.contains(.societe) : !$0.kinds.isDisjoint(with: kindFilters) }
        guard q.isEmpty else {
            return base.filter {
                $0.displayName.lowercased().contains(q)
                    || ($0.party.siren ?? "").lowercased().contains(q)
                    || ($0.party.siret ?? "").lowercased().contains(q)
                    || ($0.party.vatNumber ?? "").lowercased().contains(q)
                    || $0.party.city.lowercased().contains(q)
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        }
        return base.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    Button {
                        creatingNew = true
                    } label: { Label("Nouveau tiers", systemImage: "plus") }
                        .buttonStyle(.borderedProminent)
                    Text("Annuaire des tiers").font(.title2.bold())
                    HStack(spacing: 6) {
                        KindChipToggle(label: "Tous", isOn: kindFilters.isEmpty) {
                            kindFilters = []
                        }
                        ForEach([DirectoryEntryKind.client, .fournisseur, .interco], id: \.self) { kind in
                            KindChipToggle(label: kind.label, isOn: kindFilters.contains(kind)) {
                                if kindFilters.contains(kind) { kindFilters.remove(kind) }
                                else { kindFilters.insert(kind) }
                            }
                        }
                    }
                    Spacer()
                    Button { showImport = true } label: { Label("Importer", systemImage: "square.and.arrow.down") }
                        .buttonStyle(.bordered)
                    Button { showExport = true } label: { Label("Exporter", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.bordered)
                    Toggle(isOn: $showArchived) {
                        Label("Archives", systemImage: "archivebox")
                    }
                    .toggleStyle(.switch)
                    .help("Afficher les tiers archivés")
                }
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Rechercher (nom, SIREN, ville…)", text: $query)
                        .textFieldStyle(.plain)
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.clear))
            }
            .padding(12)

            Divider()

            HSplitView {
                if filtered.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "person.2").font(.largeTitle).foregroundStyle(.secondary)
                        Text("Aucun tiers dans l'annuaire.")
                            .foregroundStyle(.secondary)
                        Button("Ajouter un tiers") { creatingNew = true }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filtered, selection: Binding(
                        get: { selectedEntry?.id },
                        set: { id in
                            selectedEntry = directory.entries.first(where: { $0.id == id })
                        }
                    )) { entry in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(entry.displayName).font(.headline)
                                KindBadges(kinds: entry.kinds, kindColors: kindColors)
                                ForEach(entry.tagIDs.compactMap({ id in tagStore.tags.first(where: { $0.id == id }) }), id: \.id) { tag in
                                    Text(tag.name).font(.caption2)
                                        .padding(.horizontal, 6).padding(.vertical, 1)
                                        .background(Color(hex: tag.hexColor).opacity(0.2), in: Capsule())
                                        .foregroundColor(Color(hex: tag.hexColor))
                                }
                                if entry.isArchived {
                                    Label("Archive", systemImage: "archivebox")
                                        .font(.caption2)
                                        .padding(.horizontal, 6).padding(.vertical, 1)
                                        .background(Color.orange.opacity(0.2), in: Capsule())
                                }
                            }
                            Text(entry.party.fullAddressLine).font(.caption).foregroundStyle(.secondary)
                            if let sn = entry.party.siren?.trimmingCharacters(in: .whitespaces), !sn.isEmpty,
                               !SireneValidator.isValidSiren(sn) {
                                Label("SIREN invalide", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(Color.orange.opacity(0.2), in: Capsule())
                                    .foregroundColor(.orange)
                            }
                            if let sub = entry.subtitle.isEmpty ? nil : entry.subtitle {
                                Text(sub).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .tag(entry.id)
                        .contextMenu {
                            if canEditEntry(entry) {
                                Button {
                                    editingEntry = entry
                                } label: { Label("Modifier", systemImage: "pencil") }
                                Divider()
                                Button {
                                    var e = entry
                                    e.isArchived.toggle()
                                    directory.upsert(e)
                                } label: {
                                    Label(entry.isArchived ? "Désarchiver" : "Archiver",
                                          systemImage: entry.isArchived ? "tray.and.arrow.up" : "archivebox")
                                }
                                Divider()
                                Button(role: .destructive) {
                                    directory.delete(entry)
                                    if selectedEntry?.id == entry.id { selectedEntry = nil }
                                } label: { Label("Supprimer", systemImage: "trash") }
                            } else {
                                Text("Modification non autorisée")
                            }
                        }
                    }
                    .frame(minWidth: 220, idealWidth: 320, maxWidth: 360)
                }

                DirectoryDetailView(
                    entry: selectedEntry,
                    canEdit: selectedEntry.map { canEditEntry($0) } ?? true,
                    onEdit: { entry in editingEntry = entry },
                    onArchive: { entry in
                        guard canEditEntry(entry) else { return }
                        var e = entry
                        e.isArchived.toggle()
                        directory.upsert(e)
                        selectedEntry = e
                    },
                    onDelete: { entry in
                        guard canEditEntry(entry) else { return }
                        directory.delete(entry)
                        selectedEntry = nil
                    }
                )
                .frame(minWidth: 380)
            }
        }
        .sheet(item: $editingEntry) { entry in
            DirectoryEditorView(entry: entry, onSave: { updated in
                directory.upsert(updated)
                selectedEntry = updated
                editingEntry = nil
            }, onDelete: { toDelete in
                directory.delete(toDelete)
                if selectedEntry?.id == toDelete.id { selectedEntry = nil }
                editingEntry = nil
            })
        }
        .sheet(isPresented: $creatingNew) {
            DirectoryEditorView(initialKind: .client, defaultCompanyID: defaultCompanyID()) { newEntry in
                directory.upsert(newEntry)
                creatingNew = false
            }
        }
        .sheet(isPresented: $showExport) {
            PartyExportSheet(entries: filtered, isPresented: $showExport)
        }
        .sheet(isPresented: $showImport) {
            PartyImportSheet(
                isPresented: $showImport,
                onImport: { newEntries in
                    for e in newEntries { directory.upsert(e) }
                    showImport = false
                }
            )
        }
    }

    private func canEditEntry(_ entry: DirectoryEntry) -> Bool {
        if entry.kinds.contains(.societe) { return canManageSocietes }
        return true
    }

    private func defaultCompanyID() -> UUID? {
        let visible = auth.visibleSocieties(for: auth.currentUser)
        if visible.count == 1 { return visible.first?.id }
        return nil
    }
}

struct DirectoryDetailView: View {
    let entry: DirectoryEntry?
    let canEdit: Bool
    let onEdit: (DirectoryEntry) -> Void
    let onArchive: (DirectoryEntry) -> Void
    let onDelete: (DirectoryEntry) -> Void
    @EnvironmentObject var tagStore: TagStore
    @EnvironmentObject var kindColors: KindColorStore
    @EnvironmentObject var directory: PartyDirectory
    @State private var showRoutingEditor = false
    @State private var showContactEditor = false
    @State private var editingAddress: PartyRoutingAddress?
    @State private var editingContact: PartyContact?

    private var currentEntry: DirectoryEntry? {
        guard let id = entry?.id else { return nil }
        return directory.entries.first(where: { $0.id == id }) ?? entry
    }

    private func routingBinding(entry: DirectoryEntry) -> Binding<[PartyRoutingAddress]> {
        Binding(
            get: { directory.entries.first(where: { $0.id == entry.id })?.routingAddresses ?? entry.routingAddresses },
            set: { newValue in
                if var e = directory.entries.first(where: { $0.id == entry.id }) {
                    e.routingAddresses = newValue
                    directory.upsert(e)
                }
            }
        )
    }

    private func contactsBinding(entry: DirectoryEntry) -> Binding<[PartyContact]> {
        Binding(
            get: { directory.entries.first(where: { $0.id == entry.id })?.contacts ?? entry.contacts },
            set: { newValue in
                if var e = directory.entries.first(where: { $0.id == entry.id }) {
                    e.contacts = newValue
                    directory.upsert(e)
                }
            }
        )
    }

    var body: some View {
        if let entry = currentEntry {
            VStack(spacing: 0) {
                HStack {
                    Text(entry.displayName).font(.headline)
                    KindBadges(kinds: entry.kinds, kindColors: kindColors, font: .caption)
                    Spacer()
                    Button { onEdit(entry) } label: { Label("Modifier", systemImage: "pencil") }
                        .buttonStyle(.bordered)
                        .disabled(!canEdit)
                    Button { onArchive(entry) } label: {
                        Label(entry.isArchived ? "Désarchiver" : "Archiver",
                              systemImage: entry.isArchived ? "tray.and.arrow.up" : "archivebox")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canEdit)
                    Button(role: .destructive) { onDelete(entry) } label: { Label("Supprimer", systemImage: "trash") }
                        .buttonStyle(.bordered)
                        .disabled(!canEdit)
                }
                .padding(12)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Statut").font(.headline)
                            Spacer()
                            if entry.isArchived {
                                Label("Tiers archivé", systemImage: "archivebox")
                                    .font(.callout.bold()).foregroundStyle(.orange)
                            } else {
                                Label("Tiers actif", systemImage: "checkmark.circle")
                                    .font(.callout.bold()).foregroundStyle(.green)
                            }
                        }
                        Divider()
                        Text("Identité").font(.headline)
                        detailRow("Type", entry.kindsLabel)
                        detailRow("Nom", entry.party.name)
                        if !entry.tagIDs.isEmpty {
                            HStack(alignment: .top) {
                                Text("Tags").font(.callout.bold()).frame(width: 160, alignment: .leading)
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(entry.tagIDs.compactMap({ id in tagStore.tags.first(where: { $0.id == id }) }), id: \.id) { tag in
                                        Text(tag.name).font(.caption)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Color(hex: tag.hexColor).opacity(0.2), in: Capsule())
                                            .foregroundColor(Color(hex: tag.hexColor))
                                    }
                                }
                                Spacer()
                            }
                        }

                        HStack(alignment: .top, spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Identifiants").font(.headline)
                                if let s = entry.party.siren, !s.isEmpty {
                                    HStack(alignment: .top) {
                                        Text("SIREN").font(.callout.bold()).frame(width: 140, alignment: .leading)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(s).font(.body)
                                            if SireneValidator.isValidSiren(s) {
                                                Label("SIREN valide (clé Luhn correcte)", systemImage: "checkmark.circle.fill")
                                                    .font(.caption2).foregroundStyle(.green)
                                            } else {
                                                Label("SIREN invalide (9 chiffres attendus, clé Luhn incorrecte)", systemImage: "exclamationmark.triangle.fill")
                                                    .font(.caption2).foregroundStyle(.orange)
                                            }
                                        }
                                        Spacer()
                                    }
                                }
                                if let st = entry.party.siret, !st.isEmpty {
                                    HStack(alignment: .top) {
                                        Text("SIRET").font(.callout.bold()).frame(width: 140, alignment: .leading)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(st).font(.body)
                                            if SireneValidator.isValidSiret(st) {
                                                Label("valide (Luhn)", systemImage: "checkmark.circle.fill")
                                                    .font(.caption2).foregroundStyle(.green)
                                            } else {
                                                Label("invalide (Luhn)", systemImage: "exclamationmark.triangle.fill")
                                                    .font(.caption2).foregroundStyle(.orange)
                                            }
                                        }
                                        Spacer()
                                    }
                                }
                                if let v = entry.party.vatNumber, !v.isEmpty { detailRow("N° TVA", v) }
                                if let e = entry.party.endpointID, !e.isEmpty {
                                    detailRow("Ident. élec. (BT-49/34)", e)
                                }
                                if !entry.party.endpointSchemeID.trimmingCharacters(in: .whitespaces).isEmpty {
                                    detailRow("Scheme ident. élec.", entry.party.endpointSchemeID)
                                }
                                detailRow("Scheme légal", entry.party.legalSchemeID)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Divider()
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Adresse").font(.headline)
                                if !entry.party.street.trimmingCharacters(in: .whitespaces).isEmpty {
                                    detailRow("Rue", entry.party.street)
                                }
                                if !entry.party.postcode.trimmingCharacters(in: .whitespaces).isEmpty {
                                    detailRow("Code postal", entry.party.postcode)
                                }
                                if !entry.party.city.trimmingCharacters(in: .whitespaces).isEmpty {
                                    detailRow("Ville", entry.party.city)
                                }
                                if !entry.party.country.trimmingCharacters(in: .whitespaces).isEmpty {
                                    detailRow("Pays", entry.party.country)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Divider()
                        if entry.isPayee {
                            Text("Coordonnées bancaires").font(.headline)
                        if let iban = entry.party.iban?.trimmingCharacters(in: .whitespaces), !iban.isEmpty {
                            HStack(alignment: .top) {
                                Text("IBAN").font(.callout.bold()).frame(width: 160, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(IBANValidator.formatted(iban)).font(.system(.body, design: .monospaced))
                                    if IBANValidator.isValid(iban) {
                                        Label("IBAN valide (clé mod 97 correcte)", systemImage: "checkmark.circle.fill")
                                            .font(.caption2).foregroundStyle(.green)
                                    } else {
                                        Label("IBAN invalide (clé de contrôle incorrecte)", systemImage: "exclamationmark.triangle.fill")
                                            .font(.caption2).foregroundStyle(.orange)
                                    }
                                }
                                Spacer()
                            }
                        }
                        if let bic = entry.party.bic?.trimmingCharacters(in: .whitespaces), !bic.isEmpty {
                            detailRow("BIC", bic)
                        }
                        if let pt = entry.party.paymentTerms?.trimmingCharacters(in: .whitespaces), !pt.isEmpty {
                            detailRow("Conditions de paiement", pt)
                        }
                        if (entry.party.iban?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
                            && (entry.party.bic?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
                            && (entry.party.paymentTerms?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) {
                            Text("Aucune coordonnée bancaire renseignée.").font(.caption).foregroundStyle(.secondary)
                        }
                        }
                        Divider()
                        HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Contact(s)").font(.headline)
                            Spacer()
                            Button {
                                editingContact = nil
                                showContactEditor = true
                            } label: { Label("Créer un contact", systemImage: "plus.circle") }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                        if !entry.contacts.isEmpty {
                            ForEach(entry.contacts) { ct in
                                HStack(alignment: .top, spacing: 8) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            Text(ct.name.trimmingCharacters(in: .whitespaces).isEmpty ? "(sans nom)" : ct.name).font(.callout.bold())
                                            if ct.isDefault {
                                                Text("défaut").font(.caption).padding(.horizontal, 5).padding(.vertical, 1)
                                                    .background(Color.accentColor.opacity(0.2), in: Capsule())
                                            }
                                            if !ct.isActive {
                                                Text("inactif").font(.caption).padding(.horizontal, 5).padding(.vertical, 1)
                                                    .background(Color.gray.opacity(0.2), in: Capsule())
                                            }
                                        }
                                        if let e = ct.email?.trimmingCharacters(in: .whitespaces), !e.isEmpty { Text("Email : \(e)").font(.caption).foregroundColor(.secondary) }
                                        if let p = ct.phone?.trimmingCharacters(in: .whitespaces), !p.isEmpty { Text("Tél : \(p)").font(.caption).foregroundColor(.secondary) }
                                        if let lbl = ct.label?.trimmingCharacters(in: .whitespaces), !lbl.isEmpty { Text("Libellé : \(lbl)").font(.caption).foregroundColor(.secondary) }
                                    }
                                    Spacer()
                                    Button {
                                        editingContact = ct
                                        showContactEditor = true
                                    } label: { Image(systemName: "pencil") }
                                        .buttonStyle(.borderless)
                                        .help("Modifier ce contact")
                                    Button(role: .destructive) {
                                        var e = entry
                                        e.contacts.removeAll { $0.id == ct.id }
                                        if e.contacts.allSatisfy({ !$0.isDefault }), !e.contacts.isEmpty {
                                            e.contacts[0].isDefault = true
                                        }
                                        directory.upsert(e)
                                    } label: { Image(systemName: "trash") }
                                        .buttonStyle(.borderless)
                                        .help("Supprimer ce contact")
                                }
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.clear))
                            }
                        } else if (entry.party.contactName?.isEmpty ?? true)
                            && (entry.party.contactEmail?.isEmpty ?? true)
                            && (entry.party.contactPhone?.isEmpty ?? true) {
                            Text("Aucun contact renseigné").font(.caption).foregroundStyle(.secondary)
                        } else {
                            if let cn = entry.party.contactName, !cn.isEmpty { detailRow("Nom", cn) }
                            if let ce = entry.party.contactEmail, !ce.isEmpty { detailRow("Email", ce) }
                            if let cp = entry.party.contactPhone, !cp.isEmpty { detailRow("Téléphone", cp) }
                        }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if !entry.isSupplierOnly {
                        VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Adresses de facturation électronique").font(.headline)
                            Spacer()
                            Button {
                                editingAddress = PartyRoutingAddress(siren: entry.party.siren ?? "")
                            } label: { Label("Créer une adresse", systemImage: "plus.circle") }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                        if entry.routingAddresses.isEmpty {
                            Text("Aucune adresse de facturation électronique renseignée").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(entry.routingAddresses) { addr in
                            HStack(alignment: .top, spacing: 8) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(addr.format.label).font(.callout.bold())
                                        if addr.isDefault {
                                            Text("défaut").font(.caption).padding(.horizontal, 5).padding(.vertical, 1)
                                                .background(Color.accentColor.opacity(0.2), in: Capsule())
                                        }
                                        if !addr.isActive {
                                            Text("inactive").font(.caption).padding(.horizontal, 5).padding(.vertical, 1)
                                                .background(Color.gray.opacity(0.2), in: Capsule())
                                        }
                                    }
                                    Text(addr.composedAddress).font(.system(.callout, design: .monospaced))
                                    if let lbl = addr.label, !lbl.isEmpty {
                                        Text("Libellé : \(lbl)").font(.caption).foregroundColor(.secondary)
                                    }
                                    if let s = addr.siret, !s.isEmpty { Text("SIRET : \(s)").font(.caption).foregroundColor(.secondary) }
                                    if let suf = addr.suffixe, !suf.isEmpty { Text("Suffixe : \(suf)").font(.caption).foregroundColor(.secondary) }
                                    if let cr = addr.codeRoutage, !cr.isEmpty { Text("Code routage : \(cr)").font(.caption).foregroundColor(.secondary) }
                                }
                                Spacer()
                                Button {
                                    editingAddress = addr
                                } label: { Image(systemName: "pencil") }
                                    .buttonStyle(.borderless)
                                    .help("Modifier cette adresse")
                                Button(role: .destructive) {
                                    var e = entry
                                    e.routingAddresses.removeAll { $0.id == addr.id }
                                    if e.routingAddresses.allSatisfy({ !$0.isDefault }), !e.routingAddresses.isEmpty {
                                        e.routingAddresses[0].isDefault = true
                                    }
                                    directory.upsert(e)
                                } label: { Image(systemName: "trash") }
                                    .buttonStyle(.borderless)
                                    .help("Supprimer cette adresse")
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.clear))
                        }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        }

                        if let note = entry.note, !note.isEmpty {
                            Divider()
                            Text("Note").font(.headline)
                            Text(note).font(.callout).foregroundStyle(.secondary)
                        }
                    }.padding(14)
                }
            }
            .sheet(isPresented: $showRoutingEditor) {
                RoutingAddressQuickEditor(
                    siren: entry.party.siren ?? "",
                    addresses: routingBinding(entry: entry)
                )
            }
            .sheet(item: $editingAddress) { addr in
                RoutingAddressFormView(addresses: routingBinding(entry: entry), editing: addr)
            }
            .sheet(isPresented: $showContactEditor) {
                if let ct = editingContact {
                    ContactFormView(contacts: contactsBinding(entry: entry), editing: ct)
                } else {
                    ContactFormView(contacts: contactsBinding(entry: entry), editing: PartyContact())
                }
            }
            .onChange(of: showContactEditor) { showing in
                if !showing { editingContact = nil }
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "person.text.rectangle").font(.largeTitle).foregroundStyle(.secondary)
                Text("Sélectionnez un tiers pour voir le détail.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.callout.bold()).frame(width: 160, alignment: .leading)
            Text(value).font(.body)
            Spacer()
        }
    }
}

struct DirectoryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var directory: PartyDirectory
    @EnvironmentObject var tagStore: TagStore
    @EnvironmentObject var auth: AuthStore
    @State private var entry: DirectoryEntry
    private let isEditing: Bool
    let onSave: (DirectoryEntry) -> Void
    let onDelete: ((DirectoryEntry) -> Void)?
    @State private var duplicateMatches: [PartyDirectory.DuplicateMatch]?
    @State private var pendingSave = false

    init(entry: DirectoryEntry, onSave: @escaping (DirectoryEntry) -> Void, onDelete: ((DirectoryEntry) -> Void)? = nil) {
        _entry = State(initialValue: entry)
        self.isEditing = true
        self.onSave = onSave
        self.onDelete = onDelete
    }

    init(initialKind: DirectoryEntryKind, defaultCompanyID: UUID? = nil, onSave: @escaping (DirectoryEntry) -> Void) {
        // Une société du périmètre est toujours aussi une partie liée aux autres sociétés
        // gérées dans l'app (même utilisateur, même périmètre) — cochée Interco par défaut,
        // modifiable ensuite comme n'importe quel autre type.
        let initialKinds: Set<DirectoryEntryKind> = initialKind == .societe ? [.societe, .interco] : [initialKind]
        var initial = DirectoryEntry(kinds: initialKinds, party: InvoiceParty(name: "", street: "", postcode: "", city: ""))
        if initialKind == .client, let cid = defaultCompanyID {
            initial.companyID = cid
        }
        _entry = State(initialValue: initial)
        self.isEditing = false
        self.onSave = onSave
        self.onDelete = nil
    }

    private var headerTitle: String {
        if entry.party.name.trimmingCharacters(in: .whitespaces).isEmpty {
            return isEditing ? "Modifier le tiers" : "Nouveau tiers"
        }
        return isEditing ? "Modifier : \(entry.party.name)" : "Nouveau tiers : \(entry.party.name)"
    }

    private var canManageSocietes: Bool { auth.currentUser?.isAdmin == true }

    private var availableKinds: [DirectoryEntryKind] {
        if canManageSocietes { return DirectoryEntryKind.selectable }
        return [.client]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(headerTitle).font(.headline)
                Spacer()
                if isEditing {
                    Button {
                        entry.isArchived.toggle()
                    } label: {
                        Label(entry.isArchived ? "Désarchiver" : "Archiver",
                              systemImage: entry.isArchived ? "tray.and.arrow.up" : "archivebox")
                    }
                    .buttonStyle(.bordered)
                }
                if isEditing, let onDelete = onDelete {
                    Button(role: .destructive) {
                        onDelete(entry)
                        dismiss()
                    } label: { Label("Supprimer", systemImage: "trash") }
                        .buttonStyle(.bordered)
                }
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Enregistrer") {
                    var entry = entry
                    if let cid = entry.companyID, !auth.availableSocieties().contains(where: { $0.id == cid }) {
                        entry.companyID = nil
                    }
                    let dup = directory.findDuplicates(of: entry)
                    if dup.isEmpty {
                        onSave(entry)
                        dismiss()
                    } else {
                        duplicateMatches = dup
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Type").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(availableKinds, id: \.self) { kind in
                        KindChipToggle(label: kind.label, isOn: entry.kinds.contains(kind)) {
                            if entry.kinds.contains(kind) {
                                // Un tiers doit toujours garder au moins un type — on
                                // ignore silencieusement le dernier décochage plutôt que
                                // d'autoriser un ensemble vide dénué de sens.
                                if entry.kinds.count > 1 { entry.kinds.remove(kind) }
                            } else {
                                entry.kinds.insert(kind)
                            }
                        }
                    }
                    Spacer()
                }
            }

            if entry.kinds.contains(.client) {
                GroupBox("Société (périmètre)") {
                    HStack {
                        Text("Société").frame(width: 80, alignment: .leading)
                        Picker("Société", selection: Binding<UUID?>(
                            get: { entry.companyID },
                            set: { entry.companyID = $0 }
                        )) {
                            Text("Aucune").tag(UUID?.none)
                            ForEach(auth.visibleSocieties(for: auth.currentUser)) { s in
                                Text(s.displayName).tag(Optional(s.id))
                            }
                        }
                        Spacer()
                    }.padding(4)
                }
            }

            GroupBox("Identité et adresse") {
                PartyEditorView(party: $entry.party, routingAddresses: $entry.routingAddresses, contacts: $entry.contacts, isSociete: entry.kinds.contains(.societe), hideBankDetails: !entry.isPayee, hideElectronicAddress: entry.isSupplierOnly)
            }

            if !tagStore.tags.isEmpty {
                GroupBox("Tags") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(tagStore.tags) { tag in
                            Toggle(isOn: Binding(
                                get: { entry.tagIDs.contains(tag.id) },
                                set: { isOn in
                                    if isOn { entry.tagIDs.append(tag.id) }
                                    else { entry.tagIDs.removeAll { $0 == tag.id } }
                                }
                            )) {
                                HStack {
                                    Text(tag.name)
                                    Text("●").foregroundColor(Color(hex: tag.hexColor))
                                }
                            }
                        }
                    }
                }
            }

            TextField("Note (optionnel)", text: Binding($entry.note, replacingNilWith: ""))
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 560)
        .onChange(of: entry.routingAddresses) { _ in
            // L'identifiant électronique affiché sur la fiche (BT-49/34, champ "Ident. élec.")
            // et la liste "Adresses de facturation électronique" ci-dessus pouvaient diverger :
            // modifier la liste (ajout, suppression, changement de défaut) ne rafraîchissait
            // jamais le champ sur le tiers, qui restait sur son ancienne valeur saisie ou
            // choisie précédemment. Recalé automatiquement sur l'adresse par défaut active.
            if let def = entry.defaultRoutingAddress, def.isActive {
                let composed = def.composedAddress.trimmingCharacters(in: .whitespaces)
                if !composed.isEmpty {
                    entry.party.endpointID = composed
                    entry.party.endpointSchemeID = "0225"
                }
            }
        }
        .alert("Tiers potentiellement en doublon", isPresented: Binding(
            get: { duplicateMatches != nil },
            set: { if !$0 { duplicateMatches = nil } }
        )) {
            Button("Enregistrer quand même", role: .destructive) {
                onSave(entry)
                dismiss()
                duplicateMatches = nil
            }
            Button("Annuler", role: .cancel) {
                duplicateMatches = nil
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
}

struct RoutingAddressFormView: View {
    @Binding var addresses: [PartyRoutingAddress]
    @State private var draft: PartyRoutingAddress
    @Environment(\.dismiss) private var dismiss
    private let existingID: UUID?

    init(addresses: Binding<[PartyRoutingAddress]>, editing: PartyRoutingAddress) {
        _addresses = addresses
        _draft = State(initialValue: editing)
        existingID = editing.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(existingID == nil ? "Nouvelle adresse de routage" : "Modifier l'adresse de routage").font(.headline)
            Picker("Format", selection: $draft.format) {
                ForEach(RoutingAddressFormat.allCases, id: \.self) { Text($0.label).tag($0) }
            }.pickerStyle(.segmented)
            Text(draft.format.help).font(.caption).foregroundColor(.secondary)

            TextField("SIREN (9 chiffres)", text: $draft.siren)
            if draft.format == .sirenSiret || draft.format == .sirenSiretCodeRoutage {
                TextField("SIRET (14 chiffres)", text: Binding($draft.siret, replacingNilWith: ""))
            }
            if draft.format == .sirenSuffixe {
                TextField("Suffixe", text: Binding($draft.suffixe, replacingNilWith: ""))
            }
            if draft.format == .sirenSiretCodeRoutage {
                TextField("Code de routage", text: Binding($draft.codeRoutage, replacingNilWith: ""))
            }
            TextField("Libellé (optionnel)", text: Binding($draft.label, replacingNilWith: ""))
            Toggle("Adresse active", isOn: $draft.isActive)
                .toggleStyle(.switch)
            Toggle("Adresse par défaut", isOn: $draft.isDefault)
                .toggleStyle(.switch)
            HStack {
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Enregistrer") {
                    if draft.isDefault {
                        for i in addresses.indices { addresses[i].isDefault = false }
                    }
                    if let id = existingID, let idx = addresses.firstIndex(where: { $0.id == id }) {
                        addresses[idx] = draft
                    } else {
                        if addresses.isEmpty { draft.isDefault = true }
                        addresses.append(draft)
                    }
                    if addresses.allSatisfy({ !$0.isDefault }), !addresses.isEmpty {
                        addresses[0].isDefault = true
                    }
                    dismiss()
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }.padding(16).frame(minWidth: 420, minHeight: 360)
    }
}

struct CapsuleToggleButton: View {
    let title: String
    @Binding var isOn: Bool
    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "checkmark" : "")
                    .font(.caption.weight(.bold))
                    .frame(width: 12)
                Text(title)
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(isOn ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                Capsule().stroke(isOn ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: 1)
            )
            .foregroundStyle(isOn ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
    }
}

struct ContactFormView: View {
    @Binding var contacts: [PartyContact]
    @State private var draft: PartyContact
    @Environment(\.dismiss) private var dismiss
    private let existingID: UUID?

    init(contacts: Binding<[PartyContact]>, editing: PartyContact) {
        _contacts = contacts
        _draft = State(initialValue: editing)
        existingID = editing.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(existingID == nil ? "Nouveau contact" : "Modifier le contact").font(.headline)
            TextField("Nom", text: $draft.name)
            TextField("Email", text: Binding($draft.email, replacingNilWith: ""))
            TextField("Téléphone", text: Binding($draft.phone, replacingNilWith: ""))
            TextField("Libellé (optionnel)", text: Binding($draft.label, replacingNilWith: ""))
            HStack(spacing: 10) {
                CapsuleToggleButton(title: "Contact actif", isOn: $draft.isActive)
                CapsuleToggleButton(title: "Contact par défaut", isOn: $draft.isDefault)
                Spacer()
            }
            HStack {
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Enregistrer") {
                    if draft.isDefault {
                        for i in contacts.indices { contacts[i].isDefault = false }
                    }
                    if let id = existingID, let idx = contacts.firstIndex(where: { $0.id == id }) {
                        contacts[idx] = draft
                    } else {
                        if contacts.isEmpty { draft.isDefault = true }
                        contacts.append(draft)
                    }
                    if contacts.allSatisfy({ !$0.isDefault }), !contacts.isEmpty {
                        contacts[0].isDefault = true
                    }
                    dismiss()
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }.padding(16).frame(minWidth: 420, minHeight: 320)
    }
}

struct ContactPickerSheet: View {
    let entry: DirectoryEntry
    let onPick: (PartyContact?) -> Void
    @EnvironmentObject var directory: PartyDirectory
    @Environment(\.dismiss) private var dismiss
    @State private var showEditor = false
    @State private var editing: PartyContact?
    @State private var drafts: [PartyContact]

    init(entry: DirectoryEntry, onPick: @escaping (PartyContact?) -> Void) {
        self.entry = entry
        self.onPick = onPick
        _drafts = State(initialValue: entry.contacts)
    }

    private var contactsBinding: Binding<[PartyContact]> {
        Binding(
            get: { drafts },
            set: { drafts = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Contacts — \(entry.displayName)").font(.headline)
                Spacer()
                Button("Fermer") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(12)
            Divider()
            if drafts.isEmpty {
                Text("Aucun contact. Cliquez « Nouveau » pour en créer un.")
                    .foregroundStyle(.secondary).padding()
            } else {
                List {
                    ForEach(drafts) { ct in
                        HStack(spacing: 8) {
                            Button {
                                onPick(ct); dismiss()
                            } label: {
                                HStack(spacing: 8) {
                                    if ct.isDefault {
                                        Text("défaut").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(Color.accentColor.opacity(0.2), in: Capsule())
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ct.name.trimmingCharacters(in: .whitespaces).isEmpty ? "(sans nom)" : ct.name)
                                            .font(.body.weight(.medium))
                                        if let e = ct.email?.trimmingCharacters(in: .whitespaces), !e.isEmpty {
                                            Text(e).font(.caption).foregroundStyle(.secondary)
                                        }
                                        if let p = ct.phone?.trimmingCharacters(in: .whitespaces), !p.isEmpty {
                                            Text(p).font(.caption).foregroundStyle(.secondary)
                                        }
                                        if !ct.isActive {
                                            Text("inactif").font(.caption2)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Button {
                                editing = ct
                                showEditor = true
                            } label: { Image(systemName: "pencil") }
                                .buttonStyle(.borderless)
                                .help("Modifier ce contact")
                        }
                    }
                }
            }
            HStack {
                Button {
                    editing = nil
                    showEditor = true
                } label: { Label("Nouveau contact", systemImage: "plus") }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Aucun contact") { onPick(nil); dismiss() }
            }.padding(12)
        }
        .frame(minWidth: 460, minHeight: 320)
        .sheet(isPresented: $showEditor) {
            if let ct = editing {
                ContactFormView(contacts: contactsBinding, editing: ct)
            } else {
                ContactFormView(contacts: contactsBinding, editing: PartyContact())
            }
        }
        .onChange(of: showEditor) { showing in
            guard !showing else { return }
            var e = entry
            e.contacts = drafts
            directory.upsert(e)
            editing = nil
        }
    }
}

struct RoutingPickerSheet: View {
    let entry: DirectoryEntry
    let onPick: (PartyRoutingAddress?) -> Void
    @EnvironmentObject var directory: PartyDirectory
    @Environment(\.dismiss) private var dismiss
    @State private var showEditor = false
    @State private var editing: PartyRoutingAddress?
    @State private var drafts: [PartyRoutingAddress]

    init(entry: DirectoryEntry, onPick: @escaping (PartyRoutingAddress?) -> Void) {
        self.entry = entry
        self.onPick = onPick
        _drafts = State(initialValue: entry.routingAddresses)
    }

    private var routingBinding: Binding<[PartyRoutingAddress]> {
        Binding(
            get: { drafts },
            set: { drafts = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Adresses de facturation électronique — \(entry.displayName)").font(.headline)
                Spacer()
                Button("Fermer") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(12)
            Divider()
            if drafts.isEmpty {
                Text("Aucune adresse. Cliquez « Nouvelle » pour en créer une.")
                    .foregroundStyle(.secondary).padding()
            } else {
                List {
                    ForEach(drafts) { addr in
                        Button {
                            onPick(addr); dismiss()
                        } label: {
                            HStack(spacing: 8) {
                                if addr.isDefault {
                                    Text("défaut").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Color.accentColor.opacity(0.2), in: Capsule())
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(addr.format.label).font(.caption.bold())
                                    Text(addr.composedAddress).font(.system(.body, design: .monospaced))
                                    if let l = addr.label, !l.isEmpty { Text(l).font(.caption2).foregroundStyle(.secondary) }
                                    if !addr.isActive { Text("inactive").font(.caption2) }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack {
                Button {
                    editing = nil
                    showEditor = true
                } label: { Label("Nouvelle adresse", systemImage: "plus") }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Aucune adresse") { onPick(nil); dismiss() }
            }.padding(12)
        }
        .frame(minWidth: 480, minHeight: 340)
        .sheet(isPresented: $showEditor) {
            if let addr = editing {
                RoutingAddressFormView(addresses: routingBinding, editing: addr)
            } else {
                RoutingAddressFormView(addresses: routingBinding, editing: PartyRoutingAddress(siren: entry.party.siren ?? ""))
            }
        }
        .onChange(of: showEditor) { showing in
            guard !showing else { return }
            var e = entry
            e.routingAddresses = drafts
            directory.upsert(e)
            editing = nil
        }
    }
}

struct PartyLogoEditor: View {
    let entry: DirectoryEntry
    @EnvironmentObject var directory: PartyDirectory
    @Binding var isPresented: Bool

    private var currentLogo: Data? { entry.logoData }

    var body: some View {
        VStack(spacing: 16) {
            Text("Logo « \(entry.displayName) »").font(.headline)
            Text("Image (PNG, JPEG ou TIFF) affichée en en-tête du PDF lisible des factures émises par cette société. Le logo n'est pas embarqué dans le XML Factur-X.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)

            if let data = currentLogo, let img = NSImage(data: data) {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 220, maxHeight: 90)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).stroke(.secondary, lineWidth: 0.5))
                Text("Logo chargé (\(data.count) octets)").font(.caption2).foregroundStyle(.secondary)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("Aucun logo pour cette société").font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Button {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.png, .jpeg, .tiff]
                    panel.allowsMultipleSelection = false
                    panel.canChooseDirectories = false
                    if panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) {
                        var e = entry
                        e.logoData = data
                        directory.upsert(e)
                    }
                } label: { Label(currentLogo == nil ? "Choisir une image…" : "Remplacer…", systemImage: "folder") }
                .buttonStyle(.bordered)

                if currentLogo != nil {
                    Button(role: .destructive) {
                        var e = entry
                        e.logoData = nil
                        directory.upsert(e)
                    } label: { Label("Retirer", systemImage: "trash") }
                        .buttonStyle(.bordered)
                }
            }

            Spacer()
            Button("Fermer") { isPresented = false }
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(width: 420, height: 320)
    }
}
