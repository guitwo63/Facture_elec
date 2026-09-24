import XCTest
import SwiftUI
import AppKit
import Network
import Vision
import FacturXCore
@testable import FacturXMacApp

/// Un statut posé par le programme (reçu de SUPER PDP, restauration d'une sauvegarde) ne repart
/// jamais vers SUPER PDP et ne déclenche pas l'alerte email ; seul un choix de l'utilisateur part.
///
/// Les vrais éditeurs de l'app sont affichés dans une fenêtre hors écran. Rien ne sort de la
/// machine : SUPER PDP est simulé en mémoire (`StatusEchoFakeSuperPDP`, hôte `superpdp.invalid`)
/// et le serveur SMTP écoute sur 127.0.0.1 (`StatusEchoFakeSMTPServer`). Sous XCTest, les stores
/// lisent une suite UserDefaults et un service Trousseau propres à ce processus (`AppPersistence`).
@MainActor
final class StatusEchoTests: XCTestCase {
    private var window: NSWindow?
    private var smtp: StatusEchoFakeSMTPServer?

    override func setUp() async throws {
        try await super.setUp()
        guard AppPersistence.keychainService.hasPrefix("fr.arverneo.facturxmacapp.tests.") else {
            throw NSError(domain: "StatusEchoTests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Stockage de test non isolé : aucun store n'est touché."
            ])
        }
        URLProtocol.registerClass(StatusEchoFakeSuperPDP.self)
        StatusEchoFakeSuperPDP.reset()
        SuperPDPSettings.shared.credentials = SuperPDPCredentials(
            clientID: "client-de-test", clientSecret: "secret-de-test",
            apiBaseURL: StatusEchoFakeSuperPDP.baseURL, usePDP: true
        )
        SuperPDPSettings.shared.credentialsBySociety = [:]

        let server = try StatusEchoFakeSMTPServer()
        smtp = server
        SMTPSettings.shared.credentials = SMTPCredentials(
            host: "127.0.0.1", port: server.port, fromAddress: "alertes@facturx.invalid",
            useTLS: false, alertsEnabled: true, alertOnInvoiceStatusChange: true
        )
        SMTPSettings.shared.credentialsBySociety = [:]

