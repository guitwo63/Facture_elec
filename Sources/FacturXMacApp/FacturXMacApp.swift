import SwiftUI
import FacturXCore
import AppKit
import UniformTypeIdentifiers

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
    @ViewBuilder
    func lockable(_ locked: Bool) -> some View {
        self.allowsHitTesting(!locked)
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

@main
struct FacturXMacApp: App {
    @StateObject private var store = InvoiceStore.shared
    @StateObject private var orderStore = OrderStore.shared
    @StateObject private var directory = PartyDirectory.shared
    @StateObject private var chorusSettings = ChorusProSettings.shared
    @StateObject private var tagStore = TagStore.shared
    @StateObject private var kindColors = KindColorStore.shared
    @StateObject private var statusStore = OrderStatusStore.shared
    @StateObject private var auth = AuthStore.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Factur-X") {
            RootView()
                .environmentObject(store)
                .environmentObject(orderStore)
                .environmentObject(directory)
                .environmentObject(chorusSettings)
                .environmentObject(tagStore)
                .environmentObject(kindColors)
                .environmentObject(statusStore)
                .environmentObject(auth)
                .frame(minWidth: 980, minHeight: 620)
                .onAppear {
                    auth.attachDirectory(directory)
                    auth.testBypassSecurity = true
                    store.audit = AuditStore.shared
                    orderStore.audit = AuditStore.shared
                    directory.audit = AuditStore.shared
                    store.actorName = auth.currentUser?.username ?? "system"
                    orderStore.actorName = auth.currentUser?.username ?? "system"
                    directory.actorName = auth.currentUser?.username ?? "system"
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
                Button("Nouvelle commande") {
                    NotificationCenter.default.post(name: .newOrderRequested, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let newInvoiceRequested = Notification.Name("newInvoiceRequested")
    static let newOrderRequested = Notification.Name("newOrderRequested")
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
    case directory = "Annuaire"
    case orders = "Commandes"
    case invoices = "Factures"
    var id: String { rawValue }

    static func visible(for role: UserRole?) -> [RootTab] {
        switch role {
        case .acheteur:
            return [.orders]
        default:
            return allCases
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: InvoiceStore
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var orderStore: OrderStore
    @State private var tab: RootTab = .invoices
    @State private var selectedID: UUID?
    @State private var selectedOrderID: UUID?
    @State private var showSettings = false
    @State private var showUserManagement = false

    var body: some View {
        Group {
            if auth.currentUser == nil {
                LoginView()
            } else {
                mainBody
            }
        }
    }

    private var mainBody: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $tab) {
                    ForEach(RootTab.visible(for: auth.currentUser?.role)) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
                Spacer()
                if let user = auth.currentUser {
                    HStack(spacing: 6) {
                        Image(systemName: user.role.systemImage)
                            .foregroundStyle(.secondary)
                        Text(user.effectiveDisplayName).font(.callout)
                        Text(user.role.label).font(.caption).foregroundStyle(.secondary)
                        Button {
                            auth.logout()
                            tab = .invoices
                            selectedID = nil
                        } label: {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.title2)
                        }
                        .buttonStyle(.borderless)
                        .help("Se déconnecter")
                    }
                }
                if auth.currentUser?.isAdmin == true {
                    Button {
                        showUserManagement = true
                    } label: {
                        Image(systemName: "person.badge.shield.checkmark")
                            .font(.title2)
                    }
                    .buttonStyle(.borderless)
                    .help("Gestion utilisateurs")
                }
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.title2)
                }
                .buttonStyle(.borderless)
                .help("Réglages")
            }
            .padding(8)

            switch tab {
            case .invoices:
                InvoicesTabView(selectedID: $selectedID)
            case .orders:
                OrdersTabView(selectedID: $selectedOrderID)
            case .directory:
                DirectoryView()
            }
        }
        .sheet(isPresented: $showSettings) {
            VStack(spacing: 0) {
                HStack {
                    Text("Réglages").font(.title2.bold())
                    Spacer()
                    Button {
                        showSettings = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Fermer")
                }
                .padding(12)
                Divider()
                SettingsTabView()
                    .frame(minWidth: 720, minHeight: 640)
            }
        }
        .sheet(isPresented: $showUserManagement) {
            VStack(spacing: 0) {
                HStack {
                    Text("Gestion utilisateurs").font(.title2.bold())
                    Spacer()
                    Button {
                        showUserManagement = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Fermer")
                }
                .padding(12)
                Divider()
                UserManagementView()
                    .frame(minWidth: 760, minHeight: 560)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newInvoiceRequested)) { _ in
            tab = .invoices
            let draft = store.newDraft(companyID: defaultDraftCompanyID(),
                                       preferredSellerEntryID: auth.currentUser?.defaultSellerEntryID)
            store.upsert(draft)
            selectedID = draft.id
        }
        .onReceive(NotificationCenter.default.publisher(for: .newOrderRequested)) { _ in
            tab = .orders
            let draft = orderStore.newDraft(preferredBuyerEntryID: auth.currentUser?.defaultSellerEntryID, companyID: defaultDraftCompanyID())
            orderStore.upsert(draft)
            selectedOrderID = draft.id
        }
        .onAppear {
            if auth.currentUser?.role == .acheteur, !RootTab.visible(for: .acheteur).contains(tab) {
                tab = .orders
            }
            syncAuditActor()
        }
        .onChange(of: auth.currentUser) { _ in syncAuditActor() }
    }

    private func syncAuditActor() {
        let name = auth.currentUser?.username ?? "system"
        store.actorName = name
        orderStore.actorName = name
        PartyDirectory.shared.actorName = name
    }

    private func defaultDraftCompanyID() -> UUID? {
        let visible = auth.visibleSocieties(for: auth.currentUser)
        if visible.count == 1 { return visible.first?.id }
        if let preferred = auth.societyEntry(forID: auth.currentUser?.defaultSellerEntryID),
           visible.contains(where: { $0.id == preferred.id }) {
            return preferred.id
        }
        return visible.first?.id
    }
}

enum InvoiceTypeFilter: String, CaseIterable, Hashable {
    case all = "Tous"
    case invoice = "Factures"
    case creditNote = "Avoirs"
}

struct ExportSheet: View {
    let invoices: [Invoice]
    let orders: [SalesOrder]
    @Binding var isPresented: Bool

    enum ExportKind: String, CaseIterable, Hashable {
        case invoices = "Factures"
        case orders = "Commandes"
    }

    enum ExportFormat: String, CaseIterable, Hashable {
        case csvList = "Liste (CSV/Excel)"
        case csvLines = "Détail des lignes (CSV/Excel)"
        case electronic = "Fichiers électroniques (Factur-X / Order-X)"
    }

    @State private var kind: ExportKind = .invoices
    @State private var format: ExportFormat = .csvList
    @State private var query = ""
    @State private var selectedIDs: Set<UUID> = []
    @State private var exportLog: String = ""

    private var baseList: [(id: UUID, number: String, date: Date, label: String, amount: Double)] {
        switch kind {
        case .invoices:
            return invoices.map { ($0.id, $0.number, $0.issueDate, $0.type.label, $0.grandTotal) }
        case .orders:
            return orders.map { ($0.id, $0.number, $0.issueDate, $0.type.label, $0.grandTotal) }
        }
    }

    private var filteredList: [(id: UUID, number: String, date: Date, label: String, amount: Double)] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return baseList }
        return baseList.filter { $0.number.lowercased().contains(q) || $0.label.lowercased().contains(q) }
    }

    private var selectedInvoices: [Invoice] {
        invoices.filter { selectedIDs.contains($0.id) }
    }

    private var selectedOrders: [SalesOrder] {
        orders.filter { selectedIDs.contains($0.id) }
    }

    private let df: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Export des documents").font(.headline)
                Spacer()
            }
            .padding(12)
            Divider()
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Type").font(.caption.bold())
                    Picker("Type", selection: $kind) {
                        ForEach(ExportKind.allCases, id: \.self) { k in Text(k.rawValue).tag(k) }
                    }.labelsHidden().pickerStyle(.segmented)
                    Text("Format").font(.caption.bold())
                    Picker("Format", selection: $format) {
                        ForEach(ExportFormat.allCases, id: \.self) { f in Text(f.rawValue).tag(f) }
                    }.labelsHidden()
                    HStack {
                        Button("Tout sélectionner") {
                            selectedIDs = Set(filteredList.map { $0.id })
                        }
                        Button("Tout désélectionner") {
                            selectedIDs = []
                        }
                    }.font(.caption)
                }
                Spacer()
            }
            .padding(12)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Rechercher (numéro, type…)", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            Divider()
            List(Array(filteredList.enumerated()), id: \.element.id) { _, item in
                HStack {
                    Image(systemName: selectedIDs.contains(item.id) ? "checkmark.square.fill" : "square")
                        .foregroundStyle(selectedIDs.contains(item.id) ? Color.accentColor : Color.secondary)
                        .onTapGesture {
                            if selectedIDs.contains(item.id) { selectedIDs.remove(item.id) }
                            else { selectedIDs.insert(item.id) }
                        }
                    VStack(alignment: .leading) {
                        Text(item.number).font(.headline)
                        Text(item.label).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(String(format: "%.2f", item.amount))
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    Text(df.string(from: item.date)).font(.caption).foregroundStyle(.secondary).frame(width: 90, alignment: .trailing)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if selectedIDs.contains(item.id) { selectedIDs.remove(item.id) }
                    else { selectedIDs.insert(item.id) }
                }
            }
            Divider()
            HStack {
                Button("Fermer") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if !exportLog.isEmpty {
                    Text(exportLog).font(.caption).foregroundStyle(.secondary)
                }
                Button("Exporter") { runExport() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedIDs.isEmpty)
            }
            .padding(12)
        }
        .frame(width: 640, height: 480)
    }

    private func runExport() {
        exportLog = ""
        switch (kind, format) {
        case (.invoices, .csvList):
            saveCSV(ExportGenerator().invoiceCSV(selectedInvoices), filename: "factures")
        case (.invoices, .csvLines):
            saveCSV(ExportGenerator().invoiceLinesCSV(selectedInvoices), filename: "factures-lignes")
        case (.invoices, .electronic):
            exportElectronicInvoices()
        case (.orders, .csvList):
            saveCSV(ExportGenerator().orderCSV(selectedOrders), filename: "commandes")
        case (.orders, .csvLines):
            saveCSV(ExportGenerator().orderLinesCSV(selectedOrders), filename: "commandes-lignes")
        case (.orders, .electronic):
            exportElectronicOrders()
        }
    }

    private func saveCSV(_ csv: String, filename: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "\(filename).csv"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try ExportGenerator().writeCSV(csv, to: url)
                exportLog = "Exporté : \(url.lastPathComponent)"
            } catch {
                exportLog = "Erreur : \(error)"
            }
        }
    }

    private func exportElectronicInvoices() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Exporter ici"
        if panel.runModal() != .OK, panel.url == nil { return }
        guard let dir = panel.url else { return }
        var ok = 0
        var failed = 0
        var skipped = 0
        let gen = FacturXGenerator()
        for inv in selectedInvoices {
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
        exportLog = "\(ok) fichier(s) généré(s)\(failed > 0 ? ", \(failed) échec(s)" : "")\(skipped > 0 ? ", \(skipped) avoir(s) interne(s) ignoré(s)" : "")"
    }

    private func exportElectronicOrders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Exporter ici"
        if panel.runModal() != .OK, panel.url == nil { return }
        guard let dir = panel.url else { return }
        var ok = 0
        var failed = 0
        let gen = OrderXGenerator()
        for order in selectedOrders {
            do {
                let data = try gen.generate(order: order)
                let name = "commande-\(order.number).pdf"
                try data.write(to: dir.appendingPathComponent(name))
                ok += 1
            } catch {
                failed += 1
            }
        }
        exportLog = "\(ok) fichier(s) généré(s)\(failed > 0 ? ", \(failed) échec(s)" : "")"
    }
}

struct OrderToInvoiceSheet: View {
    let orders: [SalesOrder]
    let onCreate: (SalesOrder) -> Void
    let onCancel: () -> Void
    @State private var query = ""
    @State private var selectedOrderID: UUID?

