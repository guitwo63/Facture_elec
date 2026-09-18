import SwiftUI
import FacturXCore
import AppKit
import PDFKit
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
/// Style de bouton uniforme pour les barres d'action (taille et forme identiques,
/// seule la couleur varie) : rempli pour l'action principale, liseré + fond très
/// légèrement teinté sinon.
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

@main
struct FacturXMacApp: App {
    @StateObject private var store = InvoiceStore.shared
    @StateObject private var orderStore = OrderStore.shared
    @StateObject private var quoteStore = QuoteStore.shared
    @StateObject private var quoteStatusStore = QuoteStatusStore.shared
    @StateObject private var directory = PartyDirectory.shared
    @StateObject private var chorusSettings = ChorusProSettings.shared
    @StateObject private var superPDPSettings = SuperPDPSettings.shared
    @StateObject private var smtpSettings = SMTPSettings.shared
    @StateObject private var emailTemplateStore = EmailTemplateStore.shared
    @StateObject private var twoFactorSettings = TwoFactorSettings.shared
    @StateObject private var pcloudSettings = PCloudSettings.shared
    @StateObject private var moduleStore = ModuleStore.shared
    @StateObject private var backupStrategyStore = BackupStrategyStore.shared
    @StateObject private var appEnv = AppEnvironment.shared
    @StateObject private var tagStore = TagStore.shared
    @StateObject private var kindColors = KindColorStore.shared
    @StateObject private var statusStore = OrderStatusStore.shared
    @StateObject private var invoiceStatusStore = InvoiceStatusStore.shared
    @StateObject private var paymentTermsStore = PaymentTermsPresetStore.shared
    @StateObject private var auth = AuthStore.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Factur-X") {
            RootView()
                .environmentObject(store)
                .environmentObject(orderStore)
                .environmentObject(quoteStore)
                .environmentObject(quoteStatusStore)
                .environmentObject(directory)
                .environmentObject(chorusSettings)
                .environmentObject(superPDPSettings)
                .environmentObject(smtpSettings)
                .environmentObject(emailTemplateStore)
                .environmentObject(twoFactorSettings)
                .environmentObject(pcloudSettings)
                .environmentObject(moduleStore)
                .environmentObject(backupStrategyStore)
                .environmentObject(tagStore)
                .environmentObject(kindColors)
                .environmentObject(statusStore)
                .environmentObject(invoiceStatusStore)
                .environmentObject(paymentTermsStore)
                .environmentObject(auth)
                .environmentObject(appEnv)
                .frame(minWidth: 980, minHeight: 620)
                .onAppear {
                    auth.attachDirectory(directory)
                    auth.testBypassSecurity = true
                    store.audit = AuditStore.shared
                    orderStore.audit = AuditStore.shared
                    quoteStore.audit = AuditStore.shared
                    directory.audit = AuditStore.shared
                    store.actorName = auth.currentUser?.username ?? "system"
                    orderStore.actorName = auth.currentUser?.username ?? "system"
                    quoteStore.actorName = auth.currentUser?.username ?? "system"
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
    static let fullSettingsWizardRequested = Notification.Name("fullSettingsWizardRequested")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        guard SingleInstanceLock.shared.acquire() else {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Facture_elec est déjà ouvert"
            alert.informativeText = "Une autre instance de l'application est déjà lancée sur cette machine. Fermez-la avant d'en ouvrir une nouvelle, pour éviter tout conflit sur les données enregistrées."
            alert.addButton(withTitle: "Quitter")
            alert.runModal()
            exit(0)
        }
    }

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
    case quotes = "Devis"
    case orders = "Ventes"
    case invoices = "Factures"
    case dashboard = "Tableau de bord"
    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .directory: return "person.crop.rectangle.stack"
        case .quotes: return "doc.text.below.ecg"
        case .orders: return "cart.fill"
        case .invoices: return "doc.text.fill"
        case .dashboard: return "gauge"
        }
    }

    static func visible(for role: UserRole?, modules: ModuleSettings = ModuleStore.shared.settings) -> [RootTab] {
        var result: [RootTab]
        switch role {
        case .acheteur:
            result = [.orders]
        default:
            result = allCases
        }
        if !modules.ordersEnabled { result.removeAll { $0 == .orders } }
        if !modules.quotesEnabled { result.removeAll { $0 == .quotes } }
        return result
    }
}

/// Vue agrégée en lecture sur InvoiceStore existant : aucun nouveau modèle,
/// aucune donnée stockée séparément — tout est recalculé à l'affichage.
enum DashboardPeriod: String, CaseIterable, Identifiable, Hashable {
    case month = "Ce mois-ci"
    case quarter = "Ce trimestre"
    case year = "Cette année"
    case all = "Tout"
    case custom = "Personnalisé"
    var id: String { rawValue }
}

struct TreasuryDashboardView: View {
    @EnvironmentObject var store: InvoiceStore
    @EnvironmentObject var auth: AuthStore

    @State private var period: DashboardPeriod = .year
    @State private var customFrom: Date = Calendar.current.dateInterval(of: .year, for: Date())?.start ?? Date()
    @State private var customTo: Date = Date()

    private struct ClientBalance: Identifiable {
        let id: String
        let name: String
        let outstanding: Double
        let overdue: Double
    }

    private var scopedInvoices: [Invoice] {
        var result = store.invoices
        if let scope = auth.visibleInvoiceCompanyIDs(for: auth.currentUser) {
            result = result.filter { inv in
                if let cid = inv.companyID { return scope.contains(cid) }
                return false
            }
        }
        return result
    }

    /// Exclut les factures annulées : elles ne représentent plus un CA réel.
    private var activeInvoices: [Invoice] {
        scopedInvoices.filter { $0.status != .cancelled }
    }

    /// Sous-ensemble réellement envoyé au client : un brouillon ou une facture
    /// validée mais non envoyée (statut « Validée (non envoyée) ») n'engage
    /// rien et ne doit pas gonfler artificiellement les indicateurs.
    private var sentInvoices: [Invoice] {
        activeInvoices.filter { $0.status != .draft && $0.status != .issued }
    }

    private func signedAmount(_ inv: Invoice) -> Double {
        inv.type.isCreditNote ? -inv.grandTotal : inv.grandTotal
    }

    /// Bornes de la période sélectionnée. `nil` = pas de borne (période "Tout").
    private var periodRange: ClosedRange<Date>? {
        let cal = Calendar.current
        let now = Date()
        switch period {
        case .all:
            return nil
        case .month:
            guard let interval = cal.dateInterval(of: .month, for: now) else { return nil }
            return interval.start...interval.end
        case .quarter:
            let month = cal.component(.month, from: now)
            let quarterStartMonth = ((month - 1) / 3) * 3 + 1
            var comps = cal.dateComponents([.year], from: now)
            comps.month = quarterStartMonth
            comps.day = 1
            guard let start = cal.date(from: comps),
                  let end = cal.date(byAdding: DateComponents(month: 3), to: start) else { return nil }
            return start...end
        case .year:
            guard let interval = cal.dateInterval(of: .year, for: now) else { return nil }
            return interval.start...interval.end
        case .custom:
            let start = min(customFrom, customTo)
            let end = cal.date(byAdding: .day, value: 1, to: max(customFrom, customTo)) ?? customTo
            return start...end
        }
    }

    /// Uniquement les KPI d'activité (CA facturé, Encaissé) sont scopés à la période — "En
    /// attente"/"En retard"/"Validées non envoyées" restent des photos de l'état courant,
    /// filtrer par période les masquerait à tort (une facture en retard depuis l'an dernier
    /// reste un problème actuel, quelle que soit la période affichée).
    private var periodInvoices: [Invoice] {
        guard let range = periodRange else { return sentInvoices }
        return sentInvoices.filter { range.contains($0.issueDate) }
    }

    private var caFacture: Double {
        periodInvoices.reduce(0) { $0 + signedAmount($1) }
    }

    private var encaisse: Double {
        periodInvoices.filter { $0.status == .paid }.reduce(0) { $0 + signedAmount($1) }
    }

    private var enRetard: Double {
        sentInvoices.filter(\.isOverdue).reduce(0) { $0 + signedAmount($1) }
    }

    private var enAttente: Double {
        sentInvoices.filter { $0.status != .paid && !$0.isOverdue }.reduce(0) { $0 + signedAmount($1) }
    }

    /// Factures au statut « Validée (non envoyée) » : verrouillées côté saisie mais pas
    /// encore engagées vis-à-vis du client — exclues de `sentInvoices`, donc absentes
    /// des autres KPI. Utile pour repérer les factures prêtes qui attendent l'envoi.
    private var validatedNotSent: Double {
        activeInvoices.filter { $0.status == .issued }.reduce(0) { $0 + signedAmount($1) }
    }

    private var byClient: [ClientBalance] {
        var byName: [String: (outstanding: Double, overdue: Double)] = [:]
        for inv in sentInvoices where inv.status != .paid {
            let name = inv.buyer.name.trimmingCharacters(in: .whitespaces).isEmpty ? "Client sans nom" : inv.buyer.name
            var entry = byName[name] ?? (outstanding: 0, overdue: 0)
            entry.outstanding += signedAmount(inv)
            if inv.isOverdue { entry.overdue += signedAmount(inv) }
            byName[name] = entry
        }
        return byName.map { ClientBalance(id: $0.key, name: $0.key, outstanding: $0.value.outstanding, overdue: $0.value.overdue) }
            .sorted { $0.outstanding > $1.outstanding }
    }

    private var currency: String { scopedInvoices.first?.currency ?? "EUR" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Tableau de bord").font(.title2.bold())
                    Spacer()
                    Picker("Période", selection: $period) {
                        ForEach(DashboardPeriod.allCases) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 420)
                    .labelsHidden()
                }
                if period == .custom {
                    HStack(spacing: 8) {
                        Text("Du").font(.caption).foregroundStyle(.secondary)
                        DatePicker("", selection: $customFrom, displayedComponents: .date).labelsHidden()
                        Text("au").font(.caption).foregroundStyle(.secondary)
                        DatePicker("", selection: $customTo, displayedComponents: .date).labelsHidden()
                    }
                }
                HStack(spacing: 16) {
                    kpiCard("CA facturé — \(period.rawValue)", caFacture, color: .blue, icon: "chart.line.uptrend.xyaxis")
                    kpiCard("Encaissé — \(period.rawValue)", encaisse, color: .green, icon: "checkmark.circle.fill")
                    kpiCard("En attente", enAttente, color: .orange, icon: "hourglass")
                    kpiCard("En retard", enRetard, color: .red, icon: "exclamationmark.triangle.fill")
                    kpiCard("Validées, non envoyées", validatedNotSent, color: Color(hex: InvoiceStatus.issued.hexColor), icon: InvoiceStatus.issued.systemImage)
                }
                GroupBox("Par client — montant dû") {
                    if byClient.isEmpty {
                        Text("Aucun montant en attente.").foregroundStyle(.secondary).padding()
                    } else {
                        VStack(spacing: 0) {
                            ForEach(byClient) { c in
                                HStack {
                                    Text(c.name).font(.body)
                                    Spacer()
                                    if c.overdue < 0 {
                                        Label(String(format: "%.2f %@ en retard", abs(c.overdue), currency), systemImage: "exclamationmark.triangle.fill")
                                            .font(.caption).foregroundStyle(.red)
                                    }
                                    Text(String(format: "%.2f %@", c.outstanding, currency))
                                        .font(.body.bold()).monospacedDigit()
                                }
                                .padding(.vertical, 6).padding(.horizontal, 8)
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func kpiCard(_ title: String, _ amount: Double, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: icon).foregroundStyle(color)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Text(String(format: "%.2f %@", amount, currency))
                .font(.title2.bold())
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.12)))
    }
}

struct RootView: View {
    @EnvironmentObject var store: InvoiceStore
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var orderStore: OrderStore
    @EnvironmentObject var quoteStore: QuoteStore
    @EnvironmentObject var quoteStatusStore: QuoteStatusStore
    @EnvironmentObject var appEnv: AppEnvironment
    @EnvironmentObject var directory: PartyDirectory
    @EnvironmentObject var tagStore: TagStore
    @EnvironmentObject var kindColors: KindColorStore
    @EnvironmentObject var statusStore: OrderStatusStore
    @EnvironmentObject var invoiceStatusStore: InvoiceStatusStore
    @EnvironmentObject var chorusSettings: ChorusProSettings
    @EnvironmentObject var superPDPSettings: SuperPDPSettings
    @EnvironmentObject var smtpSettings: SMTPSettings
    @EnvironmentObject var twoFactorSettings: TwoFactorSettings
    @EnvironmentObject var pcloudSettings: PCloudSettings
    @EnvironmentObject var moduleStore: ModuleStore
    @EnvironmentObject var backupStrategyStore: BackupStrategyStore
    @State private var tab: RootTab = .invoices
    @State private var didAttemptAutoBackup = false
    @State private var selectedID: UUID?
    @State private var selectedOrderID: UUID?
    @State private var selectedQuoteID: UUID?
    @State private var showSettings = false
    @State private var showUserManagement = false
    @State private var showEnvConfirm = false
    @State private var showSetupWizard = false
    @State private var setupWizardSkippedThisSession = false
    @State private var showFullSettingsWizard = false

    var body: some View {
        Group {
            if auth.currentUser == nil {
                LoginView()
            } else {
                mainBody
                    .onChange(of: appEnv.mode) { _ in
                        reloadAllStores()
                    }
            }
        }
        .alert("Changer d'environnement ?", isPresented: $showEnvConfirm) {
            Button("Annuler", role: .cancel) { }
        } message: {
            Text("Les données affichées vont basculer vers l'environnement sélectionné (test ou production). Les identifiants SUPER PDP propres à cet environnement seront utilisés.")
        }
    }

    private func reloadAllStores() {
        store.load()
        orderStore.load()
        quoteStore.load()
        quoteStatusStore.load()
        directory.load()
        tagStore.load()
        kindColors.load()
        statusStore.load()
        invoiceStatusStore.load()
        AuditStore.shared.load()
        chorusSettings.credentials = reloadChorusCredentials()
        superPDPSettings.credentials = reloadSuperPDPCredentials()
        smtpSettings.credentials = reloadSMTPCredentials()
        twoFactorSettings.load()
        pcloudSettings.load()
        moduleStore.load()
        backupStrategyStore.load()
        store.audit = AuditStore.shared
        orderStore.audit = AuditStore.shared
        quoteStore.audit = AuditStore.shared
        directory.audit = AuditStore.shared
        auth.reloadEnvironment()
        store.actorName = auth.currentUser?.username ?? "system"
        orderStore.actorName = auth.currentUser?.username ?? "system"
        quoteStore.actorName = auth.currentUser?.username ?? "system"
        directory.actorName = auth.currentUser?.username ?? "system"
        selectedID = nil
        selectedOrderID = nil
    }

    private func reloadChorusCredentials() -> ChorusProCredentials {
        let k = appEnv.key("facturx.choruspro.credentials.v1")
        if let data = UserDefaults.standard.data(forKey: k),
           let decoded = try? JSONDecoder().decode(ChorusProCredentials.self, from: data) {
            return decoded
        }
        return ChorusProCredentials(clientID: "", clientSecret: "")
    }

    private func reloadSuperPDPCredentials() -> SuperPDPCredentials {
        let k = appEnv.key("facturx.superpdp.credentials.v1")
        if let data = UserDefaults.standard.data(forKey: k),
           let decoded = try? JSONDecoder().decode(SuperPDPCredentials.self, from: data) {
            return decoded
        }
        return SuperPDPCredentials(clientID: "", clientSecret: "")
    }

    private func reloadSMTPCredentials() -> SMTPCredentials {
        let k = appEnv.key("facturx.smtp.credentials.v1")
        if let data = UserDefaults.standard.data(forKey: k),
           let decoded = try? JSONDecoder().decode(SMTPCredentials.self, from: data) {
            return decoded
        }
        return SMTPCredentials()
    }

    private func moduleButton(_ t: RootTab) -> some View {
        let isSelected = tab == t
        return Button {
            tab = t
        } label: {
            VStack(spacing: 4) {
                Image(systemName: t.systemImage).font(.title2)
                Text(t.rawValue).font(.caption.weight(isSelected ? .semibold : .regular))
            }
            .frame(minWidth: 76)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            // Sans ça, la zone transparente (module non sélectionné) n'est pas fiable
            // au clic — d'où le "il faut 2 clics" : le premier tombait dans une zone
            // que SwiftUI ne comptait pas comme cliquable faute de contenu opaque.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
    }

    private var mainBody: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: appEnv.isTest ? "flask" : "checkmark.seal.fill")
                    .foregroundStyle(appEnv.isTest ? .orange : .green)
                Text("Environnement : \(appEnv.mode.label)")
                    .font(.caption.bold())
                    .foregroundStyle(appEnv.isTest ? .orange : .green)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(appEnv.isTest ? Color.orange.opacity(0.12) : Color.green.opacity(0.12))
            HStack {
                HStack(spacing: 6) {
                    ForEach(RootTab.visible(for: auth.currentUser?.role, modules: moduleStore.settings)) { t in
                        moduleButton(t)
                    }
                }
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
            case .quotes:
                QuotesTabView(selectedID: $selectedQuoteID, rootTab: $tab, invoiceSelectedID: $selectedID)
            case .directory:
                DirectoryView()
            case .dashboard:
                TreasuryDashboardView()
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
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
            let draft = orderStore.newDraft(preferredSellerEntryID: auth.currentUser?.defaultSellerEntryID, companyID: defaultDraftCompanyID())
            orderStore.upsert(draft)
            selectedOrderID = draft.id
        }
        .onAppear {
            if auth.currentUser?.role == .acheteur, !RootTab.visible(for: .acheteur, modules: moduleStore.settings).contains(tab) {
                tab = .orders
            }
            syncAuditActor()
            maybeShowSetupWizard()
            runAutoBackupIfNeeded()
        }
        .onChange(of: auth.currentUser) { _ in
            syncAuditActor()
            maybeShowSetupWizard()
        }
        .sheet(isPresented: $showSetupWizard) {
            SetupWizardView {
                showSetupWizard = false
                setupWizardSkippedThisSession = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .fullSettingsWizardRequested)) { _ in
            showFullSettingsWizard = true
        }
        .sheet(isPresented: $showFullSettingsWizard) {
            FullSettingsWizardView {
                showFullSettingsWizard = false
            }
        }
    }

    private func maybeShowSetupWizard() {
        guard !setupWizardSkippedThisSession else { return }
        guard auth.currentUser?.isAdmin == true else { return }
        guard !directory.entries.contains(where: { $0.kind == .societe }) else { return }
        showSetupWizard = true
    }

    /// Stratégie de lancement (chantier « sauvegardes ») : au premier affichage
    /// post-connexion, si l'utilisateur l'a activé, lance une sauvegarde en
    /// tâche de fond — silencieuse pour ne pas interrompre l'ouverture de
    /// l'app, mais tracée dans le journal d'audit dans les deux cas.
    private func runAutoBackupIfNeeded() {
        guard !didAttemptAutoBackup else { return }
        didAttemptAutoBackup = true
        guard backupStrategyStore.settings.autoBackupOnLaunch, pcloudSettings.credentials.isConfigured else { return }
        let credentials = pcloudSettings.credentials
        let strategy = backupStrategyStore.settings
        let bundle = BackupService.capture(invoiceStore: store, orderStore: orderStore, quoteStore: quoteStore, directory: directory)
        Task {
            do {
                let summary = try await BackupRunner.run(bundle: bundle, pcloudCredentials: credentials, strategy: strategy)
                store.audit?.record(actor: "system", action: "backup_auto_launch_success", target: "", details: summary)
            } catch {
                store.audit?.record(actor: "system", action: "backup_auto_launch_failed", target: "", details: error.localizedDescription)
            }
        }
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

enum InvoiceFilterField: String, CaseIterable, Hashable {
    case none = "Aucun"
    case number = "N° facture"
    case buyerName = "Client"
    case buyerSiren = "SIREN client"
    case buyerVat = "TVA client"
    case sellerName = "Émetteur"
    case sellerSiren = "SIREN émetteur"
    case amountMin = "Montant TTC min"
    case amountMax = "Montant TTC max"
    case issueDateFrom = "Émise depuis"
    case issueDateTo = "Émise jusqu'à"
    case dueDateFrom = "Échue depuis"
    case purchaseOrderRef = "Réf. commande"
    case contractRef = "Réf. contrat"
    case precedingInvoiceRef = "Facture antérieure"
    case status = "Statut"
    case type = "Type"
}

enum OrderFilterField: String, CaseIterable, Hashable {
    case none = "Aucun"
    case number = "N° commande"
    case buyerName = "Client"
    case buyerSiren = "SIREN client"
    case buyerVat = "TVA client"
    case sellerName = "Émetteur"
    case sellerSiren = "SIREN émetteur"
    case amountMin = "Montant TTC min"
    case amountMax = "Montant TTC max"
    case issueDateFrom = "Émise depuis"
    case issueDateTo = "Émise jusqu'à"
    case quotationRef = "Réf. devis"
    case contractRef = "Réf. contrat"
    case buyerReference = "Réf. acheteur"
    case status = "Statut"
}

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

/// Export direct des documents déjà filtrés dans la liste d'origine : pas de
/// fenêtre intermédiaire de sélection, juste le choix du format puis
/// l'emplacement de sauvegarde.
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
                            Text("\(order.buyer.name.isEmpty ? "Sans client" : order.buyer.name)")
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

/// Miroir de OrderToInvoiceSheet pour les devis : ne liste que les devis déjà
/// acceptés et pas encore convertis (même règle que le bouton "Convertir en
/// facture" sur la fiche devis), pour donner un second point d'entrée depuis
/// l'onglet Factures sans dupliquer la logique métier.
struct QuoteToInvoiceSheet: View {
    let quotes: [Quote]
    let onCreate: (Quote) -> Void
    let onCancel: () -> Void
    @State private var query = ""
    @State private var selectedQuoteID: UUID?

    private var filteredQuotes: [Quote] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return quotes }
        return quotes.filter { quote in
            quote.number.lowercased().contains(q)
                || quote.buyer.name.lowercased().contains(q)
                || quote.seller.name.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Créer une facture depuis un devis").font(.headline)
                Spacer()
            }
            .padding(12)
            Divider()
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Rechercher (numéro, client…)", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            Divider()
            if filteredQuotes.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.below.ecg").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Aucun devis accepté disponible à facturer dans votre périmètre.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(Array(filteredQuotes.enumerated()), id: \.element.id) { _, quote in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(quote.number).font(.headline)
                            Text("\(quote.buyer.name.isEmpty ? "Sans client" : quote.buyer.name)")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(String(format: "%.2f %@ TTC", quote.grandTotal, quote.currency))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(quote.issueDate, format: .dateTime.day().month().year())
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selectedQuoteID = quote.id }
                    .background(selectedQuoteID == quote.id ? Color.accentColor.opacity(0.15) : Color.clear)
                }
            }
            Divider()
            HStack {
                Button("Annuler", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Créer la facture") {
                    if let quote = filteredQuotes.first(where: { $0.id == selectedQuoteID }) {
                        onCreate(quote)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedQuoteID == nil)
            }
            .padding(12)
        }
        .frame(width: 520, height: 420)
    }
}

struct InvoicePickerSheet: View {
    let invoices: [Invoice]
    let selectedID: UUID?
    let onPick: (Invoice) -> Void
    let onClear: () -> Void
    let onCancel: () -> Void
    @State private var query = ""
    @State private var companyFilter: UUID?
    @State private var localSelectedID: UUID?

    private var companies: [DirectoryEntry] {
        let dir = PartyDirectory.shared
        let ids = Set(invoices.compactMap { $0.companyID })
        return dir.entries.filter { ids.contains($0.id) }.sorted { $0.party.name < $1.party.name }
    }

