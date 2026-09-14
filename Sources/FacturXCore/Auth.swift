import Foundation
import CryptoKit

public enum UserRole: String, Codable, CaseIterable {
    case admin
    case comptable

    public var label: String {
        switch self {
        case .admin: return "Administrateur"
        case .comptable: return "Comptable client"
        }
    }

    public var systemImage: String {
        switch self {
        case .admin: return "person.badge.shield.checkmark"
        case .comptable: return "person.crop.rectangle.stack"
        }
    }
}

public struct User: Codable, Hashable, Identifiable {
    public var id: UUID
    public var username: String
    public var displayName: String
    public var role: UserRole
    public var passwordHash: String
    public var salt: String
    public var societyIDs: [UUID]
    public var isActive: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        username: String,
        displayName: String = "",
        role: UserRole = .comptable,
        passwordHash: String = "",
        salt: String = "",
        societyIDs: [UUID] = [],
        isActive: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.role = role
        self.passwordHash = passwordHash
        self.salt = salt
        self.societyIDs = societyIDs
        self.isActive = isActive
        self.createdAt = createdAt
    }

    public var effectiveDisplayName: String {
        let n = displayName.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? username : n
    }

    private enum CodingKeys: String, CodingKey {
        case id, username, displayName, role, passwordHash, salt, societyIDs, isActive, createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        role = try c.decodeIfPresent(UserRole.self, forKey: .role) ?? .comptable
        passwordHash = try c.decodeIfPresent(String.self, forKey: .passwordHash) ?? ""
        salt = try c.decodeIfPresent(String.self, forKey: .salt) ?? ""
        societyIDs = try c.decodeIfPresent([UUID].self, forKey: .societyIDs) ?? []
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
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

public enum AuthError: Error, LocalizedError {
    case unknownUser
    case wrongPassword
    case inactiveUser
    case duplicateUsername
    case emptyPassword
    case missingSociety
    case invalidEmail

    public var errorDescription: String? {
        switch self {
        case .unknownUser: return "Utilisateur introuvable."
        case .wrongPassword: return "Mot de passe incorrect."
        case .inactiveUser: return "Ce compte est désactivé."
        case .duplicateUsername: return "Cet identifiant existe déjà."
        case .emptyPassword: return "Le mot de passe ne peut pas être vide."
        case .missingSociety: return "Un comptable doit être associé à au moins une société (fiche fournisseur de l'annuaire)."
        case .invalidEmail: return "L'identifiant doit être une adresse e-mail valide."
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

public final class AuthStore: ObservableObject {
    public static let shared = AuthStore()

    @Published public var users: [User]
    @Published public var currentUser: User?

    public weak var directory: PartyDirectory?

    private let defaults = UserDefaults.standard
    private let usersKey = "facturx.users.v1"
    private let sessionKey = "facturx.session.userid.v1"
    private let seededKey = "facturx.auth.seeded.v1"

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
        } else {
            defaults.removeObject(forKey: sessionKey)
        }
    }

    private static let defaultAdminUsername = "admin@facturx.local"
    private static let defaultAdminPassword = "admin"

    public func seedDefaultAdminIfEmpty() {
        if let idx = users.firstIndex(where: { $0.username.lowercased() == Self.defaultAdminUsername.lowercased() }) {
            // Réinitialise le mot de passe de l'admin par défaut à chaque lancement
            // pour garantir un accès de secours reproductible.
            let salt = PasswordHasher.generateSalt()
            users[idx].salt = salt
            users[idx].passwordHash = PasswordHasher.hash(password: Self.defaultAdminPassword, salt: salt)
            users[idx].isActive = true
            save()
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
            isActive: true
        )
        if let idx = users.firstIndex(where: { $0.id == admin.id }) {
            users[idx] = admin
        } else {
            users.append(admin)
        }
        save()
        defaults.set(true, forKey: seededKey)
    }

    private func restoreSession() {
        guard let raw = defaults.string(forKey: sessionKey),
              let id = UUID(uuidString: raw),
              let user = users.first(where: { $0.id == id && $0.isActive }) else { return }
        currentUser = user
    }

    @discardableResult
    public func login(username: String, password: String) throws -> User {
        guard let user = users.first(where: {
            $0.username.lowercased() == username.trimmingCharacters(in: .whitespaces).lowercased()
        }) else {
            throw AuthError.unknownUser
        }
        guard user.isActive else { throw AuthError.inactiveUser }
        guard PasswordHasher.verify(password: password, salt: user.salt, expectedHash: user.passwordHash) else {
            throw AuthError.wrongPassword
        }
        currentUser = user
        save()
        return user
    }

    public func logout() {
        currentUser = nil
        save()
    }

    @discardableResult
    public func createUser(
        username: String,
        password: String,
        displayName: String = "",
        role: UserRole = .comptable,
        societyIDs: [UUID] = []
    ) throws -> User {
        let trimmedName = username.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { throw AuthError.unknownUser }
        guard EmailValidator.isValid(trimmedName) else { throw AuthError.invalidEmail }
        guard !password.isEmpty else { throw AuthError.emptyPassword }
        guard !users.contains(where: { $0.username.lowercased() == trimmedName.lowercased() }) else {
            throw AuthError.duplicateUsername
        }
        if role == .comptable, societyIDs.isEmpty {
            throw AuthError.missingSociety
        }
        let salt = PasswordHasher.generateSalt()
        let hash = PasswordHasher.hash(password: password, salt: salt)
        let user = User(
            username: trimmedName,
            displayName: displayName,
            role: role,
            passwordHash: hash,
            salt: salt,
            societyIDs: societyIDs,
            isActive: true
        )
        users.append(user)
        save()
        return user
    }

    public func updatePassword(_ user: User, newPassword: String) throws {
        guard !newPassword.isEmpty else { throw AuthError.emptyPassword }
        guard let idx = users.firstIndex(where: { $0.id == user.id }) else { return }
        let salt = PasswordHasher.generateSalt()
        users[idx].salt = salt
        users[idx].passwordHash = PasswordHasher.hash(password: newPassword, salt: salt)
        if currentUser?.id == user.id { currentUser = users[idx] }
        save()
    }

    public func upsert(_ user: User) {
        if let idx = users.firstIndex(where: { $0.id == user.id }) {
            users[idx] = user
        } else {
            users.append(user)
        }
        if currentUser?.id == user.id { currentUser = user }
        save()
    }

    public func delete(_ user: User) {
        guard user.role != .admin || users.filter({ $0.role == .admin }).count > 1 else { return }
        users.removeAll { $0.id == user.id }
        if currentUser?.id == user.id { currentUser = nil }
        save()
    }

    // MARK: - Périmètre basé sur l'annuaire (DirectoryEntry)

    private func allSocietyEntries(in directory: PartyDirectory) -> [DirectoryEntry] {
        directory.entries.filter { $0.kind == .fournisseur || $0.kind == .both }
    }

    public func availableSocieties() -> [DirectoryEntry] {
        let dir = directory ?? PartyDirectory.shared
        return allSocietyEntries(in: dir)
    }

    public func visibleSocieties(for user: User?) -> [DirectoryEntry] {
        guard let user = user else { return [] }
        let all = availableSocieties()
        if user.role == .admin { return all }
        let scope = Set(user.societyIDs)
        return all.filter { scope.contains($0.id) }
    }

    public func societyEntry(forID id: UUID?) -> DirectoryEntry? {
        guard let id = id else { return nil }
        return availableSocieties().first(where: { $0.id == id })
    }

    public func userCanAccessSociety(_ user: User?, societyID: UUID?) -> Bool {
        guard let user = user else { return false }
        if user.role == .admin { return true }
        guard let sid = societyID else { return false }
        return user.societyIDs.contains(sid)
    }

    public func visibleInvoiceCompanyIDs(for user: User?) -> Set<UUID>? {
        guard let user = user else { return nil }
        if user.role == .admin { return nil }
        return Set(user.societyIDs)
    }

    public func visibleDirectoryEntryIDs(for user: User?) -> Set<UUID>? {
        guard let user = user else { return nil }
        if user.role == .admin { return nil }
        return Set(user.societyIDs)
    }
}
