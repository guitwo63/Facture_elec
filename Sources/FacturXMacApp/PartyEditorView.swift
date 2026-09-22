import SwiftUI
import FacturXCore

// MARK: - Extrait de FacturXMacApp.swift (découpage par domaine)

struct PartyEditorView: View {
    @Binding var party: InvoiceParty
    @Binding var routingAddresses: [PartyRoutingAddress]
    @Binding var contacts: [PartyContact]
    var showWebButton: Bool
    var isSociete: Bool = false
    var hideEmail: Bool = false
    var hideBankDetails: Bool = false
    var hideElectronicAddress: Bool = false
    var locked: Bool = false
    var isMultiContact: Bool
    var directory: PartyDirectory?
    var onPickContact: ((PartyContact) -> Void)?
    var onPickRouting: ((PartyRoutingAddress) -> Void)?
    var onPartyPicked: ((InvoiceParty) -> Void)?
    @State private var showRoutingEditor = false
    @State private var editingAddress: PartyRoutingAddress?
    @State private var showContactEditor = false
    @State private var editingContact: PartyContact?
    @State private var showContactPicker = false
    @State private var showRoutingPicker = false
    @State private var dinumResults: [SireneResult] = []
    @State private var dinumLoading = false
    @State private var dinumError: String?
    @State private var lastSearchKey: String = ""
    @State private var superPDPLookupLoading = false
    @State private var superPDPLookupNote: String?
    @State private var superPDPAddressChoices: [SuperPDPDirectoryEntry] = []
    @EnvironmentObject var paymentTermsStore: PaymentTermsPresetStore
    @EnvironmentObject var superPDPSettings: SuperPDPSettings

    /// `nil` = "Personnalisé" (saisie libre) ; sinon l'id du préréglage sélectionné.
    private var paymentTermsPresetIDBinding: Binding<String?> {
        Binding(
            get: { paymentTermsStore.matchingPresetID(for: party.paymentTerms) },
            set: { newID in
                guard let id = newID, let preset = paymentTermsStore.presets.first(where: { $0.id == id }) else { return }
                party.paymentTerms = preset.text
            }
        )
    }

    init(party: Binding<InvoiceParty>, routingAddresses: Binding<[PartyRoutingAddress]>? = nil, contacts: Binding<[PartyContact]>? = nil, showWebButton: Bool = true, isSociete: Bool = false, hideEmail: Bool = false, hideBankDetails: Bool = false, hideElectronicAddress: Bool = false, locked: Bool = false, directory: PartyDirectory? = nil, onPickContact: ((PartyContact) -> Void)? = nil, onPickRouting: ((PartyRoutingAddress) -> Void)? = nil, onPartyPicked: ((InvoiceParty) -> Void)? = nil) {
        self._party = party
        self.showWebButton = showWebButton
        self.isSociete = isSociete
        self.hideEmail = hideEmail
        self.hideBankDetails = hideBankDetails
        self.hideElectronicAddress = hideElectronicAddress
        self.locked = locked
        self.isMultiContact = contacts != nil
        self.directory = directory
        self.onPickContact = onPickContact
        self.onPickRouting = onPickRouting
        self.onPartyPicked = onPartyPicked
        if let ra = routingAddresses {
            self._routingAddresses = ra
        } else {
            self._routingAddresses = .constant([])
        }
        if let ct = contacts {
            self._contacts = ct
        } else {
            self._contacts = .constant([])
        }
    }

    private var linkedEntry: DirectoryEntry? {
        guard let dir = directory else { return nil }
        let siren = (party.siren ?? "").filter { $0.isNumber }
        if siren.count == 9, let e = dir.entries.first(where: { ($0.party.siren ?? "").filter { $0.isNumber } == siren }) {
            return e
        }
        let name = party.name.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { return dir.entries.first(where: { $0.party.name.trimmingCharacters(in: .whitespaces) == name }) }
        return nil
    }

    private var star: some View { Text(" *").foregroundColor(.red) }

    private var searchTrigger: String {
        "\((party.name.trimmingCharacters(in: .whitespaces)))|\((party.siren ?? ""))"
    }

    @State private var addressExpanded = false
    @FocusState private var addressFieldFocused: Bool

