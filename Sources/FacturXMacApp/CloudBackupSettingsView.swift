import SwiftUI
import AppKit
import FacturXCore

struct CloudBackupSettingsView: View {
    @EnvironmentObject var pcloudSettings: PCloudSettings
    @EnvironmentObject var backupStrategyStore: BackupStrategyStore
    @EnvironmentObject var store: InvoiceStore
    @EnvironmentObject var orderStore: OrderStore
    @EnvironmentObject var directory: PartyDirectory

    @State private var testing = false
    @State private var testMessage: String?
    @State private var backingUp = false
    @State private var backupMessage: String?
    @State private var showRestoreSheet = false
    @State private var restoreCandidates: [PCloudBackupFile] = []
    @State private var restoring = false
    @State private var restoreMessage: String?
    @State private var listingBackups = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sauvegarde les factures, commandes et l'annuaire vers votre compte pCloud, dans un fichier JSON horodaté. La restauration ajoute/met à jour les données à partir d'une sauvegarde — elle n'efface jamais rien.")
                .font(.caption).foregroundStyle(.secondary)

            TextField("Email pCloud", text: $pcloudSettings.credentials.username)
                .textFieldStyle(.roundedBorder).frame(width: 280)
                .disableAutocorrection(true)
            SecureField("Mot de passe pCloud", text: $pcloudSettings.credentials.password)
                .textFieldStyle(.roundedBorder).frame(width: 280)
            Picker("Région du compte", selection: $pcloudSettings.credentials.region) {
                ForEach(PCloudRegion.allCases, id: \.self) { r in Text(r.label).tag(r) }
            }
            .frame(width: 380)
            .help("Le compte pCloud est hébergé aux États-Unis ou en Europe selon l'inscription initiale — une mauvaise région empêche toute connexion.")
            TextField("Dossier de sauvegarde", text: $pcloudSettings.credentials.backupFolderPath)
                .textFieldStyle(.roundedBorder).frame(width: 280)