    private var filteredOrders: [SalesOrder] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return orders }
        return orders.filter { order in
            order.number.lowercased().contains(q)
                || order.buyer.name.lowercased().contains(q)
                || order.seller.name.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Créer une facture depuis une commande").font(.headline)
                Spacer()
            }
            .padding(12)
            Divider()
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Rechercher (numéro, acheteur, client…)", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            Divider()
            if filteredOrders.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "cart").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Aucune commande disponible dans votre périmètre.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(Array(filteredOrders.enumerated()), id: \.element.id) { _, order in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(order.number).font(.headline)
                            Text("\(order.seller.name.isEmpty ? "Sans client" : order.seller.name)")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(String(format: "%.2f %@ TTC", order.grandTotal, order.currency))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(order.issueDate, format: .dateTime.day().month().year())
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selectedOrderID = order.id }
                    .background(selectedOrderID == order.id ? Color.accentColor.opacity(0.15) : Color.clear)
                }
            }
            Divider()
            HStack {
                Button("Annuler", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Créer la facture") {
                    if let order = filteredOrders.first(where: { $0.id == selectedOrderID }) {
                        onCreate(order)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedOrderID == nil)
            }
            .padding(12)
        }
        .frame(width: 520, height: 420)
    }
}

struct InvoicesTabView: View {
    @EnvironmentObject var store: InvoiceStore
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var orderStore: OrderStore
    @Binding var selectedID: UUID?
    @State private var query = ""
    @State private var typeFilter: InvoiceTypeFilter = .all
    @State private var showOrderPicker = false
    @State private var showExport = false

