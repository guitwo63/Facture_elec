import SwiftUI
import AppKit
import CoreImage
import UniformTypeIdentifiers
import FacturXCore

private struct EnvironmentModeButton: View {
    let systemImage: String
    let title: String
    let color: Color
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 28))
                Text(title)
                    .font(.caption.bold())
            }
            .frame(width: 140, height: 72)
            .foregroundStyle(isActive ? Color.white : Color.secondary)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isActive ? color : Color.gray.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isActive ? color : Color.gray.opacity(0.3), lineWidth: isActive ? 0 : 1)
        )
        .shadow(color: isActive ? color.opacity(0.4) : .clear, radius: 6, y: 2)
    }
}

struct LoginView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var appEnv: AppEnvironment
    @State private var username = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var attempting = false
    @State private var mustChangePasswordUser: User?
    @State private var newPassword = ""
    @State private var newPasswordConfirm = ""
    @State private var newPasswordError: String?
    @State private var pendingTwoFactorUserID: UUID?
    @State private var twoFactorCode = ""
    @State private var twoFactorError: String?
    @State private var twoFactorAttempting = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.accentColor)
                Text("Factur-X").font(.largeTitle.bold())
                Text("Connexion").font(.title3).foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                EnvironmentModeButton(
                    systemImage: "checkmark.seal.fill",
                    title: "PRODUCTION",
                    color: .green,
                    isActive: appEnv.mode == .production
                ) { appEnv.setMode(.production) }
                EnvironmentModeButton(
                    systemImage: "flask.fill",
                    title: "TEST",
                    color: .orange,
                    isActive: appEnv.mode == .test
                ) { appEnv.setMode(.test) }
            }
            VStack(spacing: 12) {
                TextField("Adresse e-mail", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
                    .disableAutocorrection(true)
                SecureField("Mot de passe", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
                    .submitLabel(.go)
                    .onSubmit { attemptLogin() }
                if let err = errorMessage {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
                Button {
                    attemptLogin()
                } label: {
                    HStack {
                        if attempting { ProgressView().controlSize(.small).tint(.white) }
                        Label("Se connecter", systemImage: "arrow.right.circle.fill")
                    }
                    .frame(width: 280)
                }
                .buttonStyle(.borderedProminent)
                .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty || attempting)
            }
            VStack(spacing: 4) {
                Text("Compte admin par défaut : admin@facturx.local / admin")
                    .font(.caption2).foregroundStyle(.tertiary)
                Text("Pensez à modifier le mot de passe après la première connexion.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            VStack(spacing: 6) {
                Link(destination: AppVersion.repositoryURL) {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                        Text("github.com/guitwo63/Facture_elec")
                    }
                    .font(.callout.weight(.medium))
                }
                Text("Facture_elec v\(AppVersion.current)")
                    .font(.caption2).foregroundStyle(.secondary)
                Text("© 2026 \(AppVersion.copyrightHolder) — \(AppVersion.licenseName)")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .sheet(item: $mustChangePasswordUser) { user in
            VStack(spacing: 16) {
                Text("Changer le mot de passe").font(.title3.bold())
                Text("Vous devez définir un nouveau mot de passe avant de continuer.")
                    .font(.caption).foregroundStyle(.secondary)
                SecureField("Nouveau mot de passe", text: $newPassword)
                    .textFieldStyle(.roundedBorder).frame(width: 300)
                SecureField("Confirmer", text: $newPasswordConfirm)
                    .textFieldStyle(.roundedBorder).frame(width: 300)
                if let err = newPasswordError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
                HStack {
                    Button("Annuler") {
                        auth.logout()
                        mustChangePasswordUser = nil
                        newPassword = ""; newPasswordConfirm = ""; newPasswordError = nil
                    }.keyboardShortcut(.cancelAction)
                    Button("Enregistrer") {
                        newPasswordError = nil
                        guard !newPassword.isEmpty, newPassword == newPasswordConfirm else {
                            newPasswordError = "Les mots de passe ne correspondent pas."
                            return
                        }
                        do {
                            try auth.updatePassword(user, newPassword: newPassword)
                            mustChangePasswordUser = nil
                            newPassword = ""; newPasswordConfirm = ""
                        } catch {
                            newPasswordError = error.localizedDescription
                        }
                    }.buttonStyle(.borderedProminent)
                }
            }.padding(40)
        }
        .sheet(isPresented: Binding(
            get: { pendingTwoFactorUserID != nil },
            set: { if !$0 { pendingTwoFactorUserID = nil } }
        )) {
            VStack(spacing: 16) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 36)).foregroundStyle(Color.accentColor)
                Text("Double authentification").font(.title3.bold())
                Text("Entrez le code à 6 chiffres de votre application d'authentification, ou un de vos codes de récupération.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
                TextField("Code", text: $twoFactorCode)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .multilineTextAlignment(.center)
                    .submitLabel(.go)
                    .onSubmit { completeTwoFactor() }
                if let err = twoFactorError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
                HStack {
                    Button("Annuler") {
                        pendingTwoFactorUserID = nil
                        twoFactorCode = ""
                        twoFactorError = nil
                    }.keyboardShortcut(.cancelAction)
                    Button {
                        completeTwoFactor()
                    } label: {
                        HStack {
                            if twoFactorAttempting { ProgressView().controlSize(.small) }
                            Text("Valider")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(twoFactorCode.trimmingCharacters(in: .whitespaces).isEmpty || twoFactorAttempting)
                }
            }.padding(30).frame(width: 320)
        }
    }

    private func completeTwoFactor() {
        guard let userID = pendingTwoFactorUserID else { return }
        twoFactorAttempting = true
        twoFactorError = nil
        do {
            let user = try auth.completeTwoFactorLogin(userID: userID, code: twoFactorCode)
            pendingTwoFactorUserID = nil
            twoFactorCode = ""
            if user.mustChangePassword && !auth.testBypassSecurity {
                mustChangePasswordUser = user
            }
        } catch {
            twoFactorError = error.localizedDescription
        }
        twoFactorAttempting = false
    }

    private func attemptLogin() {
        attempting = true
        errorMessage = nil
        do {
            let user = try auth.login(username: username, password: password)
            if user.mustChangePassword && !auth.testBypassSecurity {
                mustChangePasswordUser = user
            }
        } catch AuthError.twoFactorRequired(let userID) {
            pendingTwoFactorUserID = userID
            twoFactorCode = ""
            twoFactorError = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        attempting = false
    }
}

// MARK: - Journal d'audit (B1)

struct AuditLogView: View {
    @EnvironmentObject var auth: AuthStore
    @State private var query = ""
    @State private var typeFilter: AuditObjectType? = nil
    @State private var statusOnly = false

    private var isAdmin: Bool { auth.currentUser?.isAdmin == true }

    /// Types d'objets visibles selon le rôle : un non-admin ne doit pas voir les
    /// événements liés aux comptes utilisateurs (créations, verrouillages…), qui
    /// relèvent de l'administration et pas du suivi métier des documents.
    private var visibleObjectTypes: [AuditObjectType] {
        AuditObjectType.allCases.filter { isAdmin || $0 != .user }
    }

    /// Entrées visibles pour le rôle courant, avant recherche/filtre de type.
    private var visibleEntries: [AuditLogEntry] {
        let all = auth.audit.entries
        return isAdmin ? all : all.filter { $0.objectType != .user }
    }

    var filtered: [AuditLogEntry] {
        var result = visibleEntries
        if let t = typeFilter { result = result.filter { $0.objectType == t } }
        if statusOnly { result = result.filter { $0.action == "status_change" } }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return result }
        return result.filter {
            $0.actor.lowercased().contains(q) || $0.action.lowercased().contains(q)
            || $0.target.lowercased().contains(q) || $0.details.lowercased().contains(q)
            || ($0.objectCode ?? "").lowercased().contains(q)
            || ($0.statusFrom ?? "").lowercased().contains(q) || ($0.statusTo ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Journal d'audit").font(.title2.bold())
                Spacer()
                Text("\(visibleEntries.count) / \(auth.audit.maxEntries)")
                    .font(.caption).foregroundStyle(.secondary)
                if isAdmin {
                    Button(role: .destructive) {
                        auth.audit.clear()
                    } label: { Label("Vider", systemImage: "trash") }
                        .buttonStyle(.bordered)
                }
            }.padding(10)
            HStack {
                TextField("Rechercher", text: $query)
                    .textFieldStyle(.roundedBorder)
                Picker("Type", selection: $typeFilter) {
                    Text("Tous").tag(AuditObjectType?.none)
                    ForEach(visibleObjectTypes, id: \.self) { t in
                        Text(t.label).tag(AuditObjectType?.some(t))
                    }
                }
                .pickerStyle(.menu).frame(width: 160)
                Toggle("Statuts uniquement", isOn: $statusOnly)
            }
            .padding(.horizontal, 10).padding(.bottom, 8)
            Divider()
            Table(filtered) {
                TableColumn("Date") { e in
                    Text(e.timestamp, format: .dateTime.day().month().year().hour().minute())
                        .font(.caption.monospacedDigit())
                }.width(140)
                TableColumn("Type") { e in
                    Text(e.objectType?.label ?? "").font(.caption)
                }.width(90)
                TableColumn("Acteur") { e in Text(e.actor).font(.caption) }.width(120)
                TableColumn("Code") { e in Text(e.objectCode ?? e.target).font(.caption) }.width(120)
                TableColumn("Action") { e in Text(e.action).font(.caption) }.width(120)
                TableColumn("Détails") { e in
                    if e.action == "status_change" {
                        Text("\(e.statusFrom ?? "?") → \(e.statusTo ?? "?")")
                            .font(.caption)
                    } else {
                        Text(e.details).font(.caption)
                    }
                }
            }
        }
    }
}

struct UserManagementView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var directory: PartyDirectory
    @State private var selectedUserID: UUID?
    @State private var editingUser: User?
    @State private var creatingUser = false
    @State private var searchQuery = ""
    @State private var roleFilter: UserRole? = nil

    private var filteredUsers: [User] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        var result = auth.users
        if let rf = roleFilter {
            result = result.filter { $0.hasRole(rf) }
        }
        guard !q.isEmpty else { return result }
        return result.filter {
            $0.username.lowercased().contains(q) ||
            $0.effectiveDisplayName.lowercased().contains(q) ||
            $0.rolesLabel.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Gestion utilisateurs").font(.title2.bold())
                Spacer()
                Text("\(auth.users.count) utilisateur(s)").font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
            Divider()
            HSplitView {
                usersSection
                    .frame(minWidth: 300, idealWidth: 340, maxWidth: 420)
                Group {
                    if let id = selectedUserID, let user = auth.users.first(where: { $0.id == id }) {
                        ScrollView {
                            UserDetailCard(user: user, onChange: { updated in auth.upsert(updated) },
                                           onResetPassword: { pw in try? auth.updatePassword(user, newPassword: pw, forceChange: true) })
                                .padding(12)
                        }
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: "person.badge.shield.checkmark").font(.largeTitle).foregroundStyle(.secondary)
                            Text("Sélectionnez un utilisateur.").foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 360)
            }
        }
        .sheet(isPresented: $creatingUser) {
            UserEditorSheet { username, displayName, password, roles, societyIDs, defaultSeller in
                do {
                    _ = try auth.createUser(username: username, password: password,
                                            displayName: displayName, roles: roles, societyIDs: societyIDs,
                                            defaultSellerEntryID: defaultSeller)
                } catch {
                    return error.localizedDescription
                }
                creatingUser = false
                return nil
            }
        }
        .sheet(item: $editingUser) { user in
            UserEditorSheet(existing: user) { username, displayName, password, roles, societyIDs, defaultSeller in
                var updated = user
                updated.username = username
                updated.displayName = displayName
                updated.roles = roles
                updated.societyIDs = societyIDs
                updated.defaultSellerEntryID = defaultSeller
                auth.upsert(updated)
                if !password.isEmpty {
                    do {
                        try auth.updatePassword(updated, newPassword: password, forceChange: true)
                    } catch {
                        return error.localizedDescription
                    }
                }
                editingUser = nil
                return nil
            }
        }
    }

    private var usersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Rechercher un utilisateur", text: $searchQuery)
                    .textFieldStyle(.plain)
                Spacer()
                Button { creatingUser = true } label: { Label("Nouveau", systemImage: "plus") }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
            .padding(.horizontal, 8).padding(.top, 8)
            Picker("Rôle", selection: $roleFilter) {
                Text("Tous").tag(UserRole?.none)
                ForEach(UserRole.allCases, id: \.self) { r in Text(r.label).tag(UserRole?.some(r)) }
            }
            .labelsHidden().pickerStyle(.segmented)
            .padding(.horizontal, 8)
            List(filteredUsers, selection: Binding(
                get: { selectedUserID },
                set: { selectedUserID = $0 }
            )) { user in
                HStack(spacing: 8) {
                    Image(systemName: user.role.systemImage)
                        .foregroundStyle(roleColor(user.role))
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.effectiveDisplayName).font(.body.weight(.medium))
                        Text("@\(user.username)").font(.caption2).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Text(user.rolesLabel).font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(roleColor(user.role).opacity(0.18), in: Capsule())
                                .foregroundStyle(roleColor(user.role))
                            if !user.isAdmin {
                                Text("\(user.societyIDs.count) société(s)").font(.caption2).foregroundStyle(.secondary)
                            }
                            if !user.isActive {
                                Text("Désactivé").font(.caption2.bold()).foregroundStyle(.white)
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Color.red, in: Capsule())
                            }
                        }
                    }
                    Spacer()
                }
                .opacity(user.isActive ? 1 : 0.6)
                .padding(.vertical, 2)
                .contextMenu {
                    Button { editingUser = user } label: { Label("Modifier", systemImage: "pencil") }
                    Divider()
                    Button {
                        var u = user; u.isActive.toggle(); auth.upsert(u)
                    } label: { Label(user.isActive ? "Désactiver" : "Activer",
                                    systemImage: user.isActive ? "minus.circle" : "checkmark.circle") }
                    if !user.isAdmin || auth.users.filter({ $0.isAdmin }).count > 1 {
                        Divider()
                        Button(role: .destructive) {
                            auth.delete(user)
                            if selectedUserID == user.id { selectedUserID = nil }
                        } label: { Label("Supprimer", systemImage: "trash") }
                    }
                }
            }
        }
    }

    private func roleColor(_ role: UserRole) -> Color {
        switch role {
        case .admin: return .red
        case .comptable: return .blue
        case .acheteur: return .green
        }
    }
}

