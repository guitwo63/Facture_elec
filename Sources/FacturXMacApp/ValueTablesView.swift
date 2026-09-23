import SwiftUI
import FacturXCore

// MARK: - Extrait de FacturXMacApp.swift (découpage par domaine)

extension DirectoryEntryKind: Identifiable {
    public var id: String { rawValue }
}

enum ValueTable: String, CaseIterable, Identifiable {
    case invoiceStatuses
    case purchaseInvoiceStatuses
    case orderStatuses
    case quoteStatuses
    case paymentTerms
    case tags
    case kindColors
    case currencies
    case units
    case countries
    case endpointSchemes
    case auditActionLabels
    case superPDPStatusCodes

    var id: String { rawValue }

    var label: String {
        switch self {
        case .invoiceStatuses: return "Statuts des factures"
        case .purchaseInvoiceStatuses: return "Statuts des factures d'achat"
        case .orderStatuses: return "Statuts des commandes"
        case .quoteStatuses: return "Statuts des devis"
        case .paymentTerms: return "Conditions de paiement"
        case .tags: return "Tags des tiers"
        case .kindColors: return "Couleurs des types de tiers"
        case .currencies: return "Devises"
        case .units: return "Unités"
        case .countries: return "Pays"
        case .endpointSchemes: return "Schémas d'identifiant"
        case .auditActionLabels: return "Libellés du journal"
        case .superPDPStatusCodes: return "Statuts SUPER PDP"
        }
    }

    var systemImage: String {
        switch self {
        case .invoiceStatuses: return "doc.text.fill"
        case .purchaseInvoiceStatuses: return "cart.badge.clock"
        case .orderStatuses: return "list.bullet.rectangle"
        case .quoteStatuses: return "doc.text.below.ecg"
        case .paymentTerms: return "banknote"
        case .tags: return "tag"
        case .kindColors: return "paintpalette"
        case .currencies: return "dollarsign.circle"
        case .units: return "ruler"
        case .countries: return "globe"
        case .endpointSchemes: return "number"
        case .auditActionLabels: return "list.bullet.clipboard"
        case .superPDPStatusCodes: return "antenna.radar"
        }
    }

    var isEditable: Bool {
        switch self {
        case .invoiceStatuses, .purchaseInvoiceStatuses, .orderStatuses, .quoteStatuses, .paymentTerms, .tags, .kindColors, .auditActionLabels, .superPDPStatusCodes: return true
        default: return false
        }
    }
}

struct ValueTablesView: View {
    @EnvironmentObject var directory: PartyDirectory
    @EnvironmentObject var statusStore: OrderStatusStore
    @EnvironmentObject var invoiceStatusStore: InvoiceStatusStore
    @EnvironmentObject var purchaseInvoiceStatusStore: PurchaseInvoiceStatusStore
    @EnvironmentObject var quoteStatusStore: QuoteStatusStore
    @EnvironmentObject var tagStore: TagStore
    @EnvironmentObject var kindColors: KindColorStore
    @EnvironmentObject var paymentTermsStore: PaymentTermsPresetStore
    @EnvironmentObject var actionLabelStore: AuditActionLabelStore
    @EnvironmentObject var superPDPStatusCodeStore: SuperPDPStatusCodeStore
    @EnvironmentObject var auth: AuthStore
    @State private var selectedTable: ValueTable = .orderStatuses
    /// Société dont on édite/consulte les surcharges — commune à toutes les tables
    /// modifiables (pas besoin de re-choisir en changeant de table). `nil` = "Toutes" : le
    /// réglage global lui-même, affiché ET enregistré tel quel. Ne jamais l'afficher via
    /// `list(for: nil)`/`override(for:companyID: nil)`, qui résolvent sur la société
    /// principale : une modification enregistrée dans le global semblait alors disparaître.
    /// Une société sélectionnée affiche sa résolution réelle (ses surcharges sur le global,
    /// sans héritage de la société principale).
    @State private var tableSocietyID: UUID?
    @State private var editingPDPStatusCode: PDPEventCodeOverride?
    @State private var creatingPDPStatusCode = false
    @State private var searchQuery = ""
    @State private var editingStatus: OrderStatusOverride?
    @State private var editingInvoiceStatus: InvoiceStatusOverride?
    @State private var editingPurchaseInvoiceStatus: PurchaseInvoiceStatusOverride?
    @State private var editingQuoteStatus: QuoteStatusOverride?
    @State private var editingTag: PartyTag?
    @State private var editingPaymentTerm: PaymentTermsPreset?
    @State private var editingKind: DirectoryEntryKind?
    @State private var newTagName = ""
    @State private var newTagHex = "555555"

