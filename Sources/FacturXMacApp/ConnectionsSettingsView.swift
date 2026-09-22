import SwiftUI
import FacturXCore

// MARK: - Extrait de FacturXMacApp.swift (découpage par domaine)

struct ConnectionsSettingsView: View {
    @EnvironmentObject var chorusSettings: ChorusProSettings
    @EnvironmentObject var superPDPSettings: SuperPDPSettings
    @EnvironmentObject var smtpSettings: SMTPSettings
    @EnvironmentObject var appEnv: AppEnvironment
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var directory: PartyDirectory
    @State private var dinumExpanded = false
    @State private var pisteExpanded = false
    @State private var superPDPExpanded = true
    @State private var smtpExpanded = false
    @State private var pcloudExpanded = false
    @State private var testMessage: String?
    @State private var testing = false
    @State private var superPDPTestMessage: String?
    @State private var superPDPTesting = false
    @State private var pdpSessionMessage: String?
    @State private var pdpSessionChecking = false
    @State private var smtpTestMessage: String?
    @State private var smtpTesting = false
    /// Société dont on édite/teste les identifiants — commune aux 4 services ci-dessous
    /// (configurer une société touche typiquement ses 4 services d'affilée). `nil` = société
    /// principale si une est désignée, sinon le réglage global par défaut — même principe que
    /// `ValueTablesView.tableSocietyID`.
    @State private var connectionsSocietyID: UUID?

    private var noSelectionConnectionsLabel: String {
        guard let principaleID = directory.principaleSocieteID,
              let principale = directory.entries.first(where: { $0.id == principaleID }) else {
            return "Toutes (réglage par défaut)"
        }
        return "Société principale : \(principale.displayName)"
    }

    /// Identifiants SUPER PDP en cours d'édition : ceux de la société sélectionnée (créés à
    /// la volée à partir du réglage hérité si elle n'a pas encore de surcharge propre), ou
    /// le réglage global si "Toutes" est sélectionné. Écrire dedans met à jour la bonne
    /// cible chez `superPDPSettings` — même principe qu'`activeNumberingFormatBinding`.
    private var activeSuperPDPCredentialsBinding: Binding<SuperPDPCredentials> {
        Binding(
            get: {
                guard let cid = connectionsSocietyID else { return superPDPSettings.credentials }
                return superPDPSettings.credentialsBySociety[cid] ?? superPDPSettings.credentials(for: cid)
            },
            set: { newValue in
                if let cid = connectionsSocietyID {
                    superPDPSettings.setOverride(newValue, companyID: cid)
                } else {
                    superPDPSettings.credentials = newValue
                    superPDPSettings.save()
                }
            }
        )
    }

    /// Identifiants Chorus Pro en cours d'édition — même principe qu'`activeSuperPDPCredentialsBinding`.
    private var activeChorusProCredentialsBinding: Binding<ChorusProCredentials> {
        Binding(
            get: {
                guard let cid = connectionsSocietyID else { return chorusSettings.credentials }
                return chorusSettings.credentialsBySociety[cid] ?? chorusSettings.credentials(for: cid)
            },
            set: { newValue in
                if let cid = connectionsSocietyID {
                    chorusSettings.setOverride(newValue, companyID: cid)
                } else {
                    chorusSettings.credentials = newValue
                    chorusSettings.save()
                }
            }
        )
    }