    private var addressSummary: String {
        let cityLine = [party.postcode, party.city]
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: " ")
        let parts = [party.street, cityLine].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return parts.isEmpty ? "Adresse non renseignée" : parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if showWebButton {
                    Button {
                        openWebDirectory()
                    } label: {
                        Label("Annuaire web", systemImage: "safari")
                    }
                    .buttonStyle(.bordered)
                    .help("Ouvre l'annuaire public Chorus Pro dans le navigateur")
                }
                if dinumLoading { ProgressView().controlSize(.small) }
                Spacer()
            }
            if let err = dinumError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
            HStack { Text("Nom").font(.caption); star }
            TextField("Nom", text: $party.name)
                .onChange(of: party.name) { _ in scheduleDinumSearch() }
            VStack(alignment: .leading, spacing: 6) {
                Group {
                    if addressExpanded || addressFieldFocused {
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Adresse", text: $party.street)
                                .focused($addressFieldFocused)
                            HStack(spacing: 8) {
                                TextField("Code postal", text: $party.postcode).frame(width: 90)
                                    .focused($addressFieldFocused)
                                TextField("Ville", text: $party.city)
                                    .focused($addressFieldFocused)
                                HStack(spacing: 2) {
                                    Text("Pays").font(.caption); star
                                    NormRefPicker("Pays", options: NormRefs.countries, code: $party.country).frame(width: 160)
                                }
                            }
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "location").font(.caption2).foregroundStyle(.secondary)
                            Text(addressSummary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .onHover { hovering in addressExpanded = hovering }
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Text("SIREN").font(.caption); star
                        TextField("SIREN (9 chiffres)", text: Binding($party.siren, replacingNilWith: ""))
                            .frame(width: 130)
                            .onChange(of: party.siren) { _ in scheduleDinumSearch() }
                        if let sn = party.siren?.trimmingCharacters(in: .whitespaces), !sn.isEmpty {
                            Image(systemName: SireneValidator.isValidSiren(sn) ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(SireneValidator.isValidSiren(sn) ? .green : .orange)
                                .help(SireneValidator.isValidSiren(sn) ? "SIREN valide" : "SIREN invalide")
                        }
                    }
                    HStack(spacing: 4) {
                        Text("TVA").font(.caption)
                        TextField("N° TVA", text: Binding($party.vatNumber, replacingNilWith: "")).frame(width: 130)
                    }
                    HStack(spacing: 4) {
                        Text("SIRET").font(.caption)
                        TextField("SIRET (14 chiffres)", text: Binding($party.siret, replacingNilWith: "")).frame(width: 150)
                        if let st = party.siret?.trimmingCharacters(in: .whitespaces), !st.isEmpty {
                            Image(systemName: SireneValidator.isValidSiret(st) ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(SireneValidator.isValidSiret(st) ? .green : .orange)
                                .help(SireneValidator.isValidSiret(st) ? "SIRET valide" : "SIRET invalide")
                        }
                    }
                }
            }
            if !hideElectronicAddress {
                HStack {
                    Text("Ident. élec. (BT-49/34)").font(.caption)
                    if linkedEntry != nil {
                        Text((party.endpointID ?? "").isEmpty ? "Aucune" : (party.endpointID ?? ""))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if !locked {
                            Button {
                                showRoutingPicker = true
                            } label: { Image(systemName: "envelope.circle.fill").font(.title3) }
                                .buttonStyle(.borderless)
                                .help("Choisir ou créer une adresse électronique depuis la fiche tiers")
                        }
                    } else {
                        TextField("Auto depuis SIREN si vide", text: Binding($party.endpointID, replacingNilWith: ""))
                        NormRefPicker("Scheme", options: NormRefs.endpointSchemes, code: $party.endpointSchemeID).frame(width: 180)
                        if !locked, superPDPSettings.credentials.isConfigured {
                            Button {
                                lookupSuperPDPElectronicAddress()
                            } label: {
                                if superPDPLookupLoading {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "magnifyingglass.circle.fill").font(.title3)
                                }
                            }
                            .buttonStyle(.borderless)
                            .disabled(superPDPLookupLoading || !canLookupSuperPDPElectronicAddress)
                            .help("Rechercher l'adresse électronique sur SUPER PDP à partir du SIREN/SIRET")
                        }
                    }
                }
                if !locked, linkedEntry == nil, let note = superPDPLookupNote {
                    Text(note).font(.caption2).foregroundStyle(.secondary)
                }
            }
            if isMultiContact {
                HStack {
                    Text("Contacts").font(.caption)
                    Spacer()
                    if !locked {
                        Button {
                            editingContact = nil
                            showContactEditor = true
                        } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                            .buttonStyle(.borderless)
                            .help("Ajouter un contact")
                    }
                }
                if contacts.isEmpty {
                    Text("Aucun contact").font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(contacts) { ct in
                        HStack(spacing: 8) {
                            if ct.isDefault {
                                Text("défaut").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Color.accentColor.opacity(0.2), in: Capsule())
                            }
                            Text(ct.name.trimmingCharacters(in: .whitespaces).isEmpty ? "(sans nom)" : ct.name)
                                .font(.callout.bold())
                            if let e = ct.email?.trimmingCharacters(in: .whitespaces), !e.isEmpty {
                                Text(e).font(.callout).foregroundStyle(.secondary)
                            }
                            if let p = ct.phone?.trimmingCharacters(in: .whitespaces), !p.isEmpty {
                                Text(p).font(.callout).foregroundStyle(.secondary)
                            }
                            if !ct.isActive {
                                Text("inactif").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Color.gray.opacity(0.2), in: Capsule())
                            }
                            Spacer()
                            if !locked {
                                Button {
                                    editingContact = ct
                                    showContactEditor = true
                                } label: { Image(systemName: "pencil") }
                                    .buttonStyle(.borderless)
                                    .help("Modifier ce contact")
                                Button(role: .destructive) {
                                    contacts.removeAll { $0.id == ct.id }
                                    if contacts.allSatisfy({ !$0.isDefault }), !contacts.isEmpty {
                                        contacts[0].isDefault = true
                                    }
                                } label: { Image(systemName: "trash") }
                                    .buttonStyle(.borderless)
                                    .help("Supprimer ce contact")
                            }
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.clear))
                    }
                }
            } else if linkedEntry != nil {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Contact").font(.caption)
                        Spacer()
                        if !locked {
                            Button {
                                showContactPicker = true
                            } label: { Image(systemName: "person.crop.circle.fill.badge.checkmark").font(.title3) }
                                .buttonStyle(.borderless)
                                .help("Choisir ou créer un contact depuis la fiche tiers")
                        }
                    }
                    let name = party.contactName?.trimmingCharacters(in: .whitespaces) ?? ""
                    let email = hideEmail ? "" : (party.contactEmail?.trimmingCharacters(in: .whitespaces) ?? "")
                    let phone = party.contactPhone?.trimmingCharacters(in: .whitespaces) ?? ""
                    if name.isEmpty && email.isEmpty && phone.isEmpty {
                        Text("Aucun contact").font(.callout).foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 8) {
                            Text(name.isEmpty ? "(sans nom)" : name).font(.callout.bold())
                            if !email.isEmpty { Text(email).font(.callout).foregroundStyle(.secondary) }
                            if !phone.isEmpty { Text(phone).font(.callout).foregroundStyle(.secondary) }
                            Spacer()
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.clear))
                    }
                }
            } else {
                HStack {
                    TextField("Contact", text: Binding($party.contactName, replacingNilWith: ""))
                    if !hideEmail {
                        TextField("Email", text: Binding($party.contactEmail, replacingNilWith: ""))
                    }
                    TextField("Téléphone", text: Binding($party.contactPhone, replacingNilWith: ""))
                }
            }
            if !hideElectronicAddress, linkedEntry == nil, !locked {
                Button {
                    showRoutingEditor = true
                } label: {
                    Label("Adresses de facturation électronique", systemImage: "envelope.badge")
                }
                .buttonStyle(.bordered)
            }
            if isSociete, !hideBankDetails {
                DisclosureGroup("Coordonnées bancaires & conditions de paiement") {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("IBAN", text: Binding($party.iban, replacingNilWith: ""))
                            .textCase(.uppercase)
                        if let iban = party.iban?.trimmingCharacters(in: .whitespaces), !iban.isEmpty {
                            if IBANValidator.isValid(iban) {
                                Label("IBAN valide (clé mod 97 correcte)", systemImage: "checkmark.circle.fill")
                                    .font(.caption2).foregroundStyle(.green)
                            } else {
                                Label("IBAN invalide (clé de contrôle incorrecte ou longueur pays inattendue)", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption2).foregroundStyle(.orange)
                            }
                        }
                        TextField("BIC", text: Binding($party.bic, replacingNilWith: ""))
                            .textCase(.uppercase)
                        Picker("Conditions de paiement", selection: paymentTermsPresetIDBinding) {
                            ForEach(paymentTermsStore.presets) { preset in
                                Text(preset.label).tag(Optional(preset.id))
                            }
                            Text("Personnalisé").tag(String?.none)
                        }
                        if paymentTermsPresetIDBinding.wrappedValue == nil {
                            TextField("Texte libre", text: Binding($party.paymentTerms, replacingNilWith: ""))
                        }
                    }
                }
                .font(.caption)
            }
            if !hideElectronicAddress, !routingAddresses.isEmpty {
                ForEach(routingAddresses) { addr in
                    HStack(spacing: 8) {
                        Text(addr.format.label).font(.callout.bold())
                        Text(addr.composedAddress).font(.system(.callout, design: .monospaced))
                        if addr.isDefault {
                            Text("défaut").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.2), in: Capsule())
                        }
                        Spacer()
                        if !locked {
                            Button {
                                editingAddress = addr
                            } label: { Image(systemName: "pencil") }
                                .buttonStyle(.borderless)
                                .help("Modifier cette adresse")
                            Button(role: .destructive) {
                                routingAddresses.removeAll { $0.id == addr.id }
                                if routingAddresses.allSatisfy({ !$0.isDefault }), !routingAddresses.isEmpty {
                                    routingAddresses[0].isDefault = true
                                }
                            } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                                .help("Supprimer cette adresse")
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.clear))
                }
            }
            if !dinumResults.isEmpty {
                Divider()
                Text("Suggestions (DINUM)").font(.caption.bold())
                ForEach(dinumResults, id: \.self) { r in
                    Button {
                        party = r.merged(into: party)
                        dinumResults = []
                        dinumError = nil
                        dinumLoading = false
                        lastSearchKey = searchTrigger
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.denomination ?? r.siren).font(.body.weight(.semibold))
                            HStack(spacing: 8) {
                                Text("SIREN : \(r.siren)").font(.caption).foregroundStyle(.secondary)
                                if let v = r.vatNumber { Text("TVA : \(v)").font(.caption).foregroundStyle(.secondary) }
                            }
                            if let st = r.street, let pc = r.postcode, let c = r.city {
                                Text("\(st) \(pc) \(c)").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }.padding(8)
        .sheet(isPresented: $showRoutingEditor) {
            RoutingAddressQuickEditor(
                siren: party.siren ?? "",
                addresses: $routingAddresses
            )
        }
        .sheet(item: $editingAddress) { addr in
            RoutingAddressFormView(addresses: $routingAddresses, editing: addr)
        }
        .sheet(isPresented: $showContactEditor) {
            if let ct = editingContact {
                ContactFormView(contacts: $contacts, editing: ct)
            } else {
                ContactFormView(contacts: $contacts, editing: PartyContact())
            }
        }
        .onChange(of: showContactEditor) { showing in
            if !showing { editingContact = nil }
        }
        .sheet(isPresented: $showContactPicker) {
            if let e = linkedEntry {
                ContactPickerSheet(entry: e) { contact in
                    if let c = contact {
                        onPickContact?(c)
                    } else {
                        var p = party
                        p.contactName = nil
                        p.contactEmail = nil
                        p.contactPhone = nil
                        party = p
                        onPartyPicked?(p)
                    }
                }
            }
        }
        .sheet(isPresented: $showRoutingPicker) {
            if let e = linkedEntry {
                RoutingPickerSheet(entry: e) { routing in
                    if let r = routing {
                        onPickRouting?(r)
                    } else {
                        var p = party
                        p.endpointID = nil
                        party = p
                        onPartyPicked?(p)
                    }
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { !superPDPAddressChoices.isEmpty },
            set: { if !$0 { superPDPAddressChoices = [] } }
        )) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Plusieurs adresses électroniques trouvées").font(.headline).padding(12)
                Text("Ce SIREN/SIRET correspond à plusieurs établissements sur SUPER PDP. Choisissez l'adresse à utiliser.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.bottom, 8)
                Divider()
                List(superPDPAddressChoices) { entry in
                    Button {
                        applySuperPDPMatch(entry)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name ?? entry.routingAddress ?? "—").font(.body.weight(.medium))
                            Text(entry.routingAddress ?? "").font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(minWidth: 420, minHeight: 320)
        }
    }

    private var canLookupSuperPDPElectronicAddress: Bool {
        let siren = (party.siren ?? "").filter { $0.isNumber }
        let siret = (party.siret ?? "").filter { $0.isNumber }
        return siren.count == 9 || siret.count == 14
    }

    /// Recherche manuelle de l'adresse électronique SUPER PDP pour le SIREN/SIRET saisi —
    /// même logique que `PartySection.saveToDirectory()`, mais déclenchée explicitement ici
    /// car cette vue sert aussi à la création directe d'un tiers depuis l'Annuaire, un
    /// chemin qui ne passait jusque-là par aucune recherche automatique.
    private func lookupSuperPDPElectronicAddress() {
        let siren = (party.siren ?? "").filter { $0.isNumber }
        let siret = (party.siret ?? "").filter { $0.isNumber }
        guard superPDPSettings.credentials.isConfigured, siren.count == 9 || siret.count == 14 else { return }
        superPDPLookupLoading = true
        superPDPLookupNote = nil
        let query = siret.count == 14 ? siret : siren
        Task {
            do {
                let results = try await SuperPDPService().searchRecipient(siretOrSiren: query, credentials: superPDPSettings.credentials)
                let withAddress = results.filter { !($0.routingAddress ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
                let distinctAddresses = Set(withAddress.map { $0.routingAddress ?? "" })
                if distinctAddresses.count > 1 {
                    superPDPAddressChoices = withAddress
                } else if let match = withAddress.first {
                    applySuperPDPMatch(match)
                    superPDPLookupNote = "Adresse électronique trouvée sur SUPER PDP."
                } else {
                    superPDPLookupNote = "Aucune adresse électronique trouvée sur SUPER PDP pour ce SIREN/SIRET."
                }
            } catch {
                superPDPLookupNote = "Recherche SUPER PDP indisponible : \(error.localizedDescription)"
            }
            superPDPLookupLoading = false
        }
    }

    private func applySuperPDPMatch(_ match: SuperPDPDirectoryEntry) {
        guard let addr = match.routingAddress?.trimmingCharacters(in: .whitespaces), !addr.isEmpty else { return }
        party.endpointID = addr
        party.endpointSchemeID = match.routingScheme?.trimmingCharacters(in: .whitespaces).isEmpty == false ? match.routingScheme! : "0225"
        let siren = (party.siren ?? "").filter { $0.isNumber }
        let siret = (party.siret ?? "").filter { $0.isNumber }
        if !siren.isEmpty {
            let format: RoutingAddressFormat = siret.count == 14 ? .sirenSiret : .siren
            let newAddress = PartyRoutingAddress(
                format: format, siren: siren, siret: siret.count == 14 ? siret : nil,
                label: "SUPER PDP", isActive: true, isDefault: routingAddresses.isEmpty
            )
            if !routingAddresses.contains(where: { $0.composedAddress == newAddress.composedAddress }) {
                routingAddresses.append(newAddress)
            }
        }
        superPDPAddressChoices = []
    }

    private func scheduleDinumSearch() {
        let key = searchTrigger
        guard key != lastSearchKey else { return }
        lastSearchKey = key
        let name = party.name.trimmingCharacters(in: .whitespaces)
        let siren = (party.siren ?? "").filter { $0.isNumber }
        if name.count < 3 && siren.count < 9 {
            dinumResults = []
            dinumError = nil
            return
        }
        let query = siren.count >= 9 ? siren : name
        guard !query.isEmpty else { return }
        dinumLoading = true
        dinumError = nil
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            let currentKey = searchTrigger
            guard currentKey == key else { return }
            do {
                let res = try await SireneService().lookup(query: query)
                await MainActor.run {
                    dinumResults = res
                    dinumLoading = false
                }
            } catch let e as SireneError {
                await MainActor.run { dinumError = e.errorDescription; dinumLoading = false }
            } catch {
                await MainActor.run { dinumError = error.localizedDescription; dinumLoading = false }
            }
        }
    }

    private func openWebDirectory() {
        let base = "https://facturation.chorus-pro.gouv.fr/annuaire/"
        if let url = URL(string: base) {
            NSWorkspace.shared.open(url)
        }
    }
}
