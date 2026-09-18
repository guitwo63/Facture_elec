import SwiftUI
import FacturXCore

enum PurchaseInvoiceFilterField: String, CaseIterable, Hashable {
    case none = "Aucun"
    case number = "N° facture"
    case supplierName = "Fournisseur"
    case supplierSiren = "SIREN fournisseur"
}

/// Pendant de `InvoicesTabView` côté achats — même forme (recherche, filtre statut,
/// `HSplitView` liste+détail), sans les actions spécifiques ventes qui ne s'appliquent pas
/// ici (depuis commande/devis, facture guidée, export) et sans le scan papier (hors
/// périmètre de cette première version — voir le plan). `Invoice`/`InvoiceParty`/
/// `InvoiceLine` restent réutilisés tels quels via `PurchaseInvoice`.
struct PurchasesTabView: View {
    @EnvironmentObject var store: PurchaseInvoiceStore
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var directory: PartyDirectory
    @Binding var selectedID: UUID?
    @State private var query = ""
    @State private var statusFilter: PurchaseInvoiceStatus? = nil

    var filteredInvoices: [PurchaseInvoice] {
        var result = store.invoices
        if let scope = auth.visiblePurchaseInvoiceCompanyIDs(for: auth.currentUser) {
            result = result.filter { rec in
                if let cid = rec.invoice.companyID { return scope.contains(cid) }
                return false
            }
        }
        if let sf = statusFilter {
            result = result.filter { $0.status == sf }
        }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return result }
        return result.filter { rec in
            rec.invoice.number.lowercased().contains(q)
                || rec.invoice.seller.name.lowercased().contains(q)
                || (rec.invoice.seller.siren ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    Button {
                        let record = store.newManualEntry(directory: directory, companyID: defaultCompanyID())
                        store.upsert(record)
                        selectedID = record.id
                    } label: { Label("Nouvelle facture d'achat", systemImage: "plus") }
                        .buttonStyle(.borderedProminent)
                    Text("Achats").font(.title2.bold())
                    Picker("Statut", selection: $statusFilter) {
                        Text("Tous statuts").tag(PurchaseInvoiceStatus?.none)
                        ForEach(PurchaseInvoiceStatus.allCases, id: \.self) { s in
                            Label(s.label, systemImage: s.systemImage).tag(PurchaseInvoiceStatus?.some(s))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                    Spacer()
                }
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Rechercher (numéro, fournisseur, SIREN…)", text: $query)
                        .textFieldStyle(.plain)
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
            }
            .padding(12)

            Divider()

            HSplitView {
                if filteredInvoices.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray").font(.largeTitle).foregroundStyle(.secondary)
                        Text("Aucune facture d'achat.")
                            .foregroundStyle(.secondary)
                        Button("Nouvelle facture d'achat") {
                            let record = store.newManualEntry(directory: directory, companyID: defaultCompanyID())
                            store.upsert(record)
                            selectedID = record.id
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filteredInvoices, selection: Binding(
                        get: { selectedID },
                        set: { id in selectedID = id }
                    )) { record in
                        VStack(alignment: .leading) {
                            HStack {
                                Text(record.invoice.number.isEmpty ? "(sans numéro)" : record.invoice.number).font(.headline)
                                Spacer()
                                Text(record.invoice.issueDate, format: .dateTime.day().month().year())
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            HStack(spacing: 6) {
                                Image(systemName: record.status.systemImage)
                                    .foregroundColor(Color(hex: record.status.hexColor))
                                    .font(.caption2)
                                Text(record.status.label).font(.caption2)
                                    .foregroundColor(Color(hex: record.status.hexColor))
                                Spacer()
                            }
                            Text(record.invoice.seller.name.isEmpty ? "Sans fournisseur" : record.invoice.seller.name)
                                .font(.caption).foregroundStyle(.secondary)
                            Text(String(format: "%.2f %@ TTC", record.invoice.grandTotal, record.invoice.currency))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                store.delete(record)
                                if selectedID == record.id { selectedID = nil }
                            } label: { Label("Supprimer", systemImage: "trash") }
                        }
                    }
                    .frame(minWidth: 180, idealWidth: 230, maxWidth: 270)
                }

                if let id = selectedID,
                   filteredInvoices.contains(where: { $0.id == id }) {
                    PurchaseInvoiceEditorView(record: binding(for: id))
                        .frame(minWidth: 420)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass").font(.largeTitle).foregroundStyle(.secondary)
                        Text("Sélectionnez ou créez une facture d'achat")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onChange(of: filteredInvoices) { newList in
            if let id = selectedID, !newList.contains(where: { $0.id == id }) {
                selectedID = nil
            }
        }
    }

    private func binding(for id: UUID) -> Binding<PurchaseInvoice> {
        Binding(
            get: { store.invoices.first(where: { $0.id == id }) ?? store.newManualEntry(directory: directory) },
            set: { newValue in store.upsert(newValue) }
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
}

/// Pendant de `InvoiceEditorView` côté achats — même modèle de verrouillage
/// (isLocked/fieldLocked/adminConfirmedEdit), même structure de sections, mais sans les
/// fonctions ventes qui n'ont pas de sens ici (dépôt PDP, envoi email client, relance,
/// avoir/duplication, mentions légales d'émetteur). Dans cet incrément, seules les
/// transitions côté acheteur (draft→received→toValidate) sont actives ; les transitions
/// comptable sont visibles mais désactivées, câblées avec le retour SUPER PDP dans
/// l'incrément suivant.
struct PurchaseInvoiceEditorView: View {
    @Binding var record: PurchaseInvoice
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var purchaseInvoiceStatusStore: PurchaseInvoiceStatusStore
    @State private var isManuallyLocked = false
    @State private var adminConfirmedEdit = false
    @State private var showAdminEditConfirm = false

    private var invoice: Binding<Invoice> {
        Binding(get: { record.invoice }, set: { record.invoice = $0 })
    }

    private var isLocked: Bool { record.status.locksInvoice || isManuallyLocked }
    private var statusLocked: Bool { record.status.locksInvoice }
    private var isAdmin: Bool { auth.currentUser?.isAdmin ?? false }
    private var canActAsAcheteur: Bool { isAdmin || (auth.currentUser?.roles.contains(.acheteur) ?? false) }
    private var canActAsComptable: Bool { isAdmin || (auth.currentUser?.roles.contains(.comptable) ?? false) }

    /// Un admin peut modifier une facture d'achat verrouillée par son statut, mais
    /// seulement après confirmation explicite — même principe que côté ventes.
    private var fieldLocked: Bool {
        guard isLocked else { return false }
        if statusLocked { return !(isAdmin && adminConfirmedEdit) }
        return !isAdmin
    }

    private var configuredTransitions: [PurchaseInvoiceStatus] {
        purchaseInvoiceStatusStore.override(for: record.status).transitionCodes.compactMap { PurchaseInvoiceStatus(rawValue: $0) }
    }

    /// Transitions réservées au comptable (workflow de validation) — désactivées pour le
    /// moment, câblées avec le retour SUPER PDP dans le prochain incrément.
    private func requiresComptableWorkflow(_ s: PurchaseInvoiceStatus) -> Bool {
        [.validated, .disputed, .refused, .paid].contains(s)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(record.invoice.number.isEmpty ? "(sans numéro)" : record.invoice.number).font(.title2.bold())
                Text(record.invoice.issueDate, format: .dateTime.day().month().year())
                    .font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Image(systemName: record.status.systemImage)
                    Text(record.status.label)
                }
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Color(hex: record.status.hexColor)))
                if isLocked, isAdmin, !adminConfirmedEdit {
                    Button {
                        showAdminEditConfirm = true
                    } label: { Label("Modifier quand même", systemImage: "lock.open") }
                        .buttonStyle(.bordered)
                        .font(.caption)
                }
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // MARK: Transitions
                    HStack(spacing: 8) {
                        ForEach(configuredTransitions, id: \.self) { s in
                            let comptableOnly = requiresComptableWorkflow(s)
                            Button {
                                record.status = s
                            } label: {
                                Label(s.label, systemImage: s.systemImage)
                            }
                            .buttonStyle(ToolbarActionButtonStyle(tint: Color(hex: s.hexColor)))
                            .disabled(comptableOnly || (!canActAsAcheteur && !isAdmin))
                            .help(comptableOnly
                                  ? "Fait partie du workflow de validation comptable — pas encore actif dans cette version."
                                  : "Passer au statut « \(s.label) »")
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12).padding(.top, 8)

                    VStack(alignment: .leading, spacing: 16) {
                        GroupBox("En-tête") {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top, spacing: 24) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 3) {
                                            Text("Numéro fournisseur *").foregroundColor(.red)
                                            InfoBadge(text: "Le numéro de facture du fournisseur, tel quel — jamais généré par nous, contrairement à une facture de vente.")
                                        }
                                        TextField("", text: invoice.number).frame(width: 200)
                                            .disabled(fieldLocked)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Type").font(.caption)
                                        Picker("", selection: invoice.type) {
                                            ForEach(InvoiceTypeCode.allCases, id: \.self) { Text($0.label).tag($0) }
                                        }.labelsHidden().frame(width: 260)
                                        .disabled(fieldLocked)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Devise").font(.caption)
                                        NormRefPicker("", options: NormRefs.currencies, code: invoice.currency).labelsHidden().frame(width: 160)
                                            .disabled(fieldLocked)
                                    }
                                }
                                HStack(alignment: .top, spacing: 24) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Date facture").font(.caption)
                                        DatePicker("", selection: invoice.issueDate, displayedComponents: .date).labelsHidden()
                                            .disabled(fieldLocked)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Échéance").font(.caption)
                                        DatePicker("", selection: invoice.dueDate, displayedComponents: .date).labelsHidden()
                                            .disabled(fieldLocked)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Conditions de paiement").font(.caption)
                                        TextField("Ex. Paiement à 30 jours", text: Binding($record.invoice.paymentTerms, replacingNilWith: ""))
                                            .frame(width: 220)
                                            .disabled(fieldLocked)
                                    }
                                }
                                HStack(spacing: 3) {
                                    TextField("Référence de commande", text: Binding($record.invoice.purchaseOrderRef, replacingNilWith: ""))
                                        .frame(width: 260)
                                        .disabled(fieldLocked)
                                    InfoBadge(text: "Notre référence de commande auprès de ce fournisseur, si applicable.")
                                }
                                OptionalFieldsSection(fields: $record.invoice.optionalFields, location: .header, locked: fieldLocked)
                            }.padding(8)
                        }.lockable(fieldLocked)

                        GroupBox("Fournisseur") {
                            PurchasePartySection(party: Binding(get: { record.invoice.seller }, set: { record.invoice.seller = $0 }), role: .supplier, locked: fieldLocked)
                        }.lockable(fieldLocked)

                        GroupBox("Notre société") {
                            PurchasePartySection(party: Binding(get: { record.invoice.buyer }, set: { record.invoice.buyer = $0 }), role: .buyer, locked: fieldLocked)
                        }.lockable(fieldLocked)

                        GroupBox("Lignes") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach($record.invoice.lines) { $line in
                                    HStack {
                                        TextField("Désignation *", text: $line.name).frame(minWidth: 220)
                                        DoubleField("Qté", value: $line.quantity, format: .number)
                                        NormRefPicker("Unité", options: NormRefs.units, code: $line.unit).frame(width: 180)
                                        DoubleField("P.U. HT", value: $line.unitPrice, format: .number)
                                        VATRatePicker(rate: $line.vatRate)
                                        Text(String(format: "%.2f", line.lineTotal))
                                            .monospacedDigit().frame(width: 80, alignment: .trailing)
                                        Button {
                                            DispatchQueue.main.async {
                                                record.invoice.lines.removeAll { $0.id == line.id }
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
                                            Picker("", selection: $line.vatCategory) {
                                                ForEach(VATCategory.allCases, id: \.self) { cat in
                                                    Text("\(cat.rawValue) — \(cat.label)").tag(cat)
                                                }
                                            }.labelsHidden().frame(width: 210)
                                            if line.vatCategory.requiresExemptionReason {
                                                TextField("Motif d'exonération", text: Binding($line.vatExemptionReason, replacingNilWith: ""))
                                                    .frame(minWidth: 280)
                                            }
                                        }.padding(.leading, 4)
                                    }
                                    OptionalFieldsSection(fields: $line.optionalFields, location: .line, locked: fieldLocked)
                                        .padding(.leading, 4)
                                }
                                Button {
                                    record.invoice.lines.append(InvoiceLine(name: "", quantity: 1, unitPrice: 0, vatRate: record.invoice.lines.last?.vatRate ?? 20))
                                } label: { Label("Ajouter une ligne", systemImage: "plus") }
                            }.padding(8)
                        }.lockable(fieldLocked)

                        HStack {
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(String(format: "Total HT : %.2f %@", record.invoice.lineTotal, record.invoice.currency)).font(.callout)
                                Text(String(format: "TVA : %.2f %@", record.invoice.taxTotal, record.invoice.currency)).font(.callout)
                                Text(String(format: "Total TTC : %.2f %@", record.invoice.grandTotal, record.invoice.currency)).font(.title3.bold())
                            }
                        }

                        AttachmentsAndCommentSection(attachments: $record.invoice.attachments, internalComment: $record.invoice.internalComment, locked: fieldLocked)
                    }.padding()
                }
            }
        }
        .alert("Modifier cette facture d'achat verrouillée ?", isPresented: $showAdminEditConfirm) {
            Button("Annuler", role: .cancel) { }
            Button("Modifier quand même") { adminConfirmedEdit = true }
        } message: {
            Text("Cette facture d'achat a le statut « \(record.status.label) ». La modifier peut créer une incohérence comptable. Continuer ?")
        }
        .onChange(of: record.invoice.number) { _ in adminConfirmedEdit = false }
    }
}
