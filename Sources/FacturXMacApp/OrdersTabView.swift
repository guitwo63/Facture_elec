import SwiftUI
import FacturXCore

// MARK: - Extrait de FacturXMacApp.swift (découpage par domaine)

enum OrderFilterField: String, CaseIterable, Hashable {
    case none = "Aucun"
    case number = "N° commande"
    case buyerName = "Client"
    case buyerSiren = "SIREN client"
    case buyerVat = "TVA client"
    case sellerName = "Émetteur"
    case sellerSiren = "SIREN émetteur"
    case amountMin = "Montant TTC min"
    case amountMax = "Montant TTC max"
    case issueDateFrom = "Émise depuis"
    case issueDateTo = "Émise jusqu'à"
    case quotationRef = "Réf. devis"
    case contractRef = "Réf. contrat"
    case buyerReference = "Réf. acheteur"
    case status = "Statut"
}

struct QuoteToOrderSheet: View {
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
                Text("Créer une commande depuis un devis").font(.headline)
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
                    Text("Aucun devis accepté disponible à transformer en commande dans votre périmètre.")
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
                Button("Créer la commande") {
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

struct OrderPartySection: View {
    enum Role {
        case buyer, seller
        var title: String { self == .buyer ? "Acheteur" : "Société" }
        var defaultKind: DirectoryEntryKind { self == .buyer ? .client : .societe }
    }

    @Binding var party: InvoiceParty
    let role: Role
    var onPartyPicked: ((InvoiceParty) -> Void)? = nil
    var locked: Bool = false
    /// Société de la commande — voir `PartySection.companyID`.
    var companyID: UUID? = nil
    @EnvironmentObject var directory: PartyDirectory
    @State private var showPicker = false

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
                    Spacer()
                }
            }

