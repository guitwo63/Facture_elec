import SwiftUI
import FacturXCore
import AppKit
import PDFKit
import UniformTypeIdentifiers



/// Style de bouton uniforme pour les barres d'action (taille et forme identiques,
/// seule la couleur varie) : rempli pour l'action principale, liseré + fond très
/// légèrement teinté sinon.



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
    @StateObject private var auditActionLabelStore = AuditActionLabelStore.shared
    @StateObject private var superPDPStatusCodeStore = SuperPDPStatusCodeStore.shared
    @StateObject private var purchaseInvoiceStore = PurchaseInvoiceStore.shared
    @StateObject private var purchaseInvoiceStatusStore = PurchaseInvoiceStatusStore.shared
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
                .environmentObject(auditActionLabelStore)
                .environmentObject(superPDPStatusCodeStore)
                .environmentObject(purchaseInvoiceStore)
                .environmentObject(purchaseInvoiceStatusStore)
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
                    purchaseInvoiceStore.audit = AuditStore.shared
                    store.actorName = auth.currentUser?.username ?? "system"
                    orderStore.actorName = auth.currentUser?.username ?? "system"
                    quoteStore.actorName = auth.currentUser?.username ?? "system"
                    directory.actorName = auth.currentUser?.username ?? "system"
                    purchaseInvoiceStore.actorName = auth.currentUser?.username ?? "system"
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
    case purchases = "Achats"
    case dashboard = "Tableau de bord"
    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .directory: return "person.crop.rectangle.stack"
        case .quotes: return "doc.text.below.ecg"
        case .orders: return "cart.fill"
        case .invoices: return "doc.text.fill"
        case .purchases: return "cart.badge.clock"
        case .dashboard: return "gauge"
        }
    }

    static func visible(for role: UserRole?, modules: ModuleSettings = ModuleStore.shared.settings) -> [RootTab] {
        var result: [RootTab]
        switch role {
        // Le rôle acheteur garde l'onglet Ventes (déjà son point d'entrée avant l'existence
        // du module Achats) et gagne Achats en plus — jamais retiré un accès existant sans
        // qu'on le demande explicitement.
        case .acheteur:
            result = [.orders, .purchases]
        default:
            result = allCases
        }
        if !modules.ordersEnabled { result.removeAll { $0 == .orders } }
        if !modules.quotesEnabled { result.removeAll { $0 == .quotes } }
        if !modules.purchasesEnabled { result.removeAll { $0 == .purchases } }
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

    private var caFactureInvoices: [Invoice] { periodInvoices }
    private var encaisseInvoices: [Invoice] { periodInvoices.filter { $0.status == .paid } }
    private var enRetardInvoices: [Invoice] { sentInvoices.filter(\.isOverdue) }
    private var enAttenteInvoices: [Invoice] { sentInvoices.filter { $0.status != .paid && !$0.isOverdue } }
    /// Factures au statut « Validée (non envoyée) » : verrouillées côté saisie mais pas
    /// encore engagées vis-à-vis du client — exclues de `sentInvoices`, donc absentes
    /// des autres KPI. Utile pour repérer les factures prêtes qui attendent l'envoi.
    private var validatedNotSentInvoices: [Invoice] { activeInvoices.filter { $0.status == .issued } }

    private var caFacture: Double { caFactureInvoices.reduce(0) { $0 + signedAmount($1) } }
    private var encaisse: Double { encaisseInvoices.reduce(0) { $0 + signedAmount($1) } }
    private var enRetard: Double { enRetardInvoices.reduce(0) { $0 + signedAmount($1) } }
    private var enAttente: Double { enAttenteInvoices.reduce(0) { $0 + signedAmount($1) } }
    private var validatedNotSent: Double { validatedNotSentInvoices.reduce(0) { $0 + signedAmount($1) } }

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
                    kpiCard("CA facturé — \(period.rawValue)", caFacture, invoices: caFactureInvoices, color: .blue, icon: "chart.line.uptrend.xyaxis")
                    kpiCard("Encaissé — \(period.rawValue)", encaisse, invoices: encaisseInvoices, color: .green, icon: "checkmark.circle.fill")
                    kpiCard("En attente", enAttente, invoices: enAttenteInvoices, color: .orange, icon: "hourglass")
                    kpiCard("En retard", enRetard, invoices: enRetardInvoices, color: .red, icon: "exclamationmark.triangle.fill")
                    kpiCard("Validées, non envoyées", validatedNotSent, invoices: validatedNotSentInvoices, color: Color(hex: InvoiceStatus.issued.hexColor), icon: InvoiceStatus.issued.systemImage)
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

    private func kpiCard(_ title: String, _ amount: Double, invoices: [Invoice], color: Color, icon: String) -> some View {
        let invoiceCount = invoices.filter { !$0.type.isCreditNote }.count
        let creditNoteCount = invoices.filter { $0.type.isCreditNote }.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: icon).foregroundStyle(color)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Text(String(format: "%.2f %@", amount, currency))
                .font(.title2.bold())
            Text("\(pluralized(invoiceCount, "facture", "factures")) · \(pluralized(creditNoteCount, "avoir", "avoirs"))")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.12)))
    }

    private func pluralized(_ count: Int, _ singular: String, _ plural: String) -> String {
        "\(count) \(count > 1 ? plural : singular)"
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
    @EnvironmentObject var purchaseInvoiceStore: PurchaseInvoiceStore
    @EnvironmentObject var purchaseInvoiceStatusStore: PurchaseInvoiceStatusStore
    @StateObject private var pdpSync = PDPPeriodicSyncEngine()
    @StateObject private var purchaseReceptionSync = PurchasePDPReceptionEngine()
    @State private var tab: RootTab = .invoices
    @State private var didAttemptAutoBackup = false
    @State private var selectedID: UUID?
    @State private var selectedOrderID: UUID?
    @State private var selectedQuoteID: UUID?
    @State private var selectedPurchaseID: UUID?
    // Périmètre société actif, partagé par les 4 modules (Factures/Commandes/Devis/Achats) :
    // filtre leur liste et détermine la société assignée aux nouveaux documents créés depuis
    // leur bouton "Nouveau". nil = "Toutes les sociétés" (du périmètre visible de
    // l'utilisateur — voir `auth.visibleSocieties`). Initialisé une fois dans `.onAppear`
    // (dépend de `auth.currentUser`, indisponible à l'initialisation de l'état).
    @State private var activeCompanyID: UUID?
    @State private var didInitActiveCompanyID = false
    @State private var showSettings = false
    @State private var showUserManagement = false
    @State private var showEnvConfirm = false
    @State private var showSetupWizard = false
    @State private var setupWizardSkippedThisSession = false
    @State private var showFullSettingsWizard = false
    @State private var showConnectionStatus = false

    var body: some View {
        Group {
            if auth.currentUser == nil {
                LoginView()
            } else if let user = auth.currentUser, !user.emailVerified, !auth.testBypassSecurity {
                // Toutes les fonctions de l'application sont bloquées tant que l'email du
                // compte n'est pas validé — seule cette fenêtre (saisie/renvoi du code) est
                // accessible. `testBypassSecurity` contourne ce blocage, comme pour
                // `mustChangePassword` dans LoginView, pour ne pas gêner la mise au point.
                EmailVerificationGateView(user: user)
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
        purchaseInvoiceStore.load()
        purchaseInvoiceStatusStore.load()
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
        purchaseInvoiceStore.audit = AuditStore.shared
        auth.reloadEnvironment()
        store.actorName = auth.currentUser?.username ?? "system"
        orderStore.actorName = auth.currentUser?.username ?? "system"
        quoteStore.actorName = auth.currentUser?.username ?? "system"
        directory.actorName = auth.currentUser?.username ?? "system"
        purchaseInvoiceStore.actorName = auth.currentUser?.username ?? "system"
        selectedID = nil
        selectedOrderID = nil
        selectedPurchaseID = nil
        // La société active peut ne pas exister dans l'environnement qu'on vient de charger
        // (UUID propres à chaque environnement test/production) — resemée immédiatement,
        // comme au premier .onAppear (qui ne se redéclenche pas ici : la vue reste montée,
        // seules ses données sont rechargées).
        activeCompanyID = (auth.currentUser?.isAdmin == true) ? nil : defaultDraftCompanyID()
        didInitActiveCompanyID = true
        // Les identifiants SUPER PDP sont propres à l'environnement (test/production) :
        // un cycle de synchronisation en cours avec les anciens identifiants n'a plus de
        // sens après une bascule — on relance avec ceux qui viennent d'être rechargés.
        pdpSync.stop()
        pdpSync.start(store: store) { companyID in superPDPSettings.credentials(for: companyID) }
        purchaseReceptionSync.stop()
        purchaseReceptionSync.start(
            store: purchaseInvoiceStore,
            defaultCredentials: { superPDPSettings.credentials },
            credentialsBySociety: { superPDPSettings.credentialsBySociety }
        )
    }

    /// Migration Keychain one-shot par clé, jamais rejouée ensuite — voir le commentaire
    /// de `SMTPSettings.migrateFromKeychainOnce`. Utilisée ici pour les rechargements
    /// déclenchés par une bascule d'environnement (test/production), qui ne passent pas
    /// par `XSettings.init()` mais lisent UserDefaults directement.
    private func keychainMigrationAlreadyDone(_ doneKey: String) -> Bool {
        UserDefaults.standard.bool(forKey: doneKey)
    }

    private func markKeychainMigrationDone(_ doneKey: String) {
        UserDefaults.standard.set(true, forKey: doneKey)
    }

    private func reloadChorusCredentials() -> ChorusProCredentials {
        let k = appEnv.key("facturx.choruspro.credentials.v1")
        var result = ChorusProCredentials(clientID: "", clientSecret: "")
        if let data = UserDefaults.standard.data(forKey: k),
           let decoded = try? JSONDecoder().decode(ChorusProCredentials.self, from: data) {
            result = decoded
        }
        let doneKey = appEnv.key("facturx.choruspro.keychainCleanupDone.v1")
        if !keychainMigrationAlreadyDone(doneKey) {
            if result.clientSecret.isEmpty, let migrated = KeychainStore.get(forKey: appEnv.key("facturx.choruspro.clientSecret.v1")), !migrated.isEmpty {
                result.clientSecret = migrated
            }
            if result.techPassword.isEmpty, let migrated = KeychainStore.get(forKey: appEnv.key("facturx.choruspro.techPassword.v1")), !migrated.isEmpty {
                result.techPassword = migrated
            }
            KeychainStore.delete(forKey: appEnv.key("facturx.choruspro.clientSecret.v1"))
            KeychainStore.delete(forKey: appEnv.key("facturx.choruspro.techPassword.v1"))
            markKeychainMigrationDone(doneKey)
        }
        return result
    }

    private func reloadSuperPDPCredentials() -> SuperPDPCredentials {
        let k = appEnv.key("facturx.superpdp.credentials.v1")
        var result = SuperPDPCredentials(clientID: "", clientSecret: "")
        if let data = UserDefaults.standard.data(forKey: k),
           let decoded = try? JSONDecoder().decode(SuperPDPCredentials.self, from: data) {
            result = decoded
        }
        let doneKey = appEnv.key("facturx.superpdp.keychainCleanupDone.v1")
        if !keychainMigrationAlreadyDone(doneKey) {
            if result.clientSecret.isEmpty, let migrated = KeychainStore.get(forKey: appEnv.key("facturx.superpdp.clientSecret.v1")), !migrated.isEmpty {
                result.clientSecret = migrated
            }
            KeychainStore.delete(forKey: appEnv.key("facturx.superpdp.clientSecret.v1"))
            markKeychainMigrationDone(doneKey)
        }
        return result
    }

    private func reloadSMTPCredentials() -> SMTPCredentials {
        let k = appEnv.key("facturx.smtp.credentials.v1")
        var result = SMTPCredentials()
        if let data = UserDefaults.standard.data(forKey: k),
           let decoded = try? JSONDecoder().decode(SMTPCredentials.self, from: data) {
            result = decoded
        }
        let doneKey = appEnv.key("facturx.smtp.keychainCleanupDone.v1")
        if !keychainMigrationAlreadyDone(doneKey) {
            if result.password.isEmpty, let migrated = KeychainStore.get(forKey: appEnv.key("facturx.smtp.password.v1")), !migrated.isEmpty {
                result.password = migrated
            }
            KeychainStore.delete(forKey: appEnv.key("facturx.smtp.password.v1"))
            markKeychainMigrationDone(doneKey)
        }
        return result
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
                if !auth.visibleSocieties(for: auth.currentUser).isEmpty {
                    Divider().frame(height: 20).padding(.horizontal, 4)
                    HStack(spacing: 3) {
                        Picker("Société (périmètre)", selection: $activeCompanyID) {
                            Text("Toutes les sociétés").tag(UUID?.none)
                            ForEach(auth.visibleSocieties(for: auth.currentUser)) { s in
                                Text(s.displayName).tag(UUID?.some(s.id))
                            }
                        }.frame(width: 280)
                        InfoBadge(text: "Société active : filtre les listes de Factures/Commandes/Devis/Achats et détermine la société assignée aux nouveaux documents créés depuis leur bouton « Nouveau ». « Toutes les sociétés » n'affecte que l'affichage.")
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
                            activeCompanyID = nil
                            didInitActiveCompanyID = false
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
                    showConnectionStatus = true
                } label: {
                    Image(systemName: allConnectionsConfigured ? "checkmark.circle" : "exclamationmark.circle")
                        .font(.title2)
                        .foregroundStyle(allConnectionsConfigured ? Color.secondary : Color.orange)
                }
                .buttonStyle(.borderless)
                .help("État des connexions distantes activées")
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
                InvoicesTabView(selectedID: $selectedID, companyFilter: $activeCompanyID)
            case .orders:
                OrdersTabView(selectedID: $selectedOrderID, companyFilter: $activeCompanyID)
            case .quotes:
                QuotesTabView(selectedID: $selectedQuoteID, rootTab: $tab, invoiceSelectedID: $selectedID, orderSelectedID: $selectedOrderID, companyFilter: $activeCompanyID)
            case .purchases:
                PurchasesTabView(selectedID: $selectedPurchaseID, companyFilter: $activeCompanyID)
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
        .sheet(isPresented: $showConnectionStatus) {
            ConnectionStatusView(pdpSync: pdpSync, purchaseReceptionSync: purchaseReceptionSync)
        }
        .onReceive(NotificationCenter.default.publisher(for: .newInvoiceRequested)) { _ in
            tab = .invoices
            let draft = store.newDraft(companyID: activeCompanyID ?? defaultDraftCompanyID(),
                                       preferredSellerEntryID: auth.currentUser?.defaultSellerEntryID)
            store.upsert(draft)
            selectedID = draft.id
        }
        .onReceive(NotificationCenter.default.publisher(for: .newOrderRequested)) { _ in
            tab = .orders
            let draft = orderStore.newDraft(preferredSellerEntryID: auth.currentUser?.defaultSellerEntryID, companyID: activeCompanyID ?? defaultDraftCompanyID())
            orderStore.upsert(draft)
            selectedOrderID = draft.id
        }
        .onAppear {
            if auth.currentUser?.role == .acheteur, !RootTab.visible(for: .acheteur, modules: moduleStore.settings).contains(tab) {
                tab = .orders
            }
            if !didInitActiveCompanyID {
                activeCompanyID = (auth.currentUser?.isAdmin == true) ? nil : defaultDraftCompanyID()
                didInitActiveCompanyID = true
            }
            syncAuditActor()
            maybeShowSetupWizard()
            runAutoBackupIfNeeded()
            pdpSync.start(store: store) { companyID in superPDPSettings.credentials(for: companyID) }
            purchaseReceptionSync.start(
                store: purchaseInvoiceStore,
                defaultCredentials: { superPDPSettings.credentials },
                credentialsBySociety: { superPDPSettings.credentialsBySociety }
            )
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
        guard !directory.entries.contains(where: { $0.kinds.contains(.societe) }) else { return }
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
        let bundle = BackupService.capture(invoiceStore: store, orderStore: orderStore, quoteStore: quoteStore, directory: directory, purchaseInvoiceStore: purchaseInvoiceStore)
        Task {
            do {
                let summary = try await BackupRunner.run(bundle: bundle, pcloudCredentials: credentials, strategy: strategy)
                store.audit?.record(actor: "system", action: "backup_auto_launch_success", target: "", details: summary)
            } catch {
                store.audit?.record(actor: "system", action: "backup_auto_launch_failed", target: "", details: error.localizedDescription)
            }
        }
    }

    /// Configuration (pas connectivité live) des services distants activés — un simple
    /// repère dans l'en-tête, le test réel se fait à l'ouverture de ConnectionStatusView.
    /// PDP ne compte que s'il est activé (`usePDP`) : désactivé, il n'y a rien à signaler.
    private var allConnectionsConfigured: Bool {
        let pdpOK = !superPDPSettings.credentials.usePDP || superPDPSettings.credentials.isConfigured
        return pdpOK && pcloudSettings.credentials.isConfigured
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

/// Témoin de configuration + test pour les services distants activés (SUPER PDP, pCloud,
/// Chorus Pro/PISTE, SMTP — voir `visibleRows`, qui masque les non activés). Le test se
/// lance automatiquement à l'ouverture pour les trois premiers (lecture seule côté API,
/// sans risque à répéter) ; SMTP reste manuel, son test envoyant un vrai email (Réglages >
/// Connexions > Alertes email).
struct ConnectionStatusView: View {
    @ObservedObject var pdpSync: PDPPeriodicSyncEngine
    @ObservedObject var purchaseReceptionSync: PurchasePDPReceptionEngine
    @EnvironmentObject var superPDPSettings: SuperPDPSettings
    @EnvironmentObject var pcloudSettings: PCloudSettings
    @EnvironmentObject var chorusSettings: ChorusProSettings
    @EnvironmentObject var smtpSettings: SMTPSettings
    @EnvironmentObject var store: InvoiceStore
    @EnvironmentObject var purchaseInvoiceStore: PurchaseInvoiceStore
    @Environment(\.dismiss) private var dismiss
    @State private var syncingNow = false
    @State private var syncingPurchasesNow = false

    @State private var pdpTesting = false
    @State private var pdpResult: String?
    @State private var pdpOK: Bool?

    @State private var pcloudTesting = false
    @State private var pcloudResult: String?
    @State private var pcloudOK: Bool?

    @State private var chorusTesting = false
    @State private var chorusResult: String?
    @State private var chorusOK: Bool?

    /// Seules les connexions réellement activées apparaissent : PDP se coupe entièrement
    /// via son interrupteur (`usePDP`) ; les autres n'ont pas d'interrupteur dédié, alors
    /// « activée » veut dire « des identifiants ont été saisis ».
    private var visibleRows: [AnyView] {
        var rows: [AnyView] = []
        if superPDPSettings.credentials.usePDP {
            rows.append(AnyView(connectionRow(
                name: "SUPER PDP", systemImage: "checkmark.shield",
                configured: superPDPSettings.credentials.isConfigured,
                testing: pdpTesting, result: pdpResult, ok: pdpOK, test: testSuperPDP
            )))
        }
        if pcloudSettings.credentials.isConfigured {
            rows.append(AnyView(connectionRow(
                name: "pCloud", systemImage: "icloud",
                configured: true,
                testing: pcloudTesting, result: pcloudResult, ok: pcloudOK, test: testPCloud
            )))
        }
        if chorusSettings.credentials.isConfigured {
            rows.append(AnyView(connectionRow(
                name: "Chorus Pro (PISTE)", systemImage: "network",
                configured: true,
                testing: chorusTesting, result: chorusResult, ok: chorusOK, test: testChorusPro
            )))
        }
        if smtpSettings.credentials.isConfigured {
            // Pas de test au clic ici : contrairement aux autres, tester SMTP envoie un
            // vrai email — l'automatiser à chaque ouverture du panneau serait intrusif.
            // Le test réel ("Envoyer un test") reste dans Réglages > Connexions > SMTP.
            rows.append(AnyView(connectionRow(
                name: "Alertes email (SMTP)", systemImage: "envelope",
                configured: true, testing: false, result: nil, ok: nil, test: nil
            )))
        }
        return rows
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("État des connexions").font(.title2.bold())
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    let rows = visibleRows
                    if rows.isEmpty {
                        Text("Aucune connexion externe activée.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                            row
                            if idx < rows.count - 1 { Divider() }
                        }
                    }
                    if superPDPSettings.credentials.usePDP {
                        Divider()
                        pdpSyncSection
                        Divider()
                        purchaseReceptionSection
                    }
                }
                .padding()
            }
        }
        .frame(width: 460, height: 480)
        // Lancé au clic sur l'icône "État des connexions" de la barre d'outils : consulter
        // le statut sans avoir en plus à cliquer "Tester" sur chaque ligne une par une.
        .task {
            if superPDPSettings.credentials.usePDP && superPDPSettings.credentials.isConfigured { testSuperPDP() }
            if pcloudSettings.credentials.isConfigured { testPCloud() }
            if chorusSettings.credentials.isConfigured { testChorusPro() }
        }
    }

    /// Statut de la synchronisation périodique des statuts SUPER PDP (factures déposées,
    /// pas encore à un statut terminal — voir `PDPPeriodicSyncEngine`). Cadence réglable
    /// dans Réglages > Application > SUPER PDP ; ce bouton permet de déclencher un cycle
    /// sans attendre le prochain.
    private var pdpSyncSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Synchronisation des statuts", systemImage: "arrow.triangle.2.circlepath").font(.headline)
                Spacer()
                if pdpSync.isRunning {
                    Label("Active", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.green)
                }
            }
            Text("Interroge SUPER PDP toutes les \(superPDPSettings.credentials.syncIntervalMinutes) min pour les factures déposées non encore à un statut terminal, et applique tout avancement reçu.")
                .font(.caption).foregroundStyle(.secondary)
            if let lastRun = pdpSync.lastRunAt {
                Text("Dernière synchronisation : \(lastRun.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let summary = pdpSync.lastRunSummary {
                Text(summary).font(.caption2).foregroundStyle(.secondary)
            }
            Button {
                syncingNow = true
                Task {
                    await pdpSync.runOnce(store: store) { companyID in superPDPSettings.credentials(for: companyID) }
                    syncingNow = false
                }
            } label: {
                if syncingNow {
                    HStack(spacing: 4) { ProgressView().controlSize(.small); Text("Synchronisation…") }
                } else {
                    Label("Synchroniser maintenant", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .disabled(syncingNow || !superPDPSettings.credentials.isConfigured)
        }
    }

    /// Statut de la réception automatique des factures d'achat (module Achats) — pendant de
    /// `pdpSyncSection` côté réception, même cadence partagée. Voir
    /// `PurchasePDPReceptionEngine`.
    private var purchaseReceptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Réception des factures d'achat", systemImage: "tray.and.arrow.down").font(.headline)
                Spacer()
                if purchaseReceptionSync.isRunning {
                    Label("Active", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.green)
                }
            }
            Text("Récupère automatiquement sur SUPER PDP les factures déposées par vos fournisseurs et les ajoute à Achats.")
                .font(.caption).foregroundStyle(.secondary)
            if let lastRun = purchaseReceptionSync.lastRunAt {
                Text("Dernière réception : \(lastRun.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let summary = purchaseReceptionSync.lastRunSummary {
                Text(summary).font(.caption2).foregroundStyle(.secondary)
            }
            Button {
                syncingPurchasesNow = true
                Task {
                    await purchaseReceptionSync.runOnce(
                        store: purchaseInvoiceStore,
                        defaultCredentials: superPDPSettings.credentials,
                        credentialsBySociety: superPDPSettings.credentialsBySociety
                    )
                    syncingPurchasesNow = false
                }
            } label: {
                if syncingPurchasesNow {
                    HStack(spacing: 4) { ProgressView().controlSize(.small); Text("Réception…") }
                } else {
                    Label("Recevoir maintenant", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .disabled(syncingPurchasesNow || !superPDPSettings.credentials.isConfigured)
        }
    }

    @ViewBuilder
    private func connectionRow(
        name: String, systemImage: String, configured: Bool,
        testing: Bool, result: String?, ok: Bool?, test: (() -> Void)?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(name, systemImage: systemImage).font(.headline)
                Spacer()
                if configured {
                    Label("Configuré", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.green)
                } else {
                    Label("Non configuré", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
                }
            }
            if let test {
                Button {
                    test()
                } label: {
                    if testing {
                        HStack(spacing: 4) { ProgressView().controlSize(.small); Text("Test…") }
                    } else {
                        Label("Tester la connexion", systemImage: "network")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(testing || !configured)
            }
            if let result {
                Text(result).font(.caption).foregroundStyle(ok == true ? .green : .red)
            }
        }
    }

    private func testSuperPDP() {
        pdpTesting = true
        pdpResult = nil
        let credentials = superPDPSettings.credentials
        Task {
            do {
                _ = try await SuperPDPService().fetchToken(credentials: credentials)
                pdpOK = true
                pdpResult = "Connexion réussie."
            } catch {
                pdpOK = false
                pdpResult = "Échec : \(error.localizedDescription)"
            }
            pdpTesting = false
        }
    }

    private func testPCloud() {
        pcloudTesting = true
        pcloudResult = nil
        let credentials = pcloudSettings.credentials
        Task {
            do {
                _ = try await PCloudService().login(credentials: credentials)
                pcloudOK = true
                pcloudResult = "Connexion réussie."
            } catch {
                pcloudOK = false
                pcloudResult = "Échec : \(error.localizedDescription)"
            }
            pcloudTesting = false
        }
    }

    private func testChorusPro() {
        chorusTesting = true
        chorusResult = nil
        let credentials = chorusSettings.credentials
        Task {
            do {
                _ = try await ChorusProService().fetchToken(credentials: credentials)
                chorusOK = true
                chorusResult = "Connexion réussie."
            } catch {
                chorusOK = false
                chorusResult = "Échec : \(error.localizedDescription)"
            }
            chorusTesting = false
        }
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

struct QuoteToOrderSheet: View {
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
                Text("Créer une commande depuis un devis").font(.headline)
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
                    Text("Aucun devis accepté disponible à transformer en commande dans votre périmètre.")
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
                Button("Créer la commande") {
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
    @Binding var companyFilter: UUID?
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
        if let cf = companyFilter {
            result = result.filter { $0.companyID == cf }
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
                    // Bouton scindé : le corps crée directement un brouillon (action la plus
                    // fréquente), la flèche ouvre les autres origines — remplace 4 boutons
                    // séparés qui finissaient tronqués dans la barre d'actions.
                    Menu {
                        if moduleStore.settings.ordersEnabled {
                            Button {
                                showOrderPicker = true
                            } label: { Label("Depuis une commande", systemImage: "cart") }
                        }
                        if moduleStore.settings.quotesEnabled {
                            Button {
                                showQuotePicker = true
                            } label: { Label("Depuis un devis", systemImage: "doc.text.below.ecg") }
                                .help("Convertit un devis accepté en facture")
                        }
                        Button {
                            showScanImport = true
                        } label: { Label("Scanner un document", systemImage: "doc.viewfinder") }
                            .help("Importer la photo/le scan d'un devis signé ou d'un bon de commande client pour pré-remplir une facture")
                    } label: {
                        Label("Nouvelle facture", systemImage: "plus")
                    } primaryAction: {
                        let draft = store.newDraft(companyID: companyFilter ?? defaultCompanyID(),
                                                   preferredSellerEntryID: auth.currentUser?.defaultSellerEntryID)
                        store.upsert(draft)
                        selectedID = draft.id
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Nouvelle facture vierge — flèche pour créer depuis une commande, un devis, ou en scannant un document")
                    Text("Factures").font(.title2.bold())
                    Button {
                        showQuickInvoiceWizard = true
                    } label: { Label("Facture guidée", systemImage: "wand.and.stars") }
                        .buttonStyle(.bordered)
                        .help("Créer une facture en quelques étapes avec le minimum d'informations")
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
                HStack(spacing: 12) {
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
                    Button {
                        showAdvancedFilters.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: showAdvancedFilters ? "chevron.down" : "chevron.right")
                                .font(.caption2).foregroundStyle(.secondary)
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.caption)
                            Text("Filtres avancés")
                                .font(.caption.bold())
                            Text("(\(activeAdvancedFilterCount))")
                                .font(.caption.bold())
                                .foregroundStyle(activeAdvancedFilterCount > 0 ? Color.accentColor : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
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
                if showAdvancedFilters {
                    HStack(alignment: .center, spacing: 12) {
                        advancedFilterRow(field: $advField1, value: $advValue1, index: 1)
                        advancedFilterRow(field: $advField2, value: $advValue2, index: 2)
                        advancedFilterRow(field: $advField3, value: $advValue3, index: 3)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 4)
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
                            let draft = store.newDraft(companyID: companyFilter ?? defaultCompanyID())
                            store.upsert(draft)
                            selectedID = draft.id
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { listProxy in
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
                    .onChange(of: selectedID) { newID in
                        // À la création d'une facture (insérée en tête de liste), le haut de la
                        // nouvelle ligne pouvait rester hors champ si la liste était défilée plus
                        // bas — on recentre explicitement sur la sélection. Le défilement est
                        // différé au prochain tour de boucle : appelé de façon synchrone depuis
                        // ce onChange, il s'exécute encore pendant le rappel délégué de la
                        // NSTableView sous-jacente et AppKit journalise une opération réentrante
                        // ("WARNING: Application performed a reentrant operation in its
                        // NSTableView delegate").
                        if let newID {
                            DispatchQueue.main.async {
                                withAnimation { listProxy.scrollTo(newID, anchor: .top) }
                            }
                        }
                    }
                    }
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
    /// cette seconde entrée n'invente pas une règle différente. Exclut aussi les devis
    /// déjà transformés en commande : la facture doit alors venir de la commande, pas
    /// court-circuiter la traçabilité en repartant directement du devis.
    private var scopedInvoiceableQuotes: [Quote] {
        var result = quoteStore.quotes.filter {
            $0.status == .accepted && $0.convertedInvoiceNumber == nil && $0.convertedOrderNumber == nil
        }
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
    /// Repliée par défaut en saisie (`locked` == false, pour ne pas encombrer un formulaire
    /// en cours de remplissage) ; forcée dépliée en lecture seule pour que le contenu déjà
    /// saisi reste consultable sans clic supplémentaire.
    @State private var isExpanded = false

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
        DisclosureGroup(isExpanded: Binding(
            get: { isExpanded || locked },
            set: { isExpanded = $0 }
        )) {
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
        } label: {
            Text(title)
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
    @EnvironmentObject var actionLabelStore: AuditActionLabelStore
    @State private var sendingInvoiceEmail = false
    @State private var showResendEmailConfirm = false
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
    /// facture. Le champ Échéance se grise alors (voir `dueDateIsComputedFromPreset`) :
    /// en mode Personnalisé, il reste modifiable manuellement.
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

    /// Vrai si le préréglage actif calcule réellement une échéance (jours nets /
    /// fin de mois + jours) — le champ Échéance se grise alors, pour éviter une
    /// saisie manuelle immédiatement écrasée par le prochain recalcul. Un
    /// préréglage sans règle (ex. "Comptant") ou le mode Personnalisé laissent
    /// le champ modifiable.
    private var dueDateIsComputedFromPreset: Bool {
        guard let id = paymentTermsPresetIDBinding.wrappedValue,
              let preset = paymentTermsStore.presets.first(where: { $0.id == id }) else { return false }
        if case .none = preset.dueRule { return false }
        return true
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
                if superPDPSettings.credentials(for: invoice.companyID).usePDP {
                    Button {
                        // Rafraîchit le statut (auparavant un bouton "Statut PDP" séparé
                        // dans la barre d'action) et ouvre l'historique en un seul clic :
                        // consulter l'historique sans le statut à jour n'avait pas grand
                        // sens, et inversement.
                        refreshSuperPDPStatus()
                        fetchPDPEvents()
                    } label: {
                        if superPDPSubmitting {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.callout)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(superPDPSubmitting
                              || ((invoice.superPDPRemoteID ?? superPDPSubmission?.remoteID ?? "").isEmpty)
                              || !superPDPSettings.credentials(for: invoice.companyID).isConfigured)
                    .help("Rafraîchir le statut et voir l'historique des événements SUPER PDP")
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
                    if superPDPSettings.credentials(for: invoice.companyID).usePDP {
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
                            .disabled(pdpValidating || !superPDPSettings.credentials(for: invoice.companyID).isConfigured)
                            .help("Valider le Factur-X sur SUPER PDP avant dépôt")
                    } else {
                        Button("Valider") { runValidation() }
                            .buttonStyle(ToolbarActionButtonStyle(tint: .blue))
                            .disabled(fieldLocked)
                    }
                    ForEach(configuredTransitions, id: \.self) { s in
                        Button {
                            // « Envoyée / en cours » ne doit jamais être qu'une étiquette : passer
                            // ce statut sans réellement déposer laissait croire la facture
                            // transmise alors qu'elle ne l'était pas, tout en la verrouillant
                            // (statut verrouillant) — ce qui bloquait ensuite le vrai bouton
                            // "Super PDP" (dépôt), y compris pour un administrateur. Le seul
                            // chemin valide vers ce statut est donc le dépôt réel.
                            if s == .sent, superPDPSettings.credentials(for: invoice.companyID).usePDP,
                               (invoice.superPDPRemoteID ?? superPDPSubmission?.remoteID ?? "").isEmpty {
                                depositToSuperPDP()
                            } else {
                                invoice.status = s
                            }
                        } label: {
                            Label(s.label, systemImage: s.systemImage)
                        }
                        .buttonStyle(ToolbarActionButtonStyle(tint: Color(hex: s.hexColor)))
                        .help("Passer au statut « \(s.label) »")
                    }
                    if invoice.type.isInternalCreditNote {
                        Button("Exporter PDF") { exportPlainPDF() }
                            .buttonStyle(ToolbarActionButtonStyle(tint: .blue, filled: true))
                    } else if superPDPSettings.credentials(for: invoice.companyID).usePDP {
                        Button {
                            depositToSuperPDP()
                        } label: { Label("Super PDP", systemImage: "paperplane.fill") }
                            .buttonStyle(ToolbarActionButtonStyle(tint: .blue, filled: true))
                            // `fieldLocked` intègre déjà `statusLocked` (verrouillé sauf
                            // administrateur ayant confirmé "Modifier quand même") : le vérifier
                            // une seconde fois ici rendait ce bouton définitivement inaccessible
                            // dès que le statut verrouille la facture, même pour un administrateur
                            // — empêchant justement de corriger une facture restée bloquée à tort
                            // au statut « Transmise au PDP » sans dépôt réel.
                            .disabled(fieldLocked || superPDPSubmitting || !superPDPSettings.credentials(for: invoice.companyID).isConfigured || !isAdmin)
                            .help(isAdmin
                                  ? "Déposer la facture Factur-X sur SUPER PDP (Plateforme Agréée)"
                                  : "Réservé aux administrateurs : dépôt réglementaire sur SUPER PDP (Plateforme Agréée)")
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
                        if superPDPSettings.credentials(for: invoice.companyID).usePDP {
                            Divider()
                            Button {
                                downloadPDPInvoice()
                            } label: { Label("Copie PDP", systemImage: "square.and.arrow.down") }
                                .disabled(pdpDownloading
                                          || ((invoice.superPDPRemoteID ?? superPDPSubmission?.remoteID ?? "").isEmpty)
                                          || !superPDPSettings.credentials(for: invoice.companyID).isConfigured)
                                .help("Télécharger la copie de la facture déposée sur SUPER PDP")
                        }
                    } label: {
                        Label("Autre action", systemImage: "ellipsis.circle")
                    }
                    .buttonStyle(ToolbarActionButtonStyle(tint: .gray))
                    .help("Visualiser, exporter XML, générer le Factur-X, dupliquer, copie PDP…")
                }

                if emailTemplateStore.globalEnabled {
                    Divider().frame(height: 20)
                    Button {
                        if invoice.lastEmailSentAt != nil {
                            showResendEmailConfirm = true
                        } else {
                            sendInvoiceEmail()
                        }
                    } label: {
                        if sendingInvoiceEmail {
                            HStack(spacing: 4) { ProgressView().controlSize(.small); Text("Envoi…") }
                        } else {
                            Label("Envoyer la facture", systemImage: EmailTemplateKind.invoiceSent.systemImage)
                        }
                    }
                    .buttonStyle(ToolbarActionButtonStyle(tint: .blue))
                    .disabled(sendingInvoiceEmail
                              || !emailTemplateStore.isSendEnabled(.invoiceSent, companyID: invoice.companyID)
                              || (invoice.buyer.contactEmail ?? "").isEmpty
                              || !smtpSettings.credentials(for: invoice.companyID).isConfigured)
                    .help(!emailTemplateStore.template(for: .invoiceSent, companyID: invoice.companyID).enabled
                          ? "Cet email est désactivé (Réglages > Application)"
                          : (invoice.buyer.contactEmail ?? "").isEmpty
                          ? "Aucune adresse email cliente renseignée"
                          : !smtpSettings.credentials(for: invoice.companyID).isConfigured
                          ? "Configurez l'envoi d'email (Réglages) pour envoyer la facture"
                          : "Envoyer la facture par email au client")
                    .confirmationDialog(
                        "Cette facture a déjà été envoyée le \(invoice.lastEmailSentAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "")",
                        isPresented: $showResendEmailConfirm, titleVisibility: .visible
                    ) {
                        Button("Envoyer quand même") { sendInvoiceEmail() }
                        Button("Annuler", role: .cancel) {}
                    }
                    if let sentAt = invoice.lastEmailSentAt {
                        Text("Envoyée le \(sentAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }

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
                                      || !emailTemplateStore.isSendEnabled(.invoiceReminder, companyID: invoice.companyID)
                                      || (invoice.buyer.contactEmail ?? "").isEmpty
                                      || !smtpSettings.credentials(for: invoice.companyID).isConfigured)
                            .help(!emailTemplateStore.template(for: .invoiceReminder, companyID: invoice.companyID).enabled
                                  ? "Les relances sont désactivées (Réglages > Application)"
                                  : (invoice.buyer.contactEmail ?? "").isEmpty
                                  ? "Aucune adresse email cliente renseignée"
                                  : !smtpSettings.credentials(for: invoice.companyID).isConfigured
                                  ? "Configurez l'envoi d'email (Réglages) pour envoyer une relance"
                                  : "Envoyer un email de relance au client")
                        }
                    }
                }

                if isAdmin {
                    let forceable = InvoiceStatus.allCases.filter { $0 != invoice.status && !configuredTransitions.contains($0) }
                    if !forceable.isEmpty || superPDPSettings.credentials(for: invoice.companyID).usePDP {
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
                            if superPDPSettings.credentials(for: invoice.companyID).usePDP {
                                Button {
                                    notifyPDPStatusChange(to: invoice.status, force: true)
                                } label: {
                                    Label("Forcer renvoi", systemImage: "arrow.clockwise.circle")
                                }
                                .buttonStyle(ToolbarActionButtonStyle(tint: .red))
                                .disabled(((invoice.superPDPRemoteID ?? superPDPSubmission?.remoteID ?? "").isEmpty)
                                          || !superPDPSettings.credentials(for: invoice.companyID).isConfigured)
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
                                            InfoBadge(text: "BT-9 — Date d'échéance du paiement. Calculée automatiquement par le préréglage de conditions de paiement sélectionné ; modifiable uniquement en mode « Personnalisé ».")
                                        }
                                        DatePicker("", selection: $invoice.dueDate, displayedComponents: .date).labelsHidden()
                                            .disabled(fieldLocked || dueDateIsComputedFromPreset)
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
                                    if paymentTermsPresetIDBinding.wrappedValue == nil {
                                        TextField("Ex. Paiement à 30 jours", text: Binding($invoice.paymentTerms, replacingNilWith: ""))
                                            .textFieldStyle(.roundedBorder)
                                            .font(.callout)
                                            .frame(maxWidth: 260)
                                            .disabled(fieldLocked)
                                    } else {
                                        Text(invoice.paymentTerms ?? "")
                                            .font(.caption).foregroundStyle(.secondary)
                                            .frame(maxWidth: 260, alignment: .leading)
                                    }
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
                                    VATRatePicker(rate: $line.vatRate)
                                    InfoBadge(text: "BT-151 — Taux de TVA appliqué (%). Catégorie et motif d'exonération réglables ci-dessous pour un taux à 0 %.")
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
                            .onChange(of: line.vatRate) { newRate in
                                line.vatCategory = newRate == 0 ? .zeroRated : .standard
                                if newRate != 0 { line.vatExemptionReason = nil }
                            }
                            // Catégorie/motif d'exonération : uniquement pertinents à taux 0 % (autoliquidation,
                            // export, exonération…) — masqués pour le cas standard afin de ne pas allonger
                            // la ligne pour rien.
                            if line.vatRate == 0 {
                                HStack(spacing: 8) {
                                    HStack(spacing: 2) {
                                        Picker("", selection: $line.vatCategory) {
                                            ForEach(VATCategory.allCases, id: \.self) { cat in
                                                Text("\(cat.rawValue) — \(cat.label)").tag(cat)
                                            }
                                        }
                                        .labelsHidden()
                                        .frame(width: 210)
                                        InfoBadge(text: "BT-151 — Catégorie de TVA : S = normal, Z = taux zéro, AE = autoliquidation, K = livraison intracommunautaire, G = exportation hors UE, E = exonérée, O = hors champ.")
                                    }
                                    if line.vatCategory.requiresExemptionReason {
                                        HStack(spacing: 2) {
                                            TextField("Motif d'exonération (BT-120)", text: Binding($line.vatExemptionReason, replacingNilWith: ""))
                                                .frame(minWidth: 280)
                                            InfoBadge(text: "BT-120 — Motif d'exonération, obligatoire pour cette catégorie de TVA.")
                                        }
                                    }
                                }
                                .padding(.leading, 4)
                            }
                            OptionalFieldsSection(fields: $line.optionalFields, location: .line, locked: fieldLocked)
                                .padding(.leading, 4)
                        }
                        Button {
                            invoice.lines.append(InvoiceLine(name: "", quantity: 1, unitPrice: 0, vatRate: invoice.lines.last?.vatRate ?? 20))
                        } label: { Label("Ajouter une ligne", systemImage: "plus") }
                    }.padding(8)
                }.lockable(fieldLocked)

                GroupBox {
                    DisclosureGroup(isExpanded: Binding(
                        // Forcée dépliée en lecture seule : les mentions légales et les notes
                        // libres sont des champs saisis, pas de la documentation statique —
                        // à consulter sans clic supplémentaire une fois la facture verrouillée.
                        get: { showLegalMentions || fieldLocked },
                        set: { showLegalMentions = $0 }
                    )) {
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
                AttachmentsAndCommentSection(attachments: $invoice.attachments, internalComment: $invoice.internalComment, locked: fieldLocked)
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
            exportError = "Validation échouée : \(preCheck.totalErrorCount) erreur(s). Corrigez avant de générer."
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
        if invoice.status == .accepted || invoice.status == .partiallyPaid || invoice.status == .paid || invoice.status == .cancelled {
            superPDPMessage = "Dépôt refusé : la facture est déjà « \(invoice.status.label) ». Un dépôt n'est possible que depuis Brouillon / Validée / Transmise."
            return
        }
        superPDPSubmitting = true
        superPDPMessage = nil
        let preCheck = FacturXValidator().validate(invoice: invoice)
        if !preCheck.isValid {
            validation = preCheck
            showValidation = true
            superPDPMessage = "Validation échouée : \(preCheck.totalErrorCount) erreur(s). Corrigez avant de déposer."
            superPDPSubmitting = false
            return
        }
        Task {
            do {
                let facturx = try FacturXGenerator().generate(invoice: invoice, logo: sellerLogo)
                let service = SuperPDPService()
                let submission = try await service.submitInvoice(fileData: facturx, credentials: superPDPSettings.credentials(for: invoice.companyID))
                superPDPSubmission = SuperPDPInvoiceSubmission(
                    id: submission.id, remoteID: submission.remoteID, status: submission.status,
                    enInvoiceRef: submission.enInvoiceRef, submittedAt: submission.submittedAt,
                    lastCheckedAt: submission.lastCheckedAt, message: submission.message, direction: .sent
                )
                if let rid = submission.remoteID, !rid.isEmpty {
                    invoice.superPDPRemoteID = rid
                    if invoice.status == .issued || invoice.status == .draft {
                        invoice.status = .sent
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

    private func refreshSuperPDPStatus() {
        guard let rid = (superPDPSubmission?.remoteID ?? invoice.superPDPRemoteID), !rid.isEmpty else { return }
        superPDPSubmitting = true
        let priorStatus = superPDPSubmission?.status
        Task {
            do {
                let service = SuperPDPService()
                let updated = try await service.getInvoiceStatus(remoteID: rid, credentials: superPDPSettings.credentials(for: invoice.companyID))
                superPDPSubmission = SuperPDPInvoiceSubmission(
                    id: updated.id, remoteID: updated.remoteID, status: updated.status,
                    enInvoiceRef: updated.enInvoiceRef, submittedAt: updated.submittedAt,
                    lastCheckedAt: updated.lastCheckedAt, message: updated.message, direction: .received
                )
                if let mapped = PDPStatusMapper.functionalTransition(for: updated.status) {
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
        guard superPDPSettings.credentials(for: invoice.companyID).isConfigured else {
            superPDPMessage = "Identifiants SUPER PDP non configurés."
            return
        }
        pdpDownloading = true
        superPDPMessage = nil
        Task {
            do {
                let service = SuperPDPService()
                let data = try await service.downloadInvoice(remoteID: rid, credentials: superPDPSettings.credentials(for: invoice.companyID))
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
        guard superPDPSettings.credentials(for: invoice.companyID).isConfigured else {
            superPDPMessage = "Identifiants SUPER PDP non configurés."
            return
        }
        pdpEventsLoading = true
        showPDPEvents = true
        Task {
            do {
                let service = SuperPDPService()
                let events = try await service.listInvoiceEvents(remoteID: rid, credentials: superPDPSettings.credentials(for: invoice.companyID))
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
        let credentials = smtpSettings.credentials(for: invoice.companyID)
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
        let credentials = smtpSettings.credentials(for: invoice.companyID)
        guard credentials.isConfigured else {
            invoiceEmailMessage = "Échec envoi : envoi d'email non configuré (Réglages)."
            return
        }
        let template = emailTemplateStore.template(for: .invoiceSent, companyID: invoice.companyID)
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
                invoice.lastEmailSentAt = Date()
            } catch {
                invoiceEmailMessage = "Échec envoi : \(error.localizedDescription)"
            }
            sendingInvoiceEmail = false
        }
    }

    private func validatePDP() {
        guard superPDPSettings.credentials(for: invoice.companyID).isConfigured else {
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
            superPDPMessage = "Validation locale échouée : \(preCheck.totalErrorCount) erreur(s). Corrigez avant la validation SUPER PDP."
            pdpValidating = false
            return
        }
        Task {
            do {
                let facturx = try FacturXGenerator().generate(invoice: invoice, logo: sellerLogo)
                let service = SuperPDPService()
                let report = try await service.validateInvoice(fileData: facturx, credentials: superPDPSettings.credentials(for: invoice.companyID))
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
        let smtp = smtpSettings.credentials(for: invoice.companyID)
        guard smtp.alertsEnabled, smtp.alertOnInvoiceStatusChange, smtp.isConfigured,
              [InvoiceStatus.accepted, .disputed, .refused, .partiallyPaid, .paid, .cancelled].contains(newStatus),
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
        guard superPDPSettings.credentials(for: invoice.companyID).isConfigured else { return }
        // "200" (sent) est posé par le dépôt lui-même (voir depositToSuperPDP) — jamais
        // envoyé séparément comme événement de statut.
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
                try await service.sendInvoiceEvent(remoteID: rid, statusCode: statusCode, credentials: superPDPSettings.credentials(for: invoice.companyID), reportedData: reported)
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
                                Text(actionLabelStore.label(for: e.action))
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
                        Label("OK — contrôlé en local", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                    } else {
                        Label("Pré-vérification locale : \(ruleErrors.count) erreur(s)", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    }
                    Spacer()
                    Button { showValidation = false } label: {
                        Image(systemName: "xmark.circle")
                    }.buttonStyle(.plain)
                }
                Text("Contrôles internes, non exhaustifs — seule la validation SUPER PDP ci-dessous fait foi.")
                    .font(.caption2).foregroundStyle(.secondary)
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
                // Le rapport dit non conforme mais n'a donné aucun détail structuré
                // (`subreports` absent ou vide côté SUPER PDP pour cette réponse précise) —
                // sans repli, l'utilisateur n'avait aucune piste (juste "0 erreur(s)").
                // On affiche au moins les champs bruts reçus, utiles pour diagnostiquer.
                if !report.isValid, report.errors.isEmpty, report.warnings.isEmpty {
                    Text("Le rapport SUPER PDP ne détaille pas la cause (aucun sous-rapport reçu). Champs bruts de la réponse :")
                        .font(.caption).foregroundStyle(.secondary)
                    if report.raw.isEmpty {
                        Text("(réponse vide)").font(.caption2).foregroundStyle(.secondary)
                    } else {
                        ForEach(report.raw.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            HStack(alignment: .top, spacing: 4) {
                                Text("\(key) :").font(.caption2.bold()).foregroundStyle(.secondary)
                                Text(value).font(.caption2).foregroundStyle(.secondary)
                            }
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
    @State private var electronicAddressChoices: [SuperPDPDirectoryEntry] = []
    @State private var pendingPartyForAddressChoice: InvoiceParty?

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
        .sheet(isPresented: Binding(
            get: { !electronicAddressChoices.isEmpty },
            set: { if !$0 { electronicAddressChoices = []; pendingPartyForAddressChoice = nil } }
        )) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Plusieurs adresses électroniques trouvées").font(.headline).padding(12)
                Text("Ce SIREN/SIRET correspond à plusieurs établissements sur SUPER PDP. Choisissez celle à enregistrer pour ce tiers.")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12)
                Divider().padding(.top, 8)
                List(electronicAddressChoices) { entry in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.name ?? entry.routingAddress ?? "(sans nom)").font(.body.bold())
                        Text(entry.routingAddress ?? "").font(.caption.monospaced()).foregroundStyle(.secondary)
                        if let addr = entry.addressLine, !addr.isEmpty {
                            Text([addr, entry.postcode, entry.city].compactMap { $0 }.joined(separator: " "))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { applyElectronicAddressChoice(entry) }
                }
            }
            .frame(width: 420, height: 340)
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
                let withAddress = results.filter { !($0.routingAddress ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
                let distinctAddresses = Set(withAddress.map { $0.routingAddress ?? "" })
                if distinctAddresses.count > 1 {
                    // Plusieurs adresses électroniques différentes trouvées pour ce SIREN/SIRET
                    // (plusieurs établissements, par ex.) : on ne peut pas en choisir une au
                    // hasard, l'utilisateur doit trancher — au lieu de prendre silencieusement
                    // la première, ce qui pouvait enregistrer la mauvaise adresse.
                    lookingUpElectronicAddress = false
                    pendingPartyForAddressChoice = p
                    electronicAddressChoices = withAddress
                    return
                } else if let match = withAddress.first {
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

    /// Choix retenu quand plusieurs adresses électroniques étaient disponibles pour le même
    /// SIREN/SIRET (plusieurs établissements) : reprend le flux normal avec l'adresse choisie.
    private func applyElectronicAddressChoice(_ match: SuperPDPDirectoryEntry) {
        guard var p = pendingPartyForAddressChoice else { return }
        p.endpointID = match.routingAddress
        p.endpointSchemeID = match.routingScheme?.trimmingCharacters(in: .whitespaces).isEmpty == false ? match.routingScheme! : "0225"
        electronicAddressChoices = []
        pendingPartyForAddressChoice = nil
        finishSaveToDirectory(p)
    }

    private func finishSaveToDirectory(_ p: InvoiceParty) {
        var entry = DirectoryEntry(kinds: [role.defaultKind], party: p)
        // L'adresse électronique trouvée était appliquée à `party.endpointID` mais jamais
        // recopiée dans `routingAddresses` (la liste gérée depuis la fiche tiers) : elle
        // semblait alors ne "rien avoir enregistré" une fois le tiers ouvert, malgré un
        // endpointID bien présent en mémoire au moment de la sauvegarde.
        let siren = (p.siren ?? "").filter { $0.isNumber }
        let siret = (p.siret ?? "").filter { $0.isNumber }
        let endpoint = (p.endpointID ?? "").trimmingCharacters(in: .whitespaces)
        if !endpoint.isEmpty, !siren.isEmpty {
            let format: RoutingAddressFormat = siret.count == 14 ? .sirenSiret : .siren
            entry.routingAddresses = [PartyRoutingAddress(
                format: format, siren: siren, siret: siret.count == 14 ? siret : nil,
                label: "SUPER PDP", isActive: true, isDefault: true
            )]
        }
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
            guard !$0.isArchived else { return false }
            if $0.kinds.contains(.interco) { return true }
            return role == .seller ? $0.kinds.contains(.societe) : $0.kinds.contains(.client)
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
                                        Text(entry.kindsLabel).font(.caption2)
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

/// Puce cliquable partagée par le multi-sélecteur de types (fiche tiers) et le filtre par
/// type (Annuaire) — même style, logique de bascule laissée à l'appelant car elle diffère
/// (la fiche impose au moins un type coché, le filtre autorise "aucun" = "Tous").
private struct KindChipToggle: View {
    let label: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.callout)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(isOn ? Color.accentColor.opacity(0.18) : Color.clear, in: Capsule())
                .overlay(Capsule().stroke(isOn ? Color.accentColor : Color.secondary.opacity(0.4)))
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
    }
}

/// Une capsule colorée par type cumulé sur un tiers (voir `DirectoryEntry.kinds`) — remplace
/// la capsule unique d'avant le multi-sélecteur. Vue dédiée (plutôt qu'un `ForEach` inline
/// dans chaque `HStack` appelante) : le vérificateur de types SwiftUI n'arrivait pas à
/// résoudre l'expression en un temps raisonnable une fois ce `ForEach` ajouté inline.
private struct KindBadges: View {
    let kinds: Set<DirectoryEntryKind>
    let kindColors: KindColorStore
    var font: Font = .caption2

    var body: some View {
        ForEach(DirectoryEntryKind.selectable.filter { kinds.contains($0) }, id: \.self) { kind in
            Text(kind.label).font(font)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(Color(hex: kindColors.hexColor(for: kind)).opacity(0.2), in: Capsule())
                .foregroundColor(Color(hex: kindColors.hexColor(for: kind)))
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
    /// Vide = "Tous" (tous les tiers hors sociétés du périmètre, comme avant) ; sinon un
    /// tiers est visible s'il porte au moins un des types cochés ici.
    @State private var kindFilters: Set<DirectoryEntryKind> = []

    private var canManageSocietes: Bool { auth.currentUser?.isAdmin == true }

    var filtered: [DirectoryEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var base = directory.entries.filter { showArchived || !$0.isArchived }
        base = base.filter { kindFilters.isEmpty ? !$0.kinds.contains(.societe) : !$0.kinds.isDisjoint(with: kindFilters) }
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
                    HStack(spacing: 6) {
                        KindChipToggle(label: "Tous", isOn: kindFilters.isEmpty) {
                            kindFilters = []
                        }
                        ForEach([DirectoryEntryKind.client, .fournisseur, .interco], id: \.self) { kind in
                            KindChipToggle(label: kind.label, isOn: kindFilters.contains(kind)) {
                                if kindFilters.contains(kind) { kindFilters.remove(kind) }
                                else { kindFilters.insert(kind) }
                            }
                        }
                    }
                    Spacer()
                    Button { showImport = true } label: { Label("Importer", systemImage: "square.and.arrow.down") }
                        .buttonStyle(.bordered)
                    Button { showExport = true } label: { Label("Exporter", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.bordered)
                    Toggle(isOn: $showArchived) {
                        Label("Archives", systemImage: "archivebox")
                    }
                    .toggleStyle(.switch)
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
                                KindBadges(kinds: entry.kinds, kindColors: kindColors)
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
        if entry.kinds.contains(.societe) { return canManageSocietes }
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
                    KindBadges(kinds: entry.kinds, kindColors: kindColors, font: .caption)
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
                        detailRow("Type", entry.kindsLabel)
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
                        if entry.isPayee {
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
                        HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
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
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if !entry.isSupplierOnly {
                        VStack(alignment: .leading, spacing: 8) {
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
                        .frame(maxWidth: .infinity, alignment: .leading)
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
        // Une société du périmètre est toujours aussi une partie liée aux autres sociétés
        // gérées dans l'app (même utilisateur, même périmètre) — cochée Interco par défaut,
        // modifiable ensuite comme n'importe quel autre type.
        let initialKinds: Set<DirectoryEntryKind> = initialKind == .societe ? [.societe, .interco] : [initialKind]
        var initial = DirectoryEntry(kinds: initialKinds, party: InvoiceParty(name: "", street: "", postcode: "", city: ""))
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
        if canManageSocietes { return DirectoryEntryKind.selectable }
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

            VStack(alignment: .leading, spacing: 4) {
                Text("Type").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(availableKinds, id: \.self) { kind in
                        KindChipToggle(label: kind.label, isOn: entry.kinds.contains(kind)) {
                            if entry.kinds.contains(kind) {
                                // Un tiers doit toujours garder au moins un type — on
                                // ignore silencieusement le dernier décochage plutôt que
                                // d'autoriser un ensemble vide dénué de sens.
                                if entry.kinds.count > 1 { entry.kinds.remove(kind) }
                            } else {
                                entry.kinds.insert(kind)
                            }
                        }
                    }
                    Spacer()
                }
            }

            if entry.kinds.contains(.client) {
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
                PartyEditorView(party: $entry.party, routingAddresses: $entry.routingAddresses, contacts: $entry.contacts, isSociete: entry.kinds.contains(.societe), hideBankDetails: !entry.isPayee, hideElectronicAddress: entry.isSupplierOnly)
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
        .onChange(of: entry.routingAddresses) { _ in
            // L'identifiant électronique affiché sur la fiche (BT-49/34, champ "Ident. élec.")
            // et la liste "Adresses de facturation électronique" ci-dessus pouvaient diverger :
            // modifier la liste (ajout, suppression, changement de défaut) ne rafraîchissait
            // jamais le champ sur le tiers, qui restait sur son ancienne valeur saisie ou
            // choisie précédemment. Recalé automatiquement sur l'adresse par défaut active.
            if let def = entry.defaultRoutingAddress, def.isActive {
                let composed = def.composedAddress.trimmingCharacters(in: .whitespaces)
                if !composed.isEmpty {
                    entry.party.endpointID = composed
                    entry.party.endpointSchemeID = "0225"
                }
            }
        }
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
                .toggleStyle(.switch)
            Toggle("Adresse par défaut", isOn: $draft.isDefault)
                .toggleStyle(.switch)
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
                TabItem(index: 5, label: "Connexions", icon: "network"),
                TabItem(index: 6, label: "Par société", icon: "building.2.crop.circle")
            ])
        }
        // Le journal (historique des statuts) est utile à tous les rôles, pas
        // seulement à l'administrateur : un comptable doit pouvoir suivre le
        // cycle de vie des factures/commandes/devis. `AuditLogView` masque de
        // son côté les entrées liées aux comptes utilisateurs pour les non-admins.
        items.append(TabItem(index: 3, label: "Journal", icon: "clock.arrow.circlepath"))
        if auth.currentUser?.isAdmin == true {
            items.append(TabItem(index: 4, label: "Données", icon: "externaldrive.fill"))
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
            case 5:
                ConnectionsSettingsView()
            case 6:
                ConfigureSocieteView()
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
        directory.entries.filter { $0.kinds.contains(.societe) }
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
                    TableColumn("Principale") { e in
                        Button {
                            if e.isPrincipale {
                                directory.clearPrincipale()
                            } else {
                                directory.setPrincipale(e.id)
                            }
                        } label: {
                            Image(systemName: e.isPrincipale ? "star.fill" : "star")
                                .foregroundStyle(e.isPrincipale ? .yellow : .secondary)
                        }
                        .buttonStyle(.borderless)
                        .help(e.isPrincipale
                            ? "Société principale — sert de repli pour les réglages par société non personnalisés. Cliquer pour retirer."
                            : "Définir comme société principale")
                    }
                    .width(min: 60, ideal: 70)
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
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var directory: PartyDirectory
    /// String et non EmailTemplateKind : Table exige que `selection` corresponde au
    /// type de `id` (String, via EmailTemplateKind.rawValue), pas au type de la ligne.
    @State private var selectedKind: String?
    @State private var editingKind: EmailTemplateKind?
    /// Société dont on édite/consulte les surcharges — `nil` = société principale (ou le
    /// réglage global si aucune n'est désignée). Même principe que `ValueTablesView`.
    @State private var societyID: UUID?

    /// Pré-sélectionne le picker société — voir `ValueTablesView.init(initialSocietyID:)`,
    /// même principe, utilisé par l'écran "Configurer une société" (F.3).
    init(initialSocietyID: UUID? = nil) {
        _societyID = State(initialValue: initialSocietyID)
    }

    private var noSelectionLabel: String {
        guard let principaleID = directory.principaleSocieteID,
              let principale = directory.entries.first(where: { $0.id == principaleID }) else {
            return "Toutes (réglage par défaut)"
        }
        return "Société principale : \(principale.displayName)"
    }

    private func overrideState(for kind: EmailTemplateKind) -> SocietyOverrideState {
        guard let cid = societyID else { return .none }
        if emailTemplateStore.templatesBySociety[cid]?.contains(where: { $0.kind == kind }) == true { return .customized }
        if let principaleID = directory.principaleSocieteID, principaleID != cid,
           emailTemplateStore.templatesBySociety[principaleID]?.contains(where: { $0.kind == kind }) == true {
            return .inheritedFromPrincipale
        }
        return .none
    }

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
            .help("Désactivé, tous les boutons d'envoi disparaissent de l'application, quel que soit le réglage de chaque email ci-dessous — réglage global, pas par société.")

            if !emailTemplateStore.globalEnabled {
                Label("Tous les boutons d'envoi sont masqués tant que c'est désactivé.", systemImage: "eye.slash")
                    .font(.caption).foregroundStyle(.orange)
            } else {
                if !auth.visibleSocieties(for: auth.currentUser).isEmpty {
                    HStack(spacing: 6) {
                        Text("Société").font(.caption).foregroundStyle(.secondary)
                        Picker("Société", selection: $societyID) {
                            Text(noSelectionLabel).tag(UUID?.none)
                            ForEach(auth.visibleSocieties(for: auth.currentUser)) { s in
                                Text(s.displayName).tag(UUID?.some(s.id))
                            }
                        }
                        .labelsHidden()
                        .frame(width: 260)
                    }
                }
                Table(EmailTemplateKind.allCases, selection: Binding(
                    get: { selectedKind },
                    set: { selectedKind = $0 }
                )) {
                    TableColumn("Email") { kind in
                        Label(kind.label, systemImage: kind.systemImage)
                    }
                    TableColumn("Activé") { kind in
                        Toggle("", isOn: Binding(
                            get: { emailTemplateStore.template(for: kind, companyID: societyID).enabled },
                            set: { newValue in
                                var t = emailTemplateStore.template(for: kind, companyID: societyID)
                                t.enabled = newValue
                                if let cid = societyID {
                                    emailTemplateStore.setOverride(t, companyID: cid)
                                } else {
                                    emailTemplateStore.upsert(t)
                                }
                            }
                        ))
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                    }
                    .width(60)
                    TableColumn("Sujet") { kind in
                        Text(kind.hasEditableContent ? emailTemplateStore.template(for: kind, companyID: societyID).subject : "3 modèles selon le niveau d'urgence")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    TableColumn("") { kind in
                        SocietyOverrideBadge(state: overrideState(for: kind)) {
                            if let cid = societyID {
                                emailTemplateStore.removeOverride(kind: kind, companyID: cid)
                            }
                        }
                    }
                    .width(min: 90, ideal: 140)
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
            EmailTemplateEditorSheet(kind: kind, societyID: societyID)
        }
    }
}

/// Édition du sujet/corps d'un email automatique. Les champs disponibles
/// ({{numero}}, {{client}}…) sont insérables par un clic — pas besoin de
/// connaître/taper la syntaxe des balises — plutôt qu'un champ de texte libre
/// qui suppose que l'utilisateur connaît déjà les noms de variables.
struct EmailTemplateEditorSheet: View {
    let kind: EmailTemplateKind
    /// `nil` = édite le réglage global (ou celui de la société principale à l'affichage,
    /// mais l'écriture cible toujours le global quand `nil` — voir `EmailTemplatesAdminView`).
    var societyID: UUID?
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
                    var t = emailTemplateStore.template(for: kind, companyID: societyID)
                    t.subject = subject
                    t.body = emailBody
                    if let cid = societyID {
                        emailTemplateStore.setOverride(t, companyID: cid)
                    } else {
                        emailTemplateStore.upsert(t)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 560, height: 520)
        .onAppear {
            let t = emailTemplateStore.template(for: kind, companyID: societyID)
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
    @EnvironmentObject var emailTemplateStore: EmailTemplateStore
    @EnvironmentObject var twoFactorSettings: TwoFactorSettings
    @EnvironmentObject var moduleStore: ModuleStore
    @EnvironmentObject var appEnv: AppEnvironment
    @EnvironmentObject var store: InvoiceStore
    @EnvironmentObject var orderStore: OrderStore
    @EnvironmentObject var quoteStore: QuoteStore
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var directory: PartyDirectory
    @State private var twoFactorExpanded = false
    @State private var envExpanded = true
    @State private var modulesExpanded = false
    @State private var emailTemplatesExpanded = false
    @State private var societiesExpanded = false
    @State private var numberingExpanded = false
    @State private var numberingCompanyID: UUID?
    @State private var orderNumberingExpanded = false
    @State private var orderNumberingCompanyID: UUID?
    @State private var quoteNumberingExpanded = false
    @State private var quoteNumberingCompanyID: UUID?
    @State private var editingSociety: DirectoryEntry?
    @State private var creatingSociety = false

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
                        Toggle("Achats", isOn: $moduleStore.settings.purchasesEnabled)
                            .toggleStyle(.switch)
                            .onChange(of: moduleStore.settings.purchasesEnabled) { _ in moduleStore.save() }
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


                DisclosureGroup(isExpanded: $numberingExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Personnalisez le format des numéros de facture. Le chrono s'incrémente automatiquement à chaque création et démarre au numéro de début défini. Le compteur est toujours indépendant par société émettrice ; le format (préfixe, année, séparateur) peut l'être aussi si une société a besoin d'une numérotation différente — sinon toutes les sociétés partagent le format par défaut.")
                            .font(.caption).foregroundStyle(.secondary)
                        let societies = auth.visibleSocieties(for: auth.currentUser)
                        if !societies.isEmpty {
                            Picker("Société", selection: $numberingCompanyID) {
                                Text(noSelectionNumberingLabel).tag(UUID?.none)
                                ForEach(societies) { c in
                                    Text(c.displayName).tag(UUID?.some(c.id))
                                }
                            }
                            if let cid = numberingCompanyID {
                                if store.numberFormatOverrides[cid] == nil {
                                    HStack(spacing: 6) {
                                        Text(directory.principaleSocieteID != nil && cid != directory.principaleSocieteID ? "Hérite actuellement de la société principale." : "Utilise actuellement le format par défaut.").font(.caption2).foregroundStyle(.secondary)
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
                            .toggleStyle(.switch)
                        HStack {
                            Text("Numéro de début").font(.caption)
                            Stepper(value: activeNumberingFormatBinding.start, in: 1...999999) {
                                Text("\(activeNumberingFormatBinding.wrappedValue.start)")
                            }
                        }
                        Toggle("Séparer par un \"-\"", isOn: activeNumberingFormatBinding.useSeparator)
                            .toggleStyle(.switch)
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

                DisclosureGroup(isExpanded: $orderNumberingExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Même principe que pour les factures : le compteur est toujours indépendant par société émettrice, le format (préfixe, année, séparateur) peut l'être aussi si besoin.")
                            .font(.caption).foregroundStyle(.secondary)
                        let societies = auth.visibleSocieties(for: auth.currentUser)
                        if !societies.isEmpty {
                            Picker("Société", selection: $orderNumberingCompanyID) {
                                Text(noSelectionNumberingLabel).tag(UUID?.none)
                                ForEach(societies) { c in
                                    Text(c.displayName).tag(UUID?.some(c.id))
                                }
                            }
                            if let cid = orderNumberingCompanyID {
                                if orderStore.numberFormatOverrides[cid] == nil {
                                    HStack(spacing: 6) {
                                        Text(directory.principaleSocieteID != nil && cid != directory.principaleSocieteID ? "Hérite actuellement de la société principale." : "Utilise actuellement le format par défaut.").font(.caption2).foregroundStyle(.secondary)
                                        Button("Personnaliser pour cette société") {
                                            orderStore.numberFormatOverrides[cid] = orderStore.numberingFormat(for: nil)
                                            orderStore.save()
                                        }.buttonStyle(.link).font(.caption2)
                                    }
                                } else {
                                    Button("Revenir au format par défaut", role: .destructive) {
                                        orderStore.numberFormatOverrides.removeValue(forKey: cid)
                                        orderStore.save()
                                    }.buttonStyle(.link).font(.caption2)
                                }
                            }
                        }
                        HStack {
                            Text("Préfixe texte").font(.caption)
                            TextField("ex. CD", text: activeOrderNumberingFormatBinding.prefix)
                                .frame(width: 140)
                        }
                        Toggle("Inclure l'année", isOn: activeOrderNumberingFormatBinding.includeYear)
                            .toggleStyle(.switch)
                        HStack {
                            Text("Numéro de début").font(.caption)
                            Stepper(value: activeOrderNumberingFormatBinding.start, in: 1...999999) {
                                Text("\(activeOrderNumberingFormatBinding.wrappedValue.start)")
                            }
                        }
                        Toggle("Séparer par un \"-\"", isOn: activeOrderNumberingFormatBinding.useSeparator)
                            .toggleStyle(.switch)
                        Divider()
                        HStack {
                            Text("Aperçu : ").font(.caption).foregroundStyle(.secondary)
                            Text(orderStore.previewNextNumber(companyID: orderNumberingCompanyID ?? previewCompanyID())).monospaced().font(.caption.bold())
                            Spacer()
                        }
                    }.padding(8)
                } label: {
                    Label("Numérotation des commandes", systemImage: "number")
                        .font(.headline)
                }

                DisclosureGroup(isExpanded: $quoteNumberingExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Même principe que pour les factures : le compteur est toujours indépendant par société émettrice, le format (préfixe, année, séparateur) peut l'être aussi si besoin.")
                            .font(.caption).foregroundStyle(.secondary)
                        let societies = auth.visibleSocieties(for: auth.currentUser)
                        if !societies.isEmpty {
                            Picker("Société", selection: $quoteNumberingCompanyID) {
                                Text(noSelectionNumberingLabel).tag(UUID?.none)
                                ForEach(societies) { c in
                                    Text(c.displayName).tag(UUID?.some(c.id))
                                }
                            }
                            if let cid = quoteNumberingCompanyID {
                                if quoteStore.numberFormatOverrides[cid] == nil {
                                    HStack(spacing: 6) {
                                        Text(directory.principaleSocieteID != nil && cid != directory.principaleSocieteID ? "Hérite actuellement de la société principale." : "Utilise actuellement le format par défaut.").font(.caption2).foregroundStyle(.secondary)
                                        Button("Personnaliser pour cette société") {
                                            quoteStore.numberFormatOverrides[cid] = quoteStore.numberingFormat(for: nil)
                                            quoteStore.save()
                                        }.buttonStyle(.link).font(.caption2)
                                    }
                                } else {
                                    Button("Revenir au format par défaut", role: .destructive) {
                                        quoteStore.numberFormatOverrides.removeValue(forKey: cid)
                                        quoteStore.save()
                                    }.buttonStyle(.link).font(.caption2)
                                }
                            }
                        }
                        HStack {
                            Text("Préfixe texte").font(.caption)
                            TextField("ex. DEV", text: activeQuoteNumberingFormatBinding.prefix)
                                .frame(width: 140)
                        }
                        Toggle("Inclure l'année", isOn: activeQuoteNumberingFormatBinding.includeYear)
                            .toggleStyle(.switch)
                        HStack {
                            Text("Numéro de début").font(.caption)
                            Stepper(value: activeQuoteNumberingFormatBinding.start, in: 1...999999) {
                                Text("\(activeQuoteNumberingFormatBinding.wrappedValue.start)")
                            }
                        }
                        Toggle("Séparer par un \"-\"", isOn: activeQuoteNumberingFormatBinding.useSeparator)
                            .toggleStyle(.switch)
                        Divider()
                        HStack {
                            Text("Aperçu : ").font(.caption).foregroundStyle(.secondary)
                            Text(quoteStore.previewNextNumber(companyID: quoteNumberingCompanyID ?? previewCompanyID())).monospaced().font(.caption.bold())
                            Spacer()
                        }
                    }.padding(8)
                } label: {
                    Label("Numérotation des devis", systemImage: "number")
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

    /// Libellé de l'option "pas de société sélectionnée" des 3 pickers de numérotation —
    /// voir `ValueTablesView.noSelectionLabel`, même principe.
    private var noSelectionNumberingLabel: String {
        guard let principaleID = directory.principaleSocieteID,
              let principale = directory.entries.first(where: { $0.id == principaleID }) else {
            return "Toutes (format par défaut)"
        }
        return "Société principale : \(principale.displayName)"
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

    private var activeOrderNumberingFormatBinding: Binding<InvoiceNumberingFormat> {
        Binding(
            get: {
                guard let cid = orderNumberingCompanyID else { return orderStore.numberingFormat(for: nil) }
                return orderStore.numberFormatOverrides[cid] ?? orderStore.numberingFormat(for: nil)
            },
            set: { newValue in
                if let cid = orderNumberingCompanyID {
                    orderStore.numberFormatOverrides[cid] = newValue
                } else {
                    orderStore.numberPrefix = newValue.prefix
                    orderStore.numberIncludeYear = newValue.includeYear
                    orderStore.numberStart = newValue.start
                    orderStore.numberUseSeparator = newValue.useSeparator
                }
                orderStore.save()
            }
        )
    }

    private var activeQuoteNumberingFormatBinding: Binding<InvoiceNumberingFormat> {
        Binding(
            get: {
                guard let cid = quoteNumberingCompanyID else { return quoteStore.numberingFormat(for: nil) }
                return quoteStore.numberFormatOverrides[cid] ?? quoteStore.numberingFormat(for: nil)
            },
            set: { newValue in
                if let cid = quoteNumberingCompanyID {
                    quoteStore.numberFormatOverrides[cid] = newValue
                } else {
                    quoteStore.numberPrefix = newValue.prefix
                    quoteStore.numberIncludeYear = newValue.includeYear
                    quoteStore.numberStart = newValue.start
                    quoteStore.numberUseSeparator = newValue.useSeparator
                }
                quoteStore.save()
            }
        )
    }
}

/// Regroupe tout ce qui est lié à un service externe (annuaires, dépôt réglementaire,
/// email, sauvegarde) — séparé d'`ApplicationSettingsView` pour ne pas noyer les réglages
/// purement internes (environnement, modules, sociétés…) au milieu de champs
/// d'identifiants. Même structure de section (DisclosureGroup) que le reste des réglages.

// MARK: - Tables de valeurs paramétrées



/// Badge affiché sur une ligne de table de réglages quand une société est sélectionnée et
/// que cette ligne a une surcharge propre à elle — clic pour revenir au réglage par défaut.
/// État d'une ligne de table de valeurs vis-à-vis de la société actuellement sélectionnée
/// (`ValueTablesView.tableSocietyID`) — voir `ValueTablesView.overrideState(hasOwnOverride:hasPrincipaleOverride:)`.



/// Choisir une société d'abord, puis revoir tous ses réglages personnalisables en une seule
/// fois — en complément des sélecteurs déjà présents écran par écran (Tables, Application),
/// pas à leur place (F.3 du chantier "Réglages par société"). Réutilise les vues déjà
/// existantes (`ValueTablesView`, pré-filtrée via son `initialSocietyID`) plutôt que de
/// dupliquer leur logique d'édition. Conçue pour grossir : une section "Emails" s'ajoutera
/// après la Zone 0, une section "Connexions" après la Zone 4.
struct ConfigureSocieteView: View {
    @EnvironmentObject var directory: PartyDirectory
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var store: InvoiceStore
    @EnvironmentObject var orderStore: OrderStore
    @EnvironmentObject var quoteStore: QuoteStore
    @State private var selectedSocieteID: UUID?
    @State private var tablesExpanded = true
    @State private var numberingExpanded = false
    @State private var emailsExpanded = false

    private var societies: [DirectoryEntry] {
        auth.visibleSocieties(for: auth.currentUser)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Configurer une société").font(.title2.bold())
            Text("Choisissez une société pour revoir en une seule fois tous ses réglages personnalisables, plutôt que de les retrouver écran par écran.")
                .font(.caption).foregroundStyle(.secondary)

            if societies.isEmpty {
                Text("Aucune société du périmètre. Créez-en une dans Réglages > Application > Sociétés du périmètre.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("Société", selection: $selectedSocieteID) {
                    Text("Choisir une société…").tag(UUID?.none)
                    ForEach(societies) { s in
                        HStack {
                            Text(s.displayName)
                            if s.isPrincipale { Text("— principale") }
                        }.tag(UUID?.some(s.id))
                    }
                }
                .frame(width: 340)
            }

            if let cid = selectedSocieteID {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        DisclosureGroup("Tables de valeurs (statuts, tags, conditions de paiement, couleurs…)", isExpanded: $tablesExpanded) {
                            ValueTablesView(initialSocietyID: cid)
                                .id(cid)
                                .frame(minHeight: 480)
                        }
                        DisclosureGroup("Numérotation", isExpanded: $numberingExpanded) {
                            VStack(alignment: .leading, spacing: 10) {
                                numberingSummaryRow(
                                    title: "Factures",
                                    format: store.numberingFormat(for: cid),
                                    isOverridden: store.numberFormatOverrides[cid] != nil,
                                    onCustomize: { store.numberFormatOverrides[cid] = store.numberingFormat(for: nil); store.save() },
                                    onRevert: { store.numberFormatOverrides.removeValue(forKey: cid); store.save() }
                                )
                                numberingSummaryRow(
                                    title: "Commandes",
                                    format: orderStore.numberingFormat(for: cid),
                                    isOverridden: orderStore.numberFormatOverrides[cid] != nil,
                                    onCustomize: { orderStore.numberFormatOverrides[cid] = orderStore.numberingFormat(for: nil); orderStore.save() },
                                    onRevert: { orderStore.numberFormatOverrides.removeValue(forKey: cid); orderStore.save() }
                                )
                                numberingSummaryRow(
                                    title: "Devis",
                                    format: quoteStore.numberingFormat(for: cid),
                                    isOverridden: quoteStore.numberFormatOverrides[cid] != nil,
                                    onCustomize: { quoteStore.numberFormatOverrides[cid] = quoteStore.numberingFormat(for: nil); quoteStore.save() },
                                    onRevert: { quoteStore.numberFormatOverrides.removeValue(forKey: cid); quoteStore.save() }
                                )
                                Text("Détail complet (préfixe, année, numéro de début, séparateur) dans Réglages > Application.")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            .padding(.top, 4)
                        }
                        DisclosureGroup("Emails automatiques", isExpanded: $emailsExpanded) {
                            EmailTemplatesAdminView(initialSocietyID: cid)
                                .id(cid)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Spacer()
                HStack {
                    Spacer()
                    Text("Sélectionnez une société pour commencer.").foregroundStyle(.secondary)
                    Spacer()
                }
                Spacer()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func numberingSummaryRow(title: String, format: InvoiceNumberingFormat, isOverridden: Bool, onCustomize: @escaping () -> Void, onRevert: @escaping () -> Void) -> some View {
        HStack {
            Text(title).frame(width: 90, alignment: .leading)
            Text("\(format.prefix)\(format.includeYear ? "-AAAA" : "")-0001").monospaced().font(.caption).foregroundStyle(.secondary)
            Spacer()
            if isOverridden {
                Button("Revenir au réglage hérité", role: .destructive, action: onRevert).buttonStyle(.link).font(.caption2)
            } else {
                Button("Personnaliser pour cette société", action: onCustomize).buttonStyle(.link).font(.caption2)
            }
        }
    }
}





/// Pendant de `InvoiceStatusEditorSheet` côté achats — copie structurelle, retypée sur
/// `PurchaseInvoiceStatus`/`PurchaseInvoiceStatusOverride`.




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
    @State private var superPDPLookupLoading = false
    @State private var superPDPLookupNote: String?
    @State private var superPDPAddressChoices: [SuperPDPDirectoryEntry] = []
    @EnvironmentObject var paymentTermsStore: PaymentTermsPresetStore
    @EnvironmentObject var superPDPSettings: SuperPDPSettings

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
                        if !locked, superPDPSettings.credentials.isConfigured {
                            Button {
                                lookupSuperPDPElectronicAddress()
                            } label: {
                                if superPDPLookupLoading {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "magnifyingglass.circle.fill").font(.title3)
                                }
                            }
                            .buttonStyle(.borderless)
                            .disabled(superPDPLookupLoading || !canLookupSuperPDPElectronicAddress)
                            .help("Rechercher l'adresse électronique sur SUPER PDP à partir du SIREN/SIRET")
                        }
                    }
                }
                if !locked, linkedEntry == nil, let note = superPDPLookupNote {
                    Text(note).font(.caption2).foregroundStyle(.secondary)
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
        .sheet(isPresented: Binding(
            get: { !superPDPAddressChoices.isEmpty },
            set: { if !$0 { superPDPAddressChoices = [] } }
        )) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Plusieurs adresses électroniques trouvées").font(.headline).padding(12)
                Text("Ce SIREN/SIRET correspond à plusieurs établissements sur SUPER PDP. Choisissez l'adresse à utiliser.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.bottom, 8)
                Divider()
                List(superPDPAddressChoices) { entry in
                    Button {
                        applySuperPDPMatch(entry)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name ?? entry.routingAddress ?? "—").font(.body.weight(.medium))
                            Text(entry.routingAddress ?? "").font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(minWidth: 420, minHeight: 320)
        }
    }

    private var canLookupSuperPDPElectronicAddress: Bool {
        let siren = (party.siren ?? "").filter { $0.isNumber }
        let siret = (party.siret ?? "").filter { $0.isNumber }
        return siren.count == 9 || siret.count == 14
    }

    /// Recherche manuelle de l'adresse électronique SUPER PDP pour le SIREN/SIRET saisi —
    /// même logique que `PartySection.saveToDirectory()`, mais déclenchée explicitement ici
    /// car cette vue sert aussi à la création directe d'un tiers depuis l'Annuaire, un
    /// chemin qui ne passait jusque-là par aucune recherche automatique.
    private func lookupSuperPDPElectronicAddress() {
        let siren = (party.siren ?? "").filter { $0.isNumber }
        let siret = (party.siret ?? "").filter { $0.isNumber }
        guard superPDPSettings.credentials.isConfigured, siren.count == 9 || siret.count == 14 else { return }
        superPDPLookupLoading = true
        superPDPLookupNote = nil
        let query = siret.count == 14 ? siret : siren
        Task {
            do {
                let results = try await SuperPDPService().searchRecipient(siretOrSiren: query, credentials: superPDPSettings.credentials)
                let withAddress = results.filter { !($0.routingAddress ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
                let distinctAddresses = Set(withAddress.map { $0.routingAddress ?? "" })
                if distinctAddresses.count > 1 {
                    superPDPAddressChoices = withAddress
                } else if let match = withAddress.first {
                    applySuperPDPMatch(match)
                    superPDPLookupNote = "Adresse électronique trouvée sur SUPER PDP."
                } else {
                    superPDPLookupNote = "Aucune adresse électronique trouvée sur SUPER PDP pour ce SIREN/SIRET."
                }
            } catch {
                superPDPLookupNote = "Recherche SUPER PDP indisponible : \(error.localizedDescription)"
            }
            superPDPLookupLoading = false
        }
    }

    private func applySuperPDPMatch(_ match: SuperPDPDirectoryEntry) {
        guard let addr = match.routingAddress?.trimmingCharacters(in: .whitespaces), !addr.isEmpty else { return }
        party.endpointID = addr
        party.endpointSchemeID = match.routingScheme?.trimmingCharacters(in: .whitespaces).isEmpty == false ? match.routingScheme! : "0225"
        let siren = (party.siren ?? "").filter { $0.isNumber }
        let siret = (party.siret ?? "").filter { $0.isNumber }
        if !siren.isEmpty {
            let format: RoutingAddressFormat = siret.count == 14 ? .sirenSiret : .siren
            let newAddress = PartyRoutingAddress(
                format: format, siren: siren, siret: siret.count == 14 ? siret : nil,
                label: "SUPER PDP", isActive: true, isDefault: routingAddresses.isEmpty
            )
            if !routingAddresses.contains(where: { $0.composedAddress == newAddress.composedAddress }) {
                routingAddresses.append(newAddress)
            }
        }
        superPDPAddressChoices = []
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



/// Taux de TVA français standards (métropole). "Autre…" bascule sur un champ
/// numérique libre pour un cas hors norme (DOM-TOM, régime particulier…).

/// Pièces jointes + commentaire interne, factorisés car identiques sur facture/commande/devis.

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
    @EnvironmentObject var quoteStore: QuoteStore
    @EnvironmentObject var moduleStore: ModuleStore
    @Binding var selectedID: UUID?
    @Binding var companyFilter: UUID?
    @State private var query = ""
    @State private var exportMessage: String?
    @State private var showScanImport = false
    @State private var showQuotePicker = false
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
        if let cf = companyFilter {
            result = result.filter { $0.companyID == cf }
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
                    Menu {
                        Button {
                            showScanImport = true
                        } label: { Label("Scanner un document", systemImage: "doc.viewfinder") }
                            .help("Importer la photo/le scan d'un bon de commande ou d'un devis fournisseur pour pré-remplir une commande")
                        if moduleStore.settings.quotesEnabled {
                            Button {
                                showQuotePicker = true
                            } label: { Label("Depuis un devis", systemImage: "doc.text.below.ecg") }
                                .help("Transforme un devis accepté en commande")
                        }
                    } label: {
                        Label("Nouvelle commande", systemImage: "plus")
                    } primaryAction: {
                        let draft = orderStore.newDraft(preferredSellerEntryID: auth.currentUser?.defaultSellerEntryID, companyID: companyFilter ?? defaultOrderCompanyID())
                        orderStore.upsert(draft)
                        selectedID = draft.id
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Nouvelle commande vierge — flèche pour créer depuis un devis, ou en scannant un document")
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
                HStack(spacing: 12) {
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
                    Button {
                        showAdvancedFilters.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: showAdvancedFilters ? "chevron.down" : "chevron.right")
                                .font(.caption2).foregroundStyle(.secondary)
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.caption)
                            Text("Filtres avancés")
                                .font(.caption.bold())
                            Text("(\(activeAdvancedFilterCount))")
                                .font(.caption.bold())
                                .foregroundStyle(activeAdvancedFilterCount > 0 ? Color.accentColor : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
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
                if showAdvancedFilters {
                    HStack(alignment: .center, spacing: 12) {
                        advancedFilterRow(field: $advField1, value: $advValue1, index: 1)
                        advancedFilterRow(field: $advField2, value: $advValue2, index: 2)
                        advancedFilterRow(field: $advField3, value: $advValue3, index: 3)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 4)
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
                            let draft = orderStore.newDraft(preferredSellerEntryID: auth.currentUser?.defaultSellerEntryID, companyID: companyFilter ?? defaultOrderCompanyID())
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
        .sheet(isPresented: $showQuotePicker) {
            QuoteToOrderSheet(
                quotes: scopedOrderableQuotes,
                onCreate: { quote in
                    let number = orderStore.nextNumber(companyID: quote.companyID)
                    let order = quote.toOrder(number: number)
                    orderStore.upsert(order)
                    var converted = quote
                    converted.convertedOrderNumber = order.number
                    quoteStore.upsert(converted)
                    selectedID = order.id
                    showQuotePicker = false
                },
                onCancel: { showQuotePicker = false }
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

    /// Devis transformables en commande : acceptés et pas déjà convertis (ni en
    /// commande, ni directement en facture) — même garde que côté Factures, pour
    /// qu'un devis n'alimente jamais deux documents de vente à la fois.
    private var scopedOrderableQuotes: [Quote] {
        var result = quoteStore.quotes.filter {
            $0.status == .accepted && $0.convertedOrderNumber == nil && $0.convertedInvoiceNumber == nil
        }
        if let scope = auth.visibleOrderCompanyIDs(for: auth.currentUser) {
            result = result.filter { quote in
                if let cid = quote.companyID { return scope.contains(cid) }
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
    @Binding var orderSelectedID: UUID?
    @Binding var companyFilter: UUID?
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
        if let cf = companyFilter {
            result = result.filter { $0.companyID == cf }
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
        let draft = quoteStore.newDraft(seller: seller, companyID: companyFilter ?? defaultCompanyID())
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
                HStack(spacing: 12) {
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
                    Button {
                        showAdvancedFilters.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: showAdvancedFilters ? "chevron.down" : "chevron.right")
                                .font(.caption2).foregroundStyle(.secondary)
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.caption)
                            Text("Filtres avancés")
                                .font(.caption.bold())
                            Text("(\(activeAdvancedFilterCount))")
                                .font(.caption.bold())
                                .foregroundStyle(activeAdvancedFilterCount > 0 ? Color.accentColor : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
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
                if showAdvancedFilters {
                    HStack(alignment: .center, spacing: 12) {
                        advancedFilterRow(field: $advField1, value: $advValue1, index: 1)
                        advancedFilterRow(field: $advField2, value: $advValue2, index: 2)
                        advancedFilterRow(field: $advField3, value: $advValue3, index: 3)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 4)
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
                    QuoteEditorView(quote: binding(for: id), rootTab: $rootTab, invoiceSelectedID: $invoiceSelectedID, orderSelectedID: $orderSelectedID)
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
    @Binding var orderSelectedID: UUID?
    @EnvironmentObject var quoteStore: QuoteStore
    @EnvironmentObject var quoteStatusStore: QuoteStatusStore
    @EnvironmentObject var store: InvoiceStore
    @EnvironmentObject var orderStore: OrderStore
    @EnvironmentObject var moduleStore: ModuleStore
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
                                  || !emailTemplateStore.isSendEnabled(.quoteSent, companyID: quote.companyID)
                                  || (quote.buyer.contactEmail ?? "").isEmpty
                                  || !smtpSettings.credentials(for: quote.companyID).isConfigured)
                        .help(!emailTemplateStore.template(for: .quoteSent, companyID: quote.companyID).enabled
                              ? "Cet email est désactivé (Réglages > Application)"
                              : (quote.buyer.contactEmail ?? "").isEmpty
                              ? "Aucune adresse email cliente renseignée"
                              : !smtpSettings.credentials(for: quote.companyID).isConfigured
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
                    if quote.status == .accepted && quote.convertedOrderNumber == nil {
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
                    if quote.status == .accepted && moduleStore.settings.ordersEnabled && quote.convertedInvoiceNumber == nil {
                        Button {
                            let number = orderStore.nextNumber(companyID: quote.companyID)
                            let order = quote.toOrder(number: number)
                            orderStore.upsert(order)
                            quote.convertedOrderNumber = order.number
                            orderSelectedID = order.id
                            rootTab = .orders
                        } label: {
                            Label("Convertir en commande", systemImage: "cart.badge.plus")
                        }
                        .buttonStyle(ToolbarActionButtonStyle(tint: .orange, filled: true))
                        .help("Recopie les lignes du devis dans une nouvelle commande brouillon")
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }

            if let n = quote.convertedOrderNumber {
                Text("Converti en commande : \(n) (disponible dans l'onglet Ventes)")
                    .font(.caption).foregroundStyle(.green)
                    .padding(.horizontal, 12)
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
                                .onChange(of: line.vatRate) { newRate in
                                    // Un devis n'affiche pas de sélecteur de catégorie TVA (il n'émet pas de
                                    // XML), mais toInvoice()/toOrder() recopient les lignes telles quelles :
                                    // sans ce recalage, une catégorie "zéro-rated" laissée par un ancien taux
                                    // à 0 % suivrait la ligne jusqu'à la facture/commande, rejetée par le
                                    // validateur EN16931 (BR-Z-05/BR-Z-09).
                                    line.vatCategory = newRate == 0 ? .zeroRated : .standard
                                    if newRate != 0 { line.vatExemptionReason = nil }
                                }
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
                    AttachmentsAndCommentSection(attachments: $quote.attachments, internalComment: $quote.internalComment, locked: isLocked)
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
        let credentials = smtpSettings.credentials(for: quote.companyID)
        guard credentials.isConfigured else {
            quoteEmailMessage = "Échec envoi : envoi d'email non configuré (Réglages)."
            return
        }
        let template = emailTemplateStore.template(for: .quoteSent, companyID: quote.companyID)
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
                                    VATRatePicker(rate: $line.vatRate)
                                    InfoBadge(text: "Taux de TVA appliqué (%). Catégorie et motif d'exonération réglables ci-dessous pour un taux à 0 %.")
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
                            .onChange(of: line.vatRate) { newRate in
                                line.vatCategory = newRate == 0 ? .zeroRated : .standard
                                if newRate != 0 { line.vatExemptionReason = nil }
                            }
                            if line.vatRate == 0 {
                                HStack(spacing: 8) {
                                    HStack(spacing: 2) {
                                        Picker("", selection: $line.vatCategory) {
                                            ForEach(VATCategory.allCases, id: \.self) { cat in
                                                Text("\(cat.rawValue) — \(cat.label)").tag(cat)
                                            }
                                        }
                                        .labelsHidden()
                                        .frame(width: 210)
                                        InfoBadge(text: "Catégorie de TVA : S = normal, Z = taux zéro, AE = autoliquidation, K = livraison intracommunautaire, G = exportation hors UE, E = exonérée, O = hors champ.")
                                    }
                                    if line.vatCategory.requiresExemptionReason {
                                        HStack(spacing: 2) {
                                            TextField("Motif d'exonération", text: Binding($line.vatExemptionReason, replacingNilWith: ""))
                                                .frame(minWidth: 280)
                                            InfoBadge(text: "Motif d'exonération, obligatoire pour cette catégorie de TVA.")
                                        }
                                    }
                                }
                                .padding(.leading, 4)
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

                AttachmentsAndCommentSection(attachments: $order.attachments, internalComment: $order.internalComment, locked: fieldLocked)

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
                  || !emailTemplateStore.isSendEnabled(kind, companyID: order.companyID)
                  || (order.buyer.contactEmail ?? "").isEmpty
                  || !smtpSettings.credentials(for: order.companyID).isConfigured)
        .help(!emailTemplateStore.template(for: kind, companyID: order.companyID).enabled
              ? "Cet email est désactivé (Réglages > Application)"
              : (order.buyer.contactEmail ?? "").isEmpty
              ? "Aucune adresse email cliente renseignée"
              : !smtpSettings.credentials(for: order.companyID).isConfigured
              ? "Configurez l'envoi d'email (Réglages) pour envoyer cet email"
              : "Envoyer « \(kind.label) » par email au client")
    }

    private func sendOrderEmail(kind: EmailTemplateKind) {
        guard let recipient = order.buyer.contactEmail, !recipient.isEmpty else {
            orderEmailMessage = "Échec envoi : aucune adresse email cliente renseignée."
            return
        }
        let credentials = smtpSettings.credentials(for: order.companyID)
        guard credentials.isConfigured else {
            orderEmailMessage = "Échec envoi : envoi d'email non configuré (Réglages)."
            return
        }
        let template = emailTemplateStore.template(for: kind, companyID: order.companyID)
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
                        Label("OK — contrôlé en local", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                    } else {
                        Label("Pré-vérification locale : \(v.errors.count) erreur(s)", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    }
                    Spacer()
                    Button { showValidation = false } label: {
                        Image(systemName: "xmark.circle")
                    }.buttonStyle(.plain)
                }
                Text("Contrôles internes, non exhaustifs — seule une validation officielle (SUPER PDP, etc.) fait foi.")
                    .font(.caption2).foregroundStyle(.secondary)
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
