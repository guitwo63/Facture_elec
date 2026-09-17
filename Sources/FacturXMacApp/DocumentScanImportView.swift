import SwiftUI
import AppKit
import Vision
import PDFKit
import FacturXCore

/// Importe la photo/le scan d'un document papier (bon de commande, devis
/// fournisseur…), en extrait le texte par OCR (Vision, 100% local) puis
/// suggère fournisseur/référence/date via ScannedDocumentParser — jamais
/// appliqué à l'aveugle : l'utilisateur confirme/corrige avant création.
struct DocumentScanImportView: View {
    var onCreated: (UUID) -> Void
    var onCancel: () -> Void

    @EnvironmentObject var orderStore: OrderStore
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var directory: PartyDirectory

    @State private var recognizedText = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var pickedFileName: String?

    @State private var supplierName = ""
    @State private var reference = ""
    @State private var date = Date()
    @State private var matchedEntry: DirectoryEntry?
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

    private func fmt(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", v) : String(format: "%.2f", v)
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
        .frame(width: 600, height: 560)
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
            Text("Importez la photo ou le scan d'un bon de commande, d'un devis fournisseur ou de tout document papier pour en pré-remplir automatiquement une commande (référence, date, fournisseur si reconnu).")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
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
                Label("Fournisseur reconnu dans l'annuaire : \(matched.displayName)", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            } else {
                Label("Fournisseur non reconnu — vérifiez le nom suggéré ci-dessous", systemImage: "questionmark.circle")
                    .font(.caption).foregroundStyle(.orange)
            }

            Form {
                Section("Fournisseur (à confirmer)") {
                    TextField("Nom", text: $supplierName)
                }
                Section("Commande") {
                    TextField("Référence", text: $reference)
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
                        Text("Aucune ligne reconnue automatiquement — une ligne vide sera créée, à compléter dans l'éditeur de commande.")
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
                        Text("Vérifiables et corrigeables dans l'éditeur de commande après création.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Section("Texte reconnu (OCR)") {
                    TextEditor(text: .constant(recognizedText))
                        .font(.system(.caption, design: .monospaced))
                        .frame(height: 140)
                        .disabled(true)
                }
            }
            if let err = errorMessage {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            if pickedFileName != nil {
                Button("Créer la commande") { createOrder() }
                    .buttonStyle(.borderedProminent)
                    .disabled(supplierName.trimmingCharacters(in: .whitespaces).isEmpty)
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
           let entry = directory.entries.first(where: { ($0.party.siren ?? "").filter(\.isNumber) == siren }) {
            matchedEntry = entry
            supplierName = entry.displayName
        }
        if supplierName.trimmingCharacters(in: .whitespaces).isEmpty {
            // Faute de mieux : la première ligne non vide est en général l'en-tête
            // (raison sociale) d'un document professionnel.
            supplierName = text.split(separator: "\n")
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

    private func createOrder() {
        let trimmedName = supplierName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            errorMessage = "Renseignez au moins le nom du fournisseur."
            return
        }
        var scannedParty = matchedEntry?.party ?? InvoiceParty(name: trimmedName, street: "", postcode: "", city: "")
        scannedParty.name = trimmedName
        let ourCompany = visibleCompanies.first(where: { $0.id == companyID })?.party
            ?? auth.societyEntry(forID: auth.currentUser?.defaultSellerEntryID)?.party
            ?? InvoiceParty(name: "", street: "", postcode: "", city: "")
        var order = SalesOrder(
            number: orderStore.nextNumber(companyID: companyID),
            issueDate: date,
            buyer: scannedParty,
            seller: ourCompany,
            lines: extractedLines.isEmpty ? [InvoiceLine(name: "", quantity: 1, unitPrice: 0, vatRate: 20)] : extractedLines,
            companyID: companyID
        )
        let trimmedRef = reference.trimmingCharacters(in: .whitespaces)
        if !trimmedRef.isEmpty { order.quotationRef = trimmedRef }
        orderStore.upsert(order)
        onCreated(order.id)
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
