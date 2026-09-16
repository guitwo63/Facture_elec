import Foundation

public enum SireneError: Error, LocalizedError {
    case http(status: Int, body: String)
    case decoding(String)
    case emptyQuery
    case notFound

    public var errorDescription: String? {
        switch self {
        case .http(let status, let body): return "Erreur HTTP \(status) : \(body)"
        case .decoding(let m): return "Décodage impossible : \(m)"
        case .emptyQuery: return "Saisissez un SIREN (9 chiffres), un SIRET (14 chiffres) ou un nom à rechercher."
        case .notFound: return "Aucune entreprise trouvée."
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
    public var vatNumber: String?

    public init(
        siren: String,
        siret: String? = nil,
        denomination: String? = nil,
        street: String? = nil,
        postcode: String? = nil,
        city: String? = nil,
        country: String = "FR",
        isActive: Bool = true,
        vatNumber: String? = nil
    ) {
        self.siren = siren
        self.siret = siret
        self.denomination = denomination
        self.street = street
        self.postcode = postcode
        self.city = city
        self.country = country
        self.isActive = isActive
        self.vatNumber = vatNumber
    }

    public func merged(into party: InvoiceParty) -> InvoiceParty {
        var p = party
        if let d = denomination, !d.isEmpty { p.name = d }
        if let s = street, !s.isEmpty { p.street = s }
        if let pc = postcode, !pc.isEmpty { p.postcode = pc }
        if let c = city, !c.isEmpty { p.city = c }
        p.siren = siren
        if let st = siret, !st.isEmpty { p.siret = st }
        if let vat = vatNumber, !vat.isEmpty, (party.vatNumber == nil || party.vatNumber?.isEmpty == true) {
            p.vatNumber = vat
        }
        if (party.endpointID == nil || party.endpointID?.isEmpty == true), !siren.isEmpty {
            p.endpointID = siren
            p.endpointSchemeID = "0225"
        }
        return p
    }
}

public final class SireneService {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    private func urlEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }

    public func lookup(query: String) async throws -> [SireneResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw SireneError.emptyQuery }
        // L'API recherche-entreprises.api.gouv.fr n'accepte pas de préfixe de champ
        // (ex. "siren:123456789") dans le paramètre q : elle attend le numéro brut,
        // exactement comme une recherche par nom. Un préfixe fait échouer la requête
        // (0 résultat) — vérifié empiriquement.
        let digits = trimmed.filter { $0.isNumber }
        let isSiretOrSiren = digits.count == 9 || digits.count >= 14
        let qParam = isSiretOrSiren ? digits : trimmed
        let endpoint = "https://recherche-entreprises.api.gouv.fr/search?q=" + urlEncode(qParam)
        guard let url = URL(string: endpoint) else {
            throw SireneError.decoding("URL invalide : \(endpoint)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw SireneError.decoding("Réponse non HTTP")
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
            throw SireneError.decoding("Réponse inattendue")
        }
        guard let results = dict["results"] as? [[String: Any]] else {
            throw SireneError.decoding("Champ results absent")
        }
        if results.isEmpty { throw SireneError.notFound }
        return results.map { mapResult($0) }
    }

    private func mapResult(_ r: [String: Any]) -> SireneResult {
        func s(_ key: String) -> String? {
            if let v = r[key] as? String { return v.isEmpty ? nil : v }
            return nil
        }
        let siren = s("siren") ?? ""
        let denomination = s("nom_complet") ?? s("nom_raison_sociale") ?? s("denomination")
        let active = (s("etat_administratif") ?? "A") == "A"
        var street: String? = nil
        var postcode: String? = nil
        var city: String? = nil
        var siret: String? = nil
        if let siege = r["siege"] as? [String: Any] {
            func ss(_ key: String) -> String? {
                if let v = siege[key] as? String { return v.isEmpty ? nil : v }
                return nil
            }
            var parts: [String] = []
            if let n = ss("numero_voie"), !n.isEmpty { parts.append(n) }
            if let t = ss("type_voie"), !t.isEmpty { parts.append(t) }
            if let l = ss("libelle_voie"), !l.isEmpty { parts.append(l) }
            street = parts.isEmpty ? nil : parts.joined(separator: " ")
            postcode = ss("code_postal")
            city = ss("libelle_commune")
            siret = ss("siret")
        }
        var vat: String? = nil
        if let tvaArr = r["tva"] as? [String], let first = tvaArr.first { vat = first }
        return SireneResult(
            siren: siren,
            siret: siret,
            denomination: denomination,
            street: street,
            postcode: postcode,
            city: city,
            country: "FR",
            isActive: active,
            vatNumber: vat
        )
    }
}
