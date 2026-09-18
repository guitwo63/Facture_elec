import SwiftUI
import FacturXCore

/// Facture guidée : crée une facture de vente avec le minimum d'informations
/// (émetteur, client, une ou plusieurs prestations, échéance) puis ouvre le
/// résultat dans l'éditeur complet pour tout complément. Une TPE facture
/// rarement avec plus que ça au départ ; le reste (mentions légales, IBAN…)
/// est déjà repris de la fiche société choisie.
struct SalesInvoiceWizardView: View {
    var onCreated: (UUID) -> Void
    var onCancel: () -> Void

    @EnvironmentObject var store: InvoiceStore
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var directory: PartyDirectory
    @EnvironmentObject var paymentTermsStore: PaymentTermsPresetStore

    @State private var step: Step = .company
    @State private var companyID: UUID?
    @State private var buyerEntry: DirectoryEntry?
    @State private var showBuyerPicker = false
    @State private var lines: [InvoiceLine] = [InvoiceLine(name: "", quantity: 1, unitPrice: 0, vatRate: 20)]
    @State private var dueDate = Date().addingTimeInterval(30 * 86400)
    @State private var errorMessage: String?

    enum Step: Int, CaseIterable {
        case company, client, line, review
    }

    private var visibleCompanies: [DirectoryEntry] {
        auth.visibleSocieties(for: auth.currentUser)
    }

    private var lineTotal: Double { lines.reduce(0) { $0 + $1.lineTotal }.rounded(toPlaces: 2) }
    private var vatAmount: Double {
        lines.reduce(0) { $0 + ($1.lineTotal * $1.vatRate / 100) }.rounded(toPlaces: 2)
    }
    private var grandTotal: Double { (lineTotal + vatAmount).rounded(toPlaces: 2) }