    private var filtered: [Invoice] {
        var result = invoices
        if let cid = companyFilter {
            result = result.filter { $0.companyID == cid }
        }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return result.sorted { $0.issueDate > $1.issueDate } }
        return result.filter { inv in
            inv.number.lowercased().contains(q)
                || inv.seller.name.lowercased().contains(q)
                || inv.buyer.name.lowercased().contains(q)
                || (inv.buyer.siren ?? "").lowercased().contains(q)
        }.sorted { $0.issueDate > $1.issueDate }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sélectionner la facture antérieure").font(.headline)
                Spacer()
            }
            .padding(12)
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Rechercher (numéro, client, SIREN…)", text: $query)
                    .textFieldStyle(.plain)
                if !companies.isEmpty {
                    Picker("Société", selection: $companyFilter) {
                        Text("Toutes les sociétés").tag(UUID?.none)
                        ForEach(companies) { c in
                            Text(c.party.name.isEmpty ? "Sans nom" : c.party.name).tag(Optional(c.id))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            Divider()
            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Aucune facture disponible dans votre périmètre.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered) { inv in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(inv.number).font(.headline)
                                if (localSelectedID ?? selectedID) == inv.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                        .font(.caption)
                                }
                            }
                            Text("\(inv.seller.name.isEmpty ? "Sans émetteur" : inv.seller.name) → \(inv.buyer.name.isEmpty ? "Sans client" : inv.buyer.name)")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(String(format: "%.2f %@ TTC", inv.grandTotal, inv.currency))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(inv.issueDate, format: .dateTime.day().month().year())
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { localSelectedID = inv.id }
                    .background((localSelectedID ?? selectedID) == inv.id ? Color.accentColor.opacity(0.15) : Color.clear)
                }
            }
            Divider()
            HStack {
                Button("Annuler", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Effacer", role: .destructive, action: onClear)
                    .buttonStyle(.bordered)
                Spacer()
                Button("Sélectionner") {
                    let id = localSelectedID ?? selectedID
                    if let picked = filtered.first(where: { $0.id == id }) {
                        onPick(picked)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(localSelectedID == nil && selectedID == nil)
            }
            .padding(12)
        }
        .frame(width: 620, height: 460)
        .onAppear {
            localSelectedID = selectedID
            companyFilter = nil
        }
    }
}

