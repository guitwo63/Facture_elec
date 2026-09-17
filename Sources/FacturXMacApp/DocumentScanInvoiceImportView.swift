import SwiftUI
import AppKit
import Vision
import PDFKit
import FacturXCore

/// Importe la photo/le scan d'un document papier (devis signé, bon de commande
/// client…) pour pré-remplir une facture : client, référence, date, lignes de
/// prestation et contrôle du total — par OCR (Vision, 100% local) puis
/// heuristiques de `ScannedDocumentParser`. Comme pour l'import commande,
/// jamais appliqué à l'aveugle : tout reste visible et modifiable avant
/// création, et les lignes détectées restent corrigeables ensuite dans
/// l'éditeur de facture complet.
struct DocumentScanInvoiceImportView: View {
    var onCreated: (UUID) -> Void
    var onCancel: () -> Void

    @EnvironmentObject var store: InvoiceStore
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var directory: PartyDirectory

    @State private var recognizedText = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var pickedFileName: String?

    @State private var buyerName = ""
    @State private var matchedEntry: DirectoryEntry?
    @State private var showBuyerPicker = false
    @State private var reference = ""
    @State private var date = Date()
    @State private var companyID: UUID?
    @State private var extractedLines: [InvoiceLine] = []
    @State private var extractedTotal: Double?

    private var visibleCompanies: [DirectoryEntry] {
        auth.visibleSocieties(for: auth.currentUser)
    }

    private var extractedLinesTotal: Double {
        extractedLines.reduce(0) { $0 + $1.lineTotal }
    }

