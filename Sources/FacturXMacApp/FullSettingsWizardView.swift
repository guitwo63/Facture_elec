import SwiftUI
import FacturXCore

/// Assistant complet de revue des réglages : contrairement à `SetupWizardView`
/// (premier lancement, minimal, non bloquant), celui-ci passe en revue *toutes*
/// les catégories de Réglages > Application, une par une, pour un administrateur
/// qui veut s'assurer que rien n'a été oublié. Relançable à tout moment depuis
/// Réglages > Application ("Relancer l'assistant complet").
///
/// Chaque étape édite les valeurs réelles directement (mêmes `@Published` que
/// Réglages, donc aucun risque de divergence ni de double saisie) — retour du
/// 2026-09-17 : la première version se contentait d'un statut en lecture seule
/// pour les réglages à plusieurs champs et renvoyait vers Réglages, ce qui
/// n'était pas ce qui était demandé.
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
    @State private var editingSociety: DirectoryEntry?
    @State private var superPDPSaved = false
    @State private var smtpSaved = false

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
        .sheet(item: $editingSociety) { entry in
            DirectoryEditorView(entry: entry, onSave: { updated in
                directory.upsert(updated)
                editingSociety = nil
            }, onDelete: { toDelete in
                directory.delete(toDelete)
                editingSociety = nil
            })
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
            Text("Cet assistant passe en revue et modifie toutes les catégories de réglages de l'application, une par une : mêmes valeurs que dans Réglages > Application, éditées directement ici. Vous pouvez le relancer à tout moment.")
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
            Text("Chaque société émettrice définit un périmètre (utilisateurs, factures, numérotation…).")
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
                        Button("Modifier") { editingSociety = s }
                            .buttonStyle(.link)
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
            .toggleStyle(.switch)
            Toggle("Ventes (commandes)", isOn: Binding(
                get: { moduleStore.settings.ordersEnabled },
                set: { moduleStore.settings.ordersEnabled = $0; moduleStore.save() }
            ))
            .toggleStyle(.switch)
        }
    }

    private var numberingStep: some View {
        stepContainer(icon: "number", title: "Numérotation des factures") {
            Text("Format par défaut des numéros de facture. Le compteur est indépendant par société ; un format différent par société se règle dans Réglages > Application.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("Préfixe texte").font(.caption)
                TextField("ex. FAC", text: Binding(
                    get: { invoiceStore.numberPrefix },
                    set: { invoiceStore.numberPrefix = $0; invoiceStore.save() }
                )).frame(width: 140)
            }
            Toggle("Inclure l'année", isOn: Binding(
                get: { invoiceStore.numberIncludeYear },
                set: { invoiceStore.numberIncludeYear = $0; invoiceStore.save() }
            ))
            .toggleStyle(.switch)
            HStack {
                Text("Numéro de début").font(.caption)
                Stepper(value: Binding(
                    get: { invoiceStore.numberStart },
                    set: { invoiceStore.numberStart = $0; invoiceStore.save() }
                ), in: 1...999999) {
                    Text("\(invoiceStore.numberStart)")
                }
            }
            Toggle("Séparer par un \"-\"", isOn: Binding(
                get: { invoiceStore.numberUseSeparator },
                set: { invoiceStore.numberUseSeparator = $0; invoiceStore.save() }
            ))
            .toggleStyle(.switch)
            Divider()
            HStack {
                Text("Aperçu : ").font(.caption).foregroundStyle(.secondary)
                Text(invoiceStore.previewNextNumber()).monospaced().font(.callout.bold())
            }
        }
    }

    private var paymentTermsStep: some View {
        stepContainer(icon: "banknote", title: "Conditions de paiement") {
            Text("Préréglages proposés à la saisie sur les fiches société, avec calcul automatique de l'échéance. Modifiez le texte directement :")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(paymentTermsStore.presets) { preset in
                HStack {
                    Text(preset.label).font(.caption.bold()).frame(width: 150, alignment: .leading)
                    TextField("Texte", text: Binding(
                        get: { preset.text },
                        set: { newValue in
                            var updated = preset
                            updated.text = newValue
                            paymentTermsStore.upsert(updated)
                        }
                    ))
                }
            }
            Text("Tables complètes (ajout/suppression de préréglages, statuts…) dans Réglages > Tables.")
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
            .toggleStyle(.switch)
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
                    Button {
                        superPDPSettings.save()
                        superPDPSaved = true
                    } label: { Label("Enregistrer", systemImage: "checkmark.circle") }
                        .buttonStyle(.borderedProminent)
                    if superPDPSaved {
                        Label("Enregistré", systemImage: "checkmark").font(.caption2).foregroundStyle(.green)
                    }
                }
                Text("Réglages avancés (base API, test de connexion) dans Réglages > Application > SUPER PDP.")
                    .font(.caption2).foregroundStyle(.tertiary)
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
            .toggleStyle(.switch)
            if smtpSettings.credentials.alertsEnabled {
                HStack {
                    Text("Serveur").frame(width: 100, alignment: .leading)
                    TextField("smtp.exemple.fr", text: $smtpSettings.credentials.host)
                    Text("Port").foregroundStyle(.secondary)
                    TextField("465", value: $smtpSettings.credentials.port, format: .number).frame(width: 70)
                }
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
                }
                HStack {
                    Button {
                        smtpSettings.save()
                        smtpSaved = true
                    } label: { Label("Enregistrer", systemImage: "checkmark.circle") }
                        .buttonStyle(.borderedProminent)
                    if smtpSaved {
                        Label("Enregistré", systemImage: "checkmark").font(.caption2).foregroundStyle(.green)
                    }
                }
                Text("Déclencheurs et test d'envoi dans Réglages > Application > Alertes email.")
                    .font(.caption2).foregroundStyle(.tertiary)
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
            .toggleStyle(.switch)
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
}