    /// `initialSocietyID` pré-sélectionne le picker société — utilisé par l'écran
    /// "Configurer une société" (F.3) pour embarquer cette vue déjà filtrée sur la société
    /// choisie, sans dupliquer la logique des 9 panneaux. `nil` (par défaut) préserve le
    /// comportement de l'onglet Réglages > Tables autonome ("Toutes" au départ).
    init(initialSocietyID: UUID? = nil) {
        _tableSocietyID = State(initialValue: initialSocietyID)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filtrer les tables et les valeurs", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(10)
            if selectedTable.isEditable, !auth.visibleSocieties(for: auth.currentUser).isEmpty {
                HStack(spacing: 6) {
                    Text("Société").font(.caption).foregroundStyle(.secondary)
                    Picker("Société", selection: $tableSocietyID) {
                        Text("Toutes (réglage par défaut)").tag(UUID?.none)
                        ForEach(auth.visibleSocieties(for: auth.currentUser)) { s in
                            Text(s.displayName).tag(UUID?.some(s.id))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 260)
                    InfoBadge(text: "Personnalisez une valeur pour cette société uniquement — les autres sociétés gardent le réglage par défaut. « Toutes » édite ce réglage par défaut lui-même."
                        + (directory.principaleSocieteID == nil ? "" : " Ce qui n'est rattaché à aucune société (tiers sans société, anciens documents) suit la société principale."))
                    Spacer()
                }
                .padding(.horizontal, 10).padding(.bottom, 8)
            }
            Divider()
            HStack(alignment: .top, spacing: 0) {
                tablesList
                    .frame(width: 220)
                Divider()
                valuesPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(item: $editingStatus) { override in
            OrderStatusEditorSheet(override: override) { updated in
                if let cid = tableSocietyID {
                    statusStore.setOverride(updated, companyID: cid)
                } else if let i = statusStore.overrides.firstIndex(where: { $0.id == override.id }) {
                    statusStore.overrides[i] = updated
                    statusStore.save()
                }
            }
        }
        .sheet(item: $editingInvoiceStatus) { override in
            InvoiceStatusEditorSheet(override: override) { updated in
                if let cid = tableSocietyID {
                    invoiceStatusStore.setOverride(updated, companyID: cid)
                } else if let i = invoiceStatusStore.overrides.firstIndex(where: { $0.id == override.id }) {
                    invoiceStatusStore.overrides[i] = updated
                    invoiceStatusStore.save()
                }
            }
        }
        .sheet(item: $editingPurchaseInvoiceStatus) { override in
            PurchaseInvoiceStatusEditorSheet(override: override) { updated in
                if let cid = tableSocietyID {
                    purchaseInvoiceStatusStore.setOverride(updated, companyID: cid)
                } else if let i = purchaseInvoiceStatusStore.overrides.firstIndex(where: { $0.id == override.id }) {
                    purchaseInvoiceStatusStore.overrides[i] = updated
                    purchaseInvoiceStatusStore.save()
                }
            }
        }
        .sheet(item: $editingQuoteStatus) { override in
            QuoteStatusEditorSheet(override: override) { updated in
                if let cid = tableSocietyID {
                    quoteStatusStore.setOverride(updated, companyID: cid)
                } else if let i = quoteStatusStore.overrides.firstIndex(where: { $0.id == override.id }) {
                    quoteStatusStore.overrides[i] = updated
                    quoteStatusStore.save()
                }
            }
        }
        .sheet(item: $editingTag) { tag in
            TagEditorSheet(tag: tag) { updated in
                if let cid = tableSocietyID {
                    tagStore.setOverride(updated, companyID: cid)
                } else {
                    tagStore.upsert(updated)
                }
            }
        }
        .sheet(item: $editingPaymentTerm) { preset in
            PaymentTermsPresetEditorSheet(preset: preset) { updated in
                if let cid = tableSocietyID {
                    paymentTermsStore.setOverride(updated, companyID: cid)
                } else {
                    paymentTermsStore.upsert(updated)
                }
            }
        }
        .sheet(item: $editingKind) { kind in
            KindColorEditorSheet(kind: kind, hex: displayedHexColor(for: kind)) { newHex in
                if let cid = tableSocietyID {
                    kindColors.setOverride(hexColor: newHex, for: kind, companyID: cid)
                } else {
                    kindColors.colors[kind] = newHex
                    kindColors.save()
                }
            }
        }
        .sheet(item: $editingPDPStatusCode) { override in
            PDPStatusCodeEditorSheet(existing: override) { updated in
                if let cid = tableSocietyID {
                    superPDPStatusCodeStore.setOverride(updated, companyID: cid)
                } else {
                    superPDPStatusCodeStore.upsert(updated)
                }
            }
        }
        .sheet(isPresented: $creatingPDPStatusCode) {
            PDPStatusCodeEditorSheet(existing: nil) { created in
                superPDPStatusCodeStore.upsert(created)
            }
        }
    }

    private var filteredTables: [ValueTable] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return ValueTable.allCases }
        return ValueTable.allCases.filter { $0.label.lowercased().contains(q) }
    }

