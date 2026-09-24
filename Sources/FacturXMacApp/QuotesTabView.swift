import SwiftUI
import FacturXCore

// MARK: - Extrait de FacturXMacApp.swift (découpage par domaine)

enum QuoteFilterField: String, CaseIterable, Hashable {
    case none = "Aucun"
    case number = "N° devis"
    case buyerName = "Client"
    case buyerSiren = "SIREN client"
    case buyerVat = "TVA client"
    case sellerName = "Émetteur"
    case amountMin = "Montant TTC min"
    case amountMax = "Montant TTC max"
    case issueDateFrom = "Émis depuis"
    case issueDateTo = "Émis jusqu'à"
    case validUntilFrom = "Valable jusqu'au (depuis)"
    case status = "Statut"
}

struct QuotesTabView: View {
    @EnvironmentObject var quoteStore: QuoteStore
    @EnvironmentObject var quoteStatusStore: QuoteStatusStore
    @EnvironmentObject var store: InvoiceStore
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var directory: PartyDirectory
    @Binding var selectedID: UUID?
    @Binding var rootTab: RootTab
    @Binding var invoiceSelectedID: UUID?
    @Binding var orderSelectedID: UUID?
    @Binding var companyFilter: UUID?
    @State private var query = ""
    @State private var exportMessage: String?
    @State private var statusFilter: QuoteStatus? = nil
    @State private var showAdvancedFilters = false
    @State private var advField1: QuoteFilterField = .none
    @State private var advValue1 = ""
    @State private var advField2: QuoteFilterField = .none
    @State private var advValue2 = ""
    @State private var advField3: QuoteFilterField = .none
    @State private var advValue3 = ""

