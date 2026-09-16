import Foundation
import CryptoKit

public enum UserRole: String, Codable, CaseIterable {
    case admin
    case comptable
    case acheteur

    public var label: String {
        switch self {
        case .admin: return "Administrateur"
        case .comptable: return "Comptable client"
        case .acheteur: return "Acheteur"
        }
    }

    public var systemImage: String {
        switch self {
        case .admin: return "person.badge.shield.checkmark"
        case .comptable: return "person.crop.rectangle.stack"
        case .acheteur: return "cart"
        }
    }
}

public struct User: Codable, Hashable, Identifiable {
    public var id: UUID
    public var username: String
    public var displayName: String
    public var roles: [UserRole]
    public var passwordHash: String
    public var salt: String
    public var societyIDs: [UUID]
    public var defaultSellerEntryID: UUID?
    public var isActive: Bool
    public var createdAt: Date
    public var mustChangePassword: Bool
    public var failedLoginAttempts: Int
    public var lockUntil: Date?
    public var lastActivityAt: Date?

    public init(
        id: UUID = UUID(),
        username: String,
        displayName: String = "",
        role: UserRole = .comptable,
        roles: [UserRole]? = nil,
        passwordHash: String = "",
        salt: String = "",
        societyIDs: [UUID] = [],
        defaultSellerEntryID: UUID? = nil,
        isActive: Bool = true,
        createdAt: Date = Date(),
        mustChangePassword: Bool = false,
        failedLoginAttempts: Int = 0,
        lockUntil: Date? = nil,
        lastActivityAt: Date? = nil
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.roles = roles ?? [role]
        if self.roles.isEmpty { self.roles = [.comptable] }
        self.passwordHash = passwordHash
        self.salt = salt
        self.societyIDs = societyIDs
        self.defaultSellerEntryID = defaultSellerEntryID
        self.isActive = isActive
        self.createdAt = createdAt
        self.mustChangePassword = mustChangePassword
        self.failedLoginAttempts = failedLoginAttempts
        self.lockUntil = lockUntil
        self.lastActivityAt = lastActivityAt
    }

    public var role: UserRole { roles.first ?? .comptable }
    public var isAdmin: Bool { roles.contains(.admin) }
    public func hasRole(_ r: UserRole) -> Bool { roles.contains(r) }
    public var rolesLabel: String { roles.map { $0.label }.joined(separator: ", ") }

    public var effectiveDisplayName: String {
        let n = displayName.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? username : n
    }

    private enum CodingKeys: String, CodingKey {
        case id, username, displayName, role, roles, passwordHash, salt, societyIDs, defaultSellerEntryID, isActive, createdAt
        case mustChangePassword, failedLoginAttempts, lockUntil, lastActivityAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        if let arr = try c.decodeIfPresent([UserRole].self, forKey: .roles), !arr.isEmpty {
            roles = arr
        } else if let single = try c.decodeIfPresent(UserRole.self, forKey: .role) {
            roles = [single]
        } else {
            roles = [.comptable]
        }
        passwordHash = try c.decodeIfPresent(String.self, forKey: .passwordHash) ?? ""
        salt = try c.decodeIfPresent(String.self, forKey: .salt) ?? ""
        societyIDs = try c.decodeIfPresent([UUID].self, forKey: .societyIDs) ?? []
        defaultSellerEntryID = try c.decodeIfPresent(UUID.self, forKey: .defaultSellerEntryID)
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        mustChangePassword = try c.decodeIfPresent(Bool.self, forKey: .mustChangePassword) ?? false
        failedLoginAttempts = try c.decodeIfPresent(Int.self, forKey: .failedLoginAttempts) ?? 0
        lockUntil = try c.decodeIfPresent(Date.self, forKey: .lockUntil)
        lastActivityAt = try c.decodeIfPresent(Date.self, forKey: .lastActivityAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(username, forKey: .username)
        try c.encode(displayName, forKey: .displayName)
        try c.encode(role, forKey: .role)
        try c.encode(roles, forKey: .roles)
        try c.encode(passwordHash, forKey: .passwordHash)
        try c.encode(salt, forKey: .salt)
        try c.encode(societyIDs, forKey: .societyIDs)
        try c.encodeIfPresent(defaultSellerEntryID, forKey: .defaultSellerEntryID)
        try c.encode(isActive, forKey: .isActive)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(mustChangePassword, forKey: .mustChangePassword)
        try c.encode(failedLoginAttempts, forKey: .failedLoginAttempts)
        try c.encodeIfPresent(lockUntil, forKey: .lockUntil)
        try c.encodeIfPresent(lastActivityAt, forKey: .lastActivityAt)
    }
}

public enum PasswordHasher {
    public static let iterations = 12_000

