import SwiftUI
import FacturXCore
import AppKit

// MARK: - Composants et utilitaires partagés entre plusieurs onglets/écrans
// Extrait de FacturXMacApp.swift (découpage par domaine) — voir le plan
// "Découpage de FacturXMacApp.swift par domaine fonctionnel".

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r, g, b, a: UInt64
        switch cleaned.count {
        case 8:
            (r, g, b, a) = (int >> 24 & 0xFF, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        case 6:
            (r, g, b, a) = (int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF, 255)
        default:
            (r, g, b, a) = (85, 85, 85, 255)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

func hexString(from color: Color) -> String {
    let nsColor = NSColor(color)
    let rgb = nsColor.usingColorSpace(.sRGB) ?? nsColor
    let r = Int((rgb.redComponent * 255).rounded())
    let g = Int((rgb.greenComponent * 255).rounded())
    let b = Int((rgb.blueComponent * 255).rounded())
    return String(format: "%02X%02X%02X", r, g, b)
}

extension View {
    /// Bloque l'édition d'une section sans en griser le contenu : un liseré en
    /// pointillés signale la zone en lecture seule (le bandeau au-dessus indique
    /// déjà l'état verrouillé), les données restent pleinement lisibles.
    @ViewBuilder
    func lockable(_ locked: Bool) -> some View {
        self
            .allowsHitTesting(!locked)
            .overlay {
                if locked {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
            }
    }
}

struct ToolbarActionButtonStyle: ButtonStyle {
    var tint: Color
    var filled: Bool = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .foregroundStyle(filled ? Color.white : tint)
            .background(filled ? tint : tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(tint, lineWidth: filled ? 0 : 1.5))
            .opacity(!isEnabled ? 0.35 : (configuration.isPressed ? 0.7 : 1))
    }
}

struct InfoBadge: View {
    let text: String
    @State private var isHovering = false
    @State private var showTask: DispatchWorkItem?
    var body: some View {
        Image(systemName: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel(Text(text))
            .onHover { hovering in
                showTask?.cancel()
                if hovering {
                    let task = DispatchWorkItem { isHovering = true }
                    showTask = task
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: task)
                } else {
                    isHovering = false
                }
            }
            .overlay(alignment: .top) {
                if isHovering {
                    Text(text)
                        .font(.caption2)
                        .padding(6)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(4)
                        .shadow(radius: 2)
                        .frame(maxWidth: 250)
                        .fixedSize()
                        .offset(y: -22)
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }
            }
    }
}

struct LabeledInfoField<Content: View>: View {
    let label: String
    let info: String
    @ViewBuilder let content: Content
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 3) {
                Text(label)
                InfoBadge(text: info)
            }
            content
        }
    }
}

enum QuickExport {
    enum Format: String, CaseIterable, Hashable {
        case csvList = "Liste (CSV/Excel)"
        case csvLines = "Détail des lignes (CSV/Excel)"
        case electronic = "Fichiers électroniques (Factur-X)"
    }

    enum OrderFormat: String, CaseIterable, Hashable {
        case csvList = "Liste (CSV/Excel)"
        case csvLines = "Détail des lignes (CSV/Excel)"
        case electronic = "Fichiers électroniques (Order-X)"
    }

    /// Pas de format "électronique" : un devis n'est pas un document Factur-X/Order-X,
    /// juste une liste/CSV.
    enum QuoteFormat: String, CaseIterable, Hashable {
        case csvList = "Liste (CSV/Excel)"
        case csvLines = "Détail des lignes (CSV/Excel)"
    }

    static func run(invoices: [Invoice], format: Format) -> String {
        switch format {
        case .csvList:
            return saveCSV(ExportGenerator().invoiceCSV(invoices), filename: "factures")
        case .csvLines:
            return saveCSV(ExportGenerator().invoiceLinesCSV(invoices), filename: "factures-lignes")
        case .electronic:
            return exportElectronicInvoices(invoices)
        }
    }