    var filteredInvoices: [Invoice] {
        var result = store.invoices
        if let scope = auth.visibleInvoiceCompanyIDs(for: auth.currentUser) {
            result = result.filter { inv in
                if let cid = inv.companyID { return scope.contains(cid) }
                return false
            }
        }
        switch typeFilter {
        case .all:
            break
        case .invoice:
            result = result.filter { !$0.type.isCreditNote }
        case .creditNote:
            result = result.filter { $0.type.isCreditNote }
        }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return result }
        return result.filter { invoice in
            invoice.number.lowercased().contains(q)
                || invoice.buyer.name.lowercased().contains(q)
                || (invoice.buyer.siren ?? "").lowercased().contains(q)
                || (invoice.seller.name.lowercased()).contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    Menu {
                        Button {
                            let draft = store.newDraft(companyID: defaultCompanyID(),
                                                       preferredSellerEntryID: auth.currentUser?.defaultSellerEntryID)
                            store.upsert(draft)
                            selectedID = draft.id
                        } label: { Label("Facture vierge", systemImage: "doc") }
                        Button {
                            showOrderPicker = true
                        } label: { Label("Facture depuis une commande", systemImage: "cart") }
                    } label: { Label("Nouvelle facture", systemImage: "plus") }
                        .buttonStyle(.borderedProminent)
                    Text("Factures").font(.title2.bold())
                    Picker("Filtre", selection: $typeFilter) {
                        ForEach(InvoiceTypeFilter.allCases, id: \.self) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                    Spacer()
                    Button { showExport = true } label: { Label("Exporter", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.bordered)
                }
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Rechercher (numéro, client, SIREN…)", text: $query)
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
                if filteredInvoices.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text").font(.largeTitle).foregroundStyle(.secondary)
                        Text("Aucune facture.")
                            .foregroundStyle(.secondary)
                        Button("Nouvelle facture") {
                            let draft = store.newDraft(companyID: defaultCompanyID())
                            store.upsert(draft)
                            selectedID = draft.id
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filteredInvoices, selection: Binding(
                        get: { selectedID },
                        set: { id in selectedID = id }
                    )) { invoice in
                        VStack(alignment: .leading) {
                            HStack {
                                Text(invoice.number).font(.headline)
                                Spacer()
                                Text(invoice.issueDate, format: .dateTime.day().month().year())
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            HStack(spacing: 6) {
                                Image(systemName: invoice.status.systemImage)
                                    .foregroundColor(Color(hex: invoice.status.hexColor))
                                    .font(.caption2)
                                Text(invoice.status.label).font(.caption2)
                                    .foregroundColor(Color(hex: invoice.status.hexColor))
                                Text(invoice.type == .creditNote ? "Avoir" : invoice.type.isInternalCreditNote ? "Avoir interne" : "Facture")
                                    .font(.caption2).foregroundStyle(invoice.type.isCreditNote ? Color.orange : Color.accentColor)
                                Spacer()
                            }
                            Text("\(invoice.buyer.name.isEmpty ? "Sans client" : invoice.buyer.name)")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(String(format: "%.2f %@ TTC", invoice.grandTotal, invoice.currency))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .contextMenu {
                            Button {
                                let credit = store.newCreditNote(from: invoice)
                                store.upsert(credit)
                                selectedID = credit.id
                            } label: { Label("Créer un avoir", systemImage: "arrow.uturn.backward.circle") }
                            .disabled(invoice.type.isCreditNote)
                            Divider()
                            Button(role: .destructive) {
                                store.invoices.removeAll { $0.id == invoice.id }
                                store.save()
                                if selectedID == invoice.id { selectedID = nil }
                            } label: { Label("Supprimer", systemImage: "trash") }
                        }
                    }
                    .frame(minWidth: 200, idealWidth: 260, maxWidth: 300)
                }

                if let id = selectedID,
                   store.invoices.contains(where: { $0.id == id }) {
                    InvoiceEditorView(invoice: binding(for: id))
                        .frame(minWidth: 380)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass").font(.largeTitle).foregroundStyle(.secondary)
                        Text("Sélectionnez ou créez une facture")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .sheet(isPresented: $showOrderPicker) {
            OrderToInvoiceSheet(
                orders: scopedOrders,
                onCreate: { order in
                    let number = store.nextNumber(companyID: order.companyID)
                    let invoice = order.toInvoice(number: number)
                    store.upsert(invoice)
                    selectedID = invoice.id
                    showOrderPicker = false
                },
                onCancel: { showOrderPicker = false }
            )
        }
        .sheet(isPresented: $showExport) {
            ExportSheet(
                invoices: scopedInvoices,
                orders: scopedOrders,
                isPresented: $showExport
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

    private var scopedInvoices: [Invoice] {
        var result = store.invoices
        if let scope = auth.visibleInvoiceCompanyIDs(for: auth.currentUser) {
            result = result.filter { inv in
                if let cid = inv.companyID { return scope.contains(cid) }
                return false
            }
        }
        return result.sorted { $0.issueDate > $1.issueDate }
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

struct InvoiceEditorView: View {
    @Binding var invoice: Invoice
    @EnvironmentObject var store: InvoiceStore
    @EnvironmentObject var auth: AuthStore
    @State private var exportError: String?
    @State private var exportedURL: URL?
    @State private var validation: FacturXValidationResult?
    @State private var showValidation = false
    @State private var isLocked = false
    @State private var showUnlockAlert = false

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
        VStack(spacing: 0) {
            HStack {
                Text("Édition : \(invoice.number)").font(.title2.bold())
                if isLocked {
                    Label("Lecture seule", systemImage: "lock.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .overlay(Capsule().stroke(.secondary, lineWidth: 0.5))
                }
                Spacer()
                if isLocked {
                    Button { showUnlockAlert = true } label: {
                        Label("Modifier", systemImage: "lock.open")
                    }
                    .buttonStyle(.bordered)
                    .help("Repasser en édition (la facture n'est plus protégée)")
                } else if validation?.isValid == true {
                    Button { isLocked = true } label: {
                        Label("Verrouiller", systemImage: "lock")
                    }
                    .buttonStyle(.bordered)
                    .help("Protéger la facture validée en lecture seule")
                }
                Button("Valider") { runValidation() }
                    .buttonStyle(.bordered)
                    .disabled(isLocked)
                if invoice.type.isInternalCreditNote {
                    Button("Exporter PDF") { exportPlainPDF() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Exporter XML") { exportXML() }
                        .buttonStyle(.bordered)
                    Button("Générer le Factur-X") { export() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
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
                        if !linkedCreditNotes.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.uturn.backward.circle.fill")
                                    .foregroundStyle(.orange)
                                Text(linkedCreditNotes.count == 1
                                     ? "Avoir lié : \(linkedCreditNotes[0].number)"
                                     : "Avoirs liés : \(linkedCreditNotes.map { $0.number }.joined(separator: ", "))")
                                    .font(.caption.bold())
                                Spacer()
                            }
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.12)))
                        }
                        HStack(alignment: .top, spacing: 24) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    LabeledContent {
                                        TextField("", text: $invoice.number).frame(width: 160)
                                    } label: {
                                        HStack(spacing: 3) {
                                            Text("Numéro *").foregroundColor(.red)
                                            InfoBadge(text: "BT-1 — Numéro unique de la facture. Obligatoire.")
                                        }
                                    }
                                    HStack(spacing: 3) {
                                        Picker("Type", selection: $invoice.type) {
                                            ForEach(InvoiceTypeCode.allCases, id: \.self) { Text($0.label).tag($0) }
                                        }.frame(width: 260)
                                        InfoBadge(text: "BT-3 — Code type. 380 facture, 381 avoir, 384 rectificative.")
                                    }
                                }
                                HStack {
                                    HStack(spacing: 3) {
                                        DatePicker("Date", selection: $invoice.issueDate, displayedComponents: .date)
                                        InfoBadge(text: "BT-2 — Date d'émission de la facture. Obligatoire.")
                                    }
                                    HStack(spacing: 3) {
                                        DatePicker("Échéance", selection: $invoice.dueDate, displayedComponents: .date)
                                        InfoBadge(text: "BT-9 — Date d'échéance du paiement. Obligatoire si non déduit des conditions.")
                                    }
                                }
                                HStack(spacing: 3) {
                                    TextField("Référence commande (BT-13)", text: Binding($invoice.purchaseOrderRef, replacingNilWith: "")).frame(width: 260)
                                    InfoBadge(text: "BT-13 — Référence de la commande acheteur. Remontée en haut de la facture.")
                                }
                                if invoice.type.requiresPrecedingInvoice || invoice.type == .internalCreditNote {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Référence et date de la facture liée :").font(.caption.bold())
                                        HStack(spacing: 3) {
                                            TextField("N° facture liée", text: Binding($invoice.precedingInvoiceRef, replacingNilWith: "")).frame(width: 160)
                                            InfoBadge(text: "BT-25 — Numéro de la facture antérieure référencée. Obligatoire pour un avoir, une rectificative ou un solde.")
                                            DatePicker("Date facture liée", selection: Binding(
                                                get: { invoice.precedingInvoiceDate ?? Date() },
                                                set: { invoice.precedingInvoiceDate = $0 }
                                            ), displayedComponents: .date)
                                            InfoBadge(text: "BT-26 — Date d'émission de la facture antérieure référencée.")
                                        }
                                    }
                                }
                                if invoice.type.isDeposit || invoice.type.isFinalSettlement {
                                    HStack(spacing: 3) {
                                        Text("Acompte déjà payé").font(.caption)
                                        TextField("0,00", value: $invoice.prepaidAmount, format: .number)
                                            .frame(width: 120).textFieldStyle(.roundedBorder)
                                        Text(invoice.currency).font(.caption).foregroundStyle(.secondary)
                                        InfoBadge(text: "BT-105 — Montant des acomptes déjà payés (PrepaidAmount). Sert au calcul du net à payer sur une facture de solde.")
                                    }
                                }
                                HStack {
                                    Picker("Profil Factur-X", selection: $invoice.profile) {
                                        ForEach(FacturXProfile.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                                    }
                                    NormRefPicker("Devise", options: NormRefs.currencies, code: $invoice.currency).frame(width: 160)
                                    TextField("Référence acheteur", text: Binding($invoice.buyerReference, replacingNilWith: ""))
                                }
                                HStack {
                                    HStack(spacing: 3) {
                                        Picker("Mode facturation (BT-23)", selection: $invoice.billingMode) {
                                            ForEach(BillingMode.allCases, id: \.self) { Text($0.label).tag($0) }
                                        }.frame(width: 320)
                                        InfoBadge(text: "BT-23 — Mode de facturation (B/S/M). Requis pour le cycle de vie PDP.")
                                    }
                                }
                                companyScopePicker
                                DisclosureGroup("Autres références") {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(spacing: 3) {
                                            TextField("Réf. contrat (BT-17)", text: Binding($invoice.contractRef, replacingNilWith: "")).frame(width: 220)
                                            InfoBadge(text: "BT-17 — Référence du contrat.")
                                        }
                                        HStack(spacing: 3) {
                                            TextField("Réf. appel d'offres (BT-18)", text: Binding($invoice.tenderRef, replacingNilWith: "")).frame(width: 220)
                                            InfoBadge(text: "BT-18 — Référence de l'appel d'offres.")
                                        }
                                        HStack(spacing: 3) {
                                            TextField("Réf. bon de réception (BT-19)", text: Binding($invoice.receivingAdviceRef, replacingNilWith: "")).frame(width: 220)
                                            InfoBadge(text: "BT-19 — Référence de l'avis de réception.")
                                        }
                                        HStack(spacing: 3) {
                                            TextField("Réf. bon de livraison (BT-20)", text: Binding($invoice.despatchAdviceRef, replacingNilWith: "")).frame(width: 220)
                                            InfoBadge(text: "BT-20 — Référence de l'avis d'expédition.")
                                        }
                                    }
                                }
                                .font(.caption)
                            }
                            VStack(alignment: .trailing) {
                                row("Total HT", invoice.lineTotal)
                                ForEach(invoice.vatBreakdown, id: \.rate) { item in
                                    row("TVA \(String(format: "%.0f%%", item.rate))", item.amount)
                                }
                                row("Total TTC", invoice.grandTotal, bold: true)
                                if invoice.prepaidAmount > 0 {
                                    row("Acompte déjà payé", -invoice.prepaidAmount)
                                    row("Net à payer", invoice.netToPay, bold: true)
                                }
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
                        }
                    }.padding(8)
                }.lockable(isLocked)

                HStack(alignment: .top, spacing: 12) {
                    GroupBox("Émetteur (vous)") {
                        PartySection(party: $invoice.seller, role: .seller, onPartyPicked: { p in
                            invoice.paymentIBAN = p.iban
                            invoice.paymentBIC = p.bic
                            if let pt = p.paymentTerms, !pt.isEmpty { invoice.paymentTerms = pt }
                        })
                    }.lockable(isLocked)
                    GroupBox("Destinataire") {
                        PartySection(party: $invoice.buyer, role: .buyer)
                    }.lockable(isLocked)
                }

                GroupBox("Lignes") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach($invoice.lines) { $line in
                            HStack {
                                HStack(spacing: 2) {
                                    TextField("Désignation *", text: $line.name).frame(minWidth: 220)
                                    InfoBadge(text: "BT-153 — Désignation de la ligne. Obligatoire.")
                                }
                                HStack(spacing: 2) {
                                    TextField("Commande", text: Binding($line.orderReference, replacingNilWith: ""))
                                        .frame(width: 140)
                                    InfoBadge(text: "BT-132 — Référence de commande liée à la ligne.")
                                }
                                HStack(spacing: 2) {
                                    DoubleField("Qté", value: $line.quantity, format: .number)
                                    InfoBadge(text: "BT-149 — Quantité. Doit être positive (facture) ou négative (avoir).")
                                }
                                HStack(spacing: 2) {
                                    NormRefPicker("Unité", options: NormRefs.units, code: $line.unit).frame(width: 180)
                                    InfoBadge(text: "BT-150 — Unité de mesure (UN/ECE Rec 20).")
                                }
                                HStack(spacing: 2) {
                                    DoubleField("P.U. HT", value: $line.unitPrice, format: .number)
                                    InfoBadge(text: "BT-146 — Prix unitaire HT.")
                                }
                                HStack(spacing: 2) {
                                    DoubleField("TVA %", value: $line.vatRate, format: .number)
                                    InfoBadge(text: "BT-151 — Taux de TVA appliqué (%).")
                                }
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
                }.lockable(isLocked)

                GroupBox("Paiement") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            HStack(spacing: 3) {
                                TextField("IBAN", text: Binding($invoice.paymentIBAN, replacingNilWith: ""))
                                InfoBadge(text: "BT-84 — IBAN pour le virement SEPA.")
                            }
                            HStack(spacing: 3) {
                                TextField("BIC", text: Binding($invoice.paymentBIC, replacingNilWith: ""))
                                InfoBadge(text: "BT-85 — BIC de la banque (requis si IBAN hors SEPA).")
                            }
                        }
                        TextField("Conditions de paiement", text: Binding($invoice.paymentTerms, replacingNilWith: ""))
                    }.padding(8)
                }.lockable(isLocked)

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
                }.lockable(isLocked)
            }.padding()
        }
            .alert("Repasser en modification ?", isPresented: $showUnlockAlert) {
                Button("Annuler", role: .cancel) { }
                Button("Modifier", role: .destructive) { isLocked = false }
            } message: {
                Text("La facture était verrouillée en lecture seule après validation conforme. En la déverrouillant, vous reprenez l'édition ; pensez à valider de nouveau avant tout dépôt PDP.")
            }
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

    @ViewBuilder
    private var companyScopePicker: some View {
        let visible = auth.visibleSocieties(for: auth.currentUser)
        if visible.count > 1 {
            HStack(spacing: 3) {
                Picker("Société (périmètre)", selection: Binding(
                    get: { invoice.companyID ?? visible.first?.id ?? UUID() },
                    set: { invoice.companyID = $0 }
                )) {
                    ForEach(visible) { s in Text(s.displayName).tag(s.id) }
                }.frame(width: 320)
                InfoBadge(text: "Société émettrice du périmètre de l'utilisateur. La facture est rattachée à cette société.")
            }
        } else if visible.count == 1, let s = visible.first, invoice.companyID == nil {
            HStack(spacing: 3) {
                Text("Société : \(s.displayName)").font(.caption).foregroundStyle(.secondary)
                Button {
                    invoice.companyID = s.id
                } label: { Text("Rattacher") }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var linkedCreditNotes: [Invoice] {
        guard !invoice.number.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let scope = auth.visibleInvoiceCompanyIDs(for: auth.currentUser)
        return store.invoices.filter { inv in
            guard inv.type.isCreditNote
                && (inv.precedingInvoiceRef ?? "").trimmingCharacters(in: .whitespaces) == invoice.number.trimmingCharacters(in: .whitespaces) else { return false }
            if let scope = scope, let cid = inv.companyID { return scope.contains(cid) }
            if scope != nil && inv.companyID == nil { return false }
            return true
        }
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
                    warnings: preCheck.warnings + postCheck.warnings,
                    businessRules: preCheck.businessRules
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
                    warnings: preCheck.warnings + postCheck.warnings,
                    businessRules: preCheck.businessRules
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

    private func exportPlainPDF() {
        exportError = nil
        exportedURL = nil
        store.upsert(invoice)
        let data = FacturXGenerator().generateVisiblePDF(invoice: invoice)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "avoir-interne-\(invoice.number).pdf"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try data.write(to: url)
                exportedURL = url
            } catch {
                exportError = "\(error)"
            }
        }
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
                    HStack(spacing: 4) {
                        Image(systemName: invoice.status.systemImage)
                            .foregroundColor(Color(hex: invoice.status.hexColor))
                            .font(.caption2)
                        Picker("Statut", selection: $invoice.status) {
                            ForEach(InvoiceStatus.allCases, id: \.self) { s in
                                Label(s.label, systemImage: s.systemImage).tag(s)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 200)
                        .help("Statut de la facture (modifiable à tout moment)")
                    }
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
                if !v.businessRules.isEmpty {
                    Divider().padding(.vertical, 2)
                    Text("Règles métier EN 16931 :").font(.caption.bold())
                    ForEach(v.businessRules) { br in
                        HStack(alignment: .top, spacing: 4) {
                            Text(br.ruleId)
                                .font(.caption.bold().monospaced())
                                .foregroundStyle(br.severity == .error ? .red : .orange)
                                .frame(width: 84, alignment: .leading)
                            Text(br.message)
                                .font(.caption)
                                .foregroundStyle(br.severity == .error ? .red : .orange)
                        }
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
    var onPartyPicked: ((InvoiceParty) -> Void)? = nil
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

            PartyEditorView(party: $party, isFournisseur: role == .seller, directory: directory, onPickContact: { updatePartyFromContact($0) }, onPickRouting: { updatePartyFromRouting($0) }, onPartyPicked: { p in onPartyPicked?(p) })
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

struct PartyPickerSheet: View {
    let role: PartySection.Role
    let onPick: (DirectoryEntry) -> Void

    @EnvironmentObject var directory: PartyDirectory
    @EnvironmentObject var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var creatingNew = false
    @State private var editingEntry: DirectoryEntry?

    var filtered: [DirectoryEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let roleKind = role.defaultKind
        var active = directory.entries.filter {
            !$0.isArchived && ($0.kind == roleKind || $0.kind == .both)
        }
        if role == .seller, let scope = auth.visibleDirectoryEntryIDs(for: auth.currentUser) {
            active = active.filter { scope.contains($0.id) }
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

    private var canCreateNew: Bool {
        if role == .seller { return auth.currentUser?.isAdmin == true }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Annuaire — choisir \(role.title.lowercased())").font(.headline)
                Spacer()
                if canCreateNew {
                    Button {
                        creatingNew = true
                    } label: { Label("Nouveau", systemImage: "plus") }
                        .buttonStyle(.bordered)
                }
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

struct PartyExportSheet: View {
    let entries: [DirectoryEntry]
    @Binding var isPresented: Bool
    @State private var exportLog = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Export des tiers").font(.headline)
                Spacer()
            }.padding(12)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Text("\(entries.count) tier(s) à exporter (selon le filtre et le périmètre).")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Format : CSV compatible Excel (UTF-8, séparateur ;). Toutes les données : raison sociale, type, SIREN, SIRET, TVA, adresse, contact, endpoint, IBAN/BIC, conditions de paiement, note, archive.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(12)
            Spacer()
            Divider()
            HStack {
                Button("Fermer") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if !exportLog.isEmpty {
                    Text(exportLog).font(.caption).foregroundStyle(.secondary)
                }
                Button("Exporter") { runExport() }
                    .buttonStyle(.borderedProminent)
                    .disabled(entries.isEmpty)
            }.padding(12)
        }
        .frame(width: 520, height: 280)
    }

    private func runExport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "tiers.csv"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try ExportGenerator().writeCSV(ExportGenerator().directoryCSV(entries), to: url)
                exportLog = "Exporté : \(url.lastPathComponent)"
            } catch {
                exportLog = "Erreur : \(error)"
            }
        }
    }
}

struct PartyImportSheet: View {
    @Binding var isPresented: Bool
    let onImport: ([DirectoryEntry]) -> Void
    @State private var fileURL: URL?
    @State private var result: ExportGenerator.PartyImportResult?
    @State private var importLog = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Import des tiers").font(.headline)
                Spacer()
            }.padding(12)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Text("Sélectionnez un fichier CSV. Colonnes obligatoires : Raison sociale, SIREN. Toutes les autres colonnes sont optionnelles (Type, SIRET, TVA, Rue, Code postal, Ville, Pays, Contact (nom), Contact (email), Contact (tél.), Endpoint ID, Schéma endpoint, IBAN, BIC, Conditions paiement, Note).")
                    .font(.caption).foregroundStyle(.secondary)
                Button {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.commaSeparatedText]
                    if panel.runModal() == .OK, let url = panel.url {
                        do {
                            let raw = try String(contentsOf: url, encoding: .utf8)
                            let res = ExportGenerator().parseDirectoryCSV(raw)
                            fileURL = url
                            result = res
                            importLog = "\(res.entries.count) tier(s) à importer\(res.errors.isEmpty ? "" : ", \(res.errors.count) avertissement(s)")"
                        } catch {
                            importLog = "Erreur de lecture : \(error)"
                        }
                    }
                } label: { Label("Choisir un fichier CSV…", systemImage: "doc") }
                    .buttonStyle(.bordered)
                if let r = result {
                    if !r.errors.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Avertissements :").font(.caption.bold())
                            ForEach(Array(r.errors.enumerated()), id: \.offset) { _, msg in
                                Text("• \(msg)").font(.caption2).foregroundStyle(.orange)
                            }
                        }
                    }
                    if !r.entries.isEmpty {
                        Text(importLog).font(.caption).foregroundStyle(.secondary)
                    }
                } else if !importLog.isEmpty {
                    Text(importLog).font(.caption).foregroundStyle(.red)
                }
            }.padding(12)
            Spacer()
            Divider()
            HStack {
                Button("Fermer") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Importer") {
                    if let r = result { onImport(r.entries) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(result?.entries.isEmpty ?? true)
            }.padding(12)
        }
        .frame(width: 560, height: 420)
    }
}