    private var tablesList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(filteredTables) { table in
                    Button {
                        selectedTable = table
                    } label: {
                        HStack {
                            Image(systemName: table.systemImage)
                                .foregroundStyle(selectedTable == table ? Color.accentColor : .secondary)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(table.label).font(.body.weight(selectedTable == table ? .semibold : .regular))
                                Text(table.isEditable ? "modifiable" : "lecture seule")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                            Spacer()
                            if selectedTable == table {
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(selectedTable == table ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private var valuesPanel: some View {
        switch selectedTable {
        case .invoiceStatuses: invoiceStatusesPanel
        case .purchaseInvoiceStatuses: purchaseInvoiceStatusesPanel
        case .orderStatuses: orderStatusesPanel
        case .quoteStatuses: quoteStatusesPanel
        case .paymentTerms: paymentTermsPanel
        case .tags: tagsPanel
        case .kindColors: kindColorsPanel
        case .currencies: refPanel(NormRefs.currencies)
        case .units: refPanel(NormRefs.units)
        case .countries: refPanel(NormRefs.countries)
        case .endpointSchemes: refPanel(NormRefs.endpointSchemes)
        case .auditActionLabels: auditActionLabelsPanel
        case .superPDPStatusCodes: superPDPStatusCodesPanel
        }
    }

    private var filteredAuditActionLabels: [AuditActionLabel] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let resolved = actionLabelStore.overrides
            .map { global in
                tableSocietyID.map { AuditActionLabel(id: global.id, label: actionLabelStore.label(for: global.id, companyID: $0)) } ?? global
            }
            .sorted { $0.label < $1.label }
        guard !q.isEmpty else { return resolved }
        return resolved.filter { $0.label.lowercased().contains(q) || $0.id.lowercased().contains(q) }
    }

    private func isAuditActionLabelCustomized(_ id: String) -> Bool {
        tableSocietyID.flatMap { actionLabelStore.overridesBySociety[$0]?.contains { $0.id == id } } ?? false
    }

    private var auditActionLabelsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Libellés du journal").font(.title3.bold())
                Spacer()
                if tableSocietyID == nil {
                    Button {
                        actionLabelStore.resetToDefaults()
                    } label: { Label("Réinitialiser", systemImage: "arrow.counterclockwise") }
                        .buttonStyle(.bordered)
                }
            }
            .padding(12)
            Divider()
            Text("Libellé affiché dans le journal (Réglages > Journal, et le journal de chaque facture/commande/devis) pour chaque code technique d'événement.")
                .font(.caption).foregroundStyle(.secondary).padding(12)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredAuditActionLabels) { item in
                        HStack(spacing: 10) {
                            Text(item.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                                .frame(width: 220, alignment: .leading)
                            TextField("Libellé", text: Binding(
                                get: { item.label },
                                set: { newLabel in
                                    if let cid = tableSocietyID {
                                        actionLabelStore.setOverride(AuditActionLabel(id: item.id, label: newLabel), companyID: cid)
                                    } else {
                                        actionLabelStore.upsert(AuditActionLabel(id: item.id, label: newLabel))
                                    }
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                            SocietyOverrideBadge(isCustomized: isAuditActionLabelCustomized(item.id)) {
                                if let cid = tableSocietyID {
                                    actionLabelStore.removeOverride(id: item.id, companyID: cid)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(12)
            }
        }
    }

    private var filteredPDPStatusCodes: [PDPEventCodeOverride] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let resolved = superPDPStatusCodeStore.overrides
            .map { global in tableSocietyID.flatMap { superPDPStatusCodeStore.override(for: global.id, companyID: $0) } ?? global }
            .sorted { $0.id < $1.id }
        guard !q.isEmpty else { return resolved }
        return resolved.filter { $0.label.lowercased().contains(q) || $0.id.lowercased().contains(q) }
    }

    private func isPDPStatusCodeCustomized(_ id: String) -> Bool {
        let normalized = id.lowercased()
        return tableSocietyID.flatMap { superPDPStatusCodeStore.overridesBySociety[$0]?.contains { $0.id.lowercased() == normalized } } ?? false
    }

    /// Table de paramétrage des codes d'événement SUPER PDP (fr:2XX) : libellé français et
    /// règle de mise à jour (quel statut fonctionnel le code déclenche, s'il y en a un) —
    /// voir `SuperPDPStatusCodeStore` et la passerelle `PDPStatusMapper.functionalTransition`
    /// qui la consulte. Contrairement à la table des statuts de facture, "Nouvelle valeur"
    /// a un sens ici : un code SUPER PDP pas encore connu de l'app (ex. une future version
    /// de l'API) peut être ajouté dès que sa signification est publiée, sans mise à jour
    /// de l'app.
    private var superPDPStatusCodesPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Statuts SUPER PDP").font(.title3.bold())
                Spacer()
                if tableSocietyID == nil {
                    Button {
                        creatingPDPStatusCode = true
                    } label: { Label("Nouvelle valeur", systemImage: "plus") }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(12)
            Divider()
            Text("Libellé et règle de mise à jour pour chaque code d'événement SUPER PDP (envoyé ou reçu). Une règle de mise à jour fait avancer le statut fonctionnel de la facture quand ce code est rencontré ; sans règle, le code reste visible dans le journal SUPER PDP de la facture sans effet sur son statut.")
                .font(.caption).foregroundStyle(.secondary).padding(12)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredPDPStatusCodes) { item in
                        pdpStatusCodeRow(item)
                    }
                }
                .padding(12)
            }
        }
    }

    private func pdpStatusCodeRow(_ item: PDPEventCodeOverride) -> some View {
        HStack(spacing: 10) {
            Text(item.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(item.label).font(.body)
                .frame(minWidth: 160, alignment: .leading)
            if let raw = item.functionalTransition, let status = InvoiceStatus(rawValue: raw) {
                Label(status.label, systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption2.bold())
                    .foregroundStyle(Color(hex: status.hexColor))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: status.hexColor).opacity(0.12)))
                    .help("Fait passer la facture au statut « \(status.label) »")
            } else {
                Text("informatif seulement").font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            SocietyOverrideBadge(isCustomized: isPDPStatusCodeCustomized(item.id)) {
                if let cid = tableSocietyID {
                    superPDPStatusCodeStore.removeOverride(id: item.id, companyID: cid)
                }
            }
            Button {
                editingPDPStatusCode = item
            } label: { Image(systemName: "pencil") }
                .buttonStyle(.borderless)
                .help("Modifier")
            if !item.isSystemDefined, tableSocietyID == nil {
                Button(role: .destructive) {
                    superPDPStatusCodeStore.remove(item)
                } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help("Supprimer ce code")
            }
        }
        .padding(.vertical, 4).padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.clear))
    }

    private var invoiceStatusesPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Statuts des factures").font(.title3.bold())
                Spacer()
            }
            .padding(12)
            Divider()
            // Pas de bouton "Nouvelle valeur" ici (contrairement aux autres tables) :
            // `Invoice.status` est typé sur l'enum InvoiceStatus, un statut personnalisé ne
            // pourrait donc jamais être assigné à une facture — il n'aurait fait que
            // réapparaître comme entrée orpheline (voir InvoiceStatusStore.load()).
            Text("Personnalisez le libellé des 9 statuts fonctionnels. Les lignes « réforme » (liaison PDP) sont non supprimables : seul le libellé est modifiable. La colonne « code réforme » indique l'équivalent envoyé à SUPER PDP ; les transitions affichent le cycle de vie normé.")
                .font(.caption).foregroundStyle(.secondary).padding(12)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredInvoiceStatuses) { override in
                        invoiceStatusRow(override)
                    }
                }
                .padding(12)
            }
        }
    }

    private func invoiceStatusRow(_ override: InvoiceStatusOverride) -> some View {
        let transitionLabels: [String] = override.transitionCodes.compactMap { code in
            invoiceStatusStore.overrides.first { $0.id == code }?.label
                ?? InvoiceStatus(rawValue: code)?.label
        }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: override.systemImage)
                    .frame(width: 22)
                    .foregroundStyle(Color(hex: override.hexColor))
                Text(override.label).font(.body)
                if override.isReformStatus {
                    HStack(spacing: 3) {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(override.reformCode ?? "")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.12)))
                    .help("Statut lié à la réforme (PDP) — code \(override.reformCode ?? ""). Non supprimable, libellé modifiable.")
                    if let direction = pdpDirection(for: override) {
                        Label(direction.label, systemImage: direction.systemImage)
                            .font(.caption2.bold())
                            .foregroundStyle(direction.color)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(direction.color.opacity(0.12)))
                            .help(direction.help)
                    }
                } else {
                    Text("hors réforme")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                SocietyOverrideBadge(isCustomized: tableSocietyID.flatMap { cid in invoiceStatusStore.overridesBySociety[cid]?.contains { $0.id == override.id } } ?? false) {
                    if let status = InvoiceStatus(rawValue: override.id), let cid = tableSocietyID {
                        invoiceStatusStore.removeOverride(for: status, companyID: cid)
                    }
                }
                Button {
                    editingInvoiceStatus = override
                } label: { Image(systemName: "pencil") }
                    .buttonStyle(.borderless)
                    .help("Modifier le libellé")
                if !override.isReformStatus, tableSocietyID == nil {
                    Button(role: .destructive) {
                        if let i = invoiceStatusStore.overrides.firstIndex(where: { $0.id == override.id }) {
                            invoiceStatusStore.remove(at: i)
                        }
                    } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .help("Supprimer ce statut")
                }
            }
            if !transitionLabels.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Transitions : " + transitionLabels.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 32)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.clear))
    }

    /// Sens de circulation du statut fonctionnel avec SUPER PDP : chaque code renvoyé par
    /// `InvoiceStatusStore.reformCode` est réellement envoyable (voir sa doc) — le détail
    /// fin des événements réseau reçus (fr:200-204, fr:208, fr:209, fr:211, fr:220…) vit
    /// dans le journal SUPER PDP de la facture, pas dans cette table. `sent` (fr:200) est
    /// un cas particulier : envoyé, mais implicitement par le dépôt lui-même plutôt que
    /// par un événement de statut séparé.
    private func pdpDirection(for override: InvoiceStatusOverride) -> (label: String, systemImage: String, color: Color, help: String)? {
        guard override.reformCode != nil else { return nil }
        if override.id == InvoiceStatus.sent.rawValue {
            return (
                "Envoyé (via le dépôt)", "arrow.up.circle",
                Color.orange,
                "Posé automatiquement par le dépôt Factur-X — jamais envoyé séparément comme événement de statut."
            )
        } else {
            return (
                "Envoyé à SUPER PDP", "arrow.up.circle",
                Color.orange,
                "L'app peut transmettre ce statut à SUPER PDP (bouton de transition dans la fiche facture)."
            )
        }
    }

    private var filteredInvoiceStatuses: [InvoiceStatusOverride] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let resolved = InvoiceStatus.allCases.map { status in
            tableSocietyID.map { invoiceStatusStore.override(for: status, companyID: $0) } ?? invoiceStatusStore.override(for: status)
        }
        guard !q.isEmpty else { return resolved }
        return resolved.filter { $0.label.lowercased().contains(q) || $0.id.lowercased().contains(q) || ($0.reformCode ?? "").lowercased().contains(q) }
    }

    // MARK: - Statuts des factures d'achat

    private var purchaseInvoiceStatusesPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Statuts des factures d'achat").font(.title3.bold())
                Spacer()
            }
            .padding(12)
            Divider()
            // Même raison que pour la table des statuts de facture : PurchaseInvoice.status
            // est typé sur l'enum PurchaseInvoiceStatus, un statut personnalisé ne pourrait
            // jamais être assigné à une facture d'achat.
            Text("Personnalisez le libellé des 8 statuts fonctionnels. Les lignes « réforme » (liaison PDP) sont non supprimables : seul le libellé est modifiable. La colonne « code réforme » indique l'événement envoyé à SUPER PDP pour informer le fournisseur ; les transitions affichent le workflow de validation.")
                .font(.caption).foregroundStyle(.secondary).padding(12)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredPurchaseInvoiceStatuses) { override in
                        purchaseInvoiceStatusRow(override)
                    }
                }
                .padding(12)
            }
        }
    }

    private func purchaseInvoiceStatusRow(_ override: PurchaseInvoiceStatusOverride) -> some View {
        let transitionLabels: [String] = override.transitionCodes.compactMap { code in
            purchaseInvoiceStatusStore.overrides.first { $0.id == code }?.label
                ?? PurchaseInvoiceStatus(rawValue: code)?.label
        }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: override.systemImage)
                    .frame(width: 22)
                    .foregroundStyle(Color(hex: override.hexColor))
                Text(override.label).font(.body)
                if override.isReformStatus {
                    HStack(spacing: 3) {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(override.reformCode ?? "")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.12)))
                    .help("Statut lié à la réforme (PDP) — code \(override.reformCode ?? ""). Non supprimable, libellé modifiable.")
                    Label("Envoyé à SUPER PDP", systemImage: "arrow.up.circle")
                        .font(.caption2.bold())
                        .foregroundStyle(Color.orange)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.orange.opacity(0.12)))
                        .help("L'app transmet ce statut à SUPER PDP pour informer le fournisseur (bouton de transition dans la fiche facture d'achat).")
                } else {
                    Text("hors réforme")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                SocietyOverrideBadge(isCustomized: tableSocietyID.flatMap { cid in purchaseInvoiceStatusStore.overridesBySociety[cid]?.contains { $0.id == override.id } } ?? false) {
                    if let status = PurchaseInvoiceStatus(rawValue: override.id), let cid = tableSocietyID {
                        purchaseInvoiceStatusStore.removeOverride(for: status, companyID: cid)
                    }
                }
                Button {
                    editingPurchaseInvoiceStatus = override
                } label: { Image(systemName: "pencil") }
                    .buttonStyle(.borderless)
                    .help("Modifier le libellé")
            }
            if !transitionLabels.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Transitions : " + transitionLabels.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 32)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.clear))
    }

    private var filteredPurchaseInvoiceStatuses: [PurchaseInvoiceStatusOverride] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let resolved = PurchaseInvoiceStatus.allCases.map { status in
            tableSocietyID.map { purchaseInvoiceStatusStore.override(for: status, companyID: $0) } ?? purchaseInvoiceStatusStore.override(for: status)
        }
        guard !q.isEmpty else { return resolved }
        return resolved.filter { $0.label.lowercased().contains(q) || $0.id.lowercased().contains(q) || ($0.reformCode ?? "").lowercased().contains(q) }
    }

    private var orderStatusesPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Statuts des commandes").font(.title3.bold())
                Spacer()
                if tableSocietyID == nil {
                    Button {
                        let id = "custom-\(UUID().uuidString.prefix(8))"
                        statusStore.append(OrderStatusOverride(id: id, label: "Nouveau statut", systemImage: "doc", hexColor: "6E6E73"))
                    } label: { Label("Nouvelle valeur", systemImage: "plus") }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredStatuses) { override in
                        orderStatusRow(override)
                    }
                }
                .padding(12)
            }
        }
    }

    private func orderStatusRow(_ override: OrderStatusOverride) -> some View {
        let transitionLabels: [String] = override.transitionCodes.compactMap { code in
            statusStore.overrides.first { $0.id == code }?.label
        }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: override.systemImage)
                    .frame(width: 22)
                    .foregroundStyle(Color(hex: override.hexColor))
                Text(override.label).font(.body)
                if override.isPDPStatus {
                    HStack(spacing: 3) {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(override.id)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.clear))
                    .help("Clé technique non modifiable (statut lié au cycle standard)")
                } else {
                    Text("hors cycle standard")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                SocietyOverrideBadge(isCustomized: tableSocietyID.flatMap { cid in statusStore.overridesBySociety[cid]?.contains { $0.id == override.id } } ?? false) {
                    // Manipulation directe (pas de removeOverride(for:companyID:) générique côté
                    // OrderStatusStore) : cette table mélange statuts standard (enum OrderStatus)
                    // et statuts personnalisés (id "custom-…", hors enum) — il faut fonctionner
                    // uniformément sur un id brut pour couvrir les deux.
                    if let cid = tableSocietyID {
                        statusStore.overridesBySociety[cid]?.removeAll { $0.id == override.id }
                        if statusStore.overridesBySociety[cid]?.isEmpty == true {
                            statusStore.overridesBySociety.removeValue(forKey: cid)
                        }
                        statusStore.save()
                    }
                }
                Button {
                    editingStatus = override
                } label: { Image(systemName: "pencil") }
                    .buttonStyle(.borderless)
                    .help("Modifier ce statut")
                if !override.isPDPStatus, tableSocietyID == nil {
                    Button(role: .destructive) {
                        if let i = statusStore.overrides.firstIndex(where: { $0.id == override.id }) {
                            statusStore.remove(at: i)
                        }
                    } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .help("Supprimer ce statut")
                }
            }
            if !transitionLabels.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Transitions : " + transitionLabels.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 32)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.clear))
    }

    /// Contrairement aux commandes/factures, un devis n'a pas de statuts imposés
    /// par un tiers externe : pas de bouton « nouvelle valeur » ni de suppression,
    /// seuls les 5 statuts standard existent et restent tous éditables.
    private var quoteStatusesPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Statuts des devis").font(.title3.bold())
                Spacer()
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredQuoteStatuses) { override in
                        quoteStatusRow(override)
                    }
                }
                .padding(12)
            }
        }
    }

    private func quoteStatusRow(_ override: QuoteStatusOverride) -> some View {
        let transitionLabels: [String] = override.transitionCodes.compactMap { code in
            quoteStatusStore.overrides.first { $0.id == code }?.label
        }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: override.systemImage)
                    .frame(width: 22)
                    .foregroundStyle(Color(hex: override.hexColor))
                Text(override.label).font(.body)
                Spacer()
                SocietyOverrideBadge(isCustomized: tableSocietyID.flatMap { cid in quoteStatusStore.overridesBySociety[cid]?.contains { $0.id == override.id } } ?? false) {
                    if let status = QuoteStatus(rawValue: override.id), let cid = tableSocietyID {
                        quoteStatusStore.removeOverride(for: status, companyID: cid)
                    }
                }
                Button {
                    editingQuoteStatus = override
                } label: { Image(systemName: "pencil") }
                    .buttonStyle(.borderless)
                    .help("Modifier ce statut")
            }
            if !transitionLabels.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Transitions : " + transitionLabels.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 32)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.clear))
    }

    private var filteredQuoteStatuses: [QuoteStatusOverride] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let resolved = QuoteStatus.allCases.map { status in
            tableSocietyID.map { quoteStatusStore.override(for: status, companyID: $0) } ?? quoteStatusStore.override(for: status)
        }
        guard !q.isEmpty else { return resolved }
        return resolved.filter { $0.label.lowercased().contains(q) || $0.id.lowercased().contains(q) }
    }

    private var filteredStatuses: [OrderStatusOverride] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        // Mélange statuts standard + personnalisés ("custom-…") — résolu par id brut plutôt
        // que via OrderStatus.allCases, pour couvrir les deux (voir le commentaire sur le
        // bouton de retour au réglage global ci-dessus).
        let resolved = statusStore.overrides.map { global in
            tableSocietyID.flatMap { cid in SocietyScopedCatalog.resolvedElement(id: global.id, overrideForSociety: statusStore.overridesBySociety[cid]) } ?? global
        }
        guard !q.isEmpty else { return resolved }
        return resolved.filter { $0.label.lowercased().contains(q) || $0.id.lowercased().contains(q) }
    }

    private var filteredPaymentTerms: [PaymentTermsPreset] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let resolved = tableSocietyID.map { paymentTermsStore.list(for: $0) } ?? paymentTermsStore.presets
        guard !q.isEmpty else { return resolved }
        return resolved.filter { $0.label.lowercased().contains(q) || $0.text.lowercased().contains(q) }
    }

    private func isPaymentTermCustomized(_ id: String) -> Bool {
        tableSocietyID.flatMap { paymentTermsStore.presetsBySociety[$0]?.contains { $0.id == id } } ?? false
    }

    private var paymentTermsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Conditions de paiement").font(.title3.bold())
                Spacer()
                if tableSocietyID == nil {
                    Button {
                        paymentTermsStore.reset()
                    } label: { Label("Réinitialiser", systemImage: "arrow.counterclockwise") }
                        .buttonStyle(.bordered)
                }
                Button {
                    let preset = PaymentTermsPreset(label: "Nouveau préréglage", text: "")
                    if let cid = tableSocietyID {
                        paymentTermsStore.setOverride(preset, companyID: cid)
                    } else {
                        paymentTermsStore.append(preset)
                    }
                    editingPaymentTerm = preset
                } label: { Label("Nouvelle valeur", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredPaymentTerms) { preset in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(preset.label).font(.body)
                                Text(preset.text.isEmpty ? "(texte vide)" : preset.text)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            SocietyOverrideBadge(isCustomized: isPaymentTermCustomized(preset.id)) {
                                if let cid = tableSocietyID {
                                    paymentTermsStore.removeOverride(id: preset.id, companyID: cid)
                                }
                            }
                            Button {
                                editingPaymentTerm = preset
                            } label: { Image(systemName: "pencil") }
                                .buttonStyle(.borderless)
                                .help("Modifier ce préréglage")
                            if tableSocietyID == nil {
                                Button(role: .destructive) {
                                    if let idx = paymentTermsStore.presets.firstIndex(where: { $0.id == preset.id }) {
                                        paymentTermsStore.remove(at: idx)
                                    }
                                } label: { Image(systemName: "trash") }
                                    .buttonStyle(.borderless)
                                    .help("Supprimer ce préréglage")
                            }
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.clear))
                    }
                }
                .padding(12)
            }
        }
    }

    private var tagsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Tags des tiers").font(.title3.bold())
                Spacer()
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredTags) { tag in
                        HStack(spacing: 10) {
                            Circle().fill(Color(hex: tag.hexColor)).frame(width: 14, height: 14)
                            Text(tag.name).font(.body)
                            Spacer()
                            SocietyOverrideBadge(isCustomized: tableSocietyID.flatMap { cid in tagStore.tagsBySociety[cid]?.contains { $0.id == tag.id } } ?? false) {
                                if let cid = tableSocietyID {
                                    tagStore.removeOverride(id: tag.id, companyID: cid)
                                }
                            }
                            Button {
                                editingTag = tag
                            } label: { Image(systemName: "pencil") }
                                .buttonStyle(.borderless)
                                .help("Modifier ce tag")
                            if tableSocietyID == nil {
                                Button(role: .destructive) {
                                    tagStore.delete(tag)
                                } label: { Image(systemName: "trash") }
                                    .buttonStyle(.borderless)
                                    .help("Supprimer ce tag")
                            }
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.clear))
                    }
                    Divider().padding(.vertical, 6)
                    Text("Ajouter un tag").font(.caption.bold())
                    HStack {
                        ColorPicker("", selection: Binding(
                            get: { Color(hex: newTagHex) },
                            set: { newTagHex = hexString(from: $0) }
                        )).labelsHidden().frame(width: 30)
                        TextField("Nom du nouveau tag", text: $newTagName)
                        Button {
                            guard !newTagName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            let newTag = PartyTag(name: newTagName.trimmingCharacters(in: .whitespaces), hexColor: newTagHex)
                            if let cid = tableSocietyID {
                                tagStore.setOverride(newTag, companyID: cid)
                            } else {
                                tagStore.upsert(newTag)
                            }
                            newTagName = ""
                            newTagHex = "555555"
                        } label: { Label("Ajouter", systemImage: "plus.circle.fill") }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(12)
            }
        }
    }

    private var filteredTags: [PartyTag] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let source = tableSocietyID.map { tagStore.list(for: $0) } ?? tagStore.tags
        guard !q.isEmpty else { return source }
        return source.filter { $0.name.lowercased().contains(q) }
    }

    private func displayedHexColor(for kind: DirectoryEntryKind) -> String {
        tableSocietyID.map { kindColors.hexColor(for: kind, companyID: $0) } ?? kindColors.hexColor(for: kind)
    }

    private var kindColorsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Couleurs des types de tiers").font(.title3.bold())
                Spacer()
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(DirectoryEntryKind.selectable, id: \.self) { kind in
                        HStack(spacing: 10) {
                            Circle().fill(Color(hex: displayedHexColor(for: kind))).frame(width: 14, height: 14)
                            Text(kind.label).font(.body)
                            Text(displayedHexColor(for: kind)).font(.caption).foregroundStyle(.secondary).monospaced()
                            Spacer()
                            SocietyOverrideBadge(isCustomized: tableSocietyID.flatMap { cid in kindColors.colorsBySociety[cid]?[kind] != nil } ?? false) {
                                if let cid = tableSocietyID {
                                    kindColors.removeOverride(for: kind, companyID: cid)
                                }
                            }
                            Button {
                                editingKind = kind
                            } label: { Image(systemName: "pencil") }
                                .buttonStyle(.borderless)
                                .help("Modifier cette couleur")
                            if tableSocietyID == nil {
                                Button(role: .destructive) {
                                    kindColors.colors[kind] = kind.defaultHexColor
                                    kindColors.save()
                                } label: { Image(systemName: "trash") }
                                    .buttonStyle(.borderless)
                                    .help("Réinitialiser cette couleur")
                            }
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.clear))
                    }
                }
                .padding(12)
            }
        }
    }

    private func refPanel(_ refs: [NormRef]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(selectedTable.label).font(.title3.bold())
                Spacer()
                Text("Lecture seule (référentiel normatif)").font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(filteredRefs(refs)) { ref in
                        HStack {
                            Text(ref.code).font(.body.monospaced()).frame(width: 100, alignment: .leading)
                            Text(ref.label).foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 3)
                    }
                }
                .padding(12)
            }
        }
    }

    private func filteredRefs(_ refs: [NormRef]) -> [NormRef] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return refs }
        return refs.filter { $0.code.lowercased().contains(q) || $0.label.lowercased().contains(q) }
    }
}

