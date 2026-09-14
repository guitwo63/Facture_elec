import SwiftUI
import FacturXCore

struct LoginView: View {
    @EnvironmentObject var auth: AuthStore
    @State private var username = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var attempting = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.accentColor)
                Text("Factur-X").font(.largeTitle.bold())
                Text("Connexion").font(.title3).foregroundStyle(.secondary)
            }
            VStack(spacing: 12) {
                TextField("Identifiant", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
                SecureField("Mot de passe", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
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
                Text("Compte admin par défaut : admin / admin")
                    .font(.caption2).foregroundStyle(.tertiary)
                Text("Pensez à modifier le mot de passe après la première connexion.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func attemptLogin() {
        attempting = true
        errorMessage = nil
        do {
            _ = try auth.login(username: username, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
        attempting = false
    }
}

struct AdministrationView: View {
    @EnvironmentObject var auth: AuthStore
    @State private var selectedUserID: UUID?
    @State private var selectedSocietyID: UUID?
    @State private var editingUser: User?
    @State private var creatingUser = false
    @State private var editingSociety: Society?
    @State private var creatingSociety = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    Text("Administration").font(.title2.bold())
                    Spacer()
                }
                HStack(alignment: .top, spacing: 16) {
                    usersSection
                        .frame(maxWidth: .infinity)
                    societiesSection
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(12)
            Divider()
            if let id = selectedUserID, let user = auth.users.first(where: { $0.id == id }) {
                UserDetailCard(user: user, onChange: { updated in auth.upsert(updated) },
                               onResetPassword: { pw in try? auth.updatePassword(user, newPassword: pw) })
                    .padding(12)
            } else if let id = selectedSocietyID, let society = auth.societies.first(where: { $0.id == id }) {
                SocietyDetailCard(society: society)
                    .padding(12)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "person.badge.shield.checkmark").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Sélectionnez un utilisateur ou une société.").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Spacer()
        }
        .sheet(isPresented: $creatingUser) {
            UserEditorSheet { username, displayName, password, role, societyIDs in
                do {
                    _ = try auth.createUser(username: username, password: password,
                                            displayName: displayName, role: role, societyIDs: societyIDs)
                } catch {
                    return
                }
                creatingUser = false
            }
        }
        .sheet(item: $editingUser) { user in
            UserEditorSheet(existing: user) { username, displayName, password, role, societyIDs in
                var updated = user
                updated.username = username
                updated.displayName = displayName
                updated.role = role
                updated.societyIDs = societyIDs
                auth.upsert(updated)
                if !password.isEmpty {
                    try? auth.updatePassword(updated, newPassword: password)
                }
                editingUser = nil
            }
        }
        .sheet(isPresented: $creatingSociety) {
            SocietyEditorSheet { name, siren, entryID in
                auth.upsert(Society(name: name, siren: siren, entryID: entryID))
                creatingSociety = false
            }
        }
        .sheet(item: $editingSociety) { society in
            SocietyEditorSheet(existing: society) { name, siren, entryID in
                var s = society
                s.name = name
                s.siren = siren
                s.entryID = entryID
                auth.upsert(s)
                editingSociety = nil
            }
        }
    }

    private var usersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Utilisateurs").font(.headline)
                Spacer()
                Button { creatingUser = true } label: { Label("Nouveau", systemImage: "plus") }
                    .buttonStyle(.bordered)
            }
            List(auth.users, selection: Binding(
                get: { selectedUserID },
                set: { selectedUserID = $0; selectedSocietyID = nil }
            )) { user in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.effectiveDisplayName).font(.body.weight(.medium))
                        Text("@\(user.username)").font(.caption2).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Text(user.role.label).font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(.quaternary, in: Capsule())
                            Text("\(user.societyIDs.count) société(s)").font(.caption2).foregroundStyle(.secondary)
                            if !user.isActive {
                                Text("Désactivé").font(.caption2).foregroundStyle(.red)
                            }
                        }
                    }
                    Spacer()
                    Image(systemName: user.role.systemImage).foregroundStyle(.secondary)
                }
                .contextMenu {
                    Button { editingUser = user } label: { Label("Modifier", systemImage: "pencil") }
                    Divider()
                    Button {
                        var u = user; u.isActive.toggle(); auth.upsert(u)
                    } label: { Label(user.isActive ? "Désactiver" : "Activer",
                                    systemImage: user.isActive ? "minus.circle" : "checkmark.circle") }
                    if user.role != .admin || auth.users.filter({ $0.role == .admin }).count > 1 {
                        Divider()
                        Button(role: .destructive) {
                            auth.delete(user)
                            if selectedUserID == user.id { selectedUserID = nil }
                        } label: { Label("Supprimer", systemImage: "trash") }
                    }
                }
            }
            .frame(minHeight: 240)
        }
    }

    private var societiesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sociétés (périmètre)").font(.headline)
                Spacer()
                Button { creatingSociety = true } label: { Label("Nouveau", systemImage: "plus") }
                    .buttonStyle(.bordered)
            }
            List(auth.societies, selection: Binding(
                get: { selectedSocietyID },
                set: { selectedSocietyID = $0; selectedUserID = nil }
            )) { society in
                VStack(alignment: .leading, spacing: 2) {
                    Text(society.displayName).font(.body.weight(.medium))
                    if let s = society.siren, !s.isEmpty {
                        Text("SIREN : \(s)").font(.caption2).foregroundStyle(.secondary)
                    }
                    Text("\(auth.users.filter { $0.societyIDs.contains(society.id) }.count) utilisateur(s)")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .contextMenu {
                    Button { editingSociety = society } label: { Label("Modifier", systemImage: "pencil") }
                    Divider()
                    Button(role: .destructive) {
                        auth.delete(society)
                        if selectedSocietyID == society.id { selectedSocietyID = nil }
                    } label: { Label("Supprimer", systemImage: "trash") }
                }
            }
            .frame(minHeight: 240)
        }
    }
}

