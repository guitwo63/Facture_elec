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

    /// Les soldes d'une devise dans « Par client » : un intertitre par devise dès qu'il y en a
    /// plusieurs.
    private struct ClientBalanceSection: Identifiable {
        let currency: String
        let balances: [ClientBalance]
        var id: String { currency }
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

    /// Montant dû par client, dans chaque devise : les soldes de `CurrencyTotals.clientBalances`,
    /// déjà triés par devise, regroupés en une section par devise.
    private var clientSections: [ClientBalanceSection] {
        var sections: [ClientBalanceSection] = []
        for balance in CurrencyTotals.clientBalances(sentInvoices.filter { $0.status != .paid }) {
            if let last = sections.last, last.currency == balance.currency {
                sections[sections.count - 1] = ClientBalanceSection(currency: last.currency, balances: last.balances + [balance])
            } else {
                sections.append(ClientBalanceSection(currency: balance.currency, balances: [balance]))
            }
        }
        return sections
    }

    /// « 1250.00 USD ». Une facture émise sans devise (BR-05) ne devrait pas exister, mais un
    /// montant sans code resterait lisible.
    private func amountText(_ amount: Double, _ currency: String) -> String {
        String(format: "%.2f %@", amount, currency.isEmpty ? "(sans devise)" : currency)
    }

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
                // Hauteur commune : une carte qui a des factures en plusieurs devises compte une
                // ligne de montant par devise.
                HStack(spacing: 16) {
                    kpiCard("CA facturé — \(period.rawValue)", invoices: caFactureInvoices, color: .blue, icon: "chart.line.uptrend.xyaxis")
                    kpiCard("Encaissé — \(period.rawValue)", invoices: encaisseInvoices, color: .green, icon: "checkmark.circle.fill")
                    kpiCard("En attente", invoices: enAttenteInvoices, color: .orange, icon: "hourglass")
                    kpiCard("En retard", invoices: enRetardInvoices, color: .red, icon: "exclamationmark.triangle.fill")
                    kpiCard("Validées, non envoyées", invoices: validatedNotSentInvoices, color: Color(hex: InvoiceStatus.issued.hexColor), icon: InvoiceStatus.issued.systemImage)
                }
                .fixedSize(horizontal: false, vertical: true)
                GroupBox("Par client — montant dû") {
                    let sections = clientSections
                    if sections.isEmpty {
                        Text("Aucun montant en attente.").foregroundStyle(.secondary).padding()
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(sections) { section in
                                if sections.count > 1 {
                                    Text(section.currency.isEmpty ? "Sans devise" : section.currency)
                                        .font(.caption.bold()).foregroundStyle(.secondary)
                                        .padding(.horizontal, 8).padding(.top, 10).padding(.bottom, 2)
                                }
                                ForEach(section.balances) { c in
                                    HStack {
                                        Text(c.name).font(.body)
                                        Spacer()
                                        if c.overdue > 0 {
                                            Label(amountText(c.overdue, c.currency) + " en retard", systemImage: "exclamationmark.triangle.fill")
                                                .font(.caption).foregroundStyle(.red)
                                        }
                                        Text(amountText(c.outstanding, c.currency))
                                            .font(.body.bold()).monospacedDigit()
                                    }
                                    .padding(.vertical, 6).padding(.horizontal, 8)
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Un montant par devise, sans conversion, l'euro d'abord ; « 0.00 EUR » sans facture.
    private func kpiCard(_ title: String, invoices: [Invoice], color: Color, icon: String) -> some View {
        let invoiceCount = invoices.filter { !$0.type.isCreditNote }.count
        let creditNoteCount = invoices.filter { $0.type.isCreditNote }.count
        let totals = CurrencyTotals.byCurrency(invoices)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: icon).foregroundStyle(color)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(totals.isEmpty ? [CurrencyAmount(currency: CurrencyTotals.defaultCurrency, amount: 0)] : totals) { total in
                    Text(amountText(total.amount, total.currency))
                        .font(.title2.bold())
                }
            }
            Text("\(pluralized(invoiceCount, "facture", "factures")) · \(pluralized(creditNoteCount, "avoir", "avoirs"))")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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





/// Export direct des documents déjà filtrés dans la liste d'origine : pas de
/// fenêtre intermédiaire de sélection, juste le choix du format puis
/// l'emplacement de sauvegarde.


/// Miroir de OrderToInvoiceSheet pour les devis : ne liste que les devis déjà
/// acceptés et pas encore convertis (même règle que le bouton "Convertir en
/// facture" sur la fiche devis), pour donner un second point d'entrée depuis
/// l'onglet Factures sans dupliquer la logique métier.










/// Puce cliquable partagée par le multi-sélecteur de types (fiche tiers) et le filtre par
/// type (Annuaire) — même style, logique de bascule laissée à l'appelant car elle diffère
/// (la fiche impose au moins un type coché, le filtre autorise "aucun" = "Tous").

/// Une capsule colorée par type cumulé sur un tiers (voir `DirectoryEntry.kinds`) — remplace
/// la capsule unique d'avant le multi-sélecteur. Vue dédiée (plutôt qu'un `ForEach` inline
/// dans chaque `HStack` appelante) : le vérificateur de types SwiftUI n'arrivait pas à
/// résoudre l'expression en un temps raisonnable une fois ce `ForEach` ajouté inline.










/// Liste des emails automatiques, présentée sur le même schéma que
/// `SocietiesAdminView` : une Table avec case d'activation en ligne, puis un
/// bouton "Modifier" qui ouvre la fiche d'édition du modèle sélectionné.

/// Édition du sujet/corps d'un email automatique. Les champs disponibles
/// ({{numero}}, {{client}}…) sont insérables par un clic — pas besoin de
/// connaître/taper la syntaxe des balises — plutôt qu'un champ de texte libre
/// qui suppose que l'utilisateur connaît déjà les noms de variables.


/// Regroupe tout ce qui est lié à un service externe (annuaires, dépôt réglementaire,
/// email, sauvegarde) — séparé d'`ApplicationSettingsView` pour ne pas noyer les réglages
/// purement internes (environnement, modules, sociétés…) au milieu de champs
/// d'identifiants. Même structure de section (DisclosureGroup) que le reste des réglages.

// MARK: - Tables de valeurs paramétrées



/// Choisir une société d'abord, puis revoir tous ses réglages personnalisables en une seule
/// fois — en complément des sélecteurs déjà présents écran par écran (Tables, Application),
/// pas à leur place (F.3 du chantier "Réglages par société"). Réutilise les vues déjà
/// existantes (`ValueTablesView`, pré-filtrée via son `initialSocietyID`) plutôt que de
/// dupliquer leur logique d'édition. Conçue pour grossir : une section "Emails" s'ajoutera
/// après la Zone 0, une section "Connexions" après la Zone 4.





/// Pendant de `InvoiceStatusEditorSheet` côté achats — copie structurelle, retypée sur
/// `PurchaseInvoiceStatus`/`PurchaseInvoiceStatusOverride`.












/// Taux de TVA français standards (métropole). "Autre…" bascule sur un champ
/// numérique libre pour un cas hors norme (DOM-TOM, régime particulier…).

/// Pièces jointes + commentaire interne, factorisés car identiques sur facture/commande/devis.







/// Édition du logo d'une fiche tiers (société). Le logo est persisté
/// sur le DirectoryEntry et réutilisé automatiquement en en-tête du PDF
/// des factures émises par cette société.