struct PDPStatusCodeEditorSheet: View {
    var existing: PDPEventCodeOverride?
    let onSave: (PDPEventCodeOverride) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var id: String
    @State private var label: String
    @State private var functionalTransition: InvoiceStatus?
    @State private var errorMessage: String?

    private var isNew: Bool { existing == nil }

    init(existing: PDPEventCodeOverride?, onSave: @escaping (PDPEventCodeOverride) -> Void) {
        self.existing = existing
        self.onSave = onSave
        _id = State(initialValue: existing?.id ?? "")
        _label = State(initialValue: existing?.label ?? "")
        _functionalTransition = State(initialValue: existing?.functionalTransition.flatMap { InvoiceStatus(rawValue: $0) })
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(isNew ? "Nouveau code SUPER PDP" : "Modifier le code SUPER PDP").font(.title3.bold())
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Code").frame(width: 140, alignment: .leading)
                    TextField("ex. fr:214", text: $id)
                        .textFieldStyle(.roundedBorder)
                        .disabled(!isNew)
                        .disableAutocorrection(true)
                }
                HStack {
                    Text("Libellé").frame(width: 140, alignment: .leading)
                    TextField("Libellé", text: $label).textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Règle de mise à jour").frame(width: 140, alignment: .leading)
                        Picker("", selection: $functionalTransition) {
                            Text("Aucune (informatif seulement)").tag(InvoiceStatus?.none)
                            ForEach(InvoiceStatus.allCases, id: \.self) { s in
                                Text(s.label).tag(InvoiceStatus?.some(s))
                            }
                        }
                        .labelsHidden()
                        Spacer()
                    }
                    Text("Si ce code est envoyé ou reçu pour une facture, le statut choisi ici s'applique — sauf s'il s'agirait d'une rétrogradation dans le cycle de vie.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            if let err = errorMessage {
                Text(err).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Enregistrer") {
                    let trimmedID = id.trimmingCharacters(in: .whitespaces)
                    guard !trimmedID.isEmpty else {
                        errorMessage = "Le code ne peut pas être vide."
                        return
                    }
                    let trimmedLabel = label.trimmingCharacters(in: .whitespaces)
                    onSave(PDPEventCodeOverride(
                        id: trimmedID,
                        label: trimmedLabel.isEmpty ? trimmedID : trimmedLabel,
                        functionalTransition: functionalTransition?.rawValue,
                        isSystemDefined: existing?.isSystemDefined ?? false
                    ))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(id.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

struct OrderStatusEditorSheet: View {
    var override: OrderStatusOverride
    let onSave: (OrderStatusOverride) -> Void
    @EnvironmentObject var statusStore: OrderStatusStore
    @Environment(\.dismiss) private var dismiss
    @State private var label: String
    @State private var systemImage: String
    @State private var hexColor: String
    @State private var transitionCodes: Set<String>

    private var possibleTargets: [OrderStatusOverride] {
        statusStore.overrides.filter { $0.id != override.id }
    }

    init(override: OrderStatusOverride, onSave: @escaping (OrderStatusOverride) -> Void) {
        self.override = override
        self.onSave = onSave
        _label = State(initialValue: override.label)
        _systemImage = State(initialValue: override.systemImage)
        _hexColor = State(initialValue: override.hexColor)
        _transitionCodes = State(initialValue: Set(override.transitionCodes))
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Modifier le statut").font(.title3.bold())
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Libellé").frame(width: 100, alignment: .leading)
                    TextField("Libellé", text: $label).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Icône SF").frame(width: 100, alignment: .leading)
                    TextField("Icône SF", text: $systemImage).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Couleur").frame(width: 100, alignment: .leading)
                    ColorPicker(selection: Binding(
                        get: { Color(hex: hexColor) },
                        set: { hexColor = hexString(from: $0) }
                    )) { Text("Couleur") }
                }
            }
            if !possibleTargets.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Transitions autorisées vers…").font(.subheadline.bold())
                    Text("Statuts accessibles depuis « \(label) » via les boutons d'action de la commande (un administrateur peut toujours forcer les autres).")
                        .font(.caption).foregroundStyle(.secondary)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(possibleTargets) { target in
                                Toggle(isOn: Binding(
                                    get: { transitionCodes.contains(target.id) },
                                    set: { isOn in
                                        if isOn { transitionCodes.insert(target.id) }
                                        else { transitionCodes.remove(target.id) }
                                    }
                                )) {
                                    Label(target.label, systemImage: target.systemImage)
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                    }
                    .frame(maxHeight: 140)
                }
            }
            HStack {
                Spacer()
                Button("Enregistrer") {
                    let ordered = statusStore.overrides.map { $0.id }.filter { transitionCodes.contains($0) }
                    onSave(OrderStatusOverride(id: override.id, label: label, systemImage: systemImage, hexColor: hexColor, transitionCodes: ordered))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 460, height: 460)
    }
}

struct QuoteStatusEditorSheet: View {
    var override: QuoteStatusOverride
    let onSave: (QuoteStatusOverride) -> Void
    @EnvironmentObject var quoteStatusStore: QuoteStatusStore
    @Environment(\.dismiss) private var dismiss
    @State private var label: String
    @State private var systemImage: String
    @State private var hexColor: String
    @State private var transitionCodes: Set<String>

