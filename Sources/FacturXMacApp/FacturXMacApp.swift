import SwiftUI
import FacturXCore
import AppKit
import UniformTypeIdentifiers

@main
struct FacturXMacApp: App {
    @StateObject private var store = InvoiceStore.shared
    @StateObject private var directory = PartyDirectory.shared
    @StateObject private var chorusSettings = ChorusProSettings.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Factur-X") {
            RootView()
                .environmentObject(store)
                .environmentObject(directory)
                .environmentObject(chorusSettings)
                .frame(minWidth: 980, minHeight: 620)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        NSApp.activate(ignoringOtherApps: true)
                        if let window = NSApp.windows.first {
                            window.makeKeyAndOrderFront(nil)
                        }
                    }
                }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Nouvelle facture") {
                    NotificationCenter.default.post(name: .newInvoiceRequested, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let newInvoiceRequested = Notification.Name("newInvoiceRequested")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
    }
}

enum RootTab: String, CaseIterable, Identifiable {
    case invoices = "Factures"
    case directory = "Annuaire"
    var id: String { rawValue }
}

struct RootView: View {
    @EnvironmentObject var store: InvoiceStore
    @State private var tab: RootTab = .invoices
    @State private var selectedID: UUID?
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $tab) {
                    ForEach(RootTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                Spacer()
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Réglages")
            }
            .padding(8)

            switch tab {
            case .invoices:
                InvoicesTabView(selectedID: $selectedID)
            case .directory:
                DirectoryView()
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .frame(minWidth: 720, minHeight: 640)
        }
        .onReceive(NotificationCenter.default.publisher(for: .newInvoiceRequested)) { _ in
            tab = .invoices
            let draft = store.newDraft()
            store.upsert(draft)
            selectedID = draft.id
        }
    }
}

struct InvoicesTabView: View {
    @EnvironmentObject var store: InvoiceStore
    @Binding var selectedID: UUID?
    @State private var query = ""