    /// Identifiants SMTP en cours d'édition — même principe qu'`activeSuperPDPCredentialsBinding`.
    private var activeSMTPCredentialsBinding: Binding<SMTPCredentials> {
        Binding(
            get: {
                guard let cid = connectionsSocietyID else { return smtpSettings.credentials }
                return smtpSettings.credentialsBySociety[cid] ?? smtpSettings.credentials(for: cid)
            },
            set: { newValue in
                if let cid = connectionsSocietyID {
                    smtpSettings.setOverride(newValue, companyID: cid)
                } else {
                    smtpSettings.credentials = newValue
                    smtpSettings.save()
                }
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !auth.visibleSocieties(for: auth.currentUser).isEmpty {
                    HStack(spacing: 6) {
                        Text("Société").font(.caption).foregroundStyle(.secondary)
                        Picker("Société", selection: $connectionsSocietyID) {
                            Text(noSelectionConnectionsLabel).tag(UUID?.none)
                            ForEach(auth.visibleSocieties(for: auth.currentUser)) { s in
                                Text(s.displayName).tag(UUID?.some(s.id))
                            }
                        }
                        .labelsHidden().frame(width: 260)
                        InfoBadge(text: "Chaque société a ses propres identifiants pour chacun des 4 services ci-dessous — ce sélecteur pilote les quatre à la fois.")
                    }
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
                        if let cid = connectionsSocietyID {
                            if chorusSettings.credentialsBySociety[cid] == nil {
                                HStack(spacing: 6) {
                                    Text(directory.principaleSocieteID != nil && cid != directory.principaleSocieteID ? "Hérite actuellement de la société principale." : "Utilise actuellement le réglage par défaut.").font(.caption2).foregroundStyle(.secondary)
                                    Button("Personnaliser pour cette société") {
                                        chorusSettings.setOverride(chorusSettings.credentials(for: cid), companyID: cid)
                                    }.buttonStyle(.link).font(.caption2)
                                }
                            } else {
                                Button("Revenir au réglage hérité", role: .destructive) {
                                    chorusSettings.removeOverride(companyID: cid)
                                }.buttonStyle(.link).font(.caption2)
                            }
                        }
                        HStack {
                            Text("Client ID").frame(width: 100, alignment: .leading)
                            TextField("Client ID", text: activeChorusProCredentialsBinding.clientID)
                        }
                        HStack {
                            Text("Client Secret").frame(width: 100, alignment: .leading)
                            SecureField("Client Secret", text: activeChorusProCredentialsBinding.clientSecret)
                        }
                        HStack {
                            Text("Scope").frame(width: 100, alignment: .leading)
                            TextField("openid", text: activeChorusProCredentialsBinding.scope)
                        }
                        HStack {
                            Text("URL Token").frame(width: 100, alignment: .leading)
                            TextField("URL Token", text: activeChorusProCredentialsBinding.tokenURL)
                        }
                        HStack {
                            Text("Base API").frame(width: 100, alignment: .leading)
                            TextField("Base API", text: activeChorusProCredentialsBinding.apiBaseURL)
                        }
                        Divider()
                        Text("Compte technique Chorus Pro (en-tête cpro-account)").font(.caption.bold())
                        HStack {
                            Text("Login tech.").frame(width: 100, alignment: .leading)
                            TextField("login technique", text: activeChorusProCredentialsBinding.techLogin)
                        }
                        HStack {
                            Text("Mot de passe").frame(width: 100, alignment: .leading)
                            SecureField("mot de passe technique", text: activeChorusProCredentialsBinding.techPassword)
                        }
                        HStack {
                            Button {
                                if let cid = connectionsSocietyID {
                                    chorusSettings.setOverride(activeChorusProCredentialsBinding.wrappedValue, companyID: cid)
                                } else {
                                    chorusSettings.save()
                                }
                            } label: { Label("Enregistrer", systemImage: "checkmark.circle") }
                                .buttonStyle(.borderedProminent)
                            Button {
                                testing = true
                                testMessage = nil
                                let creds = chorusSettings.credentials(for: connectionsSocietyID)
                                Task {
                                    do {
                                        let service = ChorusProService()
                                        _ = try await service.fetchToken(credentials: creds)
                                        testMessage = "Connexion réussie — jeton obtenu."
                                    } catch {
                                        testMessage = "Échec : \(error.localizedDescription)"
                                    }
                                    testing = false
                                }
                            } label: { Label("Tester la connexion", systemImage: "antenna.radiowaves.left.and.right") }
                                .buttonStyle(.bordered)
                                .disabled(testing || !chorusSettings.credentials(for: connectionsSocietyID).isConfigured)
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
                        if let cid = connectionsSocietyID {
                            if superPDPSettings.credentialsBySociety[cid] == nil {
                                HStack(spacing: 6) {
                                    Text(directory.principaleSocieteID != nil && cid != directory.principaleSocieteID ? "Hérite actuellement de la société principale." : "Utilise actuellement le réglage par défaut.").font(.caption2).foregroundStyle(.secondary)
                                    Button("Personnaliser pour cette société") {
                                        superPDPSettings.setOverride(superPDPSettings.credentials(for: cid), companyID: cid)
                                    }.buttonStyle(.link).font(.caption2)
                                }
                            } else {
                                Button("Revenir au réglage hérité", role: .destructive) {
                                    superPDPSettings.removeOverride(companyID: cid)
                                }.buttonStyle(.link).font(.caption2)
                            }
                        }
                        Toggle(isOn: activeSuperPDPCredentialsBinding.usePDP) {
                            Text("Utiliser PDP").font(.body.weight(.semibold))
                        }
                        .toggleStyle(.switch)
                        .help("Active les fonctions de dépôt et validation des factures via SUPER PDP. Si désactivé, seul le bouton « Valider » reste disponible sur la facture.")
                        if activeSuperPDPCredentialsBinding.wrappedValue.usePDP {
                        HStack {
                            Text("Client ID").frame(width: 100, alignment: .leading)
                            TextField("Client ID", text: activeSuperPDPCredentialsBinding.clientID)
                        }
                        HStack {
                            Text("Client Secret").frame(width: 100, alignment: .leading)
                            SecureField("Client Secret", text: activeSuperPDPCredentialsBinding.clientSecret)
                        }
                        HStack {
                            Text("Base API").frame(width: 100, alignment: .leading)
                            TextField("https://api.superpdp.tech", text: activeSuperPDPCredentialsBinding.apiBaseURL)
                        }
                        HStack {
                            Text("Synchronisation").frame(width: 100, alignment: .leading)
                            Stepper(
                                value: activeSuperPDPCredentialsBinding.syncIntervalMinutes,
                                in: SuperPDPCredentials.minSyncIntervalMinutes...120,
                                step: 5
                            ) {
                                Text("Toutes les \(activeSuperPDPCredentialsBinding.wrappedValue.syncIntervalMinutes) min")
                            }
                            .help("Cadence du cycle en arrière-plan qui interroge SUPER PDP pour les factures déposées et applique tout avancement de statut reçu.")
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
                                if let cid = connectionsSocietyID {
                                    superPDPSettings.setOverride(activeSuperPDPCredentialsBinding.wrappedValue, companyID: cid)
                                } else {
                                    superPDPSettings.save()
                                }
                            } label: { Label("Enregistrer", systemImage: "checkmark.circle") }
                                .buttonStyle(.borderedProminent)
                            Button {
                                superPDPTesting = true
                                superPDPTestMessage = nil
                                let creds = superPDPSettings.credentials(for: connectionsSocietyID)
                                Task {
                                    do {
                                        let service = SuperPDPService()
                                        let company = try await service.getCompany(credentials: creds)
                                        superPDPTestMessage = "Connexion réussie — \(company.formalName ?? "société") (env : \(company.env ?? "?"))"
                                    } catch {
                                        superPDPTestMessage = "Échec : \(error.localizedDescription)"
                                    }
                                    superPDPTesting = false
                                }
                            } label: { Label("Tester la connexion", systemImage: "antenna.radiowaves.left.and.right") }
                                .buttonStyle(.bordered)
                                .disabled(superPDPTesting || !superPDPSettings.credentials(for: connectionsSocietyID).isConfigured)
                            Button {
                                pdpSessionChecking = true
                                pdpSessionMessage = nil
                                let creds = superPDPSettings.credentials(for: connectionsSocietyID)
                                Task {
                                    do {
                                        let service = SuperPDPService()
                                        let session = try await service.getSession(credentials: creds)
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
                            .disabled(pdpSessionChecking || !superPDPSettings.credentials(for: connectionsSocietyID).isConfigured)
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
                        if let cid = connectionsSocietyID {
                            if smtpSettings.credentialsBySociety[cid] == nil {
                                HStack(spacing: 6) {
                                    Text(directory.principaleSocieteID != nil && cid != directory.principaleSocieteID ? "Hérite actuellement de la société principale." : "Utilise actuellement le réglage par défaut.").font(.caption2).foregroundStyle(.secondary)
                                    Button("Personnaliser pour cette société") {
                                        smtpSettings.setOverride(smtpSettings.credentials(for: cid), companyID: cid)
                                    }.buttonStyle(.link).font(.caption2)
                                }
                            } else {
                                Button("Revenir au réglage hérité", role: .destructive) {
                                    smtpSettings.removeOverride(companyID: cid)
                                }.buttonStyle(.link).font(.caption2)
                            }
                        }
                        Toggle(isOn: activeSMTPCredentialsBinding.alertsEnabled) {
                            Text("Activer les alertes email").font(.body.weight(.semibold))
                        }
                        .toggleStyle(.switch)
                        if activeSMTPCredentialsBinding.wrappedValue.alertsEnabled {
                            HStack {
                                Text("Serveur").frame(width: 100, alignment: .leading)
                                TextField("smtp.exemple.fr", text: activeSMTPCredentialsBinding.host)
                                Text("Port").foregroundStyle(.secondary)
                                TextField("465", value: activeSMTPCredentialsBinding.port, format: .number)
                                    .frame(width: 70)
                            }
                            Toggle("TLS implicite (recommandé, port 465)", isOn: activeSMTPCredentialsBinding.useTLS)
                                .toggleStyle(.switch)
                            HStack {
                                Text("Utilisateur").frame(width: 100, alignment: .leading)
                                TextField("Identifiant SMTP", text: activeSMTPCredentialsBinding.username)
                            }
                            HStack {
                                Text("Mot de passe").frame(width: 100, alignment: .leading)
                                SecureField("Mot de passe SMTP", text: activeSMTPCredentialsBinding.password)
                            }
                            HStack {
                                Text("Expéditeur").frame(width: 100, alignment: .leading)
                                TextField("alertes@votre-domaine.fr", text: activeSMTPCredentialsBinding.fromAddress)
                                TextField("Nom affiché", text: activeSMTPCredentialsBinding.fromName).frame(width: 160)
                            }
                            Divider()
                            Text("Déclencheurs").font(.caption.bold())
                            Toggle("Nouvel utilisateur créé", isOn: activeSMTPCredentialsBinding.alertOnNewUser)
                                .toggleStyle(.switch)
                            Toggle("Changement de statut de facture (Acceptée/Rejetée/Payée/Annulée)", isOn: activeSMTPCredentialsBinding.alertOnInvoiceStatusChange)
                                .toggleStyle(.switch)
                            HStack {
                                Button {
                                    if let cid = connectionsSocietyID {
                                        smtpSettings.setOverride(activeSMTPCredentialsBinding.wrappedValue, companyID: cid)
                                    } else {
                                        smtpSettings.save()
                                    }
                                } label: { Label("Enregistrer", systemImage: "checkmark.circle") }
                                    .buttonStyle(.borderedProminent)
                                Button {
                                    smtpTesting = true
                                    smtpTestMessage = nil
                                    let creds = smtpSettings.credentials(for: connectionsSocietyID)
                                    let recipient = auth.currentUser?.username ?? creds.fromAddress
                                    Task {
                                        do {
                                            try await SMTPService().send(
                                                to: recipient,
                                                subject: "Test SMTP — Factur-X",
                                                body: "Ceci est un email de test envoyé depuis les Réglages de Factur-X.",
                                                credentials: creds
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
                                .disabled(smtpTesting || !smtpSettings.credentials(for: connectionsSocietyID).isConfigured)
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

                DisclosureGroup(isExpanded: $pcloudExpanded) {
                    CloudBackupSettingsView(initialSocietyID: connectionsSocietyID)
                        .id(connectionsSocietyID)
                        .padding(8)
                } label: {
                    Label("Sauvegarde cloud (pCloud)", systemImage: "icloud.and.arrow.up")
                        .font(.headline)
                }

                Spacer()
            }.padding()
        }
    }
}
