import Foundation

public struct SireneCredentials: Codable, Equatable {
    public var clientKey: String
    public var clientSecret: String
    public var tokenURL: String
    public var apiBaseURL: String

    public init(
        clientKey: String,
        clientSecret: String,
        tokenURL: String = "https://api.insee.fr/token",
        apiBaseURL: String = "https://api.insee.fr/entreprises/sirene/V3"
    ) {
        self.clientKey = clientKey
        self.clientSecret = clientSecret
        self.tokenURL = tokenURL
        self.apiBaseURL = apiBaseURL
    }

    public var isConfigured: Bool {
        !clientKey.trimmingCharacters(in: .whitespaces).isEmpty
            && !clientSecret.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case clientKey, clientSecret, tokenURL, apiBaseURL
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clientKey = try c.decodeIfPresent(String.self, forKey: .clientKey) ?? ""
        clientSecret = try c.decodeIfPresent(String.self, forKey: .clientSecret) ?? ""
        tokenURL = try c.decodeIfPresent(String.self, forKey: .tokenURL) ?? "https://api.insee.fr/token"
        apiBaseURL = try c.decodeIfPresent(String.self, forKey: .apiBaseURL) ?? "https://api.insee.fr/entreprises/sirene/V3"
    }
}

public enum SireneError: Error, LocalizedError {
    case notConfigured
    case http(status: Int, body: String)
    case decoding(String)
    case noToken
    case emptyQuery
    case notFound

    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "Identifiants API Sirene non configurés. Ouvrez les Réglages."
        case .http(let status, let body): return "Erreur HTTP \(status) : \(body)"
        case .decoding(let m): return "Décodage impossible : \(m)"
        case .noToken: return "Aucun jeton d'accès renvoyé par l'API Sirene."
        case .emptyQuery: return "Saisissez un SIREN (9 chiffres) ou SIRET (14 chiffres) à rechercher."
        case .notFound: return "Aucune entreprise trouvée pour ce SIREN/SIRET."
        }
    }
}

public struct SireneResult: Hashable {
    public var siren: String
    public var siret: String?
    public var denomination: String?
    public var street: String?
    public var postcode: String?
    public var city: String?
    public var country: String
    public var isActive: Bool

    public init(
        siren: String,
        siret: String? = nil,
        denomination: String? = nil,
        street: String? = nil,
        postcode: String? = nil,
        city: String? = nil,
        country: String = "FR",
        isActive: Bool = true
    ) {
        self.siren = siren
        self.siret = siret
        self.denomination = denomination
        self.street = street
        self.postcode = postcode
        self.city = city
        self.country = country
        self.isActive = isActive
    }

    public func merged(into party: InvoiceParty) -> InvoiceParty {
        var p = party
        if let d = denomination, !d.isEmpty { p.name = d }
        if let s = street, !s.isEmpty { p.street = s }
        if let pc = postcode, !pc.isEmpty { p.postcode = pc }
        if let c = city, !c.isEmpty { p.city = c }
        p.siren = siren
        if (party.endpointID == nil || party.endpointID?.isEmpty == true), !siren.isEmpty {
            p.endpointID = siren
            p.endpointSchemeID = "0225"
        }
        return p
    }
}