struct InvoicesTabView: View {
    @EnvironmentObject var store: InvoiceStore
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var orderStore: OrderStore
    @EnvironmentObject var quoteStore: QuoteStore
    @EnvironmentObject var moduleStore: ModuleStore
    @Binding var selectedID: UUID?
    @State private var query = ""
    @State private var typeFilter: InvoiceTypeFilter = .all
    @State private var statusFilter: InvoiceStatus? = nil
    @State private var showOrderPicker = false
    @State private var showQuotePicker = false
    @State private var showQuickInvoiceWizard = false
    @State private var showScanImport = false
    @State private var exportMessage: String?
    @State private var showAdvancedFilters = false
    @State private var advField1: InvoiceFilterField = .none
    @State private var advValue1 = ""
    @State private var advField2: InvoiceFilterField = .none
    @State private var advValue2 = ""
    @State private var advField3: InvoiceFilterField = .none
    @State private var advValue3 = ""

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
        if let sf = statusFilter {
            result = result.filter { $0.status == sf }
        }
        result = applyAdvancedFilter(result, field: advField1, value: advValue1)
        result = applyAdvancedFilter(result, field: advField2, value: advValue2)
        result = applyAdvancedFilter(result, field: advField3, value: advValue3)
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
                    Button {
                        let draft = store.newDraft(companyID: defaultCompanyID(),
                                                   preferredSellerEntryID: auth.currentUser?.defaultSellerEntryID)
                        store.upsert(draft)
                        selectedID = draft.id
                    } label: { Label("Nouvelle facture", systemImage: "plus") }
                        .buttonStyle(.borderedProminent)
                    Text("Factures").font(.title2.bold())
                    if moduleStore.settings.ordersEnabled {
                        Button {
                            showOrderPicker = true
                        } label: { Label("Depuis une commande", systemImage: "cart") }
                            .buttonStyle(.bordered)
                    }
                    if moduleStore.settings.quotesEnabled {
                        Button {
                            showQuotePicker = true
                        } label: { Label("Depuis un devis", systemImage: "doc.text.below.ecg") }
                            .buttonStyle(.bordered)
                            .help("Convertit un devis accepté en facture")
                    }
                    Button {
                        showQuickInvoiceWizard = true
                    } label: { Label("Facture guidée", systemImage: "wand.and.stars") }
                        .buttonStyle(.bordered)
                        .help("Créer une facture en quelques étapes avec le minimum d'informations")
                    Button {
                        showScanImport = true
                    } label: { Label("Scanner un document", systemImage: "doc.viewfinder") }
                        .buttonStyle(.bordered)
                        .help("Importer la photo/le scan d'un devis signé ou d'un bon de commande client pour pré-remplir une facture")
                    Picker("Filtre", selection: $typeFilter) {
                        ForEach(InvoiceTypeFilter.allCases, id: \.self) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                    Picker("Statut", selection: $statusFilter) {
                        Text("Tous statuts").tag(InvoiceStatus?.none)
                        ForEach(InvoiceStatus.allCases, id: \.self) { s in
                            Label(s.label, systemImage: s.systemImage).tag(InvoiceStatus?.some(s))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                    Spacer()
                    Menu {
                        ForEach(QuickExport.Format.allCases, id: \.self) { f in
                            Button(f.rawValue) { exportMessage = QuickExport.run(invoices: filteredInvoices, format: f) }
                        }
                    } label: { Label("Exporter", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.bordered)
                        .help("Exporte les factures actuellement filtrées (\(filteredInvoices.count))")
                }
                if let m = exportMessage, !m.isEmpty {
                    Text(m).font(.caption).foregroundStyle(.secondary)
                        .onChange(of: query) { _ in exportMessage = nil }
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
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.clear))
                DisclosureGroup(isExpanded: $showAdvancedFilters) {
                    HStack(alignment: .center, spacing: 12) {
                        advancedFilterRow(field: $advField1, value: $advValue1, index: 1)
                        if advField1 != .none || !advValue1.isEmpty || showAdvancedFilters {
                            advancedFilterRow(field: $advField2, value: $advValue2, index: 2)
                        }
                        if advField2 != .none || !advValue2.isEmpty || showAdvancedFilters {
                            advancedFilterRow(field: $advField3, value: $advValue3, index: 3)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 4)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.caption)
                        Text("Filtres avancés")
                            .font(.caption.bold())
                        Text("(\(activeAdvancedFilterCount))")
                            .font(.caption.bold())
                            .foregroundStyle(activeAdvancedFilterCount > 0 ? Color.accentColor : .secondary)
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
                }
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
                        .buttonStyle(.borderedProminent)
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
                                if invoice.isOverdue {
                                    Label("En retard", systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption2).foregroundStyle(.red)
                                }
                                Spacer()
                            }
                            Text("\(invoice.buyer.name.isEmpty ? "Sans client" : invoice.buyer.name)")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(String(format: "%.2f %@ TTC", invoice.grandTotal, invoice.currency))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .contextMenu {
                            Button {
                                let copy = store.duplicate(from: invoice)
                                store.upsert(copy)
                                selectedID = copy.id
                            } label: { Label("Dupliquer", systemImage: "plus.square.on.square") }
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
                    .frame(minWidth: 180, idealWidth: 230, maxWidth: 270)
                }

                if let id = selectedID,
                   filteredInvoices.contains(where: { $0.id == id }) {
                    InvoiceEditorView(invoice: binding(for: id))
                        .frame(minWidth: 420)
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
        .sheet(isPresented: $showQuotePicker) {
            QuoteToInvoiceSheet(
                quotes: scopedInvoiceableQuotes,
                onCreate: { quote in
                    let number = store.nextNumber(companyID: quote.companyID)
                    let invoice = quote.toInvoice(number: number)
                    store.upsert(invoice)
                    var converted = quote
                    converted.convertedInvoiceNumber = invoice.number
                    quoteStore.upsert(converted)
                    selectedID = invoice.id
                    showQuotePicker = false
                },
                onCancel: { showQuotePicker = false }
            )
        }
        .sheet(isPresented: $showQuickInvoiceWizard) {
            SalesInvoiceWizardView(
                onCreated: { invoiceID in
                    selectedID = invoiceID
                    showQuickInvoiceWizard = false
                },
                onCancel: { showQuickInvoiceWizard = false }
            )
        }
        .sheet(isPresented: $showScanImport) {
            DocumentScanInvoiceImportView(
                onCreated: { invoiceID in
                    selectedID = invoiceID
                    showScanImport = false
                },
                onCancel: { showScanImport = false }
            )
        }
        .onChange(of: filteredInvoices) { newList in
            if let id = selectedID, !newList.contains(where: { $0.id == id }) {
                selectedID = nil
            }
        }
        .onChange(of: selectedID) { id in
            if let id = id, !filteredInvoices.contains(where: { $0.id == id }) {
                selectedID = nil
            }
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

    /// Devis facturables : acceptés (le client a dit oui) et pas déjà convertis — même
    /// garde que le bouton "Convertir en facture" sur la fiche devis elle-même, pour que
    /// cette seconde entrée n'invente pas une règle différente.
    private var scopedInvoiceableQuotes: [Quote] {
        var result = quoteStore.quotes.filter { $0.status == .accepted && $0.convertedInvoiceNumber == nil }
        if let scope = auth.visibleInvoiceCompanyIDs(for: auth.currentUser) {
            result = result.filter { quote in
                if let cid = quote.companyID { return scope.contains(cid) }
                return false
            }
        }
        return result.sorted { $0.issueDate > $1.issueDate }
    }

    private func binding(for id: UUID) -> Binding<Invoice> {
        Binding(
            get: { store.invoices.first(where: { $0.id == id }) ?? Invoice(number: "", seller: store.myCompany, buyer: .init(name: "", street: "", postcode: "", city: "")) },
            set: { newValue in
                store.upsert(newValue)
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

    private func applyAdvancedFilter(_ invoices: [Invoice], field: InvoiceFilterField, value: String) -> [Invoice] {
        let raw = value.trimmingCharacters(in: .whitespaces)
        let v = raw.lowercased()
        guard field != .none, !v.isEmpty else { return invoices }
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
            return invoices.filter { $0.number.lowercased().contains(v) }
        case .buyerName:
            return invoices.filter { $0.buyer.name.lowercased().contains(v) }
        case .buyerSiren:
            return invoices.filter { ($0.buyer.siren ?? "").lowercased().contains(v) }
        case .buyerVat:
            return invoices.filter { ($0.buyer.vatNumber ?? "").lowercased().contains(v) }
        case .sellerName:
            return invoices.filter { $0.seller.name.lowercased().contains(v) }
        case .sellerSiren:
            return invoices.filter { ($0.seller.siren ?? "").lowercased().contains(v) }
        case .amountMin:
            if let min = Double(v.replacingOccurrences(of: ",", with: ".")) {
                return invoices.filter { $0.grandTotal >= min }
            }
            return invoices
        case .amountMax:
            if let max = Double(v.replacingOccurrences(of: ",", with: ".")) {
                return invoices.filter { $0.grandTotal <= max }
            }
            return invoices
        case .issueDateFrom:
            if let d = parseDate(raw) { return invoices.filter { $0.issueDate >= d } }
            return invoices
        case .issueDateTo:
            if let d = parseDate(raw) { return invoices.filter { $0.issueDate <= d } }
            return invoices
        case .dueDateFrom:
            if let d = parseDate(raw) { return invoices.filter { $0.dueDate >= d } }
            return invoices
        case .purchaseOrderRef:
            return invoices.filter { ($0.purchaseOrderRef ?? "").lowercased().contains(v) }
        case .contractRef:
            return invoices.filter { ($0.contractRef ?? "").lowercased().contains(v) }
        case .precedingInvoiceRef:
            return invoices.filter { ($0.precedingInvoiceRef ?? "").lowercased().contains(v) }
        case .status:
            return invoices.filter { $0.status.rawValue.lowercased() == v || $0.status.label.lowercased().contains(v) }
        case .type:
            return invoices.filter { $0.type.label.lowercased().contains(v) || ($0.type.isCreditNote ? "avoir" : "facture").contains(v) }
        case .none:
            return invoices
        }
    }

    @ViewBuilder
    private func advancedFilterRow(field: Binding<InvoiceFilterField>, value: Binding<String>, index: Int) -> some View {
        let isDate = {
            switch field.wrappedValue {
            case .issueDateFrom, .issueDateTo, .dueDateFrom: return true
            default: return false
            }
        }()
        let isAmount = (field.wrappedValue == .amountMin || field.wrappedValue == .amountMax)
        HStack(spacing: 8) {
            Picker("", selection: field) {
                ForEach(InvoiceFilterField.allCases, id: \.self) { f in
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
}

struct OptionalFieldsSection: View {
    @Binding var fields: [OptionalField]
    let location: OptionalFieldLocation
    var locked: Bool = false

    private var templates: [OptionalFieldTemplate] { OptionalFieldCatalogue.templates(for: location) }
    private var title: String { location == .header ? "Champs optionnels (entete)" : "Champs optionnels (ligne)" }

    private func labelFor(tagName: String) -> String {
        if let tpl = OptionalFieldCatalogue.template(forTag: tagName, location: location) {
            return "\(tpl.bt) - \(tpl.label)"
        }
        return tagName
    }

    private func helpFor(tagName: String) -> String {
        OptionalFieldCatalogue.template(forTag: tagName, location: location)?.help ?? "Balise libre (non emise dans le XML CII)."
    }

    var body: some View {
        DisclosureGroup(title) {
            VStack(alignment: .leading, spacing: 6) {
                if fields.isEmpty {
                    Text("Aucun champ optionnel.").foregroundStyle(.secondary)
                }
                ForEach($fields) { $field in
                    fieldRow(field: $field)
                }
                Menu {
                    ForEach(templates) { tpl in
                        Button {
                            fields.append(OptionalField(tagName: tpl.tagName, value: ""))
                        } label: {
                            Label("\(tpl.bt) - \(tpl.label)", systemImage: "tag")
                        }
                    }
                    Divider()
                    Button {
                        fields.append(OptionalField(tagName: "", value: ""))
                    } label: {
                        Label("Balise personnalisee...", systemImage: "pencil")
                    }
                } label: {
                    Label("Ajouter un champ", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .disabled(locked)
            }
            .padding(.top, 4)
        }
        .font(.caption)
        .disabled(locked)
    }

    @ViewBuilder
    private func fieldRow(field: Binding<OptionalField>) -> some View {
        let tagName = field.tagName.wrappedValue
        let isCustom = tagName.isEmpty || OptionalFieldCatalogue.template(forTag: tagName, location: location) == nil
        HStack(spacing: 4) {
            Menu {
                ForEach(templates) { tpl in
                    Button {
                        field.tagName.wrappedValue = tpl.tagName
                    } label: {
                        Text("\(tpl.bt) - \(tpl.label)")
                    }
                }
                Divider()
                Button {
                    field.tagName.wrappedValue = ""
                } label: {
                    Text("Personnalisee...")
                }
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "tag")
                    Text(tagName.isEmpty ? "Choisir une balise..." : labelFor(tagName: tagName))
                        .lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .frame(width: 320, alignment: .leading)
            }
            if isCustom {
                let placeholder = OptionalFieldCatalogue.template(forTag: tagName, location: location)?.label ?? "ram:..."
                TextField(placeholder, text: field.tagName).frame(width: 200)
            }
            TextField("Valeur", text: field.value).frame(maxWidth: .infinity)
            InfoBadge(text: helpFor(tagName: tagName))
            Button {
                if let idx = fields.firstIndex(where: { $0.id == field.wrappedValue.id }) {
                    fields.remove(at: idx)
                }
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
        }
    }
}

struct InvoiceEditorView: View {
    @Binding var invoice: Invoice
    @EnvironmentObject var store: InvoiceStore
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var superPDPSettings: SuperPDPSettings
    @EnvironmentObject var invoiceStatusStore: InvoiceStatusStore
    @EnvironmentObject var smtpSettings: SMTPSettings
    @EnvironmentObject var emailTemplateStore: EmailTemplateStore
    @EnvironmentObject var paymentTermsStore: PaymentTermsPresetStore
    @State private var sendingInvoiceEmail = false
    @State private var invoiceEmailMessage: String?
    @State private var exportError: String?
    @State private var exportedURL: URL?
    @State private var duplicatedNumber: String?
    @State private var validation: FacturXValidationResult?
    @State private var showValidation = false
    @State private var isManuallyLocked = false
    @State private var showUnlockAlert = false
    @State private var adminConfirmedEdit = false
    @State private var showAdminEditConfirm = false
    @State private var showPrecedingInvoicePicker = false
    @State private var showMandatoryDetails = false
    @State private var superPDPSubmitting = false
    @State private var superPDPMessage: String?
    @State private var superPDPSubmission: SuperPDPInvoiceSubmission?
    @State private var pdpDownloadedURL: URL?
    @State private var syncingFromPDP = false
    @State private var lastSentPDPStatusCode: String?
    @State private var showStatusJournal = false
    @State private var showLegalMentions = false
    @State private var showInvoicePreview = false
    @State private var previewPDFData: Data?
    @State private var showPDPEvents = false
    @State private var pdpEvents: [SuperPDPInvoiceEvent] = []
    @State private var pdpEventsLoading = false
    @State private var pdpDownloading = false
    @State private var pdpValidating = false
    @State private var pdpValidationReport: SuperPDPValidationReport?
    @State private var showPDPValidationPanel = false
    @State private var sendingReminder = false
    @State private var reminderMessage: String?
    private var isLocked: Bool { invoice.status.locksInvoice || isManuallyLocked }
    private var statusLocked: Bool { invoice.status.locksInvoice }
    private var isAdmin: Bool { auth.currentUser?.isAdmin ?? false }
    /// Un admin peut modifier une facture verrouillée par son statut (payée,
    /// acceptée, annulée), mais seulement après confirmation explicite — jamais
    /// en silence, pour éviter une incohérence comptable accidentelle.
    private var fieldLocked: Bool {
        guard isLocked else { return false }
        if statusLocked { return !(isAdmin && adminConfirmedEdit) }
        return !isAdmin
    }
    private var sellerLogo: Data? {
        guard let cid = invoice.companyID else { return nil }
        return PartyDirectory.shared.entries.first(where: { $0.id == cid })?.logoData
    }

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

    private var errorRuleIDs: Set<String> {
        guard let v = validation, showValidation else { return [] }
        return Set(v.businessRules.filter { $0.severity == .error }.map { $0.ruleId })
    }

    /// `nil` = "Personnalisé" (saisie libre) ; sinon l'id du préréglage sélectionné.
    /// Appliquer un préréglage recalcule aussi l'échéance (BT-9) à partir de la date de
    /// facture — l'utilisateur garde toujours la main pour modifier la date ensuite,
    /// ce calcul ne verrouille jamais le champ.
    private var paymentTermsPresetIDBinding: Binding<String?> {
        Binding(
            get: { paymentTermsStore.matchingPresetID(for: invoice.paymentTerms) },
            set: { newID in
                guard let id = newID, let preset = paymentTermsStore.presets.first(where: { $0.id == id }) else { return }
                invoice.paymentTerms = preset.text
                invoice.dueDate = preset.dueRule.dueDate(from: invoice.issueDate)
            }
        )
    }

    private func fieldHighlight<V: View>(_ view: V, forRuleIDs ids: [String]) -> some View {
        view.overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.red, lineWidth: ids.contains(where: { errorRuleIDs.contains($0) }) ? 1.5 : 0)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Bandeau d'informations (fixe, lecture seule)
            HStack(spacing: 10) {
                Text(invoice.number).font(.title2.bold())
                Text(invoice.issueDate, format: .dateTime.day().month().year())
                    .font(.callout).foregroundStyle(.secondary)
                Text(String(format: "%.2f %@ HT", invoice.lineTotal, invoice.currency))
                    .font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Image(systemName: invoice.status.systemImage)
                    Text(invoice.status.label)
                }
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Color(hex: invoice.status.hexColor)))
                if invoice.isOverdue {
                    Label("En retard (\(invoice.overdueDays) j)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.red))
                }
                if superPDPSettings.credentials.usePDP {
                    Button {
                        fetchPDPEvents()
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.callout)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(((invoice.superPDPRemoteID ?? superPDPSubmission?.remoteID ?? "").isEmpty)
                              || !superPDPSettings.credentials.isConfigured)
                    .help("Historique des événements de cycle de vie sur SUPER PDP")
                }
                if isLocked {
                    Label(statusLocked ? "Verrouillée (statut)" : "Lecture seule", systemImage: "lock.fill")
                        .font(.caption.bold())
                        .foregroundStyle(statusLocked ? Color(hex: invoice.status.hexColor) : .secondary)
                        .padding(.horizontal, 6)
                        .overlay(Capsule().stroke(.secondary, lineWidth: 0.5))
                    if isAdmin && statusLocked && adminConfirmedEdit {
                        Label("Modification admin activée", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2.bold()).foregroundStyle(.red)
                    }
                }
                Spacer()
                HStack(spacing: 4) {
                    Text(invoice.seller.name.trimmingCharacters(in: .whitespaces).isEmpty ? "Émetteur non renseigné" : invoice.seller.name)
                    Image(systemName: "arrow.right").font(.caption2)
                    Text(invoice.buyer.name.trimmingCharacters(in: .whitespaces).isEmpty ? "Client non renseigné" : invoice.buyer.name)
                }
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .padding(.horizontal, 12).padding(.top, 12)
            Divider()

            // MARK: Barre d'actions (fixe), sous-groupée : cycle de vie · utilitaires · admin
            // Défile horizontalement plutôt que de recadrer les boutons si la fenêtre est étroite.
            ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                let configuredTransitions = invoiceStatusStore.override(for: invoice.status).transitionCodes.compactMap { InvoiceStatus(rawValue: $0) }
                HStack(spacing: 8) {
                    if isManuallyLocked && !statusLocked && !isAdmin {
                        Button { showUnlockAlert = true } label: {
                            Label("Modifier", systemImage: "lock.open")
                        }
                        .buttonStyle(ToolbarActionButtonStyle(tint: .gray))
                        .help("Repasser en édition (la facture n'est plus protégée)")
                    } else if statusLocked && isAdmin && !adminConfirmedEdit {
                        Button { showAdminEditConfirm = true } label: {
                            Label("Modifier quand même", systemImage: "exclamationmark.triangle")
                        }
                        .buttonStyle(ToolbarActionButtonStyle(tint: .red))
                        .help("Facture « \(invoice.status.label) » : la modifier peut créer une incohérence comptable ou avec SUPER PDP — confirmation requise")
                    } else if !isLocked && validation?.isValid == true {
                        Button { isManuallyLocked = true } label: {
                            Label("Verrouiller", systemImage: "lock")
                        }
                        .buttonStyle(ToolbarActionButtonStyle(tint: .gray))
                        .help("Protéger la facture validée en lecture seule")
                    }
                    if superPDPSettings.credentials.usePDP {
                            Button {
                                validatePDP()
                            } label: {
                                if pdpValidating {
                                    HStack(spacing: 4) {
                                        ProgressView().controlSize(.small)
                                        Text("Valider…")
                                    }
                                } else {
                                    Label("Valider PDP", systemImage: "checkmark.shield")
                                }
                            }
                            .buttonStyle(ToolbarActionButtonStyle(tint: .blue))
                            .disabled(pdpValidating || !superPDPSettings.credentials.isConfigured)
                            .help("Valider le Factur-X sur SUPER PDP avant dépôt")
                    } else {
                        Button("Valider") { runValidation() }
                            .buttonStyle(ToolbarActionButtonStyle(tint: .blue))
                            .disabled(fieldLocked)
                    }
                    ForEach(configuredTransitions, id: \.self) { s in
                        Button {
                            invoice.status = s
                        } label: {
                            Label(s.label, systemImage: s.systemImage)
                        }
                        .buttonStyle(ToolbarActionButtonStyle(tint: Color(hex: s.hexColor)))
                        .help("Passer au statut « \(s.label) »")
                    }
                    if invoice.type.isInternalCreditNote {
                        Button("Exporter PDF") { exportPlainPDF() }
                            .buttonStyle(ToolbarActionButtonStyle(tint: .blue, filled: true))
                    } else if superPDPSettings.credentials.usePDP {
                        Button {
                            depositToSuperPDP()
                        } label: { Label("Super PDP", systemImage: "paperplane.fill") }
                            .buttonStyle(ToolbarActionButtonStyle(tint: .blue, filled: true))
                            .disabled(fieldLocked || statusLocked || superPDPSubmitting || !superPDPSettings.credentials.isConfigured)
                            .help("Déposer la facture Factur-X sur SUPER PDP (Plateforme Agréée)")
                    }
                }

                Divider().frame(height: 20)

                HStack(spacing: 8) {
                    Menu {
                        Button {
                            previewPDFData = FacturXGenerator().generateVisiblePDF(invoice: invoice, logo: sellerLogo)
                            showInvoicePreview = true
                        } label: { Label("Visualiser", systemImage: "eye") }
                        Button { exportXML() } label: { Label("Exporter XML", systemImage: "chevron.left.forwardslash.chevron.right") }
                        Button { export() } label: { Label("Générer le Factur-X", systemImage: "doc.text.fill") }
                        Button {
                            let copy = store.duplicate(from: invoice)
                            store.upsert(copy)
                            duplicatedNumber = copy.number
                        } label: { Label("Dupliquer", systemImage: "plus.square.on.square") }
                        if superPDPSettings.credentials.usePDP {
                            Divider()
                            Button {
                                downloadPDPInvoice()
                            } label: { Label("Copie PDP", systemImage: "square.and.arrow.down") }
                                .disabled(pdpDownloading
                                          || ((invoice.superPDPRemoteID ?? superPDPSubmission?.remoteID ?? "").isEmpty)
                                          || !superPDPSettings.credentials.isConfigured)
                                .help("Télécharger la copie de la facture déposée sur SUPER PDP")
                        }
                    } label: {
                        Label("Autre action", systemImage: "ellipsis.circle")
                    }
                    .buttonStyle(ToolbarActionButtonStyle(tint: .gray))
                    .help("Visualiser, exporter XML, générer le Factur-X, dupliquer, copie PDP…")
                    if superPDPSettings.credentials.usePDP {
                        Button {
                            refreshSuperPDPStatus()
                        } label: {
                            if superPDPSubmitting {
                                HStack(spacing: 4) {
                                    ProgressView().controlSize(.small)
                                    Text("Statut PDP…")
                                }
                            } else {
                                Label("Statut PDP", systemImage: "antenna.radar")
                            }
                        }
                        .buttonStyle(ToolbarActionButtonStyle(tint: .gray))
                        .disabled(superPDPSubmitting
                                  || ((invoice.superPDPRemoteID ?? superPDPSubmission?.remoteID ?? "").isEmpty)
                                  || !superPDPSettings.credentials.isConfigured)
                        .help("Interroger le statut de la facture sur SUPER PDP")
                    }
                }

                if emailTemplateStore.globalEnabled {
                    Divider().frame(height: 20)
                    Button {
                        sendInvoiceEmail()
                    } label: {
                        if sendingInvoiceEmail {
                            HStack(spacing: 4) { ProgressView().controlSize(.small); Text("Envoi…") }
                        } else {
                            Label("Envoyer la facture", systemImage: EmailTemplateKind.invoiceSent.systemImage)
                        }
                    }
                    .buttonStyle(ToolbarActionButtonStyle(tint: .blue))
                    .disabled(sendingInvoiceEmail
                              || !emailTemplateStore.isSendEnabled(.invoiceSent)
                              || (invoice.buyer.contactEmail ?? "").isEmpty
                              || !smtpSettings.credentials.isConfigured)
                    .help(!emailTemplateStore.template(for: .invoiceSent).enabled
                          ? "Cet email est désactivé (Réglages > Application)"
                          : (invoice.buyer.contactEmail ?? "").isEmpty
                          ? "Aucune adresse email cliente renseignée"
                          : !smtpSettings.credentials.isConfigured
                          ? "Configurez l'envoi d'email (Réglages) pour envoyer la facture"
                          : "Envoyer la facture par email au client")

                    if invoice.isOverdue {
                        Divider().frame(height: 20)
                        HStack(spacing: 8) {
                            Menu {
                                ForEach(PaymentReminderLevel.allCases) { level in
                                    Button {
                                        sendReminder(level: level)
                                    } label: { Label(level.label, systemImage: level.systemImage) }
                                }
                            } label: {
                                if sendingReminder {
                                    HStack(spacing: 4) {
                                        ProgressView().controlSize(.small)
                                        Text("Envoi…")
                                    }
                                } else {
                                    Label("Relance", systemImage: "exclamationmark.bubble")
                                }
                            }
                            .buttonStyle(ToolbarActionButtonStyle(tint: .red))
                            .disabled(sendingReminder
                                      || !emailTemplateStore.isSendEnabled(.invoiceReminder)
                                      || (invoice.buyer.contactEmail ?? "").isEmpty
                                      || !smtpSettings.credentials.isConfigured)
                            .help(!emailTemplateStore.template(for: .invoiceReminder).enabled
                                  ? "Les relances sont désactivées (Réglages > Application)"
                                  : (invoice.buyer.contactEmail ?? "").isEmpty
                                  ? "Aucune adresse email cliente renseignée"
                                  : !smtpSettings.credentials.isConfigured
                                  ? "Configurez l'envoi d'email (Réglages) pour envoyer une relance"
                                  : "Envoyer un email de relance au client")
                        }
                    }
                }

                if isAdmin {
                    let forceable = InvoiceStatus.allCases.filter { $0 != invoice.status && !configuredTransitions.contains($0) }
                    if !forceable.isEmpty || superPDPSettings.credentials.usePDP {
                        Divider().frame(height: 20)
                        HStack(spacing: 8) {
                            if !forceable.isEmpty {
                                Menu {
                                    ForEach(forceable, id: \.self) { s in
                                        Button {
                                            invoice.status = s
                                        } label: {
                                            Label(s.label, systemImage: s.systemImage)
                                        }
                                    }
                                } label: {
                                    Label("Forcer", systemImage: "bolt.fill")
                                }
                                .buttonStyle(ToolbarActionButtonStyle(tint: .red))
                                .help("Administrateur : forcer un statut hors des transitions configurées")
                            }
                            if superPDPSettings.credentials.usePDP {
                                Button {
                                    notifyPDPStatusChange(to: invoice.status, force: true)
                                } label: {
                                    Label("Forcer renvoi", systemImage: "arrow.clockwise.circle")
                                }
                                .buttonStyle(ToolbarActionButtonStyle(tint: .red))
                                .disabled(((invoice.superPDPRemoteID ?? superPDPSubmission?.remoteID ?? "").isEmpty)
                                          || !superPDPSettings.credentials.isConfigured)
                                .help("Forcer le renvoi du statut actuel à SUPER PDP (admin)")
                            }
                        }
                    }
                }
                Spacer()
            }
            .padding(12)
            }
            Divider()
            if hasMandatoryWarnings || showValidation || showPDPValidationPanel || exportError != nil || exportedURL != nil || duplicatedNumber != nil || superPDPMessage != nil || superPDPSubmission != nil || reminderMessage != nil || invoiceEmailMessage != nil {
                VStack(alignment: .leading, spacing: 8) {
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
                if let n = duplicatedNumber {
                    Text("Facture dupliquée : \(n) (disponible dans la liste)").font(.caption).foregroundStyle(.green)
                        .onChange(of: invoice.number) { _ in duplicatedNumber = nil }
                }
                if let m = reminderMessage {
                    Text(m).font(.caption).foregroundStyle(m.hasPrefix("Échec") ? .red : .green)
                        .onChange(of: invoice.number) { _ in reminderMessage = nil }
                }
                if let m = invoiceEmailMessage {
                    Text(m).font(.caption).foregroundStyle(m.hasPrefix("Échec") ? .red : .green)
                        .onChange(of: invoice.number) { _ in invoiceEmailMessage = nil }
                }
                if let m = superPDPMessage {
                    HStack(spacing: 6) {
                        if m.hasPrefix("Échec") {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                        } else if let sub = superPDPSubmission {
                            Image(systemName: sub.isProcessed ? "checkmark.seal.fill" : "hourglass")
                                .foregroundStyle(sub.isProcessed ? .green : .orange)
                            Image(systemName: sub.direction == .sent ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                                .foregroundStyle(sub.direction == .sent ? .blue : .teal)
                                .help(sub.direction == .sent ? "Envoyé à Super PDP" : "Reçu de Super PDP")
                        } else {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                        }
                        Text(m).font(.caption).foregroundStyle(m.hasPrefix("Échec") ? .red : .primary)
                        if let durl = pdpDownloadedURL {
                            Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([durl]) }
                                .buttonStyle(.borderless)
                                .font(.caption)
                        }
                    }
                    .onChange(of: invoice.number) { _ in superPDPMessage = nil; superPDPSubmission = nil; pdpDownloadedURL = nil }
                } else if let sub = superPDPSubmission {
                    HStack(spacing: 6) {
                        Image(systemName: sub.isProcessed ? "checkmark.seal.fill" : "hourglass")
                            .foregroundStyle(sub.isProcessed ? .green : .orange)
                        Image(systemName: sub.direction == .sent ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                            .foregroundStyle(sub.direction == .sent ? .blue : .teal)
                            .help(sub.direction == .sent ? "Envoyé à Super PDP" : "Reçu de Super PDP")
                        Text("SUPER PDP — id \(sub.remoteID ?? "?") · statut \(sub.status) · \(sub.direction == .sent ? "envoyé" : "reçu")").font(.caption)
                    }
                    .onChange(of: invoice.number) { _ in superPDPSubmission = nil }
                }

                if hasMandatoryWarnings {
                    DisclosureGroup(isExpanded: $showMandatoryDetails) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Émetteur et destinataire : nom, pays (code ISO 2 lettres), SIREN ou identifiant électronique (BT-49/34), n° TVA si applicable.").font(.caption)
                            Text("Lignes : désignation non vide, quantité positive, prix unitaire, taux TVA, unité (code UN/ECE ex. C62, DAY, HUR).").font(.caption)
                            Text("En-tête : numéro de facture, date, échéance, devise (EUR), mode de facturation (BT-23).").font(.caption)
                            Text("Mentions légales FR : frais de recouvrement (PMT), pénalités de retard (PMD), escompte (AAB) — pré-remplies, modifiables.").font(.caption)
                            Text("Paiement : IBAN et BIC si virement SEPA.").font(.caption)
                        }
                    } label: {
                        Label("Données obligatoires pour la conformité Factur-X", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                    }
                }

                if showValidation, let v = validation {
                    validationPanel(v)
                        .onChange(of: invoice.number) { _ in showValidation = false; validation = nil }
                }
                if showPDPValidationPanel, let report = pdpValidationReport {
                    pdpValidationPanel(report)
                        .onChange(of: invoice.number) { _ in showPDPValidationPanel = false; pdpValidationReport = nil }
                }
                }.padding(12)
                Divider()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
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
                                        fieldHighlight(TextField("", text: $invoice.number).frame(width: 160), forRuleIDs: ["BR-1"])
                                    } label: {
                                        HStack(spacing: 3) {
                                            Text("Numéro *").foregroundColor(.red)
                                            InfoBadge(text: "BT-1 — Numéro unique de la facture. Obligatoire.")
                                        }
                                    }
                                    .help("Créée le \(invoice.createdAt.formatted(.dateTime.day().month().year().hour().minute())) (non modifiable).")
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 3) {
                                            Text("Type").font(.caption)
                                            InfoBadge(text: "BT-3 — Code type. 380 facture, 381 avoir, 384 rectificative.")
                                        }
                                        Picker("", selection: $invoice.type) {
                                            ForEach(InvoiceTypeCode.allCases, id: \.self) { Text($0.label).tag($0) }
                                        }.labelsHidden().frame(width: 260)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 3) {
                                            Text("Devise").font(.caption)
                                            InfoBadge(text: "BT-5 — Code de la devise (ram:TaxCurrencyCode / ram:InvoiceCurrencyCode).")
                                        }
                                        fieldHighlight(NormRefPicker("", options: NormRefs.currencies, code: $invoice.currency).labelsHidden().frame(width: 160), forRuleIDs: ["BR-5"])
                                    }
                                }
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 3) {
                                            Text("Date facture").font(.caption)
                                            InfoBadge(text: "BT-2 — Date d'émission de la facture. Obligatoire.")
                                        }
                                        DatePicker("", selection: $invoice.issueDate, displayedComponents: .date).labelsHidden()
                                            .onChange(of: invoice.issueDate) { newDate in
                                                guard let id = paymentTermsPresetIDBinding.wrappedValue,
                                                      let preset = paymentTermsStore.presets.first(where: { $0.id == id }) else { return }
                                                invoice.dueDate = preset.dueRule.dueDate(from: newDate)
                                            }
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 3) {
                                            Text("Échéance").font(.caption)
                                            InfoBadge(text: "BT-9 — Date d'échéance du paiement. Obligatoire si non déduit des conditions.")
                                        }
                                        DatePicker("", selection: $invoice.dueDate, displayedComponents: .date).labelsHidden()
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 3) {
                                            Text("Mode facturation (BT-23)").font(.caption)
                                            InfoBadge(text: "BT-23 — Mode de facturation (B/S/M). Requis pour le cycle de vie PDP.")
                                        }
                                        Picker("", selection: $invoice.billingMode) {
                                            ForEach(BillingMode.allCases, id: \.self) { Text($0.label).tag($0) }
                                        }.labelsHidden().frame(width: 320)
                                    }
                                }
                                HStack(spacing: 6) {
                                    Image(systemName: "banknote").foregroundStyle(.secondary)
                                    Text("Conditions de paiement :").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                                    Picker("", selection: paymentTermsPresetIDBinding) {
                                        ForEach(paymentTermsStore.presets) { preset in
                                            Text(preset.label).tag(Optional(preset.id))
                                        }
                                        Text("Personnalisé").tag(String?.none)
                                    }
                                    .labelsHidden()
                                    .frame(width: 180)
                                    .disabled(fieldLocked)
                                    .help("Applique le texte du préréglage et recalcule l'échéance ci-dessus — celle-ci reste modifiable manuellement ensuite.")
                                    TextField("Ex. Paiement à 30 jours", text: Binding($invoice.paymentTerms, replacingNilWith: ""))
                                        .textFieldStyle(.roundedBorder)
                                        .font(.callout)
                                        .frame(maxWidth: 260)
                                        .disabled(fieldLocked)
                                    if (invoice.paymentTerms ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                                        Label("Non renseignées", systemImage: "exclamationmark.circle")
                                            .font(.caption).foregroundStyle(.orange)
                                    }
                                }
                                .padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity((invoice.paymentTerms ?? "").trimmingCharacters(in: .whitespaces).isEmpty ? 0.08 : 0)))
                                HStack(spacing: 3) {
                                    TextField("Référence commande (BT-13)", text: Binding($invoice.purchaseOrderRef, replacingNilWith: "")).frame(width: 260)
                                    InfoBadge(text: "BT-13 — Numéro de commande acheteur (BuyerOrderReferencedDocument/IssuerAssignedID). Distinct du BT-10 : c'est le numéro du bon de commande, pas la référence de routage.")
                                }
                                if invoice.type.requiresPrecedingInvoice || invoice.type == .internalCreditNote {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Facture antérieure référencée :").font(.caption.bold())
                                        HStack(spacing: 6) {
                                            Button {
                                                showPrecedingInvoicePicker = true
                                            } label: {
                                                HStack(spacing: 6) {
                                                    Image(systemName: "doc.text.magnifyingglass")
                                                    VStack(alignment: .leading, spacing: 1) {
                                                        let ref = (invoice.precedingInvoiceRef ?? "").trimmingCharacters(in: .whitespaces)
                                                        if !ref.isEmpty {
                                                            Text(ref).font(.caption.bold())
                                                            if let d = invoice.precedingInvoiceDate {
                                                                Text("Date : \(d, format: .dateTime.day().month().year())")
                                                                    .font(.caption2).foregroundStyle(.secondary)
                                                            } else {
                                                                Text("Date : non renseignée")
                                                                    .font(.caption2).foregroundStyle(.orange)
                                                            }
                                                        } else {
                                                            Text("Sélectionner une facture…").foregroundStyle(.secondary)
                                                        }
                                                    }
                                                    Spacer()
                                                    Image(systemName: "chevron.right")
                                                        .font(.caption2).foregroundStyle(.secondary)
                                                }
                                                .frame(maxWidth: 360, alignment: .leading)
                                            }
                                            .buttonStyle(.bordered)
                                            .overlay(RoundedRectangle(cornerRadius: 4)
                                                .stroke(Color.red, lineWidth: errorRuleIDs.contains("BR-FR-CO-05") ? 1.5 : 0))
                                            if linkableInvoices.isEmpty {
                                                Text("Aucune facture disponible").font(.caption2).foregroundStyle(.secondary)
                                            }
                                            if (invoice.precedingInvoiceRef ?? "").trimmingCharacters(in: .whitespaces) != "" {
                                                Button {
                                                    invoice.precedingInvoiceRef = nil
                                                    invoice.precedingInvoiceDate = nil
                                                } label: {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .foregroundStyle(.secondary)
                                                }
                                                .buttonStyle(.borderless)
                                                .help("Effacer la référence")
                                            }
                                            InfoBadge(text: "BT-25/BT-26 — Numéro et date de la facture antérieure référencée. Sélection dans les factures du périmètre (hors avoirs).")
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
                                companyScopePicker
                                OptionalFieldsSection(fields: $invoice.optionalFields, location: .header, locked: fieldLocked)
                                .font(.caption)
                            }
                            VStack(alignment: .trailing, spacing: 4) {
                                VStack(alignment: .trailing) {
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
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.clear))
                            }
                        }
                    }.padding(8)
                }.lockable(fieldLocked)

                HStack(alignment: .top, spacing: 12) {
                    GroupBox("Émetteur (vous)") {
                        PartySection(party: $invoice.seller, role: .seller, onPartyPicked: { p in
                            invoice.paymentIBAN = p.iban
                            invoice.paymentBIC = p.bic
                            if let pt = p.paymentTerms, !pt.isEmpty { invoice.paymentTerms = pt }
                        }, locked: fieldLocked)
                    }.lockable(fieldLocked)
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.red, lineWidth: ["BR-6", "BR-7", "BR-49"].contains(where: { errorRuleIDs.contains($0) }) ? 1.5 : 0))
                    GroupBox("Destinataire") {
                        PartySection(party: $invoice.buyer, role: .buyer, locked: fieldLocked)
                    }.lockable(fieldLocked)
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.red, lineWidth: ["BR-25", "BR-26", "BR-46"].contains(where: { errorRuleIDs.contains($0) }) ? 1.5 : 0))
                }

                GroupBox("Lignes") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach($invoice.lines) { $line in
                            HStack {
                                HStack(spacing: 2) {
                                    fieldHighlight(TextField("Désignation *", text: $line.name).frame(minWidth: 220), forRuleIDs: ["BR-21"])
                                    InfoBadge(text: "BT-153 — Désignation de la ligne. Obligatoire.")
                                }
                                HStack(spacing: 2) {
                                    TextField("Commande", text: Binding($line.orderReference, replacingNilWith: ""))
                                        .frame(width: 140)
                                    InfoBadge(text: "BT-132 — Référence de commande liée à la ligne.")
                                }
                                HStack(spacing: 2) {
                                    fieldHighlight(DoubleField("Qté", value: $line.quantity, format: .number), forRuleIDs: ["BR-16"])
                                    InfoBadge(text: "BT-149 — Quantité. Doit être positive (facture) ou négative (avoir).")
                                }
                                HStack(spacing: 2) {
                                    NormRefPicker("Unité", options: NormRefs.units, code: $line.unit).frame(width: 180)
                                    InfoBadge(text: "BT-150 — Unité de mesure (UN/ECE Rec 20).")
                                }
                                HStack(spacing: 2) {
                                    fieldHighlight(DoubleField("P.U. HT", value: $line.unitPrice, format: .number), forRuleIDs: ["BR-17"])
                                    InfoBadge(text: "BT-146 — Prix unitaire HT.")
                                }
                                HStack(spacing: 2) {
                                    DoubleField("TVA %", value: $line.vatRate, format: .number)
                                    InfoBadge(text: "BT-151 — Taux de TVA appliqué (%).")
                                }
                                Text(String(format: "%.2f", line.lineTotal))
                                    .monospacedDigit().frame(width: 80, alignment: .trailing)
                                Button {
                                    // Différé au tick suivant : laisse le champ en cours d'édition
                                    // se valider (commit AppKit) avant que la ligne ne disparaisse,
                                    // sinon crash (Binding sur un index qui n'existe plus).
                                    DispatchQueue.main.async {
                                        invoice.lines.removeAll { $0.id == line.id }
                                    }
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                            }
                            OptionalFieldsSection(fields: $line.optionalFields, location: .line, locked: fieldLocked)
                                .padding(.leading, 4)
                        }
                        Button {
                            invoice.lines.append(InvoiceLine(name: "", quantity: 1, unitPrice: 0, vatRate: invoice.lines.last?.vatRate ?? 20))
                        } label: { Label("Ajouter une ligne", systemImage: "plus") }
                    }.padding(8)
                }.lockable(fieldLocked)

                GroupBox("Paiement") {
                    VStack(alignment: .leading, spacing: 8) {
                        if let iban = invoice.paymentIBAN, !iban.isEmpty {
                            HStack(spacing: 3) {
                                Text(iban).font(.caption.monospaced())
                                InfoBadge(text: "BT-84 — IBAN hérité de l'émetteur (annuaire).")
                            }
                        }
                        if let bic = invoice.paymentBIC, !bic.isEmpty {
                            HStack(spacing: 3) {
                                Text(bic).font(.caption.monospaced())
                                InfoBadge(text: "BT-85 — BIC hérité de l'émetteur (annuaire).")
                            }
                        }
                        if (invoice.paymentIBAN ?? "").isEmpty && (invoice.paymentBIC ?? "").isEmpty {
                            Text("Aucune coordonnée bancaire renseignée.").font(.caption).foregroundStyle(.secondary)
                        }
                        Text("Conditions de paiement : modifiables dans l'en-tête ci-dessus.")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }.padding(8)
                }.lockable(fieldLocked)

                GroupBox {
                    DisclosureGroup(isExpanded: $showLegalMentions) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Frais de recouvrement (SubjectCode PMT) :").font(.caption.bold())
                            TextField("Indemnité forfaitaire pour frais de recouvrement", text: $invoice.legalNotePMT)
                            Text("Pénalités de retard (SubjectCode PMD) :").font(.caption.bold())
                            TextField("Taux d'intérêt des pénalités de retard", text: $invoice.legalNotePMD)
                            Text("Escompte (SubjectCode AAB) :").font(.caption.bold())
                            TextField("Escompte pour paiement anticipé", text: $invoice.legalNoteAAB)
                            TextField("Notes libres", text: Binding($invoice.notes, replacingNilWith: ""))
                        }.padding(.top, 4)
                    } label: {
                        Label("Mentions légales (FR) — cliquer pour déplier", systemImage: "text.scroll")
                            .font(.headline)
                    }
                }.lockable(fieldLocked)
                statusJournalSection
            }.padding()
        }
            .alert("Repasser en modification ?", isPresented: $showUnlockAlert) {
                Button("Annuler", role: .cancel) { }
                Button("Modifier", role: .destructive) { isManuallyLocked = false }
            } message: {
                Text("La facture était verrouillée en lecture seule après validation conforme. En la déverrouillant, vous reprenez l'édition ; pensez à valider de nouveau avant tout dépôt PDP.")
            }
            .alert("Modifier une facture « \(invoice.status.label) » ?", isPresented: $showAdminEditConfirm) {
                Button("Annuler", role: .cancel) { }
                Button("Modifier quand même", role: .destructive) {
                    adminConfirmedEdit = true
                    store.audit?.record(
                        actor: auth.currentUser?.username ?? "admin",
                        action: "invoice_edit_unlocked_by_admin",
                        target: invoice.number,
                        details: "statut au moment du déverrouillage : \(invoice.status.label)",
                        objectType: .invoice,
                        objectCode: invoice.number
                    )
                }
            } message: {
                Text("Cette facture a le statut « \(invoice.status.label) ». La modifier peut créer une incohérence comptable ou avec SUPER PDP (facture déjà réglée ou acceptée). Cette action est tracée dans le journal d'audit. Continuer ?")
            }
            .onChange(of: invoice.number) { _ in adminConfirmedEdit = false }
            .sheet(isPresented: $showPrecedingInvoicePicker) {
                InvoicePickerSheet(
                    invoices: linkableInvoices,
                    selectedID: invoice.precedingInvoiceRef.flatMap { ref in
                        linkableInvoices.first(where: { $0.number == ref })?.id
                    },
                    onPick: { inv in
                        invoice.precedingInvoiceRef = inv.number
                        invoice.precedingInvoiceDate = inv.issueDate
                        showPrecedingInvoicePicker = false
                    },
                    onClear: {
                        invoice.precedingInvoiceRef = nil
                        invoice.precedingInvoiceDate = nil
                        showPrecedingInvoicePicker = false
                    },
                    onCancel: { showPrecedingInvoicePicker = false }
                )
            }
            .onChange(of: invoice.status) { newStatus in
                guard !syncingFromPDP else { return }
                notifyPDPStatusChange(to: newStatus)
                sendInvoiceStatusAlertIfNeeded(newStatus)
            }
            .sheet(isPresented: $showInvoicePreview) {
                InvoicePreviewSheet(pdfData: previewPDFData, title: "Facture \(invoice.number)")
            }
            .sheet(isPresented: $showPDPEvents) {
                SuperPDPEventsSheet(events: pdpEvents, loading: pdpEventsLoading)
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

    private var linkableInvoices: [Invoice] {
        let scope = auth.visibleInvoiceCompanyIDs(for: auth.currentUser)
        var result = store.invoices.filter { inv in
            guard !inv.type.isCreditNote else { return false }
            guard inv.id != invoice.id else { return false }
            if let scope = scope, let cid = inv.companyID { return scope.contains(cid) }
            if scope != nil && inv.companyID == nil { return false }
            return true
        }
        result.sort { $0.issueDate > $1.issueDate }
        return result
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
            let data = try FacturXGenerator().generate(invoice: invoice, logo: sellerLogo)
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

    private func depositToSuperPDP() {
        if let rid = (superPDPSubmission?.remoteID ?? invoice.superPDPRemoteID), !rid.isEmpty {
            superPDPMessage = "Facture déjà déposée sur SUPER PDP (id distant \(rid)). Ré-interrogez le statut plutôt que de redéposer."
            return
        }
        if invoice.status == .accepted || invoice.status == .paid || invoice.status == .cancelled {
            superPDPMessage = "Dépôt refusé : la facture est déjà « \(invoice.status.label) ». Un dépôt n'est possible que depuis Brouillon / Validée / Transmise."
            return
        }
        superPDPSubmitting = true
        superPDPMessage = nil
        let preCheck = FacturXValidator().validate(invoice: invoice)
        if !preCheck.isValid {
            validation = preCheck
            showValidation = true
            superPDPMessage = "Validation échouée : \(preCheck.errors.count) erreur(s). Corrigez avant de déposer."
            superPDPSubmitting = false
            return
        }
        Task {
            do {
                let facturx = try FacturXGenerator().generate(invoice: invoice, logo: sellerLogo)
                let service = SuperPDPService()
                let submission = try await service.submitInvoice(fileData: facturx, credentials: superPDPSettings.credentials)
                superPDPSubmission = SuperPDPInvoiceSubmission(
                    id: submission.id, remoteID: submission.remoteID, status: submission.status,
                    enInvoiceRef: submission.enInvoiceRef, submittedAt: submission.submittedAt,
                    lastCheckedAt: submission.lastCheckedAt, message: submission.message, direction: .sent
                )
                if let rid = submission.remoteID, !rid.isEmpty {
                    invoice.superPDPRemoteID = rid
                    if invoice.status == .issued || invoice.status == .draft {
                        invoice.status = .sentToPDP
                    }
                    store.upsert(invoice)
                }
                superPDPMessage = "↑ Envoyé à SUPER PDP — id distant \(submission.remoteID ?? "?") (statut : \(submission.status))."
                store.audit?.record(
                    actor: store.actorName,
                    action: "pdp_deposit_sent",
                    target: invoice.number,
                    details: "Dépôt facture sur SUPER PDP (envoyé) — id distant : \(submission.remoteID ?? "?")",
                    objectType: .invoice,
                    objectCode: invoice.number
                )
            } catch let e as SuperPDPError {
                superPDPMessage = "Échec dépôt SUPER PDP : \(e.localizedDescription)"
                store.audit?.record(
                    actor: store.actorName,
                    action: "pdp_deposit_error",
                    target: invoice.number,
                    details: "Échec dépôt SUPER PDP : \(e.localizedDescription)",
                    objectType: .invoice,
                    objectCode: invoice.number
                )
            } catch {
                superPDPMessage = "Échec dépôt SUPER PDP : \(error)"
                store.audit?.record(
                    actor: store.actorName,
                    action: "pdp_deposit_error",
                    target: invoice.number,
                    details: "Échec dépôt SUPER PDP : \(error)",
                    objectType: .invoice,
                    objectCode: invoice.number
                )
            }
            superPDPSubmitting = false
        }
    }

    private static func mapPDPStatusToLocal(_ pdpStatus: String) -> InvoiceStatus? {
        let s = pdpStatus.lowercased()
        switch s {
        case "accepted", "processed", "received": return .accepted
        case "rejected": return .rejected
        case "fr:212", "encaissée", "encaissee", "paid": return .paid
        case "fr:320", "annulée", "annulee", "cancelled": return .cancelled
        default: return nil
        }
    }

    private func refreshSuperPDPStatus() {
        guard let rid = (superPDPSubmission?.remoteID ?? invoice.superPDPRemoteID), !rid.isEmpty else { return }
        superPDPSubmitting = true
        let priorStatus = superPDPSubmission?.status
        Task {
            do {
                let service = SuperPDPService()
                let updated = try await service.getInvoiceStatus(remoteID: rid, credentials: superPDPSettings.credentials)
                superPDPSubmission = SuperPDPInvoiceSubmission(
                    id: updated.id, remoteID: updated.remoteID, status: updated.status,
                    enInvoiceRef: updated.enInvoiceRef, submittedAt: updated.submittedAt,
                    lastCheckedAt: updated.lastCheckedAt, message: updated.message, direction: .received
                )
                if let mapped = Self.mapPDPStatusToLocal(updated.status) {
                    // Ne jamais rétrograder le statut local : on n'applique le statut PDP
                    // que s'il représente un avancement dans le cycle de vie (ou une annulation).
                    let isAdvance = mapped.lifecycleRank > invoice.status.lifecycleRank
                    let isCancellation = mapped == .cancelled && invoice.status != .cancelled && invoice.status != .paid
                    if (isAdvance || isCancellation) && mapped != invoice.status {
                        syncingFromPDP = true
                        invoice.status = mapped
                        store.upsert(invoice)
                        syncingFromPDP = false
                        superPDPMessage = "⟲ Reçu de SUPER PDP : statut \(updated.status) — id distant \(rid). Statut facture mis à jour : \(mapped.label)."
                    } else if mapped == invoice.status {
                        superPDPMessage = "⟲ Reçu de SUPER PDP : statut \(updated.status)\(updated.enInvoiceRef.map { " (\($0))" } ?? "") — id distant \(rid)."
                    } else {
                        superPDPMessage = "⟲ Reçu de SUPER PDP : statut \(updated.status). Statut local « \(invoice.status.label) » conservé (supérieur dans le cycle de vie, pas de rétrogradation)."
                    }
                } else {
                    superPDPMessage = "⟲ Reçu de SUPER PDP : statut \(updated.status)\(updated.enInvoiceRef.map { " (\($0))" } ?? "") — id distant \(rid)."
                }
                store.audit?.record(
                    actor: store.actorName,
                    action: "pdp_status_received",
                    target: invoice.number,
                    details: "Statut SUPER PDP reçu : \(updated.status)\(priorStatus.map { " (avant : \($0))" } ?? "") — id distant : \(rid)",
                    objectType: .invoice,
                    objectCode: invoice.number
                )
            } catch {
                superPDPMessage = "Échec rafraîchissement : \(error.localizedDescription)"
                store.audit?.record(
                    actor: store.actorName,
                    action: "pdp_status_error",
                    target: invoice.number,
                    details: "Échec interrogation statut SUPER PDP : \(error.localizedDescription)",
                    objectType: .invoice,
                    objectCode: invoice.number
                )
            }
            superPDPSubmitting = false
        }
    }

    private func downloadPDPInvoice() {
        guard let rid = (superPDPSubmission?.remoteID ?? invoice.superPDPRemoteID), !rid.isEmpty else {
            superPDPMessage = "Aucun identifiant distant : la facture n'a pas encore été déposée sur SUPER PDP."
            return
        }
        guard superPDPSettings.credentials.isConfigured else {
            superPDPMessage = "Identifiants SUPER PDP non configurés."
            return
        }
        pdpDownloading = true
        superPDPMessage = nil
        Task {
            do {
                let service = SuperPDPService()
                let data = try await service.downloadInvoice(remoteID: rid, credentials: superPDPSettings.credentials)
                let panel = NSSavePanel()
                let isPDF = data.count > 4 && data[0] == 0x25 && data[1] == 0x50 && data[2] == 0x44 && data[3] == 0x46
                panel.allowedContentTypes = isPDF ? [.pdf] : [.xml]
                panel.nameFieldStringValue = isPDF ? "facture-\(invoice.number)-pdp.pdf" : "facture-\(invoice.number)-pdp.xml"
                if panel.runModal() == .OK, let url = panel.url {
                    try data.write(to: url)
                    superPDPMessage = "⤓ Copie déposée téléchargée : \(url.lastPathComponent)"
                    pdpDownloadedURL = url
                }
            } catch let e as SuperPDPError {
                superPDPMessage = "Échec téléchargement : \(e.localizedDescription)"
            } catch {
                superPDPMessage = "Échec téléchargement : \(error)"
            }
            pdpDownloading = false
        }
    }

    private func fetchPDPEvents() {
        guard let rid = (superPDPSubmission?.remoteID ?? invoice.superPDPRemoteID), !rid.isEmpty else {
            superPDPMessage = "Aucun identifiant distant : la facture n'a pas encore été déposée sur SUPER PDP."
            return
        }
        guard superPDPSettings.credentials.isConfigured else {
            superPDPMessage = "Identifiants SUPER PDP non configurés."
            return
        }
        pdpEventsLoading = true
        showPDPEvents = true
        Task {
            do {
                let service = SuperPDPService()
                let events = try await service.listInvoiceEvents(remoteID: rid, credentials: superPDPSettings.credentials)
                pdpEvents = events.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            } catch let e as SuperPDPError {
                superPDPMessage = "Échec historique : \(e.localizedDescription)"
                pdpEvents = []
            } catch {
                superPDPMessage = "Échec historique : \(error)"
                pdpEvents = []
            }
            pdpEventsLoading = false
        }
    }

    private func sendReminder(level: PaymentReminderLevel) {
        guard let recipient = invoice.buyer.contactEmail, !recipient.isEmpty else {
            reminderMessage = "Échec relance : aucune adresse email cliente renseignée."
            return
        }
        let credentials = smtpSettings.credentials
        guard credentials.isConfigured else {
            reminderMessage = "Échec relance : envoi d'email non configuré (Réglages)."
            return
        }
        let email = PaymentReminderComposer.compose(level: level, for: invoice)
        sendingReminder = true
        reminderMessage = nil
        Task {
            do {
                try await SMTPService().send(to: recipient, subject: email.subject, body: email.body, credentials: credentials)
                reminderMessage = "Relance « \(level.label) » envoyée à \(recipient)."
            } catch {
                reminderMessage = "Échec relance : \(error.localizedDescription)"
            }
            sendingReminder = false
        }
    }

    private func sendInvoiceEmail() {
        guard let recipient = invoice.buyer.contactEmail, !recipient.isEmpty else {
            invoiceEmailMessage = "Échec envoi : aucune adresse email cliente renseignée."
            return
        }
        let credentials = smtpSettings.credentials
        guard credentials.isConfigured else {
            invoiceEmailMessage = "Échec envoi : envoi d'email non configuré (Réglages)."
            return
        }
        let template = emailTemplateStore.template(for: .invoiceSent)
        let email = EmailComposer.compose(template: template, variables: [
            "numero": invoice.number,
            "client": invoice.buyer.name,
            "societe": invoice.seller.name,
            "montant": String(format: "%.2f %@", invoice.grandTotal, invoice.currency),
            "date": invoice.dueDate.formatted(.dateTime.day().month().year())
        ])
        sendingInvoiceEmail = true
        invoiceEmailMessage = nil
        Task {
            do {
                try await SMTPService().send(to: recipient, subject: email.subject, body: email.body, credentials: credentials)
                invoiceEmailMessage = "Facture envoyée à \(recipient)."
            } catch {
                invoiceEmailMessage = "Échec envoi : \(error.localizedDescription)"
            }
            sendingInvoiceEmail = false
        }
    }

    private func validatePDP() {
        guard superPDPSettings.credentials.isConfigured else {
            superPDPMessage = "Identifiants SUPER PDP non configurés."
            return
        }
        pdpValidating = true
        superPDPMessage = nil
        showValidation = false
        validation = nil
        let preCheck = FacturXValidator().validate(invoice: invoice)
        if !preCheck.isValid {
            validation = preCheck
            showValidation = true
            superPDPMessage = "Validation locale échouée : \(preCheck.errors.count) erreur(s). Corrigez avant la validation SUPER PDP."
            pdpValidating = false
            return
        }
        Task {
            do {
                let facturx = try FacturXGenerator().generate(invoice: invoice, logo: sellerLogo)
                let service = SuperPDPService()
                let report = try await service.validateInvoice(fileData: facturx, credentials: superPDPSettings.credentials)
                pdpValidationReport = report
                showPDPValidationPanel = true
                superPDPMessage = nil
            } catch let e as SuperPDPError {
                superPDPMessage = "Échec validation SUPER PDP : \(e.localizedDescription)"
            } catch {
                superPDPMessage = "Échec validation SUPER PDP : \(error)"
            }
            pdpValidating = false
        }
    }

    /// Alerte email best-effort (au connecté, potentiellement utile si le
    /// changement vient d'une synchronisation SUPER PDP en arrière-plan plutôt
    /// que d'un clic explicite) — n'échoue jamais la mise à jour du statut.
    private func sendInvoiceStatusAlertIfNeeded(_ newStatus: InvoiceStatus) {
        let smtp = smtpSettings.credentials
        guard smtp.alertsEnabled, smtp.alertOnInvoiceStatusChange, smtp.isConfigured,
              [.accepted, .rejected, .paid, .cancelled].contains(newStatus),
              let recipient = auth.currentUser?.username else { return }
        let invoiceNumber = invoice.number
        let label = newStatus.label
        Task {
            try? await SMTPService().send(
                to: recipient,
                subject: "Facture \(invoiceNumber) — \(label)",
                body: "La facture \(invoiceNumber) est passée au statut « \(label) ».",
                credentials: smtp
            )
        }
    }

    private func notifyPDPStatusChange(to newStatus: InvoiceStatus, force: Bool = false) {
        guard let rid = (superPDPSubmission?.remoteID ?? invoice.superPDPRemoteID), !rid.isEmpty else { return }
        guard superPDPSettings.credentials.isConfigured else { return }
        guard let statusCode = invoiceStatusStore.override(for: newStatus).reformCode, statusCode != "200" else { return }
        let detailLabel = newStatus.label
        if !force, let last = lastSentPDPStatusCode, last == statusCode {
            superPDPMessage = "Statut « \(detailLabel) » déjà envoyé à SUPER PDP (code \(statusCode)). Évite l'envoi en double."
            return
        }
        superPDPSubmitting = true
        let invoiceRef = invoice
        Task {
            do {
                let service = SuperPDPService()
                var reported: [[String: Any]]? = nil
                if newStatus == .paid {
                    reported = invoiceRef.lines.compactMap { line -> [String: Any]? in
                        let amount = (line.quantity * line.unitPrice) * (1 + line.vatRate / 100)
                        return [
                            "amount": String(format: "%.2f", amount),
                            "currency_code": invoiceRef.currency,
                            "type_code": "MEN",
                            "value_percent": String(format: "%.1f", line.vatRate),
                            "date": Self.pdpDateString(invoiceRef.issueDate)
                        ]
                    }
                }
                try await service.sendInvoiceEvent(remoteID: rid, statusCode: statusCode, credentials: superPDPSettings.credentials, reportedData: reported)
                lastSentPDPStatusCode = statusCode
                superPDPSubmission = SuperPDPInvoiceSubmission(
                    id: UUID().uuidString, remoteID: rid, status: detailLabel,
                    enInvoiceRef: superPDPSubmission?.enInvoiceRef,
                    submittedAt: Date(), lastCheckedAt: Date(),
                    message: "Statut \(detailLabel) envoyé", direction: .sent
                )
                superPDPMessage = "↑ Envoyé à SUPER PDP : statut \(detailLabel) — id distant \(rid)."
                store.audit?.record(
                    actor: store.actorName,
                    action: "pdp_status_sent",
                    target: invoiceRef.number,
                    details: "Envoi statut \(detailLabel) à SUPER PDP (envoyé) — id distant : \(rid)",
                    objectType: .invoice,
                    objectCode: invoiceRef.number
                )
            } catch let e as SuperPDPError {
                superPDPMessage = "Échec envoi statut SUPER PDP : \(e.localizedDescription)"
                store.audit?.record(
                    actor: store.actorName,
                    action: "pdp_status_send_error",
                    target: invoiceRef.number,
                    details: "Échec envoi statut \(detailLabel) à SUPER PDP : \(e.localizedDescription)",
                    objectType: .invoice,
                    objectCode: invoiceRef.number
                )
            } catch {
                superPDPMessage = "Échec envoi statut SUPER PDP : \(error)"
                store.audit?.record(
                    actor: store.actorName,
                    action: "pdp_status_send_error",
                    target: invoiceRef.number,
                    details: "Échec envoi statut \(detailLabel) à SUPER PDP : \(error)",
                    objectType: .invoice,
                    objectCode: invoiceRef.number
                )
            }
            superPDPSubmitting = false
        }
    }

    private static func pdpDateString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.string(from: date)
    }

    private func exportPlainPDF() {
        exportError = nil
        exportedURL = nil
        store.upsert(invoice)
        let data = FacturXGenerator().generateVisiblePDF(invoice: invoice, logo: sellerLogo)
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

    private var statusJournalSection: some View {
        let logs = auth.audit.entries.filter {
            $0.objectType == .invoice && ($0.objectCode ?? $0.target) == invoice.number
        }
        return DisclosureGroup(isExpanded: $showStatusJournal) {
            if logs.isEmpty {
                Text("Aucun événement enregistré pour cette facture.").font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(logs) { e in
                        HStack(alignment: .top, spacing: 8) {
                            Text(e.timestamp, format: .dateTime.day().month().year().hour().minute())
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                .frame(width: 130, alignment: .leading)
                            Text(e.actor).font(.caption).frame(width: 100, alignment: .leading)
                            if e.action == "status_change" {
                                Text("\(e.statusFrom ?? "?") → \(e.statusTo ?? "?")")
                                    .font(.caption.bold())
                                if !e.details.isEmpty {
                                    Text(e.details).font(.caption2).foregroundStyle(.secondary)
                                }
                            } else {
                                Text(e.action == "invoice_created" ? "Création" : e.action == "invoice_updated" ? "Modification" : e.action == "invoice_deleted" ? "Suppression" : e.action == "pdp_deposit_sent" ? "Dépôt PDP envoyé" : e.action == "pdp_deposit_error" ? "Dépôt PDP échoué" : e.action == "pdp_status_received" ? "Statut PDP reçu" : e.action == "pdp_status_sent" ? "Statut PDP envoyé" : e.action == "pdp_status_error" ? "Interrogation PDP échouée" : e.action == "pdp_status_send_error" ? "Envoi statut PDP échoué" : e.action)
                                    .font(.caption)
                                if !e.details.isEmpty {
                                    Text(e.details).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                    }
                }
            }
        } label: {
            Label("Journal de la facture (\(logs.count))", systemImage: "list.bullet.clipboard")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
    }

    private func validationPanel(_ v: FacturXValidationResult) -> some View {
        let ruleErrors = v.businessRules.filter { $0.severity == .error }
        let ruleWarnings = v.businessRules.filter { $0.severity == .warning }
        return GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    if v.isValid {
                        Label("Conforme", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Non conforme — \(ruleErrors.count) erreur(s)", systemImage: "xmark.seal.fill")
                            .foregroundStyle(.red)
                    }
                    Spacer()
                    Button { showValidation = false } label: {
                        Image(systemName: "xmark.circle")
                    }.buttonStyle(.plain)
                }
                if !ruleErrors.isEmpty {
                    Text("Erreurs :").font(.caption.bold())
                    ForEach(ruleErrors) { br in
                        HStack(alignment: .top, spacing: 4) {
                            Text(br.ruleId)
                                .font(.caption.bold().monospaced())
                                .foregroundStyle(.red)
                                .frame(width: 96, alignment: .leading)
                            Text(br.message)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                if !ruleWarnings.isEmpty {
                    if !ruleErrors.isEmpty { Divider().padding(.vertical, 2) }
                    Text("Avertissements :").font(.caption.bold())
                    ForEach(ruleWarnings) { br in
                        HStack(alignment: .top, spacing: 4) {
                            Text(br.ruleId)
                                .font(.caption.bold().monospaced())
                                .foregroundStyle(.orange)
                                .frame(width: 96, alignment: .leading)
                            Text(br.message)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func pdpValidationPanel(_ report: SuperPDPValidationReport) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    if report.isValid {
                        Label("Validation SUPER PDP conforme", systemImage: "checkmark.shield.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Validation SUPER PDP non conforme — \(report.errors.count) erreur(s)", systemImage: "xmark.shield.fill")
                            .foregroundStyle(.red)
                    }
                    Spacer()
                    Button { showPDPValidationPanel = false } label: {
                        Image(systemName: "xmark.circle")
                    }.buttonStyle(.plain)
                }
                if !report.errors.isEmpty {
                    Text("Erreurs :").font(.caption.bold())
                    ForEach(report.errors, id: \.self) { msg in
                        HStack(alignment: .top, spacing: 4) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.red)
                            Text(msg)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                if !report.warnings.isEmpty {
                    if !report.errors.isEmpty { Divider().padding(.vertical, 2) }
                    Text("Avertissements :").font(.caption.bold())
                    ForEach(report.warnings, id: \.self) { msg in
                        HStack(alignment: .top, spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                            Text(msg)
                                .font(.caption)
                                .foregroundStyle(.orange)
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
        var defaultKind: DirectoryEntryKind { self == .seller ? .societe : .client }
    }

    @Binding var party: InvoiceParty
    let role: Role
    var onPartyPicked: ((InvoiceParty) -> Void)? = nil
    var locked: Bool = false
    @EnvironmentObject var directory: PartyDirectory
    @EnvironmentObject var superPDPSettings: SuperPDPSettings
    @State private var showPicker = false
    @State private var showSaveSheet = false
    @State private var showSuperPDPSearch = false
    @State private var showFrenchDirectorySearch = false
    @State private var saveName = ""
    @State private var pendingEntry: DirectoryEntry?
    @State private var duplicateMatches: [PartyDirectory.DuplicateMatch]?
    @State private var lookingUpElectronicAddress = false
    @State private var electronicAddressLookupNote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !locked {
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
                    if role == .buyer {
                        Button {
                            showSuperPDPSearch = true
                        } label: {
                            Label("SUPER PDP", systemImage: "paperplane")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!superPDPSettings.credentials.isConfigured)
                        .help("Rechercher un destinataire dans l'annuaire SUPER PDP")
                        Button {
                            showFrenchDirectorySearch = true
                        } label: {
                            Label("Annuaire FR", systemImage: "building.2")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!superPDPSettings.credentials.isConfigured)
                        .help("Rechercher une entreprise dans l'annuaire français (SIREN, adresse Peppol)")
                    }
                    Spacer()
                }
            }

            PartyEditorView(party: $party, isSociete: role == .seller, locked: locked, directory: directory, onPickContact: { updatePartyFromContact($0) }, onPickRouting: { updatePartyFromRouting($0) }, onPartyPicked: { p in onPartyPicked?(p) })
        }
        .padding(8)
        .sheet(isPresented: $showSuperPDPSearch) {
            SuperPDPSearchSheet(initialQuery: party.siren ?? party.siret ?? party.name) { picked in
                party = picked
                onPartyPicked?(picked)
            }
        }
        .sheet(isPresented: $showFrenchDirectorySearch) {
            SuperPDPFrenchDirectorySheet { picked in
                party = picked
                onPartyPicked?(picked)
            }
        }
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
                if role == .buyer, superPDPSettings.credentials.isConfigured {
                    if lookingUpElectronicAddress {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Recherche de l'adresse électronique sur SUPER PDP…")
                        }.font(.caption).foregroundStyle(.secondary)
                    } else if let note = electronicAddressLookupNote {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button("Annuler") { showSaveSheet = false }
                        .keyboardShortcut(.cancelAction)
                    Button("Enregistrer") {
                        saveToDirectory()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(lookingUpElectronicAddress)
                }
            }.padding(20).frame(minWidth: 360)
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

    private func saveToDirectory() {
        var p = party
        p.name = saveName.trimmingCharacters(in: .whitespaces).isEmpty ? party.name : saveName
        let siren = (p.siren ?? "").filter { $0.isNumber }
        let siret = (p.siret ?? "").filter { $0.isNumber }
        let currentEndpoint = (p.endpointID ?? "").trimmingCharacters(in: .whitespaces)
        // La recherche DINUM (SireneResult.merged) préremplit endpointID avec le
        // SIREN brut comme repli quand rien n'est renseigné : ce n'est pas une
        // vraie adresse électronique, donc on ne doit pas s'arrêter là.
        let isPlaceholderSirenFallback = !siren.isEmpty && currentEndpoint == siren
        let hasRealElectronicAddress = !currentEndpoint.isEmpty && !isPlaceholderSirenFallback
        guard role == .buyer, superPDPSettings.credentials.isConfigured, !hasRealElectronicAddress,
              (siren.count == 9 || siret.count == 14) else {
            finishSaveToDirectory(p)
            return
        }
        lookingUpElectronicAddress = true
        electronicAddressLookupNote = nil
        let query = siret.count == 14 ? siret : siren
        Task {
            do {
                let results = try await SuperPDPService().searchRecipient(siretOrSiren: query, credentials: superPDPSettings.credentials)
                if let match = results.first(where: { ($0.routingAddress ?? "").trimmingCharacters(in: .whitespaces).isEmpty == false }) {
                    p.endpointID = match.routingAddress
                    p.endpointSchemeID = match.routingScheme?.trimmingCharacters(in: .whitespaces).isEmpty == false ? match.routingScheme! : "0225"
                    electronicAddressLookupNote = "Adresse électronique trouvée sur SUPER PDP."
                } else {
                    electronicAddressLookupNote = "Aucune adresse électronique trouvée sur SUPER PDP pour ce SIREN/SIRET."
                }
            } catch {
                electronicAddressLookupNote = "Recherche SUPER PDP indisponible : \(error.localizedDescription)"
            }
            lookingUpElectronicAddress = false
            finishSaveToDirectory(p)
        }
    }

    private func finishSaveToDirectory(_ p: InvoiceParty) {
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
        var active = directory.entries.filter {
            !$0.isArchived && (role == .seller ? $0.kind == .societe : ($0.kind == .client || $0.kind == .both))
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

enum DirectoryKindFilter: String, CaseIterable, Hashable {
    case all = "Tous"
    case clients = "Clients"
    case fournisseurs = "Fournisseurs"

    func matches(_ kind: DirectoryEntryKind) -> Bool {
        switch self {
        case .all: return kind != .societe
        case .clients: return kind == .client || kind == .both
        case .fournisseurs: return kind == .fournisseur || kind == .both
        }
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
    @State private var kindFilter: DirectoryKindFilter = .all

    private var canManageSocietes: Bool { auth.currentUser?.isAdmin == true }

    var filtered: [DirectoryEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var base = directory.entries.filter { showArchived || !$0.isArchived }
        base = base.filter { kindFilter.matches($0.kind) }
        guard q.isEmpty else {
            return base.filter {
                $0.displayName.lowercased().contains(q)
                    || ($0.party.siren ?? "").lowercased().contains(q)
                    || ($0.party.siret ?? "").lowercased().contains(q)
                    || ($0.party.vatNumber ?? "").lowercased().contains(q)
                    || $0.party.city.lowercased().contains(q)
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        }
        return base.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
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
                    Picker("Type", selection: $kindFilter) {
                        ForEach(DirectoryKindFilter.allCases, id: \.self) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
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
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.clear))
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
                            if let sn = entry.party.siren?.trimmingCharacters(in: .whitespaces), !sn.isEmpty,
                               !SireneValidator.isValidSiren(sn) {
                                Label("SIREN invalide", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(Color.orange.opacity(0.2), in: Capsule())
                                    .foregroundColor(.orange)
                            }
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
                                Text("Modification non autorisée")
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
        if entry.kind == .societe { return canManageSocietes }
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
                        HStack {
                            Text("Statut").font(.headline)
                            Spacer()
                            if entry.isArchived {
                                Label("Tiers archivé", systemImage: "archivebox")
                                    .font(.callout.bold()).foregroundStyle(.orange)
                            } else {
                                Label("Tiers actif", systemImage: "checkmark.circle")
                                    .font(.callout.bold()).foregroundStyle(.green)
                            }
                        }
                        Divider()
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

                        HStack(alignment: .top, spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Identifiants").font(.headline)
                                if let s = entry.party.siren, !s.isEmpty {
                                    HStack(alignment: .top) {
                                        Text("SIREN").font(.callout.bold()).frame(width: 140, alignment: .leading)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(s).font(.body)
                                            if SireneValidator.isValidSiren(s) {
                                                Label("SIREN valide (clé Luhn correcte)", systemImage: "checkmark.circle.fill")
                                                    .font(.caption2).foregroundStyle(.green)
                                            } else {
                                                Label("SIREN invalide (9 chiffres attendus, clé Luhn incorrecte)", systemImage: "exclamationmark.triangle.fill")
                                                    .font(.caption2).foregroundStyle(.orange)
                                            }
                                        }
                                        Spacer()
                                    }
                                }
                                if let st = entry.party.siret, !st.isEmpty {
                                    HStack(alignment: .top) {
                                        Text("SIRET").font(.callout.bold()).frame(width: 140, alignment: .leading)
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
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Divider()
                            VStack(alignment: .leading, spacing: 6) {
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
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Divider()
                        if entry.kind != .client {
                            Text("Coordonnées bancaires").font(.headline)
                        if let iban = entry.party.iban?.trimmingCharacters(in: .whitespaces), !iban.isEmpty {
                            HStack(alignment: .top) {
                                Text("IBAN").font(.callout.bold()).frame(width: 160, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(IBANValidator.formatted(iban)).font(.system(.body, design: .monospaced))
                                    if IBANValidator.isValid(iban) {
                                        Label("IBAN valide (clé mod 97 correcte)", systemImage: "checkmark.circle.fill")
                                            .font(.caption2).foregroundStyle(.green)
                                    } else {
                                        Label("IBAN invalide (clé de contrôle incorrecte)", systemImage: "exclamationmark.triangle.fill")
                                            .font(.caption2).foregroundStyle(.orange)
                                    }
                                }
                                Spacer()
                            }
                        }
                        if let bic = entry.party.bic?.trimmingCharacters(in: .whitespaces), !bic.isEmpty {
                            detailRow("BIC", bic)
                        }
                        if let pt = entry.party.paymentTerms?.trimmingCharacters(in: .whitespaces), !pt.isEmpty {
                            detailRow("Conditions de paiement", pt)
                        }
                        if (entry.party.iban?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
                            && (entry.party.bic?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
                            && (entry.party.paymentTerms?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) {
                            Text("Aucune coordonnée bancaire renseignée.").font(.caption).foregroundStyle(.secondary)
                        }
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
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.clear))
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

                        if entry.kind != .fournisseur {
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
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.clear))
                        }
                        }

                        if let note = entry.note, !note.isEmpty {
                            Divider()
                            Text("Note").font(.headline)
                            Text(note).font(.callout).foregroundStyle(.secondary)
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

    private var canManageSocietes: Bool { auth.currentUser?.isAdmin == true }

    private var availableKinds: [DirectoryEntryKind] {
        if canManageSocietes { return DirectoryEntryKind.allCases }
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
            .disabled(!canManageSocietes && entry.kind == .societe)

            if entry.kind == .client {
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
                PartyEditorView(party: $entry.party, routingAddresses: $entry.routingAddresses, contacts: $entry.contacts, isSociete: entry.kind == .societe, hideBankDetails: entry.kind == .client, hideElectronicAddress: entry.kind == .fournisseur)
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

struct CapsuleToggleButton: View {
    let title: String
    @Binding var isOn: Bool
    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "checkmark" : "")
                    .font(.caption.weight(.bold))
                    .frame(width: 12)
                Text(title)
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(isOn ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                Capsule().stroke(isOn ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: 1)
            )
            .foregroundStyle(isOn ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
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
            HStack(spacing: 10) {
                CapsuleToggleButton(title: "Contact actif", isOn: $draft.isActive)
                CapsuleToggleButton(title: "Contact par défaut", isOn: $draft.isDefault)
                Spacer()
            }
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
                        HStack(spacing: 8) {
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
                            Button {
                                editing = ct
                                showEditor = true
                            } label: { Image(systemName: "pencil") }
                                .buttonStyle(.borderless)
                                .help("Modifier ce contact")
                        }
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

    private struct TabItem { let index: Int; let label: String; let icon: String }

    /// Un `Picker` en style segmenté n'affiche pas fiablement l'icône d'un `Label` sur
    /// macOS (texte seul par segment) — même limitation que celle qui a motivé le
    /// remplacement de la barre de navigation principale par de vrais boutons. Mêmes
    /// boutons ici plutôt que de refaire la même erreur.
    private var tabs: [TabItem] {
        var items = [TabItem(index: 0, label: "Profil", icon: "person.crop.circle")]
        if auth.currentUser?.isAdmin == true {
            items.append(contentsOf: [
                TabItem(index: 1, label: "Tables", icon: "tablecells"),
                TabItem(index: 2, label: "Application", icon: "gearshape.2"),
                TabItem(index: 3, label: "Journal", icon: "clock.arrow.circlepath"),
                TabItem(index: 4, label: "Données", icon: "externaldrive.fill")
            ])
        }
        return items
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(tabs, id: \.index) { tab in
                    settingsTabButton(tab)
                }
                Spacer()
            }
            .padding(10)
            Divider()
            switch settingsTab {
            case 0:
                ProfileSettingsView()
            case 1:
                ValueTablesView()
            case 3:
                AuditLogView()
            case 4:
                DataAdminView()
            default:
                ApplicationSettingsView()
            }
        }
    }

    private func settingsTabButton(_ tab: TabItem) -> some View {
        let isSelected = settingsTab == tab.index
        return Button {
            settingsTab = tab.index
        } label: {
            Label(tab.label, systemImage: tab.icon)
                .font(.callout.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
    }
}

struct SocietiesAdminView: View {
    @Binding var editingEntry: DirectoryEntry?
    @Binding var creatingNew: Bool
    @EnvironmentObject var directory: PartyDirectory
    @State private var query = ""
    @State private var selectedID: UUID?
    @State private var editingLogoEntry: DirectoryEntry?

    private var societies: [DirectoryEntry] {
        directory.entries.filter { $0.kind == .societe }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var filtered: [DirectoryEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return societies }
        return societies.filter {
            $0.displayName.lowercased().contains(q)
                || ($0.party.siren ?? "").lowercased().contains(q)
                || ($0.party.siret ?? "").lowercased().contains(q)
                || ($0.party.vatNumber ?? "").lowercased().contains(q)
                || $0.party.city.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    creatingNew = true
                } label: { Label("Nouvelle société", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
                Spacer()
                Text("\(societies.count) société(s) — \(societies.filter { !$0.isArchived }.count) active(s)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Les sociétés sont les entités émettrices de l'application. Elles définissent le périmètre des utilisateurs et l'émetteur des factures. Elles ne sont pas affichées dans l'onglet Annuaire.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Rechercher une société", text: $query)
                    .textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.clear))

            if filtered.isEmpty {
                Text("Aucune société. Cliquez sur « Nouvelle société ».")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            } else {
                Table(filtered, selection: Binding(
                    get: { selectedID },
                    set: { selectedID = $0 }
                )) {
                    TableColumn("Nom") { e in
                        HStack(spacing: 6) {
                            Text(e.displayName)
                            if e.isArchived {
                                Text("Archive")
                                    .font(.caption2)
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(Color.orange.opacity(0.2), in: Capsule())
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    TableColumn("SIREN") { e in Text((e.party.siren ?? "").isEmpty ? "—" : e.party.siren!) }
                    TableColumn("Ville") { e in Text(e.party.city.isEmpty ? "—" : e.party.city) }
                    TableColumn("IBAN") { e in Text((e.party.iban ?? "").isEmpty ? "—" : e.party.iban!) }
                        .width(min: 120, ideal: 160)
                    TableColumn("Logo") { e in
                        Group {
                            if let data = e.logoData, let img = NSImage(data: data) {
                                Image(nsImage: img)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 36, height: 24)
                                    .background(RoundedRectangle(cornerRadius: 4).stroke(.secondary, lineWidth: 0.3))
                            } else {
                                Text("-").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .width(min: 48, ideal: 60)
                }
                .frame(minHeight: 180)
                if let id = selectedID, let entry = societies.first(where: { $0.id == id }) {
                    HStack {
                        Button {
                            editingEntry = entry
                        } label: { Label("Modifier", systemImage: "pencil") }
                            .buttonStyle(.bordered)
                        Button {
                            editingLogoEntry = entry
                        } label: { Label(entry.logoData == nil ? "Ajouter logo" : "Modifier logo", systemImage: "photo") }
                            .buttonStyle(.bordered)
                        if entry.logoData != nil {
                            Button(role: .destructive) {
                                var e = entry
                                e.logoData = nil
                                directory.upsert(e)
                            } label: { Label("Retirer logo", systemImage: "trash") }
                                .buttonStyle(.bordered)
                        }
                        Button(role: .destructive) {
                            directory.delete(entry)
                            selectedID = nil
                        } label: { Label("Supprimer", systemImage: "trash.fill") }
                            .buttonStyle(.bordered)
                        Spacer()
                        Text("Profil Factur-X : ").font(.caption)
                        Picker("Profil Factur-X", selection: Binding(
                            get: { entry.profile },
                            set: { newProfile in
                                var e = entry
                                e.profile = newProfile
                                directory.upsert(e)
                            }
                        )) {
                            ForEach(FacturXProfile.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 140)
                        .help("Profil Factur-X par défaut des factures émises par cette société (hérité à la création).")
                    }.padding(.top, 4)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $editingLogoEntry) { entry in
            PartyLogoEditor(entry: entry, isPresented: Binding(
                get: { editingLogoEntry != nil },
                set: { if !$0 { editingLogoEntry = nil } }
            ))
        }
    }
}

/// Liste des emails automatiques, présentée sur le même schéma que
/// `SocietiesAdminView` : une Table avec case d'activation en ligne, puis un
/// bouton "Modifier" qui ouvre la fiche d'édition du modèle sélectionné.
struct EmailTemplatesAdminView: View {
    @EnvironmentObject var emailTemplateStore: EmailTemplateStore
    /// String et non EmailTemplateKind : Table exige que `selection` corresponde au
    /// type de `id` (String, via EmailTemplateKind.rawValue), pas au type de la ligne.
    @State private var selectedKind: String?
    @State private var editingKind: EmailTemplateKind?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Emails envoyés automatiquement au client ou au fournisseur pour accompagner un document (devis, commande, facture) — utilise le même serveur SMTP que les alertes ci-dessus.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle(isOn: Binding(
                get: { emailTemplateStore.globalEnabled },
                set: { emailTemplateStore.globalEnabled = $0; emailTemplateStore.save() }
            )) {
                Text("Activer l'envoi de ces emails").font(.body.weight(.semibold))
            }
            .toggleStyle(.switch)
            .help("Désactivé, tous les boutons d'envoi disparaissent de l'application, quel que soit le réglage de chaque email ci-dessous.")

            if !emailTemplateStore.globalEnabled {
                Label("Tous les boutons d'envoi sont masqués tant que c'est désactivé.", systemImage: "eye.slash")
                    .font(.caption).foregroundStyle(.orange)
            } else {
                Table(EmailTemplateKind.allCases, selection: Binding(
                    get: { selectedKind },
                    set: { selectedKind = $0 }
                )) {
                    TableColumn("Email") { kind in
                        Label(kind.label, systemImage: kind.systemImage)
                    }
                    TableColumn("Activé") { kind in
                        Toggle("", isOn: Binding(
                            get: { emailTemplateStore.template(for: kind).enabled },
                            set: { newValue in
                                var t = emailTemplateStore.template(for: kind)
                                t.enabled = newValue
                                emailTemplateStore.upsert(t)
                            }
                        ))
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                    }
                    .width(60)
                    TableColumn("Sujet") { kind in
                        Text(kind.hasEditableContent ? emailTemplateStore.template(for: kind).subject : "3 modèles selon le niveau d'urgence")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .frame(minHeight: 160)

                if let kind = selectedKind.flatMap(EmailTemplateKind.init(rawValue:)) {
                    HStack {
                        if kind.hasEditableContent {
                            Button {
                                editingKind = kind
                            } label: { Label("Modifier", systemImage: "pencil") }
                                .buttonStyle(.bordered)
                        } else {
                            Text("La relance utilise 3 modèles distincts selon le niveau d'urgence (rappel amical, mise en demeure, majoration légale) — seule l'activation se règle ici, le contenu n'est pas modifiable.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.top, 4)
                }
            }
        }
        .sheet(item: $editingKind) { kind in
            EmailTemplateEditorSheet(kind: kind)
        }
    }
}

/// Édition du sujet/corps d'un email automatique. Les champs disponibles
/// ({{numero}}, {{client}}…) sont insérables par un clic — pas besoin de
/// connaître/taper la syntaxe des balises — plutôt qu'un champ de texte libre
/// qui suppose que l'utilisateur connaît déjà les noms de variables.
struct EmailTemplateEditorSheet: View {
    let kind: EmailTemplateKind
    @EnvironmentObject var emailTemplateStore: EmailTemplateStore
    @Environment(\.dismiss) private var dismiss
    @State private var subject = ""
    @State private var emailBody = ""

    private enum Field: Hashable { case subject, body }
    @FocusState private var focusedField: Field?

    private static let availableFields: [(tag: String, label: String)] = [
        ("numero", "Numéro"),
        ("client", "Client"),
        ("societe", "Société"),
        ("montant", "Montant"),
        ("date", "Date")
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(kind.label, systemImage: kind.systemImage).font(.title3.bold())
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Sujet").font(.caption.bold())
                    TextField("Sujet", text: $subject)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .subject)
                    Text("Corps").font(.caption.bold())
                    TextEditor(text: $emailBody)
                        .frame(height: 220)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
                        .focused($focusedField, equals: .body)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Insérer un champ (dans le sujet ou le corps, selon celui sélectionné) :")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            ForEach(Self.availableFields, id: \.tag) { field in
                                Button {
                                    insert(tag: field.tag)
                                } label: {
                                    Text(field.label).font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }
                .padding()
            }
            Divider()
            HStack {
                Spacer()
                Button("Enregistrer") {
                    var t = emailTemplateStore.template(for: kind)
                    t.subject = subject
                    t.body = emailBody
                    emailTemplateStore.upsert(t)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 560, height: 520)
        .onAppear {
            let t = emailTemplateStore.template(for: kind)
            subject = t.subject
            emailBody = t.body
        }
    }

    private func insert(tag: String) {
        let placeholder = "{{\(tag)}}"
        switch focusedField {
        case .subject: subject += placeholder
        case .body, .none: emailBody += placeholder
        }
    }
}

struct ApplicationSettingsView: View {
    @EnvironmentObject var chorusSettings: ChorusProSettings
    @EnvironmentObject var superPDPSettings: SuperPDPSettings
    @EnvironmentObject var smtpSettings: SMTPSettings
    @EnvironmentObject var emailTemplateStore: EmailTemplateStore
    @EnvironmentObject var twoFactorSettings: TwoFactorSettings
    @EnvironmentObject var moduleStore: ModuleStore
    @EnvironmentObject var appEnv: AppEnvironment
    @EnvironmentObject var store: InvoiceStore
    @EnvironmentObject var tagStore: TagStore
    @EnvironmentObject var kindColors: KindColorStore
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var directory: PartyDirectory
    @State private var twoFactorExpanded = false
    @State private var testMessage: String?
    @State private var testing = false
    @State private var superPDPTestMessage: String?
    @State private var superPDPTesting = false
    @State private var pdpSessionMessage: String?
    @State private var pdpSessionChecking = false
    @State private var envExpanded = true
    @State private var modulesExpanded = false
    @State private var emailTemplatesExpanded = false
    @State private var societiesExpanded = false
    @State private var dinumExpanded = false
    @State private var pisteExpanded = false
    @State private var superPDPExpanded = false
    @State private var smtpExpanded = false
    @State private var pcloudExpanded = false
    @State private var smtpTestMessage: String?
    @State private var smtpTesting = false
    @State private var tagsExpanded = false
    @State private var numberingExpanded = false
    @State private var numberingCompanyID: UUID?
    @State private var editingSociety: DirectoryEntry?
    @State private var creatingSociety = false
    @State private var newTagName = ""
    @State private var newTagHex = "555555"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Toutes les catégories ci-dessous, en revue guidée pas à pas :", systemImage: "checklist")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        NotificationCenter.default.post(name: .fullSettingsWizardRequested, object: nil)
                    } label: { Label("Relancer l'assistant complet", systemImage: "checklist") }
                        .buttonStyle(.bordered)
                }
                DisclosureGroup(isExpanded: $envExpanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: appEnv.isTest ? "flask" : "checkmark.seal.fill")
                                .foregroundStyle(appEnv.isTest ? .orange : .green)
                            Text("Environnement actif : \(appEnv.mode.label)")
                                .font(.headline)
                            Spacer()
                        }
                        Text("Bascule entre données de test et de production. Chaque environnement a ses propres factures, commandes, tiers, utilisateurs, journal d'audit et identifiants SUPER PDP.")
                            .font(.caption).foregroundStyle(.secondary)
                        Picker("Environnement", selection: Binding(
                            get: { appEnv.mode },
                            set: { newMode in appEnv.setMode(newMode) }
                        )) {
                            ForEach(AppEnvironmentMode.allCases, id: \.self) { m in
                                Text(m.label).tag(m)
                            }
                        }
                        .pickerStyle(.segmented)
                        if appEnv.isTest {
                            Label("Mode bac à sable : les données et identifiants sont isolés de la production.", systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }.padding(8)
                } label: {
                    Label("Environnement", systemImage: appEnv.isTest ? "flask" : "checkmark.seal.fill")
                        .font(.headline)
                }

                DisclosureGroup(isExpanded: $modulesExpanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Désactive un module optionnel pour toute l'application — l'onglet correspondant disparaît, et les fonctionnalités qui en dépendent ailleurs (ex. créer une facture depuis une commande) se masquent automatiquement. Annuaire et Factures restent toujours actifs.")
                            .font(.caption).foregroundStyle(.secondary)
                        Toggle("Devis", isOn: $moduleStore.settings.quotesEnabled)
                            .toggleStyle(.switch)
                            .onChange(of: moduleStore.settings.quotesEnabled) { _ in moduleStore.save() }
                        Toggle("Ventes (commandes)", isOn: $moduleStore.settings.ordersEnabled)
                            .toggleStyle(.switch)
                            .onChange(of: moduleStore.settings.ordersEnabled) { _ in moduleStore.save() }
                    }.padding(8)
                } label: {
                    Label("Modules", systemImage: "square.grid.2x2")
                        .font(.headline)
                }

                DisclosureGroup(isExpanded: $societiesExpanded) {
                    SocietiesAdminView(
                        editingEntry: $editingSociety,
                        creatingNew: $creatingSociety
                    )
                } label: {
                    Label("Sociétés du périmètre", systemImage: "building.2.fill")
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

                DisclosureGroup(isExpanded: $superPDPExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SUPER PDP est une Plateforme Agréée (PA) API-first pour envoyer et recevoir des factures électroniques conformes (Factur-X/UBL) et consulter l'annuaire des destinataires.")
                            .font(.caption).foregroundStyle(.secondary)
                        Toggle(isOn: $superPDPSettings.credentials.usePDP) {
                            Text("Utiliser PDP").font(.body.weight(.semibold))
                        }
                        .toggleStyle(.switch)
                        .onChange(of: superPDPSettings.credentials.usePDP) { _ in superPDPSettings.save() }
                        .help("Active les fonctions de dépôt et validation des factures via SUPER PDP. Si désactivé, seul le bouton « Valider » reste disponible sur la facture.")
                        if superPDPSettings.credentials.usePDP {
                        HStack {
                            Text("Client ID").frame(width: 100, alignment: .leading)
                            TextField("Client ID", text: $superPDPSettings.credentials.clientID)
                        }
                        HStack {
                            Text("Client Secret").frame(width: 100, alignment: .leading)
                            SecureField("Client Secret", text: $superPDPSettings.credentials.clientSecret)
                        }
                        HStack {
                            Text("Base API").frame(width: 100, alignment: .leading)
                            TextField("https://api.superpdp.tech", text: $superPDPSettings.credentials.apiBaseURL)
                        }
                        HStack {
                            Text("Mode SUPER PDP").font(.caption.bold())
                            Spacer()
                            Text(appEnv.isTest ? "TEST (bac à sable)" : "PRODUCTION")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 6).fill(appEnv.isTest ? Color.orange : Color.green))
                                .help("Les identifiants SUPER PDP sont isolés par environnement (test/production).")
                        }
                        HStack {
                            Button {
                                superPDPSettings.save()
                            } label: { Label("Enregistrer", systemImage: "checkmark.circle") }
                                .buttonStyle(.borderedProminent)
                            Button {
                                superPDPTesting = true
                                superPDPTestMessage = nil
                                Task {
                                    do {
                                        let service = SuperPDPService()
                                        let company = try await service.getCompany(credentials: superPDPSettings.credentials)
                                        superPDPTestMessage = "Connexion réussie — \(company.formalName ?? "société") (env : \(company.env ?? "?"))"
                                    } catch {
                                        superPDPTestMessage = "Échec : \(error.localizedDescription)"
                                    }
                                    superPDPTesting = false
                                }
                            } label: { Label("Tester la connexion", systemImage: "antenna.radiowaves.left.and.right") }
                                .buttonStyle(.bordered)
                                .disabled(superPDPTesting || !superPDPSettings.credentials.isConfigured)
                            Button {
                                pdpSessionChecking = true
                                pdpSessionMessage = nil
                                Task {
                                    do {
                                        let service = SuperPDPService()
                                        let session = try await service.getSession(credentials: superPDPSettings.credentials)
                                        if session.isAuthorized {
                                            pdpSessionMessage = "Session autorisée — statut : \(session.status)\(session.companyNumber.map { " (société \($0))" } ?? "")."
                                        } else {
                                            pdpSessionMessage = "Session non autorisée — statut : \(session.status). La relation utilisateur↔entreprise n'est pas encore vérifiée (les requêtes protégées renverront 403)."
                                        }
                                    } catch {
                                        pdpSessionMessage = "Échec vérification session : \(error.localizedDescription)"
                                    }
                                    pdpSessionChecking = false
                                }
                            } label: {
                                if pdpSessionChecking {
                                    HStack(spacing: 4) { ProgressView().controlSize(.small); Text("Session…") }
                                } else {
                                    Label("Vérifier la session", systemImage: "checkmark.shield.fill")
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(pdpSessionChecking || !superPDPSettings.credentials.isConfigured)
                            .help("Vérifier l'autorisation de la session OAuth (diagnostic des erreurs 403)")
                            Spacer()
                        }
                        if let m = superPDPTestMessage {
                            Text(m).font(.caption).foregroundStyle(m.hasPrefix("Échec") ? .red : .green)
                        }
                        if let m = pdpSessionMessage {
                            Text(m).font(.caption).foregroundStyle(m.hasPrefix("Échec") || m.contains("non autoris") ? .orange : .green)
                        }
                        } // fin if usePDP
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Endpoint OAuth : https://api.superpdp.tech/oauth2/token").font(.caption2).foregroundStyle(.tertiary)
                            Text("API : https://api.superpdp.tech/v1.beta/…").font(.caption2).foregroundStyle(.tertiary)
                            Text("Créez une application par entreprise sur superpdp.tech pour obtenir client_id et client_secret.").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }.padding(8)
                } label: {
                    Label("SUPER PDP (dépôt + annuaire)", systemImage: "paperplane.circle")
                        .font(.headline)
                }

                DisclosureGroup(isExpanded: $smtpExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Envoie des alertes par email (nouvel utilisateur, changement de statut de facture) via votre propre serveur SMTP. Seul le TLS implicite (port 465) est supporté ; STARTTLS (587) ne l'est pas.")
                            .font(.caption).foregroundStyle(.secondary)
                        Toggle(isOn: $smtpSettings.credentials.alertsEnabled) {
                            Text("Activer les alertes email").font(.body.weight(.semibold))
                        }
                        .toggleStyle(.switch)
                        .onChange(of: smtpSettings.credentials.alertsEnabled) { _ in smtpSettings.save() }
                        if smtpSettings.credentials.alertsEnabled {
                            HStack {
                                Text("Serveur").frame(width: 100, alignment: .leading)
                                TextField("smtp.exemple.fr", text: $smtpSettings.credentials.host)
                                Text("Port").foregroundStyle(.secondary)
                                TextField("465", value: $smtpSettings.credentials.port, format: .number)
                                    .frame(width: 70)
                            }
                            Toggle("TLS implicite (recommandé, port 465)", isOn: $smtpSettings.credentials.useTLS)
                                .toggleStyle(.checkbox)
                            HStack {
                                Text("Utilisateur").frame(width: 100, alignment: .leading)
                                TextField("Identifiant SMTP", text: $smtpSettings.credentials.username)
                            }
                            HStack {
                                Text("Mot de passe").frame(width: 100, alignment: .leading)
                                SecureField("Mot de passe SMTP", text: $smtpSettings.credentials.password)
                            }
                            HStack {
                                Text("Expéditeur").frame(width: 100, alignment: .leading)
                                TextField("alertes@votre-domaine.fr", text: $smtpSettings.credentials.fromAddress)
                                TextField("Nom affiché", text: $smtpSettings.credentials.fromName).frame(width: 160)
                            }
                            Divider()
                            Text("Déclencheurs").font(.caption.bold())
                            Toggle("Nouvel utilisateur créé", isOn: $smtpSettings.credentials.alertOnNewUser)
                                .toggleStyle(.checkbox)
                            Toggle("Changement de statut de facture (Acceptée/Rejetée/Payée/Annulée)", isOn: $smtpSettings.credentials.alertOnInvoiceStatusChange)
                                .toggleStyle(.checkbox)
                            HStack {
                                Button {
                                    smtpSettings.save()
                                } label: { Label("Enregistrer", systemImage: "checkmark.circle") }
                                    .buttonStyle(.borderedProminent)
                                Button {
                                    smtpTesting = true
                                    smtpTestMessage = nil
                                    let recipient = auth.currentUser?.username ?? smtpSettings.credentials.fromAddress
                                    Task {
                                        do {
                                            try await SMTPService().send(
                                                to: recipient,
                                                subject: "Test SMTP — Factur-X",
                                                body: "Ceci est un email de test envoyé depuis les Réglages de Factur-X.",
                                                credentials: smtpSettings.credentials
                                            )
                                            smtpTestMessage = "Email de test envoyé à \(recipient)."
                                        } catch {
                                            smtpTestMessage = "Échec : \(error.localizedDescription)"
                                        }
                                        smtpTesting = false
                                    }
                                } label: {
                                    if smtpTesting {
                                        HStack(spacing: 4) { ProgressView().controlSize(.small); Text("Envoi…") }
                                    } else {
                                        Label("Envoyer un test", systemImage: "paperplane")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(smtpTesting || !smtpSettings.credentials.isConfigured)
                                Spacer()
                            }
                            if let m = smtpTestMessage {
                                Text(m).font(.caption).foregroundStyle(m.hasPrefix("Échec") ? .red : .green)
                            }
                        }
                    }.padding(8)
                } label: {
                    Label("Alertes email (SMTP)", systemImage: "envelope.badge")
                        .font(.headline)
                }

                DisclosureGroup(isExpanded: $emailTemplatesExpanded) {
                    EmailTemplatesAdminView()
                        .padding(8)
                } label: {
                    Label("Emails automatiques (devis, commande, facture)", systemImage: "paperplane.fill")
                        .font(.headline)
                }

                DisclosureGroup(isExpanded: $twoFactorExpanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Active la possibilité, pour chaque utilisateur, d'activer la double authentification (application TOTP — Google Authenticator, Authy…) sur son propre profil (onglet Profil). Ce réglage est global à l'application ; désactivé, aucun utilisateur ne peut activer ni utiliser la 2FA, même s'il l'avait configurée auparavant.")
                            .font(.caption).foregroundStyle(.secondary)
                        Toggle("Autoriser la double authentification (2FA)", isOn: Binding(
                            get: { twoFactorSettings.enabledSolutionWide },
                            set: { twoFactorSettings.enabledSolutionWide = $0; twoFactorSettings.save() }
                        ))
                        .toggleStyle(.switch)
                    }.padding(8)
                } label: {
                    Label("Sécurité — Double authentification", systemImage: "lock.shield")
                        .font(.headline)
                }

                DisclosureGroup(isExpanded: $pcloudExpanded) {
                    CloudBackupSettingsView()
                        .padding(8)
                } label: {
                    Label("Sauvegarde cloud (pCloud)", systemImage: "icloud.and.arrow.up")
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
                        Text("Personnalisez le format des numéros de facture. Le chrono s'incrémente automatiquement à chaque création et démarre au numéro de début défini. Le compteur est toujours indépendant par société émettrice ; le format (préfixe, année, séparateur) peut l'être aussi si une société a besoin d'une numérotation différente — sinon toutes les sociétés partagent le format par défaut.")
                            .font(.caption).foregroundStyle(.secondary)
                        let societies = auth.visibleSocieties(for: auth.currentUser)
                        if !societies.isEmpty {
                            Picker("Société", selection: $numberingCompanyID) {
                                Text("Toutes (format par défaut)").tag(UUID?.none)
                                ForEach(societies) { c in
                                    Text(c.displayName).tag(UUID?.some(c.id))
                                }
                            }
                            if let cid = numberingCompanyID {
                                if store.numberFormatOverrides[cid] == nil {
                                    HStack(spacing: 6) {
                                        Text("Utilise actuellement le format par défaut.").font(.caption2).foregroundStyle(.secondary)
                                        Button("Personnaliser pour cette société") {
                                            store.numberFormatOverrides[cid] = store.numberingFormat(for: nil)
                                            store.save()
                                        }.buttonStyle(.link).font(.caption2)
                                    }
                                } else {
                                    Button("Revenir au format par défaut", role: .destructive) {
                                        store.numberFormatOverrides.removeValue(forKey: cid)
                                        store.save()
                                    }.buttonStyle(.link).font(.caption2)
                                }
                            }
                        }
                        HStack {
                            Text("Préfixe texte").font(.caption)
                            TextField("ex. FAC", text: activeNumberingFormatBinding.prefix)
                                .frame(width: 140)
                        }
                        Toggle("Inclure l'année", isOn: activeNumberingFormatBinding.includeYear)
                        HStack {
                            Text("Numéro de début").font(.caption)
                            Stepper(value: activeNumberingFormatBinding.start, in: 1...999999) {
                                Text("\(activeNumberingFormatBinding.wrappedValue.start)")
                            }
                        }
                        Toggle("Séparer par un \"-\"", isOn: activeNumberingFormatBinding.useSeparator)
                        Divider()
                        HStack {
                            Text("Aperçu : ").font(.caption).foregroundStyle(.secondary)
                            Text(store.previewNextNumber(companyID: numberingCompanyID ?? previewCompanyID())).monospaced().font(.caption.bold())
                            Spacer()
                        }
                    }.padding(8)
                } label: {
                    Label("Numérotation des factures", systemImage: "number")
                        .font(.headline)
                }

                Divider()
                HStack {
                    Text("Facture_elec v\(AppVersion.current) — © 2026 \(AppVersion.copyrightHolder) — \(AppVersion.licenseName)")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Link(destination: AppVersion.repositoryURL) {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                            Text("GitHub")
                        }
                    }.font(.caption.weight(.semibold))
                }

                Spacer()
            }.padding()
        }
        .sheet(item: $editingSociety) { entry in
            DirectoryEditorView(entry: entry, onSave: { updated in
                directory.upsert(updated)
                editingSociety = nil
            }, onDelete: { toDelete in
                directory.delete(toDelete)
                editingSociety = nil
            })
        }
        .sheet(isPresented: $creatingSociety) {
            DirectoryEditorView(initialKind: .societe) { newEntry in
                directory.upsert(newEntry)
                creatingSociety = false
            }
        }
    }

    private func previewCompanyID() -> UUID? {
        let visible = auth.visibleSocieties(for: auth.currentUser)
        if visible.count == 1 { return visible.first?.id }
        return nil
    }


    /// Le format en cours d'édition : celui de la société sélectionnée (créé à la volée à
    /// partir du défaut si elle n'a pas encore de réglage propre), ou le format par défaut
    /// si "Toutes" est sélectionné. Écrire dedans met à jour la bonne cible chez `store`.
    private var activeNumberingFormatBinding: Binding<InvoiceNumberingFormat> {
        Binding(
            get: {
                guard let cid = numberingCompanyID else { return store.numberingFormat(for: nil) }
                return store.numberFormatOverrides[cid] ?? store.numberingFormat(for: nil)
            },
            set: { newValue in
                if let cid = numberingCompanyID {
                    store.numberFormatOverrides[cid] = newValue
                } else {
                    store.numberPrefix = newValue.prefix
                    store.numberIncludeYear = newValue.includeYear
                    store.numberStart = newValue.start
                    store.numberUseSeparator = newValue.useSeparator
                }
                store.save()
            }
        )
    }
}

// MARK: - Tables de valeurs paramétrées

extension DirectoryEntryKind: Identifiable {
    public var id: String { rawValue }
}

enum ValueTable: String, CaseIterable, Identifiable {
    case invoiceStatuses
    case orderStatuses
    case quoteStatuses
    case paymentTerms
    case tags
    case kindColors
    case currencies
    case units
    case countries
    case endpointSchemes

    var id: String { rawValue }

    var label: String {
        switch self {
        case .invoiceStatuses: return "Statuts des factures"
        case .orderStatuses: return "Statuts des commandes"
        case .quoteStatuses: return "Statuts des devis"
        case .paymentTerms: return "Conditions de paiement"
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
        case .invoiceStatuses: return "doc.text.fill"
        case .orderStatuses: return "list.bullet.rectangle"
        case .quoteStatuses: return "doc.text.below.ecg"
        case .paymentTerms: return "banknote"
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
        case .invoiceStatuses, .orderStatuses, .quoteStatuses, .paymentTerms, .tags, .kindColors: return true
        default: return false
        }
    }
}

struct ValueTablesView: View {
    @EnvironmentObject var statusStore: OrderStatusStore
    @EnvironmentObject var invoiceStatusStore: InvoiceStatusStore
    @EnvironmentObject var quoteStatusStore: QuoteStatusStore
    @EnvironmentObject var tagStore: TagStore
    @EnvironmentObject var kindColors: KindColorStore
    @EnvironmentObject var paymentTermsStore: PaymentTermsPresetStore
    @State private var selectedTable: ValueTable = .orderStatuses
    @State private var searchQuery = ""
    @State private var editingStatus: OrderStatusOverride?
    @State private var editingInvoiceStatus: InvoiceStatusOverride?
    @State private var editingQuoteStatus: QuoteStatusOverride?
    @State private var editingTag: PartyTag?
    @State private var editingPaymentTerm: PaymentTermsPreset?
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
        .sheet(item: $editingInvoiceStatus) { override in
            InvoiceStatusEditorSheet(override: override) { updated in
                if let i = invoiceStatusStore.overrides.firstIndex(where: { $0.id == override.id }) {
                    invoiceStatusStore.overrides[i] = updated
                    invoiceStatusStore.save()
                }
            }
        }
        .sheet(item: $editingQuoteStatus) { override in
            QuoteStatusEditorSheet(override: override) { updated in
                if let i = quoteStatusStore.overrides.firstIndex(where: { $0.id == override.id }) {
                    quoteStatusStore.overrides[i] = updated
                    quoteStatusStore.save()
                }
            }
        }
        .sheet(item: $editingTag) { tag in
            TagEditorSheet(tag: tag) { updated in tagStore.upsert(updated) }
        }
        .sheet(item: $editingPaymentTerm) { preset in
            PaymentTermsPresetEditorSheet(preset: preset) { updated in paymentTermsStore.upsert(updated) }
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
        case .invoiceStatuses: invoiceStatusesPanel
        case .orderStatuses: orderStatusesPanel
        case .quoteStatuses: quoteStatusesPanel
        case .paymentTerms: paymentTermsPanel
        case .tags: tagsPanel
        case .kindColors: kindColorsPanel
        case .currencies: refPanel(NormRefs.currencies)
        case .units: refPanel(NormRefs.units)
        case .countries: refPanel(NormRefs.countries)
        case .endpointSchemes: refPanel(NormRefs.endpointSchemes)
        }
    }

    private var invoiceStatusesPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Statuts des factures").font(.title3.bold())
                Spacer()
                Button {
                    let id = "custom-\(UUID().uuidString.prefix(8))"
                    invoiceStatusStore.append(InvoiceStatusOverride(id: id, label: "Nouveau statut", systemImage: "doc", hexColor: "6E6E73"))
                } label: { Label("Nouvelle valeur", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
            }
            .padding(12)
            Divider()
            Text("Personnalisez le libellé des statuts. Les lignes « réforme » (liaison PDP) sont non supprimables : seul le libellé est modifiable. La colonne « code réforme » indique l'équivalent envoyé/rapatrié vers la PDP ; les transitions affichent le cycle de vie normé.")
                .font(.caption).foregroundStyle(.secondary).padding(12)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredInvoiceStatuses) { override in
                        invoiceStatusRow(override)
                    }
                }
                .padding(12)
            }
        }
    }

    private func invoiceStatusRow(_ override: InvoiceStatusOverride) -> some View {
        let transitionLabels: [String] = override.transitionCodes.compactMap { code in
            invoiceStatusStore.overrides.first { $0.id == code }?.label
                ?? InvoiceStatus(rawValue: code)?.label
        }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: override.systemImage)
                    .frame(width: 22)
                    .foregroundStyle(Color(hex: override.hexColor))
                Text(override.label).font(.body)
                if override.isReformStatus {
                    HStack(spacing: 3) {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(override.reformCode ?? "")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.12)))
                    .help("Statut lié à la réforme (PDP) — code \(override.reformCode ?? ""). Non supprimable, libellé modifiable.")
                } else {
                    Text("hors réforme")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button {
                    editingInvoiceStatus = override
                } label: { Image(systemName: "pencil") }
                    .buttonStyle(.borderless)
                    .help("Modifier le libellé")
                if !override.isReformStatus {
                    Button(role: .destructive) {
                        if let i = invoiceStatusStore.overrides.firstIndex(where: { $0.id == override.id }) {
                            invoiceStatusStore.remove(at: i)
                        }
                    } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .help("Supprimer ce statut")
                }
            }
            if !transitionLabels.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Transitions : " + transitionLabels.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 32)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.clear))
    }

    private var filteredInvoiceStatuses: [InvoiceStatusOverride] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return invoiceStatusStore.overrides }
        return invoiceStatusStore.overrides.filter { $0.label.lowercased().contains(q) || $0.id.lowercased().contains(q) || ($0.reformCode ?? "").lowercased().contains(q) }
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
                        orderStatusRow(override)
                    }
                }
                .padding(12)
            }
        }
    }

    private func orderStatusRow(_ override: OrderStatusOverride) -> some View {
        let transitionLabels: [String] = override.transitionCodes.compactMap { code in
            statusStore.overrides.first { $0.id == code }?.label
        }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: override.systemImage)
                    .frame(width: 22)
                    .foregroundStyle(Color(hex: override.hexColor))
                Text(override.label).font(.body)
                if override.isPDPStatus {
                    HStack(spacing: 3) {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(override.id)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.clear))
                    .help("Clé technique non modifiable (statut lié au cycle standard)")
                } else {
                    Text("hors cycle standard")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button {
                    editingStatus = override
                } label: { Image(systemName: "pencil") }
                    .buttonStyle(.borderless)
                    .help("Modifier ce statut")
                if !override.isPDPStatus {
                    Button(role: .destructive) {
                        if let i = statusStore.overrides.firstIndex(where: { $0.id == override.id }) {
                            statusStore.remove(at: i)
                        }
                    } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .help("Supprimer ce statut")
                }
            }
            if !transitionLabels.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Transitions : " + transitionLabels.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 32)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.clear))
    }

    /// Contrairement aux commandes/factures, un devis n'a pas de statuts imposés
    /// par un tiers externe : pas de bouton « nouvelle valeur » ni de suppression,
    /// seuls les 5 statuts standard existent et restent tous éditables.
    private var quoteStatusesPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Statuts des devis").font(.title3.bold())
                Spacer()
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredQuoteStatuses) { override in
                        quoteStatusRow(override)
                    }
                }
                .padding(12)
            }
        }
    }

    private func quoteStatusRow(_ override: QuoteStatusOverride) -> some View {
        let transitionLabels: [String] = override.transitionCodes.compactMap { code in
            quoteStatusStore.overrides.first { $0.id == code }?.label
        }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: override.systemImage)
                    .frame(width: 22)
                    .foregroundStyle(Color(hex: override.hexColor))
                Text(override.label).font(.body)
                Spacer()
                Button {
                    editingQuoteStatus = override
                } label: { Image(systemName: "pencil") }
                    .buttonStyle(.borderless)
                    .help("Modifier ce statut")
            }
            if !transitionLabels.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Transitions : " + transitionLabels.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 32)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.clear))
    }

    private var filteredQuoteStatuses: [QuoteStatusOverride] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return quoteStatusStore.overrides }
        return quoteStatusStore.overrides.filter { $0.label.lowercased().contains(q) || $0.id.lowercased().contains(q) }
    }

    private var filteredStatuses: [OrderStatusOverride] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return statusStore.overrides }
        return statusStore.overrides.filter { $0.label.lowercased().contains(q) || $0.id.lowercased().contains(q) }
    }

    private var filteredPaymentTerms: [PaymentTermsPreset] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return paymentTermsStore.presets }
        return paymentTermsStore.presets.filter { $0.label.lowercased().contains(q) || $0.text.lowercased().contains(q) }
    }

    private var paymentTermsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Conditions de paiement").font(.title3.bold())
                Spacer()
                Button {
                    paymentTermsStore.reset()
                } label: { Label("Réinitialiser", systemImage: "arrow.counterclockwise") }
                    .buttonStyle(.bordered)
                Button {
                    let preset = PaymentTermsPreset(label: "Nouveau préréglage", text: "")
                    paymentTermsStore.append(preset)
                    editingPaymentTerm = preset
                } label: { Label("Nouvelle valeur", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredPaymentTerms) { preset in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(preset.label).font(.body)
                                Text(preset.text.isEmpty ? "(texte vide)" : preset.text)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                editingPaymentTerm = preset
                            } label: { Image(systemName: "pencil") }
                                .buttonStyle(.borderless)
                                .help("Modifier ce préréglage")
                            Button(role: .destructive) {
                                if let idx = paymentTermsStore.presets.firstIndex(where: { $0.id == preset.id }) {
                                    paymentTermsStore.remove(at: idx)
                                }
                            } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                                .help("Supprimer ce préréglage")
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.clear))
                    }
                }
                .padding(12)
            }
        }
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
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.clear))
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
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.clear))
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
    @EnvironmentObject var statusStore: OrderStatusStore
    @Environment(\.dismiss) private var dismiss
    @State private var label: String
    @State private var systemImage: String
    @State private var hexColor: String
    @State private var transitionCodes: Set<String>

    private var possibleTargets: [OrderStatusOverride] {
        statusStore.overrides.filter { $0.id != override.id }
    }

    init(override: OrderStatusOverride, onSave: @escaping (OrderStatusOverride) -> Void) {
        self.override = override
        self.onSave = onSave
        _label = State(initialValue: override.label)
        _systemImage = State(initialValue: override.systemImage)
        _hexColor = State(initialValue: override.hexColor)
        _transitionCodes = State(initialValue: Set(override.transitionCodes))
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
            if !possibleTargets.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Transitions autorisées vers…").font(.subheadline.bold())
                    Text("Statuts accessibles depuis « \(label) » via les boutons d'action de la commande (un administrateur peut toujours forcer les autres).")
                        .font(.caption).foregroundStyle(.secondary)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(possibleTargets) { target in
                                Toggle(isOn: Binding(
                                    get: { transitionCodes.contains(target.id) },
                                    set: { isOn in
                                        if isOn { transitionCodes.insert(target.id) }
                                        else { transitionCodes.remove(target.id) }
                                    }
                                )) {
                                    Label(target.label, systemImage: target.systemImage)
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                    }
                    .frame(maxHeight: 140)
                }
            }
            HStack {
                Spacer()
                Button("Enregistrer") {
                    let ordered = statusStore.overrides.map { $0.id }.filter { transitionCodes.contains($0) }
                    onSave(OrderStatusOverride(id: override.id, label: label, systemImage: systemImage, hexColor: hexColor, transitionCodes: ordered))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 460, height: 460)
    }
}