    private var possibleTargets: [QuoteStatusOverride] {
        quoteStatusStore.overrides.filter { $0.id != override.id }
    }

    init(override: QuoteStatusOverride, onSave: @escaping (QuoteStatusOverride) -> Void) {
        self.override = override
        self.onSave = onSave
        _label = State(initialValue: override.label)
        _systemImage = State(initialValue: override.systemImage)
        _hexColor = State(initialValue: override.hexColor)
        _transitionCodes = State(initialValue: Set(override.transitionCodes))
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Modifier le statut").font(.title3.bold())
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Libellé").frame(width: 100, alignment: .leading)
                    TextField("Libellé", text: $label).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Icône SF").frame(width: 100, alignment: .leading)
                    TextField("Icône SF", text: $systemImage).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Couleur").frame(width: 100, alignment: .leading)
                    ColorPicker(selection: Binding(
                        get: { Color(hex: hexColor) },
                        set: { hexColor = hexString(from: $0) }
                    )) { Text("Couleur") }
                }
            }
            if !possibleTargets.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Transitions autorisées vers…").font(.subheadline.bold())
                    Text("Statuts accessibles depuis « \(label) » via les boutons d'action du devis.")
                        .font(.caption).foregroundStyle(.secondary)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(possibleTargets) { target in
                                Toggle(isOn: Binding(
                                    get: { transitionCodes.contains(target.id) },
                                    set: { isOn in
                                        if isOn { transitionCodes.insert(target.id) }
                                        else { transitionCodes.remove(target.id) }
                                    }
                                )) {
                                    Label(target.label, systemImage: target.systemImage)
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                    }
                    .frame(maxHeight: 140)
                }
            }
            HStack {
                Spacer()
                Button("Enregistrer") {
                    let ordered = quoteStatusStore.overrides.map { $0.id }.filter { transitionCodes.contains($0) }
                    onSave(QuoteStatusOverride(id: override.id, label: label, systemImage: systemImage, hexColor: hexColor, transitionCodes: ordered))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 460, height: 460)
    }
}