public final class SireneService {
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
    }

    private struct TokenResponse: Decodable {
        let access_token: String?
        let token_type: String?
        let expires_in: Int?
    }

    public func fetchToken(credentials: SireneCredentials) async throws -> String {
        guard credentials.isConfigured else { throw SireneError.notConfigured }
        guard let url = URL(string: credentials.tokenURL) else {
            throw SireneError.decoding("URL de token invalide")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let basic = Data("\(credentials.clientKey):\(credentials.clientSecret)".utf8).base64EncodedString()
        req.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        let body = "grant_type=client_credentials"
        req.httpBody = body.data(using: .utf8)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw SireneError.decoding("Réponse non HTTP")
        }
        guard (200...299).contains(http.statusCode) else {
            throw SireneError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        let token = try decoder.decode(TokenResponse.self, from: data)
        guard let access = token.access_token, !access.isEmpty else {
            throw SireneError.noToken
        }
        return access
    }

    public func lookup(siretOrSiren: String, credentials: SireneCredentials) async throws -> SireneResult {
        let query = siretOrSiren.trimmingCharacters(in: .whitespaces)
            .filter { $0.isNumber }
        guard !query.isEmpty else { throw SireneError.emptyQuery }
        let token = try await fetchToken(credentials: credentials)
        let base = credentials.apiBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let isSiret = query.count >= 14
        let path: String
        if isSiret {
            path = "/siret/" + query
        } else {
            path = "/siren/" + query
        }
        guard let url = URL(string: base + path) else {
            throw SireneError.decoding("URL d'API invalide : \(base + path)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw SireneError.decoding("Réponse non HTTP")
        }
        if http.statusCode == 404 {
            throw SireneError.notFound
        }
        guard (200...299).contains(http.statusCode) else {
            throw SireneError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        let obj: Any
        do {
            obj = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw SireneError.decoding("\(error)")
        }
        guard let dict = obj as? [String: Any] else {
            throw SireneError.decoding("Réponse inattendue (pas un objet JSON)")
        }
        if isSiret {
            return try parseEtablissement(dict: dict)
        } else {
            return try parseUniteLegale(dict: dict)
        }
    }

    private func parseUniteLegale(dict: [String: Any]) throws -> SireneResult {
        guard let ul = dict["uniteLegale"] as? [String: Any] else {
            throw SireneError.decoding("Champ uniteLegale absent")
        }
        func s(_ key: String) -> String? {
            if let v = ul[key] as? String { return v.isEmpty ? nil : v }
            return nil
        }
        let siren = s("siren") ?? ""
        let denomination = s("denominationUniteLegale") ?? s("nomUniteLegale") ?? s("nomUsageUniteLegale")
        var street: String? = nil
        var postcode: String? = nil
        var city: String? = nil
        if let periodes = ul["periodesUniteLegale"] as? [[String: Any]], let first = periodes.first,
           let addr = first["adressePostaleEtablissement"] as? [String: Any] {
            var parts: [String] = []
            if let n = addr["numeroVoieEtablissement"] as? String, !n.isEmpty { parts.append(n) }
            if let t = addr["typeVoieEtablissement"] as? String, !t.isEmpty { parts.append(t) }
            if let l = addr["libelleVoieEtablissement"] as? String, !l.isEmpty { parts.append(l) }
            street = parts.isEmpty ? nil : parts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if street == nil, let l2 = addr["l2AdresseEtablissement"] as? String, !l2.isEmpty { street = l2 }
            postcode = addr["codePostalEtablissement"] as? String
            city = addr["libelleCommuneEtablissement"] as? String
        }
        let active = (s("etatAdministratifUniteLegale") ?? "A") == "A"
        return SireneResult(
            siren: siren,
            siret: nil,
            denomination: denomination,
            street: street,
            postcode: postcode,
            city: city,
            country: "FR",
            isActive: active
        )
    }

    private func parseEtablissement(dict: [String: Any]) throws -> SireneResult {
        guard let etab = dict["etablissement"] as? [String: Any] else {
            throw SireneError.decoding("Champ etablissement absent")
        }
        func s(_ key: String) -> String? {
            if let v = etab[key] as? String { return v.isEmpty ? nil : v }
            return nil
        }
        let siret = s("siret") ?? ""
        let siren = String(siret.prefix(9))
        let denomination = s("denominationUsuelleEtablissement") ?? s("enseigne1Etablissement")
        var street: String? = nil
        var postcode: String? = nil
        var city: String? = nil
        if let addr = etab["adressePostaleEtablissement"] as? [String: Any] {
            var parts: [String] = []
            if let n = addr["numeroVoieEtablissement"] as? String, !n.isEmpty { parts.append(n) }
            if let t = addr["typeVoieEtablissement"] as? String, !t.isEmpty { parts.append(t) }
            if let l = addr["libelleVoieEtablissement"] as? String, !l.isEmpty { parts.append(l) }
            street = parts.isEmpty ? nil : parts.joined(separator: " ")
            if street == nil, let l2 = addr["l2AdresseEtablissement"] as? String, !l2.isEmpty { street = l2 }
            postcode = addr["codePostalEtablissement"] as? String
            city = addr["libelleCommuneEtablissement"] as? String
        }
        let active = (s("etatAdministratifEtablissement") ?? "A") == "A"
        return SireneResult(
            siren: siren,
            siret: siret,
            denomination: denomination,
            street: street,
            postcode: postcode,
            city: city,
            country: "FR",
            isActive: active
        )
    }
}

public final class SireneSettings: ObservableObject {
    public static let shared = SireneSettings()

    @Published public var credentials: SireneCredentials

    private let defaults = UserDefaults.standard
    private let storageKey = "facturx.sirene.credentials.v1"

    public init() {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(SireneCredentials.self, from: data) {
            credentials = decoded
        } else {
            credentials = SireneCredentials(clientKey: "", clientSecret: "")
        }
    }

    public func save() {
        if let data = try? JSONEncoder().encode(credentials) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
