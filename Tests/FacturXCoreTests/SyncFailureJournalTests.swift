import XCTest
@testable import FacturXCore

/// Une panne d'une synchronisation SUPER PDP n'écrit que deux entrées d'audit : au premier échec
/// et au retour à la normale. En production, une entrée par échec et par facture, toutes les
/// 15 minutes, avait réduit le journal (500 entrées) à 4 jours, dont 449 erreurs de synchro.
final class SyncFailureJournalTests: XCTestCase {
    private var journal: SyncFailureJournal!
    private var audit: AuditStore!
    /// 23/09/2026 à 23:10, heure de Paris.
    private var clock = ISO8601DateFormatter().date(from: "2026-09-23T21:10:00Z")!
    private let account = UUID()
    private let a = SyncTarget(id: "A", code: "FA-0001")
    private let b = SyncTarget(id: "B", code: "FA-0002")
    private let offline = URLError(.notConnectedToInternet)
    private let notFound = SuperPDPError.http(status: 404, body: #"{"detail":"invoice not found"}"#)

    private var storageKey: String { AppEnvironment.shared.key("facturx.syncincidents.v1") }

    override func setUp() {
        super.setUp()
        AppPersistence.defaults.removeObject(forKey: storageKey)
        audit = AuditStore()
        audit.clear()
        journal = makeJournal()
    }

    override func tearDown() {
        AppPersistence.defaults.removeObject(forKey: storageKey)
        audit.clear()
        super.tearDown()
    }

    // MARK: - Statuts des factures de vente

    func testNetworkOutageIsJournaledOnceForTheWholeAccount() throws {
        for _ in 0..<3 { statusCycle([(a, offline), (b, offline)]) }

        XCTAssertEqual(audit.entries.count, 1, "trois cycles sans réseau, deux factures suivies : une seule entrée")
        let entry = try XCTUnwrap(audit.entries.first)
        XCTAssertEqual(entry.action, "pdp_status_error")
        XCTAssertEqual(entry.actor, "system")
        XCTAssertEqual(entry.companyID, account)
        XCTAssertNil(entry.objectCode, "une panne du compte ne relève d'aucune facture")
        XCTAssertTrue(entry.details.contains(offline.localizedDescription), entry.details)
        XCTAssertTrue(entry.details.contains("(factures FA-0001, FA-0002)"), entry.details)
    }

    func testRecoveryIsJournaledOnceWithFailureCountAndStart() throws {
        inAppTimeZone("Europe/Paris") {
            for _ in 0..<3 { statusCycle([(a, offline), (b, offline)]) }
            statusCycle([(a, nil), (b, nil)])
            statusCycle([(a, nil), (b, nil)])
        }

        XCTAssertEqual(audit.entries.map(\.action), ["pdp_status_recovered", "pdp_status_error"])
        let recovery = try XCTUnwrap(audit.entries.first)
        XCTAssertNil(recovery.objectCode)
        XCTAssertEqual(recovery.companyID, account)
        XCTAssertEqual(recovery.details,
                       "Synchronisation périodique rétablie après 3 échecs, en échec depuis le 23/09/2026 à 23:10.")
        XCTAssertTrue(journal.incidents.isEmpty)
    }

    func testSuccessWithoutOpenIncidentWritesNothing() {
        statusCycle([(a, nil), (b, nil)])

        XCTAssertTrue(audit.entries.isEmpty)
        XCTAssertNil(AppPersistence.defaults.object(forKey: storageKey),
                     "tant que tout va bien, rien n'est écrit dans les préférences")
    }

    func testInvoiceSpecificFailureIsJournaledOnceWithoutFlapping() throws {
        // FA-0002 répond à chaque cycle : cela ne referme pas la panne propre à FA-0001.
        for _ in 0..<3 { statusCycle([(a, notFound), (b, nil)]) }

        XCTAssertEqual(audit.entries.count, 1)
        let failure = try XCTUnwrap(audit.entries.first)
        XCTAssertEqual(failure.action, "pdp_status_error")
        XCTAssertEqual(failure.objectCode, "FA-0001")
        XCTAssertEqual(failure.target, "FA-0001")
        XCTAssertTrue(failure.details.contains("HTTP 404"), failure.details)

        statusCycle([(a, nil), (b, nil)])
        XCTAssertEqual(audit.entries.map(\.action), ["pdp_status_recovered", "pdp_status_error"])
        XCTAssertEqual(audit.entries.first?.objectCode, "FA-0001")
        XCTAssertTrue(audit.entries[0].details.contains("après 3 échecs"), audit.entries[0].details)
        XCTAssertEqual(audit.entries(forInvoice: "FA-0001").count, 2, "les deux entrées figurent dans le journal de la facture")
        XCTAssertTrue(audit.entries(forInvoice: "FA-0002").isEmpty)
    }

    func testServerErrorOnOneInvoiceDoesNotFlapTheAccount() {
        // Une erreur 5xx vaut pour le compte, même si une autre facture répond dans le même cycle.
        let unavailable = SuperPDPError.http(status: 503, body: "Service Unavailable")
        for _ in 0..<3 { statusCycle([(a, unavailable), (b, nil)]) }
        statusCycle([(a, nil), (b, nil)])

        XCTAssertEqual(audit.entries.map(\.action), ["pdp_status_recovered", "pdp_status_error"])
        XCTAssertTrue(audit.entries[1].details.contains("(factures FA-0001)"), audit.entries[1].details)
    }

    func testNetworkOutageLeavesAnInvoiceIncidentOpen() {
        statusCycle([(a, notFound), (b, nil)])
        statusCycle([(a, offline), (b, offline)])
        statusCycle([(a, notFound), (b, nil)])

        XCTAssertEqual(audit.entries.map(\.action), ["pdp_status_recovered", "pdp_status_error", "pdp_status_error"])
        XCTAssertNil(audit.entries[0].objectCode, "le retour du réseau est celui du compte")
        XCTAssertTrue(audit.entries[0].details.contains("après 1 échec,"), audit.entries[0].details)
        XCTAssertEqual(audit.entries[2].objectCode, "FA-0001")
        XCTAssertEqual(Array(journal.incidents.keys), ["salesStatus|\(account.uuidString)|A"],
                       "la facture inconnue de SUPER PDP reste en panne")
    }

    func testNewCauseIsJournaledButNotANewMessageOfTheSameCause() {
        statusCycle([(a, offline)])
        statusCycle([(a, URLError(.timedOut))])
        statusCycle([(a, SuperPDPError.http(status: 401, body: "invalid_client"))])
        statusCycle([(a, SuperPDPError.http(status: 401, body: "invalid_client"))])

        XCTAssertEqual(audit.entries.count, 2, "réseau puis identifiants refusés : deux entrées")
        XCTAssertTrue(audit.entries[0].details.hasPrefix("Synchronisation périodique toujours en échec, autre cause : Erreur HTTP 401"),
                      audit.entries[0].details)

        statusCycle([(a, nil)])
        XCTAssertTrue(audit.entries[0].details.contains("après 4 échecs"), audit.entries[0].details)
    }

    func testOpenIncidentSurvivesARestart() {
        statusCycle([(a, offline)])
        journal = makeJournal()
        statusCycle([(a, offline)])

        XCTAssertEqual(audit.entries.count, 1, "relancer l'app ne rejournalise pas la panne en cours")

        journal = makeJournal()
        statusCycle([(a, nil)])
        XCTAssertEqual(audit.entries.first?.action, "pdp_status_recovered")
        XCTAssertTrue(audit.entries[0].details.contains("après 2 échecs"), audit.entries[0].details)
    }

    func testCancellationIsNeitherAFailureNorASuccess() {
        statusCycle([(a, URLError(.cancelled)), (b, CancellationError())])
        XCTAssertTrue(audit.entries.isEmpty)
        XCTAssertTrue(journal.incidents.isEmpty)

        statusCycle([(a, offline)])
        statusCycle([(a, URLError(.cancelled))])
        XCTAssertEqual(audit.entries.count, 1)
        XCTAssertEqual(journal.incidents.count, 1, "un arrêt du moteur ne referme pas la panne")
    }

    func testIncidentOfAnInvoiceNoLongerFollowedIsForgottenSilently() {
        statusCycle([(a, notFound), (b, nil)])
        // FA-0001 est payée entre-temps : elle n'est plus interrogée.
        statusCycle([(b, nil)])

        XCTAssertEqual(audit.entries.count, 1)
        XCTAssertTrue(journal.incidents.isEmpty)
    }

    func testAccountsNotQueriedAreForgottenSilently() {
        statusCycle([(a, offline)])
        journal.forgetAccounts(of: .salesStatus, except: [nil])
        XCTAssertTrue(journal.incidents.isEmpty, "PDP désactivé ou plus rien à suivre pour ce compte")
        XCTAssertEqual(audit.entries.count, 1)

        statusCycle([(a, offline)])
        journal.forgetAccounts(of: .salesStatus, except: [account])
        journal.forgetAccounts(of: .purchaseReception, except: [])
        XCTAssertEqual(journal.incidents.count, 1, "le compte interrogé garde sa panne, l'autre synchro n'y touche pas")
    }

    func testMessageEndingWithAPeriodKeepsASingleOne() throws {
        // Message réel de macOS hors ligne (URLError avec son libellé).
        let offlineAsMacOSSaysIt = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet,
                                           userInfo: [NSLocalizedDescriptionKey: "La connexion Internet semble être désactivée."])
        statusCycle([(a, offlineAsMacOSSaysIt)])

        XCTAssertEqual(audit.entries.first?.details,
                       "Synchronisation périodique échouée : La connexion Internet semble être désactivée (factures FA-0001). Échecs suivants non répétés jusqu'au retour à la normale.")
        XCTAssertEqual(journal.incidents.values.first?.category, "réseau")
    }