struct InvoiceStatusEditorSheet: View {
    var override: InvoiceStatusOverride
    let onSave: (InvoiceStatusOverride) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var label: String
    @State private var systemImage: String
    @State private var hexColor: String
    @State private var transitionCodes: Set<String>

    private var currentStatus: InvoiceStatus? { InvoiceStatus(rawValue: override.id) }
    private var possibleTargets: [InvoiceStatus] { InvoiceStatus.allCases.filter { $0.rawValue != override.id } }

    init(override: InvoiceStatusOverride, onSave: @escaping (InvoiceStatusOverride) -> Void) {
        self.override = override
        self.onSave = onSave
        _label = State(initialValue: override.label)
        _systemImage = State(initialValue: override.systemImage)
        _hexColor = State(initialValue: override.hexColor)
        _transitionCodes = State(initialValue: Set(override.transitionCodes))
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Modifier le statut facture").font(.title3.bold())
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if override.isReformStatus {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill").foregroundStyle(.secondary)
                    Text("Statut de réforme (PDP) — code \(override.reformCode ?? ""). Seul le libellé est modifiable.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.1)))
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Libellé").frame(width: 100, alignment: .leading)
                    TextField("Libellé", text: $label).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Icône SF").frame(width: 100, alignment: .leading)
                    TextField("Icône SF", text: $systemImage).textFieldStyle(.roundedBorder)
                        .disabled(override.isReformStatus)
                }
                HStack {
                    Text("Couleur").frame(width: 100, alignment: .leading)
                    ColorPicker(selection: Binding(
                        get: { Color(hex: hexColor) },
                        set: { hexColor = hexString(from: $0) }
                    )) { Text("Couleur") }
                    .disabled(override.isReformStatus)
                }
            }
            if currentStatus != nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Transitions autorisées vers…").font(.subheadline.bold())
                    Text("Statuts accessibles depuis « \(label) » via les boutons d'action de la facture (un administrateur peut toujours forcer les autres).")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(possibleTargets, id: \.self) { target in
                        Toggle(isOn: Binding(
                            get: { transitionCodes.contains(target.rawValue) },
                            set: { isOn in
                                if isOn { transitionCodes.insert(target.rawValue) }
                                else { transitionCodes.remove(target.rawValue) }
                            }
                        )) {
                            Label(target.label, systemImage: target.systemImage)
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Enregistrer") {
                    let ordered = InvoiceStatus.allCases.map { $0.rawValue }.filter { transitionCodes.contains($0) }
                    onSave(InvoiceStatusOverride(id: override.id, label: label, systemImage: systemImage, hexColor: hexColor, reformCode: override.reformCode, transitionCodes: ordered))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Spacer()
        }
        .padding()
        .frame(width: 460, height: 460)
    }
}

struct PurchaseInvoiceStatusEditorSheet: View {
    var override: PurchaseInvoiceStatusOverride
    let onSave: (PurchaseInvoiceStatusOverride) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var label: String
    @State private var systemImage: String
    @State private var hexColor: String
    @State private var transitionCodes: Set<String>

