import Foundation

public struct ChorusProCredentials: Codable, Equatable {
    public var clientID: String
    public var clientSecret: String
    public var tokenURL: String
    public var apiBaseURL: String

    public init(
        clientID: String,
        clientSecret: String,
        tokenURL: String = "https://oauth.piste.gouv.fr/oauth2/v1/token",
        apiBaseURL: String = "https://api.piste.gouv.fr"
    ) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.tokenURL = tokenURL
        self.apiBaseURL = apiBaseURL
    }

    public var isConfigured: Bool {
        !clientID.trimmingCharacters(in: .whitespaces).isEmpty
            && !clientSecret.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

public enum ChorusProError: Error, LocalizedError {
    case notConfigured
    case http(status: Int, body: String)
    case decoding(String)
    case noToken
    case emptyQuery

    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "Identifiants PISTE non configurés. Ouvrez les Réglages."
        case .http(let status, let body): return "Erreur HTTP \(status) : \(body)"
        case .decoding(let m): return "Décodage impossible : \(m)"
        case .noToken: return "Aucun jeton d'accès renvoyé par PISTE."
        case .emptyQuery: return "Saisissez un SIRET (14 chiffres) à rechercher."
        }
    }
}

public struct ChorusProResult: Identifiable, Hashable {
    public var id: String { siret ?? denomination ?? UUID().uuidString }
    public var denomination: String?
    public var siren: String?
    public var siret: String?
    public var addressLine: String?
    public var postcode: String?
    public var city: String?
    public var country: String?
    public var hasPlatform: Bool?
    public var isActive: Bool?
    public var raw: [String: String]

    public init(
        denomination: String? = nil,
        siren: String? = nil,
        siret: String? = nil,
        addressLine: String? = nil,
        postcode: String? = nil,
        city: String? = nil,
        country: String? = nil,
        hasPlatform: Bool? = nil,
        isActive: Bool? = nil,
        raw: [String: String] = [:]
    ) {
        self.denomination = denomination
        self.siren = siren
        self.siret = siret
        self.addressLine = addressLine
        self.postcode = postcode
        self.city = city
        self.country = country
        self.hasPlatform = hasPlatform
        self.isActive = isActive
        self.raw = raw
    }

    public var displaySubtitle: String {
        var parts: [String] = []
        if let siret = siret, !siret.isEmpty { parts.append("SIRET \(siret)") }
        if let siren = siren, !siren.isEmpty { parts.append("SIREN \(siren)") }
        if let city = city, !city.isEmpty { parts.append(city) }
        if isActive == true { parts.append("active") } else if isActive == false { parts.append("inactive") }
        return parts.joined(separator: " · ")
    }
}

public final class ChorusProService {
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

    private struct TokenResponse: Decodable {
        let access_token: String?
        let token_type: String?
        let expires_in: Int?
    }

    public func fetchToken(credentials: ChorusProCredentials) async throws -> String {
        guard credentials.isConfigured else { throw ChorusProError.notConfigured }
        guard let url = URL(string: credentials.tokenURL) else {
            throw ChorusProError.decoding("URL de token invalide")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let basic = Data("\(credentials.clientID):\(credentials.clientSecret)".utf8).base64EncodedString()
        req.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        let body = "grant_type=client_credentials&scope=scope"
        req.httpBody = body.data(using: .utf8)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw ChorusProError.decoding("Réponse non HTTP")
        }
        guard (200...299).contains(http.statusCode) else {
            throw ChorusProError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        let token = try decoder.decode(TokenResponse.self, from: data)
        guard let access = token.access_token, !access.isEmpty else {
            throw ChorusProError.noToken
        }
        return access
    }

    public func searchRecipient(siretOrSiren: String, credentials: ChorusProCredentials) async throws -> [ChorusProResult] {
        let query = siretOrSiren.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { throw ChorusProError.emptyQuery }
        let token = try await fetchToken(credentials: credentials)
        let endpoint = credentials.apiBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            + "/chorus-pro/annuaire/v1/rechercher"
        guard let url = URL(string: endpoint) else {
            throw ChorusProError.decoding("URL d'API invalide : \(endpoint)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "idCriteria": query,
            "typeRecherche": query.count >= 14 ? "SIRET" : "SIREN"
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw ChorusProError.decoding("Réponse non HTTP")
        }
        guard (200...299).contains(http.statusCode) else {
            throw ChorusProError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return try parseResults(data: data)
    }

    private func parseResults(data: Data) throws -> [ChorusProResult] {
        let obj: Any
        do {
            obj = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw ChorusProError.decoding("\(error)")
        }
        var items: [[String: Any]] = []
        if let arr = obj as? [[String: Any]] {
            items = arr
        } else if let dict = obj as? [String: Any], let list = dict["resultats"] as? [[String: Any]] {
            items = list
        } else if let dict = obj as? [String: Any], let list = dict["listeResultat"] as? [[String: Any]] {
            items = list
        } else if let dict = obj as? [String: Any] {
            items = [dict]
        }
        return items.map { mapResult($0) }
    }

    private func mapResult(_ dict: [String: Any]) -> ChorusProResult {
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
        let denom = s("denomination") ?? s("raisonSociale") ?? s("nom")
        let siret = s("siret") ?? s("identifiantStructure") ?? s("idStructure")
        let siren = s("siren")
        let address = s("adresse") ?? s("adressePostale") ?? s("adresseDestinataire")
        let postcode = s("codePostal")
        let city = s("ville") ?? s("commune") ?? s("localite")
        let country = s("pays") ?? s("codePays")
        let hasPlat = b("plateformeAgreerattachee") ?? b("plateformeAgreeRattachee") ?? b("hasPlateforme")
        let active = b("adresseActive") ?? b("actif")
        var raw: [String: String] = [:]
        for (k, v) in dict {
            if let sv = v as? String { raw[k] = sv }
            else if let nv = v as? NSNumber { raw[k] = nv.stringValue }
            else if let bv = v as? Bool { raw[k] = bv ? "Oui" : "Non" }
        }
        return ChorusProResult(
            denomination: denom,
            siren: siren,
            siret: siret,
            addressLine: address,
            postcode: postcode,
            city: city,
            country: country,
            hasPlatform: hasPlat,
            isActive: active,
            raw: raw
        )
    }
}

public extension ChorusProResult {
    func toInvoiceParty() -> InvoiceParty {
        let sirenValue = siren ?? (siret.flatMap { ChorusProService.extractSiren(from: $0) })
        return InvoiceParty(
            name: denomination ?? "",
            street: addressLine ?? "",
            postcode: postcode ?? "",
            city: city ?? "",
            country: country ?? "FR",
            vatNumber: nil,
            siren: sirenValue,
            endpointID: sirenValue,
            endpointSchemeID: "0225"
        )
    }
}

public final class ChorusProSettings: ObservableObject {
    public static let shared = ChorusProSettings()

    @Published public var credentials: ChorusProCredentials

    private let defaults = UserDefaults.standard
    private let storageKey = "facturx.choruspro.credentials.v1"

    public init() {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(ChorusProCredentials.self, from: data) {
            credentials = decoded
        } else {
            credentials = ChorusProCredentials(clientID: "", clientSecret: "")
        }
    }

    public func save() {
        if let data = try? JSONEncoder().encode(credentials) {
            defaults.set(data, forKey: storageKey)
        }
    }