struct QuoteStatusEditorSheet: View {
    var override: QuoteStatusOverride
    let onSave: (QuoteStatusOverride) -> Void
    @EnvironmentObject var quoteStatusStore: QuoteStatusStore
    @Environment(\.dismiss) private var dismiss
    @State private var label: String
    @State private var systemImage: String
    @State private var hexColor: String
    @State private var transitionCodes: Set<String>

    private var possibleTargets: [QuoteStatusOverride] {
        quoteStatusStore.overrides.filter { $0.id != override.id }
    }

    init(override: QuoteStatusOverride, onSave: @escaping (QuoteStatusOverride) -> Void) {
        self.override = override
        self.onSave = onSave
        _label = State(initialValue: override.label)
        _systemImage = State(initialValue: override.systemImage)
        _hexColor = State(initialValue: override.hexColor)
        _transitionCodes = State(initialValue: Set(override.transitionCodes))
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
            if !possibleTargets.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Transitions autorisées vers…").font(.subheadline.bold())
                    Text("Statuts accessibles depuis « \(label) » via les boutons d'action du devis.")
                        .font(.caption).foregroundStyle(.secondary)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(possibleTargets) { target in
                                Toggle(isOn: Binding(
                                    get: { transitionCodes.contains(target.id) },
                                    set: { isOn in
                                        if isOn { transitionCodes.insert(target.id) }
                                        else { transitionCodes.remove(target.id) }
                                    }
                                )) {
                                    Label(target.label, systemImage: target.systemImage)
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                    }
                    .frame(maxHeight: 140)
                }
            }
            HStack {
                Spacer()
                Button("Enregistrer") {
                    let ordered = quoteStatusStore.overrides.map { $0.id }.filter { transitionCodes.contains($0) }
                    onSave(QuoteStatusOverride(id: override.id, label: label, systemImage: systemImage, hexColor: hexColor, transitionCodes: ordered))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 460, height: 460)
    }
}