    var filteredInvoices: [Invoice] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return store.invoices }
        return store.invoices.filter { invoice in
            invoice.number.lowercased().contains(q)
                || invoice.buyer.name.lowercased().contains(q)
                || (invoice.buyer.siren ?? "").lowercased().contains(q)
                || (invoice.seller.name.lowercased()).contains(q)
        }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack {
                    Button {
                        let draft = store.newDraft()
                        store.upsert(draft)
                        selectedID = draft.id
                    } label: {
                        Label("Nouvelle", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 4)

                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Rechercher (numéro, client, SIREN…)", text: $query)
                        .textFieldStyle(.plain)
                        .onSubmit { }
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 12).padding(.vertical, 8)

                List(selection: $selectedID) {
                    ForEach(filteredInvoices) { invoice in
                        VStack(alignment: .leading) {
                            Text(invoice.number).font(.headline)
                            Text("\(invoice.buyer.name.isEmpty ? "Sans client" : invoice.buyer.name)")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(String(format: "%.2f %@ TTC", invoice.grandTotal, invoice.currency))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .tag(invoice.id)
                    }
                    .onDelete { idx in
                        let toRemove = idx.compactMap { i in
                            i < filteredInvoices.count ? filteredInvoices[i] : nil
                        }
                        for inv in toRemove {
                            store.invoices.removeAll { $0.id == inv.id }
                        }
                        store.save()
                    }
                }
            }
            .navigationTitle("Factures")
        } detail: {
            if let id = selectedID,
               store.invoices.contains(where: { $0.id == id }) {
                InvoiceEditorView(invoice: binding(for: id))
            } else {
                Text("Sélectionnez ou créez une facture")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func binding(for id: UUID) -> Binding<Invoice> {
        Binding(
            get: { store.invoices.first(where: { $0.id == id }) ?? Invoice(number: "", seller: store.myCompany, buyer: .init(name: "", street: "", postcode: "", city: "")) },
            set: { newValue in
                if let idx = store.invoices.firstIndex(where: { $0.id == id }) {
                    store.invoices[idx] = newValue
                    store.save()
                }
            }
        )
    }
}

struct InvoiceEditorView: View {
    @Binding var invoice: Invoice
    @EnvironmentObject var store: InvoiceStore
    @State private var exportError: String?
    @State private var exportedURL: URL?
    @State private var validation: FacturXValidationResult?
    @State private var showValidation = false

    private var hasMandatoryWarnings: Bool {
        let s = invoice.seller
        let b = invoice.buyer
        let sellerOk = !s.name.trimmingCharacters(in: .whitespaces).isEmpty
            && !s.country.trimmingCharacters(in: .whitespaces).isEmpty
            && ((s.siren ?? "").trimmingCharacters(in: .whitespaces).count >= 9
                || (s.endpointID ?? "").trimmingCharacters(in: .whitespaces).count >= 9)
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Édition : \(invoice.number)").font(.title2.bold())
                    Spacer()
                    Button("Valider") { runValidation() }
                        .buttonStyle(.bordered)
                    Button("Exporter XML") { exportXML() }
                        .buttonStyle(.bordered)
                    Button("Générer le Factur-X") { export() }
                        .buttonStyle(.borderedProminent)
                }

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

                if hasMandatoryWarnings {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Données obligatoires pour la conformité Factur-X", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption.bold())
                                .foregroundStyle(.orange)
                            Text("Émetteur et destinataire : nom, pays (code ISO 2 lettres), SIREN ou identifiant électronique (BT-49/34), n° TVA si applicable.").font(.caption)
                            Text("Lignes : désignation non vide, quantité positive, prix unitaire, taux TVA, unité (code UN/ECE ex. C62, DAY, HUR).").font(.caption)
                            Text("En-tête : numéro de facture, date, échéance, devise (EUR), mode de facturation (BT-23).").font(.caption)
                            Text("Mentions légales FR : frais de recouvrement (PMT), pénalités de retard (PMD), escompte (AAB) — pré-remplies, modifiables.").font(.caption)
                            Text("Paiement : IBAN et BIC si virement SEPA.").font(.caption)
                        }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if showValidation, let v = validation {
                    validationPanel(v)
                }

                GroupBox("En-tête") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            LabeledContent {
                                TextField("", text: $invoice.number).frame(width: 160)
                            } label: {
                                Text("Numéro *").foregroundColor(.red)
                            }
                            Picker("Type", selection: $invoice.type) {
                                ForEach(InvoiceTypeCode.allCases, id: \.self) { Text($0.label).tag($0) }
                            }.frame(width: 260)
                        }
                        HStack {
                            DatePicker("Date", selection: $invoice.issueDate, displayedComponents: .date)
                            DatePicker("Échéance", selection: $invoice.dueDate, displayedComponents: .date)
                        }
                        HStack {
                            Picker("Profil Factur-X", selection: $invoice.profile) {
                                ForEach(FacturXProfile.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                            TextField("Devise", text: $invoice.currency).frame(width: 60)
                            TextField("Référence acheteur", text: Binding($invoice.buyerReference, replacingNilWith: ""))
                        }
                        HStack {
                            Picker("Mode facturation (BT-23)", selection: $invoice.billingMode) {
                                ForEach(BillingMode.allCases, id: \.self) { Text($0.label).tag($0) }
                            }.frame(width: 320)
                        }
                    }.padding(8)
                }

                GroupBox("Émetteur (vous)") {
                    PartySection(party: $invoice.seller, role: .seller)
                }

                GroupBox("Destinataire") {
                    PartySection(party: $invoice.buyer, role: .buyer)
                }

                GroupBox("Lignes") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach($invoice.lines) { $line in
                            HStack {
                                TextField("Désignation *", text: $line.name).frame(minWidth: 220)
                                DoubleField("Qté", value: $line.quantity, format: .number)
                                TextField("Unité", text: $line.unit).frame(width: 50)
                                DoubleField("P.U. HT", value: $line.unitPrice, format: .number)
                                DoubleField("TVA %", value: $line.vatRate, format: .number)
                                Text(String(format: "%.2f", line.lineTotal))
                                    .monospacedDigit().frame(width: 80, alignment: .trailing)
                                Button { invoice.lines.removeAll { $0.id == line.id } } label: {
                                    Image(systemName: "minus.circle")
                                }
                            }
                        }
                        Button {
                            invoice.lines.append(InvoiceLine(name: "", quantity: 1, unitPrice: 0, vatRate: invoice.lines.last?.vatRate ?? 20))
                        } label: { Label("Ajouter une ligne", systemImage: "plus") }
                    }.padding(8)
                }

                GroupBox("Paiement") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("IBAN", text: Binding($invoice.paymentIBAN, replacingNilWith: ""))
                            TextField("BIC", text: Binding($invoice.paymentBIC, replacingNilWith: ""))
                        }
                        TextField("Conditions de paiement", text: Binding($invoice.paymentTerms, replacingNilWith: ""))
                        TextField("Référence commande", text: Binding($invoice.purchaseOrderRef, replacingNilWith: ""))
                    }.padding(8)
                }

                GroupBox("Mentions légales (FR)") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Frais de recouvrement (SubjectCode PMT) :").font(.caption.bold())
                        TextField("Indemnité forfaitaire pour frais de recouvrement", text: $invoice.legalNotePMT)
                        Text("Pénalités de retard (SubjectCode PMD) :").font(.caption.bold())
                        TextField("Taux d'intérêt des pénalités de retard", text: $invoice.legalNotePMD)
                        Text("Escompte (SubjectCode AAB) :").font(.caption.bold())
                        TextField("Escompte pour paiement anticipé", text: $invoice.legalNoteAAB)
                        TextField("Notes libres", text: Binding($invoice.notes, replacingNilWith: ""))
                    }.padding(8)
                }

                GroupBox("Totaux") {
                    VStack(alignment: .trailing) {
                        row("Total HT", invoice.lineTotal)
                        ForEach(invoice.vatBreakdown, id: \.rate) { item in
                            row("TVA \(String(format: "%.0f%%", item.rate))", item.amount)
                        }
                        row("Total TTC", invoice.grandTotal, bold: true)
                    }.padding(8).frame(maxWidth: .infinity)
                }
            }.padding()
        }
    }

    private func row(_ label: String, _ value: Double, bold: Bool = false) -> some View {
        HStack {
            Text(label).font(bold ? .body.bold() : .body)
            Spacer()
            Text(String(format: "%.2f %@", value, invoice.currency))
                .font(bold ? .body.bold() : .body)
                .monospacedDigit()
        }.frame(width: 280)
    }

    private func export() {
        exportError = nil
        exportedURL = nil
        let preCheck = FacturXValidator().validate(invoice: invoice)
        if !preCheck.isValid {
            validation = preCheck
            showValidation = true
            exportError = "Validation échouée : \(preCheck.errors.count) erreur(s). Corrigez avant de générer."
            return
        }
        do {
            store.upsert(invoice)
            let data = try FacturXGenerator().generate(invoice: invoice)
            let postCheck = FacturXValidator().validate(pdf: data)
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
            panel.nameFieldStringValue = "facture-\(invoice.number).pdf"
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
        validation = FacturXValidator().validate(invoice: invoice)
        showValidation = true
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

    private func validationPanel(_ v: FacturXValidationResult) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    if v.isValid {
                        Label("Conforme", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Non conforme — \(v.errors.count) erreur(s)", systemImage: "xmark.seal.fill")
                            .foregroundStyle(.red)
                    }
                    Spacer()
                    Button { showValidation = false } label: {
                        Image(systemName: "xmark.circle")
                    }.buttonStyle(.plain)
                }
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

struct PartySection: View {
    enum Role {
        case seller, buyer
        var title: String { self == .seller ? "Émetteur" : "Destinataire" }
        var defaultKind: DirectoryEntryKind { self == .seller ? .fournisseur : .client }
    }

    @Binding var party: InvoiceParty
    let role: Role
    @EnvironmentObject var directory: PartyDirectory
    @State private var showPicker = false
    @State private var showSaveSheet = false
    @State private var saveName = ""
    @State private var pendingEntry: DirectoryEntry?
    @State private var duplicateMatches: [PartyDirectory.DuplicateMatch]?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                Spacer()
            }

            PartyEditorView(party: $party)
        }
        .padding(8)
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
                party = p
                showPicker = false
            }
        }
        .sheet(isPresented: $showSaveSheet) {
            VStack(spacing: 12) {
                Text("Enregistrer dans l'annuaire").font(.headline)
                TextField("Nom affiché", text: $saveName).frame(width: 320)
                HStack {
                    Button("Annuler") { showSaveSheet = false }
                        .keyboardShortcut(.cancelAction)
                    Button("Enregistrer") {
                        var p = party
                        p.name = saveName.trimmingCharacters(in: .whitespaces).isEmpty ? party.name : saveName
                        let entry = DirectoryEntry(kind: role.defaultKind, party: p)
                        let dup = directory.findDuplicates(of: entry)
                        if dup.isEmpty {
                            directory.upsert(entry)
                            showSaveSheet = false
                        } else {
                            pendingEntry = entry
                            duplicateMatches = dup
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
            }.padding(20)
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
}

struct PartyPickerSheet: View {
    let role: PartySection.Role
    let onPick: (DirectoryEntry) -> Void

    @EnvironmentObject var directory: PartyDirectory
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var creatingNew = false
    @State private var editingEntry: DirectoryEntry?

    var filtered: [DirectoryEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let roleKind = role.defaultKind
        let active = directory.entries.filter {
            !$0.isArchived && ($0.kind == roleKind || $0.kind == .both)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Annuaire — choisir \(role.title.lowercased())").font(.headline)
                Spacer()
                Button {
                    creatingNew = true
                } label: { Label("Nouveau", systemImage: "plus") }
                    .buttonStyle(.bordered)
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

struct DirectoryView: View {
    @EnvironmentObject var directory: PartyDirectory
    @State private var query = ""
    @State private var editingEntry: DirectoryEntry?
    @State private var creatingNew = false
    @State private var showArchived = false
    @State private var selectedEntry: DirectoryEntry?

    var filtered: [DirectoryEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let base = directory.entries.filter { showArchived || !$0.isArchived }
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.displayName.lowercased().contains(q)
                || ($0.party.siren ?? "").lowercased().contains(q)
                || ($0.party.vatNumber ?? "").lowercased().contains(q)
                || $0.party.city.lowercased().contains(q)
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
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
                    Spacer()
                    Toggle(isOn: $showArchived) {
                        Label("Archives", systemImage: "archivebox")
                    }
                    .toggleStyle(.checkbox)
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
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1)))
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
                                Text(entry.kind.label).font(.caption2)
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(.quaternary, in: Capsule())
                                if entry.isArchived {
                                    Label("Archive", systemImage: "archivebox")
                                        .font(.caption2)
                                        .padding(.horizontal, 6).padding(.vertical, 1)
                                        .background(Color.orange.opacity(0.2), in: Capsule())
                                }
                            }
                            Text(entry.party.fullAddressLine).font(.caption).foregroundStyle(.secondary)
                            if let sub = entry.subtitle.isEmpty ? nil : entry.subtitle {
                                Text(sub).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .tag(entry.id)
                        .contextMenu {
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
                        }
                    }
                    .frame(minWidth: 280)
                }

                DirectoryDetailView(
                    entry: selectedEntry,
                    onEdit: { entry in editingEntry = entry },
                    onArchive: { entry in
                        var e = entry
                        e.isArchived.toggle()
                        directory.upsert(e)
                        selectedEntry = e
                    },
                    onDelete: { entry in
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
            DirectoryEditorView(initialKind: .client) { newEntry in
                directory.upsert(newEntry)
                creatingNew = false
            }
        }
    }
}

struct DirectoryDetailView: View {
    let entry: DirectoryEntry?
    let onEdit: (DirectoryEntry) -> Void
    let onArchive: (DirectoryEntry) -> Void
    let onDelete: (DirectoryEntry) -> Void

    var body: some View {
        if let entry = entry {
            VStack(spacing: 0) {
                HStack {
                    Text(entry.displayName).font(.headline)
                    Spacer()
                    Button { onEdit(entry) } label: { Label("Modifier", systemImage: "pencil") }
                        .buttonStyle(.bordered)
                    Button { onArchive(entry) } label: {
                        Label(entry.isArchived ? "Désarchiver" : "Archiver",
                              systemImage: entry.isArchived ? "tray.and.arrow.up" : "archivebox")
                    }
                    .buttonStyle(.bordered)
                    Button(role: .destructive) { onDelete(entry) } label: { Label("Supprimer", systemImage: "trash") }
                        .buttonStyle(.bordered)
                }
                .padding(12)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        detailRow("Type", entry.kind.label)
                        if let s = entry.party.siren, !s.isEmpty { detailRow("SIREN", s) }
                        if let v = entry.party.vatNumber, !v.isEmpty { detailRow("N° TVA", v) }
                        if let e = entry.party.endpointID, !e.isEmpty {
                            detailRow("Ident. élec. (BT-49/34)", e)
                        }
                        if !entry.party.street.isEmpty || !entry.party.city.isEmpty {
                            detailRow("Adresse", entry.party.fullAddressLine)
                        }
                        if let cn = entry.party.contactName, !cn.isEmpty { detailRow("Contact", cn) }
                        if let ce = entry.party.contactEmail, !ce.isEmpty { detailRow("Email", ce) }
                        if let cp = entry.party.contactPhone, !cp.isEmpty { detailRow("Téléphone", cp) }

                        if !entry.routingAddresses.isEmpty {
                            Divider()
                            Text("Adresses de facturation électronique").font(.caption.bold())
                            ForEach(entry.routingAddresses) { addr in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(addr.format.label).font(.caption.bold())
                                        Text(addr.composedAddress).font(.system(.caption, design: .monospaced))
                                        if let lbl = addr.label, !lbl.isEmpty {
                                            Text(lbl).font(.caption).foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if addr.isDefault {
                                        Text("défaut").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(Color.accentColor.opacity(0.2), in: Capsule())
                                    }
                                    if !addr.isActive {
                                        Text("inactive").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(Color.gray.opacity(0.2), in: Capsule())
                                    }
                                }
                                .padding(6)
                                .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.08)))
                            }
                        }

                        if let note = entry.note, !note.isEmpty {
                            Divider()
                            Text("Note").font(.caption.bold())
                            Text(note).font(.caption).foregroundStyle(.secondary)
                        }

                        if entry.isArchived {
                            Label("Tiers archivé", systemImage: "archivebox")
                                .font(.caption.bold()).foregroundStyle(.orange)
                        }
                    }.padding(12)
                }
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
            Text(label).font(.caption.bold()).frame(width: 140, alignment: .leading)
            Text(value).font(.caption)
            Spacer()
        }
    }
}
struct DirectoryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var directory: PartyDirectory
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

    init(initialKind: DirectoryEntryKind, onSave: @escaping (DirectoryEntry) -> Void) {
        _entry = State(initialValue: DirectoryEntry(kind: initialKind, party: InvoiceParty(name: "", street: "", postcode: "", city: "")))
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

            Picker("Type", selection: $entry.kind) {
                ForEach(DirectoryEntryKind.allCases, id: \.self) { Text($0.label).tag($0) }
            }.pickerStyle(.segmented)

            GroupBox("Identité et adresse") {
                PartyEditorView(party: $entry.party, routingAddresses: $entry.routingAddresses)
            }

            TextField("Note (optionnel)", text: Binding($entry.note, replacingNilWith: ""))
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 560)
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
            Toggle("Adresse par défaut", isOn: $draft.isDefault)
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

