import Foundation
import Network

// MARK: - Credentials

public struct SMTPCredentials: Codable, Equatable {
    public var host: String
    public var port: Int
    public var username: String
    public var password: String
    public var fromAddress: String
    public var fromName: String
    /// TLS implicite dès l'ouverture de la connexion (port 465 typiquement).
    /// STARTTLS (port 587, upgrade en cours de session) n'est pas supporté
    /// dans cette version — préférer un fournisseur SMTP acceptant le TLS
    /// implicite, ou une connexion non chiffrée sur un réseau de confiance.
    public var useTLS: Bool
    public var alertsEnabled: Bool
    public var alertOnNewUser: Bool
    public var alertOnInvoiceStatusChange: Bool

    public init(
        host: String = "",
        port: Int = 465,
        username: String = "",
        password: String = "",
        fromAddress: String = "",
        fromName: String = "Factur-X",
        useTLS: Bool = true,
        alertsEnabled: Bool = false,
        alertOnNewUser: Bool = true,
        alertOnInvoiceStatusChange: Bool = true
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.fromAddress = fromAddress
        self.fromName = fromName
        self.useTLS = useTLS
        self.alertsEnabled = alertsEnabled
        self.alertOnNewUser = alertOnNewUser
        self.alertOnInvoiceStatusChange = alertOnInvoiceStatusChange
    }

    private enum CodingKeys: String, CodingKey {
        case host, port, username, password, fromAddress, fromName, useTLS
        case alertsEnabled, alertOnNewUser, alertOnInvoiceStatusChange
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? ""
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? 465
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        password = try c.decodeIfPresent(String.self, forKey: .password) ?? ""
        fromAddress = try c.decodeIfPresent(String.self, forKey: .fromAddress) ?? ""
        fromName = try c.decodeIfPresent(String.self, forKey: .fromName) ?? "Factur-X"
        useTLS = try c.decodeIfPresent(Bool.self, forKey: .useTLS) ?? true
        alertsEnabled = try c.decodeIfPresent(Bool.self, forKey: .alertsEnabled) ?? false
        alertOnNewUser = try c.decodeIfPresent(Bool.self, forKey: .alertOnNewUser) ?? true
        alertOnInvoiceStatusChange = try c.decodeIfPresent(Bool.self, forKey: .alertOnInvoiceStatusChange) ?? true
    }

    public var isConfigured: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty
            && !fromAddress.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

// MARK: - Errors

public enum SMTPError: Error, LocalizedError {
    case notConfigured
    case connection(String)
    case server(code: Int, message: String)
    case authFailed
    case invalidRecipient
    case malformedResponse

    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "SMTP non configuré. Ouvrez Réglages > Alertes email."
        case .connection(let m): return "Connexion SMTP impossible : \(m)"
        case .server(let code, let message): return "Erreur serveur SMTP (\(code)) : \(message)"
        case .authFailed: return "Authentification SMTP refusée par le serveur."
        case .invalidRecipient: return "Adresse destinataire invalide."
        case .malformedResponse: return "Réponse SMTP illisible."
        }
    }
}

// MARK: - Connexion bas niveau (Network.framework)

/// Garantit qu'une continuation Swift n'est reprise (`resume`) qu'une seule fois,
/// même si `NWConnection.stateUpdateHandler` est invoqué plusieurs fois avant que
/// l'état ne se stabilise. Verrou explicite pour rester correct sous la
/// vérification stricte de concurrence de Swift 6.
private final class ContinuationGuard: @unchecked Sendable {
    private var settled = false
    private let lock = NSLock()

    func trySettle() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if settled { return false }
        settled = true
        return true
    }
}

private final class SMTPConnection {
    private let connection: NWConnection
    private var buffer = Data()

