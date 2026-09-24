import SwiftUI
import FacturXCore
import PDFKit
import UniformTypeIdentifiers

// MARK: - Extrait de FacturXMacApp.swift (découpage par domaine)

enum InvoiceTypeFilter: String, CaseIterable, Hashable {
    case all = "Tous"
    case invoice = "Factures"
    case creditNote = "Avoirs"
}

enum InvoiceFilterField: String, CaseIterable, Hashable {
    case none = "Aucun"
    case number = "N° facture"
    case buyerName = "Client"
    case buyerSiren = "SIREN client"
    case buyerVat = "TVA client"
    case sellerName = "Émetteur"
    case sellerSiren = "SIREN émetteur"
    case amountMin = "Montant TTC min"
    case amountMax = "Montant TTC max"
    case issueDateFrom = "Émise depuis"
    case issueDateTo = "Émise jusqu'à"
    case dueDateFrom = "Échue depuis"
    case purchaseOrderRef = "Réf. commande"
    case contractRef = "Réf. contrat"
    case precedingInvoiceRef = "Facture antérieure"
    case status = "Statut"
    case type = "Type"
}

struct OrderToInvoiceSheet: View {
    let orders: [SalesOrder]
    let onCreate: (SalesOrder) -> Void
    let onCancel: () -> Void
    @State private var query = ""
    @State private var selectedOrderID: UUID?

    private var filteredOrders: [SalesOrder] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return orders }
        return orders.filter { order in
            order.number.lowercased().contains(q)
                || order.buyer.name.lowercased().contains(q)
                || order.seller.name.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Créer une facture depuis une commande").font(.headline)
                Spacer()
            }
            .padding(12)
            Divider()
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Rechercher (numéro, acheteur, client…)", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            Divider()
            if filteredOrders.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "cart").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Aucune commande disponible dans votre périmètre.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(Array(filteredOrders.enumerated()), id: \.element.id) { _, order in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(order.number).font(.headline)
                            Text("\(order.buyer.name.isEmpty ? "Sans client" : order.buyer.name)")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(String(format: "%.2f %@ TTC", order.grandTotal, order.currency))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(order.issueDate, format: .dateTime.day().month().year())
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selectedOrderID = order.id }
                    .background(selectedOrderID == order.id ? Color.accentColor.opacity(0.15) : Color.clear)
                }
            }
            Divider()
            HStack {
                Button("Annuler", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Créer la facture") {
                    if let order = filteredOrders.first(where: { $0.id == selectedOrderID }) {
                        onCreate(order)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedOrderID == nil)
            }
            .padding(12)
        }
        .frame(width: 520, height: 420)
    }
}

struct QuoteToInvoiceSheet: View {
    let quotes: [Quote]
    let onCreate: (Quote) -> Void
    let onCancel: () -> Void
    @State private var query = ""
    @State private var selectedQuoteID: UUID?

    private var filteredQuotes: [Quote] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return quotes }
        return quotes.filter { quote in
            quote.number.lowercased().contains(q)
                || quote.buyer.name.lowercased().contains(q)
                || quote.seller.name.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Créer une facture depuis un devis").font(.headline)
                Spacer()
            }
            .padding(12)
            Divider()
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Rechercher (numéro, client…)", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            Divider()
            if filteredQuotes.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.below.ecg").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Aucun devis accepté disponible à facturer dans votre périmètre.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(Array(filteredQuotes.enumerated()), id: \.element.id) { _, quote in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(quote.number).font(.headline)
                            Text("\(quote.buyer.name.isEmpty ? "Sans client" : quote.buyer.name)")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(String(format: "%.2f %@ TTC", quote.grandTotal, quote.currency))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(quote.issueDate, format: .dateTime.day().month().year())
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selectedQuoteID = quote.id }
                    .background(selectedQuoteID == quote.id ? Color.accentColor.opacity(0.15) : Color.clear)
                }
            }
            Divider()
            HStack {
                Button("Annuler", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Créer la facture") {
                    if let quote = filteredQuotes.first(where: { $0.id == selectedQuoteID }) {
                        onCreate(quote)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedQuoteID == nil)
            }
            .padding(12)
        }
        .frame(width: 520, height: 420)
    }
}

struct InvoicePickerSheet: View {
    let invoices: [Invoice]
    let selectedID: UUID?
    let onPick: (Invoice) -> Void
    let onClear: () -> Void
    let onCancel: () -> Void
    @State private var query = ""
    @State private var companyFilter: UUID?
    @State private var localSelectedID: UUID?

    private var companies: [DirectoryEntry] {
        let dir = PartyDirectory.shared
        let ids = Set(invoices.compactMap { $0.companyID })
        return dir.entries.filter { ids.contains($0.id) }.sorted { $0.party.name < $1.party.name }
    }

    private var filtered: [Invoice] {
        var result = invoices
        if let cid = companyFilter {
            result = result.filter { $0.companyID == cid }
        }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return result.sorted { $0.issueDate > $1.issueDate } }
        return result.filter { inv in
            inv.number.lowercased().contains(q)
                || inv.seller.name.lowercased().contains(q)
                || inv.buyer.name.lowercased().contains(q)
                || (inv.buyer.siren ?? "").lowercased().contains(q)
        }.sorted { $0.issueDate > $1.issueDate }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sélectionner la facture antérieure").font(.headline)
                Spacer()
            }
            .padding(12)
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Rechercher (numéro, client, SIREN…)", text: $query)
                    .textFieldStyle(.plain)
                if !companies.isEmpty {
                    Picker("Société", selection: $companyFilter) {
                        Text("Toutes les sociétés").tag(UUID?.none)
                        ForEach(companies) { c in
                            Text(c.party.name.isEmpty ? "Sans nom" : c.party.name).tag(Optional(c.id))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            Divider()
            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Aucune facture disponible dans votre périmètre.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered) { inv in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(inv.number).font(.headline)
                                if (localSelectedID ?? selectedID) == inv.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                        .font(.caption)
                                }
                            }
                            Text("\(inv.seller.name.isEmpty ? "Sans émetteur" : inv.seller.name) → \(inv.buyer.name.isEmpty ? "Sans client" : inv.buyer.name)")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(String(format: "%.2f %@ TTC", inv.grandTotal, inv.currency))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(inv.issueDate, format: .dateTime.day().month().year())
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { localSelectedID = inv.id }
                    .background((localSelectedID ?? selectedID) == inv.id ? Color.accentColor.opacity(0.15) : Color.clear)
                }
            }
            Divider()
            HStack {
                Button("Annuler", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Effacer", role: .destructive, action: onClear)
                    .buttonStyle(.bordered)
                Spacer()
                Button("Sélectionner") {
                    let id = localSelectedID ?? selectedID
                    if let picked = filtered.first(where: { $0.id == id }) {
                        onPick(picked)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(localSelectedID == nil && selectedID == nil)
            }
            .padding(12)
        }
        .frame(width: 620, height: 460)
        .onAppear {
            localSelectedID = selectedID
            companyFilter = nil
        }
    }
}

struct DepositsPickerSheet: View {
    let source: Invoice
    let deposits: [Invoice]
    let onConfirm: ([Invoice]) -> Void
    let onCancel: () -> Void
    @State private var query = ""
    @State private var selected: Set<UUID> = []

