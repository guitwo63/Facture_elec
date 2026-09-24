import XCTest
@testable import FacturXCore

/// `GET /v1.beta/invoices` tel que le décrit la spec OpenAPI SUPER PDP 1.34.0.beta : `direction`
/// vaut `in` ou `out`, la liste est paginée (100 factures par défaut, 1 000 au plus, ids
/// croissants, `starting_after_id` + `has_after`). L'app envoyait `direction=received` et ne lisait
/// qu'une page : la réception automatique des factures d'achat ne pouvait pas marcher.
///
/// Les réponses viennent de `SuperPDPListStub`, branché sur une session propre au test : rien ne
/// sort de la machine.
final class SuperPDPInvoiceListPagingTests: XCTestCase {
    private var service: SuperPDPService!
    private let credentials = SuperPDPCredentials(clientID: "client-de-test", clientSecret: "secret-de-test",
                                                  apiBaseURL: "https://superpdp-liste.invalid")
    private let token = #"{"access_token":"jeton-de-test","token_type":"Bearer","expires_in":3600}"#

    override func setUp() {
        super.setUp()
        SuperPDPListStub.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SuperPDPListStub.self]
        service = SuperPDPService(session: URLSession(configuration: configuration))
    }

    override func tearDown() {
        SuperPDPListStub.reset()
        super.tearDown()
    }

    // MARK: - Paramètres

    func testReceivedInvoicesAreRequestedWithDirectionIn() async throws {
        SuperPDPListStub.respond { request in
            request.url?.path == "/oauth2/token" ? (200, self.token) : (200, Self.page(ids: [], hasAfter: false))
        }

        _ = try await service.listInvoices(direction: .received, credentials: credentials)

        let query = try XCTUnwrap(listRequests.first.map(Self.query))
        XCTAssertEqual(query["direction"], "in", "l'API n'accepte que in ou out")
        XCTAssertEqual(query["limit"], "1000")
        XCTAssertNil(query["starting_after_id"])
    }

    func testSentInvoicesAreRequestedWithDirectionOut() async throws {
        SuperPDPListStub.respond { request in
            request.url?.path == "/oauth2/token" ? (200, self.token) : (200, Self.page(ids: [], hasAfter: false))
        }

        _ = try await service.listInvoices(direction: .sent, credentials: credentials)

        XCTAssertEqual(listRequests.first.map(Self.query)?["direction"], "out")
    }

    // MARK: - Pagination

    func testEveryPageIsFetchedWithASingleToken() async throws {
        SuperPDPListStub.respond { request in
            guard request.url?.path == "/v1.beta/invoices" else { return (200, self.token) }
            switch Self.query(request)["starting_after_id"] {
            case nil: return (200, Self.page(ids: [11, 12, 13], hasAfter: true))
            case "13": return (200, Self.page(ids: [14, 15], hasAfter: false))
            default: return (400, #"{"detail":"curseur inattendu"}"#)
            }
        }

        let invoices = try await service.listInvoices(direction: .received, credentials: credentials)

        XCTAssertEqual(invoices.compactMap(\.remoteID), ["11", "12", "13", "14", "15"],
                       "les factures au-delà de la première page doivent être vues")
        XCTAssertEqual(invoices.map(\.direction), Array(repeating: .received, count: 5))
        XCTAssertEqual(listRequests.count, 2)
        XCTAssertEqual(SuperPDPListStub.requests.filter { $0.url?.path == "/oauth2/token" }.count, 1,
                       "un seul jeton pour toutes les pages")
    }

    func testPagingStopsWhenTheCursorDoesNotAdvance() async throws {
        // Serveur qui annonce toujours une page suivante et renvoie toujours la même facture.
        SuperPDPListStub.respond { request in
            request.url?.path == "/oauth2/token" ? (200, self.token) : (200, Self.page(ids: [21], hasAfter: true))
        }

        let invoices = try await service.listInvoices(direction: .received, credentials: credentials)

        XCTAssertEqual(listRequests.count, 2)
        XCTAssertEqual(invoices.compactMap(\.remoteID), ["21"], "une facture renvoyée deux fois n'est gardée qu'une fois")
    }

    func testRefusedPageThrowsTheHTTPError() async {
        SuperPDPListStub.respond { request in
            request.url?.path == "/oauth2/token"
                ? (200, self.token)
                : (400, #"{"detail":"direction: value must be one of in, out"}"#)
        }

        do {
            _ = try await service.listInvoices(direction: .received, credentials: credentials)
            XCTFail("un refus de SUPER PDP doit remonter")
        } catch SuperPDPError.http(let status, let body) {
            XCTAssertEqual(status, 400)
            XCTAssertTrue(body.contains("direction"), body)
        } catch {
            XCTFail("attendu .http, obtenu \(error)")
        }
    }

    func testResponseWithoutPaginationIsASinglePage() async throws {
        SuperPDPListStub.respond { request in
            request.url?.path == "/oauth2/token" ? (200, self.token) : (200, #"[{"id":31,"direction":"in"}]"#)
        }

        let invoices = try await service.listInvoices(direction: .received, credentials: credentials)

        XCTAssertEqual(invoices.compactMap(\.remoteID), ["31"])
        XCTAssertEqual(listRequests.count, 1, "sans has_after, pas de page suivante")
    }

    // MARK: - Direction et téléchargement

    func testDirectionInAndOutFromTheAPIAreMapped() {
        let service = SuperPDPService()
        XCTAssertEqual(service.mapInvoiceListItem(["id": 41, "direction": "in"], defaultDirection: .sent).direction, .received)
        XCTAssertEqual(service.mapInvoiceListItem(["id": 42, "direction": "out"], defaultDirection: .received).direction, .sent)
    }

    func testDownloadAsksForTheDepositedFileNotJSON() async throws {
        SuperPDPListStub.respond { request in
            request.url?.path == "/oauth2/token" ? (200, self.token) : (200, "<rsm:CrossIndustryInvoice/>")
        }

        _ = try await service.downloadInvoice(remoteID: "635790", credentials: credentials)

        let download = try XCTUnwrap(SuperPDPListStub.requests.first { $0.url?.path == "/v1.beta/invoices/635790/download" })
        XCTAssertEqual(download.value(forHTTPHeaderField: "Accept"), "application/xml, application/pdf",
                       "la route renvoie le fichier déposé, XML ou PDF")
    }

    // MARK: - Outils

    private var listRequests: [URLRequest] {
        SuperPDPListStub.requests.filter { $0.url?.path == "/v1.beta/invoices" }
    }

    private static func query(_ request: URLRequest) -> [String: String] {
        let items = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }

    /// Réponse de `GET /v1.beta/invoices` (schéma `list_invoices`), factures reçues.
    private static func page(ids: [Int], hasAfter: Bool) -> String {
        let items = ids.map { #"{"id":\#($0),"company_id":1,"created_at":"2026-09-24T08:00:00Z","direction":"in"}"# }
        return #"{"data":[\#(items.joined(separator: ","))],"count":\#(ids.count),"has_after":\#(hasAfter),"has_before":false}"#
    }
}

/// Faux SUPER PDP en mémoire, branché uniquement sur la session du test.
private final class SuperPDPListStub: URLProtocol {
    private static let lock = NSLock()
    private static var recorded: [URLRequest] = []
    private static var responder: ((URLRequest) -> (Int, String))?

    static var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    static func respond(_ responder: @escaping (URLRequest) -> (Int, String)) {
        lock.lock(); self.responder = responder; lock.unlock()
    }

    static func reset() {
        lock.lock(); recorded = []; responder = nil; lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.recorded.append(request)
        let responder = Self.responder
        Self.lock.unlock()
        let (status, body) = responder?(request) ?? (404, "{}")
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