    public static func generateSalt() -> String {
        let key = SymmetricKey(size: .bits128)
        let bytes = key.withUnsafeBytes { Data($0) }
        return bytes.base64EncodedString()
    }

    public static func hash(password: String, salt: String) -> String {
        let saltData = Data(base64Encoded: salt) ?? Data(salt.utf8)
        var current = Data(password.utf8) + saltData
        for _ in 0..<iterations {
            let digest = SHA256.hash(data: current)
            current = Data(digest)
        }
        return current.base64EncodedString()
    }

    public static func verify(password: String, salt: String, expectedHash: String) -> Bool {
        let computed = hash(password: password, salt: salt)
        return constantTimeEquals(computed, expectedHash)
    }

    public static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)
        if aBytes.count != bBytes.count { return false }
        var result: UInt8 = 0
        for i in 0..<aBytes.count {
            result |= aBytes[i] ^ bBytes[i]
        }
        return result == 0
    }
}

// MARK: - Politique de mot de passe (A4)

public enum PasswordPolicy {
    public static let minLength = 10
    public static let maxFailedAttempts = 5
    public static let lockDurationSeconds: TimeInterval = 15 * 60
    public static let sessionMaxInactivitySeconds: TimeInterval = 8 * 3600

    private static let trivialPasswords: Set<String> = [
        "admin", "password", "motdepasse", "12345678", "123456789",
        "azertyuiop", "qwertyuiop", "abcd1234", "password1", "admin123"
    ]

    public enum Violation: Error, Equatable {
        case tooShort
        case tooWeak
        case trivial
        case reused

        public var message: String {
            switch self {
            case .tooShort: return "Le mot de passe doit faire au moins \(minLength) caractères."
            case .tooWeak: return "Le mot de passe doit contenir au moins 3 des 4 classes : minuscules, majuscules, chiffres, caractères spéciaux."
            case .trivial: return "Ce mot de passe est trop courant. Choisissez-en un plus original."
            case .reused: return "Le nouveau mot de passe doit être différent de l'ancien."
            }
        }
    }

    public static func validate(_ password: String, currentHash: String? = nil, salt: String? = nil) -> Violation? {
        guard password.count >= minLength else { return .tooShort }
        if trivialPasswords.contains(password.lowercased()) { return .trivial }
        var classes = 0
        if password.rangeOfCharacter(from: .lowercaseLetters) != nil { classes += 1 }
        if password.rangeOfCharacter(from: .uppercaseLetters) != nil { classes += 1 }
        if password.rangeOfCharacter(from: .decimalDigits) != nil { classes += 1 }
        if password.rangeOfCharacter(from: CharacterSet(charactersIn: "!@#$%^&*()_+-=[]{};':\"\\|,.<>/?`~ ")) != nil { classes += 1 }
        guard classes >= 3 else { return .tooWeak }
        if let currentHash = currentHash, let salt = salt {
            let newHash = PasswordHasher.hash(password: password, salt: salt)
            if PasswordHasher.constantTimeEquals(newHash, currentHash) { return .reused }
        }
        return nil
    }
}

public enum AuthError: Error, LocalizedError {
    case unknownUser
    case wrongPassword
    case inactiveUser
    case duplicateUsername
    case emptyPassword
    case missingSociety
    case invalidEmail
    case lockedOut(retryAt: Date)
    case passwordPolicy(PasswordPolicy.Violation)
    case mustChangePassword

    public var errorDescription: String? {
        switch self {
        case .unknownUser: return "Utilisateur introuvable."
        case .wrongPassword: return "Mot de passe incorrect."
        case .inactiveUser: return "Ce compte est désactivé."
        case .duplicateUsername: return "Cet identifiant existe déjà."
        case .emptyPassword: return "Le mot de passe ne peut pas être vide."
        case .missingSociety: return "Un utilisateur non-administrateur doit être associé à au moins une société (fiche société de l'annuaire)."
        case .invalidEmail: return "L'identifiant doit être une adresse e-mail valide."
        case .lockedOut(let retryAt):
            let f = DateFormatter()
            f.dateStyle = .none
            f.timeStyle = .short
            return "Compte temporairement verrouillé suite à des échecs. Réessayez après \(f.string(from: retryAt))."
        case .passwordPolicy(let v): return v.message
        case .mustChangePassword: return "Vous devez changer votre mot de passe à la première connexion."
        }
    }
}

