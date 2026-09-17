import SwiftUI
import FacturXCore

/// Assistant complet de revue des réglages : contrairement à `SetupWizardView`
/// (premier lancement, minimal, non bloquant), celui-ci passe en revue *toutes*
/// les catégories de Réglages > Application, une par une, pour un administrateur
/// qui veut s'assurer que rien n'a été oublié. Relançable à tout moment depuis
/// Réglages > Application ("Relancer l'assistant complet").
///
/// Pour les réglages simples (bascule test/prod, activation de module, activation
/// PDP/SMTP/2FA) les contrôles réels sont directement ici — ce sont les mêmes
/// `@Published` que dans Réglages, donc aucun risque de divergence. Pour les
/// réglages à plusieurs champs (identifiants SUPER PDP/SMTP, sociétés, tables de
/// préréglages), cet assistant affiche l'état actuel et renvoie vers Réglages >
/// Application plutôt que de dupliquer tout le formulaire.
struct FullSettingsWizardView: View {
    var onFinished: () -> Void

    @EnvironmentObject var appEnv: AppEnvironment
    @EnvironmentObject var directory: PartyDirectory
    @EnvironmentObject var moduleStore: ModuleStore
    @EnvironmentObject var invoiceStore: InvoiceStore
    @EnvironmentObject var paymentTermsStore: PaymentTermsPresetStore
    @EnvironmentObject var superPDPSettings: SuperPDPSettings
    @EnvironmentObject var smtpSettings: SMTPSettings
    @EnvironmentObject var twoFactorSettings: TwoFactorSettings

    @State private var step: Step = .welcome
    @State private var creatingSociety = false

    enum Step: Int, CaseIterable {
        case welcome, environment, societies, modules, numbering, paymentTerms, superPDP, smtp, twoFactor, backup, done
    }