    init(host: String, port: Int, useTLS: Bool) {
        let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) ?? .https
        connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: useTLS ? .tls : .tcp)
    }

    func open() async throws {
        let guardBox = ContinuationGuard()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if guardBox.trySettle() { continuation.resume() }
                case .failed(let error):
                    if guardBox.trySettle() { continuation.resume(throwing: SMTPError.connection(error.localizedDescription)) }
                case .cancelled:
                    if guardBox.trySettle() { continuation.resume(throwing: SMTPError.connection("Connexion annulée")) }
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
    }

    func close() {
        connection.cancel()
    }

    func sendRaw(_ text: String) async throws {
        let data = Data(text.utf8)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: SMTPError.connection(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    func sendCommand(_ command: String) async throws {
        try await sendRaw(command + "\r\n")
    }

    struct Response {
        let code: Int
        let message: String
    }

    /// Lit une réponse SMTP, en gérant les réponses multi-lignes ("250-…" puis "250 …").
    func readResponse() async throws -> Response {
        var lines: [String] = []
        while true {
            let line = try await readLine()
            lines.append(line)
            guard line.count >= 4 else { break }
            let separator = line[line.index(line.startIndex, offsetBy: 3)]
            if separator == " " { break }
            if separator != "-" { break }
        }
        guard let first = lines.first, first.count >= 3, let code = Int(first.prefix(3)) else {
            throw SMTPError.malformedResponse
        }
        let message = lines.map { $0.count > 4 ? String($0.dropFirst(4)) : "" }.joined(separator: " ")
        return Response(code: code, message: message)
    }

    private func readLine() async throws -> String {
        let crlf = Data([0x0D, 0x0A])
        while true {
            if let range = buffer.firstRange(of: crlf) {
                let lineData = buffer[..<range.lowerBound]
                let line = String(data: lineData, encoding: .utf8) ?? ""
                buffer.removeSubrange(..<range.upperBound)
                return line
            }
            let chunk = try await receiveChunk()
            buffer.append(chunk)
        }
    }

    private func receiveChunk() async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
                if let error = error {
                    continuation.resume(throwing: SMTPError.connection(error.localizedDescription))
                } else if let data = data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(throwing: SMTPError.connection("Connexion fermée par le serveur"))
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }
}

// MARK: - Service

public final class SMTPService {
    public init() {}

    /// Envoie un email texte simple. Lève une erreur explicite à la première étape
    /// du dialogue SMTP qui échoue (connexion, auth, destinataire, envoi).
    public func send(to recipient: String, subject: String, body: String, credentials: SMTPCredentials) async throws {
        guard credentials.isConfigured else { throw SMTPError.notConfigured }
        let trimmedRecipient = recipient.trimmingCharacters(in: .whitespaces)
        guard trimmedRecipient.contains("@") else { throw SMTPError.invalidRecipient }

        let connection = SMTPConnection(host: credentials.host, port: credentials.port, useTLS: credentials.useTLS)
        try await connection.open()
        defer { connection.close() }

        _ = try await connection.readResponse() // bannière 220
        try await connection.sendCommand("EHLO facturx-mac-app")
        _ = try await connection.readResponse()

        if !credentials.username.trimmingCharacters(in: .whitespaces).isEmpty {
            try await connection.sendCommand("AUTH LOGIN")
            guard try await connection.readResponse().code == 334 else { throw SMTPError.authFailed }
            try await connection.sendCommand(Data(credentials.username.utf8).base64EncodedString())
            guard try await connection.readResponse().code == 334 else { throw SMTPError.authFailed }
            try await connection.sendCommand(Data(credentials.password.utf8).base64EncodedString())
            guard try await connection.readResponse().code == 235 else { throw SMTPError.authFailed }
        }

        try await connection.sendCommand("MAIL FROM:<\(credentials.fromAddress)>")
        let mailFromResp = try await connection.readResponse()
        guard mailFromResp.code == 250 else { throw SMTPError.server(code: mailFromResp.code, message: mailFromResp.message) }

        try await connection.sendCommand("RCPT TO:<\(trimmedRecipient)>")
        let rcptResp = try await connection.readResponse()
        guard rcptResp.code == 250 || rcptResp.code == 251 else { throw SMTPError.server(code: rcptResp.code, message: rcptResp.message) }

        try await connection.sendCommand("DATA")
        let dataResp = try await connection.readResponse()
        guard dataResp.code == 354 else { throw SMTPError.server(code: dataResp.code, message: dataResp.message) }

        let fromHeader = credentials.fromName.trimmingCharacters(in: .whitespaces).isEmpty
            ? credentials.fromAddress
            : "\(credentials.fromName) <\(credentials.fromAddress)>"
        let dateString = Self.rfc2822DateFormatter.string(from: Date())
        // Un point seul en début de ligne termine le message SMTP : on échappe les
        // lignes du corps qui commenceraient par un point (RFC 5321 §4.5.2).
        let escapedBody = body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.hasPrefix(".") ? "." + $0 : String($0) }
            .joined(separator: "\r\n")
        let message = "From: \(fromHeader)\r\n"
            + "To: \(trimmedRecipient)\r\n"
            + "Subject: \(subject)\r\n"
            + "Date: \(dateString)\r\n"
            + "Content-Type: text/plain; charset=utf-8\r\n"
            + "\r\n"
            + escapedBody
            + "\r\n.\r\n"
        try await connection.sendRaw(message)
        let sendResp = try await connection.readResponse()
        guard sendResp.code == 250 else { throw SMTPError.server(code: sendResp.code, message: sendResp.message) }

