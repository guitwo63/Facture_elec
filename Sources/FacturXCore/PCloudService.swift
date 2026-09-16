import Foundation

/// pCloud a deux centres de données distincts avec des hôtes d'API différents ;
/// utiliser le mauvais host pour la région d'inscription du compte échoue.
/// Vérifié sur la documentation officielle avant implémentation.
public enum PCloudRegion: String, Codable, CaseIterable {
    case us, eu

    public var apiHost: String {
        switch self {
        case .us: return "api.pcloud.com"
        case .eu: return "eapi.pcloud.com"
        }
    }

    public var label: String {
        switch self {
        case .us: return "États-Unis (api.pcloud.com)"
        case .eu: return "Europe (eapi.pcloud.com)"
        }
    }
}

public struct PCloudCredentials: Codable, Equatable {
    public var username: String
    public var password: String
    public var region: PCloudRegion
    public var backupFolderPath: String

    public init(
        username: String = "",
        password: String = "",
        region: PCloudRegion = .eu,
        backupFolderPath: String = "/Facture_elec Sauvegardes"
    ) {
        self.username = username
        self.password = password
        self.region = region
        self.backupFolderPath = backupFolderPath
    }

    public var isConfigured: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case username, password, region, backupFolderPath
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        password = try c.decodeIfPresent(String.self, forKey: .password) ?? ""
        region = try c.decodeIfPresent(PCloudRegion.self, forKey: .region) ?? .eu
        backupFolderPath = try c.decodeIfPresent(String.self, forKey: .backupFolderPath) ?? "/Facture_elec Sauvegardes"
    }
}

public struct PCloudBackupFile: Codable, Identifiable, Hashable {
    public var fileID: Int
    public var name: String
    public var size: Int
    public var modified: String

    public var id: Int { fileID }

    public init(fileID: Int, name: String, size: Int, modified: String) {
        self.fileID = fileID
        self.name = name
        self.size = size
        self.modified = modified
    }
}

public enum PCloudError: Error, LocalizedError {
    case notConfigured
    case invalidResponse
    case apiError(code: Int, message: String)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "Identifiants pCloud non configurés."
        case .invalidResponse: return "Réponse pCloud illisible."
        case .apiError(let code, let message): return "Erreur pCloud (\(code)) : \(message)"
        case .network(let m): return "Connexion pCloud impossible : \(m)"
        }
    }
}

/// Client pCloud minimal (authentification directe, upload, listage, téléchargement)
/// pour la sauvegarde/restauration. Authentification par identifiant/mot de passe
/// (pas OAuth) : plus adapté à une app desktop sans vue web de redirection.
public struct PCloudService {
    public init() {}

    private func baseURL(_ credentials: PCloudCredentials) -> String {
        "https://\(credentials.region.apiHost)"
    }

    public func login(credentials: PCloudCredentials) async throws -> String {
        guard credentials.isConfigured else { throw PCloudError.notConfigured }
        guard var comps = URLComponents(string: "\(baseURL(credentials))/userinfo") else {
            throw PCloudError.invalidResponse
        }
        comps.queryItems = [
            URLQueryItem(name: "username", value: credentials.username),
            URLQueryItem(name: "password", value: credentials.password),
            URLQueryItem(name: "getauth", value: "1"),
            URLQueryItem(name: "logout", value: "1")
        ]
        guard let url = comps.url else { throw PCloudError.invalidResponse }
        let (data, _) = try await perform(URLRequest(url: url))
        let json = try decodeJSON(data)
        try checkResult(json)
        guard let auth = json["auth"] as? String else { throw PCloudError.invalidResponse }
        return auth
    }