struct SettingsView: View {
    @EnvironmentObject var chorusSettings: ChorusProSettings
    @EnvironmentObject var store: InvoiceStore
    @EnvironmentObject var directory: PartyDirectory
    @State private var testMessage: String?
    @State private var testing = false
    @State private var dinumExpanded = true
    @State private var pisteExpanded = false
    @State private var sellerExpanded = true
    @State private var showSellerPicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Réglages").font(.title2.bold())

                DisclosureGroup(isExpanded: $sellerExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Cette entreprise est utilisée comme émetteur par défaut pour chaque nouvelle facture.")
                            .font(.caption).foregroundStyle(.secondary)
                        if !store.myCompany.name.trimmingCharacters(in: .whitespaces).isEmpty {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(store.myCompany.name).font(.body.weight(.semibold))
                                    if let s = store.myCompany.siren, !s.isEmpty { Text("SIREN : \(s)").font(.caption).foregroundStyle(.secondary) }
                                    if let v = store.myCompany.vatNumber, !v.isEmpty { Text("TVA : \(v)").font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                Button {
                                    showSellerPicker = true
                                } label: { Label("Choisir dans l'annuaire", systemImage: "person.crop.circle.badge.plus") }
                                    .buttonStyle(.bordered)
                            }
                        } else {
                            Button {
                                showSellerPicker = true
                            } label: { Label("Choisir dans l'annuaire", systemImage: "person.crop.circle.badge.plus") }
                                .buttonStyle(.bordered)
                        }
                        Divider()
                        PartyEditorView(party: $store.myCompany, showWebButton: false)
                        Button {
                            store.save()
                        } label: { Label("Enregistrer l'émetteur par défaut", systemImage: "checkmark.circle") }
                            .buttonStyle(.borderedProminent)
                    }.padding(8)
                } label: {
                    Label("Émetteur par défaut", systemImage: "building.2")
                        .font(.headline)
                }

                DisclosureGroup(isExpanded: $dinumExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("L'API recherche-entreprises.api.gouv.fr (DINUM) pré-remplit la désignation et l'adresse postale d'un tiers à partir d'un SIREN, SIRET ou nom. Gratuite, publique, sans compte ni jeton. Ne donne pas l'adresse de routage PPF.")
                            .font(.caption).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Endpoint : https://recherche-entreprises.api.gouv.fr/search?q=...").font(.caption2).foregroundStyle(.tertiary)
                            Text("Formats de requête : q=siren:XXXXXXXXX, q=siret:XXXXXXXXXXXXXX, ou q=nom").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }.padding(8)
                } label: {
                    Label("Recherche entreprises (DINUM — gratuit)", systemImage: "magnifyingglass.circle")
                        .font(.headline)
                }

                DisclosureGroup(isExpanded: $pisteExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Non fonctionnel sans statut Plateforme Agréée (PA)", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.bold()).foregroundStyle(.orange)
                        Text("L'API Annuaire (ppf.annuaire) est réservée aux Plateformes Agréées approuvées. Sans ce statut, la recherche via PISTE ne renvoie pas d'adresse de routage. Utilisez l'Annuaire web ou l'enrichissement DINUM à la place.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Renseignez les identifiants de votre application PISTE (client_id / client_secret) et le compte technique Chorus Pro requis pour appeler l'API.")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Text("Client ID").frame(width: 100, alignment: .leading)
                            TextField("Client ID", text: $chorusSettings.credentials.clientID)
                        }
                        HStack {
                            Text("Client Secret").frame(width: 100, alignment: .leading)
                            SecureField("Client Secret", text: $chorusSettings.credentials.clientSecret)
                        }
                        HStack {
                            Text("Scope").frame(width: 100, alignment: .leading)
                            TextField("openid", text: $chorusSettings.credentials.scope)
                        }
                        HStack {
                            Text("URL Token").frame(width: 100, alignment: .leading)
                            TextField("URL Token", text: $chorusSettings.credentials.tokenURL)
                        }
                        HStack {
                            Text("Base API").frame(width: 100, alignment: .leading)
                            TextField("Base API", text: $chorusSettings.credentials.apiBaseURL)
                        }
                        Divider()
                        Text("Compte technique Chorus Pro (en-tête cpro-account)").font(.caption.bold())
                        HStack {
                            Text("Login tech.").frame(width: 100, alignment: .leading)
                            TextField("login technique", text: $chorusSettings.credentials.techLogin)
                        }
                        HStack {
                            Text("Mot de passe").frame(width: 100, alignment: .leading)
                            SecureField("mot de passe technique", text: $chorusSettings.credentials.techPassword)
                        }
                        HStack {
                            Button {
                                chorusSettings.save()
                            } label: { Label("Enregistrer", systemImage: "checkmark.circle") }
                                .buttonStyle(.borderedProminent)
                            Button {
                                testing = true
                                testMessage = nil
                                Task {
                                    do {
                                        let service = ChorusProService()
                                        _ = try await service.fetchToken(credentials: chorusSettings.credentials)
                                        testMessage = "Connexion réussie — jeton obtenu."
                                    } catch {
                                        testMessage = "Échec : \(error.localizedDescription)"
                                    }
                                    testing = false
                                }
                            } label: { Label("Tester la connexion", systemImage: "antenna.radiowaves.left.and.right") }
                                .buttonStyle(.bordered)
                                .disabled(testing || !chorusSettings.credentials.isConfigured)
                            Spacer()
                        }
                        if let m = testMessage {
                            Text(m).font(.caption).foregroundStyle(m.hasPrefix("Échec") ? .red : .green)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sandbox (tests)").font(.caption2.bold())
                            Text("Token : https://sandbox-oauth.piste.gouv.fr/api/oauth/token").font(.caption2).foregroundStyle(.tertiary)
                            Text("API : https://sandbox-api.piste.gouv.fr").font(.caption2).foregroundStyle(.tertiary)
                            Text("Production").font(.caption2.bold())
                            Text("Token : https://oauth.piste.gouv.fr/api/oauth/token").font(.caption2).foregroundStyle(.tertiary)
                            Text("API : https://api.piste.gouv.fr").font(.caption2).foregroundStyle(.tertiary)
                            Text("Scope par défaut : openid. L'API Annuaire (ppf.annuaire) est réservée aux Plateformes Agréées approuvées — sinon utiliser l'Annuaire web. L'API Structures (cpro.structures) renvoie dénomination + statut sans l'adresse de routage.").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }.padding(8)
                } label: {
                    Label("Annuaire Chorus Pro (PISTE)", systemImage: "network")
                        .font(.headline)
                }

                Spacer()
            }.padding()
        }
        .sheet(isPresented: $showSellerPicker) {
            PartyPickerSheet(role: .seller) { selected in
                var p = selected.party
                if let routing = selected.defaultRoutingAddress, routing.isActive {
                    let composed = routing.composedAddress.trimmingCharacters(in: .whitespaces)
                    if !composed.isEmpty {
                        p.endpointID = composed
                        p.endpointSchemeID = "0225"
                    }
                }
                store.myCompany = p
                store.save()
                showSellerPicker = false
            }
        }
    }
}