    func testAffectedInvoicesAreCappedAtFive() throws {
        let targets = (1...7).map { SyncTarget(id: "\($0)", code: "FA-000\($0)") }
        statusCycle(targets.map { ($0, offline) })

        let details = try XCTUnwrap(audit.entries.first?.details)
        XCTAssertTrue(details.contains("(factures FA-0001, FA-0002, FA-0003, FA-0004, FA-0005…)"), details)
    }

    // MARK: - Réception des factures d'achat

    func testReceptionListFailureIsJournaledOnceAndRecovers() {
        let badRequest = SuperPDPError.http(status: 400, body: #"{"detail":"direction: invalid value"}"#)
        for _ in 0..<3 { receptionCycle(listError: badRequest) }

        XCTAssertEqual(audit.entries.map(\.action), ["purchase_invoice_list_error"])
        XCTAssertEqual(audit.entries[0].objectType, .purchaseInvoice)
        XCTAssertNil(audit.entries[0].companyID, "compte par défaut")
        XCTAssertTrue(audit.entries[0].details.hasPrefix("Échec de la réception des factures d'achat sur SUPER PDP : Erreur HTTP 400"),
                      audit.entries[0].details)

        receptionCycle(listError: nil)
        XCTAssertEqual(audit.entries.map(\.action), ["purchase_invoice_list_recovered", "purchase_invoice_list_error"])
        XCTAssertTrue(audit.entries[0].details.hasPrefix("Réception des factures d'achat rétablie après 3 échecs"),
                      audit.entries[0].details)
    }

    func testImportFailureIsJournaledOncePerSubmissionAndClosedByItsImport() {
        let received = SyncTarget(id: "635790", code: "635790")
        let unreadable = SuperPDPError.decoding("XML illisible")
        for _ in 0..<3 { receptionCycle(listError: nil, imports: [(received, unreadable)]) }

        XCTAssertEqual(audit.entries.map(\.action), ["purchase_invoice_receive_error"])
        XCTAssertEqual(audit.entries[0].objectCode, "635790")
        XCTAssertTrue(audit.entries[0].details.hasPrefix("Échec import facture d'achat (id distant 635790)"),
                      audit.entries[0].details)

        receptionCycle(listError: nil, imports: [(received, nil)])
        XCTAssertEqual(audit.entries.count, 1, "l'import (« Facture d'achat reçue par PDP ») tient lieu de retour à la normale")
        XCTAssertTrue(journal.incidents.isEmpty)
    }

    func testReceptionAndStatusIncidentsAreSeparate() {
        statusCycle([(a, offline)])
        receptionCycle(listError: offline, companyID: account)
        statusCycle([(a, nil)])

        XCTAssertEqual(audit.entries.map(\.action), ["pdp_status_recovered", "purchase_invoice_list_error", "pdp_status_error"])
        XCTAssertEqual(Array(journal.incidents.keys), ["purchaseReception|\(account.uuidString)"])
    }

    // MARK: - Nature des échecs

    func testCauseClassification() {
        XCTAssertEqual(SyncFailureCause(URLError(.timedOut)), SyncFailureCause(category: "réseau", accountWide: true))
        XCTAssertEqual(SyncFailureCause(URLError(.cannotFindHost)), SyncFailureCause(category: "réseau", accountWide: true))
        XCTAssertEqual(SyncFailureCause(SuperPDPError.http(status: 502, body: "")), SyncFailureCause(category: "HTTP 5xx", accountWide: true))
        XCTAssertEqual(SyncFailureCause(SuperPDPError.http(status: 401, body: "")), SyncFailureCause(category: "HTTP 401", accountWide: true))
        XCTAssertEqual(SyncFailureCause(SuperPDPError.http(status: 429, body: "")), SyncFailureCause(category: "HTTP 429", accountWide: true))
        XCTAssertEqual(SyncFailureCause(SuperPDPError.http(status: 404, body: "")), SyncFailureCause(category: "HTTP 404", accountWide: false))
        XCTAssertEqual(SyncFailureCause(SuperPDPError.noToken), SyncFailureCause(category: "identifiants", accountWide: true))
        XCTAssertEqual(SyncFailureCause(SuperPDPError.decoding("x")), SyncFailureCause(category: "réponse illisible", accountWide: false))
        XCTAssertEqual(SyncFailureCause(NSError(domain: "CIIXMLParser", code: 1)), SyncFailureCause(category: "autre", accountWide: false))

        XCTAssertTrue(SyncFailureCause.isCancellation(URLError(.cancelled)))
        XCTAssertTrue(SyncFailureCause.isCancellation(CancellationError()))
        XCTAssertFalse(SyncFailureCause.isCancellation(URLError(.notConnectedToInternet)))
    }

    func testBriefShortensLongMessages() {
        XCTAssertEqual(SyncFailureJournal.brief("court"), "court")
        let long = String(repeating: "x", count: 250)
        XCTAssertEqual(SyncFailureJournal.brief(long), String(repeating: "x", count: 200) + "…")
    }

    // MARK: - Outils

    private func makeJournal() -> SyncFailureJournal {
        let journal = SyncFailureJournal()
        journal.now = { [unowned self] in self.clock }
        return journal
    }

    /// Un cycle de la synchro des statuts (compte de `account`) : chaque facture échoue avec son
    /// erreur, ou répond (`nil`).
    private func statusCycle(_ outcomes: [(SyncTarget, Error?)]) {
        var cycle = SyncCycle(kind: .salesStatus, companyID: account, followedTargets: outcomes.map(\.0))
        for (target, error) in outcomes {
            if let error { cycle.recordFailure(error, target: target) } else { cycle.recordSuccess(target) }
        }
        journal.close(cycle, audit: audit)
        clock += 15 * 60
    }

    /// Un cycle de la réception (compte par défaut sauf mention) : la liste échoue, ou elle répond
    /// et chaque facture reçue s'importe ou échoue.
    private func receptionCycle(listError: Error?, imports: [(SyncTarget, Error?)] = [], companyID: UUID? = nil) {
        var cycle = SyncCycle(kind: .purchaseReception, companyID: companyID)
        if let listError {
            cycle.recordFailure(listError)
        } else {
            cycle.recordSuccess()
            cycle.followedTargets = imports.map(\.0)
            for (target, error) in imports {
                if let error { cycle.recordFailure(error, target: target) } else { cycle.recordSuccess(target) }
            }
        }
        journal.close(cycle, audit: audit)
        clock += 15 * 60
    }
}