public enum EmailValidator {
    public static func isValid(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.contains(" "), trimmed.contains("@") else { return false }
        let at = trimmed.firstIndex(of: "@") ?? trimmed.endIndex
        let local = trimmed[..<at]
        let domain = trimmed[trimmed.index(after: at)...]
        guard !local.isEmpty, domain.contains(".") else { return false }
        let domainParts = domain.split(separator: ".", omittingEmptySubsequences: true)
        guard domainParts.count >= 2 else { return false }
        guard domainParts.last?.count ?? 0 >= 2 else { return false }
        return true
    }
}

// MARK: - Journal d'audit (B1)

public enum AuditObjectType: String, Codable, CaseIterable {
    case invoice
    case order
    case party
    case user
    case other

    public var label: String {
        switch self {
        case .invoice: return "Facture"
        case .order: return "Commande"
        case .party: return "Tiers"
        case .user: return "Utilisateur"
        case .other: return "Autre"
        }
    }
}

public struct AuditLogEntry: Codable, Identifiable, Hashable {
    public var id: UUID
    public var timestamp: Date
    public var actor: String
    public var action: String
    public var target: String
    public var details: String
    public var objectType: AuditObjectType?
    public var objectCode: String?
    public var statusFrom: String?
    public var statusTo: String?

    public init(id: UUID = UUID(), timestamp: Date = Date(), actor: String, action: String, target: String, details: String = "", objectType: AuditObjectType? = nil, objectCode: String? = nil, statusFrom: String? = nil, statusTo: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.actor = actor
        self.action = action
        self.target = target
        self.details = details
        self.objectType = objectType
        self.objectCode = objectCode
        self.statusFrom = statusFrom
        self.statusTo = statusTo
    }

    private enum CodingKeys: String, CodingKey {
        case id, timestamp, actor, action, target, details, objectType, objectCode, statusFrom, statusTo
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        timestamp = try c.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        actor = try c.decodeIfPresent(String.self, forKey: .actor) ?? ""
        action = try c.decodeIfPresent(String.self, forKey: .action) ?? ""
        target = try c.decodeIfPresent(String.self, forKey: .target) ?? ""
        details = try c.decodeIfPresent(String.self, forKey: .details) ?? ""
        objectType = try c.decodeIfPresent(AuditObjectType.self, forKey: .objectType)
        objectCode = try c.decodeIfPresent(String.self, forKey: .objectCode)
        statusFrom = try c.decodeIfPresent(String.self, forKey: .statusFrom)
        statusTo = try c.decodeIfPresent(String.self, forKey: .statusTo)
    }
}

public final class AuditStore: ObservableObject {
    public static let shared = AuditStore()
    @Published public var entries: [AuditLogEntry] = []
    private let defaults = UserDefaults.standard
    private let env = AppEnvironment.shared
    private var key: String { env.key("facturx.audit.v1") }
    public var maxEntries = 500

    public init() { load() }

    public func load() {
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([AuditLogEntry].self, from: data) {
            entries = decoded
        }
    }

    public func save() {
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: key)
        }
    }

    public func record(actor: String, action: String, target: String, details: String = "", objectType: AuditObjectType? = nil, objectCode: String? = nil) {
        entries.insert(AuditLogEntry(actor: actor, action: action, target: target, details: details, objectType: objectType, objectCode: objectCode), at: 0)
        if entries.count > maxEntries { entries.removeLast(entries.count - maxEntries) }
        save()
    }

    public func recordStatusChange(actor: String, objectType: AuditObjectType, objectCode: String, statusFrom: String?, statusTo: String, details: String = "") {
        entries.insert(AuditLogEntry(
            actor: actor,
            action: "status_change",
            target: objectCode,
            details: details,
            objectType: objectType,
            objectCode: objectCode,
            statusFrom: statusFrom,
            statusTo: statusTo
        ), at: 0)
        if entries.count > maxEntries { entries.removeLast(entries.count - maxEntries) }
        save()
    }

    public func entries(forInvoice number: String) -> [AuditLogEntry] {
        entries.filter { ($0.objectType == .invoice && ($0.objectCode ?? $0.target) == number) || $0.target == number }
    }

    public func clear() {
        entries = []
        save()
    }
}