    private var filtered: [Invoice] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return deposits }
        return deposits.filter { inv in
            inv.number.lowercased().contains(q)
                || inv.seller.name.lowercased().contains(q)
                || inv.buyer.name.lowercased().contains(q)
                || (inv.buyer.siren ?? "").lowercased().contains(q)
        }
    }

    private var selectedTotal: Double {
        deposits.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.grandTotal }.rounded(toPlaces: 2)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sélectionner les acomptes à solder").font(.headline)
                Spacer()
            }
            .padding(12)
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Rechercher (numéro, client, SIREN…)", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            Divider()
            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Aucun acompte disponible dans votre périmètre.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered) { dep in
                    Toggle(isOn: Binding(
                        get: { selected.contains(dep.id) },
                        set: { isOn in
                            if isOn { selected.insert(dep.id) } else { selected.remove(dep.id) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(dep.number).font(.headline)
                                Spacer()
                                Text(dep.issueDate, format: .dateTime.day().month().year())
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Text(dep.buyer.name.isEmpty ? "Sans client" : dep.buyer.name)
                                .font(.caption).foregroundStyle(.secondary)
                            Text(String(format: "%.2f %@ TTC", dep.grandTotal, dep.currency))
                                .font(.caption2).foregroundStyle(.secondary)
                            if let ref = dep.linkedSettlementRef, !ref.isEmpty {
                                Label("Déjà utilisé dans \(ref)", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption2).foregroundStyle(.orange)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            Divider()
            HStack {
                Button("Annuler", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if !selected.isEmpty {
                    Text("Total sélectionné : \(String(format: "%.2f", selectedTotal)) — \(selected.count) acompte(s)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Créer le solde") {
                    onConfirm(deposits.filter { selected.contains($0.id) })
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty)
            }
            .padding(12)
        }
        .frame(width: 620, height: 460)
    }
}

struct InvoicesTabView: View {
    @EnvironmentObject var store: InvoiceStore
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var orderStore: OrderStore
    @EnvironmentObject var quoteStore: QuoteStore
    @EnvironmentObject var moduleStore: ModuleStore
    @Binding var selectedID: UUID?
    @Binding var companyFilter: UUID?
    @State private var query = ""
    @State private var typeFilter: InvoiceTypeFilter = .all
    @State private var statusFilter: InvoiceStatus? = nil
    @State private var showOrderPicker = false
    @State private var showQuotePicker = false
    @State private var showQuickInvoiceWizard = false
    @State private var showScanImport = false
    @State private var showDepositsPicker = false
    @State private var depositsPickerSource: Invoice?
    @State private var exportMessage: String?
    @State private var showAdvancedFilters = false
    @State private var advField1: InvoiceFilterField = .none
    @State private var advValue1 = ""
    @State private var advField2: InvoiceFilterField = .none
    @State private var advValue2 = ""
    @State private var advField3: InvoiceFilterField = .none
    @State private var advValue3 = ""

    var filteredInvoices: [Invoice] {
        var result = store.invoices
        if let scope = auth.visibleInvoiceCompanyIDs(for: auth.currentUser) {
            result = result.filter { inv in
                if let cid = inv.companyID { return scope.contains(cid) }
                return false
            }
        }
        switch typeFilter {
        case .all:
            break
        case .invoice:
            result = result.filter { !$0.type.isCreditNote }
        case .creditNote:
            result = result.filter { $0.type.isCreditNote }
        }
        if let sf = statusFilter {
            result = result.filter { $0.status == sf }
        }
        if let cf = companyFilter {
            result = result.filter { $0.companyID == cf }
        }
        result = applyAdvancedFilter(result, field: advField1, value: advValue1)
        result = applyAdvancedFilter(result, field: advField2, value: advValue2)
        result = applyAdvancedFilter(result, field: advField3, value: advValue3)
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return result }
        return result.filter { invoice in
            invoice.number.lowercased().contains(q)
                || invoice.buyer.name.lowercased().contains(q)
                || (invoice.buyer.siren ?? "").lowercased().contains(q)
                || (invoice.seller.name.lowercased()).contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    // Bouton scindé : le corps crée directement un brouillon (action la plus
                    // fréquente), la flèche ouvre les autres origines — remplace 4 boutons
                    // séparés qui finissaient tronqués dans la barre d'actions.
                    Menu {
                        if moduleStore.settings.ordersEnabled {
                            Button {
                                showOrderPicker = true
                            } label: { Label("Depuis une commande", systemImage: "cart") }
                        }
                        if moduleStore.settings.quotesEnabled {
                            Button {
                                showQuotePicker = true
                            } label: { Label("Depuis un devis", systemImage: "doc.text.below.ecg") }
                                .help("Convertit un devis accepté en facture")
                        }
                        Button {
                            showScanImport = true
                        } label: { Label("Scanner un document", systemImage: "doc.viewfinder") }
                            .help("Importer la photo/le scan d'un devis signé ou d'un bon de commande client pour pré-remplir une facture")
                    } label: {
                        Label("Nouvelle facture", systemImage: "plus")
                    } primaryAction: {
                        let draft = store.newDraft(companyID: companyFilter ?? defaultCompanyID(),
                                                   preferredSellerEntryID: auth.currentUser?.defaultSellerEntryID)
                        store.upsert(draft)
                        selectedID = draft.id
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Nouvelle facture vierge — flèche pour créer depuis une commande, un devis, ou en scannant un document")
                    Text("Factures").font(.title2.bold())
                    Button {
                        showQuickInvoiceWizard = true
                    } label: { Label("Facture guidée", systemImage: "wand.and.stars") }
                        .buttonStyle(.bordered)
                        .help("Créer une facture en quelques étapes avec le minimum d'informations")
                    Picker("Filtre", selection: $typeFilter) {
                        ForEach(InvoiceTypeFilter.allCases, id: \.self) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                    Picker("Statut", selection: $statusFilter) {
                        Text("Tous statuts").tag(InvoiceStatus?.none)
                        ForEach(InvoiceStatus.allCases, id: \.self) { s in
                            Label(s.label, systemImage: s.systemImage).tag(InvoiceStatus?.some(s))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                    Spacer()
                    Menu {
                        ForEach(QuickExport.Format.allCases, id: \.self) { f in
                            Button(f.rawValue) { exportMessage = QuickExport.run(invoices: filteredInvoices, format: f) }
                        }
                    } label: { Label("Exporter", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.bordered)
                        .help("Exporte les factures actuellement filtrées (\(filteredInvoices.count))")
                }
                if let m = exportMessage, !m.isEmpty {
                    ExportMessageText(message: m)
                        .onChange(of: query) { _ in exportMessage = nil }
                }
                HStack(spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Rechercher (numéro, client, SIREN…)", text: $query)
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
                    Button {
                        showAdvancedFilters.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: showAdvancedFilters ? "chevron.down" : "chevron.right")
                                .font(.caption2).foregroundStyle(.secondary)
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.caption)
                            Text("Filtres avancés")
                                .font(.caption.bold())
                            Text("(\(activeAdvancedFilterCount))")
                                .font(.caption.bold())
                                .foregroundStyle(activeAdvancedFilterCount > 0 ? Color.accentColor : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    if activeAdvancedFilterCount > 0 {
                        Button {
                            resetAdvancedFilters()
                        } label: {
                            Image(systemName: "xmark.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Réinitialiser les filtres avancés")
                    }
                }
                if showAdvancedFilters {
                    HStack(alignment: .center, spacing: 12) {
                        advancedFilterRow(field: $advField1, value: $advValue1, index: 1)
                        advancedFilterRow(field: $advField2, value: $advValue2, index: 2)
                        advancedFilterRow(field: $advField3, value: $advValue3, index: 3)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(12)

            Divider()

            HSplitView {
                if filteredInvoices.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text").font(.largeTitle).foregroundStyle(.secondary)
                        Text("Aucune facture.")
                            .foregroundStyle(.secondary)
                        Button("Nouvelle facture") {
                            let draft = store.newDraft(companyID: companyFilter ?? defaultCompanyID())
                            store.upsert(draft)
                            selectedID = draft.id
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { listProxy in
                    List(filteredInvoices, selection: Binding(
                        get: { selectedID },
                        set: { id in selectedID = id }
                    )) { invoice in
                        VStack(alignment: .leading) {
                            HStack {
                                Text(invoice.number).font(.headline)
                                Spacer()
                                Text(invoice.issueDate, format: .dateTime.day().month().year())
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            HStack(spacing: 6) {
                                Image(systemName: invoice.status.systemImage)
                                    .foregroundColor(Color(hex: invoice.status.hexColor))
                                    .font(.caption2)
                                Text(invoice.status.label).font(.caption2)
                                    .foregroundColor(Color(hex: invoice.status.hexColor))
                                Text(invoice.type.isInternalCreditNote ? "Avoir interne" : invoice.type == .creditNote ? "Avoir" : invoice.type.isDeposit ? "Acompte" : invoice.type.isFinalSettlement ? "Solde" : "Facture")
                                    .font(.caption2).foregroundStyle(invoice.type.isCreditNote ? Color.orange : Color.accentColor)
                                if invoice.isOverdue {
                                    Label("En retard", systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption2).foregroundStyle(.red)
                                }
                                Spacer()
                            }
                            Text("\(invoice.buyer.name.isEmpty ? "Sans client" : invoice.buyer.name)")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(String(format: "%.2f %@ TTC", invoice.grandTotal, invoice.currency))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .contextMenu {
                            Button {
                                let copy = store.duplicate(from: invoice)
                                store.upsert(copy)
                                selectedID = copy.id
                            } label: { Label("Dupliquer", systemImage: "plus.square.on.square") }
                            Button {
                                let credit = store.newCreditNote(from: invoice)
                                store.upsert(credit)
                                selectedID = credit.id
                            } label: { Label("Créer un avoir", systemImage: "arrow.uturn.backward.circle") }
                            .disabled(invoice.type.isCreditNote)
                            Button {
                                let deposit = store.newDeposit(from: invoice)
                                store.upsert(deposit)
                                selectedID = deposit.id
                            } label: { Label("Créer un acompte", systemImage: "eurosign.circle") }
                            .disabled(!invoice.type.allowsDepositCreation)
                            Button {
                                depositsPickerSource = invoice
                                showDepositsPicker = true
                            } label: { Label("Créer le solde", systemImage: "checkmark.seal") }
                            .disabled(!invoice.type.allowsDepositCreation)
                            Divider()
                            Button(role: .destructive) {
                                store.invoices.removeAll { $0.id == invoice.id }
                                store.save()
                                if selectedID == invoice.id { selectedID = nil }
                            } label: { Label("Supprimer", systemImage: "trash") }
                        }
                    }
                    .frame(minWidth: 180, idealWidth: 230, maxWidth: 270)
                    .onChange(of: selectedID) { newID in
                        // À la création d'une facture (insérée en tête de liste), le haut de la
                        // nouvelle ligne pouvait rester hors champ si la liste était défilée plus
                        // bas — on recentre explicitement sur la sélection. Le défilement est
                        // différé au prochain tour de boucle : appelé de façon synchrone depuis
                        // ce onChange, il s'exécute encore pendant le rappel délégué de la
                        // NSTableView sous-jacente et AppKit journalise une opération réentrante
                        // ("WARNING: Application performed a reentrant operation in its
                        // NSTableView delegate").
                        if let newID {
                            DispatchQueue.main.async {
                                withAnimation { listProxy.scrollTo(newID, anchor: .top) }
                            }
                        }
                    }
                    }
                }

                if let id = selectedID,
                   filteredInvoices.contains(where: { $0.id == id }) {
                    // Une instance d'éditeur par facture (`.id(id)`). Sans cela, SwiftUI réutilise la
                    // vue et ses `@State` d'une facture sélectionnée à l'autre, et chaque
                    // `onChange(of: invoice.…)` de l'éditeur se déclenche au simple changement de
                    // sélection. Avec `onChange(of:perform:)` (API macOS 13), c'est en plus la closure
                    // du rendu précédent qui s'exécute : elle agit sur la facture qu'on quitte, avec la
                    // valeur de celle qu'on ouvre (échéance réécrite, statut envoyé à SUPER PDP).
                    // Le VStack garde le panneau du HSplitView stable : un `.id` posé sur l'enfant
                    // direct du HSplitView remplace le panneau et ramène le séparateur à sa largeur
                    // par défaut à chaque sélection.
                    VStack(spacing: 0) {
                        InvoiceEditorView(invoice: binding(for: id))
                            .id(id)
                    }
                    .frame(minWidth: 420)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass").font(.largeTitle).foregroundStyle(.secondary)
                        Text("Sélectionnez ou créez une facture")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .sheet(isPresented: $showOrderPicker) {
            OrderToInvoiceSheet(
                orders: scopedOrders,
                onCreate: { order in
                    let number = store.nextNumber(companyID: order.companyID)
                    let invoice = order.toInvoice(number: number)
                    store.upsert(invoice)
                    selectedID = invoice.id
                    showOrderPicker = false
                },
                onCancel: { showOrderPicker = false }
            )
        }
        .sheet(isPresented: $showQuotePicker) {
            QuoteToInvoiceSheet(
                quotes: scopedInvoiceableQuotes,
                onCreate: { quote in
                    let number = store.nextNumber(companyID: quote.companyID)
                    let invoice = quote.toInvoice(number: number)
                    store.upsert(invoice)
                    var converted = quote
                    converted.convertedInvoiceNumber = invoice.number
                    quoteStore.upsert(converted)
                    selectedID = invoice.id
                    showQuotePicker = false
                },
                onCancel: { showQuotePicker = false }
            )
        }
        .sheet(isPresented: $showQuickInvoiceWizard) {
            SalesInvoiceWizardView(
                onCreated: { invoiceID in
                    selectedID = invoiceID
                    showQuickInvoiceWizard = false
                },
                onCancel: { showQuickInvoiceWizard = false }
            )
        }
        .sheet(isPresented: $showScanImport) {
            DocumentScanInvoiceImportView(
                onCreated: { invoiceID in
                    selectedID = invoiceID
                    showScanImport = false
                },
                onCancel: { showScanImport = false }
            )
        }
        .sheet(isPresented: $showDepositsPicker) {
            if let source = depositsPickerSource {
                DepositsPickerSheet(
                    source: source,
                    deposits: candidateDeposits(for: source),
                    onConfirm: { selectedDeposits in
                        let final = store.newFinalSettlement(from: source, deposits: selectedDeposits)
                        store.upsert(final)
                        for dep in selectedDeposits {
                            var updated = dep
                            updated.linkedSettlementRef = final.number
                            store.upsert(updated)
                        }
                        selectedID = final.id
                        showDepositsPicker = false
                    },
                    onCancel: { showDepositsPicker = false }
                )
            } else {
                EmptyView()
            }
        }
        .onChange(of: showDepositsPicker) { showing in
            if !showing { depositsPickerSource = nil }
        }
        .onChange(of: filteredInvoices) { newList in
            if let id = selectedID, !newList.contains(where: { $0.id == id }) {
                selectedID = nil
            }
        }
        .onChange(of: selectedID) { id in
            if let id = id, !filteredInvoices.contains(where: { $0.id == id }) {
                selectedID = nil
            }
        }
    }

    private var scopedOrders: [SalesOrder] {
        var result = orderStore.orders
        if let scope = auth.visibleOrderCompanyIDs(for: auth.currentUser) {
            result = result.filter { order in
                if let cid = order.companyID { return scope.contains(cid) }
                return false
            }
        }
        return result.sorted { $0.issueDate > $1.issueDate }
    }

    /// Devis facturables : acceptés (le client a dit oui) et pas déjà convertis — même
    /// garde que le bouton "Convertir en facture" sur la fiche devis elle-même, pour que
    /// cette seconde entrée n'invente pas une règle différente. Exclut aussi les devis
    /// déjà transformés en commande : la facture doit alors venir de la commande, pas
    /// court-circuiter la traçabilité en repartant directement du devis.
    private var scopedInvoiceableQuotes: [Quote] {
        var result = quoteStore.quotes.filter {
            $0.status == .accepted && $0.convertedInvoiceNumber == nil && $0.convertedOrderNumber == nil
        }
        if let scope = auth.visibleInvoiceCompanyIDs(for: auth.currentUser) {
            result = result.filter { quote in
                if let cid = quote.companyID { return scope.contains(cid) }
                return false
            }
        }
        return result.sorted { $0.issueDate > $1.issueDate }
    }

    /// Acomptes candidats pour un solde : même règle de périmètre société que
    /// `InvoiceEditorView.linkableInvoices`, en excluant la facture source elle-même. Les
    /// acomptes dont le client correspond à celui de la facture source remontent en tête,
    /// puis tri antéchronologique (le plus récent en premier).
    private func candidateDeposits(for source: Invoice) -> [Invoice] {
        let scope = auth.visibleInvoiceCompanyIDs(for: auth.currentUser)
        let sourceBuyerName = source.buyer.name.trimmingCharacters(in: .whitespaces).lowercased()
        var result = store.invoices.filter { inv in
            // Même devise : le solde déduit la somme de leurs totaux TTC (BT-113).
            guard inv.type.isDeposit, inv.id != source.id, inv.currency == source.currency else { return false }
            if let scope = scope, let cid = inv.companyID { return scope.contains(cid) }
            if scope != nil && inv.companyID == nil { return false }
            return true
        }
        result.sort { a, b in
            let aMatch = !sourceBuyerName.isEmpty && a.buyer.name.trimmingCharacters(in: .whitespaces).lowercased() == sourceBuyerName
            let bMatch = !sourceBuyerName.isEmpty && b.buyer.name.trimmingCharacters(in: .whitespaces).lowercased() == sourceBuyerName
            if aMatch != bMatch { return aMatch }
            return a.issueDate > b.issueDate
        }
        return result
    }

    private func binding(for id: UUID) -> Binding<Invoice> {
        Binding(
            get: { store.invoices.first(where: { $0.id == id }) ?? Invoice(number: "", seller: store.myCompany, buyer: .init(name: "", street: "", postcode: "", city: "")) },
            set: { newValue in
                store.upsert(newValue)
            }
        )
    }

    private func defaultCompanyID() -> UUID? {
        let visible = auth.visibleSocieties(for: auth.currentUser)
        if visible.count == 1 { return visible.first?.id }
        if let preferred = auth.societyEntry(forID: auth.currentUser?.defaultSellerEntryID),
           visible.contains(where: { $0.id == preferred.id }) {
            return preferred.id
        }
        return visible.first?.id
    }

    private func applyAdvancedFilter(_ invoices: [Invoice], field: InvoiceFilterField, value: String) -> [Invoice] {
        let raw = value.trimmingCharacters(in: .whitespaces)
        let v = raw.lowercased()
        guard field != .none, !v.isEmpty else { return invoices }
        let df = DateFormatter()
        df.locale = Locale(identifier: "fr_FR_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        func parseDate(_ s: String) -> Date? {
            if let d = df.date(from: s) { return d }
            df.dateFormat = "dd/MM/yyyy"
            return df.date(from: s)
        }
        switch field {
        case .number:
            return invoices.filter { $0.number.lowercased().contains(v) }
        case .buyerName:
            return invoices.filter { $0.buyer.name.lowercased().contains(v) }
        case .buyerSiren:
            return invoices.filter { ($0.buyer.siren ?? "").lowercased().contains(v) }
        case .buyerVat:
            return invoices.filter { ($0.buyer.vatNumber ?? "").lowercased().contains(v) }
        case .sellerName:
            return invoices.filter { $0.seller.name.lowercased().contains(v) }
        case .sellerSiren:
            return invoices.filter { ($0.seller.siren ?? "").lowercased().contains(v) }
        case .amountMin:
            if let min = Double(v.replacingOccurrences(of: ",", with: ".")) {
                return invoices.filter { $0.grandTotal >= min }
            }
            return invoices
        case .amountMax:
            if let max = Double(v.replacingOccurrences(of: ",", with: ".")) {
                return invoices.filter { $0.grandTotal <= max }
            }
            return invoices
        case .issueDateFrom:
            if let d = parseDate(raw) { return invoices.filter { $0.issueDate >= d } }
            return invoices
        case .issueDateTo:
            if let d = parseDate(raw) { return invoices.filter { $0.issueDate <= d } }
            return invoices
        case .dueDateFrom:
            if let d = parseDate(raw) { return invoices.filter { $0.dueDate >= d } }
            return invoices
        case .purchaseOrderRef:
            return invoices.filter { ($0.purchaseOrderRef ?? "").lowercased().contains(v) }
        case .contractRef:
            return invoices.filter { ($0.contractRef ?? "").lowercased().contains(v) }
        case .precedingInvoiceRef:
            return invoices.filter { ($0.precedingInvoiceRef ?? "").lowercased().contains(v) }
        case .status:
            return invoices.filter { $0.status.rawValue.lowercased() == v || $0.status.label.lowercased().contains(v) }
        case .type:
            return invoices.filter { $0.type.label.lowercased().contains(v) || ($0.type.isCreditNote ? "avoir" : "facture").contains(v) }
        case .none:
            return invoices
        }
    }

    @ViewBuilder
    private func advancedFilterRow(field: Binding<InvoiceFilterField>, value: Binding<String>, index: Int) -> some View {
        let isDate = {
            switch field.wrappedValue {
            case .issueDateFrom, .issueDateTo, .dueDateFrom: return true
            default: return false
            }
        }()
        let isAmount = (field.wrappedValue == .amountMin || field.wrappedValue == .amountMax)
        HStack(spacing: 8) {
            Picker("", selection: field) {
                ForEach(InvoiceFilterField.allCases, id: \.self) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .labelsHidden()
            .frame(width: 170)
            if isDate {
                let dateBinding = Binding<Date>(
                    get: {
                        let df = DateFormatter()
                        df.locale = Locale(identifier: "fr_FR_POSIX")
                        df.dateFormat = "yyyy-MM-dd"
                        if let d = df.date(from: value.wrappedValue) { return d }
                        df.dateFormat = "dd/MM/yyyy"
                        return df.date(from: value.wrappedValue) ?? Date()
                    },
                    set: { newDate in
                        let df = DateFormatter()
                        df.locale = Locale(identifier: "fr_FR_POSIX")
                        df.dateFormat = "yyyy-MM-dd"
                        value.wrappedValue = df.string(from: newDate)
                    }
                )
                DatePicker("", selection: dateBinding, displayedComponents: .date)
                    .labelsHidden()
                    .frame(width: 130)
            } else if isAmount {
                TextField("Valeur", text: value)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 130)
            } else {
                TextField("Recherche", text: value)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
            }
            if !value.wrappedValue.isEmpty {
                Button { value.wrappedValue = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var activeAdvancedFilterCount: Int {
        var n = 0
        if advField1 != .none && !advValue1.isEmpty { n += 1 }
        if advField2 != .none && !advValue2.isEmpty { n += 1 }
        if advField3 != .none && !advValue3.isEmpty { n += 1 }
        return n
    }

    private func resetAdvancedFilters() {
        advField1 = .none; advValue1 = ""
        advField2 = .none; advValue2 = ""
        advField3 = .none; advValue3 = ""
    }
}

struct OptionalFieldsSection: View {
    @Binding var fields: [OptionalField]
    let location: OptionalFieldLocation
    var locked: Bool = false
    /// Repliée par défaut en saisie (`locked` == false, pour ne pas encombrer un formulaire
    /// en cours de remplissage) ; forcée dépliée en lecture seule pour que le contenu déjà
    /// saisi reste consultable sans clic supplémentaire.
    @State private var isExpanded = false

    private var templates: [OptionalFieldTemplate] { OptionalFieldCatalogue.templates(for: location) }
    private var title: String { location == .header ? "Champs optionnels (entete)" : "Champs optionnels (ligne)" }

    private func labelFor(tagName: String) -> String {
        if let tpl = OptionalFieldCatalogue.template(forTag: tagName, location: location) {
            return "\(tpl.bt) - \(tpl.label)"
        }
        return tagName
    }

    private func helpFor(tagName: String) -> String {
        OptionalFieldCatalogue.help(forTag: tagName, location: location)
    }

    var body: some View {
        DisclosureGroup(isExpanded: Binding(
            get: { isExpanded || locked },
            set: { isExpanded = $0 }
        )) {
            VStack(alignment: .leading, spacing: 6) {
                if fields.isEmpty {
                    Text("Aucun champ optionnel.").foregroundStyle(.secondary)
                }
                ForEach($fields) { $field in
                    fieldRow(field: $field)
                }
                Menu {
                    ForEach(templates) { tpl in
                        Button {
                            fields.append(OptionalField(tagName: tpl.tagName, value: ""))
                        } label: {
                            Label("\(tpl.bt) - \(tpl.label)", systemImage: "tag")
                        }
                    }
                    Divider()
                    Button {
                        fields.append(OptionalField(tagName: "", value: ""))
                    } label: {
                        Label("Balise personnalisee...", systemImage: "pencil")
                    }
                } label: {
                    Label("Ajouter un champ", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .disabled(locked)
            }
            .padding(.top, 4)
        } label: {
            Text(title)
        }
        .font(.caption)
        .disabled(locked)
    }

    @ViewBuilder
    private func fieldRow(field: Binding<OptionalField>) -> some View {
        let tagName = field.tagName.wrappedValue
        let isCustom = tagName.isEmpty || OptionalFieldCatalogue.template(forTag: tagName, location: location) == nil
        HStack(spacing: 4) {
            Menu {
                ForEach(templates) { tpl in
                    Button {
                        field.tagName.wrappedValue = tpl.tagName
                    } label: {
                        Text("\(tpl.bt) - \(tpl.label)")
                    }
                }
                Divider()
                Button {
                    field.tagName.wrappedValue = ""
                } label: {
                    Text("Personnalisee...")
                }
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "tag")
                    Text(tagName.isEmpty ? "Choisir une balise..." : labelFor(tagName: tagName))
                        .lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .frame(width: 320, alignment: .leading)
            }
            if isCustom {
                let placeholder = OptionalFieldCatalogue.template(forTag: tagName, location: location)?.label ?? "ram:..."
                TextField(placeholder, text: field.tagName).frame(width: 200)
            }
            TextField("Valeur", text: field.value).frame(maxWidth: .infinity)
            InfoBadge(text: helpFor(tagName: tagName))
            Button {
                if let idx = fields.firstIndex(where: { $0.id == field.wrappedValue.id }) {
                    fields.remove(at: idx)
                }
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
        }
    }
}

struct InvoiceEditorView: View {
    @Binding var invoice: Invoice
    @EnvironmentObject var store: InvoiceStore
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var superPDPSettings: SuperPDPSettings
    @EnvironmentObject var invoiceStatusStore: InvoiceStatusStore
    @EnvironmentObject var smtpSettings: SMTPSettings
    @EnvironmentObject var emailTemplateStore: EmailTemplateStore
    @EnvironmentObject var paymentTermsStore: PaymentTermsPresetStore
    @EnvironmentObject var actionLabelStore: AuditActionLabelStore
    @State private var sendingInvoiceEmail = false
    @State private var showResendEmailConfirm = false
    @State private var invoiceEmailMessage: String?
    @State private var exportError: String?
    @State private var exportedURL: URL?
    @State private var duplicatedNumber: String?
    @State private var validation: FacturXValidationResult?
    @State private var showValidation = false
    @State private var isManuallyLocked = false
    @State private var showUnlockAlert = false
    @State private var adminConfirmedEdit = false
    @State private var showAdminEditConfirm = false
    @State private var showPrecedingInvoicePicker = false
    @State private var showMandatoryDetails = false
    @State private var superPDPSubmitting = false
    @State private var superPDPMessage: String?
    @State private var superPDPSubmission: SuperPDPInvoiceSubmission?
    @State private var pdpDownloadedURL: URL?
    @State private var lastSentPDPStatusCode: String?
    @State private var showStatusJournal = false
    @State private var showLegalMentions = false
    @State private var showInvoicePreview = false
    @State private var previewPDFData: Data?
    @State private var showPDPEvents = false
    @State private var pdpEvents: [SuperPDPInvoiceEvent] = []
    @State private var pdpEventsLoading = false
    @State private var pdpDownloading = false
    @State private var pdpValidating = false
    @State private var pdpValidationReport: SuperPDPValidationReport?
    @State private var showPDPValidationPanel = false
    @State private var sendingReminder = false
    @State private var reminderMessage: String?
    @State private var fetchingECBRate = false
    /// Échec du bouton « Taux BCE » (devise non cotée, aucun cours, service injoignable).
    @State private var ecbRateMessage: String?
    /// « Personnalisé » choisi dans le menu Conditions de paiement (voir `PaymentTermsPresetSelection`).
    @State private var paymentTermsSelection = PaymentTermsPresetSelection()
    private var isLocked: Bool { invoice.status.locksInvoice || isManuallyLocked }
    private var statusLocked: Bool { invoice.status.locksInvoice }
    private var isAdmin: Bool { auth.currentUser?.isAdmin ?? false }
    /// Un admin peut modifier une facture verrouillée par son statut (payée,
    /// acceptée, annulée), mais seulement après confirmation explicite — jamais
    /// en silence, pour éviter une incohérence comptable accidentelle.
    private var fieldLocked: Bool {
        guard isLocked else { return false }
        if statusLocked { return !(isAdmin && adminConfirmedEdit) }
        return !isAdmin
    }
    private var sellerLogo: Data? {
        guard let cid = invoice.companyID else { return nil }
        return PartyDirectory.shared.entries.first(where: { $0.id == cid })?.logoData
    }

    private var hasMandatoryWarnings: Bool {
        let s = invoice.seller
        let b = invoice.buyer
        // BR-FR-10 : le SIREN de l'émetteur est exigé même avec un identifiant électronique.
        let sellerOk = !s.name.trimmingCharacters(in: .whitespaces).isEmpty
            && !s.country.trimmingCharacters(in: .whitespaces).isEmpty
            && SireneValidator.isWellFormedSiren(s.siren)
        let buyerOk = !b.name.trimmingCharacters(in: .whitespaces).isEmpty
            && !b.country.trimmingCharacters(in: .whitespaces).isEmpty
            && ((b.siren ?? "").trimmingCharacters(in: .whitespaces).count >= 9
                || (b.endpointID ?? "").trimmingCharacters(in: .whitespaces).count >= 9)
        let headerOk = !invoice.number.trimmingCharacters(in: .whitespaces).isEmpty
            && !invoice.currency.trimmingCharacters(in: .whitespaces).isEmpty
        let linesOk = invoice.lines.allSatisfy {
            !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && $0.quantity > 0 && $0.unitPrice >= 0
        }
        return !(sellerOk && buyerOk && headerOk && linesOk)
    }

    private var errorRuleIDs: Set<String> {
        guard let v = validation, showValidation else { return [] }
        return Set(v.businessRules.filter { $0.severity == .error }.map { $0.ruleId })
    }

    /// Préréglage de conditions de paiement affiché dans le menu, résolu dans la liste de la
    /// société de la facture (`invoice.companyID`) — celle personnalisée dans Réglages >
    /// Tables, pas le seul réglage global. `nil` = « Personnalisé » : choisi dans le menu,
    /// texte propre à la facture, ou échéance différente de celle que calcule le préréglage.
    private var activePaymentTermsPreset: PaymentTermsPreset? {
        paymentTermsSelection.activePreset(for: invoice, in: paymentTermsStore)
    }

    /// `nil` = « Personnalisé » ; sinon l'id du préréglage affiché. Choisir un préréglage
    /// réécrit le texte et recalcule l'échéance (BT-9) à partir de la date de facture ; le
    /// champ Échéance se grise alors (voir `dueDateIsComputedFromPreset`). Choisir
    /// « Personnalisé » garde texte et échéance, qui deviennent modifiables.
    private var paymentTermsPresetIDBinding: Binding<String?> {
        Binding(
            get: { activePaymentTermsPreset?.id },
            set: { newID in
                if let updated = paymentTermsSelection.select(newID, for: invoice, in: paymentTermsStore) {
                    invoice = updated
                }
            }
        )
    }

    /// Texte libre des conditions (BT-20), affiché en « Personnalisé ». Chaque frappe retient
    /// ce mode : sinon le menu repasserait sur un préréglage dès que la saisie passe par son
    /// texte (« Paiement à 30 jours » avant « … fin de mois »), et le champ disparaîtrait.
    private var customPaymentTermsBinding: Binding<String> {
        Binding(
            get: { invoice.paymentTerms ?? "" },
            set: { newText in
                paymentTermsSelection.keepCustom()
                invoice.paymentTerms = newText
            }
        )
    }

    /// Échéance (BT-9), modifiable en « Personnalisé » ou avec un préréglage sans règle. Une
    /// saisie en « Personnalisé » retient ce mode : sinon le champ se griserait en pleine
    /// saisie quand la date passe par celle que calcule le préréglage.
    private var dueDateBinding: Binding<Date> {
        Binding(
            get: { invoice.dueDate },
            set: { newDate in
                guard newDate != invoice.dueDate else { return }
                paymentTermsSelection.keepCustomIfShown(for: invoice, in: paymentTermsStore)
                invoice.dueDate = newDate
            }
        )
    }

    /// Date facture (BT-2). Quand l'utilisateur la change, l'échéance (BT-9) suit la règle du
    /// préréglage de conditions de paiement actif, dans la même écriture. Le recalcul vit dans
    /// ce setter, appelé seulement par une saisie dans le DatePicker, et non dans un
    /// `onChange(of: invoice.issueDate)` qui se déclenchait aussi au changement de facture
    /// sélectionnée. Le préréglage actif est lu avant l'écriture : après, l'échéance ne
    /// correspondrait plus à la nouvelle date et le menu afficherait « Personnalisé ». Pas de
    /// recalcul sur une facture verrouillée, par prudence : `.lockable` tient déjà la souris
    /// et le clavier hors du DatePicker.
    private var issueDateBinding: Binding<Date> {
        Binding(
            get: { invoice.issueDate },
            set: { newDate in
                guard newDate != invoice.issueDate else { return }
                var updated = invoice
                updated.issueDate = newDate
                if !fieldLocked, let preset = activePaymentTermsPreset {
                    updated.dueDate = preset.dueRule.dueDate(from: newDate)
                }
                invoice = updated
            }
        )
    }

    /// Devise (BT-5). `setCurrency(_:)` efface le taux de change, qui ne vaut que pour la devise
    /// pour laquelle il a été saisi.
    private var currencyBinding: Binding<String> {
        Binding(
            get: { invoice.currency },
            set: { code in
                guard code != invoice.currency else { return }
                invoice.setCurrency(code)
                ecbRateMessage = nil
            }
        )
    }

    /// Taux de change saisi à la main : `setExchangeRate(_:)` efface le jour du cours BCE, que le
    /// PDF n'imprime donc plus pour un taux modifié.
    private var exchangeRateBinding: Binding<Double?> {
        Binding(
            get: { invoice.exchangeRate },
            set: { rate in
                guard rate != invoice.exchangeRate else { return }
                invoice.setExchangeRate(rate)
                ecbRateMessage = nil
            }
        )
    }

    /// Hors euro : le champ « Taux de change » (BR-FR-CO-12) s'affiche.
    private var isForeignCurrency: Bool {
        let code = invoice.currency.trimmingCharacters(in: .whitespaces)
        return !code.isEmpty && code != "EUR"
    }

    /// Bouton « Taux BCE » : cours de référence de la BCE à la date de facture, ceux de la table
    /// des parités quotidiennes de la Banque de France. La réponse n'est appliquée que si la
    /// devise et la date de facture n'ont pas changé pendant l'appel.
    private func fetchECBRate() {
        let currency = invoice.currency
        let issueDate = invoice.issueDate
        fetchingECBRate = true
        ecbRateMessage = nil
        Task {
            defer { fetchingECBRate = false }
            do {
                let reference = try await ECBReferenceRateService().referenceRate(currency: currency, on: issueDate)
                guard invoice.currency == currency, invoice.issueDate == issueDate else { return }
                invoice.applyReferenceRate(reference)
            } catch {
                ecbRateMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// Vrai si l'échéance est celle que calcule le préréglage affiché (jours nets /
    /// fin de mois + jours) — le champ Échéance se grise alors, pour éviter une
    /// saisie manuelle écrasée au prochain changement de date de facture. Un
    /// préréglage sans règle (ex. "Comptant") ou le mode Personnalisé laissent
    /// le champ modifiable.
    private var dueDateIsComputedFromPreset: Bool {
        activePaymentTermsPreset?.dueRule.computesDueDate ?? false
    }

    private func fieldHighlight<V: View>(_ view: V, forRuleIDs ids: [String]) -> some View {
        view.overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.red, lineWidth: ids.contains(where: { errorRuleIDs.contains($0) }) ? 1.5 : 0)
        )
    }

    /// Règles qui entourent de rouge une partie : les siennes, plus BR-FR-23 quand c'est son
    /// adresse électronique qui est refusée (la règle vise l'émetteur comme le destinataire).
    private func partyRuleIDs(_ ids: [String], _ party: InvoiceParty) -> [String] {
        party.hasAdmittedElectronicAddress ? ids : ids + ["BR-FR-23"]
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Bandeau d'informations (fixe, lecture seule)
            HStack(spacing: 10) {
                Text(invoice.number).font(.title2.bold())
                Text(invoice.issueDate, format: .dateTime.day().month().year())
                    .font(.callout).foregroundStyle(.secondary)
                Text(String(format: "%.2f %@ HT", invoice.lineTotal, invoice.currency))
                    .font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Image(systemName: invoice.status.systemImage)
                    Text(invoice.status.label)
                }
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Color(hex: invoice.status.hexColor)))
                if invoice.isOverdue {
                    Label("En retard (\(invoice.overdueDays) j)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.red))
                }
                if superPDPSettings.credentials(for: invoice.companyID).usePDP {
                    Button {
                        // Rafraîchit le statut (auparavant un bouton "Statut PDP" séparé
                        // dans la barre d'action) et ouvre l'historique en un seul clic :
                        // consulter l'historique sans le statut à jour n'avait pas grand
                        // sens, et inversement.
                        refreshSuperPDPStatus()
                        fetchPDPEvents()
                    } label: {
                        if superPDPSubmitting {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.callout)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(superPDPSubmitting
                              || ((invoice.superPDPRemoteID ?? superPDPSubmission?.remoteID ?? "").isEmpty)
                              || !superPDPSettings.credentials(for: invoice.companyID).isConfigured)
                    .help("Rafraîchir le statut et voir l'historique des événements SUPER PDP")
                }
                if isLocked {
                    Label(statusLocked ? "Verrouillée (statut)" : "Lecture seule", systemImage: "lock.fill")
                        .font(.caption.bold())
                        .foregroundStyle(statusLocked ? Color(hex: invoice.status.hexColor) : .secondary)
                        .padding(.horizontal, 6)
                        .overlay(Capsule().stroke(.secondary, lineWidth: 0.5))
                    if isAdmin && statusLocked && adminConfirmedEdit {
                        Label("Modification admin activée", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2.bold()).foregroundStyle(.red)
                    }
                }
                Spacer()
                HStack(spacing: 4) {
                    Text(invoice.seller.name.trimmingCharacters(in: .whitespaces).isEmpty ? "Émetteur non renseigné" : invoice.seller.name)
                    Image(systemName: "arrow.right").font(.caption2)
                    Text(invoice.buyer.name.trimmingCharacters(in: .whitespaces).isEmpty ? "Client non renseigné" : invoice.buyer.name)
                }
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .padding(.horizontal, 12).padding(.top, 12)
            Divider()

            // MARK: Barre d'actions (fixe), sous-groupée : cycle de vie · utilitaires · admin
            // Défile horizontalement plutôt que de recadrer les boutons si la fenêtre est étroite.
            ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                let configuredTransitions = invoiceStatusStore.override(for: invoice.status).transitionCodes.compactMap { InvoiceStatus(rawValue: $0) }
                HStack(spacing: 8) {
                    if isManuallyLocked && !statusLocked && !isAdmin {
                        Button { showUnlockAlert = true } label: {
                            Label("Modifier", systemImage: "lock.open")
                        }
                        .buttonStyle(ToolbarActionButtonStyle(tint: .gray))
                        .help("Repasser en édition (la facture n'est plus protégée)")
                    } else if statusLocked && isAdmin && !adminConfirmedEdit {
                        Button { showAdminEditConfirm = true } label: {
                            Label("Modifier quand même", systemImage: "exclamationmark.triangle")
                        }
                        .buttonStyle(ToolbarActionButtonStyle(tint: .red))
                        .help("Facture « \(invoice.status.label) » : la modifier peut créer une incohérence comptable ou avec SUPER PDP — confirmation requise")
                    } else if !isLocked && validation?.isValid == true {
                        Button { isManuallyLocked = true } label: {
                            Label("Verrouiller", systemImage: "lock")
                        }
                        .buttonStyle(ToolbarActionButtonStyle(tint: .gray))
                        .help("Protéger la facture validée en lecture seule")
                    }
                    if superPDPSettings.credentials(for: invoice.companyID).usePDP {
                            Button {
                                validatePDP()
                            } label: {
                                if pdpValidating {
                                    HStack(spacing: 4) {
                                        ProgressView().controlSize(.small)
                                        Text("Valider…")
                                    }
                                } else {
                                    Label("Valider PDP", systemImage: "checkmark.shield")
                                }
                            }
                            .buttonStyle(ToolbarActionButtonStyle(tint: .blue))
                            .disabled(pdpValidating || !superPDPSettings.credentials(for: invoice.companyID).isConfigured)
                            .help("Valider le Factur-X sur SUPER PDP avant dépôt")
                    } else {
                        Button("Valider") { runValidation() }
                            .buttonStyle(ToolbarActionButtonStyle(tint: .blue))
                            .disabled(fieldLocked)
                    }
                    ForEach(configuredTransitions, id: \.self) { s in
                        Button {
                            // « Envoyée / en cours » ne doit jamais être qu'une étiquette : passer
                            // ce statut sans réellement déposer laissait croire la facture
                            // transmise alors qu'elle ne l'était pas, tout en la verrouillant
                            // (statut verrouillant) — ce qui bloquait ensuite le vrai bouton
                            // "Super PDP" (dépôt), y compris pour un administrateur. Le seul
                            // chemin valide vers ce statut est donc le dépôt réel.
                            if s == .sent, superPDPSettings.credentials(for: invoice.companyID).usePDP,
                               (invoice.superPDPRemoteID ?? superPDPSubmission?.remoteID ?? "").isEmpty {
                                depositToSuperPDP()
                            } else {
                                setStatusChosenByUser(s)
                            }
                        } label: {
                            Label(s.label, systemImage: s.systemImage)
                        }
                        .buttonStyle(ToolbarActionButtonStyle(tint: Color(hex: s.hexColor)))
                        .help("Passer au statut « \(s.label) »")
                    }
                    if invoice.type.isInternalCreditNote {
                        Button("Exporter PDF") { exportPlainPDF() }
                            .buttonStyle(ToolbarActionButtonStyle(tint: .blue, filled: true))
                    } else if superPDPSettings.credentials(for: invoice.companyID).usePDP {
                        Button {
                            depositToSuperPDP()
                        } label: { Label("Super PDP", systemImage: "paperplane.fill") }
                            .buttonStyle(ToolbarActionButtonStyle(tint: .blue, filled: true))
                            // `fieldLocked` intègre déjà `statusLocked` (verrouillé sauf
                            // administrateur ayant confirmé "Modifier quand même") : le vérifier
                            // une seconde fois ici rendait ce bouton définitivement inaccessible
                            // dès que le statut verrouille la facture, même pour un administrateur
                            // — empêchant justement de corriger une facture restée bloquée à tort
                            // au statut « Transmise au PDP » sans dépôt réel.
                            .disabled(fieldLocked || superPDPSubmitting || !superPDPSettings.credentials(for: invoice.companyID).isConfigured || !isAdmin)
                            .help(isAdmin
                                  ? "Déposer la facture Factur-X sur SUPER PDP (Plateforme Agréée)"
                                  : "Réservé aux administrateurs : dépôt réglementaire sur SUPER PDP (Plateforme Agréée)")
                    }
                }

                Divider().frame(height: 20)

                HStack(spacing: 8) {
                    Menu {
                        Button {
                            previewPDFData = FacturXGenerator().generateVisiblePDF(invoice: invoice, logo: sellerLogo)
                            showInvoicePreview = true
                        } label: { Label("Visualiser", systemImage: "eye") }
                        Button { exportXML() } label: { Label("Exporter XML", systemImage: "chevron.left.forwardslash.chevron.right") }
                        Button { export() } label: { Label("Générer le Factur-X", systemImage: "doc.text.fill") }
                        Button {
                            let copy = store.duplicate(from: invoice)
                            store.upsert(copy)
                            duplicatedNumber = copy.number
                        } label: { Label("Dupliquer", systemImage: "plus.square.on.square") }
                        if superPDPSettings.credentials(for: invoice.companyID).usePDP {
                            Divider()
                            Button {
                                downloadPDPInvoice()
                            } label: { Label("Copie PDP", systemImage: "square.and.arrow.down") }
                                .disabled(pdpDownloading
                                          || ((invoice.superPDPRemoteID ?? superPDPSubmission?.remoteID ?? "").isEmpty)
                                          || !superPDPSettings.credentials(for: invoice.companyID).isConfigured)
                                .help("Télécharger la copie de la facture déposée sur SUPER PDP")
                        }
                    } label: {
                        Label("Autre action", systemImage: "ellipsis.circle")
                    }
                    .buttonStyle(ToolbarActionButtonStyle(tint: .gray))
                    .help("Visualiser, exporter XML, générer le Factur-X, dupliquer, copie PDP…")
                }

                if emailTemplateStore.globalEnabled {
                    Divider().frame(height: 20)
                    Button {
                        if invoice.lastEmailSentAt != nil {
                            showResendEmailConfirm = true
                        } else {
                            sendInvoiceEmail()
                        }
                    } label: {
                        if sendingInvoiceEmail {
                            HStack(spacing: 4) { ProgressView().controlSize(.small); Text("Envoi…") }
                        } else {
                            Label("Envoyer la facture", systemImage: EmailTemplateKind.invoiceSent.systemImage)
                        }
                    }
                    .buttonStyle(ToolbarActionButtonStyle(tint: .blue))
                    .disabled(sendingInvoiceEmail
                              || !emailTemplateStore.isSendEnabled(.invoiceSent, companyID: invoice.companyID)
                              || (invoice.buyer.contactEmail ?? "").isEmpty
                              || !smtpSettings.credentials(for: invoice.companyID).isConfigured)
                    .help(!emailTemplateStore.template(for: .invoiceSent, companyID: invoice.companyID).enabled
                          ? "Cet email est désactivé (Réglages > Application)"
                          : (invoice.buyer.contactEmail ?? "").isEmpty
                          ? "Aucune adresse email cliente renseignée"
                          : !smtpSettings.credentials(for: invoice.companyID).isConfigured
                          ? "Configurez l'envoi d'email (Réglages) pour envoyer la facture"
                          : "Envoyer la facture par email au client")
                    .confirmationDialog(
                        "Cette facture a déjà été envoyée le \(invoice.lastEmailSentAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "")",
                        isPresented: $showResendEmailConfirm, titleVisibility: .visible
                    ) {
                        Button("Envoyer quand même") { sendInvoiceEmail() }
                        Button("Annuler", role: .cancel) {}
                    }
                    if let sentAt = invoice.lastEmailSentAt {
                        Text("Envoyée le \(sentAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }

                    if invoice.isOverdue {
                        Divider().frame(height: 20)
                        HStack(spacing: 8) {
                            Menu {
                                ForEach(PaymentReminderLevel.allCases) { level in
                                    Button {
                                        sendReminder(level: level)
                                    } label: { Label(level.label, systemImage: level.systemImage) }
                                }
                            } label: {
                                if sendingReminder {
                                    HStack(spacing: 4) {
                                        ProgressView().controlSize(.small)
                                        Text("Envoi…")
                                    }
                                } else {
                                    Label("Relance", systemImage: "exclamationmark.bubble")
                                }
                            }
                            .buttonStyle(ToolbarActionButtonStyle(tint: .red))
                            .disabled(sendingReminder
                                      || !emailTemplateStore.isSendEnabled(.invoiceReminder, companyID: invoice.companyID)
                                      || (invoice.buyer.contactEmail ?? "").isEmpty
                                      || !smtpSettings.credentials(for: invoice.companyID).isConfigured)
                            .help(!emailTemplateStore.template(for: .invoiceReminder, companyID: invoice.companyID).enabled
                                  ? "Les relances sont désactivées (Réglages > Application)"
                                  : (invoice.buyer.contactEmail ?? "").isEmpty
                                  ? "Aucune adresse email cliente renseignée"
                                  : !smtpSettings.credentials(for: invoice.companyID).isConfigured
                                  ? "Configurez l'envoi d'email (Réglages) pour envoyer une relance"
                                  : "Envoyer un email de relance au client")
                        }
                    }
                }

                if isAdmin {
                    let forceable = InvoiceStatus.allCases.filter { $0 != invoice.status && !configuredTransitions.contains($0) }
                    if !forceable.isEmpty || superPDPSettings.credentials(for: invoice.companyID).usePDP {
                        Divider().frame(height: 20)
                        HStack(spacing: 8) {
                            if !forceable.isEmpty {
                                Menu {
                                    ForEach(forceable, id: \.self) { s in
                                        Button {
                                            setStatusChosenByUser(s)
                                        } label: {
                                            Label(s.label, systemImage: s.systemImage)
                                        }
                                    }
                                } label: {
                                    Label("Forcer", systemImage: "bolt.fill")
                                }
                                .buttonStyle(ToolbarActionButtonStyle(tint: .red))
                                .help("Administrateur : forcer un statut hors des transitions configurées")
                            }
                            if superPDPSettings.credentials(for: invoice.companyID).usePDP {
                                Button {
                                    notifyPDPStatusChange(to: invoice.status, force: true)
                                } label: {
                                    Label("Forcer renvoi", systemImage: "arrow.clockwise.circle")
                                }
                                .buttonStyle(ToolbarActionButtonStyle(tint: .red))
                                .disabled(((invoice.superPDPRemoteID ?? superPDPSubmission?.remoteID ?? "").isEmpty)
                                          || !superPDPSettings.credentials(for: invoice.companyID).isConfigured)
                                .help("Forcer le renvoi du statut actuel à SUPER PDP (admin)")
                            }
                        }
                    }
                }
                Spacer()
            }
            .padding(12)
            }
            Divider()
            if hasMandatoryWarnings || showValidation || showPDPValidationPanel || exportError != nil || exportedURL != nil || duplicatedNumber != nil || superPDPMessage != nil || superPDPSubmission != nil || reminderMessage != nil || invoiceEmailMessage != nil {
                VStack(alignment: .leading, spacing: 8) {
                if let err = exportError {
                    Text("Erreur : \(err)").foregroundStyle(.red).font(.caption)
                        .onChange(of: invoice.number) { _ in exportError = nil }
                        .onChange(of: invoice.seller.name) { _ in exportError = nil }
                        .onChange(of: invoice.buyer.name) { _ in exportError = nil }
                }
                if let url = exportedURL {
                    Text("Fichier généré : \(url.lastPathComponent)").font(.caption).foregroundStyle(.green)
                    Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        .onChange(of: invoice.number) { _ in exportedURL = nil }
                        .onChange(of: invoice.seller.name) { _ in exportedURL = nil }
                        .onChange(of: invoice.buyer.name) { _ in exportedURL = nil }
                }
                if let n = duplicatedNumber {
                    Text("Facture dupliquée : \(n) (disponible dans la liste)").font(.caption).foregroundStyle(.green)
                        .onChange(of: invoice.number) { _ in duplicatedNumber = nil }
                }
                if let m = reminderMessage {
                    Text(m).font(.caption).foregroundStyle(m.hasPrefix("Échec") ? .red : .green)
                        .onChange(of: invoice.number) { _ in reminderMessage = nil }
                }
                if let m = invoiceEmailMessage {
                    Text(m).font(.caption).foregroundStyle(m.hasPrefix("Échec") ? .red : .green)
                        .onChange(of: invoice.number) { _ in invoiceEmailMessage = nil }
                }
                if let m = superPDPMessage {
                    HStack(spacing: 6) {
                        if m.hasPrefix("Échec") {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                        } else if let sub = superPDPSubmission {
                            Image(systemName: sub.isProcessed ? "checkmark.seal.fill" : "hourglass")
                                .foregroundStyle(sub.isProcessed ? .green : .orange)
                            Image(systemName: sub.direction == .sent ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                                .foregroundStyle(sub.direction == .sent ? .blue : .teal)
                                .help(sub.direction == .sent ? "Envoyé à Super PDP" : "Reçu de Super PDP")
                        } else {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                        }
                        Text(m).font(.caption).foregroundStyle(m.hasPrefix("Échec") ? .red : .primary)
                        if let durl = pdpDownloadedURL {
                            Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([durl]) }
                                .buttonStyle(.borderless)
                                .font(.caption)
                        }
                    }
                    .onChange(of: invoice.number) { _ in superPDPMessage = nil; superPDPSubmission = nil; pdpDownloadedURL = nil }
                } else if let sub = superPDPSubmission {
                    HStack(spacing: 6) {
                        Image(systemName: sub.isProcessed ? "checkmark.seal.fill" : "hourglass")
                            .foregroundStyle(sub.isProcessed ? .green : .orange)
                        Image(systemName: sub.direction == .sent ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                            .foregroundStyle(sub.direction == .sent ? .blue : .teal)
                            .help(sub.direction == .sent ? "Envoyé à Super PDP" : "Reçu de Super PDP")
                        Text("SUPER PDP — id \(sub.remoteID ?? "?") · statut \(sub.status) · \(sub.direction == .sent ? "envoyé" : "reçu")").font(.caption)
                    }
                    .onChange(of: invoice.number) { _ in superPDPSubmission = nil }
                }

                if hasMandatoryWarnings {
                    DisclosureGroup(isExpanded: $showMandatoryDetails) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Émetteur et destinataire : nom, pays (code ISO 2 lettres), n° TVA si applicable. SIREN de l'émetteur (9 chiffres, BT-30) ; SIREN ou identifiant électronique du destinataire (BT-49).").font(.caption)
                            Text("Lignes : désignation non vide, quantité positive, prix unitaire, taux TVA, unité (code UN/ECE ex. C62, DAY, HUR).").font(.caption)
                            Text("En-tête : numéro de facture, date, échéance, devise (EUR ; hors euro, taux de change), mode de facturation (BT-23).").font(.caption)
                            Text("Mentions légales FR : frais de recouvrement (PMT), pénalités de retard (PMD), escompte (AAB) — pré-remplies, modifiables.").font(.caption)
                            Text("Paiement : IBAN et BIC si virement SEPA.").font(.caption)
                        }
                    } label: {
                        Label("Données obligatoires pour la conformité Factur-X", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                    }
                }

                if showValidation, let v = validation {
                    validationPanel(v)
                        .onChange(of: invoice.number) { _ in showValidation = false; validation = nil }
                }
                if showPDPValidationPanel, let report = pdpValidationReport {
                    pdpValidationPanel(report)
                        .onChange(of: invoice.number) { _ in showPDPValidationPanel = false; pdpValidationReport = nil }
                }
                }.padding(12)
                Divider()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                GroupBox("En-tête") {
                    VStack(alignment: .leading, spacing: 8) {
                        if !linkedCreditNotes.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.uturn.backward.circle.fill")
                                    .foregroundStyle(.orange)
                                Text(linkedCreditNotes.count == 1
                                     ? "Avoir lié : \(linkedCreditNotes[0].number)"
                                     : "Avoirs liés : \(linkedCreditNotes.map { $0.number }.joined(separator: ", "))")
                                    .font(.caption.bold())
                                Spacer()
                            }
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.12)))
                        }
                        HStack(alignment: .top, spacing: 24) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    LabeledContent {
                                        fieldHighlight(TextField("", text: $invoice.number).frame(width: 160), forRuleIDs: ["BR-02"])
                                    } label: {
                                        HStack(spacing: 3) {
                                            Text("Numéro *").foregroundColor(.red)
                                            InfoBadge(text: "BT-1 — Numéro unique de la facture. Obligatoire.")
                                        }
                                    }
                                    .help("Créée le \(invoice.createdAt.formatted(.dateTime.day().month().year().hour().minute())) (non modifiable).")
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 3) {
                                            Text("Type").font(.caption)
                                            InfoBadge(text: "BT-3 — Code type. 380 facture, 381 avoir, 384 rectificative.")
                                        }
                                        Picker("", selection: $invoice.type) {
                                            ForEach(InvoiceTypeCode.allCases, id: \.self) { Text($0.label).tag($0) }
                                        }.labelsHidden().frame(width: 260)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 3) {
                                            Text("Devise").font(.caption)
                                            InfoBadge(text: "BT-5 — Code de la devise de la facture (ram:InvoiceCurrencyCode). Hors euro, la facture porte aussi la TVA en euros (BT-111) et la devise de comptabilité EUR (BT-6), calculées avec le taux de change qui s'affiche alors sous la devise.")
                                        }
                                        fieldHighlight(NormRefPicker("", options: NormRefs.currencies, code: currencyBinding).labelsHidden().frame(width: 160), forRuleIDs: ["BR-05", "BR-CL-04"])
                                    }
                                }
                                if isForeignCurrency {
                                    exchangeRateRow
                                }
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 3) {
                                            Text("Date facture").font(.caption)
                                            InfoBadge(text: "BT-2 — Date d'émission de la facture. Obligatoire.")
                                        }
                                        DatePicker("", selection: issueDateBinding, displayedComponents: .date).labelsHidden()
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 3) {
                                            Text("Échéance").font(.caption)
                                            InfoBadge(text: "BT-9 — Date d'échéance du paiement. Un préréglage de conditions de paiement à délai (jours nets, fin de mois) la calcule à partir de la date de facture et grise le champ. Pour la saisir à la main, choisissez « Personnalisé » dans Conditions de paiement.")
                                        }
                                        fieldHighlight(DatePicker("", selection: dueDateBinding, displayedComponents: .date).labelsHidden()
                                            .disabled(fieldLocked || dueDateIsComputedFromPreset), forRuleIDs: ["BR-FR-CO-07"])
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 3) {
                                            Text("Cadre de facturation (BT-23)").font(.caption)
                                            InfoBadge(text: "BT-23 — Cadre de facturation. Lettre : B = biens, S = services, M = facture double (biens et services non accessoires l'un de l'autre). Chiffre : 1 = dépôt d'une facture, 2 = facture déjà payée (montant déjà payé = total TTC, échéance = date du paiement), 4 = facture définitive après acompte (interdit sur un acompte), 3/5/6 = sous-traitance ou cotraitance, 7 = TVA déjà collectée. Les cadres 8 (multi-vendeurs) et 9 (bidirectionnel) ne sont pas proposés : ils exigent des lignes de regroupement que l'application ne produit pas.")
                                        }
                                        fieldHighlight(Picker("", selection: $invoice.billingMode) {
                                            ForEach(BillingMode.selectableCases(current: invoice.billingMode), id: \.self) { Text($0.label).tag($0) }
                                        }.labelsHidden().frame(width: 320), forRuleIDs: ["BR-FR-CO-08", "BR-FR-CO-09", "BR-FR-MV-02", "BR-FR-BD-02"])
                                    }
                                    // Affiché seulement pour corriger une facture restée dans un profil
                                    // plus proposé (bloquée à l'export) : il disparaît une fois la
                                    // facture repassée en EN 16931 ou EXTENDED.
                                    if !invoice.profile.isIssuable {
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 3) {
                                                Text("Profil Factur-X (BT-24)").font(.caption)
                                                InfoBadge(text: "BT-24 — Profil Factur-X. Le profil \(invoice.profile.rawValue) n'est plus proposé : le XML produit par l'application a la structure du profil EN 16931, que le XSD des profils MINIMUM, BASIC WL et BASIC rejette. L'export reste bloqué (BR-PROFIL) tant que la facture n'est pas repassée en EN 16931 ou EXTENDED.")
                                            }
                                            fieldHighlight(Picker("", selection: $invoice.profile) {
                                                ForEach(FacturXProfile.selectableCases(current: invoice.profile), id: \.self) { Text($0.rawValue).tag($0) }
                                            }.labelsHidden().frame(width: 140), forRuleIDs: ["BR-PROFIL"])
                                        }
                                    }
                                }
                                HStack(spacing: 6) {
                                    Image(systemName: "banknote").foregroundStyle(.secondary)
                                    Text("Conditions de paiement :").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                                    Picker("", selection: paymentTermsPresetIDBinding) {
                                        ForEach(paymentTermsStore.list(for: invoice.companyID)) { preset in
                                            Text(preset.label).tag(Optional(preset.id))
                                        }
                                        Text("Personnalisé").tag(String?.none)
                                    }
                                    .labelsHidden()
                                    .frame(width: 180)
                                    .disabled(fieldLocked)
                                    .help("Un préréglage écrit son texte et recalcule l'échéance ci-dessus à partir de la date de facture. « Personnalisé » garde le texte actuel et rend le texte et l'échéance modifiables.")
                                    if paymentTermsPresetIDBinding.wrappedValue == nil {
                                        TextField("Ex. Paiement à 30 jours", text: customPaymentTermsBinding)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.callout)
                                            .frame(maxWidth: 260)
                                            .disabled(fieldLocked)
                                    } else {
                                        Text(invoice.paymentTerms ?? "")
                                            .font(.caption).foregroundStyle(.secondary)
                                            .frame(maxWidth: 260, alignment: .leading)
                                    }
                                    if (invoice.paymentTerms ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                                        Label("Non renseignées", systemImage: "exclamationmark.circle")
                                            .font(.caption).foregroundStyle(.orange)
                                    }
                                }
                                .padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity((invoice.paymentTerms ?? "").trimmingCharacters(in: .whitespaces).isEmpty ? 0.08 : 0)))
                                HStack(spacing: 3) {
                                    TextField("Référence commande (BT-13)", text: Binding($invoice.purchaseOrderRef, replacingNilWith: "")).frame(width: 260)
                                    InfoBadge(text: "BT-13 — Numéro de commande acheteur (BuyerOrderReferencedDocument/IssuerAssignedID). Distinct du BT-10 : c'est le numéro du bon de commande, pas la référence de routage.")
                                }
                                if invoice.type.requiresPrecedingInvoice || invoice.type == .internalCreditNote {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Facture antérieure référencée :").font(.caption.bold())
                                        HStack(spacing: 6) {
                                            Button {
                                                showPrecedingInvoicePicker = true
                                            } label: {
                                                HStack(spacing: 6) {
                                                    Image(systemName: "doc.text.magnifyingglass")
                                                    VStack(alignment: .leading, spacing: 1) {
                                                        let ref = (invoice.precedingInvoiceRef ?? "").trimmingCharacters(in: .whitespaces)
                                                        if !ref.isEmpty {
                                                            Text(ref).font(.caption.bold())
                                                            if let d = invoice.precedingInvoiceDate {
                                                                Text("Date : \(d, format: .dateTime.day().month().year())")
                                                                    .font(.caption2).foregroundStyle(.secondary)
                                                            } else {
                                                                Text("Date : non renseignée")
                                                                    .font(.caption2).foregroundStyle(.orange)
                                                            }
                                                        } else {
                                                            Text("Sélectionner une facture…").foregroundStyle(.secondary)
                                                        }
                                                    }
                                                    Spacer()
                                                    Image(systemName: "chevron.right")
                                                        .font(.caption2).foregroundStyle(.secondary)
                                                }
                                                .frame(maxWidth: 360, alignment: .leading)
                                            }
                                            .buttonStyle(.bordered)
                                            .overlay(RoundedRectangle(cornerRadius: 4)
                                                .stroke(Color.red, lineWidth: ["BR-FR-CO-04", "BR-FR-CO-05", "BT-25-SOLDE"].contains(where: { errorRuleIDs.contains($0) }) ? 1.5 : 0))
                                            if linkableInvoices.isEmpty {
                                                Text("Aucune facture disponible").font(.caption2).foregroundStyle(.secondary)
                                            }
                                            if (invoice.precedingInvoiceRef ?? "").trimmingCharacters(in: .whitespaces) != "" {
                                                Button {
                                                    invoice.precedingInvoiceRef = nil
                                                    invoice.precedingInvoiceDate = nil
                                                } label: {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .foregroundStyle(.secondary)
                                                }
                                                .buttonStyle(.borderless)
                                                .help("Effacer la référence")
                                            }
                                            InfoBadge(text: "BT-25/BT-26 — Numéro et date de la facture antérieure référencée. Sélection dans les factures du périmètre (hors avoirs).")
                                        }
                                    }
                                }
                                if invoice.type.isDeposit || invoice.type.isFinalSettlement || invoice.billingMode.isAlreadyPaid {
                                    HStack(spacing: 3) {
                                        Text(invoice.prepaidAmountLabel).font(.caption)
                                        fieldHighlight(TextField("0,00", value: $invoice.prepaidAmount, format: .decimalInput)
                                            .frame(width: 120).textFieldStyle(.roundedBorder), forRuleIDs: ["BR-FR-CO-09"])
                                        Text(invoice.currency).font(.caption).foregroundStyle(.secondary)
                                        InfoBadge(text: "BT-113 — Montant déjà payé (TotalPrepaidAmount), déduit du total TTC pour obtenir le net à payer : acomptes déjà réglés sur une facture de solde, ou totalité du total TTC en cadre « facture déjà payée » (B2/S2/M2).")
                                    }
                                }
                                companyScopePicker
                                OptionalFieldsSection(fields: $invoice.optionalFields, location: .header, locked: fieldLocked)
                                .font(.caption)
                            }
                            VStack(alignment: .trailing, spacing: 4) {
                                VStack(alignment: .trailing) {
                                ForEach(invoice.vatBreakdown) { item in
                                    row(item.label, item.amount)
                                }
                                row("Total TTC", invoice.grandTotal, bold: true)
                                if invoice.prepaidAmount > 0 {
                                    row(invoice.prepaidAmountLabel, -invoice.prepaidAmount)
                                    row("Net à payer", invoice.netToPay, bold: true)
                                }
                                if let taxInEuros = invoice.taxTotalInEuros {
                                    row("Total TVA en EUR", taxInEuros, currencyCode: "EUR")
                                }
                                }
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.clear))
                            }
                        }
                    }.padding(8)
                }.lockable(fieldLocked)

                HStack(alignment: .top, spacing: 12) {
                    GroupBox("Émetteur (vous)") {
                        PartySection(party: $invoice.seller, role: .seller, onPartyPicked: { p in
                            invoice.paymentIBAN = p.iban
                            invoice.paymentBIC = p.bic
                            if let pt = p.paymentTerms, !pt.isEmpty { invoice.paymentTerms = pt }
                        }, locked: fieldLocked, companyID: invoice.companyID)
                    }.lockable(fieldLocked)
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.red, lineWidth: partyRuleIDs(["BR-06", "BR-09", "BR-FR-10", "BR-FR-13"], invoice.seller).contains(where: { errorRuleIDs.contains($0) }) ? 1.5 : 0))
                    GroupBox("Destinataire") {
                        PartySection(party: $invoice.buyer, role: .buyer, locked: fieldLocked)
                    }.lockable(fieldLocked)
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.red, lineWidth: partyRuleIDs(["BR-07", "BR-11", "BR-FR-12", "BR-FR-32"], invoice.buyer).contains(where: { errorRuleIDs.contains($0) }) ? 1.5 : 0))
                }

                GroupBox("Lignes") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach($invoice.lines) { $line in
                            HStack {
                                HStack(spacing: 2) {
                                    fieldHighlight(TextField("Désignation *", text: $line.name).frame(minWidth: 220), forRuleIDs: ["BR-25"])
                                    InfoBadge(text: "BT-153 — Désignation de la ligne. Obligatoire.")
                                }
                                HStack(spacing: 2) {
                                    TextField("Commande", text: Binding($line.orderReference, replacingNilWith: ""))
                                        .frame(width: 140)
                                    InfoBadge(text: "Commande d'origine de la ligne — usage interne (rattachement aux commandes, exports), non transmise dans le XML Factur-X. Pour le numéro de ligne de commande normé, utilisez le champ optionnel BT-132.")
                                }
                                HStack(spacing: 2) {
                                    fieldHighlight(DoubleField("Qté", value: $line.quantity, format: .decimalInput), forRuleIDs: ["BT-129-POSITIVE"])
                                    InfoBadge(text: "BT-129 — Quantité facturée. Doit être positive, y compris sur un avoir : c'est le type de document (381) qui porte le sens du crédit.")
                                }
                                HStack(spacing: 2) {
                                    // Liseré sur la seule ligne dont le code est refusé (BR-CL-23).
                                    fieldHighlight(NormRefPicker("Unité", options: NormRefs.units, code: $line.unit).frame(width: 180),
                                                   forRuleIDs: line.hasAdmittedUnitCode ? [] : ["BR-CL-23"])
                                    InfoBadge(text: "BT-130 — Unité de mesure (code UN/ECE Rec 20 ou, pour un emballage, Rec 21).")
                                }
                                HStack(spacing: 2) {
                                    fieldHighlight(DoubleField("P.U. HT", value: $line.unitPrice, format: .decimalInput), forRuleIDs: ["BR-27"])
                                    InfoBadge(text: "BT-146 — Prix unitaire HT.")
                                }
                                HStack(spacing: 2) {
                                    fieldHighlight(VATRatePicker(rate: $line.editedVATRate), forRuleIDs: ["BR-FR-16"])
                                    InfoBadge(text: "BT-152 — Taux de TVA appliqué (%). À 0 %, la ligne est exonérée (catégorie E) : indiquez le motif d'exonération ci-dessous, ou choisissez une autre catégorie (BT-151).")
                                }
                                Text(String(format: "%.2f", line.lineTotal))
                                    .monospacedDigit().frame(width: 80, alignment: .trailing)
                                Button {
                                    // Différé au tick suivant : laisse le champ en cours d'édition
                                    // se valider (commit AppKit) avant que la ligne ne disparaisse,
                                    // sinon crash (Binding sur un index qui n'existe plus).
                                    DispatchQueue.main.async {
                                        invoice.lines.removeAll { $0.id == line.id }
                                    }
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                            }
                            // Catégorie/motif d'exonération : uniquement pertinents à taux 0 % (autoliquidation,
                            // export, exonération…) — masqués pour le cas standard afin de ne pas allonger
                            // la ligne pour rien.
                            if line.vatRate == 0 {
                                HStack(spacing: 8) {
                                    HStack(spacing: 2) {
                                        fieldHighlight(Picker("", selection: $line.vatCategory) {
                                            ForEach(VATCategory.zeroRateChoices(current: line.vatCategory), id: \.self) { cat in
                                                Text("\(cat.rawValue) — \(cat.label)").tag(cat)
                                            }
                                        }
                                        .labelsHidden()
                                        .frame(width: 210), forRuleIDs: line.vatCategory == .standard ? ["BR-S-05"] : [])
                                        InfoBadge(text: "BT-151 — Catégorie de TVA d'une ligne à 0 % : E = exonérée (par défaut), Z = taux zéro (rare en France), AE = autoliquidation, K = livraison intracommunautaire, G = exportation hors UE, O = hors champ.")
                                    }
                                    if line.vatCategory.requiresExemptionReason {
                                        HStack(spacing: 2) {
                                            // Liseré seulement sur un motif vide : la règle (BR-E-10…) vaut
                                            // pour la facture entière, pas pour cette ligne.
                                            fieldHighlight(TextField("Motif d'exonération (BT-120)", text: Binding($line.vatExemptionReason, replacingNilWith: ""))
                                                .frame(minWidth: 280),
                                                forRuleIDs: (line.vatExemptionReason ?? "").trimmingCharacters(in: .whitespaces).isEmpty
                                                    ? ["BR-E-10", "BR-AE-10", "BR-IC-10", "BR-G-10", "BR-O-10"] : [])
                                            InfoBadge(text: "BT-120 — Motif d'exonération, obligatoire pour cette catégorie de TVA.")
                                        }
                                    }
                                }
                                .padding(.leading, 4)
                            }
                            OptionalFieldsSection(fields: $line.optionalFields, location: .line, locked: fieldLocked)
                                .padding(.leading, 4)
                        }
                        Button {
                            invoice.lines.append(.blank(after: invoice.lines.last))
                        } label: { Label("Ajouter une ligne", systemImage: "plus") }
                    }.padding(8)
                }.lockable(fieldLocked)

                GroupBox {
                    DisclosureGroup(isExpanded: Binding(
                        // Forcée dépliée en lecture seule : les mentions légales et les notes
                        // libres sont des champs saisis, pas de la documentation statique —
                        // à consulter sans clic supplémentaire une fois la facture verrouillée.
                        // Dépliée aussi tant qu'une mention manque (BR-FR-05, bloquante) : le
                        // champ à compléter est sous les yeux.
                        get: { showLegalMentions || fieldLocked || errorRuleIDs.contains("BR-FR-05") },
                        set: { showLegalMentions = $0 }
                    )) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Frais de recouvrement (SubjectCode PMT) :").font(.caption.bold())
                            TextField("Indemnité forfaitaire pour frais de recouvrement", text: $invoice.legalNotePMT)
                            Text("Pénalités de retard (SubjectCode PMD) :").font(.caption.bold())
                            TextField("Taux d'intérêt des pénalités de retard", text: $invoice.legalNotePMD)
                            Text("Escompte (SubjectCode AAB) :").font(.caption.bold())
                            TextField("Escompte pour paiement anticipé", text: $invoice.legalNoteAAB)
                            TextField("Notes libres", text: Binding($invoice.notes, replacingNilWith: ""))
                        }.padding(.top, 4)
                    } label: {
                        Label("Mentions légales (FR) — cliquer pour déplier", systemImage: "text.scroll")
                            .font(.headline)
                    }
                }.lockable(fieldLocked)
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.red, lineWidth: errorRuleIDs.contains("BR-FR-05") ? 1.5 : 0))
                AttachmentsAndCommentSection(attachments: $invoice.attachments, internalComment: $invoice.internalComment, locked: fieldLocked)
                statusJournalSection
            }.padding()
        }
            .alert("Repasser en modification ?", isPresented: $showUnlockAlert) {
                Button("Annuler", role: .cancel) { }
                Button("Modifier", role: .destructive) { isManuallyLocked = false }
            } message: {
                Text("La facture était verrouillée en lecture seule après validation conforme. En la déverrouillant, vous reprenez l'édition ; pensez à valider de nouveau avant tout dépôt PDP.")
            }
            .alert("Modifier une facture « \(invoice.status.label) » ?", isPresented: $showAdminEditConfirm) {
                Button("Annuler", role: .cancel) { }
                Button("Modifier quand même", role: .destructive) {
                    adminConfirmedEdit = true
                    store.audit?.record(
                        actor: auth.currentUser?.username ?? "admin",
                        action: "invoice_edit_unlocked_by_admin",
                        target: invoice.number,
                        details: "statut au moment du déverrouillage : \(invoice.status.label)",
                        objectType: .invoice,
                        objectCode: invoice.number
                    )
                }
            } message: {
                Text("Cette facture a le statut « \(invoice.status.label) ». La modifier peut créer une incohérence comptable ou avec SUPER PDP (facture déjà réglée ou acceptée). Cette action est tracée dans le journal d'audit. Continuer ?")
            }
            .onChange(of: invoice.number) { _ in adminConfirmedEdit = false }
            .sheet(isPresented: $showPrecedingInvoicePicker) {
                InvoicePickerSheet(
                    invoices: linkableInvoices,
                    selectedID: invoice.precedingInvoiceRef.flatMap { ref in
                        linkableInvoices.first(where: { $0.number == ref })?.id
                    },
                    onPick: { inv in
                        invoice.precedingInvoiceRef = inv.number
                        invoice.precedingInvoiceDate = inv.issueDate
                        showPrecedingInvoicePicker = false
                    },
                    onClear: {
                        invoice.precedingInvoiceRef = nil
                        invoice.precedingInvoiceDate = nil
                        showPrecedingInvoicePicker = false
                    },
                    onCancel: { showPrecedingInvoicePicker = false }
                )
            }
            .sheet(isPresented: $showInvoicePreview) {
                InvoicePreviewSheet(pdfData: previewPDFData, title: "Facture \(invoice.number)")
            }
            .sheet(isPresented: $showPDPEvents) {
                SuperPDPEventsSheet(events: pdpEvents, loading: pdpEventsLoading)
            }
        }
    }

    /// Taux de change d'une facture hors euro (BR-FR-CO-12), saisi ou repris de la BCE. La TVA en
    /// euros qui en découle (BT-111) s'affiche dans le récapitulatif des totaux.
    private var exchangeRateRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                HStack(spacing: 3) {
                    Text("Taux de change *").font(.caption).foregroundColor(.red)
                    InfoBadge(text: "BR-FR-CO-12 — Une facture hors euro porte aussi la TVA en euros (BT-111) et la devise de comptabilité EUR (BT-6), sans quoi la PDP la rejette. Convention de la BCE : 1 EUR = taux unités de la devise. « Taux BCE » reprend le cours de référence de la BCE à la date de facture, celui de la table des parités quotidiennes de la Banque de France ; le taux reste modifiable (virgule ou point décimal). La TVA en euros est le total de TVA divisé par le taux, arrondi au centime.")
                }
                .fixedSize()
                Text("1 EUR =").font(.callout).fixedSize()
                // Virgule ou point décimal : avec le format numérique standard, « 1.1464 » collé
                // depuis le site de la BCE se lisait 1 en français (DecimalInputFormatStyle).
                fieldHighlight(TextField("taux", value: exchangeRateBinding, format: .decimalInput)
                    .frame(width: 110).textFieldStyle(.roundedBorder), forRuleIDs: ["BR-FR-CO-12"])
                Text(invoice.currency).font(.callout).fixedSize()
                Button {
                    fetchECBRate()
                } label: {
                    Label("Taux BCE", systemImage: "arrow.down.circle")
                }
                .fixedSize()
                .disabled(fieldLocked || fetchingECBRate
                          || !ECBReferenceRateService.quotedCurrencies.contains(invoice.currency.trimmingCharacters(in: .whitespaces)))
                .help("Cours de référence de la BCE (table de la Banque de France) du jour de la date de facture, ou du dernier jour ouvré avant.")
                if fetchingECBRate {
                    ProgressView().controlSize(.small)
                }
            }
            if let message = ecbRateMessage {
                Text(message).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let day = invoice.exchangeRateReferenceDate {
                Text("Cours de référence BCE du \(ExchangeRateText.day(day)) (table Banque de France)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// 320 pt : le plus long libellé de sous-total de TVA, « TVA 0% — Livraison intracommunautaire »,
    /// tient sur une ligne à côté de son montant (à 280 pt, il passait à la ligne).
    private func row(_ label: String, _ value: Double, bold: Bool = false, currencyCode: String? = nil) -> some View {
        HStack {
            Text(label).font(bold ? .body.bold() : .body)
            Spacer()
            Text(String(format: "%.2f %@", value, currencyCode ?? invoice.currency))
                .font(bold ? .body.bold() : .body)
                .monospacedDigit()
        }.frame(width: 320)
    }

    @ViewBuilder
    private var companyScopePicker: some View {
        let visible = auth.visibleSocieties(for: auth.currentUser)
        if visible.count > 1 {
            HStack(spacing: 3) {
                Picker("Société (périmètre)", selection: Binding(
                    get: { invoice.companyID ?? visible.first?.id ?? UUID() },
                    set: { invoice.companyID = $0 }
                )) {
                    ForEach(visible) { s in Text(s.displayName).tag(s.id) }
                }.frame(width: 320)
                InfoBadge(text: "Société émettrice du périmètre de l'utilisateur. La facture est rattachée à cette société.")
            }
        } else if visible.count == 1, let s = visible.first, invoice.companyID == nil {
            HStack(spacing: 3) {
                Text("Société : \(s.displayName)").font(.caption).foregroundStyle(.secondary)
                Button {
                    invoice.companyID = s.id
                } label: { Text("Rattacher") }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var linkedCreditNotes: [Invoice] {
        guard !invoice.number.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let scope = auth.visibleInvoiceCompanyIDs(for: auth.currentUser)
        return store.invoices.filter { inv in
            guard inv.type.isCreditNote
                && (inv.precedingInvoiceRef ?? "").trimmingCharacters(in: .whitespaces) == invoice.number.trimmingCharacters(in: .whitespaces) else { return false }
            if let scope = scope, let cid = inv.companyID { return scope.contains(cid) }
            if scope != nil && inv.companyID == nil { return false }
            return true
        }
    }

    private var linkableInvoices: [Invoice] {
        let scope = auth.visibleInvoiceCompanyIDs(for: auth.currentUser)
        var result = store.invoices.filter { inv in
            guard !inv.type.isCreditNote else { return false }
            guard inv.id != invoice.id else { return false }
            if let scope = scope, let cid = inv.companyID { return scope.contains(cid) }
            if scope != nil && inv.companyID == nil { return false }
            return true
        }
        result.sort { $0.issueDate > $1.issueDate }
        return result
    }

    private func export() {
        exportError = nil
        exportedURL = nil
        let preCheck = FacturXValidator().validate(invoice: invoice)
        if !preCheck.isValid {
            validation = preCheck
            showValidation = true
            exportError = "Validation échouée : \(preCheck.totalErrorCount) erreur(s). Corrigez avant de générer."
            return
        }
        do {
            store.upsert(invoice)
            let data = try FacturXGenerator().generate(invoice: invoice, logo: sellerLogo)
            let postCheck = FacturXValidator().validate(pdf: data)
            if !postCheck.isValid {
                validation = FacturXValidationResult(
                    isValid: false,
                    errors: postCheck.errors,
                    warnings: preCheck.warnings + postCheck.warnings,
                    businessRules: preCheck.businessRules
                )
                showValidation = true
                exportError = "La conformité du PDF généré a échoué : \(postCheck.errors.count) erreur(s)."
                return
            }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = "facture-\(invoice.number).pdf"
            if panel.runModal() == .OK, let url = panel.url {
                try data.write(to: url)
                exportedURL = url
                validation = FacturXValidationResult(
                    isValid: true,
                    warnings: preCheck.warnings + postCheck.warnings,
                    businessRules: preCheck.businessRules
                )
                showValidation = true
            }
        } catch {
            exportError = "\(error)"
        }
    }

    private func runValidation() {
        validation = FacturXValidator().validate(invoice: invoice)
        showValidation = true
    }

    private func depositToSuperPDP() {
        if let rid = (superPDPSubmission?.remoteID ?? invoice.superPDPRemoteID), !rid.isEmpty {
            superPDPMessage = "Facture déjà déposée sur SUPER PDP (id distant \(rid)). Ré-interrogez le statut plutôt que de redéposer."
            return
        }
        if invoice.status == .accepted || invoice.status == .partiallyPaid || invoice.status == .paid || invoice.status == .cancelled {
            superPDPMessage = "Dépôt refusé : la facture est déjà « \(invoice.status.label) ». Un dépôt n'est possible que depuis Brouillon / Validée / Transmise."
            return
        }
        superPDPSubmitting = true
        superPDPMessage = nil
        let preCheck = FacturXValidator().validate(invoice: invoice)
        if !preCheck.isValid {
            validation = preCheck
            showValidation = true
            superPDPMessage = "Validation échouée : \(preCheck.totalErrorCount) erreur(s). Corrigez avant de déposer."
            superPDPSubmitting = false
            return
        }
        Task {
            do {
                let facturx = try FacturXGenerator().generate(invoice: invoice, logo: sellerLogo)
                let service = SuperPDPService()
                let submission = try await service.submitInvoice(fileData: facturx, credentials: superPDPSettings.credentials(for: invoice.companyID))
                superPDPSubmission = SuperPDPInvoiceSubmission(
                    id: submission.id, remoteID: submission.remoteID, status: submission.status,
                    enInvoiceRef: submission.enInvoiceRef, submittedAt: submission.submittedAt,
                    lastCheckedAt: submission.lastCheckedAt, message: submission.message, direction: .sent
                )
                if let rid = submission.remoteID, !rid.isEmpty {
                    invoice.superPDPRemoteID = rid
                    if invoice.status == .issued || invoice.status == .draft {
                        invoice.status = .sent
                    }
                    store.upsert(invoice)
                }
                superPDPMessage = "↑ Envoyé à SUPER PDP — id distant \(submission.remoteID ?? "?") (statut : \(submission.status))."
                store.audit?.record(
                    actor: store.actorName,
                    action: "pdp_deposit_sent",
                    target: invoice.number,
                    details: "Dépôt facture sur SUPER PDP (envoyé) — id distant : \(submission.remoteID ?? "?")",
                    objectType: .invoice,
                    objectCode: invoice.number
                )
            } catch let e as SuperPDPError {
                superPDPMessage = "Échec dépôt SUPER PDP : \(e.localizedDescription)"
                store.audit?.record(
                    actor: store.actorName,
                    action: "pdp_deposit_error",
                    target: invoice.number,
                    details: "Échec dépôt SUPER PDP : \(e.localizedDescription)",
                    objectType: .invoice,
                    objectCode: invoice.number
                )
            } catch {
                superPDPMessage = "Échec dépôt SUPER PDP : \(error)"
                store.audit?.record(
                    actor: store.actorName,
                    action: "pdp_deposit_error",
                    target: invoice.number,
                    details: "Échec dépôt SUPER PDP : \(error)",
                    objectType: .invoice,
                    objectCode: invoice.number
                )
            }
            superPDPSubmitting = false
        }
    }

    private func refreshSuperPDPStatus() {
        guard let rid = (superPDPSubmission?.remoteID ?? invoice.superPDPRemoteID), !rid.isEmpty else { return }
        superPDPSubmitting = true
        let priorStatus = superPDPSubmission?.status
        Task {
            do {
                let service = SuperPDPService()
                let updated = try await service.getInvoiceStatus(remoteID: rid, credentials: superPDPSettings.credentials(for: invoice.companyID))
                superPDPSubmission = SuperPDPInvoiceSubmission(
                    id: updated.id, remoteID: updated.remoteID, status: updated.status,
                    enInvoiceRef: updated.enInvoiceRef, submittedAt: updated.submittedAt,
                    lastCheckedAt: updated.lastCheckedAt, message: updated.message, direction: .received
                )
                if let mapped = PDPStatusMapper.functionalTransition(for: updated.status) {
                    // Ne jamais rétrograder le statut local : on n'applique le statut PDP
                    // que s'il représente un avancement dans le cycle de vie (ou une annulation).
                    let isAdvance = mapped.lifecycleRank > invoice.status.lifecycleRank
                    let isCancellation = mapped == .cancelled && invoice.status != .cancelled && invoice.status != .paid
                    if (isAdvance || isCancellation) && mapped != invoice.status {
                        // Statut reçu : il ne repart pas vers SUPER PDP (voir `setStatusChosenByUser`).
                        invoice.status = mapped
                        store.upsert(invoice)
                        superPDPMessage = "⟲ Reçu de SUPER PDP : statut \(updated.status) — id distant \(rid). Statut facture mis à jour : \(mapped.label)."
                    } else if mapped == invoice.status {
                        superPDPMessage = "⟲ Reçu de SUPER PDP : statut \(updated.status)\(updated.enInvoiceRef.map { " (\($0))" } ?? "") — id distant \(rid)."
                    } else {
                        superPDPMessage = "⟲ Reçu de SUPER PDP : statut \(updated.status). Statut local « \(invoice.status.label) » conservé (supérieur dans le cycle de vie, pas de rétrogradation)."
                    }
                } else {
                    superPDPMessage = "⟲ Reçu de SUPER PDP : statut \(updated.status)\(updated.enInvoiceRef.map { " (\($0))" } ?? "") — id distant \(rid)."
                }
                store.audit?.record(
                    actor: store.actorName,
                    action: "pdp_status_received",
                    target: invoice.number,
                    details: "Statut SUPER PDP reçu : \(updated.status)\(priorStatus.map { " (avant : \($0))" } ?? "") — id distant : \(rid)",
                    objectType: .invoice,
                    objectCode: invoice.number
                )
            } catch {
                superPDPMessage = "Échec rafraîchissement : \(error.localizedDescription)"
                store.audit?.record(
                    actor: store.actorName,
                    action: "pdp_status_error",
                    target: invoice.number,
                    details: "Échec interrogation statut SUPER PDP : \(error.localizedDescription)",
                    objectType: .invoice,
                    objectCode: invoice.number
                )
            }
            superPDPSubmitting = false
        }
    }

    private func downloadPDPInvoice() {
        guard let rid = (superPDPSubmission?.remoteID ?? invoice.superPDPRemoteID), !rid.isEmpty else {
            superPDPMessage = "Aucun identifiant distant : la facture n'a pas encore été déposée sur SUPER PDP."
            return
        }
        guard superPDPSettings.credentials(for: invoice.companyID).isConfigured else {
            superPDPMessage = "Identifiants SUPER PDP non configurés."
            return
        }
        pdpDownloading = true
        superPDPMessage = nil
        Task {
            do {
                let service = SuperPDPService()
                let data = try await service.downloadInvoice(remoteID: rid, credentials: superPDPSettings.credentials(for: invoice.companyID))
                let panel = NSSavePanel()
                let isPDF = data.count > 4 && data[0] == 0x25 && data[1] == 0x50 && data[2] == 0x44 && data[3] == 0x46
                panel.allowedContentTypes = isPDF ? [.pdf] : [.xml]
                panel.nameFieldStringValue = isPDF ? "facture-\(invoice.number)-pdp.pdf" : "facture-\(invoice.number)-pdp.xml"
                if panel.runModal() == .OK, let url = panel.url {
                    try data.write(to: url)
                    superPDPMessage = "⤓ Copie déposée téléchargée : \(url.lastPathComponent)"
                    pdpDownloadedURL = url
                }
            } catch let e as SuperPDPError {
                superPDPMessage = "Échec téléchargement : \(e.localizedDescription)"
            } catch {
                superPDPMessage = "Échec téléchargement : \(error)"
            }
            pdpDownloading = false
        }
    }

    private func fetchPDPEvents() {
        guard let rid = (superPDPSubmission?.remoteID ?? invoice.superPDPRemoteID), !rid.isEmpty else {
            superPDPMessage = "Aucun identifiant distant : la facture n'a pas encore été déposée sur SUPER PDP."
            return
        }
        guard superPDPSettings.credentials(for: invoice.companyID).isConfigured else {
            superPDPMessage = "Identifiants SUPER PDP non configurés."
            return
        }
        pdpEventsLoading = true
        showPDPEvents = true
        Task {
            do {
                let service = SuperPDPService()
                let events = try await service.listInvoiceEvents(remoteID: rid, credentials: superPDPSettings.credentials(for: invoice.companyID))
                pdpEvents = events.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            } catch let e as SuperPDPError {
                superPDPMessage = "Échec historique : \(e.localizedDescription)"
                pdpEvents = []
            } catch {
                superPDPMessage = "Échec historique : \(error)"
                pdpEvents = []
            }
            pdpEventsLoading = false
        }
    }

    private func sendReminder(level: PaymentReminderLevel) {
        guard let recipient = invoice.buyer.contactEmail, !recipient.isEmpty else {
            reminderMessage = "Échec relance : aucune adresse email cliente renseignée."
            return
        }
        let credentials = smtpSettings.credentials(for: invoice.companyID)
        guard credentials.isConfigured else {
            reminderMessage = "Échec relance : envoi d'email non configuré (Réglages)."
            return
        }
        let email = PaymentReminderComposer.compose(level: level, for: invoice)
        sendingReminder = true
        reminderMessage = nil
        Task {
            do {
                try await SMTPService().send(to: recipient, subject: email.subject, body: email.body, credentials: credentials)
                reminderMessage = "Relance « \(level.label) » envoyée à \(recipient)."
            } catch {
                reminderMessage = "Échec relance : \(error.localizedDescription)"
            }
            sendingReminder = false
        }
    }

    private func sendInvoiceEmail() {
        guard let recipient = invoice.buyer.contactEmail, !recipient.isEmpty else {
            invoiceEmailMessage = "Échec envoi : aucune adresse email cliente renseignée."
            return
        }
        let credentials = smtpSettings.credentials(for: invoice.companyID)
        guard credentials.isConfigured else {
            invoiceEmailMessage = "Échec envoi : envoi d'email non configuré (Réglages)."
            return
        }
        let template = emailTemplateStore.template(for: .invoiceSent, companyID: invoice.companyID)
        let email = EmailComposer.compose(template: template, variables: [
            "numero": invoice.number,
            "client": invoice.buyer.name,
            "societe": invoice.seller.name,
            "montant": String(format: "%.2f %@", invoice.grandTotal, invoice.currency),
            "date": invoice.dueDate.formatted(.dateTime.day().month().year())
        ])
        sendingInvoiceEmail = true
        invoiceEmailMessage = nil
        Task {
            do {
                try await SMTPService().send(to: recipient, subject: email.subject, body: email.body, credentials: credentials)
                invoiceEmailMessage = "Facture envoyée à \(recipient)."
                invoice.lastEmailSentAt = Date()
            } catch {
                invoiceEmailMessage = "Échec envoi : \(error.localizedDescription)"
            }
            sendingInvoiceEmail = false
        }
    }

    private func validatePDP() {
        guard superPDPSettings.credentials(for: invoice.companyID).isConfigured else {
            superPDPMessage = "Identifiants SUPER PDP non configurés."
            return
        }
        pdpValidating = true
        superPDPMessage = nil
        showValidation = false
        validation = nil
        let preCheck = FacturXValidator().validate(invoice: invoice)
        if !preCheck.isValid {
            validation = preCheck
            showValidation = true
            superPDPMessage = "Validation locale échouée : \(preCheck.totalErrorCount) erreur(s). Corrigez avant la validation SUPER PDP."
            pdpValidating = false
            return
        }
        Task {
            do {
                let facturx = try FacturXGenerator().generate(invoice: invoice, logo: sellerLogo)
                // Relevées avec le fichier envoyé, avant l'attente réseau : « Ligne 2 (…) » nomme
                // la ligne validée, même si les lignes changent ensuite dans l'éditeur.
                let lineNames = invoice.lines.map(\.name)
                let service = SuperPDPService()
                var report = try await service.validateInvoice(fileData: facturx, credentials: superPDPSettings.credentials(for: invoice.companyID))
                report.lineNames = lineNames
                pdpValidationReport = report
                showPDPValidationPanel = true
                superPDPMessage = nil
            } catch let e as SuperPDPError {
                superPDPMessage = "Échec validation SUPER PDP : \(e.localizedDescription)"
            } catch {
                superPDPMessage = "Échec validation SUPER PDP : \(error)"
            }
            pdpValidating = false
        }
    }

    /// Statut choisi par l'utilisateur : bouton de transition ou menu admin « Forcer ». C'est le
    /// seul changement de statut qui part vers SUPER PDP et envoie l'alerte email. Un statut posé
    /// par le programme n'y repart jamais : reçu de SUPER PDP (bouton de rafraîchissement,
    /// `PDPPeriodicSyncEngine`), restauré d'une sauvegarde, ou « Envoyée » posé par le dépôt.
    /// D'où l'appel ici et non dans un `onChange(of: invoice.status)`, qui se déclenche aussi pour
    /// ces changements-là (un drapeau levé puis baissé dans le même bloc synchrone est déjà
    /// retombé quand l'action d'`onChange` s'exécute).
    private func setStatusChosenByUser(_ newStatus: InvoiceStatus) {
        guard newStatus != invoice.status else { return }
        invoice.status = newStatus
        notifyPDPStatusChange(to: newStatus)
        sendInvoiceStatusAlertIfNeeded(newStatus)
    }

    /// Alerte email best-effort au connecté, pour un statut choisi dans l'app (voir
    /// `setStatusChosenByUser`) — n'échoue jamais la mise à jour du statut.
    private func sendInvoiceStatusAlertIfNeeded(_ newStatus: InvoiceStatus) {
        let smtp = smtpSettings.credentials(for: invoice.companyID)
        guard smtp.alertsEnabled, smtp.alertOnInvoiceStatusChange, smtp.isConfigured,
              [InvoiceStatus.accepted, .disputed, .refused, .partiallyPaid, .paid, .cancelled].contains(newStatus),
              let recipient = auth.currentUser?.username else { return }
        let invoiceNumber = invoice.number
        let label = newStatus.label
        Task {
            try? await SMTPService().send(
                to: recipient,
                subject: "Facture \(invoiceNumber) — \(label)",
                body: "La facture \(invoiceNumber) est passée au statut « \(label) ».",
                credentials: smtp
            )
        }
    }

    private func notifyPDPStatusChange(to newStatus: InvoiceStatus, force: Bool = false) {
        guard let rid = (superPDPSubmission?.remoteID ?? invoice.superPDPRemoteID), !rid.isEmpty else { return }
        guard superPDPSettings.credentials(for: invoice.companyID).isConfigured else { return }
        // "200" (sent) est posé par le dépôt lui-même (voir depositToSuperPDP) — jamais
        // envoyé séparément comme événement de statut.
        guard let statusCode = invoiceStatusStore.override(for: newStatus).reformCode, statusCode != "200" else { return }
        let detailLabel = newStatus.label
        if !force, let last = lastSentPDPStatusCode, last == statusCode {
            superPDPMessage = "Statut « \(detailLabel) » déjà envoyé à SUPER PDP (code \(statusCode)). Évite l'envoi en double."
            return
        }
        superPDPSubmitting = true
        let invoiceRef = invoice
        Task {
            do {
                let service = SuperPDPService()
                var reported: [[String: Any]]? = nil
                if newStatus == .paid {
                    reported = invoiceRef.lines.compactMap { line -> [String: Any]? in
                        let amount = (line.quantity * line.unitPrice) * (1 + line.vatRate / 100)
                        return [
                            "amount": String(format: "%.2f", amount),
                            "currency_code": invoiceRef.currency,
                            "type_code": "MEN",
                            "value_percent": String(format: "%.1f", line.vatRate),
                            "date": Self.pdpDateString(invoiceRef.issueDate)
                        ]
                    }
                }
                try await service.sendInvoiceEvent(remoteID: rid, statusCode: statusCode, credentials: superPDPSettings.credentials(for: invoice.companyID), reportedData: reported)
                lastSentPDPStatusCode = statusCode
                superPDPSubmission = SuperPDPInvoiceSubmission(
                    id: UUID().uuidString, remoteID: rid, status: detailLabel,
                    enInvoiceRef: superPDPSubmission?.enInvoiceRef,
                    submittedAt: Date(), lastCheckedAt: Date(),
                    message: "Statut \(detailLabel) envoyé", direction: .sent
                )
                superPDPMessage = "↑ Envoyé à SUPER PDP : statut \(detailLabel) — id distant \(rid)."
                store.audit?.record(
                    actor: store.actorName,
                    action: "pdp_status_sent",
                    target: invoiceRef.number,
                    details: "Envoi statut \(detailLabel) à SUPER PDP (envoyé) — id distant : \(rid)",
                    objectType: .invoice,
                    objectCode: invoiceRef.number
                )
            } catch let e as SuperPDPError {
                superPDPMessage = "Échec envoi statut SUPER PDP : \(e.localizedDescription)"
                store.audit?.record(
                    actor: store.actorName,
                    action: "pdp_status_send_error",
                    target: invoiceRef.number,
                    details: "Échec envoi statut \(detailLabel) à SUPER PDP : \(e.localizedDescription)",
                    objectType: .invoice,
                    objectCode: invoiceRef.number
                )
            } catch {
                superPDPMessage = "Échec envoi statut SUPER PDP : \(error)"
                store.audit?.record(
                    actor: store.actorName,
                    action: "pdp_status_send_error",
                    target: invoiceRef.number,
                    details: "Échec envoi statut \(detailLabel) à SUPER PDP : \(error)",
                    objectType: .invoice,
                    objectCode: invoiceRef.number
                )
            }
            superPDPSubmitting = false
        }
    }

    private static func pdpDateString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.string(from: date)
    }

    private func exportPlainPDF() {
        exportError = nil
        exportedURL = nil
        store.upsert(invoice)
        let data = FacturXGenerator().generateVisiblePDF(invoice: invoice, logo: sellerLogo)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "avoir-interne-\(invoice.number).pdf"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try data.write(to: url)
                exportedURL = url
            } catch {
                exportError = "\(error)"
            }
        }
    }

    private func exportXML() {
        do {
            let xml = try CIIXMLGenerator().generate(invoice: invoice)
            let xmlString = String(data: xml, encoding: .utf8) ?? ""
            print("=== XML CII ===")
            print(xmlString)
            print("=== FIN XML ===")
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.xml]
            panel.nameFieldStringValue = "facture-\(invoice.number).xml"
            if panel.runModal() == .OK, let url = panel.url {
                try xml.write(to: url)
            }
        } catch {
            exportError = "\(error)"
        }
    }

    private var statusJournalSection: some View {
        let logs = auth.audit.entries.filter {
            $0.objectType == .invoice && ($0.objectCode ?? $0.target) == invoice.number
        }
        return DisclosureGroup(isExpanded: $showStatusJournal) {
            if logs.isEmpty {
                Text("Aucun événement enregistré pour cette facture.").font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(logs) { e in
                        HStack(alignment: .top, spacing: 8) {
                            Text(e.timestamp, format: .dateTime.day().month().year().hour().minute())
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                .frame(width: 130, alignment: .leading)
                            Text(e.actor).font(.caption).frame(width: 100, alignment: .leading)
                            if e.action == "status_change" {
                                Text("\(e.statusFrom ?? "?") → \(e.statusTo ?? "?")")
                                    .font(.caption.bold())
                                if !e.details.isEmpty {
                                    Text(e.details).font(.caption2).foregroundStyle(.secondary)
                                }
                            } else {
                                Text(actionLabelStore.label(for: e.action))
                                    .font(.caption)
                                if !e.details.isEmpty {
                                    Text(e.details).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                    }
                }
            }
        } label: {
            Label("Journal de la facture (\(logs.count))", systemImage: "list.bullet.clipboard")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
    }

    private func validationPanel(_ v: FacturXValidationResult) -> some View {
        let ruleErrors = v.businessRules.filter { $0.severity == .error }
        let ruleWarnings = v.businessRules.filter { $0.severity == .warning }
        return GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    if v.isValid {
                        Label("OK — contrôlé en local", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                    } else {
                        Label("Pré-vérification locale : \(ruleErrors.count) erreur(s)", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    }
                    Spacer()
                    Button { showValidation = false } label: {
                        Image(systemName: "xmark.circle")
                    }.buttonStyle(.plain)
                }
                Text("Contrôles internes, non exhaustifs — seule la validation SUPER PDP ci-dessous fait foi.")
                    .font(.caption2).foregroundStyle(.secondary)
                if !ruleErrors.isEmpty {
                    Text("Erreurs :").font(.caption.bold())
                    ForEach(ruleErrors) { br in
                        HStack(alignment: .top, spacing: 4) {
                            Text(br.ruleId)
                                .font(.caption.bold().monospaced())
                                .foregroundStyle(.red)
                                .frame(width: 96, alignment: .leading)
                            Text(br.message)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                if !ruleWarnings.isEmpty {
                    if !ruleErrors.isEmpty { Divider().padding(.vertical, 2) }
                    Text("Avertissements :").font(.caption.bold())
                    ForEach(ruleWarnings) { br in
                        HStack(alignment: .top, spacing: 4) {
                            Text(br.ruleId)
                                .font(.caption.bold().monospaced())
                                .foregroundStyle(.orange)
                                .frame(width: 96, alignment: .leading)
                            Text(br.message)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func pdpValidationPanel(_ report: SuperPDPValidationReport) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    if report.isValid {
                        Label("Validation SUPER PDP conforme", systemImage: "checkmark.shield.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Validation SUPER PDP non conforme — \(report.errors.count) erreur(s)", systemImage: "xmark.shield.fill")
                            .foregroundStyle(.red)
                    }
                    Spacer()
                    Button { showPDPValidationPanel = false } label: {
                        Image(systemName: "xmark.circle")
                    }.buttonStyle(.plain)
                }
                if !report.errors.isEmpty {
                    Text("Erreurs :").font(.caption.bold())
                    // Identité = position, pas le texte : un même message Schematron revient
                    // pour chaque élément fautif (« Ligne n » ne départage que des lignes
                    // différentes), et deux textes égaux auraient le même `id`.
                    // Le rapport est remplacé d'un bloc à chaque validation, sans état par ligne.
                    ForEach(Array(report.errorEntries.enumerated()), id: \.offset) { _, entry in
                        HStack(alignment: .top, spacing: 4) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.red)
                            Text(report.displayText(for: entry))
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                if !report.warnings.isEmpty {
                    if !report.errors.isEmpty { Divider().padding(.vertical, 2) }
                    Text("Avertissements :").font(.caption.bold())
                    ForEach(Array(report.warningEntries.enumerated()), id: \.offset) { _, entry in
                        HStack(alignment: .top, spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                            Text(report.displayText(for: entry))
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                // Le rapport dit non conforme mais n'a donné aucun détail structuré
                // (`subreports` absent ou vide côté SUPER PDP pour cette réponse précise) —
                // sans repli, l'utilisateur n'avait aucune piste (juste "0 erreur(s)").
                // On affiche au moins les champs bruts reçus, utiles pour diagnostiquer.
                if !report.isValid, report.errors.isEmpty, report.warnings.isEmpty {
                    Text("Le rapport SUPER PDP ne détaille pas la cause (aucun sous-rapport reçu). Champs bruts de la réponse :")
                        .font(.caption).foregroundStyle(.secondary)
                    if report.raw.isEmpty {
                        Text("(réponse vide)").font(.caption2).foregroundStyle(.secondary)
                    } else {
                        ForEach(report.raw.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            HStack(alignment: .top, spacing: 4) {
                                Text("\(key) :").font(.caption2.bold()).foregroundStyle(.secondary)
                                Text(value).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct InvoicePreviewSheet: View {
    let pdfData: Data?
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Aperçu — \(title)").font(.headline)
                Spacer()
                Button("Fermer") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(12)
            Divider()
            if let data = pdfData, let document = PDFDocument(data: data) {
                PDFKitView(document: document)
            } else {
                Text("Aucun aperçu disponible.").foregroundStyle(.secondary)
                Spacer()
            }
        }
        .frame(minWidth: 640, minHeight: 720)
    }
}

struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = document
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document !== document {
            nsView.document = document
        }
    }
}