struct InvoiceStatusEditorSheet: View {
    var override: InvoiceStatusOverride
    let onSave: (InvoiceStatusOverride) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var label: String
    @State private var systemImage: String
    @State private var hexColor: String
    @State private var transitionCodes: Set<String>

    private var currentStatus: InvoiceStatus? { InvoiceStatus(rawValue: override.id) }
    private var possibleTargets: [InvoiceStatus] { InvoiceStatus.allCases.filter { $0.rawValue != override.id } }

    init(override: InvoiceStatusOverride, onSave: @escaping (InvoiceStatusOverride) -> Void) {
        self.override = override
        self.onSave = onSave
        _label = State(initialValue: override.label)
        _systemImage = State(initialValue: override.systemImage)
        _hexColor = State(initialValue: override.hexColor)
        _transitionCodes = State(initialValue: Set(override.transitionCodes))
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Modifier le statut facture").font(.title3.bold())
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if override.isReformStatus {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill").foregroundStyle(.secondary)
                    Text("Statut de réforme (PDP) — code \(override.reformCode ?? ""). Seul le libellé est modifiable.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.1)))
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Libellé").frame(width: 100, alignment: .leading)
                    TextField("Libellé", text: $label).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Icône SF").frame(width: 100, alignment: .leading)
                    TextField("Icône SF", text: $systemImage).textFieldStyle(.roundedBorder)
                        .disabled(override.isReformStatus)
                }
                HStack {
                    Text("Couleur").frame(width: 100, alignment: .leading)
                    ColorPicker(selection: Binding(
                        get: { Color(hex: hexColor) },
                        set: { hexColor = hexString(from: $0) }
                    )) { Text("Couleur") }
                    .disabled(override.isReformStatus)
                }
            }
            if currentStatus != nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Transitions autorisées vers…").font(.subheadline.bold())
                    Text("Statuts accessibles depuis « \(label) » via les boutons d'action de la facture (un administrateur peut toujours forcer les autres).")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(possibleTargets, id: \.self) { target in
                        Toggle(isOn: Binding(
                            get: { transitionCodes.contains(target.rawValue) },
                            set: { isOn in
                                if isOn { transitionCodes.insert(target.rawValue) }
                                else { transitionCodes.remove(target.rawValue) }
                            }
                        )) {
                            Label(target.label, systemImage: target.systemImage)
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Enregistrer") {
                    let ordered = InvoiceStatus.allCases.map { $0.rawValue }.filter { transitionCodes.contains($0) }
                    onSave(InvoiceStatusOverride(id: override.id, label: label, systemImage: systemImage, hexColor: hexColor, reformCode: override.reformCode, transitionCodes: ordered))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Spacer()
        }
        .padding()
        .frame(width: 460, height: 460)
    }
}

struct PaymentTermsPresetEditorSheet: View {
    var preset: PaymentTermsPreset
    let onSave: (PaymentTermsPreset) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var label: String
    @State private var text: String
    @State private var ruleKind: DueRuleKind
    @State private var days: Int