public final class AuthStore: ObservableObject {
    public static let shared = AuthStore()

    @Published public var users: [User]
    @Published public var currentUser: User?

    public var directory: PartyDirectory?

    /// By-pass de test : désactive la politique de mot de passe, le verrouillage de compte
    /// et l'expiration de session pour permettre une connexion directe en tests.
    /// À retirer avant la mise en production.
    public var testBypassSecurity = false

    public let audit = AuditStore.shared

    private let defaults = UserDefaults.standard
    private let env = AppEnvironment.shared
    private var usersKey: String { env.key("facturx.users.v1") }
    private var sessionKey: String { env.key("facturx.session.userid.v1") }
    private var seededKey: String { env.key("facturx.auth.seeded.v1") }
    private var sessionExpiresKey: String { env.key("facturx.session.expires.v1") }

    public init() {
        self.users = []
        self.currentUser = nil
        load()
        seedDefaultAdminIfEmpty()
        restoreSession()
    }

    public func attachDirectory(_ directory: PartyDirectory) {
        self.directory = directory
    }

    /// Recharge les utilisateurs/seeds/session après un changement d'environnement (test/prod).
    /// L'utilisateur courant est déconnecté puis la session du nouvel environnement est restaurée.
    public func reloadEnvironment() {
        currentUser = nil
        load()
        seedDefaultAdminIfEmpty()
        restoreSession()
    }

    public func load() {
        if let data = defaults.data(forKey: usersKey),
           let decoded = try? JSONDecoder().decode([User].self, from: data) {
            users = decoded
        }
    }

    public func save() {
        if let data = try? JSONEncoder().encode(users) {
            defaults.set(data, forKey: usersKey)
        }
        if let id = currentUser?.id {
            defaults.set(id.uuidString, forKey: sessionKey)
            defaults.set(Date().addingTimeInterval(PasswordPolicy.sessionMaxInactivitySeconds).timeIntervalSince1970, forKey: sessionExpiresKey)
        } else {
            defaults.removeObject(forKey: sessionKey)
            defaults.removeObject(forKey: sessionExpiresKey)
        }
    }

    private static let defaultAdminUsername = "admin@facturx.local"
    private static let defaultAdminPassword = "admin"

    /// A1 : ne crée l'admin par défaut qu'au tout premier seeding. Si l'admin existe déjà,
    /// son mot de passe n'est JAMAIS réinitialisé au lancement. L'admin créé est marqué
    /// mustChangePassword = true pour forcer le changement à la première connexion.
    public func seedDefaultAdminIfEmpty() {
        guard !defaults.bool(forKey: seededKey) else { return }
        if users.contains(where: { $0.username.lowercased() == Self.defaultAdminUsername.lowercased() }) {
            defaults.set(true, forKey: seededKey)
            return
        }
        let salt = PasswordHasher.generateSalt()
        let hash = PasswordHasher.hash(password: Self.defaultAdminPassword, salt: salt)
        let admin = User(
            username: Self.defaultAdminUsername,
            displayName: "Administrateur",
            role: .admin,
            passwordHash: hash,
            salt: salt,
            societyIDs: [],
            isActive: true,
            mustChangePassword: true
        )
        users.append(admin)
        save()
        defaults.set(true, forKey: seededKey)
        audit.record(actor: "system", action: "seed_admin", target: Self.defaultAdminUsername)
    }

    public func restoreSession() {
        guard let raw = defaults.string(forKey: sessionKey),
              let id = UUID(uuidString: raw),
              let user = users.first(where: { $0.id == id && $0.isActive }) else { return }
        // A6 : expiration de session par inactivité
        if !testBypassSecurity {
            let expiresAt = defaults.double(forKey: sessionExpiresKey)
            if expiresAt > 0, Date().timeIntervalSince1970 > expiresAt {
                defaults.removeObject(forKey: sessionKey)
                defaults.removeObject(forKey: sessionExpiresKey)
                audit.record(actor: user.username, action: "session_expired", target: "")
                return
            }
        }
        currentUser = user
        touchActivity()
    }