    static func run(orders: [SalesOrder], format: OrderFormat) -> String {
        switch format {
        case .csvList:
            return saveCSV(ExportGenerator().orderCSV(orders), filename: "commandes")
        case .csvLines:
            return saveCSV(ExportGenerator().orderLinesCSV(orders), filename: "commandes-lignes")
        case .electronic:
            return exportElectronicOrders(orders)
        }
    }

    static func run(quotes: [Quote], format: QuoteFormat) -> String {
        switch format {
        case .csvList:
            return saveCSV(ExportGenerator().quoteCSV(quotes), filename: "devis")
        case .csvLines:
            return saveCSV(ExportGenerator().quoteLinesCSV(quotes), filename: "devis-lignes")
        }
    }

    private static func saveCSV(_ csv: String, filename: String) -> String {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "\(filename).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return "" }
        do {
            try ExportGenerator().writeCSV(csv, to: url)
            return "Exporté : \(url.lastPathComponent)"
        } catch {
            return "Erreur : \(error)"
        }
    }

    private static func exportElectronicInvoices(_ invoices: [Invoice]) -> String {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Exporter ici"
        guard panel.runModal() == .OK, let dir = panel.url else { return "" }
        var ok = 0
        var failed = 0
        var skipped = 0
        let gen = FacturXGenerator()
        for inv in invoices {
            if inv.type.isInternalCreditNote {
                skipped += 1
                continue
            }
            do {
                let data = try gen.generate(invoice: inv)
                let name = inv.type.isCreditNote ? "avoir-\(inv.number).pdf" : "facture-\(inv.number).pdf"
                try data.write(to: dir.appendingPathComponent(name))
                ok += 1
            } catch {
                failed += 1
            }
        }
        return "\(ok) fichier(s) généré(s)\(failed > 0 ? ", \(failed) échec(s)" : "")\(skipped > 0 ? ", \(skipped) avoir(s) interne(s) ignoré(s)" : "")"
    }

    private static func exportElectronicOrders(_ orders: [SalesOrder]) -> String {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Exporter ici"
        guard panel.runModal() == .OK, let dir = panel.url else { return "" }
        var ok = 0
        var failed = 0
        let gen = OrderXGenerator()
        for order in orders {
            do {
                let data = try gen.generate(order: order)
                let name = "commande-\(order.number).pdf"
                try data.write(to: dir.appendingPathComponent(name))
                ok += 1
            } catch {
                failed += 1
            }
        }
        return "\(ok) fichier(s) généré(s)\(failed > 0 ? ", \(failed) échec(s)" : "")"
    }
}

/// Badge d'une ligne de réglage quand la société sélectionnée a sa propre personnalisation
/// pour cette ligne — clic pour revenir au réglage par défaut. Sans personnalisation propre,
/// rien n'est affiché : la société suit le réglage par défaut, jamais celui de la société
/// principale (voir `PartyDirectory.principaleSocieteID`).
struct SocietyOverrideBadge: View {
    let isCustomized: Bool
    let onRevert: () -> Void

    var body: some View {
        if isCustomized {
            Button(action: onRevert) {
                HStack(spacing: 3) {
                    Image(systemName: "building.2.fill").font(.caption2)
                    Text("Personnalisé").font(.caption2)
                    Image(systemName: "arrow.uturn.backward").font(.caption2)
                }
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.12)))
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .help("Personnalisé pour cette société — cliquer pour revenir au réglage par défaut")
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
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.clear))
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

struct NormRefPicker: View {
    let label: String
    let options: [NormRef]
    @Binding var code: String

    init(_ label: String, options: [NormRef], code: Binding<String>) {
        self.label = label
        self.options = options
        self._code = code
    }

    var body: some View {
        Picker(label, selection: Binding(
            get: { options.first(where: { $0.code == code })?.id ?? "__custom__" },
            set: { id in
                if id == "__custom__" { code = "" }
                else { code = options.first(where: { $0.id == id })?.code ?? code }
            }
        )) {
            ForEach(options) { ref in Text(ref.label).tag(ref.id as String) }
            Text("Autre…").tag("__custom__" as String)
        }
    }
}

