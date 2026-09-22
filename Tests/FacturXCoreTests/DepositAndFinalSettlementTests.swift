import XCTest
@testable import FacturXCore

/// Couvre `InvoiceStore.newDeposit`/`newFinalSettlement`, jusqu'ici sans aucun appelant (donc
/// sans aucune couverture) et qui obtiennent leurs premiers points d'entrée UI (« Créer un
/// acompte » / « Créer le solde ») dans ce chantier. Couvre aussi le nouveau champ
/// `Invoice.linkedSettlementRef` et `InvoiceTypeCode.allowsDepositCreation`.
final class DepositAndFinalSettlementTests: XCTestCase {

    private let keys = [
        "facturx.invoices.v1",
        "facturx.number.prefix.v1",
        "facturx.number.includeyear.v1",
        "facturx.number.start.v1",
        "facturx.number.useseparator.v1",
        "facturx.number.overrides.bysociety.v1",
    ]

    override func setUp() {
        super.setUp()
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    override func tearDown() {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        super.tearDown()
    }

    private func party(_ name: String) -> InvoiceParty {
        InvoiceParty(name: name, street: "1 rue A", postcode: "75001", city: "Paris", country: "FR")
    }

    // MARK: - linkedSettlementRef : migration sûre

    func testDecodingInvoiceWithoutLinkedSettlementRefDefaultsNil() throws {
        let legacyJSON = """
        {"id":"\(UUID().uuidString)","number":"F-1",
         "seller":{"name":"S","street":"","postcode":"","city":"","country":"FR","legalSchemeID":"0002","endpointSchemeID":"0225"},
         "buyer":{"name":"B","street":"","postcode":"","city":"","country":"FR","legalSchemeID":"0002","endpointSchemeID":"0225"}}
        """
        let decoded = try JSONDecoder().decode(Invoice.self, from: Data(legacyJSON.utf8))
        XCTAssertNil(decoded.linkedSettlementRef)
    }

    func testInvoiceRoundTripsLinkedSettlementRef() throws {
        var invoice = Invoice(number: "ACPT-1", type: .deposit, seller: party("V"), buyer: party("A"))
        invoice.linkedSettlementRef = "SOLDE-2026-0007"
        let encoded = try JSONEncoder().encode(invoice)
        let decoded = try JSONDecoder().decode(Invoice.self, from: encoded)
        XCTAssertEqual(decoded.linkedSettlementRef, "SOLDE-2026-0007")
    }

    // MARK: - InvoiceStore.newDeposit

    func testNewDepositClonesLinesResetsStatusAndAmounts() {
        let store = InvoiceStore()
        let p = party("Client")
        let source = Invoice(number: store.nextNumber(), type: .commercialInvoice, status: .issued,
                              seller: p, buyer: p,
                              lines: [InvoiceLine(name: "Prestation", quantity: 1, unitPrice: 1000, vatRate: 20)])
        store.upsert(source)

        let deposit = store.newDeposit(from: source)

        XCTAssertEqual(deposit.type, .deposit)
        XCTAssertEqual(deposit.status, .draft)
        XCTAssertNotEqual(deposit.id, source.id)
        XCTAssertNotEqual(deposit.number, source.number)
        XCTAssertNil(deposit.precedingInvoiceRef)
        XCTAssertNil(deposit.linkedSettlementRef)
        XCTAssertEqual(deposit.prepaidAmount, 0)
        XCTAssertEqual(deposit.lines.count, source.lines.count)
    }

    func testNewDepositRecomputesDueDateRelativeToNewIssueDate() {
        let store = InvoiceStore()
        let p = party("Client")
        let oldIssue = Date().addingTimeInterval(-100 * 86400)
        let oldDue = oldIssue.addingTimeInterval(45 * 86400)
        let source = Invoice(number: store.nextNumber(), issueDate: oldIssue, dueDate: oldDue,
                              seller: p, buyer: p, lines: [InvoiceLine(name: "X", quantity: 1, unitPrice: 100, vatRate: 20)])
        store.upsert(source)

        let deposit = store.newDeposit(from: source)

        XCTAssertFalse(deposit.isOverdue, "un acompte fraîchement créé ne doit jamais paraître déjà en retard")
        let interval = deposit.dueDate.timeIntervalSince(deposit.issueDate)
        XCTAssertEqual(interval, 45 * 86400, accuracy: 1, "le délai de paiement d'origine (45 jours) doit être préservé")
    }

    // MARK: - InvoiceStore.newFinalSettlement

    func testNewFinalSettlementSumsPrepaidAmountFromAllDepositsButReferencesOnlyFirst() {
        let store = InvoiceStore()
        let p = party("Client")
        let source = Invoice(number: store.nextNumber(), seller: p, buyer: p,
                              lines: [InvoiceLine(name: "Total", quantity: 1, unitPrice: 3000, vatRate: 20)])

        var deposit1 = store.newDeposit(from: source)
        deposit1.lines = [InvoiceLine(name: "Acompte 1", quantity: 1, unitPrice: 1000, vatRate: 20)]
        var deposit2 = store.newDeposit(from: source)
        deposit2.lines = [InvoiceLine(name: "Acompte 2", quantity: 1, unitPrice: 500, vatRate: 20)]

        let final = store.newFinalSettlement(from: source, deposits: [deposit1, deposit2])

        XCTAssertEqual(final.type, .finalSettlement)
        XCTAssertNil(final.linkedSettlementRef)
        XCTAssertEqual(final.prepaidAmount, deposit1.grandTotal + deposit2.grandTotal, accuracy: 0.001)
        XCTAssertEqual(final.precedingInvoiceRef, deposit1.number,
                       "limitation connue et documentée : seul le premier acompte est référencé (BT-25/26 est scalaire)")
    }

    func testNewFinalSettlementRecomputesDueDateRelativeToNewIssueDate() {
        let store = InvoiceStore()
        let p = party("Client")
        let oldIssue = Date().addingTimeInterval(-100 * 86400)
        let oldDue = oldIssue.addingTimeInterval(30 * 86400)
        let source = Invoice(number: store.nextNumber(), issueDate: oldIssue, dueDate: oldDue,
                              seller: p, buyer: p, lines: [InvoiceLine(name: "X", quantity: 1, unitPrice: 100, vatRate: 20)])
        let deposit = store.newDeposit(from: source)

        let final = store.newFinalSettlement(from: source, deposits: [deposit])

        XCTAssertFalse(final.isOverdue, "une facture de solde fraîchement créée ne doit jamais paraître déjà en retard")
    }

    // MARK: - InvoiceTypeCode.allowsDepositCreation

    func testAllowsDepositCreationOnlyForCommercialAndCorrection() {
        XCTAssertTrue(InvoiceTypeCode.commercialInvoice.allowsDepositCreation)
        XCTAssertTrue(InvoiceTypeCode.correction.allowsDepositCreation)
        XCTAssertFalse(InvoiceTypeCode.creditNote.allowsDepositCreation)
        XCTAssertFalse(InvoiceTypeCode.internalCreditNote.allowsDepositCreation)
        XCTAssertFalse(InvoiceTypeCode.deposit.allowsDepositCreation)
        XCTAssertFalse(InvoiceTypeCode.finalSettlement.allowsDepositCreation)
    }
}