    private var totalConsistency: Bool? {
        ScannedDocumentParser.totalMatches(lines: extractedLines, extractedTotal: extractedTotal)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if pickedFileName == nil {
                        importPrompt
                    } else {
                        resultForm
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
            }
            Divider()
            footer
        }
        .frame(width: 640, height: 620)
        .sheet(isPresented: $showBuyerPicker) {
            PartyPickerSheet(role: .buyer) { entry in
                matchedEntry = entry
                buyerName = entry.displayName
                showBuyerPicker = false
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Scanner un document").font(.title3.bold())
            Spacer()
            Button { onCancel() } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding()
    }

    private var importPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.viewfinder").font(.system(size: 48)).foregroundStyle(Color.accentColor)
            Text("Importez la photo ou le scan d'un devis signé, d'un bon de commande client ou de tout document papier pour en pré-remplir automatiquement une facture (client, référence, date, lignes de prestation).")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            Button {
                pickFile()
            } label: { Label("Choisir un fichier (image ou PDF)", systemImage: "folder") }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing)
            if isProcessing {
                ProgressView("Analyse en cours…")
            }
            if let err = errorMessage {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private var resultForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(pickedFileName ?? "", systemImage: "doc.fill").font(.caption).foregroundStyle(.secondary)

            if let matched = matchedEntry {
                Label("Client reconnu dans l'annuaire : \(matched.displayName)", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            } else {
                Label("Client non reconnu — vérifiez le nom suggéré, ou choisissez-le dans l'annuaire", systemImage: "questionmark.circle")
                    .font(.caption).foregroundStyle(.orange)
            }

            Form {
                Section("Client (à confirmer)") {
                    TextField("Nom", text: $buyerName)
                    Button {
                        showBuyerPicker = true
                    } label: { Label("Choisir dans l'annuaire", systemImage: "person.crop.circle.badge.checkmark") }
                        .buttonStyle(.bordered)
                }
                Section("Facture") {
                    TextField("Référence (BT-13, ex. n° de commande client)", text: $reference)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    if visibleCompanies.count > 1 {
                        Picker("Société (nous)", selection: $companyID) {
                            Text("Choisir…").tag(UUID?.none)
                            ForEach(visibleCompanies) { c in
                                Text(c.displayName).tag(UUID?.some(c.id))
                            }
                        }
                    }
                }
                Section("Lignes détectées (\(extractedLines.count))") {
                    if extractedLines.isEmpty {
                        Text("Aucune ligne reconnue automatiquement — une ligne vide sera créée, à compléter dans l'éditeur de facture.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(extractedLines) { line in
                            HStack {
                                Text(line.name)
                                Spacer()
                                Text("\(fmt(line.quantity)) × \(fmt(line.unitPrice))")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(String(format: "%.2f", line.lineTotal))
                                    .font(.callout.bold()).frame(width: 70, alignment: .trailing)
                            }
                        }
                        HStack {
                            Text("Total des lignes (HT)").font(.caption.bold())
                            Spacer()
                            Text(String(format: "%.2f", extractedLinesTotal)).font(.caption.bold())
                        }
                        if let extractedTotal {
                            switch totalConsistency {
                            case .some(true):
                                Label("Cohérent avec le total lu sur le document (\(String(format: "%.2f", extractedTotal)))", systemImage: "checkmark.circle.fill")
                                    .font(.caption).foregroundStyle(.green)
                            case .some(false):
                                Label("Écart avec le total lu sur le document (\(String(format: "%.2f", extractedTotal))) — vérifiez les lignes avant validation", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption).foregroundStyle(.orange)
                            case .none:
                                EmptyView()
                            }
                        }
                        Text("Vérifiables et corrigeables dans l'éditeur de facture après création.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Section("Texte reconnu (OCR)") {
                    TextEditor(text: .constant(recognizedText))
                        .font(.system(.caption, design: .monospaced))
                        .frame(height: 120)
                        .disabled(true)
                }
            }
            if let err = errorMessage {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func fmt(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", v) : String(format: "%.2f", v)
    }

    private var footer: some View {
        HStack {
            Spacer()
            if pickedFileName != nil {
                Button("Créer la facture") { createInvoice() }
                    .buttonStyle(.borderedProminent)
                    .disabled(buyerName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .pdf, .heic, .tiff, .bmp]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Choisir un document scanné"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        pickedFileName = url.lastPathComponent
        isProcessing = true
        errorMessage = nil
        Task {
            do {
                let image = try Self.loadCGImage(from: url)
                let text = try await Self.recognizeText(in: image)
                recognizedText = text
                applyHeuristics(to: text)
            } catch {
                errorMessage = "Échec de l'analyse : \(error.localizedDescription)"
            }
            isProcessing = false
        }
    }

    private func applyHeuristics(to text: String) {
        if let ref = ScannedDocumentParser.extractReference(from: text) { reference = ref }
        if let d = ScannedDocumentParser.extractDate(from: text) { date = d }
        extractedLines = ScannedDocumentParser.extractLineItems(from: text)
        extractedTotal = ScannedDocumentParser.extractTotal(from: text)
        if let siren = ScannedDocumentParser.extractSIREN(from: text),
           let entry = directory.entries.first(where: {
               ($0.kind == .client || $0.kind == .both) && ($0.party.siren ?? "").filter(\.isNumber) == siren
           }) {
            matchedEntry = entry
            buyerName = entry.displayName
        }
        if buyerName.trimmingCharacters(in: .whitespaces).isEmpty {
            // Faute de mieux : la première ligne non vide est en général l'en-tête
            // (raison sociale) d'un document professionnel.
            buyerName = text.split(separator: "\n")
                .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .map(String.init) ?? ""
        }
        if companyID == nil {
            if visibleCompanies.count == 1 {
                companyID = visibleCompanies.first?.id
            } else if let preferred = auth.societyEntry(forID: auth.currentUser?.defaultSellerEntryID),
                      visibleCompanies.contains(where: { $0.id == preferred.id }) {
                companyID = preferred.id
            }
        }
    }

    private func createInvoice() {
        let trimmedName = buyerName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            errorMessage = "Renseignez au moins le nom du client."
            return
        }
        var buyerParty = matchedEntry?.party ?? InvoiceParty(name: trimmedName, street: "", postcode: "", city: "")
        buyerParty.name = trimmedName
        let sellerParty = visibleCompanies.first(where: { $0.id == companyID })?.party
            ?? store.resolveDefaultSeller(from: directory)
            ?? store.myCompany
        let number = store.nextNumber(companyID: companyID)
        let linesForInvoice = extractedLines.isEmpty
            ? [InvoiceLine(name: "", quantity: 1, unitPrice: 0, vatRate: 20)]
            : extractedLines
        let notesText = recognizedText.trimmingCharacters(in: .whitespaces).isEmpty
            ? nil
            : "Texte reconnu automatiquement (scan) :\n\(recognizedText)"
        let trimmedRef = reference.trimmingCharacters(in: .whitespaces)
        let invoice = Invoice(
            number: number,
            issueDate: date,
            seller: sellerParty,
            buyer: buyerParty,
            companyID: companyID,
            purchaseOrderRef: trimmedRef.isEmpty ? nil : trimmedRef,
            lines: linesForInvoice,
            paymentIBAN: sellerParty.iban,
            paymentBIC: sellerParty.bic,
            paymentTerms: sellerParty.paymentTerms,
            notes: notesText
        )
        store.upsert(invoice)
        onCreated(invoice.id)
    }

    private static func loadCGImage(from url: URL) throws -> CGImage {
        if url.pathExtension.lowercased() == "pdf" {
            guard let doc = PDFDocument(url: url), let page = doc.page(at: 0) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let pageRect = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2
            let size = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
            let image = NSImage(size: size)
            image.lockFocus()
            if let ctx = NSGraphicsContext.current?.cgContext {
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fill(CGRect(origin: .zero, size: size))
                ctx.saveGState()
                ctx.scaleBy(x: scale, y: scale)
                page.draw(with: .mediaBox, to: ctx)
                ctx.restoreGState()
            }
            image.unlockFocus()
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return cgImage
        }
        guard let nsImage = NSImage(contentsOf: url),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return cgImage
    }

    private static func recognizeText(in image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["fr-FR", "en-US"]
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
