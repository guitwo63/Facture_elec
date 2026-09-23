import XCTest
@testable import FacturXCore

/// Incrément 2.1 du chantier "Réglages par société" — `AuditLogEntry.companyID`, propagé
/// depuis les 16 sites documentaires (InvoiceStore/OrderStore/QuoteStore/
/// PurchaseInvoiceStore/PartyDirectory/PurchasesTabView). Les 25 sites sans société
/// naturelle (Auth.swift, sauvegarde globale) restent `companyID: nil` — voir le plan.
final class AuditLogCompanyScopeTests: XCTestCase {

    private let key = "facturx.audit.v1"

    override func setUp() {
        super.setUp()
        AppPersistence.defaults.removeObject(forKey: key)
    }

    override func tearDown() {
        AppPersistence.defaults.removeObject(forKey: key)
        super.tearDown()
    }

    func testRecordWithCompanyIDPersistsIt() {
        let store = AuditStore()
        let cid = UUID()
        store.record(actor: "admin", action: "invoice_created", target: "FA-0001", objectType: .invoice, objectCode: "FA-0001", companyID: cid)

        XCTAssertEqual(store.entries.first?.companyID, cid)
    }

    func testRecordWithoutCompanyIDDefaultsToNil() {
        let store = AuditStore()
        store.record(actor: "admin@facturx.local", action: "login_success", target: "")

        XCTAssertNil(store.entries.first?.companyID)
    }

    func testRecordStatusChangeWithCompanyIDPersistsIt() {
        let store = AuditStore()
        let cid = UUID()
        store.recordStatusChange(actor: "admin", objectType: .order, objectCode: "CD-0001", statusFrom: "Brouillon", statusTo: "Envoyée", companyID: cid)

        XCTAssertEqual(store.entries.first?.companyID, cid)
    }

    func testCompanyIDRoundTripsThroughCodable() throws {
        let cid = UUID()
        let entry = AuditLogEntry(actor: "admin", action: "invoice_created", target: "FA-0001", companyID: cid)

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(AuditLogEntry.self, from: data)

        XCTAssertEqual(decoded.companyID, cid)
    }

    func testDecodingLegacyEntryWithoutCompanyIDDefaultsToNil() throws {
        let json = """
        {"id":"\(UUID().uuidString)","timestamp":0,"actor":"admin","action":"invoice_created","target":"FA-0001","details":""}
        """
        let decoded = try JSONDecoder().decode(AuditLogEntry.self, from: Data(json.utf8))

        XCTAssertNil(decoded.companyID)
    }

    func testEntriesPersistCompanyIDAcrossReload() {
        let store = AuditStore()
        let cid = UUID()
        store.record(actor: "admin", action: "quote_created", target: "DEV-0001", objectType: .quote, objectCode: "DEV-0001", companyID: cid)

        let reloaded = AuditStore()
        XCTAssertEqual(reloaded.entries.first?.companyID, cid)
    }
}