    private enum DueRuleKind: String, CaseIterable, Identifiable {
        case none = "Aucune (saisie manuelle)"
        case days = "Jours nets"
        case endOfMonth = "Fin de mois + jours"
        var id: String { rawValue }
    }

    init(preset: PaymentTermsPreset, onSave: @escaping (PaymentTermsPreset) -> Void) {
        self.preset = preset
        self.onSave = onSave
        _label = State(initialValue: preset.label)
        _text = State(initialValue: preset.text)
        switch preset.dueRule {
        case .none:
            _ruleKind = State(initialValue: .none)
            _days = State(initialValue: 30)
        case .days(let n):
            _ruleKind = State(initialValue: .days)
            _days = State(initialValue: n)
        case .endOfMonthPlusDays(let n):
            _ruleKind = State(initialValue: .endOfMonth)
            _days = State(initialValue: n)
        }
    }

    private var dueRule: PaymentTermsDueRule {
        switch ruleKind {
        case .none: return .none
        case .days: return .days(days)
        case .endOfMonth: return .endOfMonthPlusDays(days)
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Modifier le préréglage").font(.title3.bold())
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Libellé").frame(width: 160, alignment: .leading)
                    TextField("Libellé affiché dans le menu", text: $label).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Texte").frame(width: 160, alignment: .leading)
                    TextField("Texte inséré dans les conditions de paiement", text: $text).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Échéance").frame(width: 160, alignment: .leading)
                    Picker("", selection: $ruleKind) {
                        ForEach(DueRuleKind.allCases) { k in Text(k.rawValue).tag(k) }
                    }
                    .labelsHidden()
                }
                if ruleKind != .none {
                    HStack {
                        Text(ruleKind == .days ? "Nombre de jours" : "Jours après fin de mois").frame(width: 160, alignment: .leading)
                        Stepper(value: $days, in: 0...120) { Text("\(days) j") }
                    }
                    Text("Échéance calculée automatiquement pour toute facture utilisant ce préréglage.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("L'échéance reste à saisir manuellement sur chaque facture.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("Enregistrer") {
                    onSave(PaymentTermsPreset(id: preset.id, label: label, text: text, dueRule: dueRule))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty || text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Spacer()
        }
        .padding()
        .frame(width: 440, height: 360)
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
            } catch let err {
                self.error = err.localizedDescription
            }
            searching = false
        }
    }
}