struct UserDetailCard: View {
    let user: User
    let onChange: (User) -> Void
    let onResetPassword: (String) -> Void
    @EnvironmentObject var auth: AuthStore
    @State private var newPw = ""
    @State private var newPwConfirm = ""

    var body: some View {
        GroupBox("Utilisateur : \(user.effectiveDisplayName)") {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Identifiant") { Text("@\(user.username)") }
                LabeledContent("Profils") { Text(user.rolesLabel) }
                LabeledContent("Statut") {
                    HStack(spacing: 8) {
                        Toggle(isOn: Binding(
                            get: { user.isActive },
                            set: { active in
                                var u = user
                                u.isActive = active
                                onChange(u)
                            }
                        )) {
                            Text(user.isActive ? "Actif" : "Désactivé")
                                .foregroundStyle(user.isActive ? .green : .red)
                        }
                        .toggleStyle(.switch)
                        if !user.isActive {
                            Text("connexion bloquée").font(.caption).foregroundStyle(.red)
                        }
                    }
                }
                Divider()
                Text("Sociétés du périmètre").font(.headline)
                if user.isAdmin {
                    Text("L'administrateur accède à toutes les sociétés.").font(.caption).foregroundStyle(.secondary)
                } else if auth.availableSocieties().isEmpty {
                    Text("Aucune société (fiche société) définie dans l'annuaire.").font(.caption).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(auth.availableSocieties()) { s in
                            HStack {
                                Toggle(isOn: Binding(
                                    get: { user.societyIDs.contains(s.id) },
                                    set: { checked in
                                        var u = user
                                        if checked { u.societyIDs.append(s.id) }
                                        else {
                                            u.societyIDs.removeAll { $0 == s.id }
                                            if u.defaultSellerEntryID == s.id { u.defaultSellerEntryID = nil }
                                        }
                                        onChange(u)
                                    }
                                )) {
                                    Text(s.displayName)
                                }
                                Spacer()
                                if user.defaultSellerEntryID == s.id {
                                    Text("(société par défaut)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Divider()
                Text("Réinitialiser le mot de passe").font(.headline)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        SecureField("Nouveau mot de passe", text: $newPw)
                            .textFieldStyle(.roundedBorder).frame(width: 240)
                        SecureField("Confirmer", text: $newPwConfirm)
                            .textFieldStyle(.roundedBorder).frame(width: 240)
                        Button {
                            onResetPassword(newPw)
                            newPw = ""
                            newPwConfirm = ""
                        } label: { Label("Appliquer", systemImage: "checkmark.circle") }
                            .buttonStyle(.borderedProminent)
                            .disabled(newPw.isEmpty || newPw != newPwConfirm)
                    }
                    if !newPw.isEmpty && !newPwConfirm.isEmpty && newPw != newPwConfirm {
                        Text("Les mots de passe ne correspondent pas.").font(.caption).foregroundStyle(.red)
                    }
                }
                if user.totpEnabled {
                    Divider()
                    Text("Double authentification").font(.headline)
                    HStack {
                        Label("Activée sur ce compte", systemImage: "checkmark.shield.fill")
                            .font(.caption).foregroundStyle(.green)
                        Spacer()
                        Button(role: .destructive) {
                            auth.disableTwoFactor(for: user, actor: auth.currentUser?.username ?? "admin")
                        } label: { Label("Désactiver (perte d'accès)", systemImage: "shield.slash") }
                            .buttonStyle(.bordered)
                            .help("Chemin de secours si l'utilisateur a perdu l'accès à son application d'authentification")
                    }
                }
            }
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct CompanyDetailCard: View {
    let entry: DirectoryEntry

    var body: some View {
        GroupBox("Société : \(entry.displayName)") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Nom") { Text(entry.displayName) }
                if let s = entry.party.siren, !s.isEmpty {
                    LabeledContent("SIREN") { Text(s) }
                } else {
                    LabeledContent("SIREN") { Text("—").foregroundStyle(.secondary) }
                }
                LabeledContent("Type") { Text(entry.kind.label) }
                if let city = entry.party.city.trimmingCharacters(in: .whitespaces) as String?, !city.isEmpty {
                    LabeledContent("Ville") { Text(city) }
                }
            }
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct UserEditorSheet: View {
    var existing: User?
    /// Retourne un message d'erreur à afficher (et ne ferme pas la feuille) en cas
    /// d'échec, `nil` en cas de succès (la feuille se ferme alors).
    let onSave: (String, String, String, [UserRole], [UUID], UUID?) -> String?
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var directory: PartyDirectory
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var displayName = ""
    @State private var password = ""
    @State private var selectedRoles: Set<UserRole> = [.comptable]
    @State private var societyIDs: Set<UUID> = []
    @State private var defaultSellerEntryID: UUID? = nil
    @State private var saveError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(existing == nil ? "Nouvel utilisateur" : "Modifier l'utilisateur")
                    .font(.title3.bold())
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider()
            // Contenu dans un ScrollView : la liste des sociétés (Réglages > Application >
            // Sociétés du périmètre) grandit avec l'annuaire — sans défilement, elle finissait
            // par masquer le bas du formulaire (voire le bouton Enregistrer) une fois la fenêtre
            // à taille fixe débordée.
            ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Identifiant (e-mail)").frame(width: 140, alignment: .leading)
                    TextField("admin@facturx.local", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .disableAutocorrection(true)
                }
                HStack {
                    Text("Nom affiché").frame(width: 140, alignment: .leading)
                    TextField("Nom affiché", text: $displayName).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text(existing == nil ? "Mot de passe" : "Nouveau mot de passe (optionnel)")
                        .frame(width: 140, alignment: .leading)
                    SecureField("mot de passe", text: $password).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Profils").frame(width: 140, alignment: .leading)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(UserRole.allCases, id: \.self) { r in
                            Toggle(isOn: Binding(
                                get: { selectedRoles.contains(r) },
                                set: { checked in
                                    if checked { selectedRoles.insert(r) }
                                    else if selectedRoles.count > 1 { selectedRoles.remove(r) }
                                }
                            )) {
                                Text(r.label)
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
                if selectedRoles.contains(.comptable) || selectedRoles.contains(.acheteur) {
                    Divider()
                    Text("Sociétés du périmètre (fiches sociétés de l'annuaire)").font(.headline)
                    if availableSocieties.isEmpty {
                        Text("Aucune société disponible. Créez d'abord une fiche société dans l'onglet Annuaire.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(availableSocieties) { s in
                                HStack {
                                    Toggle(isOn: Binding(
                                        get: { societyIDs.contains(s.id) },
                                        set: { checked in
                                            if checked { societyIDs.insert(s.id) }
                                            else {
                                                societyIDs.remove(s.id)
                                                if defaultSellerEntryID == s.id { defaultSellerEntryID = nil }
                                            }
                                        }
                                    )) {
                                        Text(s.displayName)
                                    }
                                    Spacer()
                                    if societyIDs.contains(s.id) {
                                        Toggle(isOn: Binding(
                                            get: { defaultSellerEntryID == s.id },
                                            set: { isDefault in
                                                defaultSellerEntryID = isDefault ? s.id : nil
                                            }
                                        )) {
                                            Text("Émetteur par défaut").font(.caption)
                                        }
                                        .toggleStyle(.checkbox)
                                    }
                                }
                            }
                        }
                        if societyIDs.isEmpty {
                            Text("Au moins une société est requise pour un comptable.")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
            }
            .padding()
            }
            Divider()
            if let err = validationError ?? saveError {
                Text(err).font(.caption).foregroundStyle(.red).padding(.horizontal)
            }
            HStack {
                Spacer()
                Button("Enregistrer") {
                    let ordered = UserRole.allCases.filter { selectedRoles.contains($0) }
                    if let error = onSave(username.trimmingCharacters(in: .whitespaces), displayName, password, ordered, Array(societyIDs), defaultSellerEntryID) {
                        saveError = error
                    } else {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
            .padding()
        }
        .frame(width: 580, height: 520)
        .onAppear {
            if let u = existing {
                username = u.username
                displayName = u.displayName
                selectedRoles = Set(u.roles)
                societyIDs = Set(u.societyIDs)
                defaultSellerEntryID = u.defaultSellerEntryID
            }
        }
    }

    private var availableSocieties: [DirectoryEntry] {
        directory.entries.filter { !$0.isArchived && $0.kind == .societe }
    }

    private var validationError: String? {
        let trimmed = username.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard EmailValidator.isValid(trimmed) else { return "Identifiant invalide : doit être une adresse e-mail." }
        if auth.users.contains(where: { $0.username.lowercased() == trimmed.lowercased() && $0.id != existing?.id }) {
            return "Cet identifiant est déjà utilisé."
        }
        return nil
    }

    private var canSave: Bool {
        let trimmed = username.trimmingCharacters(in: .whitespaces)
        let nameOK = EmailValidator.isValid(trimmed)
        let pwOK = existing != nil || !password.isEmpty
        let scopeOK = selectedRoles.contains(.admin) || !societyIDs.isEmpty
        let noDup = validationError == nil
        return nameOK && pwOK && scopeOK && noDup
    }
}

struct ProfileSettingsView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var store: InvoiceStore
    @EnvironmentObject var directory: PartyDirectory
    @EnvironmentObject var twoFactorSettings: TwoFactorSettings
    @State private var newPw = ""
    @State private var confirmPw = ""
    @State private var saved = false
    @State private var error: String?
    @State private var showSellerPicker = false
    @State private var showTwoFactorEnrollment = false
    @State private var recoveryCodesToShow: [String]?
    @State private var confirmDisableTwoFactor = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let user = auth.currentUser {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: user.role.systemImage)
                                    .font(.title2).foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(user.effectiveDisplayName).font(.body.weight(.semibold))
                                    Text(user.username).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(user.role.label).font(.caption2)
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(.quaternary, in: Capsule())
                            }
                            if user.hasRole(.comptable) || user.hasRole(.acheteur), !user.societyIDs.isEmpty {
                                Divider()
                                Text("Sociétés du périmètre").font(.caption.bold())
                                ForEach(auth.visibleSocieties(for: user)) { s in
                                    Text("• \(s.displayName)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Émetteur par défaut").font(.headline)
                            Text("L’émetteur par défaut est un lien vers une fiche société de l’annuaire. Les modifications de la fiche (IBAN, BIC, conditions de paiement…) sont reprises automatiquement à la création de chaque facture.")
                                .font(.caption).foregroundStyle(.secondary)
                            let linkedEntry: DirectoryEntry? = (user.defaultSellerEntryID ?? store.defaultSellerEntryID).flatMap { id in directory.entries.first { $0.id == id } }
                            if let entry = linkedEntry {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.party.name).font(.body.weight(.semibold))
                                    if let s = entry.party.siren, !s.isEmpty { Text("SIREN : \(s)").font(.caption).foregroundStyle(.secondary) }
                                    if let st = entry.party.siret, !st.isEmpty { Text("SIRET : \(st)").font(.caption).foregroundStyle(.secondary) }
                                    if let v = entry.party.vatNumber, !v.isEmpty { Text("TVA : \(v)").font(.caption).foregroundStyle(.secondary) }
                                    if let iban = entry.party.iban, !iban.isEmpty { Text("IBAN : \(iban)").font(.caption).foregroundStyle(.secondary) }
                                    if let bic = entry.party.bic, !bic.isEmpty { Text("BIC : \(bic)").font(.caption).foregroundStyle(.secondary) }
                                    if let pt = entry.party.paymentTerms, !pt.isEmpty { Text("Conditions : \(pt)").font(.caption).foregroundStyle(.secondary) }
                                }
                                HStack {
                                    Button {
                                        showSellerPicker = true
                                    } label: { Label("Changer", systemImage: "person.crop.circle.badge.plus") }
                                        .buttonStyle(.bordered)
                                    Button(role: .destructive) {
                                        var u = user
                                        u.defaultSellerEntryID = nil
                                        auth.upsert(u)
                                        if store.defaultSellerEntryID != nil {
                                            store.defaultSellerEntryID = nil
                                            store.save()
                                        }
                                    } label: { Label("Dissocier", systemImage: "minus.circle") }
                                        .buttonStyle(.bordered)
                                    Spacer()
                                }
                            } else {
                                Text("Aucun émetteur par défaut défini.").font(.caption).foregroundStyle(.tertiary)
                                Button {
                                    showSellerPicker = true
                                } label: { Label("Choisir une société dans l’annuaire", systemImage: "person.crop.circle.badge.plus") }
                                    .buttonStyle(.bordered)
                            }
                        }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .sheet(isPresented: $showSellerPicker) {
                        PartyPickerSheet(role: .seller) { selected in
                            var u = user
                            u.defaultSellerEntryID = selected.id
                            auth.upsert(u)
                            showSellerPicker = false
                        }
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Changer le mot de passe").font(.headline)
                            SecureField("Nouveau mot de passe", text: $newPw)
                                .textFieldStyle(.roundedBorder).frame(width: 280)
                            SecureField("Confirmer le mot de passe", text: $confirmPw)
                                .textFieldStyle(.roundedBorder).frame(width: 280)
                            HStack {
                                Button {
                                    savePassword(user)
                                } label: { Label("Enregistrer", systemImage: "checkmark.circle") }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(newPw.isEmpty || newPw != confirmPw)
                                if saved {
                                    Text("Mot de passe mis à jour").font(.caption).foregroundStyle(.green)
                                }
                                if let error = error {
                                    Text(error).font(.caption).foregroundStyle(.red)
                                }
                            }
                            if !newPw.isEmpty && newPw != confirmPw {
                                Text("Les mots de passe ne correspondent pas.")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if twoFactorSettings.enabledSolutionWide {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Double authentification (2FA)").font(.headline)
                                if user.totpEnabled {
                                    Label("Activée sur ce compte", systemImage: "checkmark.shield.fill")
                                        .font(.caption).foregroundStyle(.green)
                                    Button(role: .destructive) {
                                        confirmDisableTwoFactor = true
                                    } label: { Label("Désactiver", systemImage: "shield.slash") }
                                        .buttonStyle(.bordered)
                                } else {
                                    Text("Protège votre compte avec un code à 6 chiffres généré par une application d'authentification (Google Authenticator, Authy…), en plus de votre mot de passe.")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Button {
                                        showTwoFactorEnrollment = true
                                    } label: { Label("Activer la 2FA", systemImage: "lock.shield") }
                                        .buttonStyle(.bordered)
                                }
                            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .alert("Désactiver la double authentification ?", isPresented: $confirmDisableTwoFactor) {
                            Button("Annuler", role: .cancel) { }
                            Button("Désactiver", role: .destructive) {
                                auth.disableTwoFactor(for: user, actor: user.username)
                            }
                        } message: {
                            Text("Vous devrez la reconfigurer entièrement (nouveau QR code, nouveaux codes de récupération) si vous voulez la réactiver.")
                        }
                        .sheet(isPresented: $showTwoFactorEnrollment) {
                            TwoFactorEnrollmentSheet(user: user) { codes in
                                showTwoFactorEnrollment = false
                                recoveryCodesToShow = codes
                            }
                        }
                        .sheet(isPresented: Binding(
                            get: { recoveryCodesToShow != nil },
                            set: { if !$0 { recoveryCodesToShow = nil } }
                        )) {
                            if let codes = recoveryCodesToShow {
                                RecoveryCodesSheet(codes: codes) { recoveryCodesToShow = nil }
                            }
                        }
                    }
                } else {
                    Text("Aucun utilisateur connecté.").foregroundStyle(.secondary)
                }
                Spacer()
            }.padding()
        }
    }

    private func savePassword(_ user: User) {
        error = nil
        saved = false
        do {
            try auth.updatePassword(user, newPassword: newPw)
            saved = true
            newPw = ""
            confirmPw = ""
        } catch {
            self.error = error.localizedDescription
        }
    }
}

enum QRCodeRenderer {
    static func image(for string: String, scale: CGFloat = 8) -> NSImage? {
        guard !string.isEmpty, let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(string.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rep = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}

struct TwoFactorEnrollmentSheet: View {
    let user: User
    var onEnrolled: ([String]) -> Void
    @EnvironmentObject var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @State private var secret = ""
    @State private var provisioningURI = ""
    @State private var code = ""
    @State private var error: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Activer la double authentification").font(.title3.bold())
            Text("Scannez ce QR code avec votre application d'authentification (Google Authenticator, Authy…), ou saisissez la clé manuellement, puis entrez le code affiché pour confirmer.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            if let qr = QRCodeRenderer.image(for: provisioningURI) {
                Image(nsImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 180, height: 180)
            }
            VStack(spacing: 4) {
                Text("Clé manuelle").font(.caption.bold())
                Text(secret)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            TextField("Code à 6 chiffres", text: $code)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
                .multilineTextAlignment(.center)
                .onSubmit { confirm() }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Button("Annuler") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Activer") { confirm() }
                    .buttonStyle(.borderedProminent)
                    .disabled(code.trimmingCharacters(in: .whitespaces).count != 6)
            }
        }
        .padding(30)
        .frame(width: 360)
        .onAppear {
            let enrollment = auth.beginEnrollTwoFactor(for: user)
            secret = enrollment.secret
            provisioningURI = enrollment.provisioningURI
        }
    }

    private func confirm() {
        error = nil
        do {
            let codes = try auth.confirmEnrollTwoFactor(for: user, secret: secret, code: code)
            onEnrolled(codes)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct RecoveryCodesSheet: View {
    let codes: [String]
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Codes de récupération").font(.title3.bold())
            Text("Conservez ces codes en lieu sûr (gestionnaire de mots de passe, coffre-fort…). Chacun ne peut être utilisé qu'une seule fois pour vous connecter si vous perdez l'accès à votre application d'authentification. Ils ne seront plus jamais affichés après fermeture de cette fenêtre.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(codes, id: \.self) { code in
                    Text(code)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            Button("J'ai noté mes codes") { onDone() }
                .buttonStyle(.borderedProminent)
        }
        .padding(30)
        .frame(width: 340)
    }
}

struct DataAdminView: View {
    @EnvironmentObject var store: InvoiceStore
    @EnvironmentObject var orderStore: OrderStore
    @EnvironmentObject var directory: PartyDirectory
    @EnvironmentObject var auth: AuthStore
    @State private var table: DataTable = .invoices

    enum DataTable: String, CaseIterable, Identifiable {
        case invoices = "Factures"
        case orders = "Commandes"
        case parties = "Tiers"
        case portability = "Export / Import"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Administration des données").font(.title2.bold())
                Spacer()
            }.padding(10)
            Divider()
            HSplitView {
                List(DataTable.allCases, selection: Binding<DataTable?>(
                    get: { table },
                    set: { if let t = $0 { table = t } }
                )) { t in
                    Text(t.rawValue).tag(t)
                }
                .frame(minWidth: 160, idealWidth: 180, maxWidth: 220)
                Group {
                    switch table {
                    case .invoices: DataInvoicesPanel()
                    case .orders: DataOrdersPanel()
                    case .parties: DataPartiesPanel()
                    case .portability: DataPortabilityPanel()
                    }
                }
                .frame(minWidth: 360)
            }
        }
    }
}

struct DataInvoicesPanel: View {
    @EnvironmentObject var store: InvoiceStore
    @State private var query = ""
    @State private var editingID: UUID?
    @State private var remoteIDDraft = ""
    @State private var savedID: UUID?

    private var filtered: [Invoice] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return store.invoices.sorted { $0.number < $1.number } }
        return store.invoices.filter {
            $0.number.lowercased().contains(q)
            || ($0.superPDPRemoteID ?? "").lowercased().contains(q)
            || $0.status.label.lowercased().contains(q)
        }.sorted { $0.number < $1.number }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Rechercher (n°, statut, remote ID)", text: $query)
                    .textFieldStyle(.roundedBorder)
                Spacer()
                Text("\(store.invoices.count) facture(s)").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Réparer le remote ID Super PDP d'une facture désynchronisée.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(filtered) { inv in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(inv.number).font(.headline)
                                Text(inv.type.label).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Image(systemName: inv.status.systemImage)
                                    .foregroundColor(Color(hex: inv.status.hexColor))
                                Text(inv.status.label).font(.caption)
                                Text(inv.issueDate, format: .dateTime.day().month().year())
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            HStack {
                                Text("Remote ID :")
                                    .font(.caption.bold())
                                if editingID == inv.id {
                                    TextField("Remote ID Super PDP", text: $remoteIDDraft)
                                        .textFieldStyle(.roundedBorder)
                                    Button {
                                        var updated = inv
                                        let trimmed = remoteIDDraft.trimmingCharacters(in: .whitespaces)
                                        updated.superPDPRemoteID = trimmed.isEmpty ? nil : trimmed
                                        store.upsert(updated)
                                        editingID = nil
                                        remoteIDDraft = ""
                                        savedID = inv.id
                                    } label: { Label("OK", systemImage: "checkmark.circle.fill") }
                                        .buttonStyle(.borderedProminent).controlSize(.small)
                                    Button {
                                        editingID = nil
                                        remoteIDDraft = ""
                                    } label: { Image(systemName: "xmark") }
                                        .buttonStyle(.bordered).controlSize(.small)
                                } else {
                                    Text(inv.superPDPRemoteID ?? "—")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(inv.superPDPRemoteID == nil ? .secondary : .primary)
                                    Spacer()
                                    Button {
                                        editingID = inv.id
                                        remoteIDDraft = inv.superPDPRemoteID ?? ""
                                    } label: { Label("Modifier", systemImage: "pencil") }
                                        .buttonStyle(.bordered).controlSize(.small)
                                }
                            }
                            if savedID == inv.id {
                                Text("Remote ID enregistré.")
                                    .font(.caption).foregroundStyle(.green)
                            }
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.4)))
                    }
                }
                .padding(10)
            }
        }
        .onChange(of: savedID) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { savedID = nil }
        }
    }
}