struct UserDetailCard: View {
    let user: User
    let onChange: (User) -> Void
    let onResetPassword: (String) -> Void
    @EnvironmentObject var auth: AuthStore
    @State private var newPw = ""

    var body: some View {
        GroupBox("Utilisateur : \(user.effectiveDisplayName)") {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Identifiant") { Text("@\(user.username)") }
                LabeledContent("Rôle") { Text(user.role.label) }
                LabeledContent("Statut") {
                    Text(user.isActive ? "Actif" : "Désactivé")
                        .foregroundStyle(user.isActive ? .green : .red)
                }
                Divider()
                Text("Sociétés du périmètre").font(.headline)
                if user.role == .admin {
                    Text("L'administrateur accède à toutes les sociétés.").font(.caption).foregroundStyle(.secondary)
                } else if auth.societies.isEmpty {
                    Text("Aucune société définie.").font(.caption).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(auth.societies) { s in
                            Toggle(isOn: Binding(
                                get: { user.societyIDs.contains(s.id) },
                                set: { checked in
                                    var u = user
                                    if checked { u.societyIDs.append(s.id) }
                                    else { u.societyIDs.removeAll { $0 == s.id } }
                                    onChange(u)
                                }
                            )) {
                                Text(s.displayName)
                            }
                        }
                    }
                }
                Divider()
                Text("Réinitialiser le mot de passe").font(.headline)
                HStack {
                    SecureField("Nouveau mot de passe", text: $newPw)
                        .textFieldStyle(.roundedBorder).frame(width: 240)
                    Button {
                        onResetPassword(newPw)
                        newPw = ""
                    } label: { Label("Appliquer", systemImage: "checkmark.circle") }
                        .buttonStyle(.borderedProminent)
                        .disabled(newPw.isEmpty)
                }
            }
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SocietyDetailCard: View {
    let society: Society

    var body: some View {
        GroupBox("Société : \(society.displayName)") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Nom") { Text(society.displayName) }
                if let s = society.siren, !s.isEmpty {
                    LabeledContent("SIREN") { Text(s) }
                } else {
                    LabeledContent("SIREN") { Text("—").foregroundStyle(.secondary) }
                }
                LabeledContent("Lien annuaire") {
                    Text(society.entryID.map { "Fiche \($0.uuidString.prefix(8))" } ?? "Aucun")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct UserEditorSheet: View {
    var existing: User?
    let onSave: (String, String, String, UserRole, [UUID]) -> Void
    @EnvironmentObject var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var displayName = ""
    @State private var password = ""
    @State private var role: UserRole = .comptable
    @State private var societyIDs: Set<UUID> = []
    @State private var error: String?

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(existing == nil ? "Nouvel utilisateur" : "Modifier l'utilisateur")
                    .font(.title3.bold())
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Identifiant").frame(width: 130, alignment: .leading)
                    TextField("identifiant", text: $username).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Nom affiché").frame(width: 130, alignment: .leading)
                    TextField("Nom affiché", text: $displayName).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text(existing == nil ? "Mot de passe" : "Nouveau mot de passe (optionnel)")
                        .frame(width: 130, alignment: .leading)
                    SecureField("mot de passe", text: $password).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Rôle").frame(width: 130, alignment: .leading)
                    Picker("Rôle", selection: $role) {
                        ForEach(UserRole.allCases, id: \.self) { r in Text(r.label).tag(r) }
                    }.pickerStyle(.segmented).frame(width: 280)
                }
                if role == .comptable {
                    Divider()
                    Text("Sociétés du périmètre").font(.headline)
                    if auth.societies.isEmpty {
                        Text("Aucune société définie. Créez-en d'abord dans la section Sociétés.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(auth.societies) { s in
                                Toggle(isOn: Binding(
                                    get: { societyIDs.contains(s.id) },
                                    set: { checked in
                                        if checked { societyIDs.insert(s.id) }
                                        else { societyIDs.remove(s.id) }
                                    }
                                )) {
                                    Text(s.displayName)
                                }
                            }
                        }
                    }
                }
                if let error = error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            HStack {
                Spacer()
                Button("Enregistrer") {
                    let pw = existing == nil ? password : password
                    onSave(username, displayName, pw, role, Array(societyIDs))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty || (existing == nil && password.isEmpty))
            }
        }
        .padding()
        .frame(width: 560, height: 460)
        .onAppear {
            if let u = existing {
                username = u.username
                displayName = u.displayName
                role = u.role
                societyIDs = Set(u.societyIDs)
            }
        }
    }
}

