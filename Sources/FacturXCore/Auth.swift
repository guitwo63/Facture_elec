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

public struct Society: Codable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var siren: String?
    public var entryID: UUID?

    public init(
        id: UUID = UUID(),
        name: String,
        siren: String? = nil,
        entryID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.siren = siren
        self.entryID = entryID
    }

    public var displayName: String {
        name.trimmingCharacters(in: .whitespaces).isEmpty ? "(société sans nom)" : name
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, siren, entryID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        siren = try c.decodeIfPresent(String.self, forKey: .siren)
        entryID = try c.decodeIfPresent(UUID.self, forKey: .entryID)
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

    public var errorDescription: String? {
        switch self {
        case .unknownUser: return "Utilisateur introuvable."
        case .wrongPassword: return "Mot de passe incorrect."
        case .inactiveUser: return "Ce compte est désactivé."
        case .duplicateUsername: return "Cet identifiant existe déjà."
        case .emptyPassword: return "Le mot de passe ne peut pas être vide."
        }
    }
}

public final class AuthStore: ObservableObject {
    public static let shared = AuthStore()

    @Published public var users: [User]
    @Published public var societies: [Society]
    @Published public var currentUser: User?

    private let defaults = UserDefaults.standard
    private let usersKey = "facturx.users.v1"
    private let societiesKey = "facturx.societies.v1"
    private let sessionKey = "facturx.session.userid.v1"
    private let seededKey = "facturx.auth.seeded.v1"

    public init() {
        self.users = []
        self.societies = []
        self.currentUser = nil
        load()
        seedDefaultAdminIfEmpty()
        restoreSession()
    }

    public func load() {
        if let data = defaults.data(forKey: usersKey),
           let decoded = try? JSONDecoder().decode([User].self, from: data) {
            users = decoded
        }
        if let data = defaults.data(forKey: societiesKey),
           let decoded = try? JSONDecoder().decode([Society].self, from: data) {
            societies = decoded
        }
    }

    public func save() {
        if let data = try? JSONEncoder().encode(users) {
            defaults.set(data, forKey: usersKey)
        }
        if let data = try? JSONEncoder().encode(societies) {
            defaults.set(data, forKey: societiesKey)
        }
        if let id = currentUser?.id {
            defaults.set(id.uuidString, forKey: sessionKey)
        } else {
            defaults.removeObject(forKey: sessionKey)
        }
    }

    public func seedDefaultAdminIfEmpty() {
        if defaults.bool(forKey: seededKey) { return }
        if users.isEmpty {
            let salt = PasswordHasher.generateSalt()
            let hash = PasswordHasher.hash(password: "admin", salt: salt)
            let admin = User(
                username: "admin",
                displayName: "Administrateur",
                role: .admin,
                passwordHash: hash,
                salt: salt,
                societyIDs: [],
                isActive: true
            )
            users = [admin]
            save()
        }
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
        guard !password.isEmpty else { throw AuthError.emptyPassword }
        guard !users.contains(where: { $0.username.lowercased() == trimmedName.lowercased() }) else {
            throw AuthError.duplicateUsername
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

    public func upsert(_ society: Society) {
        if let idx = societies.firstIndex(where: { $0.id == society.id }) {
            societies[idx] = society
        } else {
            societies.append(society)
        }
        save()
    }

    public func delete(_ society: Society) {
        societies.removeAll { $0.id == society.id }
        for i in users.indices {
            users[i].societyIDs.removeAll { $0 == society.id }
        }
        if currentUser?.societyIDs.contains(society.id) == true, var cu = currentUser {
            cu.societyIDs.removeAll { $0 == society.id }
            currentUser = cu
        }
        save()
    }

    public func society(forID id: UUID?) -> Society? {
        guard let id = id else { return nil }
        return societies.first(where: { $0.id == id })
    }

    public func userCanAccessSociety(_ user: User?, societyID: UUID?) -> Bool {
        guard let user = user else { return false }
        if user.role == .admin { return true }
        guard let sid = societyID else { return false }
        return user.societyIDs.contains(sid)
    }

    public func visibleSocieties(for user: User?) -> [Society] {
        guard let user = user else { return [] }
        if user.role == .admin { return societies }
        return societies.filter { user.societyIDs.contains($0.id) }
    }

    public func visibleInvoiceCompanyIDs(for user: User?) -> Set<UUID>? {
        guard let user = user else { return nil }
        if user.role == .admin { return nil }
        return Set(user.societyIDs)
    }
}