    var filteredQuotes: [Quote] {
        var result = quoteStore.quotes
        if let scope = auth.visibleInvoiceCompanyIDs(for: auth.currentUser) {
            result = result.filter { quote in
                if let cid = quote.companyID { return scope.contains(cid) }
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
        if !q.isEmpty {
            result = result.filter { quote in
                quote.number.lowercased().contains(q) || quote.buyer.name.lowercased().contains(q)
            }
        }
        return result.sorted { $0.issueDate > $1.issueDate }
    }

    private func applyAdvancedFilter(_ quotes: [Quote], field: QuoteFilterField, value: String) -> [Quote] {
        let raw = value.trimmingCharacters(in: .whitespaces)
        let v = raw.lowercased()
        guard field != .none, !v.isEmpty else { return quotes }
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
            return quotes.filter { $0.number.lowercased().contains(v) }
        case .buyerName:
            return quotes.filter { $0.buyer.name.lowercased().contains(v) }
        case .buyerSiren:
            return quotes.filter { ($0.buyer.siren ?? "").lowercased().contains(v) }
        case .buyerVat:
            return quotes.filter { ($0.buyer.vatNumber ?? "").lowercased().contains(v) }
        case .sellerName:
            return quotes.filter { $0.seller.name.lowercased().contains(v) }
        case .amountMin:
            if let min = Double(v.replacingOccurrences(of: ",", with: ".")) {
                return quotes.filter { $0.grandTotal >= min }
            }
            return quotes
        case .amountMax:
            if let max = Double(v.replacingOccurrences(of: ",", with: ".")) {
                return quotes.filter { $0.grandTotal <= max }
            }
            return quotes
        case .issueDateFrom:
            if let d = parseDate(raw) { return quotes.filter { $0.issueDate >= d } }
            return quotes
        case .issueDateTo:
            if let d = parseDate(raw) { return quotes.filter { $0.issueDate <= d } }
            return quotes
        case .validUntilFrom:
            if let d = parseDate(raw) { return quotes.filter { $0.validUntil >= d } }
            return quotes
        case .status:
            return quotes.filter { $0.status.rawValue.lowercased() == v || $0.status.label.lowercased().contains(v) }
        case .none:
            return quotes
        }
    }

    @ViewBuilder
    private func advancedFilterRow(field: Binding<QuoteFilterField>, value: Binding<String>, index: Int) -> some View {
        let isDate = (field.wrappedValue == .issueDateFrom || field.wrappedValue == .issueDateTo || field.wrappedValue == .validUntilFrom)
        let isAmount = (field.wrappedValue == .amountMin || field.wrappedValue == .amountMax)
        HStack(spacing: 8) {
            Picker("", selection: field) {
                ForEach(QuoteFilterField.allCases, id: \.self) { f in
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

    private func defaultCompanyID() -> UUID? {
        let visible = auth.visibleSocieties(for: auth.currentUser)
        if visible.count == 1 { return visible.first?.id }
        if let preferred = auth.societyEntry(forID: auth.currentUser?.defaultSellerEntryID),
           visible.contains(where: { $0.id == preferred.id }) {
            return preferred.id
        }
        return visible.first?.id
    }

    private func newQuote() {
        let seller = store.resolveDefaultSeller(from: directory) ?? store.myCompany
        let draft = quoteStore.newDraft(seller: seller, companyID: companyFilter ?? defaultCompanyID())
        quoteStore.upsert(draft)
        selectedID = draft.id
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    Button { newQuote() } label: { Label("Nouveau devis", systemImage: "plus") }
                        .buttonStyle(.borderedProminent)
                    Text("Devis").font(.title2.bold())
                    Picker("Statut", selection: $statusFilter) {
                        Text("Tous statuts").tag(QuoteStatus?.none)
                        ForEach(QuoteStatus.allCases, id: \.self) { s in
                            Label(s.label, systemImage: s.systemImage).tag(QuoteStatus?.some(s))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                    Spacer()
                    Menu {
                        ForEach(QuickExport.QuoteFormat.allCases, id: \.self) { f in
                            Button(f.rawValue) { exportMessage = QuickExport.run(quotes: filteredQuotes, format: f) }
                        }
                    } label: { Label("Exporter", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.bordered)
                        .help("Exporte les devis actuellement filtrés (\(filteredQuotes.count))")
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
                if filteredQuotes.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text.below.ecg").font(.largeTitle).foregroundStyle(.secondary)
                        Text("Aucun devis.")
                            .foregroundStyle(.secondary)
                        Button("Nouveau devis") { newQuote() }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(filteredQuotes) { quote in
                                VStack(alignment: .leading) {
                                    HStack {
                                        Text(quote.number).font(.headline)
                                        Spacer()
                                        Text(quote.issueDate, format: .dateTime.day().month().year())
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    HStack(spacing: 6) {
                                        let qs = quoteStatusStore.override(for: quote.status)
                                        Image(systemName: qs.systemImage)
                                            .foregroundColor(Color(hex: qs.hexColor))
                                            .font(.caption2)
                                        Text(qs.label).font(.caption2)
                                            .foregroundColor(Color(hex: qs.hexColor))
                                        if quote.isExpiredByDate {
                                            Label("Validité dépassée", systemImage: "exclamationmark.triangle.fill")
                                                .font(.caption2).foregroundStyle(.orange)
                                        }
                                        Spacer()
                                    }
                                    Text("\(quote.buyer.name.isEmpty ? "Sans client" : quote.buyer.name)")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text(String(format: "%.2f %@ TTC", quote.grandTotal, quote.currency))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 6).padding(.horizontal, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .background(selectedID == quote.id ? Color.accentColor.opacity(0.15) : Color.clear)
                                .onTapGesture { selectedID = quote.id }
                                .contextMenu {
                                    Button {
                                        let copy = quoteStore.duplicate(from: quote)
                                        quoteStore.upsert(copy)
                                        selectedID = copy.id
                                    } label: { Label("Dupliquer", systemImage: "plus.square.on.square") }
                                    Divider()
                                    Button(role: .destructive) {
                                        quoteStore.delete(quote)
                                        if selectedID == quote.id { selectedID = nil }
                                    } label: { Label("Supprimer", systemImage: "trash") }
                                }
                            }
                        }
                    }
                    .frame(minWidth: 200, idealWidth: 260, maxWidth: 300)
                }

                if let id = selectedID, quoteStore.quotes.contains(where: { $0.id == id }) {
                    // Une instance d'éditeur par devis, dans un conteneur stable pour le HSplitView
                    // (voir InvoicesTabView). Sans cela, entre un devis et son duplicata (qui garde
                    // les ids de ligne), `onChange(of: line.vatRate)` réécrivait la catégorie de TVA
                    // d'une ligne du devis qu'on quitte.
                    VStack(spacing: 0) {
                        QuoteEditorView(quote: binding(for: id), rootTab: $rootTab, invoiceSelectedID: $invoiceSelectedID, orderSelectedID: $orderSelectedID)
                            .id(id)
                    }
                    .frame(minWidth: 380)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass").font(.largeTitle).foregroundStyle(.secondary)
                        Text("Sélectionnez ou créez un devis")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private func binding(for id: UUID) -> Binding<Quote> {
        Binding(
            get: { quoteStore.quotes.first(where: { $0.id == id }) ?? Quote(number: "", seller: InvoiceParty(name: "", street: "", postcode: "", city: ""), buyer: InvoiceParty(name: "", street: "", postcode: "", city: "")) },
            set: { newValue in
                quoteStore.upsert(newValue)
            }
        )
    }
}

struct QuoteEditorView: View {
    @Binding var quote: Quote
    @Binding var rootTab: RootTab
    @Binding var invoiceSelectedID: UUID?
    @Binding var orderSelectedID: UUID?
    @EnvironmentObject var quoteStore: QuoteStore
    @EnvironmentObject var quoteStatusStore: QuoteStatusStore
    @EnvironmentObject var store: InvoiceStore
    @EnvironmentObject var orderStore: OrderStore
    @EnvironmentObject var moduleStore: ModuleStore
    @EnvironmentObject var smtpSettings: SMTPSettings
    @EnvironmentObject var emailTemplateStore: EmailTemplateStore
    @State private var sendingQuoteEmail = false
    @State private var quoteEmailMessage: String?

    private var isLocked: Bool { quote.status.locksQuote }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(quote.number).font(.title2.bold())
                Text(quote.issueDate, format: .dateTime.day().month().year())
                    .font(.callout).foregroundStyle(.secondary)
                let currentStatus = quoteStatusStore.override(for: quote.status)
                HStack(spacing: 4) {
                    Image(systemName: currentStatus.systemImage)
                    Text(currentStatus.label)
                }
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Color(hex: currentStatus.hexColor)))
                if quote.isExpiredByDate {
                    Label("Validité dépassée", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.orange))
                }
                Spacer()
                Text(String(format: "%.2f %@ HT", quote.lineTotal, quote.currency))
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(12)

            Divider()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    if emailTemplateStore.globalEnabled {
                        Button {
                            sendQuoteEmail()
                        } label: {
                            if sendingQuoteEmail {
                                HStack(spacing: 4) { ProgressView().controlSize(.small); Text("Envoi…") }
                            } else {
                                Label("Envoyer le devis", systemImage: EmailTemplateKind.quoteSent.systemImage)
                            }
                        }
                        .buttonStyle(ToolbarActionButtonStyle(tint: .blue))
                        .disabled(sendingQuoteEmail
                                  || !emailTemplateStore.isSendEnabled(.quoteSent, companyID: quote.companyID)
                                  || (quote.buyer.contactEmail ?? "").isEmpty
                                  || !smtpSettings.credentials(for: quote.companyID).isConfigured)
                        .help(!emailTemplateStore.template(for: .quoteSent, companyID: quote.companyID).enabled
                              ? "Cet email est désactivé (Réglages > Application)"
                              : (quote.buyer.contactEmail ?? "").isEmpty
                              ? "Aucune adresse email cliente renseignée"
                              : !smtpSettings.credentials(for: quote.companyID).isConfigured
                              ? "Configurez l'envoi d'email (Réglages) pour envoyer un devis"
                              : "Envoyer le devis par email au client")
                    }
                    ForEach(quoteStatusStore.allowedTransitions(from: quote.status), id: \.self) { s in
                        let so = quoteStatusStore.override(for: s)
                        Button {
                            quote.status = s
                        } label: {
                            Label(so.label, systemImage: so.systemImage)
                        }
                        .buttonStyle(ToolbarActionButtonStyle(tint: Color(hex: so.hexColor)))
                        .help("Passer au statut « \(so.label) »")
                    }
                    if quote.status == .accepted && quote.convertedOrderNumber == nil {
                        Button {
                            let number = store.nextNumber(companyID: quote.companyID)
                            let invoice = quote.toInvoice(number: number)
                            store.upsert(invoice)
                            quote.convertedInvoiceNumber = invoice.number
                            invoiceSelectedID = invoice.id
                            rootTab = .invoices
                        } label: {
                            Label("Convertir en facture", systemImage: "arrow.right.doc.on.clipboard")
                        }
                        .buttonStyle(ToolbarActionButtonStyle(tint: .blue, filled: true))
                        .help("Recopie les lignes du devis dans une nouvelle facture brouillon")
                    }
                    if quote.status == .accepted && moduleStore.settings.ordersEnabled && quote.convertedInvoiceNumber == nil {
                        Button {
                            let number = orderStore.nextNumber(companyID: quote.companyID)
                            let order = quote.toOrder(number: number)
                            orderStore.upsert(order)
                            quote.convertedOrderNumber = order.number
                            orderSelectedID = order.id
                            rootTab = .orders
                        } label: {
                            Label("Convertir en commande", systemImage: "cart.badge.plus")
                        }
                        .buttonStyle(ToolbarActionButtonStyle(tint: .orange, filled: true))
                        .help("Recopie les lignes du devis dans une nouvelle commande brouillon")
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }

            if let n = quote.convertedOrderNumber {
                Text("Converti en commande : \(n) (disponible dans l'onglet Ventes)")
                    .font(.caption).foregroundStyle(.green)
                    .padding(.horizontal, 12)
            }
            if let n = quote.convertedInvoiceNumber {
                Text("Converti en facture : \(n) (disponible dans l'onglet Factures)")
                    .font(.caption).foregroundStyle(.green)
                    .padding(.horizontal, 12)
            }
            if let m = quoteEmailMessage, !m.isEmpty {
                Text(m).font(.caption).foregroundStyle(m.hasPrefix("Échec") ? .red : .green)
                    .padding(.horizontal, 12)
                    .onChange(of: quote.number) { _ in quoteEmailMessage = nil }
            }

            Divider()

            Form {
                Section("Client") {
                    PartySection(party: $quote.buyer, role: .buyer, locked: isLocked)
                }
                Section("Validité") {
                    DatePicker("Valable jusqu'au", selection: $quote.validUntil, displayedComponents: .date)
                        .disabled(isLocked)
                }
                Section("Lignes") {
                    ForEach($quote.lines) { $line in
                        HStack {
                            TextField("Désignation", text: $line.name).disabled(isLocked)
                            TextField("Qté", value: $line.quantity, format: .decimalInput).frame(width: 50).disabled(isLocked)
                            TextField("Prix U.", value: $line.unitPrice, format: .decimalInput).frame(width: 70).disabled(isLocked)
                            // Un devis n'affiche pas de sélecteur de catégorie TVA (il n'émet pas de XML),
                            // mais toInvoice()/toOrder() recopient les lignes telles quelles : la catégorie
                            // suit donc le taux (`editedVATRate` : S, ou E à 0 %, dont le motif se saisit
                            // dans la facture ou la commande). Sans ce recalage, une catégorie laissée par
                            // un ancien taux à 0 % suivait la ligne repassée à taux plein, rejetée par le
                            // validateur EN16931 (BR-Z-05/BR-Z-09).
                            TextField("TVA %", value: $line.editedVATRate, format: .decimalInput).frame(width: 50).disabled(isLocked)
                            Text(String(format: "%.2f", line.lineTotal)).foregroundStyle(.secondary).frame(width: 70)
                        }
                    }
                    .onDelete { idx in quote.lines.remove(atOffsets: idx) }
                    if !isLocked {
                        Button {
                            quote.lines.append(InvoiceLine(name: "", quantity: 1, unitPrice: 0, vatRate: 20))
                        } label: { Label("Ajouter une ligne", systemImage: "plus") }
                    }
                }
                Section("Notes") {
                    TextEditor(text: Binding(get: { quote.notes ?? "" }, set: { quote.notes = $0.isEmpty ? nil : $0 }))
                        .frame(height: 60)
                        .disabled(isLocked)
                }
                Section {
                    AttachmentsAndCommentSection(attachments: $quote.attachments, internalComment: $quote.internalComment, locked: isLocked)
                }
                Section {
                    HStack {
                        Text("Total HT")
                        Spacer()
                        Text(String(format: "%.2f %@", quote.lineTotal, quote.currency))
                    }
                    HStack {
                        Text("TVA")
                        Spacer()
                        Text(String(format: "%.2f %@", quote.taxTotal, quote.currency))
                    }
                    HStack {
                        Text("Total TTC").bold()
                        Spacer()
                        Text(String(format: "%.2f %@", quote.grandTotal, quote.currency)).bold()
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    private func sendQuoteEmail() {
        guard let recipient = quote.buyer.contactEmail, !recipient.isEmpty else {
            quoteEmailMessage = "Échec envoi : aucune adresse email cliente renseignée."
            return
        }
        let credentials = smtpSettings.credentials(for: quote.companyID)
        guard credentials.isConfigured else {
            quoteEmailMessage = "Échec envoi : envoi d'email non configuré (Réglages)."
            return
        }
        let template = emailTemplateStore.template(for: .quoteSent, companyID: quote.companyID)
        let email = EmailComposer.compose(template: template, variables: [
            "numero": quote.number,
            "client": quote.buyer.name,
            "societe": quote.seller.name,
            "montant": String(format: "%.2f %@", quote.grandTotal, quote.currency),
            "date": quote.validUntil.formatted(.dateTime.day().month().year())
        ])
        sendingQuoteEmail = true
        quoteEmailMessage = nil
        Task {
            do {
                try await SMTPService().send(to: recipient, subject: email.subject, body: email.body, credentials: credentials)
                quoteEmailMessage = "Devis envoyé à \(recipient)."
            } catch {
                quoteEmailMessage = "Échec envoi : \(error.localizedDescription)"
            }
            sendingQuoteEmail = false
        }
    }
}
