import Foundation

// Taux de change d'une facture hors euro : BR-FR-CO-12 (Schematron France CTC, fatal) exige la
// TVA en euros (BT-111), que `Invoice.taxTotalInEuros` calcule à partir de ce taux. Convention de
// la BCE : 1 EUR = taux unités de la devise de facture.

public extension Invoice {
    /// Change la devise (BT-5). Un taux de change ne vaut que pour sa devise : il est effacé quand
    /// la devise change (1 EUR = 1,15 USD serait faux en GBP), et n'a plus d'objet en euros. Même
    /// code : rien ne change.
    mutating func setCurrency(_ code: String) {
        guard code != currency else { return }
        currency = code
        exchangeRate = nil
        exchangeRateReferenceDate = nil
    }

    /// Taux saisi à la main : ce n'est plus le cours de la BCE, dont le jour est effacé. Un taux
    /// inchangé (champ validé sans modification) garde son jour.
    mutating func setExchangeRate(_ rate: Double?) {
        guard rate != exchangeRate else { return }
        exchangeRate = rate
        exchangeRateReferenceDate = nil
    }

    /// Cours de référence de la BCE repris par le bouton « Taux BCE » : le taux et son jour.
    mutating func applyReferenceRate(_ reference: ECBReferenceRate) {
        exchangeRate = reference.rate
        exchangeRateReferenceDate = reference.day
    }

    /// Copie datée d'un autre jour (duplicata, acompte, solde) : le taux d'origine était celui de
    /// la date de la facture copiée, la copie repart donc sans taux, et BR-FR-CO-12 la bloque
    /// jusqu'à la saisie. L'avoir garde celui de sa facture (même choix que le SaaS ARVERNX).
    internal mutating func clearExchangeRateForNewDate() {
        exchangeRate = nil
        exchangeRateReferenceDate = nil
    }

    /// Mention du PDF sous « Total TVA en EUR », une ligne par élément : « Taux de change : 1 EUR =
    /// 1.146 USD », puis pour un cours repris de la BCE « Cours de référence BCE du 18/09/2026 » et
    /// « (table Banque de France) ». Vide tant que la TVA en euros n'est pas calculée (facture en
    /// euros, taux absent ou invalide).
    var exchangeRateMention: [String] {
        guard taxTotalInEuros != nil, let rate = exchangeRate else { return [] }
        var lines = ["Taux de change : 1 EUR = \(ExchangeRateText.string(rate)) \(CIIXMLGenerator.xmlCurrency(currency))"]
        if let day = exchangeRateReferenceDate {
            lines += ["Cours de référence BCE du \(ExchangeRateText.day(day))", "(table Banque de France)"]
        }
        return lines
    }
}

public enum ExchangeRateText {
    /// Le taux tel que la BCE le publie : « 1.146 », « 163.25 », « 138 », sans zéro final (au plus
    /// 6 décimales), avec le point décimal des montants du PDF.
    public static func string(_ rate: Double) -> String {
        var text = String(format: "%.6f", rate)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// « 18/09/2026 », dans le fuseau de l'application comme les autres dates du PDF.
    public static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.string(from: date)
    }
}

/// Cours de référence quotidien de la BCE : 1 EUR = `rate` unités de `currency`, publié le jour
/// `day`, vers 16 h (heure de Francfort) les jours ouvrés. Ce sont aussi les cours de la table
/// « Taux de change (parités quotidiennes) » de la Banque de France, qui reprend les séries de la
/// BCE (EXR.D.<devise>.EUR.SP00.A, « source BCE »).
public struct ECBReferenceRate: Equatable {
    public let currency: String
    public let rate: Double
    /// Jour de la cotation, à midi dans le fuseau de l'application comme les dates lues du XML
    /// (`DocumentDate`) : il s'affiche le même jour quel que soit le fuseau.
    public let day: Date

    public init(currency: String, rate: Double, day: Date) {
        self.currency = currency
        self.rate = rate
        self.day = day
    }
}

public enum ECBReferenceRateError: Error, Equatable, LocalizedError {
    /// Devise que la BCE ne cote pas : le taux est à saisir.
    case notQuoted(currency: String)
    /// Aucune cotation dans les jours qui précèdent la date demandée.
    case noRate(currency: String)
    /// Service injoignable, ou réponse illisible.
    case service(String)

    public var errorDescription: String? {
        switch self {
        case .notQuoted(let currency):
            return "La BCE ne publie pas de cours de référence pour « \(currency) » : saisissez le taux de change."
        case .noRate(let currency):
            return "Aucun cours de référence BCE pour \(currency) dans les \(ECBReferenceRateService.lookbackDays) jours précédant la date de facture : saisissez le taux de change."
        case .service(let detail):
            return "Cours de la BCE indisponible (\(detail)) : réessayez plus tard, ou saisissez le taux de change."
        }
    }
}

