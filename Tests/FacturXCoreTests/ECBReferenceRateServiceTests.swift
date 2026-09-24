import XCTest
@testable import FacturXCore

/// Bouton « Taux BCE » de l'éditeur de facture : cours de référence de la BCE à la date de
/// facture, ceux que la Banque de France publie dans sa table des parités quotidiennes (mêmes
/// séries EXR.D.<devise>.EUR.SP00.A, « source BCE »). L'API Webstat de la Banque de France exige
/// une clé, celle de la BCE non : choix de l'utilisateur du 2026-09-24. Réponses du service
/// relevées le même jour (data-api.ecb.europa.eu) : CSV avec en-tête ; 200 et corps vide pour
/// une période faite d'un week-end ; 404 pour une série inconnue. Aucun appel réseau ici : les
/// réponses sont servies par `ECBStubURLProtocol`.
final class ECBReferenceRateServiceTests: XCTestCase {

    private var savedTimeZone: TimeZone!

    override func setUp() {
        super.setUp()
        savedTimeZone = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: "Europe/Paris")!
        ECBStubURLProtocol.reset()
    }

    override func tearDown() {
        NSTimeZone.default = savedTimeZone
        ECBStubURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Outils

    private func day(_ iso: String) -> Date {
        DocumentDate.date(xmlString: iso.replacingOccurrences(of: "-", with: ""))!
    }

    private var service: ECBReferenceRateService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ECBStubURLProtocol.self]
        return ECBReferenceRateService(session: URLSession(configuration: configuration))
    }

    /// Réponse réelle du 2026-09-24 pour USD (colonnes de fin coupées), plus un jour postérieur à
    /// la période demandée, à ignorer.
    private let usdCSV = """
    KEY,FREQ,CURRENCY,CURRENCY_DENOM,EXR_TYPE,EXR_SUFFIX,TIME_PERIOD,OBS_VALUE,OBS_STATUS,OBS_CONF,TITLE,TITLE_COMPL\r
    EXR.D.USD.EUR.SP00.A,D,USD,EUR,SP00,A,2026-09-16,1.1537,A,F,US dollar/Euro ECB reference exchange rate,"ECB reference exchange rate, US dollar/Euro, 2.15 pm (C.E.T.)"\r
    EXR.D.USD.EUR.SP00.A,D,USD,EUR,SP00,A,2026-09-17,1.1481,A,F,US dollar/Euro ECB reference exchange rate,"ECB reference exchange rate, US dollar/Euro, 2.15 pm (C.E.T.)"\r
    EXR.D.USD.EUR.SP00.A,D,USD,EUR,SP00,A,2026-09-18,1.146,A,F,US dollar/Euro ECB reference exchange rate,"ECB reference exchange rate, US dollar/Euro, 2.15 pm (C.E.T.)"\r
    EXR.D.USD.EUR.SP00.A,D,USD,EUR,SP00,A,2026-09-21,1.149,A,F,US dollar/Euro ECB reference exchange rate,"ECB reference exchange rate, US dollar/Euro, 2.15 pm (C.E.T.)"\r

    """

    private func assertThrows(_ expected: ECBReferenceRateError, currency: String = "USD",
                              on date: String = "2026-09-20", file: StaticString = #filePath, line: UInt = #line) async {
        do {
            let rate = try await service.referenceRate(currency: currency, on: day(date), today: day("2026-09-24"))
            XCTFail("taux inattendu : \(rate)", file: file, line: line)
        } catch let error as ECBReferenceRateError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("erreur inattendue : \(error)", file: file, line: line)
        }
    }

    // MARK: - Devises

    /// Le bouton sert pour toute devise du sélecteur de l'éditeur.
    func testEveryPickerCurrencyIsQuotedByTheECB() {
        for code in NormRefs.currencies.map(\.code) where code != "EUR" {
            XCTAssertTrue(ECBReferenceRateService.quotedCurrencies.contains(code), code)
        }
        XCTAssertEqual(ECBReferenceRateService.quotedCurrencies.count, 29)
        XCTAssertFalse(ECBReferenceRateService.quotedCurrencies.contains("EUR"))
    }

    func testUnquotedCurrencyMakesNoRequest() async {
        await assertThrows(.notQuoted(currency: "XOF"), currency: "XOF")
        XCTAssertTrue(ECBStubURLProtocol.requests.isEmpty)
    }

    // MARK: - Requête et réponse

    /// Facture du dimanche 20/09/2026 : dernier cours publié au plus tard ce jour-là, celui du
    /// vendredi 18 ; le cours du lundi 21, hors période, ne compte pas.
    func testLatestRateOnOrBeforeTheInvoiceDateOverTheFourteenPrecedingDays() async throws {
        ECBStubURLProtocol.respond(status: 200, body: usdCSV)
        let rate = try await service.referenceRate(currency: "USD", on: day("2026-09-20"), today: day("2026-09-24"))
        XCTAssertEqual(rate, ECBReferenceRate(currency: "USD", rate: 1.146, day: day("2026-09-18")))
        XCTAssertEqual(DocumentDate.xmlString(rate.day), "20260918")

        let url = try XCTUnwrap(ECBStubURLProtocol.requests.first?.url)
        XCTAssertEqual(url.absoluteString,
                       "https://data-api.ecb.europa.eu/service/data/EXR/D.USD.EUR.SP00.A?startPeriod=2026-09-06&endPeriod=2026-09-20&format=csvdata")
        XCTAssertEqual(ECBStubURLProtocol.requests.count, 1)
    }

    /// Une facture datée plus loin prend le dernier cours connu, au plus tard aujourd'hui.
    func testFutureInvoiceDateAsksUpToToday() async throws {
        ECBStubURLProtocol.respond(status: 200, body: usdCSV)
        _ = try await service.referenceRate(currency: "USD", on: day("2026-10-15"), today: day("2026-09-24"))
        let url = try XCTUnwrap(ECBStubURLProtocol.requests.first?.url?.absoluteString)
        XCTAssertTrue(url.hasSuffix("startPeriod=2026-09-10&endPeriod=2026-09-24&format=csvdata"), url)
    }

    /// Le jour de la période est celui du fuseau de l'application : 20/09 à 00:30 à Paris est le
    /// 19/09 en UTC, mais bien le 20 pour l'éditeur et le XML.
    func testWindowUsesTheAppTimeZoneDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let justAfterMidnight = calendar.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 0, minute: 30))!
        let window = ECBReferenceRateService.window(endingOn: justAfterMidnight)
        XCTAssertEqual(window.startDay, "2026-09-06")
        XCTAssertEqual(window.endDay, "2026-09-20")
    }

    func testBlankOrInvalidValuesAreSkipped() throws {
        let csv = """
        TIME_PERIOD,OBS_VALUE
        2026-09-16,1.1537
        2026-09-17,NaN
        2026-09-18,
        2026-09-19,0
        """
        let rate = try ECBReferenceRateService.latest(currency: "USD", csv: Data(csv.utf8), endDay: "2026-09-20")
        XCTAssertEqual(rate.rate, 1.1537)
        XCTAssertEqual(DocumentDate.xmlString(rate.day), "20260916")
    }

    /// Une période faite d'un seul week-end : la BCE répond 200 avec un corps vide.
    func testEmptyBodyMeansNoRate() async {
        ECBStubURLProtocol.respond(status: 200, body: "")
        await assertThrows(.noRate(currency: "USD"))
    }

    func testNotFoundMeansNoRate() async {
        ECBStubURLProtocol.respond(status: 404, body: #"{"title":"Not Found","status":404}"#)
        await assertThrows(.noRate(currency: "USD"))
    }

    func testRowsOnlyAfterTheDateMeanNoRate() async {
        ECBStubURLProtocol.respond(status: 200, body: "TIME_PERIOD,OBS_VALUE\n2026-09-21,1.149\n")
        await assertThrows(.noRate(currency: "USD"))
    }

    func testServerErrorAndUnreadableAnswerAreServiceErrors() async {
        ECBStubURLProtocol.respond(status: 503, body: "")
        await assertThrows(.service("HTTP 503"))
        ECBStubURLProtocol.respond(status: 200, body: "<html><body>Maintenance</body></html>")
        await assertThrows(.service("réponse illisible, colonnes TIME_PERIOD et OBS_VALUE absentes"))
    }

    func testNetworkFailureIsAServiceError() async {
        ECBStubURLProtocol.fail(with: URLError(.notConnectedToInternet))
        do {
            _ = try await service.referenceRate(currency: "USD", on: day("2026-09-20"), today: day("2026-09-24"))
            XCTFail("taux inattendu")
        } catch let error as ECBReferenceRateError {
            guard case .service = error else { return XCTFail("\(error)") }
        } catch {
            XCTFail("erreur inattendue : \(error)")
        }
    }

    /// Les messages s'affichent sous le champ du taux : ils disent quoi faire.
    func testErrorMessagesTellToEnterTheRate() {
        for error in [ECBReferenceRateError.notQuoted(currency: "XOF"), .noRate(currency: "USD"), .service("HTTP 503")] {
            let message = error.errorDescription ?? ""
            XCTAssertTrue(message.contains("saisissez le taux de change"), message)
        }
    }

    // MARK: - CSV

    func testCSVRowsHandleQuotedCommasDoubledQuotesAndLineEndings() {
        let rows = ECBReferenceRateService.csvRows("A,B,C\r\n1,\"x, y\",\"dit \"\"oui\"\"\"\n2,,3\r\n")
        XCTAssertEqual(rows, [["A", "B", "C"], ["1", "x, y", "dit \"oui\""], ["2", "", "3"]])
    }
}

/// Réponses du service de la BCE servies sans réseau.
final class ECBStubURLProtocol: URLProtocol {
    private static var status = 500
    private static var body = Data()
    private static var failure: Error?
    private(set) static var requests: [URLRequest] = []

    static func reset() {
        status = 500
        body = Data()
        failure = nil
        requests = []
    }

    static func respond(status: Int, body: String) {
        self.status = status
        self.body = Data(body.utf8)
        failure = nil
    }

    static func fail(with error: Error) {
        failure = error
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        if let failure = Self.failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "text/csv"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
