import XCTest
@testable import FacturXCore

final class InvoiceDuplicateTests: XCTestCase {

    private let keys = [
        "facturx.invoices.v1",
        "facturx.number.prefix.v1",
        "facturx.number.includeyear.v1",
        "facturx.number.start.v1",
        "facturx.number.useseparator.v1",
        "facturx.number.overrides.bysociety.v1"
    ]

    override func setUp() {
        super.setUp()
        keys.forEach { AppPersistence.defaults.removeObject(forKey: $0) }
    }

    override func tearDown() {
        keys.forEach { AppPersistence.defaults.removeObject(forKey: $0) }
        super.tearDown()
    }

    // MARK: - Régression : échéance d'un doublon

    /// Avant cette correction, duplicate(from:) réinitialisait issueDate à aujourd'hui mais
    /// conservait la dueDate absolue de la facture d'origine. Dupliquer une facture déjà en
    /// retard produisait donc un nouveau brouillon marqué "En retard" dès sa création.
    func testDuplicatingAnOverdueInvoiceIsNotImmediatelyOverdue() {
        let store = InvoiceStore()
        let party = InvoiceParty(name: "", street: "", postcode: "", city: "")
        let oldIssueDate = Date().addingTimeInterval(-100 * 86400)
        let oldDueDate = oldIssueDate.addingTimeInterval(30 * 86400)
        let original = Invoice(
            number: "FAC0001",
            status: .sent,
            issueDate: oldIssueDate,
            dueDate: oldDueDate,
            seller: party,
            buyer: party
        )
        XCTAssertTrue(original.isOverdue, "précondition : la facture d'origine est bien en retard")

        let copy = store.duplicate(from: original)

        XCTAssertFalse(copy.isOverdue, "un doublon fraîchement créé ne doit jamais s'afficher en retard")
        XCTAssertEqual(copy.status, .draft)
    }

    /// Le délai de paiement (ex. "30 jours") doit être préservé par rapport à la nouvelle date
    /// d'émission, plutôt que de figer une dueDate absolue ou une durée arbitraire.
    func testDuplicatePreservesPaymentTermLengthRelativeToNewIssueDate() {
        let store = InvoiceStore()
        let party = InvoiceParty(name: "", street: "", postcode: "", city: "")
        let oldIssueDate = Date().addingTimeInterval(-10 * 86400)
        let oldDueDate = oldIssueDate.addingTimeInterval(45 * 86400)
        let original = Invoice(
            number: "FAC0002",
            issueDate: oldIssueDate,
            dueDate: oldDueDate,
            seller: party,
            buyer: party
        )

        let copy = store.duplicate(from: original)

        let originalTermLength = original.dueDate.timeIntervalSince(original.issueDate)
        let copyTermLength = copy.dueDate.timeIntervalSince(copy.issueDate)
        XCTAssertEqual(copyTermLength, originalTermLength, accuracy: 1, "le délai de paiement doit rester de 45 jours")
    }
}