        try await connection.sendCommand("QUIT")
        _ = try? await connection.readResponse()
    }

    private static let rfc2822DateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f
    }()
}

// MARK: - Settings storage

public final class SMTPSettings: ObservableObject {
    public static let shared = SMTPSettings()

    @Published public var credentials: SMTPCredentials
    /// Surcharge éparse par société (Réglages > Connexions) — voir `SuperPDPSettings.
    /// credentialsBySociety`, même patron.
    @Published public var credentialsBySociety: [UUID: SMTPCredentials] = [:]

    private let defaults = UserDefaults.standard
    private let env = AppEnvironment.shared
    private var storageKey: String { env.key("facturx.smtp.credentials.v1") }
    private var credentialsBySocietyKey: String { env.key("facturx.smtp.credentials.bysociety.v1") }
    private var passwordKeychainKey: String { env.key("facturx.smtp.password.v1") }
    private var keychainCleanupDoneKey: String { env.key("facturx.smtp.keychainCleanupDone.v1") }

    /// Retour arrière volontaire (2026-09-18) : le mot de passe vivait dans le Keychain,
    /// mais l'app n'est signée qu'en "ad hoc" (pas de compte Apple Developer) — une
    /// signature ad hoc change à chaque reconstruction du binaire, et macOS refuse alors
    /// l'accès à l'entrée Keychain créée par la version précédente (ou redemande
    /// l'autorisation). Résultat : le mot de passe semblait "effacé", et l'app redemandait
    /// l'accès au Keychain à chaque lancement. Retour au stockage en clair dans
    /// UserDefaults ; à reconsidérer si l'app passe un jour en mode SaaS (signature stable
    /// / autre mécanisme de secret).
    public init() {
        var decoded: SMTPCredentials
        if let data = defaults.data(forKey: env.key("facturx.smtp.credentials.v1")),
           let fromDisk = try? JSONDecoder().decode(SMTPCredentials.self, from: data) {
            decoded = fromDisk
        } else {
            decoded = SMTPCredentials()
        }
        Self.migrateFromKeychainOnce(
            into: &decoded,
            passwordKeychainKey: env.key("facturx.smtp.password.v1"),
            keychainCleanupDoneKey: env.key("facturx.smtp.keychainCleanupDone.v1"),
            defaults: defaults
        )
        credentials = decoded
        if let data = defaults.data(forKey: env.key("facturx.smtp.credentials.bysociety.v1")),
           let decodedBySociety = try? JSONDecoder().decode([UUID: SMTPCredentials].self, from: data) {
            credentialsBySociety = decodedBySociety
        }
    }

    /// Ne touche au Keychain qu'une seule fois, jamais plus ensuite (drapeau posé qu'un
    /// mot de passe y ait été trouvé ou non) : c'est cet appel unique, et non plus un
    /// appel à chaque lancement/sauvegarde, qui pouvait redéclencher indéfiniment la
    /// demande d'autorisation d'accès au Keychain (signature ad hoc instable, voir
    /// commentaire de `init()`). `static` (plutôt qu'une méthode d'instance) car appelée
    /// depuis `init()` avant que tous les stockages propriétés ne soient initialisés.
    private static func migrateFromKeychainOnce(into credentials: inout SMTPCredentials, passwordKeychainKey: String, keychainCleanupDoneKey: String, defaults: UserDefaults) {
        guard !defaults.bool(forKey: keychainCleanupDoneKey) else { return }
        if credentials.password.isEmpty, let migrated = KeychainStore.get(forKey: passwordKeychainKey), !migrated.isEmpty {
            credentials.password = migrated
        }
        KeychainStore.delete(forKey: passwordKeychainKey)
        defaults.set(true, forKey: keychainCleanupDoneKey)
    }

    public func save() {
        if let data = try? JSONEncoder().encode(credentials) {
            defaults.set(data, forKey: storageKey)
        }
        if let data = try? JSONEncoder().encode(credentialsBySociety) {
            defaults.set(data, forKey: credentialsBySocietyKey)
        }
    }

    /// Identifiants effectifs pour une société — voir `SuperPDPSettings.credentials(for:)`,
    /// même patron.
    public func credentials(for companyID: UUID?) -> SMTPCredentials {
        let effectiveID = companyID ?? PartyDirectory.shared.principaleSocieteID
        if let effectiveID, let override = credentialsBySociety[effectiveID] { return override }
        return credentials
    }

    public func setOverride(_ creds: SMTPCredentials, companyID: UUID) {
        credentialsBySociety[companyID] = creds
        save()
    }

    public func removeOverride(companyID: UUID) {
        credentialsBySociety.removeValue(forKey: companyID)
        save()
    }
}