struct DataOrdersPanel: View {
    @EnvironmentObject var orderStore: OrderStore
    @EnvironmentObject var statusStore: OrderStatusStore
    @State private var query = ""

    private var filtered: [SalesOrder] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return orderStore.orders.sorted { $0.number < $1.number } }
        return orderStore.orders.filter {
            $0.number.lowercased().contains(q) || $0.status.label.lowercased().contains(q)
        }.sorted { $0.number < $1.number }
    }

    /// Commandes dont le customStatusID pointe vers un statut personnalisé qui
    /// n'existe plus (supprimé depuis Réglages > Statuts) — l'affichage retombe
    /// silencieusement sur le statut standard, mais la référence reste orpheline.
    private func isOrphanedCustomStatus(_ order: SalesOrder) -> Bool {
        guard let cid = order.customStatusID else { return false }
        return !statusStore.overrides.contains { $0.id == cid }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Rechercher (n°, statut)", text: $query)
                    .textFieldStyle(.roundedBorder)
                Spacer()
                Text("\(orderStore.orders.count) commande(s)").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Repère les commandes dont la référence de statut personnalisé n'existe plus.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(filtered) { order in
                        HStack {
                            Text(order.number).font(.headline)
                            Text(order.type.label).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: order.status.systemImage)
                                .foregroundColor(Color(hex: order.status.hexColor))
                            Text(order.status.label).font(.caption)
                            Text(order.issueDate, format: .dateTime.day().month().year())
                                .font(.caption).foregroundStyle(.secondary)
                            if isOrphanedCustomStatus(order) {
                                Button {
                                    if let i = orderStore.orders.firstIndex(where: { $0.id == order.id }) {
                                        orderStore.orders[i].customStatusID = nil
                                        orderStore.save()
                                    }
                                } label: {
                                    Label("Statut orphelin — réinitialiser", systemImage: "exclamationmark.triangle.fill")
                                }
                                .buttonStyle(.bordered).controlSize(.small)
                                .foregroundStyle(.orange)
                                .help("customStatusID « \(order.customStatusID ?? "")» n'existe plus dans Réglages > Statuts des commandes")
                            }
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.4)))
                    }
                }
                .padding(10)
            }
        }
    }
}

