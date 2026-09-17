import SwiftUI
import FacturXCore

/// Assistant de premier lancement : propose de créer la première société
/// (indispensable avant de créer des utilisateurs comptables ou des factures)
/// et donne un aperçu des intégrations optionnelles. Se déclenche depuis
/// RootView tant qu'aucune société n'existe — jamais un blocage permanent :
/// « Plus tard » et « Fermer » permettent de sortir à tout moment.
struct SetupWizardView: View {
    @EnvironmentObject var directory: PartyDirectory
    @EnvironmentObject var invoiceStore: InvoiceStore
    var onFinished: () -> Void

    @State private var step: WizardStep = .welcome
    @State private var showInvoiceWizard = false

    enum WizardStep: Int, CaseIterable {
        case welcome, society, integrations, firstInvoice, done
    }

    private var hasSociety: Bool {
        directory.entries.contains { $0.kind == .societe }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Configuration initiale").font(.title3.bold())
                Spacer()
                Text("Étape \(step.rawValue + 1) sur \(WizardStep.allCases.count)")
                    .font(.caption).foregroundStyle(.secondary)
                Button {
                    onFinished()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Fermer — vous pourrez reprendre la configuration plus tard dans Réglages")
            }
            .padding()
            Divider()

            Group {
                switch step {
                case .welcome: welcomeStep
                case .society: societyStep
                case .integrations: integrationsStep
                case .firstInvoice: firstInvoiceStep
                case .done: doneStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            HStack {
                if step != .welcome {
                    Button("Précédent") { back() }
                }
                Spacer()
                if (step == .society && !hasSociety) || step == .firstInvoice {
                    Button("Plus tard") { forward() }
                }
                switch step {
                case .welcome:
                    Button("Commencer") { forward() }.buttonStyle(.borderedProminent)
                case .society:
                    Button("Continuer") { forward() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!hasSociety)
                case .integrations:
                    Button("Continuer") { forward() }.buttonStyle(.borderedProminent)
                case .firstInvoice:
                    Button("Continuer") { forward() }.buttonStyle(.borderedProminent)
                case .done:
                    Button("Terminer") { onFinished() }.buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .frame(width: 640, height: 560)
        .sheet(isPresented: $showInvoiceWizard) {
            SalesInvoiceWizardView(
                onCreated: { _ in showInvoiceWizard = false },
                onCancel: { showInvoiceWizard = false }
            )
        }
    }

    private func forward() {
        if let idx = WizardStep.allCases.firstIndex(of: step), idx + 1 < WizardStep.allCases.count {
            step = WizardStep.allCases[idx + 1]
        }
    }

    private func back() {
        if let idx = WizardStep.allCases.firstIndex(of: step), idx > 0 {
            step = WizardStep.allCases[idx - 1]
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles").font(.system(size: 48)).foregroundStyle(Color.accentColor)
            Text("Bienvenue dans Factur-X").font(.title2.bold())
            Text("Ce court assistant vous aide à configurer l'indispensable avant de commencer à facturer : votre société émettrice, puis un aperçu des intégrations disponibles. Tout reste modifiable ensuite dans Réglages.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
        }
        .padding()
    }

    private var societyStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            if hasSociety {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 40)).foregroundStyle(.green)
                    Text("Société créée").font(.headline)
                    Text("Vous pourrez en ajouter d'autres, ou la modifier, depuis Réglages > Application > Sociétés du périmètre.")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                Text("Une société émettrice est nécessaire avant de créer des utilisateurs comptables ou des factures. Renseignez au moins son nom et son adresse — le reste (SIREN, IBAN…) peut être complété plus tard.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal)
                DirectoryEditorView(initialKind: .societe) { entry in
                    directory.upsert(entry)
                }
                .padding(.horizontal)
            }
        }
    }

    private var integrationsStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Ces intégrations sont optionnelles et se configurent à tout moment dans Réglages > Application :")
                    .font(.callout).foregroundStyle(.secondary)
                integrationRow(icon: "paperplane.fill", title: "SUPER PDP",
                                detail: "Dépôt électronique des factures auprès d'une Plateforme Agréée (réforme facturation électronique). Nécessite un compte SUPER PDP.")
                integrationRow(icon: "envelope.badge", title: "Alertes email (SMTP)",
                                detail: "Notifications par email (nouvel utilisateur, changement de statut, relances d'échéances). Nécessite un compte SMTP.")
                integrationRow(icon: "lock.shield", title: "Double authentification",
                                detail: "Protection additionnelle par code à usage unique via une application d'authentification. À activer globalement avant que chaque utilisateur puisse la configurer sur son profil.")
            }
            .padding()
        }
    }

    private var firstInvoiceStep: some View {
        VStack(spacing: 16) {
            if invoiceStore.invoices.isEmpty {
                Image(systemName: "doc.badge.plus").font(.system(size: 48)).foregroundStyle(Color.accentColor)
                Text("Créez votre première facture").font(.title2.bold())
                Text("Un dernier pas concret avant de démarrer réellement : créez une facture de test en quelques étapes guidées (client, une prestation, échéance). Vous pourrez la modifier ou la supprimer ensuite, elle ne sera jamais envoyée automatiquement.")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
                Button {
                    showInvoiceWizard = true
                } label: { Label("Créer ma première facture", systemImage: "wand.and.stars") }
                    .buttonStyle(.borderedProminent)
            } else {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 40)).foregroundStyle(.green)
                Text("Première facture créée").font(.headline)
                Text("Vous la retrouverez dans l'onglet Factures — modifiable comme n'importe quelle autre.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    showInvoiceWizard = true
                } label: { Label("Créer une facture de plus", systemImage: "plus") }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func integrationRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title2).foregroundStyle(Color.accentColor).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var doneStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 48)).foregroundStyle(.green)
            Text("Configuration terminée").font(.title2.bold())
            Text("Vous pouvez maintenant créer vos utilisateurs (icône utilisateurs dans la barre principale). Pour revoir les réglages plus en détail (SUPER PDP, alertes email, numérotation…), un second assistant complet est accessible à tout moment dans Réglages > Application.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
        }
        .padding()
    }
}