    private var currentStatus: PurchaseInvoiceStatus? { PurchaseInvoiceStatus(rawValue: override.id) }
    private var possibleTargets: [PurchaseInvoiceStatus] { PurchaseInvoiceStatus.allCases.filter { $0.rawValue != override.id } }

    init(override: PurchaseInvoiceStatusOverride, onSave: @escaping (PurchaseInvoiceStatusOverride) -> Void) {
        self.override = override
        self.onSave = onSave
        _label = State(initialValue: override.label)
        _systemImage = State(initialValue: override.systemImage)
        _hexColor = State(initialValue: override.hexColor)
        _transitionCodes = State(initialValue: Set(override.transitionCodes))
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Modifier le statut de facture d'achat").font(.title3.bold())
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if override.isReformStatus {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill").foregroundStyle(.secondary)
                    Text("Statut de réforme (PDP) — code \(override.reformCode ?? ""). Seul le libellé est modifiable.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.1)))
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Libellé").frame(width: 100, alignment: .leading)
                    TextField("Libellé", text: $label).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Icône SF").frame(width: 100, alignment: .leading)
                    TextField("Icône SF", text: $systemImage).textFieldStyle(.roundedBorder)
                        .disabled(override.isReformStatus)
                }
                HStack {
                    Text("Couleur").frame(width: 100, alignment: .leading)
                    ColorPicker(selection: Binding(
                        get: { Color(hex: hexColor) },
                        set: { hexColor = hexString(from: $0) }
                    )) { Text("Couleur") }
                    .disabled(override.isReformStatus)
                }
            }
            if currentStatus != nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Transitions autorisées vers…").font(.subheadline.bold())
                    Text("Statuts accessibles depuis « \(label) » via les boutons d'action de la facture d'achat (un administrateur peut toujours forcer les autres).")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(possibleTargets, id: \.self) { target in
                        Toggle(isOn: Binding(
                            get: { transitionCodes.contains(target.rawValue) },
                            set: { isOn in
                                if isOn { transitionCodes.insert(target.rawValue) }
                                else { transitionCodes.remove(target.rawValue) }
                            }
                        )) {
                            Label(target.label, systemImage: target.systemImage)
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Enregistrer") {
                    let ordered = PurchaseInvoiceStatus.allCases.map { $0.rawValue }.filter { transitionCodes.contains($0) }
                    onSave(PurchaseInvoiceStatusOverride(id: override.id, label: label, systemImage: systemImage, hexColor: hexColor, reformCode: override.reformCode, transitionCodes: ordered))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Spacer()
        }
        .padding()
        .frame(width: 460, height: 460)
    }
}

struct PaymentTermsPresetEditorSheet: View {
    var preset: PaymentTermsPreset
    let onSave: (PaymentTermsPreset) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var label: String
    @State private var text: String
    @State private var ruleKind: DueRuleKind
    @State private var days: Int