struct ChorusProSearchSheet: View {
    @EnvironmentObject var chorusSettings: ChorusProSettings
    @Environment(\.dismiss) private var dismiss
    @State private var query: String
    @State private var results: [ChorusProResult] = []
    @State private var searching = false
    @State private var error: String?
    let onPick: (InvoiceParty) -> Void

    init(initialQuery: String, onPick: @escaping (InvoiceParty) -> Void) {
        _query = State(initialValue: initialQuery)
        self.onPick = onPick
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Rechercher dans l'annuaire Chorus Pro").font(.headline)
                Spacer()
                Button {
                    if let url = URL(string: "https://facturation.chorus-pro.gouv.fr/annuaire/") {
                        NSWorkspace.shared.open(url)
                    }
                } label: { Label("Annuaire web", systemImage: "safari") }
                    .buttonStyle(.bordered)
                Button("Fermer") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(12)

            HStack {
                TextField("SIRET ou SIREN", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { runSearch() }
                Button { runSearch() } label: { Label("Rechercher", systemImage: "magnifyingglass") }
                    .buttonStyle(.borderedProminent)
                    .disabled(searching || query.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12).padding(.bottom, 8)

            if !chorusSettings.credentials.isConfigured {
                Text("Identifiants PISTE non configurés. Ouvrez l'onglet Réglages.")
                    .font(.caption).foregroundStyle(.orange).padding(12)
            }

            if searching {
                HStack { Spacer(); ProgressView(); Spacer() }.padding()
            } else if let err = error {
                Text(err).font(.caption).foregroundStyle(.red).padding(12)
            } else {
                Divider()
                if results.isEmpty {
                    Text("Saisissez un SIRET et lancez la recherche.")
                        .foregroundStyle(.secondary).padding()
                } else {
                    List {
                        ForEach(results) { r in
                            Button {
                                onPick(r.toInvoiceParty())
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(r.denomination ?? "(sans dénomination)").font(.body.weight(.medium))
                                        Text(r.displaySubtitle).font(.caption).foregroundStyle(.secondary)
                                        if let addr = r.addressLine, !addr.isEmpty {
                                            Text(addr).font(.caption2).foregroundStyle(.tertiary)
                                        }
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
            }
            Spacer(minLength: 0)
        }
        .frame(minWidth: 520, minHeight: 460)
    }

    private func runSearch() {
        guard chorusSettings.credentials.isConfigured else {
            error = "Identifiants PISTE non configurés."
            return
        }
        searching = true
        error = nil
        results = []
        Task {
            do {
                let r = try await ChorusProService().searchRecipient(
                    siretOrSiren: query,
                    credentials: chorusSettings.credentials
                )
                results = r
                if r.isEmpty { error = "Aucun résultat." }
            } catch let e as ChorusProError {
                self.error = e.errorDescription
            } catch {
                self.error = error.localizedDescription
            }
            searching = false
        }
    }
}

struct PartyEditorView: View {
    @Binding var party: InvoiceParty
    @Binding var routingAddresses: [PartyRoutingAddress]
    var showWebButton: Bool
    @State private var showRoutingEditor = false
    @State private var editingAddress: PartyRoutingAddress?
    @State private var dinumResults: [SireneResult] = []
    @State private var dinumLoading = false
    @State private var dinumError: String?
    @State private var lastSearchKey: String = ""

    init(party: Binding<InvoiceParty>, routingAddresses: Binding<[PartyRoutingAddress]>? = nil, showWebButton: Bool = true) {
        self._party = party
        self.showWebButton = showWebButton
        if let ra = routingAddresses {
            self._routingAddresses = ra
        } else {
            self._routingAddresses = .constant([])
        }
    }

    private var star: some View { Text(" *").foregroundColor(.red) }

    private var searchTrigger: String {
        "\((party.name.trimmingCharacters(in: .whitespaces)))|\((party.siren ?? ""))"
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
            TextField("Adresse", text: $party.street)
            HStack {
                TextField("Code postal", text: $party.postcode)
                TextField("Ville", text: $party.city)
            }
            HStack {
                Text("Pays").font(.caption); star
                TextField("Pays (ex. FR)", text: $party.country).frame(width: 60)
            }
            HStack {
                Text("SIREN").font(.caption); star
                TextField("SIREN", text: Binding($party.siren, replacingNilWith: ""))
                    .onChange(of: party.siren) { _ in scheduleDinumSearch() }
                TextField("N° TVA", text: Binding($party.vatNumber, replacingNilWith: ""))
            }
            HStack {
                Text("Ident. élec. (BT-49/34)").font(.caption)
                TextField("Auto depuis SIREN si vide", text: Binding($party.endpointID, replacingNilWith: ""))
                TextField("Scheme", text: $party.endpointSchemeID).frame(width: 100)
            }
            HStack {
                TextField("Contact", text: Binding($party.contactName, replacingNilWith: ""))
                TextField("Email", text: Binding($party.contactEmail, replacingNilWith: ""))
                TextField("Téléphone", text: Binding($party.contactPhone, replacingNilWith: ""))
            }
            Button {
                showRoutingEditor = true
            } label: {
                Label("Adresses de facturation électronique", systemImage: "envelope.badge")
            }
            .buttonStyle(.bordered)
            if !routingAddresses.isEmpty {
                ForEach(routingAddresses) { addr in
                    HStack(spacing: 8) {
                        Text(addr.format.label).font(.caption.bold())
                        Text(addr.composedAddress).font(.system(.caption, design: .monospaced))
                        if addr.isDefault {
                            Text("défaut").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.2), in: Capsule())
                        }
                        Spacer()
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
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.08)))
                }
            }
            if !dinumResults.isEmpty {
                Divider()
                Text("Suggestions (DINUM)").font(.caption.bold())
                ForEach(dinumResults, id: \.self) { r in
                    Button {
                        party = r.merged(into: party)
                        dinumResults = []
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

struct RoutingAddressQuickEditor: View {
    @Environment(\.dismiss) private var dismiss
    let siren: String
    @Binding var addresses: [PartyRoutingAddress]
    @State private var editing: PartyRoutingAddress?
    @State private var showForm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Adresses de facturation électronique").font(.headline)
            Text("Adresses de routage Chorus Pro (BT-49/BT-34). Une seule est marquée par défaut et s'applique à la facture.")
                .font(.caption).foregroundStyle(.secondary)
            if addresses.isEmpty {
                Text("Aucune adresse. Cliquez sur « Ajouter » pour créer une adresse vide.")
                    .font(.caption).foregroundColor(.secondary)
            } else {
                ForEach(addresses) { addr in
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(addr.format.label).font(.caption.bold())
                            Text(addr.composedAddress).font(.system(.caption, design: .monospaced))
                            if let lbl = addr.label, !lbl.isEmpty {
                                Text(lbl).font(.caption).foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        if addr.isDefault {
                            Text("défaut").font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.2), in: Capsule())
                        }
                        if !addr.isActive {
                            Text("inactive").font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.gray.opacity(0.2), in: Capsule())
                        }
                        Button { editing = addr; showForm = true } label: { Image(systemName: "pencil") }
                            .buttonStyle(.borderless)
                        Button(role: .destructive) {
                            addresses.removeAll { $0.id == addr.id }
                            if addresses.allSatisfy({ !$0.isDefault }), !addresses.isEmpty {
                                addresses[0].isDefault = true
                            }
                        } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
                }
            }
            Button {
                editing = PartyRoutingAddress(siren: siren)
                showForm = true
            } label: { Label("Ajouter une adresse", systemImage: "plus.circle") }
                .buttonStyle(.bordered)
            HStack {
                Spacer()
                Button("Fermer") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(16).frame(minWidth: 480, minHeight: 360)
        .sheet(isPresented: $showForm) {
            if let addr = editing {
                RoutingAddressFormView(addresses: $addresses, editing: addr)
            }
        }
    }
}
struct DoubleField: View {
    let label: String
    @Binding var value: Double
    let format: FloatingPointFormatStyle<Double>

    init(_ label: String, value: Binding<Double>, format: FloatingPointFormatStyle<Double>) {
        self.label = label
        self._value = value
        self.format = format
    }

    var body: some View {
        HStack {
            Text(label).font(.caption)
            TextField(label, value: $value, format: format).frame(width: 80)
        }
    }
}

extension Binding {
    init(_ source: Binding<Value?>, replacingNilWith nilValue: Value) {
        self.init(
            get: { source.wrappedValue ?? nilValue },
            set: { source.wrappedValue = $0 }
        )
    }
}
