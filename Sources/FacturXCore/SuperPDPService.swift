import Foundation

// MARK: - Credentials

public struct SuperPDPCredentials: Codable, Equatable {
    public var clientID: String
    public var clientSecret: String
    public var apiBaseURL: String
    public var useSandbox: Bool

    public init(
        clientID: String,
        clientSecret: String,
        apiBaseURL: String = SuperPDPCredentials.defaultProductionBase,
        useSandbox: Bool = true
    ) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.apiBaseURL = apiBaseURL.isEmpty ? SuperPDPCredentials.defaultProductionBase : apiBaseURL
        self.useSandbox = useSandbox
    }

    public static let defaultProductionBase = "https://api.superpdp.tech"
    public static let defaultSandboxBase = "https://api.superpdp.tech"

    public var resolvedBaseURL: String {
        let trimmed = apiBaseURL.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? SuperPDPCredentials.defaultProductionBase : trimmed
    }

    public var isConfigured: Bool {
        !clientID.trimmingCharacters(in: .whitespaces).isEmpty
            && !clientSecret.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case clientID, clientSecret, apiBaseURL, useSandbox
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clientID = try c.decodeIfPresent(String.self, forKey: .clientID) ?? ""
        clientSecret = try c.decodeIfPresent(String.self, forKey: .clientSecret) ?? ""
        apiBaseURL = try c.decodeIfPresent(String.self, forKey: .apiBaseURL) ?? SuperPDPCredentials.defaultProductionBase
        useSandbox = try c.decodeIfPresent(Bool.self, forKey: .useSandbox) ?? true
    }
}

// MARK: - Errors

public enum SuperPDPError: Error, LocalizedError {
    case notConfigured
    case http(status: Int, body: String)
    case decoding(String)
    case noToken
    case emptyQuery
    case missingFile
    case missingInvoiceID

    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "Identifiants SUPER PDP non configurés. Ouvrez les Réglages."
        case .http(let status, let body): return "Erreur HTTP \(status) : \(body)"
        case .decoding(let m): return "Décodage impossible : \(m)"
        case .noToken: return "Aucun jeton d'accès renvoyé par SUPER PDP."
        case .emptyQuery: return "Saisissez un SIREN/SIRET (au moins 9 chiffres) à rechercher."
        case .missingFile: return "Aucune facture à déposer (générez d'abord le Factur-X)."
        case .missingInvoiceID: return "SUPER PDP n'a pas renvoyé d'identifiant de facture."
        }
    }
}

// MARK: - Models

public struct SuperPDPCompany: Identifiable, Hashable {
    public var id: String { number ?? formalName ?? UUID().uuidString }
    public var formalName: String?
    public var number: String?
    public var numberScheme: String?
    public var env: String?
    public var raw: [String: String]

    public init(formalName: String? = nil, number: String? = nil, numberScheme: String? = nil, env: String? = nil, raw: [String: String] = [:]) {
        self.formalName = formalName
        self.number = number
        self.numberScheme = numberScheme
        self.env = env
        self.raw = raw
    }

    public var siren: String? {
        guard numberScheme == "fr_siren", let n = number else { return nil }
        return n
    }
}

public struct SuperPDPDirectoryEntry: Identifiable, Hashable {
    public var id: String { siret ?? siren ?? name ?? UUID().uuidString }
    public var name: String?
    public var siren: String?
    public var siret: String?
    public var addressLine: String?
    public var postcode: String?
    public var city: String?
    public var country: String?
    public var routingAddress: String?
    public var routingScheme: String?
    public var isReady: Bool?
    public var raw: [String: String]

    public init(
        name: String? = nil,
        siren: String? = nil,
        siret: String? = nil,
        addressLine: String? = nil,
        postcode: String? = nil,
        city: String? = nil,
        country: String? = nil,
        routingAddress: String? = nil,
        routingScheme: String? = nil,
        isReady: Bool? = nil,
        raw: [String: String] = [:]
    ) {
        self.name = name
        self.siren = siren
        self.siret = siret
        self.addressLine = addressLine
        self.postcode = postcode
        self.city = city
        self.country = country
        self.routingAddress = routingAddress
        self.routingScheme = routingScheme
        self.isReady = isReady
        self.raw = raw
    }

