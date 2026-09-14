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
                    .foregroundStyle(Color.accentColor)
                Text("Factur-X").font(.largeTitle.bold())
                Text("Connexion").font(.title3).foregroundStyle(.secondary)
            }
            VStack(spacing: 12) {
                TextField("Adresse e-mail", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
                    .disableAutocorrection(true)
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
                Text("Compte admin par défaut : admin@facturx.local / admin")
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

struct UserManagementView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var directory: PartyDirectory
    @State private var selectedUserID: UUID?
    @State private var selectedEntryID: UUID?
    @State private var editingUser: User?
    @State private var creatingUser = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    Text("Gestion utilisateurs").font(.headline)
                    Spacer()
                }
                HStack(alignment: .top, spacing: 16) {
                    usersSection
                        .frame(maxWidth: .infinity)
                    companiesSection
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(12)
            Divider()
            if let id = selectedUserID, let user = auth.users.first(where: { $0.id == id }) {
                UserDetailCard(user: user, onChange: { updated in auth.upsert(updated) },
                               onResetPassword: { pw in try? auth.updatePassword(user, newPassword: pw) })
                    .padding(12)
            } else if let id = selectedEntryID, let entry = directory.entries.first(where: { $0.id == id }) {
                CompanyDetailCard(entry: entry)
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
            UserEditorSheet { username, displayName, password, role, societyIDs, defaultSeller in
                do {
                    _ = try auth.createUser(username: username, password: password,
                                            displayName: displayName, role: role, societyIDs: societyIDs,
                                            defaultSellerEntryID: defaultSeller)
                } catch {
                    return
                }
                creatingUser = false
            }
        }
        .sheet(item: $editingUser) { user in
            UserEditorSheet(existing: user) { username, displayName, password, role, societyIDs, defaultSeller in
                var updated = user
                updated.username = username
                updated.displayName = displayName
                updated.role = role
                updated.societyIDs = societyIDs
                updated.defaultSellerEntryID = defaultSeller
                auth.upsert(updated)
                if !password.isEmpty {
                    try? auth.updatePassword(updated, newPassword: password)
                }
                editingUser = nil
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
                set: { selectedUserID = $0; selectedEntryID = nil }
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

    private var companiesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sociétés (annuaire)").font(.headline)
                Spacer()
                Text("Fournisseurs de l'annuaire").font(.caption2).foregroundStyle(.secondary)
            }
            List(availableSocieties, selection: Binding(
                get: { selectedEntryID },
                set: { selectedEntryID = $0; selectedUserID = nil }
            )) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayName).font(.body.weight(.medium))
                    if let s = entry.party.siren, !s.isEmpty {
                        Text("SIREN : \(s)").font(.caption2).foregroundStyle(.secondary)
                    }
                    Text("\(auth.users.filter { $0.societyIDs.contains(entry.id) }.count) utilisateur(s)")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .frame(minHeight: 240)
            if availableSocieties.isEmpty {
                Text("Aucune société. Créez une fiche fournisseur dans l'onglet Annuaire pour la proposer comme périmètre.")
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 4)
            }
        }
    }

    private var availableSocieties: [DirectoryEntry] {
        directory.entries.filter { !$0.isArchived && ($0.kind == .fournisseur || $0.kind == .both) }
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
                } else if auth.availableSocieties().isEmpty {
                    Text("Aucune société (fiche fournisseur) définie dans l'annuaire.").font(.caption).foregroundStyle(.secondary)
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
    let onSave: (String, String, String, UserRole, [UUID], UUID?) -> Void
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var directory: PartyDirectory
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var displayName = ""
    @State private var password = ""
    @State private var role: UserRole = .comptable
    @State private var societyIDs: Set<UUID> = []
    @State private var defaultSellerEntryID: UUID? = nil

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
                    Text("Rôle").frame(width: 140, alignment: .leading)
                    Picker("Rôle", selection: $role) {
                        ForEach(UserRole.allCases, id: \.self) { r in Text(r.label).tag(r) }
                    }.pickerStyle(.segmented).frame(width: 300)
                }
                if role == .comptable {
                    Divider()
                    Text("Sociétés du périmètre (fiches fournisseurs de l'annuaire)").font(.headline)
                    if availableSocieties.isEmpty {
                        Text("Aucune société disponible. Créez d'abord une fiche fournisseur dans l'onglet Annuaire.")
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
            if let err = validationError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Enregistrer") {
                    onSave(username.trimmingCharacters(in: .whitespaces), displayName, password, role, Array(societyIDs), defaultSellerEntryID)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .padding()
        .frame(width: 580, height: 480)
        .onAppear {
            if let u = existing {
                username = u.username
                displayName = u.displayName
                role = u.role
                societyIDs = Set(u.societyIDs)
                defaultSellerEntryID = u.defaultSellerEntryID
            }
        }
    }

    private var availableSocieties: [DirectoryEntry] {
        directory.entries.filter { !$0.isArchived && ($0.kind == .fournisseur || $0.kind == .both) }
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
        let scopeOK = role == .admin || !societyIDs.isEmpty
        let noDup = validationError == nil
        return nameOK && pwOK && scopeOK && noDup
    }
}

struct ProfileSettingsView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var store: InvoiceStore
    @EnvironmentObject var directory: PartyDirectory
    @State private var newPw = ""
    @State private var confirmPw = ""
    @State private var saved = false
    @State private var error: String?
    @State private var showSellerPicker = false

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
                            if user.role == .comptable, !user.societyIDs.isEmpty {
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
                            Text("L’émetteur par défaut est un lien vers une fiche fournisseur de l’annuaire. Les modifications de la fiche (IBAN, BIC, conditions de paiement…) sont reprises automatiquement à la création de chaque facture.")
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
                                } label: { Label("Choisir un fournisseur dans l’annuaire", systemImage: "person.crop.circle.badge.plus") }
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