    /// A6 : rafraîchit l'horodatage de dernière activité (appelé sur interaction / login).
    public func touchActivity() {
        guard let idx = users.firstIndex(where: { $0.id == currentUser?.id }) else { return }
        users[idx].lastActivityAt = Date()
        currentUser = users[idx]
        save()
    }

    /// A6 : déconnecte si la session a expiré par inactivité. Retourne true si déconnecté.
    @discardableResult
    public func validateSession() -> Bool {
        guard let user = currentUser, !testBypassSecurity else { return false }
        if let last = user.lastActivityAt {
            if Date().timeIntervalSince(last) > PasswordPolicy.sessionMaxInactivitySeconds {
                audit.record(actor: user.username, action: "session_expired", target: "")
                logout()
                return true
            }
        }
        touchActivity()
        return false
    }

    @discardableResult
    public func login(username: String, password: String) throws -> User {
        guard let user = users.first(where: {
            $0.username.lowercased() == username.trimmingCharacters(in: .whitespaces).lowercased()
        }) else {
            audit.record(actor: username, action: "login_failed", target: "unknown", details: "utilisateur introuvable")
            throw AuthError.unknownUser
        }
        guard user.isActive else { throw AuthError.inactiveUser }

        // A5 : verrouillage de compte après échecs
        if !testBypassSecurity, let lockUntil = user.lockUntil, lockUntil > Date() {
            audit.record(actor: user.username, action: "login_blocked", target: "", details: "compte verrouillé")
            throw AuthError.lockedOut(retryAt: lockUntil)
        }
        guard PasswordHasher.verify(password: password, salt: user.salt, expectedHash: user.passwordHash) else {
            registerFailedAttempt(user)
            throw AuthError.wrongPassword
        }
        // Succès : raz des compteurs d'échec
        if let idx = users.firstIndex(where: { $0.id == user.id }) {
            users[idx].failedLoginAttempts = 0
            users[idx].lockUntil = nil
        }
        currentUser = user
        touchActivity()
        save()
        audit.record(actor: user.username, action: "login_success", target: "")
        return user
    }

    private func registerFailedAttempt(_ user: User) {
        guard let idx = users.firstIndex(where: { $0.id == user.id }) else { return }
        let attempts = user.failedLoginAttempts + 1
        users[idx].failedLoginAttempts = attempts
        if !testBypassSecurity && attempts >= PasswordPolicy.maxFailedAttempts {
            let until = Date().addingTimeInterval(PasswordPolicy.lockDurationSeconds)
            users[idx].lockUntil = until
            audit.record(actor: user.username, action: "account_locked", target: "", details: "après \(attempts) échecs")
        } else {
            audit.record(actor: user.username, action: "login_failed", target: "", details: "tentative \(attempts)")
        }
        save()
    }

    public func logout() {
        if let u = currentUser { audit.record(actor: u.username, action: "logout", target: "") }
        currentUser = nil
        save()
    }

    @discardableResult
    public func createUser(
        username: String,
        password: String,
        displayName: String = "",
        role: UserRole = .comptable,
        roles: [UserRole]? = nil,
        societyIDs: [UUID] = [],
        defaultSellerEntryID: UUID? = nil,
        mustChangePassword: Bool = false
    ) throws -> User {
        let trimmedName = username.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { throw AuthError.unknownUser }
        guard EmailValidator.isValid(trimmedName) else { throw AuthError.invalidEmail }
        guard !password.isEmpty else { throw AuthError.emptyPassword }
        // A4 : politique de mot de passe (sauf by-pass)
        if !testBypassSecurity, let v = PasswordPolicy.validate(password) {
            throw AuthError.passwordPolicy(v)
        }
        guard !users.contains(where: { $0.username.lowercased() == trimmedName.lowercased() }) else {
            throw AuthError.duplicateUsername
        }
        let effectiveRoles = (roles ?? [role]).filter { UserRole.allCases.contains($0) }
        let finalRoles = effectiveRoles.isEmpty ? [role] : effectiveRoles
        if finalRoles.contains(.comptable) || finalRoles.contains(.acheteur), societyIDs.isEmpty {
            throw AuthError.missingSociety
        }
        let salt = PasswordHasher.generateSalt()
        let hash = PasswordHasher.hash(password: password, salt: salt)
        let user = User(
            username: trimmedName,
            displayName: displayName,
            role: role,
            roles: finalRoles,
            passwordHash: hash,
            salt: salt,
            societyIDs: societyIDs,
            defaultSellerEntryID: defaultSellerEntryID,
            isActive: true,
            mustChangePassword: mustChangePassword
        )
        users.append(user)
        save()
        audit.record(actor: currentUser?.username ?? "system", action: "user_created", target: trimmedName, details: user.rolesLabel)
        return user
    }