    /// Une ligne blanche ajoutée puis jamais remplie ne doit pas bloquer la suite ;
    /// elle sera simplement filtrée à la création (cf. validLines).
    private var hasAtLeastOneValidLine: Bool {
        lines.contains { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && $0.quantity > 0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                switch step {
                case .company: companyStep
                case .client: clientStep
                case .line: lineStep
                case .review: reviewStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 600, height: 560)
        .onAppear {
            guard companyID == nil else { return }
            if visibleCompanies.count == 1 {
                companyID = visibleCompanies.first?.id
            } else if let preferred = auth.societyEntry(forID: auth.currentUser?.defaultSellerEntryID),
                      visibleCompanies.contains(where: { $0.id == preferred.id }) {
                companyID = preferred.id
            }
            applySuggestedDueDate()
        }
        .onChange(of: companyID) { _ in applySuggestedDueDate() }
    }

    /// Si les conditions de paiement de la société émettrice correspondent à un
    /// préréglage connu, propose l'échéance calculée — l'utilisateur garde la main
    /// pour la modifier à l'étape récapitulative (DatePicker normal, non verrouillé).
    private func applySuggestedDueDate() {
        guard let cid = companyID, let company = visibleCompanies.first(where: { $0.id == cid }) else { return }
        guard let presetID = paymentTermsStore.matchingPresetID(for: company.party.paymentTerms),
              let preset = paymentTermsStore.presets.first(where: { $0.id == presetID }) else { return }
        dueDate = preset.dueRule.dueDate(from: Date())
    }

    private var header: some View {
        HStack {
            Text("Facture guidée").font(.title3.bold())
            Spacer()
            Text("Étape \(step.rawValue + 1) sur \(Step.allCases.count)").font(.caption).foregroundStyle(.secondary)
            Button { onCancel() } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding()
    }

    private var companyStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Société émettrice").font(.headline)
            if visibleCompanies.isEmpty {
                Text("Aucune société disponible. Créez-en une dans Réglages avant de continuer.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("Société", selection: $companyID) {
                    Text("Choisir…").tag(UUID?.none)
                    ForEach(visibleCompanies) { c in
                        Text(c.displayName).tag(UUID?.some(c.id))
                    }
                }
                .labelsHidden()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var clientStep: some View {
        VStack(spacing: 16) {
            Text("Client").font(.headline)
            if let entry = buyerEntry {
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.fill").font(.system(size: 36)).foregroundStyle(.secondary)
                    Text(entry.displayName).font(.body.weight(.semibold))
                    Text(entry.subtitle).font(.caption).foregroundStyle(.secondary)
                    Button("Changer") { showBuyerPicker = true }.buttonStyle(.bordered)
                }
            } else {
                Text("Choisissez un client existant, ou créez-en un nouveau.")
                    .font(.caption).foregroundStyle(.secondary)
                Button {
                    showBuyerPicker = true
                } label: { Label("Choisir un client", systemImage: "person.crop.circle.badge.plus") }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showBuyerPicker) {
            PartyPickerSheet(role: .buyer) { entry in
                buyerEntry = entry
                showBuyerPicker = false
            }
        }
    }

    private var lineStep: some View {
        Form {
            Section("Prestations") {
                ForEach($lines) { $line in
                    HStack {
                        TextField("Désignation", text: $line.name)
                        TextField("Qté", value: $line.quantity, format: .number).frame(width: 60)
                        TextField("Prix U. HT", value: $line.unitPrice, format: .number).frame(width: 90)
                        VATRatePicker(rate: $line.vatRate)
                            .onChange(of: line.vatRate) { newRate in
                                // Catégorie de TVA (BT-151) tenue cohérente avec le taux : cet assistant
                                // minimal n'offre pas de sélection fine (autoliquidation, export…), donc
                                // ne propose que standard/zéro-rated — affiner ensuite dans la fiche facture
                                // complète si besoin. Sans ce recalage, changer le taux ici pouvait laisser
                                // une catégorie "zéro-rated" sur une ligne repassée à taux plein (ou l'inverse),
                                // rejeté par le validateur EN16931 (BR-Z-05/BR-Z-09).
                                line.vatCategory = newRate == 0 ? .zeroRated : .standard
                                if newRate != 0 { line.vatExemptionReason = nil }
                            }
                        Text(String(format: "%.2f", line.lineTotal))
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .trailing)
                        Button(role: .destructive) {
                            lines.removeAll { $0.id == line.id }
                        } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                            .disabled(lines.count <= 1)
                    }
                }
                Button {
                    lines.append(InvoiceLine(name: "", quantity: 1, unitPrice: 0, vatRate: lines.last?.vatRate ?? 20))
                } label: { Label("Ajouter une ligne", systemImage: "plus") }

                HStack {
                    Text("Total HT").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.2f", lineTotal)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }

    private var reviewStep: some View {
        Form {
            Section("Récapitulatif") {
                if let cid = companyID, let c = visibleCompanies.first(where: { $0.id == cid }) {
                    LabeledContent("Émetteur") { Text(c.displayName) }
                }
                if let b = buyerEntry {
                    LabeledContent("Client") { Text(b.displayName) }
                }
                ForEach(lines.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }) { line in
                    LabeledContent(line.name) { Text(String(format: "%.2f EUR", line.lineTotal)) }
                }
                LabeledContent("Total HT") { Text(String(format: "%.2f EUR", lineTotal)) }
                LabeledContent("TVA") { Text(String(format: "%.2f EUR", vatAmount)) }
                LabeledContent("Total TTC") { Text(String(format: "%.2f EUR", grandTotal)).bold() }
                DatePicker("Échéance", selection: $dueDate, displayedComponents: .date)
            }
            if let err = errorMessage {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        }
        .padding()
    }

    private var footer: some View {
        HStack {
            if step != .company {
                Button("Précédent") { back() }
            }
            Spacer()
            switch step {
            case .company:
                Button("Continuer") { forward() }
                    .buttonStyle(.borderedProminent)
                    .disabled(companyID == nil)
            case .client:
                Button("Continuer") { forward() }
                    .buttonStyle(.borderedProminent)
                    .disabled(buyerEntry == nil)
            case .line:
                Button("Continuer") { forward() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasAtLeastOneValidLine)
            case .review:
                Button("Créer la facture") { createInvoice() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    private func forward() {
        if let idx = Step.allCases.firstIndex(of: step), idx + 1 < Step.allCases.count {
            step = Step.allCases[idx + 1]
        }
    }

    private func back() {
        if let idx = Step.allCases.firstIndex(of: step), idx > 0 {
            step = Step.allCases[idx - 1]
        }
    }

    private func createInvoice() {
        guard let cid = companyID, let companyEntry = visibleCompanies.first(where: { $0.id == cid }) else {
            errorMessage = "Sélectionnez une société émettrice."
            return
        }
        guard let buyerDirEntry = buyerEntry else {
            errorMessage = "Sélectionnez un client."
            return
        }
        let validLines = lines.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && $0.quantity > 0 }
        guard !validLines.isEmpty else {
            errorMessage = "Ajoutez au moins une prestation."
            return
        }
        var seller = companyEntry.party
        if let routing = companyEntry.defaultRoutingAddress, routing.isActive {
            let composed = routing.composedAddress.trimmingCharacters(in: .whitespaces)
            if !composed.isEmpty {
                seller.endpointID = composed
                seller.endpointSchemeID = "0225"
            }
        }
        if let contact = companyEntry.defaultContact, contact.isActive {
            seller.contactName = (contact.name.trimmingCharacters(in: .whitespaces).isEmpty) ? nil : contact.name
            seller.contactEmail = (contact.email?.trimmingCharacters(in: .whitespaces) ?? "").isEmpty ? nil : contact.email
            seller.contactPhone = (contact.phone?.trimmingCharacters(in: .whitespaces) ?? "").isEmpty ? nil : contact.phone
        }
        let number = store.nextNumber(companyID: cid)
        let invoice = Invoice(
            number: number,
            dueDate: dueDate,
            seller: seller,
            buyer: buyerDirEntry.party,
            companyID: cid,
            lines: validLines,
            paymentIBAN: seller.iban,
            paymentBIC: seller.bic,
            paymentTerms: seller.paymentTerms
        )
        store.upsert(invoice)
        onCreated(invoice.id)
    }
}
