import SwiftUI
import FacturXCore
import AppKit

// MARK: - Extrait de FacturXMacApp.swift (découpage par domaine)

struct SettingsTabView: View {
    @EnvironmentObject var auth: AuthStore
    @State private var settingsTab = 0

    private struct TabItem { let index: Int; let label: String; let icon: String }

    /// Un `Picker` en style segmenté n'affiche pas fiablement l'icône d'un `Label` sur
    /// macOS (texte seul par segment) — même limitation que celle qui a motivé le
    /// remplacement de la barre de navigation principale par de vrais boutons. Mêmes
    /// boutons ici plutôt que de refaire la même erreur.
    private var tabs: [TabItem] {
        var items = [TabItem(index: 0, label: "Profil", icon: "person.crop.circle")]
        if auth.currentUser?.isAdmin == true {
            items.append(contentsOf: [
                TabItem(index: 1, label: "Tables", icon: "tablecells"),
                TabItem(index: 2, label: "Application", icon: "gearshape.2"),
                TabItem(index: 5, label: "Connexions", icon: "network"),
                TabItem(index: 6, label: "Par société", icon: "building.2.crop.circle")
            ])
        }
        // Le journal (historique des statuts) est utile à tous les rôles, pas
        // seulement à l'administrateur : un comptable doit pouvoir suivre le
        // cycle de vie des factures/commandes/devis. `AuditLogView` masque de
        // son côté les entrées liées aux comptes utilisateurs pour les non-admins.
        items.append(TabItem(index: 3, label: "Journal", icon: "clock.arrow.circlepath"))
        if auth.currentUser?.isAdmin == true {
            items.append(TabItem(index: 4, label: "Données", icon: "externaldrive.fill"))
        }
        return items
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(tabs, id: \.index) { tab in
                    settingsTabButton(tab)
                }
                Spacer()
            }
            .padding(10)
            Divider()
            switch settingsTab {
            case 0:
                ProfileSettingsView()
            case 1:
                ValueTablesView()
            case 3:
                AuditLogView()
            case 4:
                DataAdminView()
            case 5:
                ConnectionsSettingsView()
            case 6:
                ConfigureSocieteView()
            default:
                ApplicationSettingsView()
            }
        }
    }

    private func settingsTabButton(_ tab: TabItem) -> some View {
        let isSelected = settingsTab == tab.index
        return Button {
            settingsTab = tab.index
        } label: {
            Label(tab.label, systemImage: tab.icon)
                .font(.callout.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
    }
}

struct SocietiesAdminView: View {
    @Binding var editingEntry: DirectoryEntry?
    @Binding var creatingNew: Bool
    @EnvironmentObject var directory: PartyDirectory
    @State private var query = ""
    @State private var selectedID: UUID?
    @State private var editingLogoEntry: DirectoryEntry?

    private var societies: [DirectoryEntry] {
        directory.entries.filter { $0.kinds.contains(.societe) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var filtered: [DirectoryEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return societies }
        return societies.filter {
            $0.displayName.lowercased().contains(q)
                || ($0.party.siren ?? "").lowercased().contains(q)
                || ($0.party.siret ?? "").lowercased().contains(q)
                || ($0.party.vatNumber ?? "").lowercased().contains(q)
                || $0.party.city.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    creatingNew = true
                } label: { Label("Nouvelle société", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
                Spacer()
                Text("\(societies.count) société(s) — \(societies.filter { !$0.isArchived }.count) active(s)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Les sociétés sont les entités émettrices de l'application. Elles définissent le périmètre des utilisateurs et l'émetteur des factures. Elles ne sont pas affichées dans l'onglet Annuaire.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Rechercher une société", text: $query)
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

            if filtered.isEmpty {
                Text("Aucune société. Cliquez sur « Nouvelle société ».")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            } else {
                Table(filtered, selection: Binding(
                    get: { selectedID },
                    set: { selectedID = $0 }
                )) {
                    TableColumn("Principale") { e in
                        Button {
                            if e.isPrincipale {
                                directory.clearPrincipale()
                            } else {
                                directory.setPrincipale(e.id)
                            }
                        } label: {
                            Image(systemName: e.isPrincipale ? "star.fill" : "star")
                                .foregroundStyle(e.isPrincipale ? .yellow : .secondary)
                        }
                        .buttonStyle(.borderless)
                        .help(e.isPrincipale
                            ? "Société principale — sert de repli pour les réglages par société non personnalisés. Cliquer pour retirer."
                            : "Définir comme société principale")
                    }
                    .width(min: 60, ideal: 70)
                    TableColumn("Nom") { e in
                        HStack(spacing: 6) {
                            Text(e.displayName)
                            if e.isArchived {
                                Text("Archive")
                                    .font(.caption2)
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(Color.orange.opacity(0.2), in: Capsule())
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    TableColumn("SIREN") { e in Text((e.party.siren ?? "").isEmpty ? "—" : e.party.siren!) }
                    TableColumn("Ville") { e in Text(e.party.city.isEmpty ? "—" : e.party.city) }
                    TableColumn("IBAN") { e in Text((e.party.iban ?? "").isEmpty ? "—" : e.party.iban!) }
                        .width(min: 120, ideal: 160)
                    TableColumn("Logo") { e in
                        Group {
                            if let data = e.logoData, let img = NSImage(data: data) {
                                Image(nsImage: img)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 36, height: 24)
                                    .background(RoundedRectangle(cornerRadius: 4).stroke(.secondary, lineWidth: 0.3))
                            } else {
                                Text("-").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .width(min: 48, ideal: 60)
                }
                .frame(minHeight: 180)
                if let id = selectedID, let entry = societies.first(where: { $0.id == id }) {
                    HStack {
                        Button {
                            editingEntry = entry
                        } label: { Label("Modifier", systemImage: "pencil") }
                            .buttonStyle(.bordered)
                        Button {
                            editingLogoEntry = entry
                        } label: { Label(entry.logoData == nil ? "Ajouter logo" : "Modifier logo", systemImage: "photo") }
                            .buttonStyle(.bordered)
                        if entry.logoData != nil {
                            Button(role: .destructive) {
                                var e = entry
                                e.logoData = nil
                                directory.upsert(e)
                            } label: { Label("Retirer logo", systemImage: "trash") }
                                .buttonStyle(.bordered)
                        }
                        Button(role: .destructive) {
                            directory.delete(entry)
                            selectedID = nil
                        } label: { Label("Supprimer", systemImage: "trash.fill") }
                            .buttonStyle(.bordered)
                        Spacer()
                        Text("Profil Factur-X : ").font(.caption)
                        Picker("Profil Factur-X", selection: Binding(
                            get: { entry.profile },
                            set: { newProfile in
                                var e = entry
                                e.profile = newProfile
                                directory.upsert(e)
                            }
                        )) {
                            ForEach(FacturXProfile.selectableCases(current: entry.profile), id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 140)
                        .help("Profil Factur-X par défaut des factures émises par cette société (hérité à la création). Seuls EN 16931 et EXTENDED sont proposés : le XML produit par l'application n'est pas conforme aux profils MINIMUM, BASIC WL et BASIC.")
                        if !entry.profile.isIssuable {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .help("Profil \(entry.profile.rawValue) plus proposé : les nouvelles factures de cette société sont créées en EN 16931. Choisissez EN 16931 ou EXTENDED.")
                        }
                    }.padding(.top, 4)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $editingLogoEntry) { entry in
            PartyLogoEditor(entry: entry, isPresented: Binding(
                get: { editingLogoEntry != nil },
                set: { if !$0 { editingLogoEntry = nil } }
            ))
        }
    }
}

struct EmailTemplatesAdminView: View {
    @EnvironmentObject var emailTemplateStore: EmailTemplateStore
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var directory: PartyDirectory
    /// String et non EmailTemplateKind : Table exige que `selection` corresponde au
    /// type de `id` (String, via EmailTemplateKind.rawValue), pas au type de la ligne.
    @State private var selectedKind: String?
    @State private var editingKind: EmailTemplateKind?
    /// Société dont on édite/consulte les surcharges — `nil` = société principale (ou le
    /// réglage global si aucune n'est désignée). Même principe que `ValueTablesView`.
    @State private var societyID: UUID?

    /// Pré-sélectionne le picker société — voir `ValueTablesView.init(initialSocietyID:)`,
    /// même principe, utilisé par l'écran "Configurer une société" (F.3).
    init(initialSocietyID: UUID? = nil) {
        _societyID = State(initialValue: initialSocietyID)
    }

    private var noSelectionLabel: String {
        guard let principaleID = directory.principaleSocieteID,
              let principale = directory.entries.first(where: { $0.id == principaleID }) else {
            return "Toutes (réglage par défaut)"
        }
        return "Société principale : \(principale.displayName)"
    }

    private func overrideState(for kind: EmailTemplateKind) -> SocietyOverrideState {
        guard let cid = societyID else { return .none }
        if emailTemplateStore.templatesBySociety[cid]?.contains(where: { $0.kind == kind }) == true { return .customized }
        if let principaleID = directory.principaleSocieteID, principaleID != cid,
           emailTemplateStore.templatesBySociety[principaleID]?.contains(where: { $0.kind == kind }) == true {
            return .inheritedFromPrincipale
        }
        return .none
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Emails envoyés automatiquement au client ou au fournisseur pour accompagner un document (devis, commande, facture) — utilise le même serveur SMTP que les alertes ci-dessus.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle(isOn: Binding(
                get: { emailTemplateStore.globalEnabled },
                set: { emailTemplateStore.globalEnabled = $0; emailTemplateStore.save() }
            )) {
                Text("Activer l'envoi de ces emails").font(.body.weight(.semibold))
            }
            .toggleStyle(.switch)
            .help("Désactivé, tous les boutons d'envoi disparaissent de l'application, quel que soit le réglage de chaque email ci-dessous — réglage global, pas par société.")

            if !emailTemplateStore.globalEnabled {
                Label("Tous les boutons d'envoi sont masqués tant que c'est désactivé.", systemImage: "eye.slash")
                    .font(.caption).foregroundStyle(.orange)
            } else {
                if !auth.visibleSocieties(for: auth.currentUser).isEmpty {
                    HStack(spacing: 6) {
                        Text("Société").font(.caption).foregroundStyle(.secondary)
                        Picker("Société", selection: $societyID) {
                            Text(noSelectionLabel).tag(UUID?.none)
                            ForEach(auth.visibleSocieties(for: auth.currentUser)) { s in
                                Text(s.displayName).tag(UUID?.some(s.id))
                            }
                        }
                        .labelsHidden()
                        .frame(width: 260)
                    }
                }
                Table(EmailTemplateKind.allCases, selection: Binding(
                    get: { selectedKind },
                    set: { selectedKind = $0 }
                )) {
                    TableColumn("Email") { kind in
                        Label(kind.label, systemImage: kind.systemImage)
                    }
                    TableColumn("Activé") { kind in
                        Toggle("", isOn: Binding(
                            get: { emailTemplateStore.template(for: kind, companyID: societyID).enabled },
                            set: { newValue in
                                var t = emailTemplateStore.template(for: kind, companyID: societyID)
                                t.enabled = newValue
                                if let cid = societyID {
                                    emailTemplateStore.setOverride(t, companyID: cid)
                                } else {
                                    emailTemplateStore.upsert(t)
                                }
                            }
                        ))
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                    }
                    .width(60)
                    TableColumn("Sujet") { kind in
                        Text(kind.hasEditableContent ? emailTemplateStore.template(for: kind, companyID: societyID).subject : "3 modèles selon le niveau d'urgence")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    TableColumn("") { kind in
                        SocietyOverrideBadge(state: overrideState(for: kind)) {
                            if let cid = societyID {
                                emailTemplateStore.removeOverride(kind: kind, companyID: cid)
                            }
                        }
                    }
                    .width(min: 90, ideal: 140)
                }
                .frame(minHeight: 160)

                if let kind = selectedKind.flatMap(EmailTemplateKind.init(rawValue:)) {
                    HStack {
                        if kind.hasEditableContent {
                            Button {
                                editingKind = kind
                            } label: { Label("Modifier", systemImage: "pencil") }
                                .buttonStyle(.bordered)
                        } else {
                            Text("La relance utilise 3 modèles distincts selon le niveau d'urgence (rappel amical, mise en demeure, majoration légale) — seule l'activation se règle ici, le contenu n'est pas modifiable.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.top, 4)
                }
            }
        }
        .sheet(item: $editingKind) { kind in
            EmailTemplateEditorSheet(kind: kind, societyID: societyID)
        }
    }
}

struct EmailTemplateEditorSheet: View {
    let kind: EmailTemplateKind
    /// `nil` = édite le réglage global (ou celui de la société principale à l'affichage,
    /// mais l'écriture cible toujours le global quand `nil` — voir `EmailTemplatesAdminView`).
    var societyID: UUID?
    @EnvironmentObject var emailTemplateStore: EmailTemplateStore
    @Environment(\.dismiss) private var dismiss
    @State private var subject = ""
    @State private var emailBody = ""

    private enum Field: Hashable { case subject, body }
    @FocusState private var focusedField: Field?

    private static let availableFields: [(tag: String, label: String)] = [
        ("numero", "Numéro"),
        ("client", "Client"),
        ("societe", "Société"),
        ("montant", "Montant"),
        ("date", "Date")
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(kind.label, systemImage: kind.systemImage).font(.title3.bold())
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Sujet").font(.caption.bold())
                    TextField("Sujet", text: $subject)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .subject)
                    Text("Corps").font(.caption.bold())
                    TextEditor(text: $emailBody)
                        .frame(height: 220)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
                        .focused($focusedField, equals: .body)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Insérer un champ (dans le sujet ou le corps, selon celui sélectionné) :")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            ForEach(Self.availableFields, id: \.tag) { field in
                                Button {
                                    insert(tag: field.tag)
                                } label: {
                                    Text(field.label).font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }
                .padding()
            }
            Divider()
            HStack {
                Spacer()
                Button("Enregistrer") {
                    var t = emailTemplateStore.template(for: kind, companyID: societyID)
                    t.subject = subject
                    t.body = emailBody
                    if let cid = societyID {
                        emailTemplateStore.setOverride(t, companyID: cid)
                    } else {
                        emailTemplateStore.upsert(t)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 560, height: 520)
        .onAppear {
            let t = emailTemplateStore.template(for: kind, companyID: societyID)
            subject = t.subject
            emailBody = t.body
        }
    }

    private func insert(tag: String) {
        let placeholder = "{{\(tag)}}"
        switch focusedField {
        case .subject: subject += placeholder
        case .body, .none: emailBody += placeholder
        }
    }
}

struct ApplicationSettingsView: View {
    @EnvironmentObject var emailTemplateStore: EmailTemplateStore
    @EnvironmentObject var twoFactorSettings: TwoFactorSettings
    @EnvironmentObject var moduleStore: ModuleStore
    @EnvironmentObject var appEnv: AppEnvironment
    @EnvironmentObject var store: InvoiceStore
    @EnvironmentObject var orderStore: OrderStore
    @EnvironmentObject var quoteStore: QuoteStore
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var directory: PartyDirectory
    @State private var twoFactorExpanded = false
    @State private var envExpanded = true
    @State private var modulesExpanded = false
    @State private var emailTemplatesExpanded = false
    @State private var societiesExpanded = false
    @State private var numberingExpanded = false
    @State private var numberingCompanyID: UUID?
    @State private var orderNumberingExpanded = false
    @State private var orderNumberingCompanyID: UUID?
    @State private var quoteNumberingExpanded = false
    @State private var quoteNumberingCompanyID: UUID?
    @State private var editingSociety: DirectoryEntry?
    @State private var creatingSociety = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Toutes les catégories ci-dessous, en revue guidée pas à pas :", systemImage: "checklist")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        NotificationCenter.default.post(name: .fullSettingsWizardRequested, object: nil)
                    } label: { Label("Relancer l'assistant complet", systemImage: "checklist") }
                        .buttonStyle(.bordered)
                }
                DisclosureGroup(isExpanded: $envExpanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: appEnv.isTest ? "flask" : "checkmark.seal.fill")
                                .foregroundStyle(appEnv.isTest ? .orange : .green)
                            Text("Environnement actif : \(appEnv.mode.label)")
                                .font(.headline)
                            Spacer()
                        }
                        Text("Bascule entre données de test et de production. Chaque environnement a ses propres factures, commandes, tiers, utilisateurs, journal d'audit et identifiants SUPER PDP.")
                            .font(.caption).foregroundStyle(.secondary)
                        Picker("Environnement", selection: Binding(
                            get: { appEnv.mode },
                            set: { newMode in appEnv.setMode(newMode) }
                        )) {
                            ForEach(AppEnvironmentMode.allCases, id: \.self) { m in
                                Text(m.label).tag(m)
                            }
                        }
                        .pickerStyle(.segmented)
                        if appEnv.isTest {
                            Label("Mode bac à sable : les données et identifiants sont isolés de la production.", systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }.padding(8)
                } label: {
                    Label("Environnement", systemImage: appEnv.isTest ? "flask" : "checkmark.seal.fill")
                        .font(.headline)
                }

                DisclosureGroup(isExpanded: $modulesExpanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Désactive un module optionnel pour toute l'application — l'onglet correspondant disparaît, et les fonctionnalités qui en dépendent ailleurs (ex. créer une facture depuis une commande) se masquent automatiquement. Annuaire et Factures restent toujours actifs.")
                            .font(.caption).foregroundStyle(.secondary)
                        Toggle("Devis", isOn: $moduleStore.settings.quotesEnabled)
                            .toggleStyle(.switch)
                            .onChange(of: moduleStore.settings.quotesEnabled) { _ in moduleStore.save() }
                        Toggle("Ventes (commandes)", isOn: $moduleStore.settings.ordersEnabled)
                            .toggleStyle(.switch)
                            .onChange(of: moduleStore.settings.ordersEnabled) { _ in moduleStore.save() }
                        Toggle("Achats", isOn: $moduleStore.settings.purchasesEnabled)
                            .toggleStyle(.switch)
                            .onChange(of: moduleStore.settings.purchasesEnabled) { _ in moduleStore.save() }
                    }.padding(8)
                } label: {
                    Label("Modules", systemImage: "square.grid.2x2")
                        .font(.headline)
                }

                DisclosureGroup(isExpanded: $societiesExpanded) {
                    SocietiesAdminView(
                        editingEntry: $editingSociety,
                        creatingNew: $creatingSociety
                    )
                } label: {
                    Label("Sociétés du périmètre", systemImage: "building.2.fill")
                        .font(.headline)
                }
                DisclosureGroup(isExpanded: $emailTemplatesExpanded) {
                    EmailTemplatesAdminView()
                        .padding(8)
                } label: {
                    Label("Emails automatiques (devis, commande, facture)", systemImage: "paperplane.fill")
                        .font(.headline)
                }

                DisclosureGroup(isExpanded: $twoFactorExpanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Active la possibilité, pour chaque utilisateur, d'activer la double authentification (application TOTP — Google Authenticator, Authy…) sur son propre profil (onglet Profil). Ce réglage est global à l'application ; désactivé, aucun utilisateur ne peut activer ni utiliser la 2FA, même s'il l'avait configurée auparavant.")
                            .font(.caption).foregroundStyle(.secondary)
                        Toggle("Autoriser la double authentification (2FA)", isOn: Binding(
                            get: { twoFactorSettings.enabledSolutionWide },
                            set: { twoFactorSettings.enabledSolutionWide = $0; twoFactorSettings.save() }
                        ))
                        .toggleStyle(.switch)
                    }.padding(8)
                } label: {
                    Label("Sécurité — Double authentification", systemImage: "lock.shield")
                        .font(.headline)
                }


                DisclosureGroup(isExpanded: $numberingExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Personnalisez le format des numéros de facture. Le chrono s'incrémente automatiquement à chaque création et démarre au numéro de début défini. Le compteur est toujours indépendant par société émettrice ; le format (préfixe, année, séparateur) peut l'être aussi si une société a besoin d'une numérotation différente — sinon toutes les sociétés partagent le format par défaut.")
                            .font(.caption).foregroundStyle(.secondary)
                        let societies = auth.visibleSocieties(for: auth.currentUser)
                        if !societies.isEmpty {
                            Picker("Société", selection: $numberingCompanyID) {
                                Text(noSelectionNumberingLabel).tag(UUID?.none)
                                ForEach(societies) { c in
                                    Text(c.displayName).tag(UUID?.some(c.id))
                                }
                            }
                            if let cid = numberingCompanyID {
                                if store.numberFormatOverrides[cid] == nil {
                                    HStack(spacing: 6) {
                                        Text(directory.principaleSocieteID != nil && cid != directory.principaleSocieteID ? "Hérite actuellement de la société principale." : "Utilise actuellement le format par défaut.").font(.caption2).foregroundStyle(.secondary)
                                        Button("Personnaliser pour cette société") {
                                            store.numberFormatOverrides[cid] = store.numberingFormat(for: nil)
                                            store.save()
                                        }.buttonStyle(.link).font(.caption2)
                                    }
                                } else {
                                    Button("Revenir au format par défaut", role: .destructive) {
                                        store.numberFormatOverrides.removeValue(forKey: cid)
                                        store.save()
                                    }.buttonStyle(.link).font(.caption2)
                                }
                            }
                        }
                        HStack {
                            Text("Préfixe texte").font(.caption)
                            TextField("ex. FAC", text: activeNumberingFormatBinding.prefix)
                                .frame(width: 140)
                        }
                        Toggle("Inclure l'année", isOn: activeNumberingFormatBinding.includeYear)
                            .toggleStyle(.switch)
                        HStack {
                            Text("Numéro de début").font(.caption)
                            Stepper(value: activeNumberingFormatBinding.start, in: 1...999999) {
                                Text("\(activeNumberingFormatBinding.wrappedValue.start)")
                            }
                        }
                        Toggle("Séparer par un \"-\"", isOn: activeNumberingFormatBinding.useSeparator)
                            .toggleStyle(.switch)
                        Divider()
                        HStack {
                            Text("Aperçu : ").font(.caption).foregroundStyle(.secondary)
                            Text(store.previewNextNumber(companyID: numberingCompanyID ?? previewCompanyID())).monospaced().font(.caption.bold())
                            Spacer()
                        }
                    }.padding(8)
                } label: {
                    Label("Numérotation des factures", systemImage: "number")
                        .font(.headline)
                }

                DisclosureGroup(isExpanded: $orderNumberingExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Même principe que pour les factures : le compteur est toujours indépendant par société émettrice, le format (préfixe, année, séparateur) peut l'être aussi si besoin.")
                            .font(.caption).foregroundStyle(.secondary)
                        let societies = auth.visibleSocieties(for: auth.currentUser)
                        if !societies.isEmpty {
                            Picker("Société", selection: $orderNumberingCompanyID) {
                                Text(noSelectionNumberingLabel).tag(UUID?.none)
                                ForEach(societies) { c in
                                    Text(c.displayName).tag(UUID?.some(c.id))
                                }
                            }
                            if let cid = orderNumberingCompanyID {
                                if orderStore.numberFormatOverrides[cid] == nil {
                                    HStack(spacing: 6) {
                                        Text(directory.principaleSocieteID != nil && cid != directory.principaleSocieteID ? "Hérite actuellement de la société principale." : "Utilise actuellement le format par défaut.").font(.caption2).foregroundStyle(.secondary)
                                        Button("Personnaliser pour cette société") {
                                            orderStore.numberFormatOverrides[cid] = orderStore.numberingFormat(for: nil)
                                            orderStore.save()
                                        }.buttonStyle(.link).font(.caption2)
                                    }
                                } else {
                                    Button("Revenir au format par défaut", role: .destructive) {
                                        orderStore.numberFormatOverrides.removeValue(forKey: cid)
                                        orderStore.save()
                                    }.buttonStyle(.link).font(.caption2)
                                }
                            }
                        }
                        HStack {
                            Text("Préfixe texte").font(.caption)
                            TextField("ex. CD", text: activeOrderNumberingFormatBinding.prefix)
                                .frame(width: 140)
                        }
                        Toggle("Inclure l'année", isOn: activeOrderNumberingFormatBinding.includeYear)
                            .toggleStyle(.switch)
                        HStack {
                            Text("Numéro de début").font(.caption)
                            Stepper(value: activeOrderNumberingFormatBinding.start, in: 1...999999) {
                                Text("\(activeOrderNumberingFormatBinding.wrappedValue.start)")
                            }
                        }
                        Toggle("Séparer par un \"-\"", isOn: activeOrderNumberingFormatBinding.useSeparator)
                            .toggleStyle(.switch)
                        Divider()
                        HStack {
                            Text("Aperçu : ").font(.caption).foregroundStyle(.secondary)
                            Text(orderStore.previewNextNumber(companyID: orderNumberingCompanyID ?? previewCompanyID())).monospaced().font(.caption.bold())
                            Spacer()
                        }
                    }.padding(8)
                } label: {
                    Label("Numérotation des commandes", systemImage: "number")
                        .font(.headline)
                }

                DisclosureGroup(isExpanded: $quoteNumberingExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Même principe que pour les factures : le compteur est toujours indépendant par société émettrice, le format (préfixe, année, séparateur) peut l'être aussi si besoin.")
                            .font(.caption).foregroundStyle(.secondary)
                        let societies = auth.visibleSocieties(for: auth.currentUser)
                        if !societies.isEmpty {
                            Picker("Société", selection: $quoteNumberingCompanyID) {
                                Text(noSelectionNumberingLabel).tag(UUID?.none)
                                ForEach(societies) { c in
                                    Text(c.displayName).tag(UUID?.some(c.id))
                                }
                            }
                            if let cid = quoteNumberingCompanyID {
                                if quoteStore.numberFormatOverrides[cid] == nil {
                                    HStack(spacing: 6) {
                                        Text(directory.principaleSocieteID != nil && cid != directory.principaleSocieteID ? "Hérite actuellement de la société principale." : "Utilise actuellement le format par défaut.").font(.caption2).foregroundStyle(.secondary)
                                        Button("Personnaliser pour cette société") {
                                            quoteStore.numberFormatOverrides[cid] = quoteStore.numberingFormat(for: nil)
                                            quoteStore.save()
                                        }.buttonStyle(.link).font(.caption2)
                                    }
                                } else {
                                    Button("Revenir au format par défaut", role: .destructive) {
                                        quoteStore.numberFormatOverrides.removeValue(forKey: cid)
                                        quoteStore.save()
                                    }.buttonStyle(.link).font(.caption2)
                                }
                            }
                        }
                        HStack {
                            Text("Préfixe texte").font(.caption)
                            TextField("ex. DEV", text: activeQuoteNumberingFormatBinding.prefix)
                                .frame(width: 140)
                        }
                        Toggle("Inclure l'année", isOn: activeQuoteNumberingFormatBinding.includeYear)
                            .toggleStyle(.switch)
                        HStack {
                            Text("Numéro de début").font(.caption)
                            Stepper(value: activeQuoteNumberingFormatBinding.start, in: 1...999999) {
                                Text("\(activeQuoteNumberingFormatBinding.wrappedValue.start)")
                            }
                        }
                        Toggle("Séparer par un \"-\"", isOn: activeQuoteNumberingFormatBinding.useSeparator)
                            .toggleStyle(.switch)
                        Divider()
                        HStack {
                            Text("Aperçu : ").font(.caption).foregroundStyle(.secondary)
                            Text(quoteStore.previewNextNumber(companyID: quoteNumberingCompanyID ?? previewCompanyID())).monospaced().font(.caption.bold())
                            Spacer()
                        }
                    }.padding(8)
                } label: {
                    Label("Numérotation des devis", systemImage: "number")
                        .font(.headline)
                }

                Divider()
                HStack {
                    Text("Facture_elec v\(AppVersion.current) — © 2026 \(AppVersion.copyrightHolder) — \(AppVersion.licenseName)")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Link(destination: AppVersion.repositoryURL) {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                            Text("GitHub")
                        }
                    }.font(.caption.weight(.semibold))
                }

                Spacer()
            }.padding()
        }
        .sheet(item: $editingSociety) { entry in
            DirectoryEditorView(entry: entry, onSave: { updated in
                directory.upsert(updated)
                editingSociety = nil
            }, onDelete: { toDelete in
                directory.delete(toDelete)
                editingSociety = nil
            })
        }
        .sheet(isPresented: $creatingSociety) {
            DirectoryEditorView(initialKind: .societe) { newEntry in
                directory.upsert(newEntry)
                creatingSociety = false
            }
        }
    }

    private func previewCompanyID() -> UUID? {
        let visible = auth.visibleSocieties(for: auth.currentUser)
        if visible.count == 1 { return visible.first?.id }
        return nil
    }

    /// Libellé de l'option "pas de société sélectionnée" des 3 pickers de numérotation —
    /// voir `ValueTablesView.noSelectionLabel`, même principe.
    private var noSelectionNumberingLabel: String {
        guard let principaleID = directory.principaleSocieteID,
              let principale = directory.entries.first(where: { $0.id == principaleID }) else {
            return "Toutes (format par défaut)"
        }
        return "Société principale : \(principale.displayName)"
    }


    /// Le format en cours d'édition : celui de la société sélectionnée (créé à la volée à
    /// partir du défaut si elle n'a pas encore de réglage propre), ou le format par défaut
    /// si "Toutes" est sélectionné. Écrire dedans met à jour la bonne cible chez `store`.
    private var activeNumberingFormatBinding: Binding<InvoiceNumberingFormat> {
        Binding(
            get: {
                guard let cid = numberingCompanyID else { return store.numberingFormat(for: nil) }
                return store.numberFormatOverrides[cid] ?? store.numberingFormat(for: nil)
            },
            set: { newValue in
                if let cid = numberingCompanyID {
                    store.numberFormatOverrides[cid] = newValue
                } else {
                    store.numberPrefix = newValue.prefix
                    store.numberIncludeYear = newValue.includeYear
                    store.numberStart = newValue.start
                    store.numberUseSeparator = newValue.useSeparator
                }
                store.save()
            }
        )
    }

    private var activeOrderNumberingFormatBinding: Binding<InvoiceNumberingFormat> {
        Binding(
            get: {
                guard let cid = orderNumberingCompanyID else { return orderStore.numberingFormat(for: nil) }
                return orderStore.numberFormatOverrides[cid] ?? orderStore.numberingFormat(for: nil)
            },
            set: { newValue in
                if let cid = orderNumberingCompanyID {
                    orderStore.numberFormatOverrides[cid] = newValue
                } else {
                    orderStore.numberPrefix = newValue.prefix
                    orderStore.numberIncludeYear = newValue.includeYear
                    orderStore.numberStart = newValue.start
                    orderStore.numberUseSeparator = newValue.useSeparator
                }
                orderStore.save()
            }
        )
    }

    private var activeQuoteNumberingFormatBinding: Binding<InvoiceNumberingFormat> {
        Binding(
            get: {
                guard let cid = quoteNumberingCompanyID else { return quoteStore.numberingFormat(for: nil) }
                return quoteStore.numberFormatOverrides[cid] ?? quoteStore.numberingFormat(for: nil)
            },
            set: { newValue in
                if let cid = quoteNumberingCompanyID {
                    quoteStore.numberFormatOverrides[cid] = newValue
                } else {
                    quoteStore.numberPrefix = newValue.prefix
                    quoteStore.numberIncludeYear = newValue.includeYear
                    quoteStore.numberStart = newValue.start
                    quoteStore.numberUseSeparator = newValue.useSeparator
                }
                quoteStore.save()
            }
        )
    }
}

struct ConfigureSocieteView: View {
    @EnvironmentObject var directory: PartyDirectory
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var store: InvoiceStore
    @EnvironmentObject var orderStore: OrderStore
    @EnvironmentObject var quoteStore: QuoteStore
    @State private var selectedSocieteID: UUID?
    @State private var tablesExpanded = true
    @State private var numberingExpanded = false
    @State private var emailsExpanded = false

    private var societies: [DirectoryEntry] {
        auth.visibleSocieties(for: auth.currentUser)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Configurer une société").font(.title2.bold())
            Text("Choisissez une société pour revoir en une seule fois tous ses réglages personnalisables, plutôt que de les retrouver écran par écran.")
                .font(.caption).foregroundStyle(.secondary)

            if societies.isEmpty {
                Text("Aucune société du périmètre. Créez-en une dans Réglages > Application > Sociétés du périmètre.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("Société", selection: $selectedSocieteID) {
                    Text("Choisir une société…").tag(UUID?.none)
                    ForEach(societies) { s in
                        HStack {
                            Text(s.displayName)
                            if s.isPrincipale { Text("— principale") }
                        }.tag(UUID?.some(s.id))
                    }
                }
                .frame(width: 340)
            }

            if let cid = selectedSocieteID {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        DisclosureGroup("Tables de valeurs (statuts, tags, conditions de paiement, couleurs…)", isExpanded: $tablesExpanded) {
                            ValueTablesView(initialSocietyID: cid)
                                .id(cid)
                                .frame(minHeight: 480)
                        }
                        DisclosureGroup("Numérotation", isExpanded: $numberingExpanded) {
                            VStack(alignment: .leading, spacing: 10) {
                                numberingSummaryRow(
                                    title: "Factures",
                                    format: store.numberingFormat(for: cid),
                                    isOverridden: store.numberFormatOverrides[cid] != nil,
                                    onCustomize: { store.numberFormatOverrides[cid] = store.numberingFormat(for: nil); store.save() },
                                    onRevert: { store.numberFormatOverrides.removeValue(forKey: cid); store.save() }
                                )
                                numberingSummaryRow(
                                    title: "Commandes",
                                    format: orderStore.numberingFormat(for: cid),
                                    isOverridden: orderStore.numberFormatOverrides[cid] != nil,
                                    onCustomize: { orderStore.numberFormatOverrides[cid] = orderStore.numberingFormat(for: nil); orderStore.save() },
                                    onRevert: { orderStore.numberFormatOverrides.removeValue(forKey: cid); orderStore.save() }
                                )
                                numberingSummaryRow(
                                    title: "Devis",
                                    format: quoteStore.numberingFormat(for: cid),
                                    isOverridden: quoteStore.numberFormatOverrides[cid] != nil,
                                    onCustomize: { quoteStore.numberFormatOverrides[cid] = quoteStore.numberingFormat(for: nil); quoteStore.save() },
                                    onRevert: { quoteStore.numberFormatOverrides.removeValue(forKey: cid); quoteStore.save() }
                                )
                                Text("Détail complet (préfixe, année, numéro de début, séparateur) dans Réglages > Application.")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            .padding(.top, 4)
                        }
                        DisclosureGroup("Emails automatiques", isExpanded: $emailsExpanded) {
                            EmailTemplatesAdminView(initialSocietyID: cid)
                                .id(cid)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Spacer()
                HStack {
                    Spacer()
                    Text("Sélectionnez une société pour commencer.").foregroundStyle(.secondary)
                    Spacer()
                }
                Spacer()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func numberingSummaryRow(title: String, format: InvoiceNumberingFormat, isOverridden: Bool, onCustomize: @escaping () -> Void, onRevert: @escaping () -> Void) -> some View {
        HStack {
            Text(title).frame(width: 90, alignment: .leading)
            Text("\(format.prefix)\(format.includeYear ? "-AAAA" : "")-0001").monospaced().font(.caption).foregroundStyle(.secondary)
            Spacer()
            if isOverridden {
                Button("Revenir au réglage hérité", role: .destructive, action: onRevert).buttonStyle(.link).font(.caption2)
            } else {
                Button("Personnaliser pour cette société", action: onCustomize).buttonStyle(.link).font(.caption2)
            }
        }
    }
}