        InvoiceStore.shared.invoices = []
        PurchaseInvoiceStore.shared.invoices = []
        // Destinataire de l'alerte, et rôle comptable pour les transitions d'achat.
        AuthStore.shared.currentUser = AuthStore.shared.users.first(where: { $0.isAdmin })
        XCTAssertNotNil(AuthStore.shared.currentUser)
    }

    override func tearDown() async throws {
        if let w = window {
            w.sheets.forEach { w.endSheet($0) }
            w.contentView = nil
            w.close()
        }
        window = nil
        smtp?.stop()
        smtp = nil
        AuthStore.shared.currentUser = nil
        InvoiceStore.shared.invoices = []
        PurchaseInvoiceStore.shared.invoices = []
        SuperPDPSettings.shared.credentials = SuperPDPCredentials(clientID: "", clientSecret: "")
        SMTPSettings.shared.credentials = SMTPCredentials()
        URLProtocol.unregisterClass(StatusEchoFakeSuperPDP.self)
        try await super.tearDown()
    }

    // MARK: - Ventes

    func testStatusReceivedByPeriodicSyncIsNotSentBackNorAlerted() {
        let invoice = makeInvoice(number: "ECHO-SYNC", remoteID: "4201")
        showInvoiceEditor(invoice)

        StatusEchoFakeSuperPDP.remoteStatus = "fr:205"
        var done = false
        Task { @MainActor in
            await PDPPeriodicSyncEngine().runOnce(store: InvoiceStore.shared,
                                                  credentialsProvider: { SuperPDPSettings.shared.credentials(for: $0) })
            done = true
        }
        spin(until: { done })
        spin(for: 1.5)

        XCTAssertEqual(InvoiceStore.shared.invoices.first(where: { $0.id == invoice.id })?.status, .accepted,
                       "la synchronisation doit appliquer le statut reçu")
        XCTAssertEqual(StatusEchoFakeSuperPDP.statusEventsSent, [],
                       "un statut reçu de SUPER PDP ne doit pas lui être renvoyé")
        XCTAssertEqual(smtp?.subjects ?? [], [], "un statut reçu ne déclenche pas l'alerte email")
    }

    func testStatusReceivedByRefreshButtonIsNotSentBackNorAlerted() throws {
        let invoice = makeInvoice(number: "ECHO-REFRESH", remoteID: "4202")
        showInvoiceEditor(invoice)

        StatusEchoFakeSuperPDP.remoteStatus = "fr:205"
        // Le bouton de rafraîchissement (icône seule) suit le numéro, la date, le montant et le
        // statut sur la ligne d'en-tête : on clique de gauche à droite jusqu'à ce qu'il réponde.
        let start = try XCTUnwrap(textFrame(containing: "en cours") ?? textFrame(containing: "ECHO-REFRESH"),
                                  "ligne d'en-tête introuvable à l'écran")
        var x = start.maxX + 2
        while x < start.maxX + 900, !StatusEchoFakeSuperPDP.statusWasQueried(remoteID: "4202") {
            click(at: NSPoint(x: x, y: start.midY))
            x += 4
        }
        XCTAssertTrue(StatusEchoFakeSuperPDP.statusWasQueried(remoteID: "4202"), "bouton de rafraîchissement introuvable")
        spin(until: { InvoiceStore.shared.invoices.first(where: { $0.id == invoice.id })?.status == .accepted })
        spin(for: 1.5)

        XCTAssertEqual(InvoiceStore.shared.invoices.first(where: { $0.id == invoice.id })?.status, .accepted,
                       "le rafraîchissement doit appliquer le statut reçu")
        XCTAssertEqual(StatusEchoFakeSuperPDP.statusEventsSent, [],
                       "un statut reçu de SUPER PDP ne doit pas lui être renvoyé")
        XCTAssertEqual(smtp?.subjects ?? [], [], "un statut reçu ne déclenche pas l'alerte email")
    }

    func testStatusChosenByUserIsSentAndAlerted() throws {
        let invoice = makeInvoice(number: "ECHO-USER", remoteID: "4203")
        showInvoiceEditor(invoice)

        let button = try XCTUnwrap(textFrame(containing: InvoiceStatus.accepted.label), "bouton « Acceptée » introuvable")
        click(at: NSPoint(x: button.midX, y: button.midY))
        spin(until: { !StatusEchoFakeSuperPDP.statusEventsSent.isEmpty && !(self.smtp?.subjects.isEmpty ?? true) })
        spin(for: 0.5)

        XCTAssertEqual(InvoiceStore.shared.invoices.first(where: { $0.id == invoice.id })?.status, .accepted)
        XCTAssertEqual(StatusEchoFakeSuperPDP.statusEventsSent, ["4203 fr:205"],
                       "le statut choisi par l'utilisateur part vers SUPER PDP, une seule fois")
        XCTAssertEqual(smtp?.subjects ?? [], ["Facture ECHO-USER — Acceptée"])
    }

    // MARK: - Achats

    func testRestoredPurchaseStatusIsNotSentToSupplier() {
        let record = makePurchase(number: "FOURN-RESTORE", remoteID: "5201", status: .toValidate)
        showPurchaseEditor(record)

        // Sauvegarde restaurée (Réglages, feuille au-dessus de la fenêtre) pendant que la
        // facture d'achat est ouverte : elle y est « Validée ».
        var restored = record
        restored.status = .validated
        BackupService.restore(BackupBundle(invoices: [], orders: [], parties: [], purchaseInvoices: [restored]),
                              invoiceStore: InvoiceStore.shared, orderStore: OrderStore.shared,
                              quoteStore: QuoteStore.shared, directory: PartyDirectory.shared,
                              purchaseInvoiceStore: PurchaseInvoiceStore.shared)
        spin(for: 1.5)

        XCTAssertEqual(PurchaseInvoiceStore.shared.invoices.first(where: { $0.id == record.id })?.status, .validated)
        XCTAssertEqual(StatusEchoFakeSuperPDP.statusEventsSent, [],
                       "un statut restauré ne doit pas partir vers le fournisseur")
    }

    func testPurchaseStatusChosenByUserIsSentToSupplier() throws {
        let record = makePurchase(number: "FOURN-USER", remoteID: "5202", status: .toValidate)
        showPurchaseEditor(record)

        let button = try XCTUnwrap(textFrame(containing: PurchaseInvoiceStatus.validated.label), "bouton « Validée » introuvable")
        click(at: NSPoint(x: button.midX, y: button.midY))
        spin(until: { !StatusEchoFakeSuperPDP.statusEventsSent.isEmpty })
        spin(for: 0.5)

        XCTAssertEqual(PurchaseInvoiceStore.shared.invoices.first(where: { $0.id == record.id })?.status, .validated)
        XCTAssertEqual(StatusEchoFakeSuperPDP.statusEventsSent, ["5202 fr:205"],
                       "le statut choisi par le comptable part vers le fournisseur, une seule fois")
    }

    // MARK: - Documents

    private func makeInvoice(number: String, remoteID: String) -> Invoice {
        var invoice = Invoice(number: number,
                              seller: InvoiceParty(name: "Vendeur", street: "1 rue A", postcode: "75001", city: "Paris"),
                              buyer: InvoiceParty(name: "Client", street: "2 rue B", postcode: "69001", city: "Lyon"),
                              lines: [InvoiceLine(name: "Article", quantity: 1, unitPrice: 100, vatRate: 20)])
        invoice.status = .sent
        invoice.dueDate = Date().addingTimeInterval(30 * 86_400)
        invoice.superPDPRemoteID = remoteID
        InvoiceStore.shared.upsert(invoice)
        return invoice
    }

    private func makePurchase(number: String, remoteID: String, status: PurchaseInvoiceStatus) -> PurchaseInvoice {
        var invoice = Invoice(number: number,
                              seller: InvoiceParty(name: "Fournisseur", street: "3 rue C", postcode: "33000", city: "Bordeaux"),
                              buyer: InvoiceParty(name: "Nous", street: "1 rue A", postcode: "75001", city: "Paris"),
                              lines: [InvoiceLine(name: "Fourniture", quantity: 1, unitPrice: 50, vatRate: 20)])
        invoice.superPDPRemoteID = remoteID
        let record = PurchaseInvoice(invoice: invoice, status: status)
        PurchaseInvoiceStore.shared.upsert(record)
        return record
    }

    // MARK: - Affichage hors écran

    /// Même montage que `InvoicesTabView` : `Binding(get:set:)` sur le store, `.id` dans un VStack.
    private func showInvoiceEditor(_ invoice: Invoice) {
        let store = InvoiceStore.shared
        let binding = Binding<Invoice>(
            get: { store.invoices.first(where: { $0.id == invoice.id }) ?? invoice },
            set: { store.upsert($0) }
        )
        host(VStack(spacing: 0) { InvoiceEditorView(invoice: binding).id(invoice.id) })
    }

    /// Même montage que `PurchasesTabView`.
    private func showPurchaseEditor(_ record: PurchaseInvoice) {
        let store = PurchaseInvoiceStore.shared
        let binding = Binding<PurchaseInvoice>(
            get: { store.invoices.first(where: { $0.id == record.id }) ?? record },
            set: { store.upsert($0) }
        )
        host(VStack(spacing: 0) { PurchaseInvoiceEditorView(record: binding).id(record.id) })
    }

    private func host<V: View>(_ view: V) {
        _ = NSApplication.shared
        let w = StatusEchoWindow(contentRect: NSRect(x: -5000, y: -5000, width: 1400, height: 900),
                                 styleMask: [.borderless], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.appearance = NSAppearance(named: .aqua)
        w.contentView = NSHostingView(rootView: view
            .environmentObject(InvoiceStore.shared)
            .environmentObject(OrderStore.shared)
            .environmentObject(QuoteStore.shared)
            .environmentObject(QuoteStatusStore.shared)
            .environmentObject(PartyDirectory.shared)
            .environmentObject(ChorusProSettings.shared)
            .environmentObject(SuperPDPSettings.shared)
            .environmentObject(SMTPSettings.shared)
            .environmentObject(EmailTemplateStore.shared)
            .environmentObject(TwoFactorSettings.shared)
            .environmentObject(PCloudSettings.shared)
            .environmentObject(ModuleStore.shared)
            .environmentObject(BackupStrategyStore.shared)
            .environmentObject(TagStore.shared)
            .environmentObject(KindColorStore.shared)
            .environmentObject(OrderStatusStore.shared)
            .environmentObject(InvoiceStatusStore.shared)
            .environmentObject(PaymentTermsPresetStore.shared)
            .environmentObject(AuditActionLabelStore.shared)
            .environmentObject(SuperPDPStatusCodeStore.shared)
            .environmentObject(PurchaseInvoiceStore.shared)
            .environmentObject(PurchaseInvoiceStatusStore.shared)
            .environmentObject(AuthStore.shared)
            .environmentObject(AppEnvironment.shared)
        )
        w.makeKeyAndOrderFront(nil)
        window = w
        spin(for: 0.8)
    }

    private func spin(for seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func spin(until condition: () -> Bool, timeout: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }

    /// Clic gauche au point donné (coordonnées de la fenêtre, origine en bas à gauche).
    private func click(at point: NSPoint) {
        guard let w = window else { return }
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                                 timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: w.windowNumber, context: nil, eventNumber: 0,
                                                 clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) else { continue }
            w.sendEvent(event)
            spin(for: 0.02)
        }
        spin(for: 0.05)
    }

    /// Cadre, en coordonnées de la fenêtre, du premier texte affiché qui contient `text` (lu par
    /// OCR sur le rendu de la fenêtre : l'arbre d'accessibilité de SwiftUI reste vide hors écran).
    private func textFrame(containing text: String) -> CGRect? {
        guard let view = window?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let image = rep.cgImage else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["fr-FR"]
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: image).perform([request])
        let size = view.bounds.size
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first, candidate.string.contains(text) else { continue }
            let box = (try? candidate.boundingBox(for: candidate.string.range(of: text)!))?.boundingBox ?? observation.boundingBox
            return CGRect(x: box.minX * size.width, y: box.minY * size.height,
                          width: box.width * size.width, height: box.height * size.height)
        }
        return nil
    }
}

