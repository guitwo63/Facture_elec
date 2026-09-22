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












/// Taux de TVA français standards (métropole). "Autre…" bascule sur un champ
/// numérique libre pour un cas hors norme (DOM-TOM, régime particulier…).

/// Pièces jointes + commentaire interne, factorisés car identiques sur facture/commande/devis.







/// Édition du logo d'une fiche tiers (société). Le logo est persisté
/// sur le DirectoryEntry et réutilisé automatiquement en en-tête du PDF
/// des factures émises par cette société.


