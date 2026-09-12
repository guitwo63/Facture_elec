import SwiftUI
import FacturXCore

@main
struct FacturXMacApp: App {
    @StateObject private var store = InvoiceStore.shared

    var body: some Scene {
        WindowGroup("Factur-X") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 900, minHeight: 600)
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
               let invoice = store.invoices.first(where: { $0.id == id }) {
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Édition : \(invoice.number)").font(.title2.bold())
                    Spacer()
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
                                Text(String(format: "%.2f", line.wrappedValue.lineTotal))
                                    .monospacedDigit().frame(width: 80, alignment: .trailing)
                                Button { invoice.lines.removeAll { $0.id == line.wrappedValue.id } } label: {
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
        do {
            store.upsert(invoice)
            let data = try FacturXGenerator().generate(invoice: invoice)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = "facture-\(invoice.number).pdf"
            if panel.runModal() == .OK, let url = panel.url {
                try data.write(to: url)
                exportedURL = url
            }
        } catch {
            exportError = "\(error)"
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