    private enum DueRuleKind: String, CaseIterable, Identifiable {
        case none = "Aucune (saisie manuelle)"
        case days = "Jours nets"
        case endOfMonth = "Fin de mois + jours"
        var id: String { rawValue }
    }

    init(preset: PaymentTermsPreset, onSave: @escaping (PaymentTermsPreset) -> Void) {
        self.preset = preset
        self.onSave = onSave
        _label = State(initialValue: preset.label)
        _text = State(initialValue: preset.text)
        switch preset.dueRule {
        case .none:
            _ruleKind = State(initialValue: .none)
            _days = State(initialValue: 30)
        case .days(let n):
            _ruleKind = State(initialValue: .days)
            _days = State(initialValue: n)
        case .endOfMonthPlusDays(let n):
            _ruleKind = State(initialValue: .endOfMonth)
            _days = State(initialValue: n)
        }
    }

    private var dueRule: PaymentTermsDueRule {
        switch ruleKind {
        case .none: return .none
        case .days: return .days(days)
        case .endOfMonth: return .endOfMonthPlusDays(days)
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Modifier le préréglage").font(.title3.bold())
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Libellé").frame(width: 160, alignment: .leading)
                    TextField("Libellé affiché dans le menu", text: $label).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Texte").frame(width: 160, alignment: .leading)
                    TextField("Texte inséré dans les conditions de paiement", text: $text).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Échéance").frame(width: 160, alignment: .leading)
                    Picker("", selection: $ruleKind) {
                        ForEach(DueRuleKind.allCases) { k in Text(k.rawValue).tag(k) }
                    }
                    .labelsHidden()
                }
                if ruleKind != .none {
                    HStack {
                        Text(ruleKind == .days ? "Nombre de jours" : "Jours après fin de mois").frame(width: 160, alignment: .leading)
                        Stepper(value: $days, in: 0...120) { Text("\(days) j") }
                    }
                    Text("Échéance calculée automatiquement pour toute facture utilisant ce préréglage.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("L'échéance reste à saisir manuellement sur chaque facture.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("Enregistrer") {
                    onSave(PaymentTermsPreset(id: preset.id, label: label, text: text, dueRule: dueRule))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty || text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Spacer()
        }
        .padding()
        .frame(width: 440, height: 360)
    }
}

struct TagEditorSheet: View {
    var tag: PartyTag
    let onSave: (PartyTag) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var hexColor: String

    init(tag: PartyTag, onSave: @escaping (PartyTag) -> Void) {
        self.tag = tag
        self.onSave = onSave
        _name = State(initialValue: tag.name)
        _hexColor = State(initialValue: tag.hexColor)
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Modifier le tag").font(.title3.bold())
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Nom").frame(width: 100, alignment: .leading)
                    TextField("Nom du tag", text: $name).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Couleur").frame(width: 100, alignment: .leading)
                    ColorPicker(selection: Binding(
                        get: { Color(hex: hexColor) },
                        set: { hexColor = hexString(from: $0) }
                    )) { Text("Couleur") }
                }
            }
            HStack {
                Spacer()
                Button("Enregistrer") {
                    onSave(PartyTag(id: tag.id, name: name, hexColor: hexColor))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Spacer()
        }
        .padding()
        .frame(width: 420, height: 260)
    }
}

struct KindColorEditorSheet: View {
    let kind: DirectoryEntryKind
    var hex: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var hexColor: String

    init(kind: DirectoryEntryKind, hex: String, onSave: @escaping (String) -> Void) {
        self.kind = kind
        self.hex = hex
        self.onSave = onSave
        _hexColor = State(initialValue: hex)
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Modifier la couleur").font(.title3.bold())
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Type").frame(width: 100, alignment: .leading)
                    Text(kind.label)
                }
                HStack {
                    Text("Couleur").frame(width: 100, alignment: .leading)
                    ColorPicker(selection: Binding(
                        get: { Color(hex: hexColor) },
                        set: { hexColor = hexString(from: $0) }
                    )) { Text("Couleur") }
                }
            }
            HStack {
                Spacer()
                Button("Enregistrer") {
                    onSave(hexColor)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .padding()
        .frame(width: 420, height: 240)
    }
}