struct DirectoryView: View {
    @EnvironmentObject var directory: PartyDirectory
    @EnvironmentObject var tagStore: TagStore
    @EnvironmentObject var kindColors: KindColorStore
    @EnvironmentObject var auth: AuthStore
    @State private var query = ""
    @State private var editingEntry: DirectoryEntry?
    @State private var creatingNew = false
    @State private var showArchived = false
    @State private var selectedEntry: DirectoryEntry?
    @State private var showExport = false
    @State private var showImport = false
    @State private var importResult: ExportGenerator.PartyImportResult?

    private var scope: Set<UUID>? { auth.visibleInvoiceCompanyIDs(for: auth.currentUser) }

    private var canManageFournisseurs: Bool { auth.currentUser?.isAdmin == true }

    var filtered: [DirectoryEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var base = directory.entries.filter { showArchived || !$0.isArchived }
        if let scope = scope {
            base = base.filter { entry in
                if entry.kind == .fournisseur { return scope.contains(entry.id) }
                if entry.kind == .both { return scope.contains(entry.id) }
                if let cid = entry.companyID { return scope.contains(cid) }
                return false
            }
        }
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.displayName.lowercased().contains(q)
                || ($0.party.siren ?? "").lowercased().contains(q)
                || ($0.party.siret ?? "").lowercased().contains(q)
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
                    Button { showImport = true } label: { Label("Importer", systemImage: "square.and.arrow.down") }
                        .buttonStyle(.bordered)
                    Button { showExport = true } label: { Label("Exporter", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.bordered)
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
                                    .background(Color(hex: kindColors.hexColor(for: entry.kind)).opacity(0.2), in: Capsule())
                                    .foregroundColor(Color(hex: kindColors.hexColor(for: entry.kind)))
                                ForEach(entry.tagIDs.compactMap({ id in tagStore.tags.first(where: { $0.id == id }) }), id: \.id) { tag in
                                    Text(tag.name).font(.caption2)
                                        .padding(.horizontal, 6).padding(.vertical, 1)
                                        .background(Color(hex: tag.hexColor).opacity(0.2), in: Capsule())
                                        .foregroundColor(Color(hex: tag.hexColor))
                                }
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
                            if canEditEntry(entry) {
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
                            } else {
                                Text("Fournisseur : modification réservée à l'administrateur")
                            }
                        }
                    }
                    .frame(minWidth: 220, idealWidth: 320, maxWidth: 360)
                }

                DirectoryDetailView(
                    entry: selectedEntry,
                    canEdit: selectedEntry.map { canEditEntry($0) } ?? true,
                    onEdit: { entry in editingEntry = entry },
                    onArchive: { entry in
                        guard canEditEntry(entry) else { return }
                        var e = entry
                        e.isArchived.toggle()
                        directory.upsert(e)
                        selectedEntry = e
                    },
                    onDelete: { entry in
                        guard canEditEntry(entry) else { return }
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
            DirectoryEditorView(initialKind: .client, defaultCompanyID: defaultCompanyID()) { newEntry in
                directory.upsert(newEntry)
                creatingNew = false
            }
        }
        .sheet(isPresented: $showExport) {
            PartyExportSheet(entries: filtered, isPresented: $showExport)
        }
        .sheet(isPresented: $showImport) {
            PartyImportSheet(
                isPresented: $showImport,
                onImport: { newEntries in
                    for e in newEntries { directory.upsert(e) }
                    showImport = false
                }
            )
        }
    }

    private func canEditEntry(_ entry: DirectoryEntry) -> Bool {
        if entry.kind == .fournisseur || entry.kind == .both { return canManageFournisseurs }
        return true
    }

    private func defaultCompanyID() -> UUID? {
        let visible = auth.visibleSocieties(for: auth.currentUser)
        if visible.count == 1 { return visible.first?.id }
        return nil
    }
}

struct DirectoryDetailView: View {
    let entry: DirectoryEntry?
    let canEdit: Bool
    let onEdit: (DirectoryEntry) -> Void
    let onArchive: (DirectoryEntry) -> Void
    let onDelete: (DirectoryEntry) -> Void
    @EnvironmentObject var tagStore: TagStore
    @EnvironmentObject var kindColors: KindColorStore
    @EnvironmentObject var directory: PartyDirectory
    @State private var showRoutingEditor = false
    @State private var showContactEditor = false
    @State private var editingAddress: PartyRoutingAddress?
    @State private var editingContact: PartyContact?

    private var currentEntry: DirectoryEntry? {
        guard let id = entry?.id else { return nil }
        return directory.entries.first(where: { $0.id == id }) ?? entry
    }

    private func routingBinding(entry: DirectoryEntry) -> Binding<[PartyRoutingAddress]> {
        Binding(
            get: { directory.entries.first(where: { $0.id == entry.id })?.routingAddresses ?? entry.routingAddresses },
            set: { newValue in
                if var e = directory.entries.first(where: { $0.id == entry.id }) {
                    e.routingAddresses = newValue
                    directory.upsert(e)
                }
            }
        )
    }

    private func contactsBinding(entry: DirectoryEntry) -> Binding<[PartyContact]> {
        Binding(
            get: { directory.entries.first(where: { $0.id == entry.id })?.contacts ?? entry.contacts },
            set: { newValue in
                if var e = directory.entries.first(where: { $0.id == entry.id }) {
                    e.contacts = newValue
                    directory.upsert(e)
                }
            }
        )
    }

    var body: some View {
        if let entry = currentEntry {
            VStack(spacing: 0) {
                HStack {
                    Text(entry.displayName).font(.headline)
                    Text(entry.kind.label).font(.caption)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color(hex: kindColors.hexColor(for: entry.kind)).opacity(0.2), in: Capsule())
                        .foregroundColor(Color(hex: kindColors.hexColor(for: entry.kind)))
                    Spacer()
                    Button { onEdit(entry) } label: { Label("Modifier", systemImage: "pencil") }
                        .buttonStyle(.bordered)
                        .disabled(!canEdit)
                    Button { onArchive(entry) } label: {
                        Label(entry.isArchived ? "Désarchiver" : "Archiver",
                              systemImage: entry.isArchived ? "tray.and.arrow.up" : "archivebox")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canEdit)
                    Button(role: .destructive) { onDelete(entry) } label: { Label("Supprimer", systemImage: "trash") }
                        .buttonStyle(.bordered)
                        .disabled(!canEdit)
                }
                .padding(12)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Identité").font(.headline)
                        detailRow("Type", entry.kind.label)
                        detailRow("Nom", entry.party.name)
                        if !entry.tagIDs.isEmpty {
                            HStack(alignment: .top) {
                                Text("Tags").font(.callout.bold()).frame(width: 160, alignment: .leading)
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(entry.tagIDs.compactMap({ id in tagStore.tags.first(where: { $0.id == id }) }), id: \.id) { tag in
                                        Text(tag.name).font(.caption)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Color(hex: tag.hexColor).opacity(0.2), in: Capsule())
                                            .foregroundColor(Color(hex: tag.hexColor))
                                    }
                                }
                                Spacer()
                            }
                        }

                        Divider()
                        Text("Identifiants").font(.headline)
                        if let s = entry.party.siren, !s.isEmpty {
                            detailRow("SIREN", s)
                        }
                        if let st = entry.party.siret, !st.isEmpty {
                            HStack(alignment: .top) {
                                Text("SIRET").font(.callout.bold()).frame(width: 160, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(st).font(.body)
                                    if SireneValidator.isValidSiret(st) {
                                        Label("valide (Luhn)", systemImage: "checkmark.circle.fill")
                                            .font(.caption2).foregroundStyle(.green)
                                    } else {
                                        Label("invalide (Luhn)", systemImage: "exclamationmark.triangle.fill")
                                            .font(.caption2).foregroundStyle(.orange)
                                    }
                                }
                                Spacer()
                            }
                        }
                        if let v = entry.party.vatNumber, !v.isEmpty { detailRow("N° TVA", v) }
                        if let e = entry.party.endpointID, !e.isEmpty {
                            detailRow("Ident. élec. (BT-49/34)", e)
                        }
                        if !entry.party.endpointSchemeID.trimmingCharacters(in: .whitespaces).isEmpty {
                            detailRow("Scheme ident. élec.", entry.party.endpointSchemeID)
                        }
                        detailRow("Scheme légal", entry.party.legalSchemeID)

                        Divider()
                        Text("Adresse").font(.headline)
                        if !entry.party.street.trimmingCharacters(in: .whitespaces).isEmpty {
                            detailRow("Rue", entry.party.street)
                        }
                        if !entry.party.postcode.trimmingCharacters(in: .whitespaces).isEmpty {
                            detailRow("Code postal", entry.party.postcode)
                        }
                        if !entry.party.city.trimmingCharacters(in: .whitespaces).isEmpty {
                            detailRow("Ville", entry.party.city)
                        }
                        if !entry.party.country.trimmingCharacters(in: .whitespaces).isEmpty {
                            detailRow("Pays", entry.party.country)
                        }