    private var societies: [DirectoryEntry] {
        directory.entries.filter { $0.kind == .societe }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Assistant complet des réglages").font(.title3.bold())
                Spacer()
                Text("Étape \(step.rawValue + 1) sur \(Step.allCases.count)")
                    .font(.caption).foregroundStyle(.secondary)
                Button { onFinished() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Fermer — vous pouvez relancer cet assistant à tout moment depuis Réglages > Application")
            }
            .padding()
            Divider()

            ScrollView {
                Group {
                    switch step {
                    case .welcome: welcomeStep
                    case .environment: environmentStep
                    case .societies: societiesStep
                    case .modules: modulesStep
                    case .numbering: numberingStep
                    case .paymentTerms: paymentTermsStep
                    case .superPDP: superPDPStep
                    case .smtp: smtpStep
                    case .twoFactor: twoFactorStep
                    case .backup: backupStep
                    case .done: doneStep
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            HStack {
                if step != .welcome {
                    Button("Précédent") { back() }
                }
                Spacer()
                if step == .done {
                    Button("Terminer") { onFinished() }.buttonStyle(.borderedProminent)
                } else {
                    Button(step == .welcome ? "Commencer" : "Continuer") { forward() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .frame(width: 700, height: 600)
        .sheet(isPresented: $creatingSociety) {
            DirectoryEditorView(initialKind: .societe) { entry in
                directory.upsert(entry)
                creatingSociety = false
            }
        }
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

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checklist").font(.system(size: 48)).foregroundStyle(Color.accentColor)
            Text("Revue complète des réglages").font(.title2.bold())
            Text("Cet assistant passe en revue toutes les catégories de réglages de l'application, une par une, pour vérifier que rien n'a été oublié. Les réglages à plusieurs champs (identifiants d'API…) restent à compléter dans Réglages > Application ; cet assistant vous y renvoie le cas échéant. Vous pouvez le relancer à tout moment.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }

    private var environmentStep: some View {
        stepContainer(icon: appEnv.isTest ? "flask" : "checkmark.seal.fill", title: "Environnement") {
            Text("Bascule entre données de test et de production. Chaque environnement a ses propres factures, commandes, tiers, utilisateurs, journal d'audit et identifiants SUPER PDP.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Environnement", selection: Binding(
                get: { appEnv.mode },
                set: { appEnv.setMode($0) }
            )) {
                ForEach(AppEnvironmentMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            if appEnv.isTest {
                Label("Mode bac à sable : les données et identifiants sont isolés de la production.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var societiesStep: some View {
        stepContainer(icon: "building.2.fill", title: "Sociétés du périmètre") {
            Text("Chaque société émettrice définit un périmètre (utilisateurs, factures, numérotation…). Gestion complète (logo, profil Factur-X…) dans Réglages > Application > Sociétés du périmètre.")
                .font(.caption).foregroundStyle(.secondary)
            if societies.isEmpty {
                Label("Aucune société — indispensable avant de facturer.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            } else {
                ForEach(societies) { s in
                    HStack {
                        Image(systemName: "building.2").foregroundStyle(.secondary)
                        Text(s.displayName)
                        Spacer()
                        Text(s.party.city).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Button {
                creatingSociety = true
            } label: { Label("Nouvelle société", systemImage: "plus") }
                .buttonStyle(.bordered)
        }
    }

    private var modulesStep: some View {
        stepContainer(icon: "square.grid.2x2", title: "Modules") {
            Text("Désactive un module optionnel pour toute l'application. Annuaire et Factures restent toujours actifs.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Devis", isOn: Binding(
                get: { moduleStore.settings.quotesEnabled },
                set: { moduleStore.settings.quotesEnabled = $0; moduleStore.save() }
            ))
            Toggle("Ventes (commandes)", isOn: Binding(
                get: { moduleStore.settings.ordersEnabled },
                set: { moduleStore.settings.ordersEnabled = $0; moduleStore.save() }
            ))
        }
    }

    private var numberingStep: some View {
        stepContainer(icon: "number", title: "Numérotation des factures") {
            Text("Format des numéros de facture (préfixe, année, séparateur, numéro de début). Aperçu avec le format actuel :")
                .font(.caption).foregroundStyle(.secondary)
            Text(invoiceStore.previewNextNumber()).monospaced().font(.callout.bold())
            Text("Réglable dans Réglages > Application > Numérotation des factures.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var paymentTermsStep: some View {
        stepContainer(icon: "banknote", title: "Conditions de paiement") {
            Text("Préréglages proposés à la saisie sur les fiches société (Comptant, 30 jours net…), avec calcul automatique de l'échéance. \(paymentTermsStore.presets.count) préréglage(s) actuellement.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(paymentTermsStore.presets.prefix(6)) { preset in
                Label(preset.label, systemImage: "checkmark").font(.caption)
            }
            Text("Réglable dans Réglages > Tables > Conditions de paiement.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var superPDPStep: some View {
        stepContainer(icon: "paperplane.circle", title: "SUPER PDP (dépôt + annuaire)") {
            Text("Plateforme Agréée pour le dépôt électronique des factures. Nécessaire pour se conformer à la réforme facturation électronique.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle(isOn: Binding(
                get: { superPDPSettings.credentials.usePDP },
                set: { superPDPSettings.credentials.usePDP = $0; superPDPSettings.save() }
            )) {
                Text("Utiliser PDP").font(.body.weight(.semibold))
            }
            statusLabel(configured: superPDPSettings.credentials.isConfigured,
                        okText: "Identifiants configurés",
                        koText: "Identifiants non configurés")
            if superPDPSettings.credentials.usePDP && !superPDPSettings.credentials.isConfigured {
                Text("Renseignez client_id/client_secret dans Réglages > Application > SUPER PDP.")
                    .font(.caption2).foregroundStyle(.orange)
            }
        }
    }

    private var smtpStep: some View {
        stepContainer(icon: "envelope.badge", title: "Alertes email (SMTP)") {
            Text("Notifications par email (nouvel utilisateur, changement de statut de facture) via votre propre serveur SMTP.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle(isOn: Binding(
                get: { smtpSettings.credentials.alertsEnabled },
                set: { smtpSettings.credentials.alertsEnabled = $0; smtpSettings.save() }
            )) {
                Text("Activer les alertes email").font(.body.weight(.semibold))
            }
            statusLabel(configured: smtpSettings.credentials.isConfigured,
                        okText: "Serveur configuré",
                        koText: "Serveur non configuré")
            if smtpSettings.credentials.alertsEnabled && !smtpSettings.credentials.isConfigured {
                Text("Renseignez le serveur/identifiants dans Réglages > Application > Alertes email.")
                    .font(.caption2).foregroundStyle(.orange)
            }
        }
    }

    private var twoFactorStep: some View {
        stepContainer(icon: "lock.shield", title: "Double authentification") {
            Text("Autorise chaque utilisateur à activer la 2FA sur son propre profil. Désactivé ici, personne ne peut l'utiliser, même déjà configurée.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Autoriser la double authentification (2FA)", isOn: Binding(
                get: { twoFactorSettings.enabledSolutionWide },
                set: { twoFactorSettings.enabledSolutionWide = $0; twoFactorSettings.save() }
            ))
        }
    }

    private var backupStep: some View {
        stepContainer(icon: "icloud.and.arrow.up", title: "Sauvegarde cloud (pCloud)") {
            CloudBackupSettingsView()
        }
    }

    private var doneStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 48)).foregroundStyle(.green)
            Text("Revue terminée").font(.title2.bold())
            Text("Vous pouvez relancer cet assistant à tout moment depuis Réglages > Application.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func stepContainer<Content: View>(icon: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.title3.bold())
            content()
        }
    }

    private func statusLabel(configured: Bool, okText: String, koText: String) -> some View {
        Label(configured ? okText : koText, systemImage: configured ? "checkmark.circle.fill" : "questionmark.circle")
            .font(.caption)
            .foregroundStyle(configured ? .green : .orange)
    }
}