struct DataPartiesPanel: View {
    @EnvironmentObject var directory: PartyDirectory
    @State private var query = ""

    private var filtered: [DirectoryEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return directory.entries.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending } }
        return directory.entries.filter {
            $0.displayName.lowercased().contains(q)
                || ($0.party.siren ?? "").lowercased().contains(q)
                || ($0.party.siret ?? "").lowercased().contains(q)
        }.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Rechercher (nom, SIREN, SIRET)", text: $query)
                    .textFieldStyle(.roundedBorder)
                Spacer()
                Text("\(directory.entries.count) tiers").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Vue d'ensemble de l'annuaire (sociétés, clients, archivés).")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(filtered) { entry in
                        HStack {
                            Text(entry.displayName).font(.headline)
                            Text(entry.kind.label).font(.caption).foregroundStyle(.secondary)
                            if let siren = entry.party.siren, !siren.isEmpty {
                                Text("SIREN \(siren)").font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if entry.isArchived {
                                Text("Archivé").font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.gray.opacity(0.2), in: Capsule())
                            }
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.4)))
                    }
                }
                .padding(10)
            }
        }
    }
}

struct DataPortabilityPanel: View {
    @EnvironmentObject var store: InvoiceStore
    @EnvironmentObject var orderStore: OrderStore
    @EnvironmentObject var quoteStore: QuoteStore
    @EnvironmentObject var directory: PartyDirectory
    @EnvironmentObject var invoiceStatusStore: InvoiceStatusStore
    @EnvironmentObject var orderStatusStore: OrderStatusStore
    @EnvironmentObject var tagStore: TagStore
    @EnvironmentObject var kindColorStore: KindColorStore
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Export / Import par module (JSON)").font(.headline)
                    Text("Contrairement aux exports CSV (pensés pour un tableur), ce format structuré conserve toutes les données — lignes, statuts, champs optionnels — et permet donc un import fidèle, pas seulement une extraction pour lecture externe.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                moduleRow(title: "Factures", count: store.invoices.count,
                          onExport: { exportJSON(store.invoices, suggestedName: "factures.json") },
                          onImport: importInvoices)
                moduleRow(title: "Commandes", count: orderStore.orders.count,
                          onExport: { exportJSON(orderStore.orders, suggestedName: "commandes.json") },
                          onImport: importOrders)
                moduleRow(title: "Tiers (annuaire)", count: directory.entries.count,
                          onExport: { exportJSON(directory.entries, suggestedName: "annuaire.json") },
                          onImport: importParties)
                moduleRow(title: "Devis", count: quoteStore.quotes.count,
                          onExport: { exportJSON(quoteStore.quotes, suggestedName: "devis.json") },
                          onImport: importQuotes)

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Configuration").font(.headline)
                    Text("Numérotation, statuts personnalisés, tags, couleurs — sans identifiants ni clés API, qui restent propres à chaque poste et à chaque environnement.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Exporter la configuration") { exportConfiguration() }.buttonStyle(.bordered)
                    Button("Importer la configuration") { importConfiguration() }.buttonStyle(.bordered)
                    Spacer()
                }

                if let m = message {
                    Text(m).font(.caption).foregroundStyle(m.hasPrefix("Échec") ? .red : .green)
                }
            }
            .padding()
        }
    }

    private func moduleRow(title: String, count: Int, onExport: @escaping () -> Void, onImport: @escaping () -> Void) -> some View {
        HStack {
            Text(title).font(.body.weight(.semibold))
            Text("(\(count))").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Exporter") { onExport() }.buttonStyle(.bordered)
            Button("Importer") { onImport() }.buttonStyle(.bordered)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.3)))
    }

    private func exportJSON<T: Encodable>(_ items: [T], suggestedName: String) {
        do {
            let data = try DataPortability.exportJSON(items)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = suggestedName
            panel.allowedContentTypes = [.json]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url)
            message = "Export réussi : \(url.lastPathComponent)"
        } catch {
            message = "Échec de l'export : \(error.localizedDescription)"
        }
    }

    private func pickJSONFile() -> Data? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return try? Data(contentsOf: url)
    }

    private func importInvoices() {
        guard let data = pickJSONFile() else { return }
        do {
            let imported = try DataPortability.importJSON(Invoice.self, from: data)
            imported.forEach(store.upsert)
            message = "\(imported.count) facture(s) importée(s)."
        } catch {
            message = "Échec de l'import : \(error.localizedDescription)"
        }
    }

    private func importOrders() {
        guard let data = pickJSONFile() else { return }
        do {
            let imported = try DataPortability.importJSON(SalesOrder.self, from: data)
            imported.forEach(orderStore.upsert)
            message = "\(imported.count) commande(s) importée(s)."
        } catch {
            message = "Échec de l'import : \(error.localizedDescription)"
        }
    }

    private func importParties() {
        guard let data = pickJSONFile() else { return }
        do {
            let imported = try DataPortability.importJSON(DirectoryEntry.self, from: data)
            imported.forEach(directory.upsert)
            message = "\(imported.count) tiers importé(s)."
        } catch {
            message = "Échec de l'import : \(error.localizedDescription)"
        }
    }

    private func importQuotes() {
        guard let data = pickJSONFile() else { return }
        do {
            let imported = try DataPortability.importJSON(Quote.self, from: data)
            imported.forEach(quoteStore.upsert)
            message = "\(imported.count) devis importé(s)."
        } catch {
            message = "Échec de l'import : \(error.localizedDescription)"
        }
    }

    private func exportConfiguration() {
        let bundle = AppConfigurationBundle.capture(
            invoiceStore: store, orderStore: orderStore,
            invoiceStatusStore: invoiceStatusStore, orderStatusStore: orderStatusStore,
            tagStore: tagStore, kindColorStore: kindColorStore
        )
        do {
            let data = try DataPortability.exportJSON([bundle])
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "configuration.json"
            panel.allowedContentTypes = [.json]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url)
            message = "Configuration exportée : \(url.lastPathComponent)"
        } catch {
            message = "Échec de l'export : \(error.localizedDescription)"
        }
    }

    private func importConfiguration() {
        guard let data = pickJSONFile() else { return }
        do {
            guard let bundle = try DataPortability.importJSON(AppConfigurationBundle.self, from: data).first else {
                message = "Échec de l'import : fichier vide."
                return
            }
            bundle.apply(
                invoiceStore: store, orderStore: orderStore,
                invoiceStatusStore: invoiceStatusStore, orderStatusStore: orderStatusStore,
                tagStore: tagStore, kindColorStore: kindColorStore
            )
            message = "Configuration importée."
        } catch {
            message = "Échec de l'import : \(error.localizedDescription)"
        }
    }
}