    public var displaySubtitle: String {
        var parts: [String] = []
        if let siret = siret, !siret.isEmpty { parts.append("SIRET \(siret)") }
        if let siren = siren, !siren.isEmpty { parts.append("SIREN \(siren)") }
        if let city = city, !city.isEmpty { parts.append(city) }
        if isReady == true { parts.append("prêt à recevoir") } else if isReady == false { parts.append("non configuré") }
        return parts.joined(separator: " · ")
    }
}

public enum SuperPDPDirection: String, Codable {
    case received
    case sent
}

public struct SuperPDPInvoiceSubmission: Identifiable, Codable, Hashable {
    public var id: String
    public var remoteID: String?
    public var status: String
    public var enInvoiceRef: String?
    public var submittedAt: Date
    public var lastCheckedAt: Date
    public var message: String?
    public var direction: SuperPDPDirection

    public init(id: String = UUID().uuidString, remoteID: String?, status: String, enInvoiceRef: String? = nil, submittedAt: Date = Date(), lastCheckedAt: Date = Date(), message: String? = nil, direction: SuperPDPDirection = .received) {
        self.id = id
        self.remoteID = remoteID
        self.status = status
        self.enInvoiceRef = enInvoiceRef
        self.submittedAt = submittedAt
        self.lastCheckedAt = lastCheckedAt
        self.message = message
        self.direction = direction
    }

    public var isProcessed: Bool {
        let s = status.lowercased()
        return s == "processed" || s == "accepted" || s == "received" || !(enInvoiceRef?.isEmpty ?? true)
    }
}

public struct SuperPDPValidationReport: Hashable {
    public var isValid: Bool
    public var errors: [String]
    public var warnings: [String]
    public var raw: [String: String]

    public init(isValid: Bool, errors: [String] = [], warnings: [String] = [], raw: [String: String] = [:]) {
        self.isValid = isValid
        self.errors = errors
        self.warnings = warnings
        self.raw = raw
    }
}

// MARK: - Service

