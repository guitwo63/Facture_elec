import XCTest
import FacturXCore
@testable import FacturXMacApp

/// Les vraies synchronisations périodiques face à un SUPER PDP en panne : une panne écrit une
/// entrée d'audit à son début et une à son retour à la normale, plus une par cycle et par
/// facture. En production, ces erreurs répétées avaient réduit le journal (500 entrées) à 4 jours.
///
/// Rien ne sort de la machine : SUPER PDP est simulé en mémoire (`SyncOutageFakeSuperPDP`, hôte
/// `superpdp-panne.invalid`). Sous XCTest, les stores lisent une suite UserDefaults propre à ce
/// processus (`AppPersistence`).
@MainActor
final class SyncFailureJournalingTests: XCTestCase {
    private var audit: AuditStore!
    private let credentials = SuperPDPCredentials(clientID: "client-de-test", clientSecret: "secret-de-test",
                                                  apiBaseURL: SyncOutageFakeSuperPDP.baseURL, usePDP: true)
    private var incidentsKey: String { AppEnvironment.shared.key("facturx.syncincidents.v1") }

    override func setUp() async throws {
        try await super.setUp()
        guard AppPersistence.keychainService.hasPrefix("fr.arverneo.facturxmacapp.tests.") else {
            throw NSError(domain: "SyncFailureJournalingTests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Stockage de test non isolé : aucun store n'est touché."
            ])
        }
        URLProtocol.registerClass(SyncOutageFakeSuperPDP.self)
        SyncOutageFakeSuperPDP.mode = .offline
        AppPersistence.defaults.removeObject(forKey: incidentsKey)
        InvoiceStore.shared.invoices = []
        PurchaseInvoiceStore.shared.invoices = []
        audit = AuditStore()
        audit.clear()
    }

    override func tearDown() async throws {
        InvoiceStore.shared.audit = nil
        PurchaseInvoiceStore.shared.audit = nil
        InvoiceStore.shared.invoices = []
        PurchaseInvoiceStore.shared.invoices = []
        AppPersistence.defaults.removeObject(forKey: incidentsKey)
        audit.clear()
        URLProtocol.unregisterClass(SyncOutageFakeSuperPDP.self)
        try await super.tearDown()
    }

    // MARK: - Statuts des factures de vente

    func testNetworkOutageOfStatusSyncIsJournaledOnceThenItsRecovery() async {
        makeInvoice(number: "PANNE-1", remoteID: "7101")
        makeInvoice(number: "PANNE-2", remoteID: "7102")
        InvoiceStore.shared.audit = audit
        let engine = PDPPeriodicSyncEngine()

        for _ in 0..<3 { await syncStatuses(engine) }

        XCTAssertEqual(audit.entries.map(\.action), ["pdp_status_error"],
                       "trois cycles sans réseau, deux factures suivies : une seule entrée")
        XCTAssertNil(audit.entries.first?.objectCode)
        XCTAssertTrue(audit.entries.first?.details.contains("(factures ") == true, audit.entries.first?.details ?? "")
        let summary = engine.lastRunSummary ?? ""
        XCTAssertTrue(summary.hasPrefix("2 facture(s) interrogée(s), 0 mise(s) à jour, 2 échec(s). Erreur : "), summary)

        SyncOutageFakeSuperPDP.mode = .online
        await syncStatuses(engine)
        await syncStatuses(engine)

        XCTAssertEqual(audit.entries.map(\.action), ["pdp_status_recovered", "pdp_status_error"])
        XCTAssertTrue(audit.entries.first?.details.contains("rétablie après 3 échecs") == true, audit.entries.first?.details ?? "")
        XCTAssertEqual(engine.lastRunSummary, "2 facture(s) interrogée(s), 0 mise(s) à jour.")
    }

    func testInvoiceUnknownToSuperPDPIsJournaledOnceForThatInvoice() async {
        makeInvoice(number: "PANNE-1", remoteID: "7101")
        makeInvoice(number: "PANNE-2", remoteID: "7102")
        InvoiceStore.shared.audit = audit
        let engine = PDPPeriodicSyncEngine()

        SyncOutageFakeSuperPDP.mode = .unknownInvoice("7101")
        for _ in 0..<3 { await syncStatuses(engine) }

        XCTAssertEqual(audit.entries.map(\.action), ["pdp_status_error"],
                       "l'autre facture répond à chaque cycle : la panne de PANNE-1 ne se referme pas pour autant")
        XCTAssertEqual(audit.entries.first?.objectCode, "PANNE-1")
        XCTAssertTrue(audit.entries.first?.details.contains("HTTP 404") == true, audit.entries.first?.details ?? "")
    }

    // MARK: - Réception des factures d'achat

    func testReceptionFailureIsJournaledOnceAndShownInTheConnectionPanel() async {
        PurchaseInvoiceStore.shared.audit = audit
        let engine = PurchasePDPReceptionEngine()

        SyncOutageFakeSuperPDP.mode = .listRejected
        for _ in 0..<3 { await receivePurchases(engine) }

        XCTAssertEqual(audit.entries.map(\.action), ["purchase_invoice_list_error"],
                       "trois cycles refusés : une seule entrée")
        // Affiché dans « État des connexions » : l'échec y passait pour « Aucune nouvelle facture reçue. »
        let summary = engine.lastRunSummary ?? ""
        XCTAssertTrue(summary.hasPrefix("Réception en échec. Erreur : Erreur HTTP 400"), summary)

        SyncOutageFakeSuperPDP.mode = .online
        await receivePurchases(engine)

        XCTAssertEqual(audit.entries.map(\.action), ["purchase_invoice_list_recovered", "purchase_invoice_list_error"])
        XCTAssertTrue(audit.entries.first?.details.contains("rétablie après 3 échecs") == true, audit.entries.first?.details ?? "")
        XCTAssertEqual(engine.lastRunSummary, "Aucune nouvelle facture reçue.")
    }

    // MARK: - Outils

    private func syncStatuses(_ engine: PDPPeriodicSyncEngine) async {
        await engine.runOnce(store: InvoiceStore.shared, credentialsProvider: { _ in self.credentials })
    }

    private func receivePurchases(_ engine: PurchasePDPReceptionEngine) async {
        await engine.runOnce(store: PurchaseInvoiceStore.shared, defaultCredentials: credentials, credentialsBySociety: [:])
    }

    /// Facture déposée sur SUPER PDP et pas encore à un statut terminal : la synchro l'interroge.
    private func makeInvoice(number: String, remoteID: String) {
        var invoice = Invoice(number: number,
                              seller: InvoiceParty(name: "Vendeur", street: "1 rue A", postcode: "75001", city: "Paris"),
                              buyer: InvoiceParty(name: "Client", street: "2 rue B", postcode: "69001", city: "Lyon"),
                              lines: [InvoiceLine(name: "Article", quantity: 1, unitPrice: 100, vatRate: 20)])
        invoice.status = .sent
        invoice.superPDPRemoteID = remoteID
        InvoiceStore.shared.upsert(invoice)
    }
}