                        Divider()
                        HStack {
                            Text("Contact(s)").font(.headline)
                            Spacer()
                            Button {
                                editingContact = nil
                                showContactEditor = true
                            } label: { Label("Créer un contact", systemImage: "plus.circle") }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                        if !entry.contacts.isEmpty {
                            ForEach(entry.contacts) { ct in
                                HStack(alignment: .top, spacing: 8) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            Text(ct.name.trimmingCharacters(in: .whitespaces).isEmpty ? "(sans nom)" : ct.name).font(.callout.bold())
                                            if ct.isDefault {
                                                Text("défaut").font(.caption).padding(.horizontal, 5).padding(.vertical, 1)
                                                    .background(Color.accentColor.opacity(0.2), in: Capsule())
                                            }
                                            if !ct.isActive {
                                                Text("inactif").font(.caption).padding(.horizontal, 5).padding(.vertical, 1)
                                                    .background(Color.gray.opacity(0.2), in: Capsule())
                                            }
                                        }
                                        if let e = ct.email?.trimmingCharacters(in: .whitespaces), !e.isEmpty { Text("Email : \(e)").font(.caption).foregroundColor(.secondary) }
                                        if let p = ct.phone?.trimmingCharacters(in: .whitespaces), !p.isEmpty { Text("Tél : \(p)").font(.caption).foregroundColor(.secondary) }
                                        if let lbl = ct.label?.trimmingCharacters(in: .whitespaces), !lbl.isEmpty { Text("Libellé : \(lbl)").font(.caption).foregroundColor(.secondary) }
                                    }
                                    Spacer()
                                    Button {
                                        editingContact = ct
                                        showContactEditor = true
                                    } label: { Image(systemName: "pencil") }
                                        .buttonStyle(.borderless)
                                        .help("Modifier ce contact")
                                    Button(role: .destructive) {
                                        var e = entry
                                        e.contacts.removeAll { $0.id == ct.id }
                                        if e.contacts.allSatisfy({ !$0.isDefault }), !e.contacts.isEmpty {
                                            e.contacts[0].isDefault = true
                                        }
                                        directory.upsert(e)
                                    } label: { Image(systemName: "trash") }
                                        .buttonStyle(.borderless)
                                        .help("Supprimer ce contact")
                                }
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
                            }
                        } else if (entry.party.contactName?.isEmpty ?? true)
                            && (entry.party.contactEmail?.isEmpty ?? true)
                            && (entry.party.contactPhone?.isEmpty ?? true) {
                            Text("Aucun contact renseigné").font(.caption).foregroundStyle(.secondary)
                        } else {
                            if let cn = entry.party.contactName, !cn.isEmpty { detailRow("Nom", cn) }
                            if let ce = entry.party.contactEmail, !ce.isEmpty { detailRow("Email", ce) }
                            if let cp = entry.party.contactPhone, !cp.isEmpty { detailRow("Téléphone", cp) }
                        }

                        Divider()
                        HStack {
                            Text("Adresses de facturation électronique").font(.headline)
                            Spacer()
                            Button {
                                editingAddress = PartyRoutingAddress(siren: entry.party.siren ?? "")
                            } label: { Label("Créer une adresse", systemImage: "plus.circle") }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                        if entry.routingAddresses.isEmpty {
                            Text("Aucune adresse de facturation électronique renseignée").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(entry.routingAddresses) { addr in
                            HStack(alignment: .top, spacing: 8) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(addr.format.label).font(.callout.bold())
                                        if addr.isDefault {
                                            Text("défaut").font(.caption).padding(.horizontal, 5).padding(.vertical, 1)
                                                .background(Color.accentColor.opacity(0.2), in: Capsule())
                                        }
                                        if !addr.isActive {
                                            Text("inactive").font(.caption).padding(.horizontal, 5).padding(.vertical, 1)
                                                .background(Color.gray.opacity(0.2), in: Capsule())
                                        }
                                    }
                                    Text(addr.composedAddress).font(.system(.callout, design: .monospaced))
                                    if let lbl = addr.label, !lbl.isEmpty {
                                        Text("Libellé : \(lbl)").font(.caption).foregroundColor(.secondary)
                                    }
                                    if let s = addr.siret, !s.isEmpty { Text("SIRET : \(s)").font(.caption).foregroundColor(.secondary) }
                                    if let suf = addr.suffixe, !suf.isEmpty { Text("Suffixe : \(suf)").font(.caption).foregroundColor(.secondary) }
                                    if let cr = addr.codeRoutage, !cr.isEmpty { Text("Code routage : \(cr)").font(.caption).foregroundColor(.secondary) }
                                }
                                Spacer()
                                Button {
                                    editingAddress = addr
                                } label: { Image(systemName: "pencil") }
                                    .buttonStyle(.borderless)
                                    .help("Modifier cette adresse")
                                Button(role: .destructive) {
                                    var e = entry
                                    e.routingAddresses.removeAll { $0.id == addr.id }
                                    if e.routingAddresses.allSatisfy({ !$0.isDefault }), !e.routingAddresses.isEmpty {
                                        e.routingAddresses[0].isDefault = true
                                    }
                                    directory.upsert(e)
                                } label: { Image(systemName: "trash") }
                                    .buttonStyle(.borderless)
                                    .help("Supprimer cette adresse")
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
                        }

                        if let note = entry.note, !note.isEmpty {
                            Divider()
                            Text("Note").font(.headline)
                            Text(note).font(.callout).foregroundStyle(.secondary)
                        }

                        Divider()
                        Text("Statut").font(.headline)
                        if entry.isArchived {
                            Label("Tiers archivé", systemImage: "archivebox")
                                .font(.callout.bold()).foregroundStyle(.orange)
                        } else {
                            Label("Tiers actif", systemImage: "checkmark.circle")
                                .font(.callout.bold()).foregroundStyle(.green)
                        }
                    }.padding(14)
                }
            }
            .sheet(isPresented: $showRoutingEditor) {
                RoutingAddressQuickEditor(
                    siren: entry.party.siren ?? "",
                    addresses: routingBinding(entry: entry)
                )
            }
            .sheet(item: $editingAddress) { addr in
                RoutingAddressFormView(addresses: routingBinding(entry: entry), editing: addr)
            }
            .sheet(isPresented: $showContactEditor) {
                if let ct = editingContact {
                    ContactFormView(contacts: contactsBinding(entry: entry), editing: ct)
                } else {
                    ContactFormView(contacts: contactsBinding(entry: entry), editing: PartyContact())
                }
            }
            .onChange(of: showContactEditor) { showing in
                if !showing { editingContact = nil }
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
            Text(label).font(.callout.bold()).frame(width: 160, alignment: .leading)
            Text(value).font(.body)
            Spacer()
        }
    }
}
struct DirectoryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var directory: PartyDirectory
    @EnvironmentObject var tagStore: TagStore
    @EnvironmentObject var auth: AuthStore
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

    init(initialKind: DirectoryEntryKind, defaultCompanyID: UUID? = nil, onSave: @escaping (DirectoryEntry) -> Void) {
        var initial = DirectoryEntry(kind: initialKind, party: InvoiceParty(name: "", street: "", postcode: "", city: ""))
        if initialKind == .client, let cid = defaultCompanyID {
            initial.companyID = cid
        }
        _entry = State(initialValue: initial)
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

    private var canManageFournisseurs: Bool { auth.currentUser?.isAdmin == true }

    private var availableKinds: [DirectoryEntryKind] {
        if canManageFournisseurs { return DirectoryEntryKind.allCases }
        return [.client]
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
                    var entry = entry
                    if let cid = entry.companyID, !auth.availableSocieties().contains(where: { $0.id == cid }) {
                        entry.companyID = nil
                    }
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
                ForEach(availableKinds, id: \.self) { Text($0.label).tag($0) }
            }.pickerStyle(.segmented)
            .disabled(!canManageFournisseurs && entry.kind == .fournisseur)

            if entry.kind == .client || entry.kind == .both {
                GroupBox("Société (périmètre)") {
                    HStack {
                        Text("Société").frame(width: 80, alignment: .leading)
                        Picker("Société", selection: Binding<UUID?>(
                            get: { entry.companyID },
                            set: { entry.companyID = $0 }
                        )) {
                            Text("Aucune").tag(UUID?.none)
                            ForEach(auth.visibleSocieties(for: auth.currentUser)) { s in
                                Text(s.displayName).tag(Optional(s.id))
                            }
                        }
                        Spacer()
                    }.padding(4)
                }
            }

            GroupBox("Identité et adresse") {
                PartyEditorView(party: $entry.party, routingAddresses: $entry.routingAddresses, contacts: $entry.contacts, isFournisseur: entry.kind == .fournisseur || entry.kind == .both)
            }

            if !tagStore.tags.isEmpty {
                GroupBox("Tags") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(tagStore.tags) { tag in
                            Toggle(isOn: Binding(
                                get: { entry.tagIDs.contains(tag.id) },
                                set: { isOn in
                                    if isOn { entry.tagIDs.append(tag.id) }
                                    else { entry.tagIDs.removeAll { $0 == tag.id } }
                                }
                            )) {
                                HStack {
                                    Text(tag.name)
                                    Text("●").foregroundColor(Color(hex: tag.hexColor))
                                }
                            }
                        }
                    }
                }
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

struct ContactFormView: View {
    @Binding var contacts: [PartyContact]
    @State private var draft: PartyContact
    @Environment(\.dismiss) private var dismiss
    private let existingID: UUID?

    init(contacts: Binding<[PartyContact]>, editing: PartyContact) {
        _contacts = contacts
        _draft = State(initialValue: editing)
        existingID = editing.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(existingID == nil ? "Nouveau contact" : "Modifier le contact").font(.headline)
            TextField("Nom", text: $draft.name)
            TextField("Email", text: Binding($draft.email, replacingNilWith: ""))
            TextField("Téléphone", text: Binding($draft.phone, replacingNilWith: ""))
            TextField("Libellé (optionnel)", text: Binding($draft.label, replacingNilWith: ""))
            Toggle("Contact actif", isOn: $draft.isActive)
            Toggle("Contact par défaut", isOn: $draft.isDefault)
            HStack {
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Enregistrer") {
                    if draft.isDefault {
                        for i in contacts.indices { contacts[i].isDefault = false }
                    }
                    if let id = existingID, let idx = contacts.firstIndex(where: { $0.id == id }) {
                        contacts[idx] = draft
                    } else {
                        if contacts.isEmpty { draft.isDefault = true }
                        contacts.append(draft)
                    }
                    if contacts.allSatisfy({ !$0.isDefault }), !contacts.isEmpty {
                        contacts[0].isDefault = true
                    }
                    dismiss()
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }.padding(16).frame(minWidth: 420, minHeight: 320)
    }
}

struct ContactPickerSheet: View {
    let entry: DirectoryEntry
    let onPick: (PartyContact?) -> Void
    @EnvironmentObject var directory: PartyDirectory
    @Environment(\.dismiss) private var dismiss
    @State private var showEditor = false
    @State private var editing: PartyContact?
    @State private var drafts: [PartyContact]

    init(entry: DirectoryEntry, onPick: @escaping (PartyContact?) -> Void) {
        self.entry = entry
        self.onPick = onPick
        _drafts = State(initialValue: entry.contacts)
    }

