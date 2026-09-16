import XCTest
@testable import FacturXCore

final class PaymentReminderTests: XCTestCase {

    private func makeInvoice(status: InvoiceStatus, dueDaysFromNow: Double) -> Invoice {
        Invoice(
            number: "FAC-OVR",
            status: status,
            dueDate: Date().addingTimeInterval(dueDaysFromNow * 86400),
            seller: InvoiceParty(name: "Vendeur SARL", street: "1 rue A", postcode: "75001", city: "Paris"),
            buyer: InvoiceParty(name: "Client SAS", street: "2 rue B", postcode: "75002", city: "Paris", contactEmail: "client@exemple.fr"),
            lines: [InvoiceLine(name: "Prestation", quantity: 1, unit: "C62", unitPrice: 100, vatRate: 20)]
        )
    }

    func testOverdueRequiresPastDueDateAndUnpaidStatus() {
        XCTAssertTrue(makeInvoice(status: .sentToPDP, dueDaysFromNow: -5).isOverdue)
        XCTAssertFalse(makeInvoice(status: .paid, dueDaysFromNow: -5).isOverdue, "une facture payée n'est jamais en retard")
        XCTAssertFalse(makeInvoice(status: .cancelled, dueDaysFromNow: -5).isOverdue, "une facture annulée n'est jamais en retard")
        XCTAssertFalse(makeInvoice(status: .issued, dueDaysFromNow: 5).isOverdue, "échéance future : pas en retard")
    }

    func testOverdueDaysIsZeroWhenNotOverdue() {
        XCTAssertEqual(makeInvoice(status: .paid, dueDaysFromNow: -5).overdueDays, 0)
        XCTAssertEqual(makeInvoice(status: .issued, dueDaysFromNow: 5).overdueDays, 0)
    }

    func testOverdueDaysCountsElapsedDays() {
        let inv = makeInvoice(status: .sentToPDP, dueDaysFromNow: -10)
        XCTAssertEqual(inv.overdueDays, 10)
    }

    func testComposerFillsInInvoiceNumberAndAmountForEveryLevel() {
        let inv = makeInvoice(status: .sentToPDP, dueDaysFromNow: -3)
        for level in PaymentReminderLevel.allCases {
            let email = PaymentReminderComposer.compose(level: level, for: inv)
            XCTAssertTrue(email.subject.contains(inv.number))
            XCTAssertTrue(email.body.contains(inv.number))
            XCTAssertFalse(email.subject.isEmpty)
            XCTAssertFalse(email.body.isEmpty)
        }
    }

    func testLegalPenaltyLevelMentionsLegalNotes() {
        let inv = makeInvoice(status: .sentToPDP, dueDaysFromNow: -20)
        let email = PaymentReminderComposer.compose(level: .legalPenalty, for: inv)
        XCTAssertTrue(email.body.contains(inv.legalNotePMT))
        XCTAssertTrue(email.body.contains(inv.legalNotePMD))
    }

    func testFriendlyLevelDoesNotMentionLegalPenalties() {
        let inv = makeInvoice(status: .sentToPDP, dueDaysFromNow: -3)
        let email = PaymentReminderComposer.compose(level: .friendly, for: inv)
        XCTAssertFalse(email.body.contains(inv.legalNotePMT))
    }
}