/// Faux SUPER PDP en mémoire, sur l'hôte réservé `superpdp-panne.invalid` (jamais résolu), celui
/// des identifiants de test.
private final class SyncOutageFakeSuperPDP: URLProtocol {
    enum Mode {
        /// Pas de réseau : chaque requête échoue avant d'atteindre SUPER PDP.
        case offline
        /// Tout répond ; aucune facture reçue, statut sans effet (« pending »).
        case online
        /// La liste des factures reçues est refusée (HTTP 400).
        case listRejected
        /// Cette facture est inconnue de SUPER PDP (HTTP 404) ; le reste répond.
        case unknownInvoice(String)
    }

    static let host = "superpdp-panne.invalid"
    static let baseURL = "https://superpdp-panne.invalid"
    private static let lock = NSLock()
    private static var currentMode = Mode.offline

    static var mode: Mode {
        get { lock.lock(); defer { lock.unlock() }; return currentMode }
        set { lock.lock(); currentMode = newValue; lock.unlock() }
    }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == host }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let mode = Self.mode
        if case .offline = mode {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let path = request.url?.path ?? ""
        let status: Int
        let payload: String
        switch (request.httpMethod ?? "GET", path) {
        case (_, "/oauth2/token"):
            status = 200
            payload = #"{"access_token":"jeton-de-test","token_type":"Bearer","expires_in":3600}"#
        case ("GET", "/v1.beta/invoices"):
            if case .listRejected = mode {
                status = 400
                payload = #"{"detail":"direction: value must be one of in, out"}"#
            } else {
                status = 200
                payload = #"{"data":[],"count":0,"has_after":false,"has_before":false}"#
            }
        case ("GET", _) where path.hasPrefix("/v1.beta/invoices/"):
            if case .unknownInvoice(let remoteID) = mode, path == "/v1.beta/invoices/\(remoteID)" {
                status = 404
                payload = #"{"detail":"invoice not found"}"#
            } else {
                status = 200
                payload = #"{"status":"pending"}"#
            }
        default:
            status = 404
            payload = "{}"
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(payload.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