struct SuperPDPEventsSheet: View {
    let events: [SuperPDPInvoiceEvent]
    let loading: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Historique SUPER PDP").font(.headline)
                Spacer()
                Button("Fermer") { dismiss() }
            }.padding(12)
            Divider()
            if loading {
                HStack { Spacer(); ProgressView(); Spacer() }.padding(40)
            } else if events.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.badge.questionmark").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Aucun événement retourné.").font(.caption).foregroundStyle(.secondary)
                }.padding(40)
            } else {
                List {
                    ForEach(events) { ev in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Image(systemName: ev.semanticSystemImage)
                                    .foregroundStyle(Color(hex: ev.semanticHexColor))
                                Text(ev.detailLabel).font(.body.bold())
                                Spacer()
                                if let d = ev.createdAt {
                                    Text(d, format: .dateTime.day().month().year().hour().minute())
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            HStack(spacing: 6) {
                                Image(systemName: ev.direction == .sent ? "arrow.up.circle" : "arrow.down.circle")
                                Text(ev.direction == .sent ? "Envoyé" : "Reçu")
                                Text("·")
                                Text(ev.statusCode).font(.system(.caption2, design: .monospaced))
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            if let n = ev.notes, !n.isEmpty {
                                Text(n).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }.frame(minWidth: 480, minHeight: 360)
    }
}

struct SuperPDPValidationSheet: View {
    let report: SuperPDPValidationReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Rapport de validation SUPER PDP").font(.headline)
                Spacer()
                Button("Fermer") { dismiss() }
            }.padding(12)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: report.isValid ? "checkmark.seal.fill" : "xmark.octagon.fill")
                        .foregroundStyle(report.isValid ? .green : .red).font(.title2)
                    Text(report.isValid ? "Facture valide" : "Facture non valide").font(.title3.bold())
                }
                if !report.errors.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Erreurs (\(report.errors.count))").font(.subheadline.bold()).foregroundStyle(.red)
                        ForEach(Array(report.errors.enumerated()), id: \.offset) { _, e in
                            Text("• \(e)").font(.caption).foregroundStyle(.red)
                        }
                    }
                }
                if !report.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Avertissements (\(report.warnings.count))").font(.subheadline.bold()).foregroundStyle(.orange)
                        ForEach(Array(report.warnings.enumerated()), id: \.offset) { _, w in
                            Text("• \(w)").font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
                if report.isValid && report.errors.isEmpty && report.warnings.isEmpty {
                    Text("Aucune erreur ni avertissement. La facture est conforme.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(16)
            Spacer()
        }.frame(minWidth: 480, minHeight: 360)
    }
}

struct SuperPDPFrenchDirectorySheet: View {
    @EnvironmentObject var superPDPSettings: SuperPDPSettings
    @Environment(\.dismiss) private var dismiss
    let onPick: (InvoiceParty) -> Void
    @State private var query = ""
    @State private var results: [SuperPDPFrenchCompany] = []
    @State private var searching = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Annuaire français des entreprises").font(.headline)
                Spacer()
                Button("Fermer") { dismiss() }
            }.padding(12)
            Divider()
            HStack {
                TextField("SIREN, SIRET ou raison sociale…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { runSearch() }
                Button { runSearch() } label: { Label("Rechercher", systemImage: "magnifyingglass") }
                    .disabled(searching || query.trimmingCharacters(in: .whitespaces).isEmpty)
            }.padding(12)
            if !superPDPSettings.credentials.isConfigured {
                Text("Identifiants SUPER PDP non configurés. Ouvrez l'onglet Réglages.")
                    .font(.caption).foregroundStyle(.orange).padding(12)
            }
            if searching {
                HStack { Spacer(); ProgressView(); Spacer() }.padding()
            } else if let err = error {
                Text(err).font(.caption).foregroundStyle(.red).padding(12)
            } else {
                List(results) { c in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(c.name ?? "(sans nom)").font(.body.bold())
                        Text(c.displaySubtitle).font(.caption).foregroundStyle(.secondary)
                        if let addr = c.addressLine, !addr.isEmpty {
                            Text([addr, c.postcode, c.city].compactMap { $0 }.joined(separator: " ")).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onPick(c.toInvoiceParty())
                        dismiss()
                    }
                }
            }
        }.frame(minWidth: 520, minHeight: 420).onAppear { if results.isEmpty { query = "" } }
    }

    private func runSearch() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searching = true
        error = nil
        Task {
            do {
                let service = SuperPDPService()
                results = try await service.searchFrenchDirectory(sirenOrName: q, credentials: superPDPSettings.credentials)
            } catch let e as SuperPDPError {
                error = e.localizedDescription
                results = []
            } catch let err {
                error = "\(err)"
                results = []
            }
            searching = false
        }
    }
}

struct SuperPDPSearchSheet: View {
    @EnvironmentObject var superPDPSettings: SuperPDPSettings
    @Environment(\.dismiss) private var dismiss
    @State private var query: String
    @State private var results: [SuperPDPDirectoryEntry] = []
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
                Text("Rechercher un destinataire (SUPER PDP)").font(.headline)
                Spacer()
                Button { dismiss() } label: { Text("Fermer") }.keyboardShortcut(.cancelAction)
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
            if !superPDPSettings.credentials.isConfigured {
                Text("Identifiants SUPER PDP non configurés. Ouvrez l'onglet Réglages.")
                    .font(.caption).foregroundStyle(.orange).padding(12)
            }
            if searching {
                HStack { Spacer(); ProgressView(); Spacer() }.padding()
            } else if let err = error {
                Text(err).font(.caption).foregroundStyle(.red).padding(12)
            } else {
                Divider()
                if results.isEmpty {
                    Text("Saisissez un SIREN/SIRET et lancez la recherche.")
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
                                        Text(r.name ?? "(sans dénomination)").font(.body.weight(.medium))
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
        guard superPDPSettings.credentials.isConfigured else {
            error = "Identifiants SUPER PDP non configurés."
            return
        }
        searching = true
        error = nil
        results = []
        Task {
            do {
                let r = try await SuperPDPService().searchRecipient(
                    siretOrSiren: query,
                    credentials: superPDPSettings.credentials
                )
                results = Self.deduplicated(r)
                if r.isEmpty { error = "Aucun résultat." }
            } catch let e as SuperPDPError {
                self.error = e.errorDescription
            } catch let err {
                self.error = err.localizedDescription
            }
            searching = false
        }
    }

    /// SUPER PDP peut renvoyer plusieurs enregistrements techniques distincts
    /// (facturation/e-reporting/commandes…) pour la même société, avec des
    /// champs affichés strictement identiques — on ne garde qu'une occurrence
    /// par combinaison nom/SIREN/SIRET/adresse pour éviter des lignes qui
    /// semblent être de purs doublons.
    private static func deduplicated(_ entries: [SuperPDPDirectoryEntry]) -> [SuperPDPDirectoryEntry] {
        var seen = Set<String>()
        var unique: [SuperPDPDirectoryEntry] = []
        for e in entries {
            let key = [e.name ?? "", e.siren ?? "", e.siret ?? "", e.addressLine ?? "", e.city ?? ""].joined(separator: "|")
            if seen.insert(key).inserted {
                unique.append(e)
            }
        }
        return unique
    }
}

struct PartyEditorView: View {
    @Binding var party: InvoiceParty
    @Binding var routingAddresses: [PartyRoutingAddress]
    @Binding var contacts: [PartyContact]
    var showWebButton: Bool
    var isSociete: Bool = false
    var hideEmail: Bool = false
    var hideBankDetails: Bool = false
    var hideElectronicAddress: Bool = false
    var locked: Bool = false
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
    @EnvironmentObject var paymentTermsStore: PaymentTermsPresetStore

    /// `nil` = "Personnalisé" (saisie libre) ; sinon l'id du préréglage sélectionné.
    private var paymentTermsPresetIDBinding: Binding<String?> {
        Binding(
            get: { paymentTermsStore.matchingPresetID(for: party.paymentTerms) },
            set: { newID in
                guard let id = newID, let preset = paymentTermsStore.presets.first(where: { $0.id == id }) else { return }
                party.paymentTerms = preset.text
            }
        )
    }

    init(party: Binding<InvoiceParty>, routingAddresses: Binding<[PartyRoutingAddress]>? = nil, contacts: Binding<[PartyContact]>? = nil, showWebButton: Bool = true, isSociete: Bool = false, hideEmail: Bool = false, hideBankDetails: Bool = false, hideElectronicAddress: Bool = false, locked: Bool = false, directory: PartyDirectory? = nil, onPickContact: ((PartyContact) -> Void)? = nil, onPickRouting: ((PartyRoutingAddress) -> Void)? = nil, onPartyPicked: ((InvoiceParty) -> Void)? = nil) {
        self._party = party
        self.showWebButton = showWebButton
        self.isSociete = isSociete
        self.hideEmail = hideEmail
        self.hideBankDetails = hideBankDetails
        self.hideElectronicAddress = hideElectronicAddress
        self.locked = locked
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

    @State private var addressExpanded = false
    @FocusState private var addressFieldFocused: Bool

    private var addressSummary: String {
        let cityLine = [party.postcode, party.city]
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: " ")
        let parts = [party.street, cityLine].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return parts.isEmpty ? "Adresse non renseignée" : parts.joined(separator: ", ")
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
            VStack(alignment: .leading, spacing: 6) {
                Group {
                    if addressExpanded || addressFieldFocused {
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Adresse", text: $party.street)
                                .focused($addressFieldFocused)
                            HStack(spacing: 8) {
                                TextField("Code postal", text: $party.postcode).frame(width: 90)
                                    .focused($addressFieldFocused)
                                TextField("Ville", text: $party.city)
                                    .focused($addressFieldFocused)
                                HStack(spacing: 2) {
                                    Text("Pays").font(.caption); star
                                    NormRefPicker("Pays", options: NormRefs.countries, code: $party.country).frame(width: 160)
                                }
                            }
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "location").font(.caption2).foregroundStyle(.secondary)
                            Text(addressSummary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .onHover { hovering in addressExpanded = hovering }
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Text("SIREN").font(.caption); star
                        TextField("SIREN (9 chiffres)", text: Binding($party.siren, replacingNilWith: ""))
                            .frame(width: 130)
                            .onChange(of: party.siren) { _ in scheduleDinumSearch() }
                        if let sn = party.siren?.trimmingCharacters(in: .whitespaces), !sn.isEmpty {
                            Image(systemName: SireneValidator.isValidSiren(sn) ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(SireneValidator.isValidSiren(sn) ? .green : .orange)
                                .help(SireneValidator.isValidSiren(sn) ? "SIREN valide" : "SIREN invalide")
                        }
                    }
                    HStack(spacing: 4) {
                        Text("TVA").font(.caption)
                        TextField("N° TVA", text: Binding($party.vatNumber, replacingNilWith: "")).frame(width: 130)
                    }
                    HStack(spacing: 4) {
                        Text("SIRET").font(.caption)
                        TextField("SIRET (14 chiffres)", text: Binding($party.siret, replacingNilWith: "")).frame(width: 150)
                        if let st = party.siret?.trimmingCharacters(in: .whitespaces), !st.isEmpty {
                            Image(systemName: SireneValidator.isValidSiret(st) ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(SireneValidator.isValidSiret(st) ? .green : .orange)
                                .help(SireneValidator.isValidSiret(st) ? "SIRET valide" : "SIRET invalide")
                        }
                    }
                }
            }
            if !hideElectronicAddress {
                HStack {
                    Text("Ident. élec. (BT-49/34)").font(.caption)
                    if linkedEntry != nil {
                        Text((party.endpointID ?? "").isEmpty ? "Aucune" : (party.endpointID ?? ""))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if !locked {
                            Button {
                                showRoutingPicker = true
                            } label: { Image(systemName: "envelope.circle.fill").font(.title3) }
                                .buttonStyle(.borderless)
                                .help("Choisir ou créer une adresse électronique depuis la fiche tiers")
                        }
                    } else {
                        TextField("Auto depuis SIREN si vide", text: Binding($party.endpointID, replacingNilWith: ""))
                        NormRefPicker("Scheme", options: NormRefs.endpointSchemes, code: $party.endpointSchemeID).frame(width: 180)
                    }
                }
            }
            if isMultiContact {
                HStack {
                    Text("Contacts").font(.caption)
                    Spacer()
                    if !locked {
                        Button {
                            editingContact = nil
                            showContactEditor = true
                        } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                            .buttonStyle(.borderless)
                            .help("Ajouter un contact")
                    }
                }
                if contacts.isEmpty {
                    Text("Aucun contact").font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(contacts) { ct in
                        HStack(spacing: 8) {
                            if ct.isDefault {
                                Text("défaut").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Color.accentColor.opacity(0.2), in: Capsule())
                            }
                            Text(ct.name.trimmingCharacters(in: .whitespaces).isEmpty ? "(sans nom)" : ct.name)
                                .font(.callout.bold())
                            if let e = ct.email?.trimmingCharacters(in: .whitespaces), !e.isEmpty {
                                Text(e).font(.callout).foregroundStyle(.secondary)
                            }
                            if let p = ct.phone?.trimmingCharacters(in: .whitespaces), !p.isEmpty {
                                Text(p).font(.callout).foregroundStyle(.secondary)
                            }
                            if !ct.isActive {
                                Text("inactif").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Color.gray.opacity(0.2), in: Capsule())
                            }
                            Spacer()
                            if !locked {
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
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.clear))
                    }
                }
            } else if linkedEntry != nil {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Contact").font(.caption)
                        Spacer()
                        if !locked {
                            Button {
                                showContactPicker = true
                            } label: { Image(systemName: "person.crop.circle.fill.badge.checkmark").font(.title3) }
                                .buttonStyle(.borderless)
                                .help("Choisir ou créer un contact depuis la fiche tiers")
                        }
                    }
                    let name = party.contactName?.trimmingCharacters(in: .whitespaces) ?? ""
                    let email = hideEmail ? "" : (party.contactEmail?.trimmingCharacters(in: .whitespaces) ?? "")
                    let phone = party.contactPhone?.trimmingCharacters(in: .whitespaces) ?? ""
                    if name.isEmpty && email.isEmpty && phone.isEmpty {
                        Text("Aucun contact").font(.callout).foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 8) {
                            Text(name.isEmpty ? "(sans nom)" : name).font(.callout.bold())
                            if !email.isEmpty { Text(email).font(.callout).foregroundStyle(.secondary) }
                            if !phone.isEmpty { Text(phone).font(.callout).foregroundStyle(.secondary) }
                            Spacer()
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.clear))
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
            if !hideElectronicAddress, linkedEntry == nil, !locked {
                Button {
                    showRoutingEditor = true
                } label: {
                    Label("Adresses de facturation électronique", systemImage: "envelope.badge")
                }
                .buttonStyle(.bordered)
            }
            if isSociete, !hideBankDetails {
                DisclosureGroup("Coordonnées bancaires & conditions de paiement") {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("IBAN", text: Binding($party.iban, replacingNilWith: ""))
                            .textCase(.uppercase)
                        if let iban = party.iban?.trimmingCharacters(in: .whitespaces), !iban.isEmpty {
                            if IBANValidator.isValid(iban) {
                                Label("IBAN valide (clé mod 97 correcte)", systemImage: "checkmark.circle.fill")
                                    .font(.caption2).foregroundStyle(.green)
                            } else {
                                Label("IBAN invalide (clé de contrôle incorrecte ou longueur pays inattendue)", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption2).foregroundStyle(.orange)
                            }
                        }
                        TextField("BIC", text: Binding($party.bic, replacingNilWith: ""))
                            .textCase(.uppercase)
                        Picker("Conditions de paiement", selection: paymentTermsPresetIDBinding) {
                            ForEach(paymentTermsStore.presets) { preset in
                                Text(preset.label).tag(Optional(preset.id))
                            }
                            Text("Personnalisé").tag(String?.none)
                        }
                        if paymentTermsPresetIDBinding.wrappedValue == nil {
                            TextField("Texte libre", text: Binding($party.paymentTerms, replacingNilWith: ""))
                        }
                    }
                }
                .font(.caption)
            }
            if !hideElectronicAddress, !routingAddresses.isEmpty {
                ForEach(routingAddresses) { addr in
                    HStack(spacing: 8) {
                        Text(addr.format.label).font(.callout.bold())
                        Text(addr.composedAddress).font(.system(.callout, design: .monospaced))
                        if addr.isDefault {
                            Text("défaut").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.2), in: Capsule())
                        }
                        Spacer()
                        if !locked {
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
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.clear))
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

struct OrderPartySection: View {
    enum Role {
        case buyer, seller
        var title: String { self == .buyer ? "Acheteur" : "Société" }
        var defaultKind: DirectoryEntryKind { self == .buyer ? .client : .societe }
    }