    public func updatePassword(_ user: User, newPassword: String, forceChange: Bool = false) throws {
        guard !newPassword.isEmpty else { throw AuthError.emptyPassword }
        // A4 : politique de mot de passe (sauf by-pass ou changement forcé par admin reset)
        if !testBypassSecurity, !forceChange, let v = PasswordPolicy.validate(newPassword, currentHash: user.passwordHash, salt: user.salt) {
            throw AuthError.passwordPolicy(v)
        }
        guard let idx = users.firstIndex(where: { $0.id == user.id }) else { return }
        let salt = PasswordHasher.generateSalt()
        users[idx].salt = salt
        users[idx].passwordHash = PasswordHasher.hash(password: newPassword, salt: salt)
        users[idx].mustChangePassword = false
        // raz du verrouillage en cas de reset par admin
        if forceChange {
            users[idx].failedLoginAttempts = 0
            users[idx].lockUntil = nil
        }
        if currentUser?.id == user.id { currentUser = users[idx] }
        save()
        audit.record(actor: currentUser?.username ?? "system", action: "password_changed", target: user.username)
    }

    public func upsert(_ user: User) {
        let wasRoles = users.first(where: { $0.id == user.id })?.roles
        let wasScope = users.first(where: { $0.id == user.id })?.societyIDs
        if let idx = users.firstIndex(where: { $0.id == user.id }) {
            users[idx] = user
        } else {
            users.append(user)
        }
        if currentUser?.id == user.id { currentUser = user }
        save()
        // B1 : trace des modifications de rôle / périmètre
        if wasRoles != user.roles {
            audit.record(actor: currentUser?.username ?? "system", action: "role_changed",
                         target: user.username, details: "\(wasRoles?.map { $0.label }.joined(separator: ", ") ?? "—") → \(user.rolesLabel)")
        }
        if wasScope != nil, wasScope != user.societyIDs {
            audit.record(actor: currentUser?.username ?? "system", action: "scope_changed",
                         target: user.username, details: "\(user.societyIDs.count) société(s)")
        }
    }

    public func delete(_ user: User) {
        guard !user.isAdmin || users.filter({ $0.isAdmin }).count > 1 else { return }
        users.removeAll { $0.id == user.id }
        if currentUser?.id == user.id { currentUser = nil }
        save()
        audit.record(actor: currentUser?.username ?? "system", action: "user_deleted", target: user.username)
    }

    // MARK: - Périmètre basé sur l'annuaire (DirectoryEntry)

    private func allSocietyEntries(in directory: PartyDirectory) -> [DirectoryEntry] {
        directory.entries.filter { $0.kind == .societe }
    }

    public func availableSocieties() -> [DirectoryEntry] {
        let dir = directory ?? PartyDirectory.shared
        return allSocietyEntries(in: dir)
    }

    public func visibleSocieties(for user: User?) -> [DirectoryEntry] {
        guard let user = user else { return [] }
        let all = availableSocieties()
        if user.isAdmin { return all }
        let scope = Set(user.societyIDs)
        return all.filter { scope.contains($0.id) }
    }

    public func societyEntry(forID id: UUID?) -> DirectoryEntry? {
        guard let id = id else { return nil }
        return availableSocieties().first(where: { $0.id == id })
    }

    public func userCanAccessSociety(_ user: User?, societyID: UUID?) -> Bool {
        guard let user = user else { return false }
        if user.isAdmin { return true }
        guard let sid = societyID else { return false }
        return user.societyIDs.contains(sid)
    }

    public func visibleInvoiceCompanyIDs(for user: User?) -> Set<UUID>? {
        guard let user = user else { return nil }
        if user.isAdmin { return nil }
        return Set(user.societyIDs)
    }

    public func visibleOrderCompanyIDs(for user: User?) -> Set<UUID>? {
        guard let user = user else { return nil }
        if user.isAdmin { return nil }
        return Set(user.societyIDs)
    }

    public func visibleDirectoryEntryIDs(for user: User?) -> Set<UUID>? {
        guard let user = user else { return nil }
        if user.isAdmin { return nil }
        return Set(user.societyIDs)
    }
}