struct SocietyEditorSheet: View {
    var existing: Society?
    let onSave: (String, String?, UUID?) -> Void
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var directory: PartyDirectory
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var siren = ""
    @State private var entryID: UUID?

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(existing == nil ? "Nouvelle société" : "Modifier la société")
                    .font(.title3.bold())
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Nom").frame(width: 130, alignment: .leading)
                    TextField("Nom de la société", text: $name).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("SIREN").frame(width: 130, alignment: .leading)
                    TextField("SIREN", text: $siren).textFieldStyle(.roundedBorder).frame(width: 200)
                }
                Divider()
                Text("Fiche fournisseur de l'annuaire (émetteur)").font(.headline)
                Text("Liez cette société à une fiche fournisseur de l'annuaire pour réutiliser ses coordonnées comme émetteur par défaut.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Fiche annuaire", selection: Binding(
                    get: { entryID ?? Self.noneSentinel },
                    set: { entryID = $0 }
                )) {
                    Text("Aucune").tag(Self.noneSentinel)
                    ForEach(directory.entries.filter { $0.kind == .fournisseur || $0.kind == .both }) { e in
                        Text(e.displayName).tag(e.id)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Enregistrer") {
                    let trimmedSiren = siren.trimmingCharacters(in: .whitespaces)
                    let linked = entryID == nil || entryID == Self.noneSentinel ? nil : entryID
                    onSave(name, trimmedSiren.isEmpty ? nil : trimmedSiren, linked)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 520, height: 380)
        .onAppear {
            if let s = existing {
                name = s.name
                siren = s.siren ?? ""
                entryID = s.entryID ?? Self.noneSentinel
            } else {
                entryID = Self.noneSentinel
            }
        }
    }

    static let noneSentinel = UUID()
}