    @Binding var party: InvoiceParty
    let role: Role
    var onPartyPicked: ((InvoiceParty) -> Void)? = nil
    var locked: Bool = false
    @EnvironmentObject var directory: PartyDirectory
    @State private var showPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !locked {
                HStack {
                    Button {
                        showPicker = true
                    } label: {
                        Label("Choisir dans l'annuaire", systemImage: "person.crop.circle.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
            }

            PartyEditorView(party: $party, isSociete: role == .seller, hideEmail: true, locked: locked, directory: directory, onPickContact: { updatePartyFromContact($0) }, onPickRouting: { updatePartyFromRouting($0) }, onPartyPicked: { p in onPartyPicked?(p) })
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
    @State private var exportMessage: String?
    @State private var showScanImport = false
    @State private var statusFilter: OrderStatus? = nil
    @State private var showAdvancedFilters = false
    @State private var advField1: OrderFilterField = .none
    @State private var advValue1 = ""
    @State private var advField2: OrderFilterField = .none
    @State private var advValue2 = ""
    @State private var advField3: OrderFilterField = .none
    @State private var advValue3 = ""

    var filteredOrders: [SalesOrder] {
        var result = orderStore.orders
        if let scope = auth.visibleOrderCompanyIDs(for: auth.currentUser) {
            result = result.filter { order in
                if let cid = order.companyID { return scope.contains(cid) }
                return false
            }
        }
        if let sf = statusFilter {
            result = result.filter { $0.status == sf }
        }
        result = applyAdvancedFilter(result, field: advField1, value: advValue1)
        result = applyAdvancedFilter(result, field: advField2, value: advValue2)
        result = applyAdvancedFilter(result, field: advField3, value: advValue3)
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return result }
        return result.filter { order in
            order.number.lowercased().contains(q)
                || order.buyer.name.lowercased().contains(q)
                || (order.buyer.siren ?? "").lowercased().contains(q)
                || order.seller.name.lowercased().contains(q)
        }
    }

    private func applyAdvancedFilter(_ orders: [SalesOrder], field: OrderFilterField, value: String) -> [SalesOrder] {
        let raw = value.trimmingCharacters(in: .whitespaces)
        let v = raw.lowercased()
        guard field != .none, !v.isEmpty else { return orders }
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
            return orders.filter { $0.number.lowercased().contains(v) }
        case .buyerName:
            return orders.filter { $0.buyer.name.lowercased().contains(v) }
        case .buyerSiren:
            return orders.filter { ($0.buyer.siren ?? "").lowercased().contains(v) }
        case .buyerVat:
            return orders.filter { ($0.buyer.vatNumber ?? "").lowercased().contains(v) }
        case .sellerName:
            return orders.filter { $0.seller.name.lowercased().contains(v) }
        case .sellerSiren:
            return orders.filter { ($0.seller.siren ?? "").lowercased().contains(v) }
        case .amountMin:
            if let min = Double(v.replacingOccurrences(of: ",", with: ".")) {
                return orders.filter { $0.grandTotal >= min }
            }
            return orders
        case .amountMax:
            if let max = Double(v.replacingOccurrences(of: ",", with: ".")) {
                return orders.filter { $0.grandTotal <= max }
            }
            return orders
        case .issueDateFrom:
            if let d = parseDate(raw) { return orders.filter { $0.issueDate >= d } }
            return orders
        case .issueDateTo:
            if let d = parseDate(raw) { return orders.filter { $0.issueDate <= d } }
            return orders
        case .quotationRef:
            return orders.filter { ($0.quotationRef ?? "").lowercased().contains(v) }
        case .contractRef:
            return orders.filter { ($0.contractRef ?? "").lowercased().contains(v) }
        case .buyerReference:
            return orders.filter { ($0.buyerReference ?? "").lowercased().contains(v) }
        case .status:
            return orders.filter { $0.status.rawValue.lowercased() == v || $0.status.label.lowercased().contains(v) }
        case .none:
            return orders
        }
    }

    @ViewBuilder
    private func advancedFilterRow(field: Binding<OrderFilterField>, value: Binding<String>, index: Int) -> some View {
        let isDate = (field.wrappedValue == .issueDateFrom || field.wrappedValue == .issueDateTo)
        let isAmount = (field.wrappedValue == .amountMin || field.wrappedValue == .amountMax)
        HStack(spacing: 8) {
            Picker("", selection: field) {
                ForEach(OrderFilterField.allCases, id: \.self) { f in
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

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    Button {
                        let draft = orderStore.newDraft(preferredSellerEntryID: auth.currentUser?.defaultSellerEntryID, companyID: defaultOrderCompanyID())
                        orderStore.upsert(draft)
                        selectedID = draft.id
                    } label: { Label("Nouvelle commande", systemImage: "plus") }
                        .buttonStyle(.borderedProminent)
                    Button {
                        showScanImport = true
                    } label: { Label("Scanner un document", systemImage: "doc.viewfinder") }
                        .buttonStyle(.bordered)
                        .help("Importer la photo/le scan d'un bon de commande ou d'un devis fournisseur pour pré-remplir une commande")
                    Text("Ventes").font(.title2.bold())
                    Picker("Statut", selection: $statusFilter) {
                        Text("Tous statuts").tag(OrderStatus?.none)
                        ForEach(OrderStatus.allCases, id: \.self) { s in
                            Label(s.label, systemImage: s.systemImage).tag(OrderStatus?.some(s))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                    Spacer()
                    Menu {
                        ForEach(QuickExport.OrderFormat.allCases, id: \.self) { f in
                            Button(f.rawValue) { exportMessage = QuickExport.run(orders: filteredOrders, format: f) }
                        }
                    } label: { Label("Exporter", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.bordered)
                        .help("Exporte les commandes actuellement filtrées (\(filteredOrders.count))")
                }
                if let m = exportMessage, !m.isEmpty {
                    Text(m).font(.caption).foregroundStyle(.secondary)
                        .onChange(of: query) { _ in exportMessage = nil }
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
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.clear))
                DisclosureGroup(isExpanded: $showAdvancedFilters) {
                    HStack(alignment: .center, spacing: 12) {
                        advancedFilterRow(field: $advField1, value: $advValue1, index: 1)
                        if advField1 != .none || !advValue1.isEmpty || showAdvancedFilters {
                            advancedFilterRow(field: $advField2, value: $advValue2, index: 2)
                        }
                        if advField2 != .none || !advValue2.isEmpty || showAdvancedFilters {
                            advancedFilterRow(field: $advField3, value: $advValue3, index: 3)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 4)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.caption)
                        Text("Filtres avancés")
                            .font(.caption.bold())
                        Text("(\(activeAdvancedFilterCount))")
                            .font(.caption.bold())
                            .foregroundStyle(activeAdvancedFilterCount > 0 ? Color.accentColor : .secondary)
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
                }
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
                            let draft = orderStore.newDraft(preferredSellerEntryID: auth.currentUser?.defaultSellerEntryID, companyID: defaultOrderCompanyID())
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
                                    Text("\(order.buyer.name.isEmpty ? "Sans client" : order.buyer.name)")
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
        .sheet(isPresented: $showScanImport) {
            DocumentScanImportView(
                onCreated: { orderID in
                    selectedID = orderID
                    showScanImport = false
                },
                onCancel: { showScanImport = false }
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

struct QuotesTabView: View {
    @EnvironmentObject var quoteStore: QuoteStore
    @EnvironmentObject var quoteStatusStore: QuoteStatusStore
    @EnvironmentObject var store: InvoiceStore
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var directory: PartyDirectory
    @Binding var selectedID: UUID?
    @Binding var rootTab: RootTab
    @Binding var invoiceSelectedID: UUID?
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
        let draft = quoteStore.newDraft(seller: seller, companyID: defaultCompanyID())
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
                DisclosureGroup(isExpanded: $showAdvancedFilters) {
                    HStack(alignment: .center, spacing: 12) {
                        advancedFilterRow(field: $advField1, value: $advValue1, index: 1)
                        if advField1 != .none || !advValue1.isEmpty || showAdvancedFilters {
                            advancedFilterRow(field: $advField2, value: $advValue2, index: 2)
                        }
                        if advField2 != .none || !advValue2.isEmpty || showAdvancedFilters {
                            advancedFilterRow(field: $advField3, value: $advValue3, index: 3)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 4)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.caption)
                        Text("Filtres avancés")
                            .font(.caption.bold())
                        Text("(\(activeAdvancedFilterCount))")
                            .font(.caption.bold())
                            .foregroundStyle(activeAdvancedFilterCount > 0 ? Color.accentColor : .secondary)
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
                    QuoteEditorView(quote: binding(for: id), rootTab: $rootTab, invoiceSelectedID: $invoiceSelectedID)
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
    @EnvironmentObject var quoteStore: QuoteStore
    @EnvironmentObject var quoteStatusStore: QuoteStatusStore
    @EnvironmentObject var store: InvoiceStore
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
                                  || !emailTemplateStore.isSendEnabled(.quoteSent)
                                  || (quote.buyer.contactEmail ?? "").isEmpty
                                  || !smtpSettings.credentials.isConfigured)
                        .help(!emailTemplateStore.template(for: .quoteSent).enabled
                              ? "Cet email est désactivé (Réglages > Application)"
                              : (quote.buyer.contactEmail ?? "").isEmpty
                              ? "Aucune adresse email cliente renseignée"
                              : !smtpSettings.credentials.isConfigured
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
                    if quote.status == .accepted {
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
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
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
                            TextField("Qté", value: $line.quantity, format: .number).frame(width: 50).disabled(isLocked)
                            TextField("Prix U.", value: $line.unitPrice, format: .number).frame(width: 70).disabled(isLocked)
                            TextField("TVA %", value: $line.vatRate, format: .number).frame(width: 50).disabled(isLocked)
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
        let credentials = smtpSettings.credentials
        guard credentials.isConfigured else {
            quoteEmailMessage = "Échec envoi : envoi d'email non configuré (Réglages)."
            return
        }
        let template = emailTemplateStore.template(for: .quoteSent)
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

struct OrderEditorView: View {
    @Binding var order: SalesOrder
    @EnvironmentObject var orderStore: OrderStore
    @EnvironmentObject var statusStore: OrderStatusStore
    @EnvironmentObject var store: InvoiceStore
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var smtpSettings: SMTPSettings
    @EnvironmentObject var emailTemplateStore: EmailTemplateStore
    @State private var exportError: String?
    @State private var exportedURL: URL?
    @State private var validation: FacturXValidationResult?
    @State private var showValidation = false
    @State private var isManuallyLocked = false
    @State private var showUnlockAlert = false
    @State private var createdInvoiceNumber: String?
    @State private var showMandatoryDetails = false
    @State private var sendingOrderEmail: EmailTemplateKind?
    @State private var orderEmailMessage: String?

    private var statusLocked: Bool { order.status.locksOrder }
    private var isLocked: Bool { statusLocked || isManuallyLocked }
    private var isAdmin: Bool { auth.currentUser?.isAdmin ?? false }
    private var fieldLocked: Bool { isLocked && !isAdmin }

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
            // MARK: Bandeau d'informations (fixe, lecture seule)
            HStack(spacing: 10) {
                Text(order.number).font(.title2.bold())
                Text(order.issueDate, format: .dateTime.day().month().year())
                    .font(.callout).foregroundStyle(.secondary)
                Text(String(format: "%.2f %@ HT", order.lineTotal, order.currency))
                    .font(.callout).foregroundStyle(.secondary)
                let currentStatus = statusStore.override(for: order)
                HStack(spacing: 4) {
                    Image(systemName: currentStatus.systemImage)
                    Text(currentStatus.label)
                }
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Color(hex: currentStatus.hexColor)))
                if isLocked {
                    Label("Lecture seule", systemImage: "lock.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .overlay(Capsule().stroke(.secondary, lineWidth: 0.5))
                    if isAdmin {
                        Text("(admin : modification autorisée)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                HStack(spacing: 4) {
                    Text(order.seller.name.trimmingCharacters(in: .whitespaces).isEmpty ? "Société non renseignée" : order.seller.name)
                    Image(systemName: "arrow.right").font(.caption2)
                    Text(order.buyer.name.trimmingCharacters(in: .whitespaces).isEmpty ? "Client non renseigné" : order.buyer.name)
                }
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .padding(12)
            Divider()

            // MARK: Barre d'actions (fixe), sous-groupée : cycle de vie · admin
            ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                let currentStatus = statusStore.override(for: order)
                let configuredTransitions = statusStore.override(for: order.status).transitionCodes.compactMap { OrderStatus(rawValue: $0) }
                HStack(spacing: 8) {
                    if isManuallyLocked && !statusLocked && !isAdmin {
                        Button { showUnlockAlert = true } label: {
                            Label("Modifier", systemImage: "lock.open")
                        }
                        .buttonStyle(ToolbarActionButtonStyle(tint: .gray))
                        .help("Repasser en édition (la commande n'est plus protégée)")
                    } else if !isLocked && validation?.isValid == true {
                        Button { isManuallyLocked = true } label: {
                            Label("Verrouiller", systemImage: "lock")
                        }
                        .buttonStyle(ToolbarActionButtonStyle(tint: .gray))
                        .help("Protéger la commande validée en lecture seule")
                    }
                    Button("Valider") { runValidation() }
                        .buttonStyle(ToolbarActionButtonStyle(tint: .blue))
                        .disabled(fieldLocked)
                    ForEach(configuredTransitions, id: \.self) { s in
                        Button {
                            order.status = s
                            order.customStatusID = nil
                        } label: {
                            Label(s.label, systemImage: s.systemImage)
                        }
                        .buttonStyle(ToolbarActionButtonStyle(tint: Color(hex: s.hexColor)))
                        .help("Passer au statut « \(s.label) »")
                    }
                    Button("Exporter XML") { exportXML() }
                        .buttonStyle(ToolbarActionButtonStyle(tint: .gray))
                    Button("Générer l'Order-X") { export() }
                        .buttonStyle(ToolbarActionButtonStyle(tint: .blue, filled: true))
                    Button("Créer la facture") { createInvoice() }
                        .buttonStyle(ToolbarActionButtonStyle(tint: .gray))
                }
                if emailTemplateStore.globalEnabled {
                    Divider().frame(height: 20)
                    HStack(spacing: 8) {
                        orderEmailButton(kind: .orderConfirmation, label: "Confirmer par email")
                        orderEmailButton(kind: .deliveryNotice, label: "Avis de livraison")
                    }
                }
                if isAdmin {
                    let forceable = statusStore.overrides.filter { $0.id != currentStatus.id && !configuredTransitions.map(\.rawValue).contains($0.id) }
                    if !forceable.isEmpty {
                        Divider().frame(height: 20)
                        Menu {
                            ForEach(forceable) { target in
                                Button {
                                    if let s = OrderStatus(rawValue: target.id) {
                                        order.status = s
                                        order.customStatusID = nil
                                    } else {
                                        order.customStatusID = target.id
                                    }
                                } label: {
                                    Label(target.label, systemImage: target.systemImage)
                                }
                            }
                        } label: {
                            Label("Forcer", systemImage: "bolt.fill")
                        }
                        .buttonStyle(ToolbarActionButtonStyle(tint: .red))
                        .help("Administrateur : forcer un statut hors des transitions configurées")
                    }
                }
                Spacer()
            }
            .padding(12)
            }
            Divider()
            if hasMandatoryWarnings || showValidation || exportError != nil || exportedURL != nil || createdInvoiceNumber != nil || orderEmailMessage != nil {
                VStack(alignment: .leading, spacing: 8) {
                if let m = orderEmailMessage, !m.isEmpty {
                    Text(m).font(.caption).foregroundStyle(m.hasPrefix("Échec") ? .red : .green)
                        .onChange(of: order.number) { _ in orderEmailMessage = nil }
                }
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
                    DisclosureGroup(isExpanded: $showMandatoryDetails) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Acheteur et client : nom, pays (code ISO 2 lettres), SIREN ou identifiant électronique, n° TVA si applicable.").font(.caption)
                            Text("Lignes : désignation non vide, quantité positive, prix unitaire, taux TVA, unité (code UN/ECE ex. C62, DAY, HUR).").font(.caption)
                            Text("En-tête : numéro de commande, date d'émission, date de livraison souhaitée, devise (EUR).").font(.caption)
                        }
                    } label: {
                        Label("Données obligatoires pour la conformité Order-X", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                    }
                }

                if showValidation, let v = validation {
                    orderValidationPanel(v)
                        .onChange(of: order.number) { _ in showValidation = false; validation = nil }
                }
                }.padding(12)
                Divider()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
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
                                ForEach(order.vatBreakdown, id: \.rate) { item in
                                    row("TVA \(String(format: "%.0f%%", item.rate))", item.amount)
                                }
                                row("Total TTC", order.grandTotal, bold: true)
                                Divider().frame(width: 280)
                                row("Montant facturé", linkedInvoicesAmount)
                                row("Reste à facturer", max(0, order.grandTotal - linkedInvoicesAmount), bold: true)
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.clear))
                        }
                    }.padding(8)
                }.lockable(fieldLocked)

                HStack(alignment: .top, spacing: 12) {
                    GroupBox("Société (vous)") {
                        OrderPartySection(party: $order.seller, role: .seller, locked: fieldLocked)
                    }.lockable(fieldLocked)
                    GroupBox("Client") {
                        OrderPartySection(party: $order.buyer, role: .buyer, locked: fieldLocked)
                    }.lockable(fieldLocked)
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
                                Button {
                                    DispatchQueue.main.async {
                                        order.lines.removeAll { $0.id == line.id }
                                    }
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                            }
                        }
                        Button {
                            order.lines.append(InvoiceLine(name: "", quantity: 1, unitPrice: 0, vatRate: order.lines.last?.vatRate ?? 20))
                        } label: { Label("Ajouter une ligne", systemImage: "plus") }
                    }.padding(8)
                }.lockable(fieldLocked)

                GroupBox("Notes") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Notes libres", text: Binding($order.notes, replacingNilWith: ""))
                    }.padding(8)
                }.lockable(fieldLocked)

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
                }.lockable(fieldLocked)
            }.padding()
        }
            .alert("Repasser en modification ?", isPresented: $showUnlockAlert) {
                Button("Annuler", role: .cancel) { }
                Button("Modifier", role: .destructive) { isManuallyLocked = false }
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

    @ViewBuilder
    private func orderEmailButton(kind: EmailTemplateKind, label: String) -> some View {
        Button {
            sendOrderEmail(kind: kind)
        } label: {
            if sendingOrderEmail == kind {
                HStack(spacing: 4) { ProgressView().controlSize(.small); Text("Envoi…") }
            } else {
                Label(label, systemImage: kind.systemImage)
            }
        }
        .buttonStyle(ToolbarActionButtonStyle(tint: .blue))
        .disabled(sendingOrderEmail != nil
                  || !emailTemplateStore.isSendEnabled(kind)
                  || (order.buyer.contactEmail ?? "").isEmpty
                  || !smtpSettings.credentials.isConfigured)
        .help(!emailTemplateStore.template(for: kind).enabled
              ? "Cet email est désactivé (Réglages > Application)"
              : (order.buyer.contactEmail ?? "").isEmpty
              ? "Aucune adresse email cliente renseignée"
              : !smtpSettings.credentials.isConfigured
              ? "Configurez l'envoi d'email (Réglages) pour envoyer cet email"
              : "Envoyer « \(kind.label) » par email au client")
    }

    private func sendOrderEmail(kind: EmailTemplateKind) {
        guard let recipient = order.buyer.contactEmail, !recipient.isEmpty else {
            orderEmailMessage = "Échec envoi : aucune adresse email cliente renseignée."
            return
        }
        let credentials = smtpSettings.credentials
        guard credentials.isConfigured else {
            orderEmailMessage = "Échec envoi : envoi d'email non configuré (Réglages)."
            return
        }
        let template = emailTemplateStore.template(for: kind)
        let email = EmailComposer.compose(template: template, variables: [
            "numero": order.number,
            "client": order.buyer.name,
            "societe": order.seller.name,
            "montant": String(format: "%.2f %@", order.grandTotal, order.currency),
            "date": order.requestedDeliveryDate.formatted(.dateTime.day().month().year())
        ])
        sendingOrderEmail = kind
        orderEmailMessage = nil
        Task {
            do {
                try await SMTPService().send(to: recipient, subject: email.subject, body: email.body, credentials: credentials)
                orderEmailMessage = "« \(kind.label) » envoyé à \(recipient)."
            } catch {
                orderEmailMessage = "Échec envoi : \(error.localizedDescription)"
            }
            sendingOrderEmail = nil
        }
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

/// Édition du logo d'une fiche tiers (société). Le logo est persisté
/// sur le DirectoryEntry et réutilisé automatiquement en en-tête du PDF
/// des factures émises par cette société.
struct PartyLogoEditor: View {
    let entry: DirectoryEntry
    @EnvironmentObject var directory: PartyDirectory
    @Binding var isPresented: Bool

    private var currentLogo: Data? { entry.logoData }

    var body: some View {
        VStack(spacing: 16) {
            Text("Logo « \(entry.displayName) »").font(.headline)
            Text("Image (PNG, JPEG ou TIFF) affichée en en-tête du PDF lisible des factures émises par cette société. Le logo n'est pas embarqué dans le XML Factur-X.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)

            if let data = currentLogo, let img = NSImage(data: data) {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 220, maxHeight: 90)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).stroke(.secondary, lineWidth: 0.5))
                Text("Logo chargé (\(data.count) octets)").font(.caption2).foregroundStyle(.secondary)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("Aucun logo pour cette société").font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Button {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.png, .jpeg, .tiff]
                    panel.allowsMultipleSelection = false
                    panel.canChooseDirectories = false
                    if panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) {
                        var e = entry
                        e.logoData = data
                        directory.upsert(e)
                    }
                } label: { Label(currentLogo == nil ? "Choisir une image…" : "Remplacer…", systemImage: "folder") }
                .buttonStyle(.bordered)

                if currentLogo != nil {
                    Button(role: .destructive) {
                        var e = entry
                        e.logoData = nil
                        directory.upsert(e)
                    } label: { Label("Retirer", systemImage: "trash") }
                        .buttonStyle(.bordered)
                }
            }

            Spacer()
            Button("Fermer") { isPresented = false }
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(width: 420, height: 320)
    }
}

struct InvoicePreviewSheet: View {
    let pdfData: Data?
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Aperçu — \(title)").font(.headline)
                Spacer()
                Button("Fermer") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(12)
            Divider()
            if let data = pdfData, let document = PDFDocument(data: data) {
                PDFKitView(document: document)
            } else {
                Text("Aucun aperçu disponible.").foregroundStyle(.secondary)
                Spacer()
            }
        }
        .frame(minWidth: 640, minHeight: 720)
    }
}

struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = document
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document !== document {
            nsView.document = document
        }
    }
}