            PartyEditorView(party: $party, isSociete: role == .seller, hideEmail: true, locked: locked, directory: directory, onPickContact: { updatePartyFromContact($0) }, onPickRouting: { updatePartyFromRouting($0) }, onPartyPicked: { p in onPartyPicked?(p) }, companyID: companyID)
        }
        .padding(8)
        .sheet(isPresented: $showPicker) {
            PartyPickerSheet(role: role == .buyer ? .buyer : .seller) { selected in
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

struct OrdersTabView: View {
    @EnvironmentObject var orderStore: OrderStore
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var statusStore: OrderStatusStore
    @EnvironmentObject var store: InvoiceStore
    @EnvironmentObject var quoteStore: QuoteStore
    @EnvironmentObject var moduleStore: ModuleStore
    @Binding var selectedID: UUID?
    @Binding var companyFilter: UUID?
    @State private var query = ""
    @State private var exportMessage: String?
    @State private var showScanImport = false
    @State private var showQuotePicker = false
    @State private var statusFilter: OrderStatus? = nil
    @State private var showAdvancedFilters = false
    @State private var advField1: OrderFilterField = .none
    @State private var advValue1 = ""
    @State private var advField2: OrderFilterField = .none
    @State private var advValue2 = ""
    @State private var advField3: OrderFilterField = .none
    @State private var advValue3 = ""

    var filteredOrders: [SalesOrder] {
        var result = orderStore.orders
        if let scope = auth.visibleOrderCompanyIDs(for: auth.currentUser) {
            result = result.filter { order in
                if let cid = order.companyID { return scope.contains(cid) }
                return false
            }
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
        return result.filter { order in
            order.number.lowercased().contains(q)
                || order.buyer.name.lowercased().contains(q)
                || (order.buyer.siren ?? "").lowercased().contains(q)
                || order.seller.name.lowercased().contains(q)
        }
    }

    private func applyAdvancedFilter(_ orders: [SalesOrder], field: OrderFilterField, value: String) -> [SalesOrder] {
        let raw = value.trimmingCharacters(in: .whitespaces)
        let v = raw.lowercased()
        guard field != .none, !v.isEmpty else { return orders }
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
            return orders.filter { $0.number.lowercased().contains(v) }
        case .buyerName:
            return orders.filter { $0.buyer.name.lowercased().contains(v) }
        case .buyerSiren:
            return orders.filter { ($0.buyer.siren ?? "").lowercased().contains(v) }
        case .buyerVat:
            return orders.filter { ($0.buyer.vatNumber ?? "").lowercased().contains(v) }
        case .sellerName:
            return orders.filter { $0.seller.name.lowercased().contains(v) }
        case .sellerSiren:
            return orders.filter { ($0.seller.siren ?? "").lowercased().contains(v) }
        case .amountMin:
            if let min = Double(v.replacingOccurrences(of: ",", with: ".")) {
                return orders.filter { $0.grandTotal >= min }
            }
            return orders
        case .amountMax:
            if let max = Double(v.replacingOccurrences(of: ",", with: ".")) {
                return orders.filter { $0.grandTotal <= max }
            }
            return orders
        case .issueDateFrom:
            if let d = parseDate(raw) { return orders.filter { $0.issueDate >= d } }
            return orders
        case .issueDateTo:
            if let d = parseDate(raw) { return orders.filter { $0.issueDate <= d } }
            return orders
        case .quotationRef:
            return orders.filter { ($0.quotationRef ?? "").lowercased().contains(v) }
        case .contractRef:
            return orders.filter { ($0.contractRef ?? "").lowercased().contains(v) }
        case .buyerReference:
            return orders.filter { ($0.buyerReference ?? "").lowercased().contains(v) }
        case .status:
            return orders.filter { $0.status.rawValue.lowercased() == v || $0.status.label.lowercased().contains(v) }
        case .none:
            return orders
        }
    }

    @ViewBuilder
    private func advancedFilterRow(field: Binding<OrderFilterField>, value: Binding<String>, index: Int) -> some View {
        let isDate = (field.wrappedValue == .issueDateFrom || field.wrappedValue == .issueDateTo)
        let isAmount = (field.wrappedValue == .amountMin || field.wrappedValue == .amountMax)
        HStack(spacing: 8) {
            Picker("", selection: field) {
                ForEach(OrderFilterField.allCases, id: \.self) { f in
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

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    Menu {
                        Button {
                            showScanImport = true
                        } label: { Label("Scanner un document", systemImage: "doc.viewfinder") }
                            .help("Importer la photo/le scan d'un bon de commande ou d'un devis fournisseur pour pré-remplir une commande")
                        if moduleStore.settings.quotesEnabled {
                            Button {
                                showQuotePicker = true
                            } label: { Label("Depuis un devis", systemImage: "doc.text.below.ecg") }
                                .help("Transforme un devis accepté en commande")
                        }
                    } label: {
                        Label("Nouvelle commande", systemImage: "plus")
                    } primaryAction: {
                        let draft = orderStore.newDraft(preferredSellerEntryID: auth.currentUser?.defaultSellerEntryID, companyID: companyFilter ?? defaultOrderCompanyID())
                        orderStore.upsert(draft)
                        selectedID = draft.id
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Nouvelle commande vierge — flèche pour créer depuis un devis, ou en scannant un document")
                    Text("Ventes").font(.title2.bold())
                    Picker("Statut", selection: $statusFilter) {
                        Text("Tous statuts").tag(OrderStatus?.none)
                        ForEach(OrderStatus.allCases, id: \.self) { s in
                            Label(s.label, systemImage: s.systemImage).tag(OrderStatus?.some(s))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                    Spacer()
                    Menu {
                        ForEach(QuickExport.OrderFormat.allCases, id: \.self) { f in
                            Button(f.rawValue) { exportMessage = QuickExport.run(orders: filteredOrders, format: f) }
                        }
                    } label: { Label("Exporter", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.bordered)
                        .help("Exporte les commandes actuellement filtrées (\(filteredOrders.count))")
                }
                if let m = exportMessage, !m.isEmpty {
                    Text(m).font(.caption).foregroundStyle(.secondary)
                        .onChange(of: query) { _ in exportMessage = nil }
                }
                HStack(spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Rechercher (numéro, client…)", text: $query)
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
                if filteredOrders.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "cart").font(.largeTitle).foregroundStyle(.secondary)
                        Text("Aucune commande.")
                            .foregroundStyle(.secondary)
                        Button("Nouvelle commande") {
                            let draft = orderStore.newDraft(preferredSellerEntryID: auth.currentUser?.defaultSellerEntryID, companyID: companyFilter ?? defaultOrderCompanyID())
                            orderStore.upsert(draft)
                            selectedID = draft.id
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(filteredOrders.enumerated()), id: \.element.id) { _, order in
                                VStack(alignment: .leading) {
                                    HStack {
                                        Text(order.number).font(.headline)
                                        Spacer()
                                        Text(order.issueDate, format: .dateTime.day().month().year())
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    HStack(spacing: 6) {
                                        let so = statusStore.override(for: order)
                                        Image(systemName: so.systemImage)
                                            .foregroundColor(Color(hex: so.hexColor))
                                            .font(.caption2)
                                        Text(so.label).font(.caption2)
                                            .foregroundColor(Color(hex: so.hexColor))
                                        Text(order.type.label)
                                            .font(.caption2).foregroundStyle(Color.accentColor)
                                        Spacer()
                                    }
                                    Text("\(order.buyer.name.isEmpty ? "Sans client" : order.buyer.name)")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text(String(format: "%.2f %@ TTC", order.grandTotal, order.currency))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 6).padding(.horizontal, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .background(selectedID == order.id ? Color.accentColor.opacity(0.15) : Color.clear)
                                .onTapGesture { selectedID = order.id }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        orderStore.orders.removeAll { $0.id == order.id }
                                        orderStore.save()
                                        if selectedID == order.id { selectedID = nil }
                                    } label: { Label("Supprimer", systemImage: "trash") }
                                }
                            }
                        }
                    }
                    .frame(minWidth: 200, idealWidth: 260, maxWidth: 300)
                }

                if let id = selectedID,
                   orderStore.orders.contains(where: { $0.id == id }) {
                    // Une instance d'éditeur par commande, dans un conteneur stable pour le
                    // HSplitView (voir InvoicesTabView) : aucun `onChange` de l'éditeur ne se
                    // déclenche au changement de sélection, et ses `@State` (verrouillage manuel,
                    // messages) ne passent plus d'une commande à l'autre.
                    VStack(spacing: 0) {
                        OrderEditorView(order: binding(for: id))
                            .id(id)
                    }
                    .frame(minWidth: 380)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "cart.magnifyingglass").font(.largeTitle).foregroundStyle(.secondary)
                        Text("Sélectionnez ou créez une commande")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .sheet(isPresented: $showScanImport) {
            DocumentScanImportView(
                onCreated: { orderID in
                    selectedID = orderID
                    showScanImport = false
                },
                onCancel: { showScanImport = false }
            )
        }
        .sheet(isPresented: $showQuotePicker) {
            QuoteToOrderSheet(
                quotes: scopedOrderableQuotes,
                onCreate: { quote in
                    let number = orderStore.nextNumber(companyID: quote.companyID)
                    let order = quote.toOrder(number: number)
                    orderStore.upsert(order)
                    var converted = quote
                    converted.convertedOrderNumber = order.number
                    quoteStore.upsert(converted)
                    selectedID = order.id
                    showQuotePicker = false
                },
                onCancel: { showQuotePicker = false }
            )
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

    /// Devis transformables en commande : acceptés et pas déjà convertis (ni en
    /// commande, ni directement en facture) — même garde que côté Factures, pour
    /// qu'un devis n'alimente jamais deux documents de vente à la fois.
    private var scopedOrderableQuotes: [Quote] {
        var result = quoteStore.quotes.filter {
            $0.status == .accepted && $0.convertedOrderNumber == nil && $0.convertedInvoiceNumber == nil
        }
        if let scope = auth.visibleOrderCompanyIDs(for: auth.currentUser) {
            result = result.filter { quote in
                if let cid = quote.companyID { return scope.contains(cid) }
                return false
            }
        }
        return result.sorted { $0.issueDate > $1.issueDate }
    }

    private func defaultOrderCompanyID() -> UUID? {
        let visible = auth.visibleSocieties(for: auth.currentUser)
        if visible.count == 1 { return visible.first?.id }
        if let preferred = auth.societyEntry(forID: auth.currentUser?.defaultSellerEntryID),
           visible.contains(where: { $0.id == preferred.id }) {
            return preferred.id
        }
        return visible.first?.id
    }

    private func binding(for id: UUID) -> Binding<SalesOrder> {
        Binding(
            get: { orderStore.orders.first(where: { $0.id == id }) ?? SalesOrder(number: "", buyer: InvoiceParty(name: "", street: "", postcode: "", city: ""), seller: InvoiceParty(name: "", street: "", postcode: "", city: "")) },
            set: { newValue in
                if let idx = orderStore.orders.firstIndex(where: { $0.id == id }) {
                    orderStore.orders[idx] = newValue
                    orderStore.save()
                }
            }
        )
    }
}

struct OrderEditorView: View {
    @Binding var order: SalesOrder
    @EnvironmentObject var orderStore: OrderStore
    @EnvironmentObject var statusStore: OrderStatusStore
    @EnvironmentObject var store: InvoiceStore
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var smtpSettings: SMTPSettings
    @EnvironmentObject var emailTemplateStore: EmailTemplateStore
    @State private var exportError: String?
    @State private var exportedURL: URL?
    @State private var validation: FacturXValidationResult?
    @State private var showValidation = false
    @State private var isManuallyLocked = false
    @State private var showUnlockAlert = false
    @State private var createdInvoiceNumber: String?
    @State private var showMandatoryDetails = false
    @State private var sendingOrderEmail: EmailTemplateKind?
    @State private var orderEmailMessage: String?

    private var statusLocked: Bool { order.status.locksOrder }
    private var isLocked: Bool { statusLocked || isManuallyLocked }
    private var isAdmin: Bool { auth.currentUser?.isAdmin ?? false }
    private var fieldLocked: Bool { isLocked && !isAdmin }

    private var hasMandatoryWarnings: Bool {
        let b = order.buyer
        let s = order.seller
        let buyerOk = !b.name.trimmingCharacters(in: .whitespaces).isEmpty
            && !b.country.trimmingCharacters(in: .whitespaces).isEmpty
            && ((b.siren ?? "").trimmingCharacters(in: .whitespaces).count >= 9
                || (b.endpointID ?? "").trimmingCharacters(in: .whitespaces).count >= 9)
        let sellerOk = !s.name.trimmingCharacters(in: .whitespaces).isEmpty
            && !s.country.trimmingCharacters(in: .whitespaces).isEmpty
            && ((s.siren ?? "").trimmingCharacters(in: .whitespaces).count >= 9
                || (s.endpointID ?? "").trimmingCharacters(in: .whitespaces).count >= 9)
        let headerOk = !order.number.trimmingCharacters(in: .whitespaces).isEmpty
            && !order.currency.trimmingCharacters(in: .whitespaces).isEmpty
        let linesOk = order.lines.allSatisfy {
            !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && $0.quantity > 0 && $0.unitPrice >= 0
        }
        return !(buyerOk && sellerOk && headerOk && linesOk)
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Bandeau d'informations (fixe, lecture seule)
            HStack(spacing: 10) {
                Text(order.number).font(.title2.bold())
                Text(order.issueDate, format: .dateTime.day().month().year())
                    .font(.callout).foregroundStyle(.secondary)
                Text(String(format: "%.2f %@ HT", order.lineTotal, order.currency))
                    .font(.callout).foregroundStyle(.secondary)
                let currentStatus = statusStore.override(for: order)
                HStack(spacing: 4) {
                    Image(systemName: currentStatus.systemImage)
                    Text(currentStatus.label)
                }
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Color(hex: currentStatus.hexColor)))
                if isLocked {
                    Label("Lecture seule", systemImage: "lock.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .overlay(Capsule().stroke(.secondary, lineWidth: 0.5))
                    if isAdmin {
                        Text("(admin : modification autorisée)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                HStack(spacing: 4) {
                    Text(order.seller.name.trimmingCharacters(in: .whitespaces).isEmpty ? "Société non renseignée" : order.seller.name)
                    Image(systemName: "arrow.right").font(.caption2)
                    Text(order.buyer.name.trimmingCharacters(in: .whitespaces).isEmpty ? "Client non renseigné" : order.buyer.name)
                }
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .padding(12)
            Divider()

            // MARK: Barre d'actions (fixe), sous-groupée : cycle de vie · admin
            ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                let currentStatus = statusStore.override(for: order)
                let configuredTransitions = statusStore.override(for: order.status).transitionCodes.compactMap { OrderStatus(rawValue: $0) }
                HStack(spacing: 8) {
                    if isManuallyLocked && !statusLocked && !isAdmin {
                        Button { showUnlockAlert = true } label: {
                            Label("Modifier", systemImage: "lock.open")
                        }
                        .buttonStyle(ToolbarActionButtonStyle(tint: .gray))
                        .help("Repasser en édition (la commande n'est plus protégée)")
                    } else if !isLocked && validation?.isValid == true {
                        Button { isManuallyLocked = true } label: {
                            Label("Verrouiller", systemImage: "lock")
                        }
                        .buttonStyle(ToolbarActionButtonStyle(tint: .gray))
                        .help("Protéger la commande validée en lecture seule")
                    }
                    Button("Valider") { runValidation() }
                        .buttonStyle(ToolbarActionButtonStyle(tint: .blue))
                        .disabled(fieldLocked)
                    ForEach(configuredTransitions, id: \.self) { s in
                        Button {
                            order.status = s
                            order.customStatusID = nil
                        } label: {
                            Label(s.label, systemImage: s.systemImage)
                        }
                        .buttonStyle(ToolbarActionButtonStyle(tint: Color(hex: s.hexColor)))
                        .help("Passer au statut « \(s.label) »")
                    }
                    Button("Exporter XML") { exportXML() }
                        .buttonStyle(ToolbarActionButtonStyle(tint: .gray))
                    Button("Générer l'Order-X") { export() }
                        .buttonStyle(ToolbarActionButtonStyle(tint: .blue, filled: true))
                    Button("Créer la facture") { createInvoice() }
                        .buttonStyle(ToolbarActionButtonStyle(tint: .gray))
                }
                if emailTemplateStore.globalEnabled {
                    Divider().frame(height: 20)
                    HStack(spacing: 8) {
                        orderEmailButton(kind: .orderConfirmation, label: "Confirmer par email")
                        orderEmailButton(kind: .deliveryNotice, label: "Avis de livraison")
                    }
                }
                if isAdmin {
                    let forceable = statusStore.overrides.filter { $0.id != currentStatus.id && !configuredTransitions.map(\.rawValue).contains($0.id) }
                    if !forceable.isEmpty {
                        Divider().frame(height: 20)
                        Menu {
                            ForEach(forceable) { target in
                                Button {
                                    if let s = OrderStatus(rawValue: target.id) {
                                        order.status = s
                                        order.customStatusID = nil
                                    } else {
                                        order.customStatusID = target.id
                                    }
                                } label: {
                                    Label(target.label, systemImage: target.systemImage)
                                }
                            }
                        } label: {
                            Label("Forcer", systemImage: "bolt.fill")
                        }
                        .buttonStyle(ToolbarActionButtonStyle(tint: .red))
                        .help("Administrateur : forcer un statut hors des transitions configurées")
                    }
                }
                Spacer()
            }
            .padding(12)
            }
            Divider()
            if hasMandatoryWarnings || showValidation || exportError != nil || exportedURL != nil || createdInvoiceNumber != nil || orderEmailMessage != nil {
                VStack(alignment: .leading, spacing: 8) {
                if let m = orderEmailMessage, !m.isEmpty {
                    Text(m).font(.caption).foregroundStyle(m.hasPrefix("Échec") ? .red : .green)
                        .onChange(of: order.number) { _ in orderEmailMessage = nil }
                }
                if let err = exportError {
                    Text("Erreur : \(err)").foregroundStyle(.red).font(.caption)
                        .onChange(of: order.number) { _ in exportError = nil }
                        .onChange(of: order.seller.name) { _ in exportError = nil }
                        .onChange(of: order.buyer.name) { _ in exportError = nil }
                }
                if let url = exportedURL {
                    Text("Fichier généré : \(url.lastPathComponent)").font(.caption).foregroundStyle(.green)
                    Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        .onChange(of: order.number) { _ in exportedURL = nil }
                        .onChange(of: order.seller.name) { _ in exportedURL = nil }
                        .onChange(of: order.buyer.name) { _ in exportedURL = nil }
                }
                if let n = createdInvoiceNumber {
                    Text("Facture créée : \(n)").font(.caption).foregroundStyle(.green)
                        .onChange(of: order.number) { _ in createdInvoiceNumber = nil }
                }

                if hasMandatoryWarnings {
                    DisclosureGroup(isExpanded: $showMandatoryDetails) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Acheteur et client : nom, pays (code ISO 2 lettres), SIREN ou identifiant électronique, n° TVA si applicable.").font(.caption)
                            Text("Lignes : désignation non vide, quantité positive, prix unitaire, taux TVA, unité (code UN/ECE ex. C62, DAY, HUR).").font(.caption)
                            Text("En-tête : numéro de commande, date d'émission, date de livraison souhaitée, devise (EUR).").font(.caption)
                        }
                    } label: {
                        Label("Données obligatoires pour la conformité Order-X", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                    }
                }

                if showValidation, let v = validation {
                    orderValidationPanel(v)
                        .onChange(of: order.number) { _ in showValidation = false; validation = nil }
                }
                }.padding(12)
                Divider()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                GroupBox("En-tête") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 24) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    LabeledContent {
                                        TextField("", text: $order.number).frame(width: 160)
                                    } label: {
                                        HStack(spacing: 3) {
                                            Text("Numéro *").foregroundColor(.red)
                                            InfoBadge(text: "Numéro unique de la commande.")
                                        }
                                    }
                                    HStack(spacing: 3) {
                                        Picker("Type", selection: $order.type) {
                                            ForEach(OrderTypeCode.allCases, id: \.self) { Text($0.label).tag($0) }
                                        }.frame(width: 260)
                                        InfoBadge(text: "Type de document : 220 commande, 221 modification, 222 réponse.")
                                    }
                                }
                                HStack {
                                    HStack(spacing: 3) {
                                        DatePicker("Date", selection: $order.issueDate, displayedComponents: .date)
                                        InfoBadge(text: "Date d'émission de la commande.")
                                    }
                                    HStack(spacing: 3) {
                                        DatePicker("Livraison", selection: $order.requestedDeliveryDate, displayedComponents: .date)
                                        InfoBadge(text: "Date de livraison souhaitée par l'acheteur.")
                                    }
                                }
                                HStack {
                                    Picker("Profil Order-X", selection: $order.profile) {
                                        ForEach(OrderXProfile.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                                    }
                                    NormRefPicker("Devise", options: NormRefs.currencies, code: $order.currency).frame(width: 160)
                                    HStack(spacing: 3) {
                                        TextField("Réf. acheteur", text: Binding($order.buyerReference, replacingNilWith: ""))
                                        InfoBadge(text: "Référence acheteur (BuyerReference), remontée en haut de la commande.")
                                    }
                                }
                                DisclosureGroup("Autres références") {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(spacing: 3) {
                                            TextField("Réf. devis", text: Binding($order.quotationRef, replacingNilWith: "")).frame(width: 220)
                                            InfoBadge(text: "QuotationReferencedDocument — référence du devis.")
                                        }
                                        HStack(spacing: 3) {
                                            TextField("Réf. contrat", text: Binding($order.contractRef, replacingNilWith: "")).frame(width: 220)
                                            InfoBadge(text: "ContractReferencedDocument — référence du contrat.")
                                        }
                                        HStack(spacing: 3) {
                                            TextField("Réf. commande cadre", text: Binding($order.blanketOrderRef, replacingNilWith: "")).frame(width: 220)
                                            InfoBadge(text: "BlanketOrderReferencedDocument — commande cadre.")
                                        }
                                        HStack(spacing: 3) {
                                            TextField("Réf. modif. précédente", text: Binding($order.previousOrderChangeRef, replacingNilWith: "")).frame(width: 220)
                                            InfoBadge(text: "PreviousOrderChangeReferencedDocument.")
                                        }
                                        HStack(spacing: 3) {
                                            TextField("Réf. réponse précédente", text: Binding($order.previousOrderResponseRef, replacingNilWith: "")).frame(width: 220)
                                            InfoBadge(text: "PreviousOrderResponseReferencedDocument.")
                                        }
                                    }
                                }
                                .font(.caption)
                            }
                            VStack(alignment: .trailing) {
                                ForEach(order.vatBreakdown, id: \.rate) { item in
                                    row("TVA \(String(format: "%g%%", item.rate))", item.amount)
                                }
                                row("Total TTC", order.grandTotal, bold: true)
                                Divider().frame(width: 280)
                                row("Montant facturé", linkedInvoicesAmount)
                                row("Reste à facturer", max(0, order.grandTotal - linkedInvoicesAmount), bold: true)
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.clear))
                        }
                    }.padding(8)
                }.lockable(fieldLocked)

                HStack(alignment: .top, spacing: 12) {
                    GroupBox("Société (vous)") {
                        OrderPartySection(party: $order.seller, role: .seller, locked: fieldLocked, companyID: order.companyID)
                    }.lockable(fieldLocked)
                    GroupBox("Client") {
                        OrderPartySection(party: $order.buyer, role: .buyer, locked: fieldLocked)
                    }.lockable(fieldLocked)
                }

                GroupBox("Lignes") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach($order.lines) { $line in
                            HStack {
                                HStack(spacing: 2) {
                                    TextField("Désignation *", text: $line.name).frame(minWidth: 220)
                                    InfoBadge(text: "Désignation de la ligne. Obligatoire.")
                                }
                                HStack(spacing: 2) {
                                    DoubleField("Qté", value: $line.quantity, format: .number)
                                    InfoBadge(text: "Quantité demandée. Doit être positive.")
                                }
                                HStack(spacing: 2) {
                                    NormRefPicker("Unité", options: NormRefs.units, code: $line.unit).frame(width: 180)
                                    InfoBadge(text: "Unité de mesure (UN/ECE Rec 20).")
                                }
                                HStack(spacing: 2) {
                                    DoubleField("P.U. HT", value: $line.unitPrice, format: .number)
                                    InfoBadge(text: "Prix unitaire HT.")
                                }
                                HStack(spacing: 2) {
                                    VATRatePicker(rate: $line.vatRate)
                                    InfoBadge(text: "Taux de TVA appliqué (%). Catégorie et motif d'exonération réglables ci-dessous pour un taux à 0 %.")
                                }
                                Text(String(format: "%.2f", line.lineTotal))
                                    .monospacedDigit().frame(width: 80, alignment: .trailing)
                                Button {
                                    DispatchQueue.main.async {
                                        order.lines.removeAll { $0.id == line.id }
                                    }
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                            }
                            .onChange(of: line.vatRate) { newRate in
                                line.vatCategory = newRate == 0 ? .zeroRated : .standard
                                if newRate != 0 { line.vatExemptionReason = nil }
                            }
                            if line.vatRate == 0 {
                                HStack(spacing: 8) {
                                    HStack(spacing: 2) {
                                        Picker("", selection: $line.vatCategory) {
                                            ForEach(VATCategory.allCases, id: \.self) { cat in
                                                Text("\(cat.rawValue) — \(cat.label)").tag(cat)
                                            }
                                        }
                                        .labelsHidden()
                                        .frame(width: 210)
                                        InfoBadge(text: "Catégorie de TVA : S = normal, Z = taux zéro, AE = autoliquidation, K = livraison intracommunautaire, G = exportation hors UE, E = exonérée, O = hors champ.")
                                    }
                                    if line.vatCategory.requiresExemptionReason {
                                        HStack(spacing: 2) {
                                            TextField("Motif d'exonération", text: Binding($line.vatExemptionReason, replacingNilWith: ""))
                                                .frame(minWidth: 280)
                                            InfoBadge(text: "Motif d'exonération, obligatoire pour cette catégorie de TVA.")
                                        }
                                    }
                                }
                                .padding(.leading, 4)
                            }
                        }
                        Button {
                            order.lines.append(InvoiceLine(name: "", quantity: 1, unitPrice: 0, vatRate: order.lines.last?.vatRate ?? 20))
                        } label: { Label("Ajouter une ligne", systemImage: "plus") }
                    }.padding(8)
                }.lockable(fieldLocked)

                GroupBox("Notes") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Notes libres", text: Binding($order.notes, replacingNilWith: ""))
                    }.padding(8)
                }.lockable(fieldLocked)

                AttachmentsAndCommentSection(attachments: $order.attachments, internalComment: $order.internalComment, locked: fieldLocked)

                GroupBox("Factures et avoirs liés") {
                    VStack(alignment: .leading, spacing: 8) {
                        if linkedInvoices.isEmpty {
                            Text("Aucune facture ou avoir lié à cette commande.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(linkedInvoices.enumerated()), id: \.element.id) { _, inv in
                                HStack {
                                    Image(systemName: inv.type.isCreditNote ? "arrow.uturn.backward.circle" : "doc.text")
                                        .foregroundStyle(inv.type.isCreditNote ? Color.orange : Color.accentColor)
                                    VStack(alignment: .leading) {
                                        Text(inv.number).font(.headline)
                                        Text("\(inv.type == .creditNote ? "Avoir" : inv.type.isInternalCreditNote ? "Avoir interne" : "Facture") — \(String(format: "%.2f %@ TTC", inv.grandTotal, inv.currency))")
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(inv.issueDate, format: .dateTime.day().month().year())
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }.padding(8)
                }.lockable(fieldLocked)
            }.padding()
        }
            .alert("Repasser en modification ?", isPresented: $showUnlockAlert) {
                Button("Annuler", role: .cancel) { }
                Button("Modifier", role: .destructive) { isManuallyLocked = false }
            } message: {
                Text("La commande était verrouillée en lecture seule après validation conforme. En la déverrouillant, vous reprenez l'édition ; pensez à valider de nouveau avant tout envoi au client.")
            }
        }
    }

    private var linkedInvoices: [Invoice] {
        store.invoices.filter { inv in
            inv.purchaseOrderRef == order.number
                || inv.lines.contains(where: { ($0.orderReference ?? "") == order.number })
        }.sorted { $0.issueDate > $1.issueDate }
    }

    private var linkedInvoicesAmount: Double {
        linkedInvoices.reduce(0) { acc, inv in
            inv.type.isCreditNote ? acc - inv.grandTotal : acc + inv.grandTotal
        }.rounded(toPlaces: 2)
    }

    private func row(_ label: String, _ value: Double, bold: Bool = false) -> some View {
        HStack {
            Text(label).font(bold ? .body.bold() : .body)
            Spacer()
            Text(String(format: "%.2f %@", value, order.currency))
                .font(bold ? .body.bold() : .body)
                .monospacedDigit()
        }.frame(width: 280)
    }

    private func export() {
        exportError = nil
        exportedURL = nil
        let preCheck = OrderXValidator().validate(order: order)
        if !preCheck.isValid {
            validation = preCheck
            showValidation = true
            exportError = "Validation échouée : \(preCheck.errors.count) erreur(s). Corrigez avant de générer."
            return
        }
        do {
            orderStore.upsert(order)
            let data = try OrderXGenerator().generate(order: order)
            let postCheck = OrderXValidator().validate(pdf: data)
            if !postCheck.isValid {
                validation = FacturXValidationResult(
                    isValid: false,
                    errors: postCheck.errors,
                    warnings: preCheck.warnings + postCheck.warnings
                )
                showValidation = true
                exportError = "La conformité du PDF généré a échoué : \(postCheck.errors.count) erreur(s)."
                return
            }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = "commande-\(order.number).pdf"
            if panel.runModal() == .OK, let url = panel.url {
                try data.write(to: url)
                exportedURL = url
                validation = FacturXValidationResult(
                    isValid: true,
                    warnings: preCheck.warnings + postCheck.warnings
                )
                showValidation = true
            }
        } catch {
            exportError = "\(error)"
        }
    }

    private func runValidation() {
        validation = OrderXValidator().validate(order: order)
        showValidation = true
    }

    private func createInvoice() {
        let number = store.nextNumber(companyID: order.companyID)
        let invoice = order.toInvoice(number: number)
        store.upsert(invoice)
        createdInvoiceNumber = number
    }

    @ViewBuilder
    private func orderEmailButton(kind: EmailTemplateKind, label: String) -> some View {
        Button {
            sendOrderEmail(kind: kind)
        } label: {
            if sendingOrderEmail == kind {
                HStack(spacing: 4) { ProgressView().controlSize(.small); Text("Envoi…") }
            } else {
                Label(label, systemImage: kind.systemImage)
            }
        }
        .buttonStyle(ToolbarActionButtonStyle(tint: .blue))
        .disabled(sendingOrderEmail != nil
                  || !emailTemplateStore.isSendEnabled(kind, companyID: order.companyID)
                  || (order.buyer.contactEmail ?? "").isEmpty
                  || !smtpSettings.credentials(for: order.companyID).isConfigured)
        .help(!emailTemplateStore.template(for: kind, companyID: order.companyID).enabled
              ? "Cet email est désactivé (Réglages > Application)"
              : (order.buyer.contactEmail ?? "").isEmpty
              ? "Aucune adresse email cliente renseignée"
              : !smtpSettings.credentials(for: order.companyID).isConfigured
              ? "Configurez l'envoi d'email (Réglages) pour envoyer cet email"
              : "Envoyer « \(kind.label) » par email au client")
    }

    private func sendOrderEmail(kind: EmailTemplateKind) {
        guard let recipient = order.buyer.contactEmail, !recipient.isEmpty else {
            orderEmailMessage = "Échec envoi : aucune adresse email cliente renseignée."
            return
        }
        let credentials = smtpSettings.credentials(for: order.companyID)
        guard credentials.isConfigured else {
            orderEmailMessage = "Échec envoi : envoi d'email non configuré (Réglages)."
            return
        }
        let template = emailTemplateStore.template(for: kind, companyID: order.companyID)
        let email = EmailComposer.compose(template: template, variables: [
            "numero": order.number,
            "client": order.buyer.name,
            "societe": order.seller.name,
            "montant": String(format: "%.2f %@", order.grandTotal, order.currency),
            "date": order.requestedDeliveryDate.formatted(.dateTime.day().month().year())
        ])
        sendingOrderEmail = kind
        orderEmailMessage = nil
        Task {
            do {
                try await SMTPService().send(to: recipient, subject: email.subject, body: email.body, credentials: credentials)
                orderEmailMessage = "« \(kind.label) » envoyé à \(recipient)."
            } catch {
                orderEmailMessage = "Échec envoi : \(error.localizedDescription)"
            }
            sendingOrderEmail = nil
        }
    }

    private func exportXML() {
        do {
            let xml = try OrderCIOXMLGenerator().generate(order: order)
            let xmlString = String(data: xml, encoding: .utf8) ?? ""
            print("=== XML CIO ===")
            print(xmlString)
            print("=== FIN XML ===")
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.xml]
            panel.nameFieldStringValue = "commande-\(order.number).xml"
            if panel.runModal() == .OK, let url = panel.url {
                try xml.write(to: url)
            }
        } catch {
            exportError = "\(error)"
        }
    }

    private func orderValidationPanel(_ v: FacturXValidationResult) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    if v.isValid {
                        Label("OK — contrôlé en local", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                    } else {
                        Label("Pré-vérification locale : \(v.errors.count) erreur(s)", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    }
                    Spacer()
                    Button { showValidation = false } label: {
                        Image(systemName: "xmark.circle")
                    }.buttonStyle(.plain)
                }
                Text("Contrôles internes, non exhaustifs — seule une validation officielle (SUPER PDP, etc.) fait foi.")
                    .font(.caption2).foregroundStyle(.secondary)
                if !v.errors.isEmpty {
                    Text("Erreurs :").font(.caption.bold())
                    ForEach(v.errors, id: \.self) { e in
                        Text("• \(e)").font(.caption).foregroundStyle(.red)
                    }
                }
                if !v.warnings.isEmpty {
                    Text("Avertissements :").font(.caption.bold())
                    ForEach(v.warnings, id: \.self) { w in
                        Text("• \(w)").font(.caption).foregroundStyle(.orange)
                    }
                }
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