    private var contactsBinding: Binding<[PartyContact]> {
        Binding(
            get: { drafts },
            set: { drafts = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Contacts — \(entry.displayName)").font(.headline)
                Spacer()
                Button("Fermer") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(12)
            Divider()
            if drafts.isEmpty {
                Text("Aucun contact. Cliquez « Nouveau » pour en créer un.")
                    .foregroundStyle(.secondary).padding()
            } else {
                List {
                    ForEach(drafts) { ct in
                        Button {
                            onPick(ct); dismiss()
                        } label: {
                            HStack(spacing: 8) {
                                if ct.isDefault {
                                    Text("défaut").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Color.accentColor.opacity(0.2), in: Capsule())
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ct.name.trimmingCharacters(in: .whitespaces).isEmpty ? "(sans nom)" : ct.name)
                                        .font(.body.weight(.medium))
                                    if let e = ct.email?.trimmingCharacters(in: .whitespaces), !e.isEmpty {
                                        Text(e).font(.caption).foregroundStyle(.secondary)
                                    }
                                    if let p = ct.phone?.trimmingCharacters(in: .whitespaces), !p.isEmpty {
                                        Text(p).font(.caption).foregroundStyle(.secondary)
                                    }
                                    if !ct.isActive {
                                        Text("inactif").font(.caption2)
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
            HStack {
                Button {
                    editing = nil
                    showEditor = true
                } label: { Label("Nouveau contact", systemImage: "plus") }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Aucun contact") { onPick(nil); dismiss() }
            }.padding(12)
        }
        .frame(minWidth: 460, minHeight: 320)
        .sheet(isPresented: $showEditor) {
            if let ct = editing {
                ContactFormView(contacts: contactsBinding, editing: ct)
            } else {
                ContactFormView(contacts: contactsBinding, editing: PartyContact())
            }
        }
        .onChange(of: showEditor) { showing in
            guard !showing else { return }
            var e = entry
            e.contacts = drafts
            directory.upsert(e)
            editing = nil
        }
    }
}

struct RoutingPickerSheet: View {
    let entry: DirectoryEntry
    let onPick: (PartyRoutingAddress?) -> Void
    @EnvironmentObject var directory: PartyDirectory
    @Environment(\.dismiss) private var dismiss
    @State private var showEditor = false
    @State private var editing: PartyRoutingAddress?
    @State private var drafts: [PartyRoutingAddress]

    init(entry: DirectoryEntry, onPick: @escaping (PartyRoutingAddress?) -> Void) {
        self.entry = entry
        self.onPick = onPick
        _drafts = State(initialValue: entry.routingAddresses)
    }

    private var routingBinding: Binding<[PartyRoutingAddress]> {
        Binding(
            get: { drafts },
            set: { drafts = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Adresses de facturation électronique — \(entry.displayName)").font(.headline)
                Spacer()
                Button("Fermer") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(12)
            Divider()
            if drafts.isEmpty {
                Text("Aucune adresse. Cliquez « Nouvelle » pour en créer une.")
                    .foregroundStyle(.secondary).padding()
            } else {
                List {
                    ForEach(drafts) { addr in
                        Button {
                            onPick(addr); dismiss()
                        } label: {
                            HStack(spacing: 8) {
                                if addr.isDefault {
                                    Text("défaut").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Color.accentColor.opacity(0.2), in: Capsule())
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(addr.format.label).font(.caption.bold())
                                    Text(addr.composedAddress).font(.system(.body, design: .monospaced))
                                    if let l = addr.label, !l.isEmpty { Text(l).font(.caption2).foregroundStyle(.secondary) }
                                    if !addr.isActive { Text("inactive").font(.caption2) }
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
            HStack {
                Button {
                    editing = nil
                    showEditor = true
                } label: { Label("Nouvelle adresse", systemImage: "plus") }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Aucune adresse") { onPick(nil); dismiss() }
            }.padding(12)
        }
        .frame(minWidth: 480, minHeight: 340)
        .sheet(isPresented: $showEditor) {
            if let addr = editing {
                RoutingAddressFormView(addresses: routingBinding, editing: addr)
            } else {
                RoutingAddressFormView(addresses: routingBinding, editing: PartyRoutingAddress(siren: entry.party.siren ?? ""))
            }
        }
        .onChange(of: showEditor) { showing in
            guard !showing else { return }
            var e = entry
            e.routingAddresses = drafts
            directory.upsert(e)
            editing = nil
        }
    }
}

struct SettingsTabView: View {
    @EnvironmentObject var auth: AuthStore
    @State private var settingsTab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $settingsTab) {
                Text("Profil").tag(0)
                if auth.currentUser?.isAdmin == true {
                    Text("Tables").tag(1)
                    Text("Application").tag(2)
                    Text("Journal").tag(3)
                }
            }
            .pickerStyle(.segmented)
            .padding(10)
            Divider()
            switch settingsTab {
            case 0:
                ProfileSettingsView()
            case 1:
                ValueTablesView()
            case 3:
                AuditLogView()
            default:
                ApplicationSettingsView()
            }
        }
    }
}

struct OrderStatusSettingsView: View {
    @EnvironmentObject var statusStore: OrderStatusStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Statuts des commandes").font(.title2.bold())
                Spacer()
                Button {
                    let id = "custom-\(UUID().uuidString.prefix(8))"
                    statusStore.append(OrderStatusOverride(id: id, label: "Nouveau statut", systemImage: "doc", hexColor: "6E6E73"))
                } label: { Label("Nouvelle valeur", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
            }
            .padding(12)
            Divider()
            Text("Personnalisez le libellé, l'icône SF Symbol et la couleur de chaque statut de commande.")
                .font(.caption).foregroundStyle(.secondary).padding(12)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(statusStore.overrides) { override in
                        statusRow(override)
                    }
                }
                .padding(12)
            }
        }
        .frame(minWidth: 480, minHeight: 420)
    }

    private func statusRow(_ override: OrderStatusOverride) -> some View {
        let idx = statusStore.overrides.firstIndex(where: { $0.id == override.id }) ?? 0
        let binding = Binding<OrderStatusOverride>(
            get: { statusStore.overrides[idx] },
            set: { statusStore.overrides[idx] = $0 }
        )
        return HStack(spacing: 12) {
            Image(systemName: binding.wrappedValue.systemImage)
                .frame(width: 22)
                .foregroundStyle(Color(hex: binding.wrappedValue.hexColor))
            TextField("Libellé", text: binding.label)
                .frame(minWidth: 180)
            TextField("Icône SF", text: binding.systemImage)
                .frame(width: 120)
            ColorPicker(selection: Binding(
                get: { Color(hex: binding.wrappedValue.hexColor) },
                set: { newColor in
                    statusStore.overrides[idx].hexColor = hexString(from: newColor)
                }
            )) {
                Text("Couleur")
            }
            .labelsHidden()
            Spacer()
            Button(role: .destructive) {
                if let i = statusStore.overrides.firstIndex(where: { $0.id == override.id }) {
                    statusStore.remove(at: i)
                }
            } label: {
                Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.borderless)
            .help("Supprimer ce statut")
        }
    }
}

struct ApplicationSettingsView: View {
    @EnvironmentObject var chorusSettings: ChorusProSettings
    @EnvironmentObject var store: InvoiceStore
    @EnvironmentObject var tagStore: TagStore
    @EnvironmentObject var kindColors: KindColorStore
    @EnvironmentObject var auth: AuthStore
    @State private var testMessage: String?
    @State private var testing = false
    @State private var dinumExpanded = true
    @State private var pisteExpanded = false
    @State private var appearanceExpanded = true
    @State private var tagsExpanded = true
    @State private var numberingExpanded = true
    @State private var newTagName = ""
    @State private var newTagHex = "555555"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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

                DisclosureGroup(isExpanded: $appearanceExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Couleurs des étiquettes de type de tiers (Client / Fournisseur / Client-Fournisseur).")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(DirectoryEntryKind.allCases, id: \.self) { kind in
                            HStack {
                                Text(kind.label).frame(width: 140, alignment: .leading)
                                ColorPicker(selection: Binding(
                                    get: { Color(hex: kindColors.hexColor(for: kind)) },
                                    set: { newColor in
                                        kindColors.colors[kind] = hexString(from: newColor)
                                        kindColors.save()
                                    }
                                )) {
                                    Text(kind.label)
                                }
                                .labelsHidden()
                                Text(kindColors.hexColor(for: kind)).font(.caption).foregroundStyle(.secondary).monospaced()
                                Spacer()
                            }
                        }
                    }.padding(8)
                } label: {
                    Label("Apparence (couleurs des types)", systemImage: "paintpalette")
                        .font(.headline)
                }

                DisclosureGroup(isExpanded: $tagsExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Définissez des tags personnalisés pour classifier vos tiers. Chaque tier peut porter plusieurs tags.")
                            .font(.caption).foregroundStyle(.secondary)
                        if tagStore.tags.isEmpty {
                            Text("Aucun tag défini.").font(.caption).foregroundStyle(.secondary)
                        } else {
                            ForEach(tagStore.tags) { tag in
                                HStack {
                                    Circle().fill(Color(hex: tag.hexColor)).frame(width: 14, height: 14)
                                    TextField("Nom du tag", text: Binding(
                                        get: { tag.name },
                                        set: { newName in
                                            var t = tag; t.name = newName; tagStore.upsert(t)
                                        }
                                    )).frame(maxWidth: 200)
                                    ColorPicker("", selection: Binding(
                                        get: { Color(hex: tag.hexColor) },
                                        set: { newColor in
                                            var t = tag; t.hexColor = hexString(from: newColor); tagStore.upsert(t)
                                        }
                                    )).labelsHidden().frame(width: 40)
                                    Button(role: .destructive) {
                                        tagStore.delete(tag)
                                    } label: { Image(systemName: "trash") }
                                        .buttonStyle(.borderless)
                                }
                            }
                        }
                        Divider()
                        Text("Ajouter un tag").font(.caption.bold())
                        HStack {
                            ColorPicker("", selection: Binding(
                                get: { Color(hex: newTagHex) },
                                set: { newTagHex = hexString(from: $0) }
                            )).labelsHidden().frame(width: 30)
                            TextField("Nom du nouveau tag", text: $newTagName)
                            Button {
                                guard !newTagName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                                tagStore.upsert(PartyTag(name: newTagName.trimmingCharacters(in: .whitespaces), hexColor: newTagHex))
                                newTagName = ""
                                newTagHex = "555555"
                            } label: { Label("Ajouter", systemImage: "plus.circle.fill") }
                                .buttonStyle(.borderedProminent)
                        }
                    }.padding(8)
                } label: {
                    Label("Tags personnalisés", systemImage: "tag")
                        .font(.headline)
                }

                DisclosureGroup(isExpanded: $numberingExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Personnalisez le format des numéros de facture. Le chrono s'incrémente automatiquement à chaque création et démarre au numéro de début défini. Le compteur est indépendant par société émettrice.")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Text("Préfixe texte").font(.caption)
                            TextField("ex. FAC", text: $store.numberPrefix)
                                .frame(width: 140)
                        }
                        Toggle("Inclure l'année", isOn: $store.numberIncludeYear)
                        HStack {
                            Text("Numéro de début").font(.caption)
                            Stepper(value: $store.numberStart, in: 1...999999) {
                                Text("\(store.numberStart)")
                            }
                        }
                        Toggle("Séparer par un \"-\"", isOn: $store.numberUseSeparator)
                        Divider()
                        HStack {
                            Text("Aperçu : ").font(.caption).foregroundStyle(.secondary)
                            Text(store.previewNextNumber(companyID: previewCompanyID())).monospaced().font(.caption.bold())
                            Spacer()
                            Button("Appliquer") { store.save() }
                                .buttonStyle(.borderedProminent)
                        }
                    }.padding(8)
                } label: {
                    Label("Numérotation des factures", systemImage: "number")
                        .font(.headline)
                }
                .onChange(of: store.numberPrefix) { _ in store.save() }
                .onChange(of: store.numberIncludeYear) { _ in store.save() }
                .onChange(of: store.numberStart) { _ in store.save() }
                .onChange(of: store.numberUseSeparator) { _ in store.save() }

                Divider()
                HStack {
                    Text("Facture_elec v0.3.0").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if let repo = URL(string: "https://github.com/guitwo63/Facture_elec") {
                        Link("GitHub", destination: repo).font(.caption)
                    }
                }

                Spacer()
            }.padding()
        }
    }

    private func previewCompanyID() -> UUID? {
        let visible = auth.visibleSocieties(for: auth.currentUser)
        if visible.count == 1 { return visible.first?.id }
        return nil
    }
}

// MARK: - Tables de valeurs paramétrées

extension DirectoryEntryKind: Identifiable {
    public var id: String { rawValue }
}

enum ValueTable: String, CaseIterable, Identifiable {
    case orderStatuses
    case tags
    case kindColors
    case currencies
    case units
    case countries
    case endpointSchemes

    var id: String { rawValue }

    var label: String {
        switch self {
        case .orderStatuses: return "Statuts des commandes"
        case .tags: return "Tags des tiers"
        case .kindColors: return "Couleurs des types de tiers"
        case .currencies: return "Devises"
        case .units: return "Unités"
        case .countries: return "Pays"
        case .endpointSchemes: return "Schémas d'identifiant"
        }
    }

    var systemImage: String {
        switch self {
        case .orderStatuses: return "list.bullet.rectangle"
        case .tags: return "tag"
        case .kindColors: return "paintpalette"
        case .currencies: return "dollarsign.circle"
        case .units: return "ruler"
        case .countries: return "globe"
        case .endpointSchemes: return "number"
        }
    }

    var isEditable: Bool {
        switch self {
        case .orderStatuses, .tags, .kindColors: return true
        default: return false
        }
    }
}

struct ValueTablesView: View {
    @EnvironmentObject var statusStore: OrderStatusStore
    @EnvironmentObject var tagStore: TagStore
    @EnvironmentObject var kindColors: KindColorStore
    @State private var selectedTable: ValueTable = .orderStatuses
    @State private var searchQuery = ""
    @State private var editingStatus: OrderStatusOverride?
    @State private var editingTag: PartyTag?
    @State private var editingKind: DirectoryEntryKind?
    @State private var newTagName = ""
    @State private var newTagHex = "555555"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filtrer les tables et les valeurs", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(10)
            Divider()
            HStack(alignment: .top, spacing: 0) {
                tablesList
                    .frame(width: 220)
                Divider()
                valuesPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(item: $editingStatus) { override in
            OrderStatusEditorSheet(override: override) { updated in
                if let i = statusStore.overrides.firstIndex(where: { $0.id == override.id }) {
                    statusStore.overrides[i] = updated
                    statusStore.save()
                }
            }
        }
        .sheet(item: $editingTag) { tag in
            TagEditorSheet(tag: tag) { updated in tagStore.upsert(updated) }
        }
        .sheet(item: $editingKind) { kind in
            KindColorEditorSheet(kind: kind, hex: kindColors.hexColor(for: kind)) { newHex in
                kindColors.colors[kind] = newHex
                kindColors.save()
            }
        }
    }