/// Fenêtre sans bordure qui peut devenir clé, pour recevoir les clics simulés.
private final class StatusEchoWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// Faux SUPER PDP en mémoire : n'intercepte que l'hôte `superpdp.invalid` (domaine réservé, jamais
/// résolu), celui des identifiants de test.
private final class StatusEchoFakeSuperPDP: URLProtocol {
    static let host = "superpdp.invalid"
    static let baseURL = "https://superpdp.invalid"
    static var remoteStatus = "fr:205"
    private static let lock = NSLock()
    private static var requests: [(method: String, path: String, body: Data)] = []

    static func reset() {
        lock.lock(); requests = []; lock.unlock()
    }

    /// Événements de statut envoyés (`POST /v1.beta/invoice_events`), « <id distant> <code> ».
    static var statusEventsSent: [String] {
        lock.lock(); defer { lock.unlock() }
        return requests.filter { $0.method == "POST" && $0.path == "/v1.beta/invoice_events" }.map { request in
            let json = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:]
            return "\(json["invoice_id"].map { "\($0)" } ?? "?") \(json["status_code"] as? String ?? "?")"
        }
    }

    static func statusWasQueried(remoteID: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return requests.contains { $0.method == "GET" && $0.path == "/v1.beta/invoices/\(remoteID)" }
    }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == host }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? ""
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(buffer, count: count)
            }
            stream.close()
        }
        Self.lock.lock(); Self.requests.append((method, path, body)); Self.lock.unlock()

        let status: Int
        let payload: String
        switch (method, path) {
        case (_, "/oauth2/token"):
            status = 200
            payload = #"{"access_token":"jeton-de-test","token_type":"Bearer","expires_in":3600}"#
        case ("GET", "/v1.beta/invoice_events"):
            status = 200
            payload = #"{"data":[]}"#
        case ("POST", "/v1.beta/invoice_events"):
            // Réponse de SUPER PDP aux échos « Acceptée » relevés en production.
            status = 400
            payload = #"{"detail":"Statut non pris en charge"}"#
        case ("GET", _) where path.hasPrefix("/v1.beta/invoices/"):
            status = 200
            payload = #"{"status":"\#(Self.remoteStatus)"}"#
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

/// Serveur SMTP minimal sur 127.0.0.1 (port libre), sans TLS : accepte tout et garde le sujet de
/// chaque message reçu.
private final class StatusEchoFakeSMTPServer {
    private(set) var port = 0
    private let listener: NWListener
    private let queue = DispatchQueue(label: "StatusEchoFakeSMTPServer")
    private let lock = NSLock()
    private var receivedSubjects: [String] = []

    var subjects: [String] {
        lock.lock(); defer { lock.unlock() }
        return receivedSubjects
    }

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.signal() }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success, let port = listener.port?.rawValue else {
            listener.cancel()
            throw NSError(domain: "StatusEchoFakeSMTPServer", code: 1)
        }
        self.port = Int(port)
    }

    func stop() {
        listener.cancel()
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        var buffer = Data()
        var inData = false
        var message: [String] = []
        func reply(_ line: String) {
            connection.send(content: Data((line + "\r\n").utf8), completion: .contentProcessed { _ in })
        }
        func receive() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
                guard let self else { return }
                if let data { buffer.append(data) }
                while let range = buffer.firstRange(of: Data([0x0D, 0x0A])) {
                    let line = String(decoding: buffer[..<range.lowerBound], as: UTF8.self)
                    buffer.removeSubrange(..<range.upperBound)
                    if inData {
                        if line == "." {
                            inData = false
                            let subject = message.first(where: { $0.hasPrefix("Subject: ") }).map { String($0.dropFirst(9)) } ?? ""
                            self.lock.lock(); self.receivedSubjects.append(subject); self.lock.unlock()
                            message = []
                            reply("250 message reçu")
                        } else {
                            message.append(line)
                        }
                    } else if line.uppercased().hasPrefix("DATA") {
                        inData = true
                        reply("354 suite")
                    } else if line.uppercased().hasPrefix("QUIT") {
                        reply("221 au revoir")
                        connection.cancel()
                        return
                    } else {
                        reply("250 ok")
                    }
                }
                if isComplete || error != nil {
                    connection.cancel()
                } else {
                    receive()
                }
            }
        }
        reply("220 faux serveur SMTP")
        receive()
    }
}
