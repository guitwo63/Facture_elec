import SwiftUI
import FacturXCore
import AppKit

@main
struct FacturXMacApp: App {
    @StateObject private var store = InvoiceStore.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Factur-X") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 900, minHeight: 600)
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
                    let draft = store.newDraft()
                    store.upsert(draft)
                    selectedItem = draft.id
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }

    @State private var selectedItem: UUID?
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

struct ContentView: View {
    @EnvironmentObject var store: InvoiceStore
    @State private var selectedID: UUID?

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedID) {
                ForEach(store.invoices) { invoice in
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
                    store.invoices.remove(atOffsets: idx)
                    store.save()
                }
            }
            .navigationTitle("Factures")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        let draft = store.newDraft()
                        store.upsert(draft)
                        selectedID = draft.id
                    } label: {
                        Label("Nouvelle", systemImage: "plus")
                    }
                }
            }
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Édition : \(invoice.number)").font(.title2.bold())
                    Spacer()
                    Button("Valider") { runValidation() }
                        .buttonStyle(.bordered)
                    Button("Générer le Factur-X") { export() }
                        .buttonStyle(.borderedProminent)
                }

                if let err = exportError {
                    Text("Erreur : \(err)").foregroundStyle(.red).font(.caption)
                }
                if let url = exportedURL {
                    Text("Fichier généré : \(url.lastPathComponent)").font(.caption).foregroundStyle(.green)
                    Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }

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

                if showValidation, let v = validation {
                    validationPanel(v)
                }

                GroupBox("En-tête") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            LabeledContent("Numéro") {
                                TextField("", text: $invoice.number).frame(width: 160)
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
                    PartyEditorView(party: $invoice.seller)
                }

                GroupBox("Destinataire") {
                    PartyEditorView(party: $invoice.buyer)
                }

                GroupBox("Lignes") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach($invoice.lines) { $line in
                            HStack {
                                TextField("Désignation", text: $line.name).frame(minWidth: 220)
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

struct PartyEditorView: View {
    @Binding var party: InvoiceParty

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Nom", text: $party.name)
            TextField("Adresse", text: $party.street)
            HStack {
                TextField("Code postal", text: $party.postcode)
                TextField("Ville", text: $party.city)
                TextField("Pays", text: $party.country).frame(width: 60)
            }
            HStack {
                TextField("N° TVA", text: Binding($party.vatNumber, replacingNilWith: ""))
                TextField("SIREN", text: Binding($party.siren, replacingNilWith: ""))
            }
            HStack {
                TextField("Identifiant électronique (BT-49/34)", text: Binding($party.endpointID, replacingNilWith: ""))
                TextField("Scheme", text: $party.endpointSchemeID).frame(width: 100)
            }
            HStack {
                TextField("Contact", text: Binding($party.contactName, replacingNilWith: ""))
                TextField("Email", text: Binding($party.contactEmail, replacingNilWith: ""))
                TextField("Téléphone", text: Binding($party.contactPhone, replacingNilWith: ""))
            }
        }.padding(8)
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