    private var filteredTables: [ValueTable] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return ValueTable.allCases }
        return ValueTable.allCases.filter { $0.label.lowercased().contains(q) }
    }

    private var tablesList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(filteredTables) { table in
                    Button {
                        selectedTable = table
                    } label: {
                        HStack {
                            Image(systemName: table.systemImage)
                                .foregroundStyle(selectedTable == table ? Color.accentColor : .secondary)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(table.label).font(.body.weight(selectedTable == table ? .semibold : .regular))
                                Text(table.isEditable ? "modifiable" : "lecture seule")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                            Spacer()
                            if selectedTable == table {
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(selectedTable == table ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private var valuesPanel: some View {
        switch selectedTable {
        case .orderStatuses: orderStatusesPanel
        case .tags: tagsPanel
        case .kindColors: kindColorsPanel
        case .currencies: refPanel(NormRefs.currencies)
        case .units: refPanel(NormRefs.units)
        case .countries: refPanel(NormRefs.countries)
        case .endpointSchemes: refPanel(NormRefs.endpointSchemes)
        }
    }

    private var orderStatusesPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Statuts des commandes").font(.title3.bold())
                Spacer()
                Button {
                    let id = "custom-\(UUID().uuidString.prefix(8))"
                    statusStore.append(OrderStatusOverride(id: id, label: "Nouveau statut", systemImage: "doc", hexColor: "6E6E73"))
                } label: { Label("Nouvelle valeur", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredStatuses) { override in
                        HStack(spacing: 10) {
                            Image(systemName: override.systemImage)
                                .frame(width: 22)
                                .foregroundStyle(Color(hex: override.hexColor))
                            Text(override.label).font(.body)
                            Text(override.systemImage).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                editingStatus = override
                            } label: { Image(systemName: "pencil") }
                                .buttonStyle(.borderless)
                                .help("Modifier ce statut")
                            Button(role: .destructive) {
                                if let i = statusStore.overrides.firstIndex(where: { $0.id == override.id }) {
                                    statusStore.remove(at: i)
                                }
                            } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                                .help("Supprimer ce statut")
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.06)))
                    }
                }
                .padding(12)
            }
        }
    }

    private var filteredStatuses: [OrderStatusOverride] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return statusStore.overrides }
        return statusStore.overrides.filter { $0.label.lowercased().contains(q) || $0.id.lowercased().contains(q) }
    }

    private var tagsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Tags des tiers").font(.title3.bold())
                Spacer()
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredTags) { tag in
                        HStack(spacing: 10) {
                            Circle().fill(Color(hex: tag.hexColor)).frame(width: 14, height: 14)
                            Text(tag.name).font(.body)
                            Spacer()
                            Button {
                                editingTag = tag
                            } label: { Image(systemName: "pencil") }
                                .buttonStyle(.borderless)
                                .help("Modifier ce tag")
                            Button(role: .destructive) {
                                tagStore.delete(tag)
                            } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                                .help("Supprimer ce tag")
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.06)))
                    }
                    Divider().padding(.vertical, 6)
                    Text("Ajouter un tag").font(.caption.bold())
                    HStack {
                        ColorPicker("", selection: Binding(
                            get: { Color(hex: newTagHex) },
                            set: { newTagHex = hexString(from: $0) }
                        )).labelsHidden().frame(width: 30)
                        TextField("Nom du nouveau tag", text: $newTagName)
                        Button {
                            guard !newTagName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            tagStore.upsert(PartyTag(name: newTagName.trimmingCharacters(in: .whitespaces), hexColor: newTagHex))
                            newTagName = ""
                            newTagHex = "555555"
                        } label: { Label("Ajouter", systemImage: "plus.circle.fill") }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(12)
            }
        }
    }

    private var filteredTags: [PartyTag] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return tagStore.tags }
        return tagStore.tags.filter { $0.name.lowercased().contains(q) }
    }

    private var kindColorsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Couleurs des types de tiers").font(.title3.bold())
                Spacer()
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(DirectoryEntryKind.allCases, id: \.self) { kind in
                        HStack(spacing: 10) {
                            Circle().fill(Color(hex: kindColors.hexColor(for: kind))).frame(width: 14, height: 14)
                            Text(kind.label).font(.body)
                            Text(kindColors.hexColor(for: kind)).font(.caption).foregroundStyle(.secondary).monospaced()
                            Spacer()
                            Button {
                                editingKind = kind
                            } label: { Image(systemName: "pencil") }
                                .buttonStyle(.borderless)
                                .help("Modifier cette couleur")
                            Button(role: .destructive) {
                                kindColors.colors[kind] = kind.defaultHexColor
                                kindColors.save()
                            } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                                .help("Réinitialiser cette couleur")
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.06)))
                    }
                }
                .padding(12)
            }
        }
    }

    private func refPanel(_ refs: [NormRef]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(selectedTable.label).font(.title3.bold())
                Spacer()
                Text("Lecture seule (référentiel normatif)").font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(filteredRefs(refs)) { ref in
                        HStack {
                            Text(ref.code).font(.body.monospaced()).frame(width: 100, alignment: .leading)
                            Text(ref.label).foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 3)
                    }
                }
                .padding(12)
            }
        }
    }

    private func filteredRefs(_ refs: [NormRef]) -> [NormRef] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return refs }
        return refs.filter { $0.code.lowercased().contains(q) || $0.label.lowercased().contains(q) }
    }
}

struct OrderStatusEditorSheet: View {
    var override: OrderStatusOverride
    let onSave: (OrderStatusOverride) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var label: String
    @State private var systemImage: String
    @State private var hexColor: String

    init(override: OrderStatusOverride, onSave: @escaping (OrderStatusOverride) -> Void) {
        self.override = override
        self.onSave = onSave
        _label = State(initialValue: override.label)
        _systemImage = State(initialValue: override.systemImage)
        _hexColor = State(initialValue: override.hexColor)
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Modifier le statut").font(.title3.bold())
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Libellé").frame(width: 100, alignment: .leading)
                    TextField("Libellé", text: $label).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Icône SF").frame(width: 100, alignment: .leading)
                    TextField("Icône SF", text: $systemImage).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Couleur").frame(width: 100, alignment: .leading)
                    ColorPicker(selection: Binding(
                        get: { Color(hex: hexColor) },
                        set: { hexColor = hexString(from: $0) }
                    )) { Text("Couleur") }
                }
            }
            HStack {
                Spacer()
                Button("Enregistrer") {
                    onSave(OrderStatusOverride(id: override.id, label: label, systemImage: systemImage, hexColor: hexColor))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Spacer()
        }
        .padding()
        .frame(width: 420, height: 300)
    }
}

struct TagEditorSheet: View {
    var tag: PartyTag
    let onSave: (PartyTag) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var hexColor: String

    init(tag: PartyTag, onSave: @escaping (PartyTag) -> Void) {
        self.tag = tag
        self.onSave = onSave
        _name = State(initialValue: tag.name)
        _hexColor = State(initialValue: tag.hexColor)
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Modifier le tag").font(.title3.bold())
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Nom").frame(width: 100, alignment: .leading)
                    TextField("Nom du tag", text: $name).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Couleur").frame(width: 100, alignment: .leading)
                    ColorPicker(selection: Binding(
                        get: { Color(hex: hexColor) },
                        set: { hexColor = hexString(from: $0) }
                    )) { Text("Couleur") }
                }
            }
            HStack {
                Spacer()
                Button("Enregistrer") {
                    onSave(PartyTag(id: tag.id, name: name, hexColor: hexColor))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Spacer()
        }
        .padding()
        .frame(width: 420, height: 260)
    }
}

struct KindColorEditorSheet: View {
    let kind: DirectoryEntryKind
    var hex: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var hexColor: String