/// Client du service public de données de la BCE (data-api.ecb.europa.eu), sans compte ni clé.
/// L'API Webstat de la Banque de France, qui diffuse les mêmes cours, exige une clé.
public final class ECBReferenceRateService {
    /// Devises dont la BCE publie un cours de référence quotidien, relevées le 2026-09-24 (même
    /// liste que le SaaS ARVERNX). Pour les autres, aucun appel : le taux est à saisir.
    public static let quotedCurrencies: Set<String> = [
        "AUD", "BRL", "CAD", "CHF", "CNY", "CZK", "DKK", "GBP", "HKD", "HUF",
        "IDR", "ILS", "INR", "ISK", "JPY", "KRW", "MXN", "MYR", "NOK", "NZD",
        "PHP", "PLN", "RON", "SEK", "SGD", "THB", "TRY", "USD", "ZAR",
    ]

    /// Jours parcourus en arrière pour trouver le dernier cours publié : un week-end prolongé de
    /// jours fériés (Noël, Pâques) en laisse jusqu'à quatre sans cotation.
    public static let lookbackDays = 14

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Dernier cours publié au plus tard le jour de `date`, et au plus tard aujourd'hui pour une
    /// facture datée plus loin. Les jours sont ceux du fuseau de l'application, comme la date de
    /// facture affichée et écrite dans le XML.
    public func referenceRate(currency: String, on date: Date, today: Date = Date()) async throws -> ECBReferenceRate {
        let code = CIIXMLGenerator.xmlCurrency(currency)
        guard Self.quotedCurrencies.contains(code) else { throw ECBReferenceRateError.notQuoted(currency: code) }
        let (startDay, endDay) = Self.window(endingOn: min(date, today))
        var request = URLRequest(url: Self.url(currency: code, startDay: startDay, endDay: endDay), timeoutInterval: 10)
        request.setValue("text/csv", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ECBReferenceRateError.service(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ECBReferenceRateError.service("réponse non HTTP")
        }
        // 404 : aucune série ou aucune cotation sur la période. Une période faite d'un seul
        // week-end répond 200 avec un corps vide, traité par `latest`.
        if http.statusCode == 404 { throw ECBReferenceRateError.noRate(currency: code) }
        guard http.statusCode == 200 else { throw ECBReferenceRateError.service("HTTP \(http.statusCode)") }
        return try Self.latest(currency: code, csv: data, endDay: endDay)
    }

    /// Jours de début et de fin (AAAA-MM-JJ) de la période interrogée : les `lookbackDays` jours
    /// qui précèdent `end`, lui compris.
    static func window(endingOn end: Date) -> (startDay: String, endDay: String) {
        let endNoon = DocumentDate.date(xmlString: DocumentDate.xmlString(end)) ?? end
        let start = endNoon.addingTimeInterval(-Double(lookbackDays) * 86400)
        return (DocumentDate.isoString(start), DocumentDate.isoString(endNoon))
    }

    static func url(currency: String, startDay: String, endDay: String) -> URL {
        var components = URLComponents(string: "https://data-api.ecb.europa.eu/service/data/EXR/D.\(currency).EUR.SP00.A")!
        components.queryItems = [
            URLQueryItem(name: "startPeriod", value: startDay),
            URLQueryItem(name: "endPeriod", value: endDay),
            URLQueryItem(name: "format", value: "csvdata"),
        ]
        return components.url!
    }

    /// Cotation la plus récente, au plus tard `endDay`, d'une réponse CSV (`format=csvdata`) : une
    /// ligne d'en-tête, puis une ligne par jour coté, avec les colonnes TIME_PERIOD (AAAA-MM-JJ) et
    /// OBS_VALUE. Une valeur vide ou non positive est ignorée.
    static func latest(currency: String, csv: Data, endDay: String) throws -> ECBReferenceRate {
        let text = String(decoding: csv, as: UTF8.self)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ECBReferenceRateError.noRate(currency: currency)
        }
        let rows = csvRows(text)
        guard let header = rows.first,
              let dayColumn = header.firstIndex(of: "TIME_PERIOD"),
              let valueColumn = header.firstIndex(of: "OBS_VALUE") else {
            throw ECBReferenceRateError.service("réponse illisible, colonnes TIME_PERIOD et OBS_VALUE absentes")
        }
        var best: (day: String, rate: Double)?
        for row in rows.dropFirst() where row.count > max(dayColumn, valueColumn) {
            let day = row[dayColumn]
            guard day.count == 10, day <= endDay, day > (best?.day ?? ""),
                  let rate = Double(row[valueColumn]), rate.isFinite, rate > 0 else { continue }
            best = (day, rate)
        }
        guard let best, let date = DocumentDate.date(xmlString: best.day.replacingOccurrences(of: "-", with: "")) else {
            throw ECBReferenceRateError.noRate(currency: currency)
        }
        return ECBReferenceRate(currency: currency, rate: best.rate, day: date)
    }

    /// Lignes d'un CSV RFC 4180 : champs séparés par des virgules, entre guillemets quand ils en
    /// contiennent (le titre de la série, « ECB reference exchange rate, US dollar/Euro… »).
    static func csvRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = Array(text).makeIterator()
        var pending: Character? = nil
        while let char = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if char == "\"" {
                    let next = iterator.next()
                    if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                } else {
                    field.append(char)
                }
            } else {
                switch char {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\n", "\r\n", "\r":
                    row.append(field); field = ""
                    if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                    row = []
                default: field.append(char)
                }
            }
        }
        row.append(field)
        if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
        return rows
    }
}