extension InvoiceLine {
    /// Taux tel que l'éditent `VATRatePicker` et le champ « TVA % » des devis : l'écrire passe
    /// par `setVATRate(_:)`, qui tient la catégorie cohérente (0 % → E). Remplace les
    /// `.onChange(of: line.vatRate)` des éditeurs : un effet voulu par l'utilisateur va dans le
    /// setter du binding, pas dans un onChange (voir #135).
    var editedVATRate: Double {
        get { vatRate }
        set { setVATRate(newValue) }
    }
}

/// Branché sur `$line.editedVATRate` : « 0 % — Exonéré » met la ligne en catégorie E.
struct VATRatePicker: View {
    @Binding var rate: Double

    static let standardRates: [(rate: Double, label: String)] = [
        (20, "20 % — Normal"),
        (10, "10 % — Intermédiaire"),
        (5.5, "5,5 % — Réduit"),
        (2.1, "2,1 % — Particulier"),
        (0, "0 % — Exonéré")
    ]

    private var isStandard: Bool { Self.standardRates.contains { $0.rate == rate } }

    var body: some View {
        HStack(spacing: 4) {
            Picker("", selection: Binding(
                get: { isStandard ? rate : -1 },
                set: { newValue in if newValue >= 0 { rate = newValue } }
            )) {
                ForEach(Self.standardRates, id: \.rate) { entry in
                    Text(entry.label).tag(entry.rate)
                }
                Text("Autre…").tag(-1.0)
            }
            .labelsHidden()
            .frame(width: 150)
            if !isStandard {
                TextField("%", value: $rate, format: .number)
                    .frame(width: 50)
            }
        }
    }
}

struct AttachmentsAndCommentSection: View {
    @Binding var attachments: [Attachment]
    @Binding var internalComment: String?
    var locked: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Pièces jointes", systemImage: "paperclip").font(.headline)
                    Spacer()
                    Button {
                        addAttachments()
                    } label: { Label("Ajouter…", systemImage: "plus") }
                        .buttonStyle(.bordered)
                        .disabled(locked)
                }
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }
                if attachments.isEmpty {
                    Text("Aucune pièce jointe.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(attachments) { att in
                        HStack(spacing: 6) {
                            Image(systemName: "doc").foregroundStyle(.secondary)
                            Text(att.fileName).lineLimit(1)
                            Spacer()
                            Text(att.sizeDescription).font(.caption).foregroundStyle(.secondary)
                            Button {
                                saveAttachment(att)
                            } label: { Image(systemName: "square.and.arrow.down") }
                                .buttonStyle(.borderless)
                                .help("Enregistrer sous…")
                            if !locked {
                                Button(role: .destructive) {
                                    attachments.removeAll { $0.id == att.id }
                                } label: { Image(systemName: "trash") }
                                    .buttonStyle(.borderless)
                                    .help("Retirer")
                            }
                        }
                    }
                }
                Divider()
                Label("Commentaire interne (non transmis au client, absent du PDF/XML)", systemImage: "lock.doc")
                    .font(.caption.bold()).foregroundStyle(.secondary)
                TextField("Commentaire interne", text: Binding($internalComment, replacingNilWith: ""), axis: .vertical)
                    .lineLimit(2...5)
                    .disabled(locked)
            }.padding(8)
        }
    }

    private func addAttachments() {
        errorMessage = nil
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.title = "Ajouter une pièce jointe"
        guard panel.runModal() == .OK else { return }
        var skipped: [String] = []
        for url in panel.urls {
            guard let data = try? Data(contentsOf: url) else {
                skipped.append(url.lastPathComponent)
                continue
            }
            guard data.count <= Attachment.maxSizeBytes else {
                skipped.append("\(url.lastPathComponent) (> 10 Mo)")
                continue
            }
            attachments.append(Attachment(fileName: url.lastPathComponent, data: data))
        }
        if !skipped.isEmpty {
            errorMessage = "Non ajouté(s) : \(skipped.joined(separator: ", "))."
        }
    }

    private func saveAttachment(_ attachment: Attachment) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = attachment.fileName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? attachment.data.write(to: url)
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