            HStack {
                Button {
                    testConnection()
                } label: {
                    if testing {
                        HStack(spacing: 4) { ProgressView().controlSize(.small); Text("Test…") }
                    } else {
                        Label("Tester la connexion", systemImage: "checkmark.circle")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(testing || !pcloudSettings.credentials.isConfigured)

                Button {
                    backupNow()
                } label: {
                    if backingUp {
                        HStack(spacing: 4) { ProgressView().controlSize(.small); Text("Sauvegarde…") }
                    } else {
                        Label("Sauvegarder maintenant", systemImage: "icloud.and.arrow.up")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(backingUp || !pcloudSettings.credentials.isConfigured)

                Button {
                    openRestoreSheet()
                } label: { Label("Restaurer…", systemImage: "icloud.and.arrow.down") }
                    .buttonStyle(.bordered)
                    .disabled(!pcloudSettings.credentials.isConfigured)
            }

            if let m = testMessage {
                Text(m).font(.caption).foregroundStyle(m.hasPrefix("Échec") ? .red : .green)
            }
            if let m = backupMessage {
                Text(m).font(.caption).foregroundStyle(m.hasPrefix("Échec") ? .red : .green)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Stratégie de sauvegarde").font(.subheadline.bold())
                Stepper(
                    "Conserver les \(backupStrategyStore.settings.retentionCount) dernières sauvegardes",
                    value: $backupStrategyStore.settings.retentionCount, in: 1...20
                )
                .help("Les sauvegardes plus anciennes sont supprimées automatiquement après chaque nouvelle sauvegarde réussie — sur pCloud et sur la copie locale si configurée.")
                Toggle("Sauvegarder automatiquement au lancement de l'application", isOn: $backupStrategyStore.settings.autoBackupOnLaunch)
                    .disabled(!pcloudSettings.credentials.isConfigured)
                HStack {
                    Text("Copie locale (emplacement différent, optionnel) :").font(.caption)
                    Text(backupStrategyStore.settings.localBackupFolderPath ?? "Aucune")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Button("Choisir…") { pickLocalFolder() }.buttonStyle(.bordered).controlSize(.small)
                    if backupStrategyStore.settings.localBackupFolderPath != nil {
                        Button("Retirer") {
                            backupStrategyStore.settings.localBackupFolderPath = nil
                        }.buttonStyle(.borderless).controlSize(.small)
                    }
                }
            }
        }
        .onChange(of: pcloudSettings.credentials) { _ in pcloudSettings.save() }
        .onChange(of: backupStrategyStore.settings) { _ in backupStrategyStore.save() }
        .sheet(isPresented: $showRestoreSheet) {
            RestoreBackupSheet(
                candidates: restoreCandidates,
                listing: listingBackups,
                message: restoreMessage,
                restoring: restoring,
                onSelect: { file in restoreBackup(file) },
                onCancel: { showRestoreSheet = false }
            )
        }
    }

    private func testConnection() {
        testing = true
        testMessage = nil
        let credentials = pcloudSettings.credentials
        Task {
            do {
                _ = try await PCloudService().login(credentials: credentials)
                testMessage = "Connexion réussie."
            } catch {
                testMessage = "Échec : \(error.localizedDescription)"
            }
            testing = false
        }
    }

    private func backupNow() {
        backingUp = true
        backupMessage = nil
        let credentials = pcloudSettings.credentials
        let strategy = backupStrategyStore.settings
        let bundle = BackupService.capture(invoiceStore: store, orderStore: orderStore, directory: directory)
        Task {
            do {
                backupMessage = try await BackupRunner.run(bundle: bundle, pcloudCredentials: credentials, strategy: strategy)
            } catch {
                backupMessage = "Échec de la sauvegarde : \(error.localizedDescription)"
            }
            backingUp = false
        }
    }

    private func pickLocalFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Choisir un dossier de sauvegarde locale"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        backupStrategyStore.settings.localBackupFolderPath = url.path
    }

    private func openRestoreSheet() {
        showRestoreSheet = true
        listingBackups = true
        restoreMessage = nil
        restoreCandidates = []
        let credentials = pcloudSettings.credentials
        Task {
            do {
                let service = PCloudService()
                let auth = try await service.login(credentials: credentials)
                restoreCandidates = try await service.listBackups(credentials: credentials, auth: auth)
                if restoreCandidates.isEmpty {
                    restoreMessage = "Aucune sauvegarde trouvée dans \(credentials.backupFolderPath)."
                }
            } catch {
                restoreMessage = "Échec : \(error.localizedDescription)"
            }
            listingBackups = false
        }
    }

    private func restoreBackup(_ file: PCloudBackupFile) {
        restoring = true
        restoreMessage = nil
        let credentials = pcloudSettings.credentials
        Task {
            do {
                let service = PCloudService()
                let auth = try await service.login(credentials: credentials)
                let data = try await service.download(fileID: file.fileID, credentials: credentials, auth: auth)
                let bundle = try BackupService.decode(data)
                BackupService.restore(bundle, invoiceStore: store, orderStore: orderStore, directory: directory)
                restoreMessage = "Restauration terminée : \(bundle.invoices.count) facture(s), \(bundle.orders.count) commande(s), \(bundle.parties.count) tiers."
            } catch {
                restoreMessage = "Échec de la restauration : \(error.localizedDescription)"
            }
            restoring = false
        }
    }

}

struct RestoreBackupSheet: View {
    let candidates: [PCloudBackupFile]
    let listing: Bool
    let message: String?
    let restoring: Bool
    var onSelect: (PCloudBackupFile) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Restaurer une sauvegarde").font(.title3.bold())
                Spacer()
                Button { onCancel() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding()
            Divider()
            if listing {
                ProgressView("Recherche des sauvegardes…").padding(40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if candidates.isEmpty {
                Text(message ?? "Aucune sauvegarde trouvée.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(candidates) { file in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(file.name).font(.body)
                            Text(file.modified).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Restaurer") { onSelect(file) }
                            .buttonStyle(.borderedProminent)
                            .disabled(restoring)
                    }
                }
            }
            if let m = message, !candidates.isEmpty {
                Text(m).font(.caption).foregroundStyle(m.hasPrefix("Échec") ? .red : .green).padding()
            }
        }
        .frame(width: 460, height: 400)
    }
}