    init(kind: DirectoryEntryKind, hex: String, onSave: @escaping (String) -> Void) {
        self.kind = kind
        self.hex = hex
        self.onSave = onSave
        _hexColor = State(initialValue: hex)
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Modifier la couleur").font(.title3.bold())
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Type").frame(width: 100, alignment: .leading)
                    Text(kind.label)
                }
                HStack {
                    Text("Couleur").frame(width: 100, alignment: .leading)
                    ColorPicker(selection: Binding(
                        get: { Color(hex: hexColor) },
                        set: { hexColor = hexString(from: $0) }
                    )) { Text("Couleur") }
                }
            }
            HStack {
                Spacer()
                Button("Enregistrer") {
                    onSave(hexColor)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .padding()
        .frame(width: 420, height: 240)
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
    @Binding var contacts: [PartyContact]
    var showWebButton: Bool
    var isFournisseur: Bool = false
    var hideEmail: Bool = false
    var isMultiContact: Bool
    var directory: PartyDirectory?
    var onPickContact: ((PartyContact) -> Void)?
    var onPickRouting: ((PartyRoutingAddress) -> Void)?
    var onPartyPicked: ((InvoiceParty) -> Void)?
    @State private var showRoutingEditor = false
    @State private var editingAddress: PartyRoutingAddress?
    @State private var showContactEditor = false
    @State private var editingContact: PartyContact?
    @State private var showContactPicker = false
    @State private var showRoutingPicker = false
    @State private var dinumResults: [SireneResult] = []
    @State private var dinumLoading = false
    @State private var dinumError: String?
    @State private var lastSearchKey: String = ""

    init(party: Binding<InvoiceParty>, routingAddresses: Binding<[PartyRoutingAddress]>? = nil, contacts: Binding<[PartyContact]>? = nil, showWebButton: Bool = true, isFournisseur: Bool = false, hideEmail: Bool = false, directory: PartyDirectory? = nil, onPickContact: ((PartyContact) -> Void)? = nil, onPickRouting: ((PartyRoutingAddress) -> Void)? = nil, onPartyPicked: ((InvoiceParty) -> Void)? = nil) {
        self._party = party
        self.showWebButton = showWebButton
        self.isFournisseur = isFournisseur
        self.hideEmail = hideEmail
        self.isMultiContact = contacts != nil
        self.directory = directory
        self.onPickContact = onPickContact
        self.onPickRouting = onPickRouting
        self.onPartyPicked = onPartyPicked
        if let ra = routingAddresses {
            self._routingAddresses = ra
        } else {
            self._routingAddresses = .constant([])
        }
        if let ct = contacts {
            self._contacts = ct
        } else {
            self._contacts = .constant([])
        }
    }

    private var linkedEntry: DirectoryEntry? {
        guard let dir = directory else { return nil }
        let siren = (party.siren ?? "").filter { $0.isNumber }
        if siren.count == 9, let e = dir.entries.first(where: { ($0.party.siren ?? "").filter { $0.isNumber } == siren }) {
            return e
        }
        let name = party.name.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { return dir.entries.first(where: { $0.party.name.trimmingCharacters(in: .whitespaces) == name }) }
        return nil
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
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Adresse", text: $party.street)
                    HStack {
                        TextField("Code postal", text: $party.postcode)
                        TextField("Ville", text: $party.city)
                    }
                    HStack {
                        Text("Pays").font(.caption); star
                        NormRefPicker("Pays", options: NormRefs.countries, code: $party.country).frame(width: 200)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("SIREN").font(.caption); star
                        TextField("SIREN", text: Binding($party.siren, replacingNilWith: ""))
                            .onChange(of: party.siren) { _ in scheduleDinumSearch() }
                    }
                    HStack(spacing: 4) {
                        Text("TVA intra").font(.caption)
                        TextField("N° TVA", text: Binding($party.vatNumber, replacingNilWith: ""))
                    }
                    HStack {
                        Text("SIRET").font(.caption)
                        TextField("SIRET (14 chiffres)", text: Binding($party.siret, replacingNilWith: ""))
                            .frame(maxWidth: 200)
                        if let st = party.siret?.trimmingCharacters(in: .whitespaces), !st.isEmpty {
                            if SireneValidator.isValidSiret(st) {
                                Label("SIRET valide (clé Luhn correcte)", systemImage: "checkmark.circle.fill")
                                    .font(.caption2).foregroundStyle(.green)
                            } else {
                                Label("SIRET invalide (clé Luhn incorrecte)", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption2).foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Text("Ident. élec. (BT-49/34)").font(.caption)
                if linkedEntry != nil {
                    Text((party.endpointID ?? "").isEmpty ? "Aucune" : (party.endpointID ?? ""))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        showRoutingPicker = true
                    } label: { Label("Choisir", systemImage: "envelope") }
                        .buttonStyle(.bordered)
                        .help("Choisir ou créer une adresse électronique depuis la fiche tiers")
                } else {
                    TextField("Auto depuis SIREN si vide", text: Binding($party.endpointID, replacingNilWith: ""))
                    NormRefPicker("Scheme", options: NormRefs.endpointSchemes, code: $party.endpointSchemeID).frame(width: 180)
                }
            }
            if isMultiContact {
                Button {
                    editingContact = nil
                    showContactEditor = true
                } label: {
                    Label("Contacts", systemImage: "person.crop.circle.badge.plus")
                }
                .buttonStyle(.bordered)
                if !contacts.isEmpty {
                    ForEach(contacts) { ct in
                        HStack(spacing: 8) {
                            if ct.isDefault {
                                Text("défaut").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Color.accentColor.opacity(0.2), in: Capsule())
                            }
                            Text(ct.name.trimmingCharacters(in: .whitespaces).isEmpty ? "(sans nom)" : ct.name)
                                .font(.caption.bold())
                            if let e = ct.email?.trimmingCharacters(in: .whitespaces), !e.isEmpty {
                                Text(e).font(.caption).foregroundStyle(.secondary)
                            }
                            if let p = ct.phone?.trimmingCharacters(in: .whitespaces), !p.isEmpty {
                                Text(p).font(.caption).foregroundStyle(.secondary)
                            }
                            if !ct.isActive {
                                Text("inactif").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Color.gray.opacity(0.2), in: Capsule())
                            }
                            Spacer()
                            Button {
                                editingContact = ct
                                showContactEditor = true
                            } label: { Image(systemName: "pencil") }
                                .buttonStyle(.borderless)
                                .help("Modifier ce contact")
                            Button(role: .destructive) {
                                contacts.removeAll { $0.id == ct.id }
                                if contacts.allSatisfy({ !$0.isDefault }), !contacts.isEmpty {
                                    contacts[0].isDefault = true
                                }
                            } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                                .help("Supprimer ce contact")
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.08)))
                    }
                }
            } else if linkedEntry != nil {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Contact").font(.caption)
                        Spacer()
                        Button {
                            showContactPicker = true
                        } label: { Label("Choisir", systemImage: "person") }
                            .buttonStyle(.bordered)
                            .help("Choisir ou créer un contact depuis la fiche tiers")
                    }
                    let name = party.contactName?.trimmingCharacters(in: .whitespaces) ?? ""
                    let email = hideEmail ? "" : (party.contactEmail?.trimmingCharacters(in: .whitespaces) ?? "")
                    let phone = party.contactPhone?.trimmingCharacters(in: .whitespaces) ?? ""
                    if name.isEmpty && email.isEmpty && phone.isEmpty {
                        Text("Aucun contact").font(.caption).foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 8) {
                            Text(name.isEmpty ? "(sans nom)" : name).font(.caption.bold())
                            if !email.isEmpty { Text(email).font(.caption).foregroundStyle(.secondary) }
                            if !phone.isEmpty { Text(phone).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.08)))
                    }
                }
            } else {
                HStack {
                    TextField("Contact", text: Binding($party.contactName, replacingNilWith: ""))
                    if !hideEmail {
                        TextField("Email", text: Binding($party.contactEmail, replacingNilWith: ""))
                    }
                    TextField("Téléphone", text: Binding($party.contactPhone, replacingNilWith: ""))
                }
            }
            if linkedEntry == nil {
                Button {
                    showRoutingEditor = true
                } label: {
                    Label("Adresses de facturation électronique", systemImage: "envelope.badge")
                }
                .buttonStyle(.bordered)
            }
            if isFournisseur {
                DisclosureGroup("Coordonnées bancaires & conditions de paiement") {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("IBAN", text: Binding($party.iban, replacingNilWith: ""))
                        TextField("BIC", text: Binding($party.bic, replacingNilWith: ""))
                        TextField("Conditions de paiement", text: Binding($party.paymentTerms, replacingNilWith: ""))
                    }
                }
                .font(.caption)
            }
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
                        dinumError = nil
                        dinumLoading = false
                        lastSearchKey = searchTrigger
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
        .sheet(isPresented: $showContactEditor) {
            if let ct = editingContact {
                ContactFormView(contacts: $contacts, editing: ct)
            } else {
                ContactFormView(contacts: $contacts, editing: PartyContact())
            }
        }
        .onChange(of: showContactEditor) { showing in
            if !showing { editingContact = nil }
        }
        .sheet(isPresented: $showContactPicker) {
            if let e = linkedEntry {
                ContactPickerSheet(entry: e) { contact in
                    if let c = contact {
                        onPickContact?(c)
                    } else {
                        var p = party
                        p.contactName = nil
                        p.contactEmail = nil
                        p.contactPhone = nil
                        party = p
                        onPartyPicked?(p)
                    }
                }
            }
        }
        .sheet(isPresented: $showRoutingPicker) {
            if let e = linkedEntry {
                RoutingPickerSheet(entry: e) { routing in
                    if let r = routing {
                        onPickRouting?(r)
                    } else {
                        var p = party
                        p.endpointID = nil
                        party = p
                        onPartyPicked?(p)
                    }
                }
            }
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

struct OrderPartySection: View {
    enum Role {
        case buyer, seller
        var title: String { self == .buyer ? "Acheteur" : "Fournisseur" }
        var defaultKind: DirectoryEntryKind { self == .buyer ? .client : .fournisseur }
    }

    @Binding var party: InvoiceParty
    let role: Role
    var onPartyPicked: ((InvoiceParty) -> Void)? = nil
    @EnvironmentObject var directory: PartyDirectory
    @State private var showPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    showPicker = true
                } label: {
                    Label("Choisir dans l'annuaire", systemImage: "person.crop.circle.badge.plus")
                }
                .buttonStyle(.bordered)
                Spacer()
            }

            PartyEditorView(party: $party, isFournisseur: role == .seller, hideEmail: true, directory: directory, onPickContact: { updatePartyFromContact($0) }, onPickRouting: { updatePartyFromRouting($0) }, onPartyPicked: { p in onPartyPicked?(p) })
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
    @Binding var selectedID: UUID?
    @State private var query = ""
    @State private var showExport = false

    var filteredOrders: [SalesOrder] {
        var result = orderStore.orders
        if let scope = auth.visibleOrderCompanyIDs(for: auth.currentUser) {
            result = result.filter { order in
                if let cid = order.companyID { return scope.contains(cid) }
                return false
            }
        }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return result }
        return result.filter { order in
            order.number.lowercased().contains(q)
                || order.seller.name.lowercased().contains(q)
                || (order.seller.siren ?? "").lowercased().contains(q)
                || order.buyer.name.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    Button {
                        let draft = orderStore.newDraft(preferredBuyerEntryID: auth.currentUser?.defaultSellerEntryID, companyID: defaultOrderCompanyID())
                        orderStore.upsert(draft)
                        selectedID = draft.id
                    } label: { Label("Nouvelle commande", systemImage: "plus") }
                        .buttonStyle(.borderedProminent)
                    Text("Commandes").font(.title2.bold())
                    Spacer()
                    Button { showExport = true } label: { Label("Exporter", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.bordered)
                }
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
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1)))
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
                            let draft = orderStore.newDraft(preferredBuyerEntryID: auth.currentUser?.defaultSellerEntryID, companyID: defaultOrderCompanyID())
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
                                    Text("\(order.seller.name.isEmpty ? "Sans client" : order.seller.name)")
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
                    OrderEditorView(order: binding(for: id))
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
        .sheet(isPresented: $showExport) {
            ExportSheet(
                invoices: scopedInvoices,
                orders: scopedOrders,
                isPresented: $showExport
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

    private var scopedInvoices: [Invoice] {
        var result = store.invoices
        if let scope = auth.visibleInvoiceCompanyIDs(for: auth.currentUser) {
            result = result.filter { inv in
                if let cid = inv.companyID { return scope.contains(cid) }
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
    @State private var exportError: String?
    @State private var exportedURL: URL?
    @State private var validation: FacturXValidationResult?
    @State private var showValidation = false
    @State private var isLocked = false
    @State private var showUnlockAlert = false
    @State private var createdInvoiceNumber: String?

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
            HStack {
                Text("Édition : \(order.number)").font(.title2.bold())
                if isLocked {
                    Label("Lecture seule", systemImage: "lock.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .overlay(Capsule().stroke(.secondary, lineWidth: 0.5))
                }
                Spacer()
                if isLocked {
                    Button { showUnlockAlert = true } label: {
                        Label("Modifier", systemImage: "lock.open")
                    }
                    .buttonStyle(.bordered)
                    .help("Repasser en édition (la commande n'est plus protégée)")
                } else if validation?.isValid == true {
                    Button { isLocked = true } label: {
                        Label("Verrouiller", systemImage: "lock")
                    }
                    .buttonStyle(.bordered)
                    .help("Protéger la commande validée en lecture seule")
                }
                Button("Valider") { runValidation() }
                    .buttonStyle(.bordered)
                    .disabled(isLocked)
                Button("Exporter XML") { exportXML() }
                    .buttonStyle(.bordered)
                Button("Générer l'Order-X") { export() }
                    .buttonStyle(.borderedProminent)
                Button("Créer la facture") { createInvoice() }
                    .buttonStyle(.bordered)
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
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
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Données obligatoires pour la conformité Order-X", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption.bold())
                                .foregroundStyle(.orange)
                            Text("Acheteur et client : nom, pays (code ISO 2 lettres), SIREN ou identifiant électronique, n° TVA si applicable.").font(.caption)
                            Text("Lignes : désignation non vide, quantité positive, prix unitaire, taux TVA, unité (code UN/ECE ex. C62, DAY, HUR).").font(.caption)
                            Text("En-tête : numéro de commande, date d'émission, date de livraison souhaitée, devise (EUR).").font(.caption)
                        }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if showValidation, let v = validation {
                    orderValidationPanel(v)
                }

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
                                row("Total HT", order.lineTotal)
                                ForEach(order.vatBreakdown, id: \.rate) { item in
                                    row("TVA \(String(format: "%.0f%%", item.rate))", item.amount)
                                }
                                row("Total TTC", order.grandTotal, bold: true)
                                Divider().frame(width: 280)
                                row("Montant facturé", linkedInvoicesAmount)
                                row("Reste à facturer", max(0, order.grandTotal - linkedInvoicesAmount), bold: true)
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
                        }
                    }.padding(8)
                }.lockable(isLocked)

                HStack(alignment: .top, spacing: 12) {
                    GroupBox("Acheteur (vous)") {
                        OrderPartySection(party: $order.buyer, role: .buyer)
                    }.lockable(isLocked)
                    GroupBox("Client") {
                        OrderPartySection(party: $order.seller, role: .buyer)
                    }.lockable(isLocked)
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
                                    DoubleField("TVA %", value: $line.vatRate, format: .number)
                                    InfoBadge(text: "Taux de TVA appliqué (%).")
                                }
                                Text(String(format: "%.2f", line.lineTotal))
                                    .monospacedDigit().frame(width: 80, alignment: .trailing)
                                Button { order.lines.removeAll { $0.id == line.id } } label: {
                                    Image(systemName: "minus.circle")
                                }
                            }
                        }
                        Button {
                            order.lines.append(InvoiceLine(name: "", quantity: 1, unitPrice: 0, vatRate: order.lines.last?.vatRate ?? 20))
                        } label: { Label("Ajouter une ligne", systemImage: "plus") }
                    }.padding(8)
                }.lockable(isLocked)

                GroupBox("Notes") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Notes libres", text: Binding($order.notes, replacingNilWith: ""))
                    }.padding(8)
                }.lockable(isLocked)

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
                }.lockable(isLocked)
            }.padding()
        }
            .alert("Repasser en modification ?", isPresented: $showUnlockAlert) {
                Button("Annuler", role: .cancel) { }
                Button("Modifier", role: .destructive) { isLocked = false }
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
                        Label("Conforme", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Non conforme — \(v.errors.count) erreur(s)", systemImage: "xmark.seal.fill")
                            .foregroundStyle(.red)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        let current = statusStore.override(for: order)
                        Image(systemName: current.systemImage)
                            .foregroundColor(Color(hex: current.hexColor))
                            .font(.caption2)
                        Picker("Statut", selection: Binding<String>(
                            get: { order.customStatusID ?? order.status.rawValue },
                            set: { selectedID in
                                if let s = OrderStatus(rawValue: selectedID) {
                                    order.status = s
                                    order.customStatusID = nil
                                } else {
                                    order.customStatusID = selectedID
                                }
                            }
                        )) {
                            ForEach(statusStore.overrides) { o in
                                Label(o.label, systemImage: o.systemImage).tag(o.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 200)
                        .help("Statut de la commande (modifiable à tout moment)")
                    }
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

extension Binding {
    init(_ source: Binding<Value?>, replacingNilWith nilValue: Value) {
        self.init(
            get: { source.wrappedValue ?? nilValue },
            set: { source.wrappedValue = $0 }
        )
    }
}