    public func ensureBackupFolder(credentials: PCloudCredentials, auth: String) async throws {
        guard var comps = URLComponents(string: "\(baseURL(credentials))/createfolderifnotexists") else {
            throw PCloudError.invalidResponse
        }
        comps.queryItems = [
            URLQueryItem(name: "auth", value: auth),
            URLQueryItem(name: "path", value: credentials.backupFolderPath)
        ]
        guard let url = comps.url else { throw PCloudError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let (data, _) = try await perform(request)
        try checkResult(try decodeJSON(data))
    }

    public func upload(data: Data, filename: String, credentials: PCloudCredentials, auth: String) async throws -> PCloudBackupFile {
        guard credentials.isConfigured else { throw PCloudError.notConfigured }
        try await ensureBackupFolder(credentials: credentials, auth: auth)

        guard var comps = URLComponents(string: "\(baseURL(credentials))/uploadfile") else {
            throw PCloudError.invalidResponse
        }
        comps.queryItems = [
            URLQueryItem(name: "auth", value: auth),
            URLQueryItem(name: "path", value: credentials.backupFolderPath),
            URLQueryItem(name: "filename", value: filename)
        ]
        guard let url = comps.url else { throw PCloudError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (respData, _) = try await perform(request)
        let json = try decodeJSON(respData)
        try checkResult(json)
        guard let metadataArray = json["metadata"] as? [[String: Any]], let first = metadataArray.first,
              let fileID = first["fileid"] as? Int, let name = first["name"] as? String else {
            throw PCloudError.invalidResponse
        }
        return PCloudBackupFile(fileID: fileID, name: name, size: first["size"] as? Int ?? 0, modified: first["modified"] as? String ?? "")
    }

    public func listBackups(credentials: PCloudCredentials, auth: String) async throws -> [PCloudBackupFile] {
        guard var comps = URLComponents(string: "\(baseURL(credentials))/listfolder") else {
            throw PCloudError.invalidResponse
        }
        comps.queryItems = [
            URLQueryItem(name: "auth", value: auth),
            URLQueryItem(name: "path", value: credentials.backupFolderPath)
        ]
        guard let url = comps.url else { throw PCloudError.invalidResponse }
        let (data, _) = try await perform(URLRequest(url: url))
        let json = try decodeJSON(data)
        try checkResult(json)
        guard let metadata = json["metadata"] as? [String: Any],
              let contents = metadata["contents"] as? [[String: Any]] else {
            return []
        }
        return contents.compactMap { item -> PCloudBackupFile? in
            guard (item["isfolder"] as? Bool) != true,
                  let fileID = item["fileid"] as? Int,
                  let name = item["name"] as? String else { return nil }
            return PCloudBackupFile(fileID: fileID, name: name, size: item["size"] as? Int ?? 0, modified: item["modified"] as? String ?? "")
        }.sorted { $0.name > $1.name }
    }

    public func download(fileID: Int, credentials: PCloudCredentials, auth: String) async throws -> Data {
        guard var comps = URLComponents(string: "\(baseURL(credentials))/getfilelink") else {
            throw PCloudError.invalidResponse
        }
        comps.queryItems = [
            URLQueryItem(name: "auth", value: auth),
            URLQueryItem(name: "fileid", value: String(fileID))
        ]
        guard let url = comps.url else { throw PCloudError.invalidResponse }
        let (data, _) = try await perform(URLRequest(url: url))
        let json = try decodeJSON(data)
        try checkResult(json)
        guard let path = json["path"] as? String,
              let hosts = json["hosts"] as? [String],
              let host = hosts.first,
              let downloadURL = URL(string: "https://\(host)\(path)") else {
            throw PCloudError.invalidResponse
        }
        let (fileData, _) = try await perform(URLRequest(url: downloadURL))
        return fileData
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            throw PCloudError.network(error.localizedDescription)
        }
    }

    private func decodeJSON(_ data: Data) throws -> [String: Any] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PCloudError.invalidResponse
        }
        return json
    }

    private func checkResult(_ json: [String: Any]) throws {
        let result = json["result"] as? Int ?? -1
        guard result == 0 else {
            throw PCloudError.apiError(code: result, message: json["error"] as? String ?? "erreur inconnue")
        }
    }
}

public final class PCloudSettings: ObservableObject {
    public static let shared = PCloudSettings()

    @Published public var credentials: PCloudCredentials

    private let defaults = UserDefaults.standard
    private let env = AppEnvironment.shared
    private var storageKey: String { env.key("facturx.pcloud.credentials.v1") }

    public init() {
        if let data = defaults.data(forKey: env.key("facturx.pcloud.credentials.v1")),
           let decoded = try? JSONDecoder().decode(PCloudCredentials.self, from: data) {
            credentials = decoded
        } else {
            credentials = PCloudCredentials()
        }
    }

    public func load() {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(PCloudCredentials.self, from: data) {
            credentials = decoded
        } else {
            credentials = PCloudCredentials()
        }
    }

    public func save() {
        if let data = try? JSONEncoder().encode(credentials) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
