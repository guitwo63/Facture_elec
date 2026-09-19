import XCTest
@testable import FacturXCore

final class PurchaseInvoiceStoreTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "facturx.purchaseinvoices.v1")
        UserDefaults.standard.removeObject(forKey: "facturx.audit.v1")
        super.tearDown()
    }

    private func samplePurchaseInvoice() -> PurchaseInvoice {
        let supplier = InvoiceParty(name: "Fournisseur Test", street: "1 rue Test", postcode: "75000", city: "Paris")
        let us = InvoiceParty(name: "Notre société", street: "2 rue Test", postcode: "75001", city: "Paris")
        let invoice = Invoice(number: "SUP-2026-001", seller: supplier, buyer: us,
                               lines: [InvoiceLine(name: "Prestation", quantity: 1, unitPrice: 100, vatRate: 20)])
        return PurchaseInvoice(invoice: invoice, status: .received)
    }

    func testUpsertPersistsAndReloads() {
        let store = PurchaseInvoiceStore()
        store.upsert(samplePurchaseInvoice())

        let reloaded = PurchaseInvoiceStore()
        XCTAssertEqual(reloaded.invoices.count, 1)
        XCTAssertEqual(reloaded.invoices.first?.invoice.number, "SUP-2026-001")
    }

    func testDeleteRemovesTheRecord() {
        let store = PurchaseInvoiceStore()
        let record = samplePurchaseInvoice()
        store.upsert(record)
        store.delete(record)
        XCTAssertTrue(store.invoices.isEmpty)
    }

    func testNewManualEntryStartsAsDraftWithEmptySupplierAndOurCompanyAsBuyer() {
        let store = PurchaseInvoiceStore()
        let salesStore = InvoiceStore()
        salesStore.myCompany = InvoiceParty(name: "Notre société", street: "", postcode: "", city: "")
        let record = store.newManualEntry(directory: PartyDirectory(), salesStore: salesStore)

        XCTAssertEqual(record.status, .draft)
        XCTAssertEqual(record.invoice.seller.name, "", "le fournisseur reste à choisir dans l'annuaire")
        XCTAssertEqual(record.invoice.buyer.name, "Notre société", "l'acheteur, c'est nous — réutilise InvoiceStore.myCompany")
    }

    func testIngestIsIdempotentForARepeatedRemoteID() {
        let store = PurchaseInvoiceStore()
        let supplier = InvoiceParty(name: "Fournisseur", street: "", postcode: "", city: "")
        let us = InvoiceParty(name: "Nous", street: "", postcode: "", city: "")
        let invoice = Invoice(number: "SUP-001", seller: supplier, buyer: us, lines: [])

        let first = store.ingest(remoteID: "remote-1", parsed: invoice, companyID: nil)
        let second = store.ingest(remoteID: "remote-1", parsed: invoice, companyID: nil)

        XCTAssertEqual(store.invoices.count, 1, "un remoteID déjà connu ne doit jamais créer un doublon")
        XCTAssertEqual(first.id, second.id)
    }

    func testIngestSetsStatusToReceived() {
        let store = PurchaseInvoiceStore()
        let supplier = InvoiceParty(name: "Fournisseur", street: "", postcode: "", city: "")
        let us = InvoiceParty(name: "Nous", street: "", postcode: "", city: "")
        let invoice = Invoice(number: "SUP-002", seller: supplier, buyer: us, lines: [])

        let record = store.ingest(remoteID: "remote-2", parsed: invoice, companyID: nil)
        XCTAssertEqual(record.status, .received)
        XCTAssertEqual(record.invoice.superPDPRemoteID, "remote-2")
    }

    func testUpsertRecordsCreationInAudit() {
        let store = PurchaseInvoiceStore()
        let audit = AuditStore()
        store.audit = audit
        store.upsert(samplePurchaseInvoice())

        let entry = audit.entries.first
        XCTAssertEqual(entry?.objectType, .purchaseInvoice)
        XCTAssertEqual(entry?.action, "purchase_invoice_created")
    }

    func testUpsertRecordsStatusChangeInAudit() {
        let store = PurchaseInvoiceStore()
        let audit = AuditStore()
        store.audit = audit
        var record = samplePurchaseInvoice()
        store.upsert(record)

        record.status = .toValidate
        store.upsert(record)

        let entry = audit.entries.first
        XCTAssertEqual(entry?.action, "status_change")
        XCTAssertEqual(entry?.objectType, .purchaseInvoice)
        XCTAssertEqual(entry?.statusFrom, PurchaseInvoiceStatus.received.label)
        XCTAssertEqual(entry?.statusTo, PurchaseInvoiceStatus.toValidate.label)
    }
}