public final class SuperPDPService {
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
    }

    public static func extractSiren(from siret: String) -> String? {
        let digits = siret.filter { $0.isNumber }
        guard digits.count >= 9 else { return nil }
        return String(digits.prefix(9))
    }

    private func urlEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }

    private func trimmedBase(_ credentials: SuperPDPCredentials) -> String {
        credentials.resolvedBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private struct TokenResponse: Decodable {
        let access_token: String?
        let token_type: String?
        let expires_in: Int?
    }

    public func tokenEndpoint(credentials: SuperPDPCredentials) -> String {
        trimmedBase(credentials) + "/oauth2/token"
    }

    public func fetchToken(credentials: SuperPDPCredentials) async throws -> String {
        guard credentials.isConfigured else { throw SuperPDPError.notConfigured }
        guard let url = URL(string: tokenEndpoint(credentials: credentials)) else {
            throw SuperPDPError.decoding("URL de token invalide")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "grant_type=client_credentials"
            + "&client_id=\(urlEncode(credentials.clientID))"
            + "&client_secret=\(urlEncode(credentials.clientSecret))"
        req.httpBody = body.data(using: .utf8)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw SuperPDPError.decoding("Réponse non HTTP")
        }
        guard (200...299).contains(http.statusCode) else {
            throw SuperPDPError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        let token = try decoder.decode(TokenResponse.self, from: data)
        guard let access = token.access_token, !access.isEmpty else {
            throw SuperPDPError.noToken
        }
        return access
    }

    public func getCompany(credentials: SuperPDPCredentials) async throws -> SuperPDPCompany {
        let token = try await fetchToken(credentials: credentials)
        let endpoint = trimmedBase(credentials) + "/v1.beta/companies/me"
        guard let url = URL(string: endpoint) else {
            throw SuperPDPError.decoding("URL d'API invalide : \(endpoint)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw SuperPDPError.decoding("Réponse non HTTP")
        }
        guard (200...299).contains(http.statusCode) else {
            throw SuperPDPError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return try parseCompany(data: data)
    }

    private func parseCompany(data: Data) throws -> SuperPDPCompany {
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw SuperPDPError.decoding("JSON société illisible")
        }
        return mapCompany(obj)
    }

    private func mapCompany(_ dict: [String: Any]) -> SuperPDPCompany {
        func s(_ key: String) -> String? {
            if let v = dict[key] as? String { return v.isEmpty ? nil : v }
            if let n = dict[key] as? NSNumber { return n.stringValue }
            return nil
        }
        var raw: [String: String] = [:]
        for (k, v) in dict {
            if let sv = v as? String { raw[k] = sv }
            else if let nv = v as? NSNumber { raw[k] = nv.stringValue }
            else if let bv = v as? Bool { raw[k] = bv ? "Oui" : "Non" }
        }
        return SuperPDPCompany(
            formalName: s("formal_name") ?? s("name"),
            number: s("number"),
            numberScheme: s("number_scheme"),
            env: s("env"),
            raw: raw
        )
    }

    public func searchRecipient(siretOrSiren: String, credentials: SuperPDPCredentials) async throws -> [SuperPDPDirectoryEntry] {
        let query = siretOrSiren.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { throw SuperPDPError.emptyQuery }
        let token = try await fetchToken(credentials: credentials)
        let base = trimmedBase(credentials)
        let endpoint = base + "/v1.beta/directory_entries?query=" + urlEncode(query)
        guard let url = URL(string: endpoint) else {
            throw SuperPDPError.decoding("URL d'annuaire invalide : \(endpoint)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw SuperPDPError.decoding("Réponse non HTTP")
        }
        guard (200...299).contains(http.statusCode) else {
            throw SuperPDPError.http(status: http.statusCode, body: "URL: \(endpoint)\nBody: \(String(data: data, encoding: .utf8) ?? "")")
        }
        return try parseDirectory(data: data)
    }

    private func parseDirectory(data: Data) throws -> [SuperPDPDirectoryEntry] {
        let obj: Any
        do {
            obj = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw SuperPDPError.decoding("\(error)")
        }
        if let dict = obj as? [String: Any] {
            if let arr = dict["data"] as? [[String: Any]] { return arr.map { mapDirectoryEntry($0) } }
            if let arr = dict["directory_entries"] as? [[String: Any]] { return arr.map { mapDirectoryEntry($0) } }
            if let arr = dict["entries"] as? [[String: Any]] { return arr.map { mapDirectoryEntry($0) } }
            if let arr = dict["results"] as? [[String: Any]] { return arr.map { mapDirectoryEntry($0) } }
            return [mapDirectoryEntry(dict)]
        }
        if let arr = obj as? [[String: Any]] {
            return arr.map { mapDirectoryEntry($0) }
        }
        return []
    }

    private func mapDirectoryEntry(_ dict: [String: Any]) -> SuperPDPDirectoryEntry {
        func s(_ key: String) -> String? {
            if let v = dict[key] as? String { return v.isEmpty ? nil : v }
            if let n = dict[key] as? NSNumber { return n.stringValue }
            return nil
        }
        func b(_ key: String) -> Bool? {
            if let v = dict[key] as? Bool { return v }
            if let v = dict[key] as? String { return v.lowercased() == "oui" || v.lowercased() == "true" || v == "1" }
            return nil
        }
        let nestedParty = dict["party"] as? [String: Any] ?? dict["company"] as? [String: Any]
        let nameVal = s("name") ?? s("formal_name") ?? s("denomination") ?? s("raison_sociale")
        let siret = s("siret")
        let siren = s("siren") ?? (siret.flatMap { SuperPDPService.extractSiren(from: $0) })
        let address = s("address") ?? s("address_line") ?? s("adresse")
        let postcode = s("postcode") ?? s("code_postal") ?? s("zip")
        let city = s("city") ?? s("ville") ?? s("commune")
        let country = s("country") ?? s("pays") ?? s("country_code")
        let routing = s("routing_address") ?? s("endpoint_id") ?? s("electronic_address")
        let routingScheme = s("routing_scheme") ?? s("endpoint_scheme")
        let ready = b("is_ready") ?? b("ready") ?? b("active")
        var raw: [String: String] = [:]
        for (k, v) in dict {
            if let sv = v as? String { raw[k] = sv }
            else if let nv = v as? NSNumber { raw[k] = nv.stringValue }
            else if let bv = v as? Bool { raw[k] = bv ? "Oui" : "Non" }
        }
        _ = nestedParty
        return SuperPDPDirectoryEntry(
            name: nameVal,
            siren: siren,
            siret: siret,
            addressLine: address,
            postcode: postcode,
            city: city,
            country: country,
            routingAddress: routing,
            routingScheme: routingScheme,
            isReady: ready,
            raw: raw
        )
    }

    public func validateInvoice(fileData: Data, credentials: SuperPDPCredentials) async throws -> SuperPDPValidationReport {
        guard !fileData.isEmpty else { throw SuperPDPError.missingFile }
        let token = try await fetchToken(credentials: credentials)
        let endpoint = trimmedBase(credentials) + "/v1.beta/validation_reports"
        guard let url = URL(string: endpoint) else {
            throw SuperPDPError.decoding("URL de validation invalide : \(endpoint)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let boundary = "----FacturXBoundary\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let body = buildMultipartBody(boundary: boundary, fieldName: "file", fileName: "invoice.xml", content: fileData)
        req.httpBody = body
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw SuperPDPError.decoding("Réponse non HTTP")
        }
        guard (200...299).contains(http.statusCode) else {
            throw SuperPDPError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return try parseValidationReport(data: data)
    }

    private func parseValidationReport(data: Data) throws -> SuperPDPValidationReport {
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw SuperPDPError.decoding("JSON rapport de validation illisible")
        }
        let dataArr = obj["data"] as? [Any]
        let first = (dataArr?.first as? [String: Any]) ?? obj
        func s(_ key: String) -> String? {
            if let v = first[key] as? String { return v.isEmpty ? nil : v }
            if let n = first[key] as? NSNumber { return n.stringValue }
            return nil
        }
        let isValid = (first["is_valid"] as? Bool) ?? (s("is_valid")?.lowercased() == "true")
        let errors = (first["errors"] as? [Any])?.compactMap { entry -> String? in
            if let e = entry as? String { return e }
            if let d = entry as? [String: Any] { return (d["message"] as? String) ?? (d["error"] as? String) }
            return nil
        } ?? []
        let warnings = (first["warnings"] as? [Any])?.compactMap { entry -> String? in
            if let e = entry as? String { return e }
            if let d = entry as? [String: Any] { return (d["message"] as? String) ?? (d["warning"] as? String) }
            return nil
        } ?? []
        var raw: [String: String] = [:]
        for (k, v) in first {
            if let sv = v as? String { raw[k] = sv }
            else if let nv = v as? NSNumber { raw[k] = nv.stringValue }
            else if let bv = v as? Bool { raw[k] = bv ? "Oui" : "Non" }
        }
        return SuperPDPValidationReport(isValid: isValid, errors: errors, warnings: warnings, raw: raw)
    }

    public func submitInvoice(fileData: Data, credentials: SuperPDPCredentials) async throws -> SuperPDPInvoiceSubmission {
        guard !fileData.isEmpty else { throw SuperPDPError.missingFile }
        let token = try await fetchToken(credentials: credentials)
        let endpoint = trimmedBase(credentials) + "/v1.beta/invoices"
        guard let url = URL(string: endpoint) else {
            throw SuperPDPError.decoding("URL de dépôt invalide : \(endpoint)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let isPDF = fileData.count > 4 && fileData[0] == 0x25 && fileData[1] == 0x50 && fileData[2] == 0x44 && fileData[3] == 0x46
        if isPDF {
            req.setValue("application/pdf", forHTTPHeaderField: "Content-Type")
        }
        req.httpBody = fileData
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw SuperPDPError.decoding("Réponse non HTTP")
        }
        guard (200...299).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            let hint = AppEnvironment.shared.isTest
                ? " (bac à sable : le SIREN émetteur de la facture doit correspondre à celui de l'application OAuth — Tricatel 000000001 ou Burger Queen 000000002 — et le destinataire doit être joignable sur le réseau Peppol test)"
                : ""
            throw SuperPDPError.http(status: http.statusCode, body: (bodyText.isEmpty ? "(corps vide)" : bodyText) + hint)
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw SuperPDPError.decoding("JSON dépôt illisible : \(String(data: data, encoding: .utf8) ?? "")")
        }
        let remoteID = (obj["id"] as? NSNumber)?.stringValue ?? obj["id"] as? String
        guard let rid = remoteID, !rid.isEmpty else { throw SuperPDPError.missingInvoiceID }
        let enInvoice = obj["en_invoice"] as? String
        let status = (obj["status"] as? String) ?? (enInvoice == nil ? "submitted" : "processed")
        return SuperPDPInvoiceSubmission(
            remoteID: rid,
            status: status,
            enInvoiceRef: enInvoice,
            submittedAt: Date(),
            lastCheckedAt: Date(),
            message: obj["message"] as? String
        )
    }

    public func getInvoiceStatus(remoteID: String, credentials: SuperPDPCredentials) async throws -> SuperPDPInvoiceSubmission {
        let token = try await fetchToken(credentials: credentials)
        let endpoint = trimmedBase(credentials) + "/v1.beta/invoices/\(urlEncode(remoteID))"
        guard let url = URL(string: endpoint) else {
            throw SuperPDPError.decoding("URL de statut invalide : \(endpoint)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw SuperPDPError.decoding("Réponse non HTTP")
        }
        guard (200...299).contains(http.statusCode) else {
            throw SuperPDPError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw SuperPDPError.decoding("JSON statut illisible")
        }
        let status = (obj["status"] as? String) ?? (obj["en_invoice"] == nil ? "pending" : "processed")
        return SuperPDPInvoiceSubmission(
            remoteID: remoteID,
            status: status,
            enInvoiceRef: obj["en_invoice"] as? String,
            submittedAt: Date(),
            lastCheckedAt: Date(),
            message: obj["message"] as? String
        )
    }

    public func sendInvoiceEvent(remoteID: String, statusCode: String, credentials: SuperPDPCredentials, reportedData: [[String: Any]]? = nil) async throws {
        let token = try await fetchToken(credentials: credentials)
        let endpoint = trimmedBase(credentials) + "/v1.beta/invoice_events"
        guard let url = URL(string: endpoint) else {
            throw SuperPDPError.decoding("URL d'événement invalide : \(endpoint)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: Any] = [
            "invoice_id": remoteID,
            "status_code": statusCode
        ]
        if let reported = reportedData, !reported.isEmpty {
            payload["details"] = [["reported_data": reported]]
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw SuperPDPError.decoding("Réponse non HTTP")
        }
        guard (200...299).contains(http.statusCode) else {
            throw SuperPDPError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
    }

    private func buildMultipartBody(boundary: String, fieldName: String, fileName: String, content: Data) -> Data {
        var body = Data()
        let crlf = "\r\n"
        body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\(crlf)".data(using: .utf8)!)
        body.append("Content-Type: application/xml\(crlf)\(crlf)".data(using: .utf8)!)
        body.append(content)
        body.append("\(crlf)--\(boundary)--\(crlf)".data(using: .utf8)!)
        return body
    }
}

// MARK: - Conversions

public extension SuperPDPDirectoryEntry {
    func toInvoiceParty() -> InvoiceParty {
        let sirenValue = siren ?? (siret.flatMap { SuperPDPService.extractSiren(from: $0) })
        return InvoiceParty(
            name: name ?? "",
            street: addressLine ?? "",
            postcode: postcode ?? "",
            city: city ?? "",
            country: country ?? "FR",
            vatNumber: nil,
            siren: sirenValue,
            siret: siret,
            endpointID: routingAddress ?? sirenValue,
            endpointSchemeID: routingScheme ?? "0225"
        )
    }
}

// MARK: - Settings storage

public final class SuperPDPSettings: ObservableObject {
    public static let shared = SuperPDPSettings()

    @Published public var credentials: SuperPDPCredentials

    private let defaults = UserDefaults.standard
    private let env = AppEnvironment.shared
    private var storageKey: String { env.key("facturx.superpdp.credentials.v1") }

    public init() {
        if let data = defaults.data(forKey: env.key("facturx.superpdp.credentials.v1")),
           let decoded = try? JSONDecoder().decode(SuperPDPCredentials.self, from: data) {
            credentials = decoded
        } else {
            credentials = SuperPDPCredentials(clientID: "", clientSecret: "", useSandbox: env.isTest)
        }
    }

    public func save() {
        if let data = try? JSONEncoder().encode(credentials) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
