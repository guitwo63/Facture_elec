import XCTest
import FacturXCore

/// Taux saisi dans un éditeur (`InvoiceLine.setVATRate(_:)`) et ligne ajoutée
/// (`InvoiceLine.blank(after:)`). Jusqu'au 2026-09-23, les éditeurs recalaient la catégorie
/// dans un `onChange` : « 0 % — Exonéré » donnait Z « Taux zéro », rare en France, et la
/// ligne ajoutée après une ligne exonérée retombait en Z, sans motif.
final class VATRateEditingTests: XCTestCase {

    private let motif = "Exonération de TVA, article 261-4-4° du CGI"

    private func invoice(_ lines: [InvoiceLine]) -> Invoice {
        Invoice(number: "2026-0099",
                seller: InvoiceParty(name: "Vendeur", street: "1 rue A", postcode: "75001", city: "Paris", country: "FR",
                                     vatNumber: "FR44732829320", siren: "732829320"),
                buyer: InvoiceParty(name: "Client", street: "2 rue B", postcode: "69001", city: "Lyon", country: "FR",
                                    siren: "303265045"),
                lines: lines)
    }

    // MARK: - setVATRate

    func testZeroRateMakesTheLineExempt() {
        var line = InvoiceLine(name: "Formation", quantity: 1, unitPrice: 100, vatRate: 20)
        line.setVATRate(0)
        XCTAssertEqual(line.vatRate, 0)
        XCTAssertEqual(line.vatCategory, .exempt, "« 0 % — Exonéré » met la ligne en E, pas en Z")
        XCTAssertNil(line.vatExemptionReason, "le motif reste à saisir")
    }

    /// Le motif manquant bloque l'export (BR-E-10) ; saisi, la ligne exonérée est conforme et
    /// n'appelle plus le rappel « taux nul en catégorie Z ».
    func testExemptLineNeedsItsReasonBeforeExport() {
        var line = InvoiceLine(name: "Formation", quantity: 1, unitPrice: 100, vatRate: 20)
        line.setVATRate(0)
        let withoutReason = EN16931BusinessRules.evaluate(invoice: invoice([line]))
        XCTAssertTrue(withoutReason.contains { $0.ruleId == "BR-E-10" && $0.severity == .error })
        XCTAssertFalse(FacturXValidator().validate(invoice: invoice([line])).isValid)

        line.vatExemptionReason = motif
        let withReason = EN16931BusinessRules.evaluate(invoice: invoice([line]))
        XCTAssertFalse(withReason.contains { $0.ruleId.hasPrefix("BR-E-") }, "\(withReason.map(\.ruleId))")
        XCTAssertFalse(withReason.contains { $0.ruleId == "BT-152-ZERO" })
    }

    func testExemptLineIsEmittedAsCategoryEWithItsReason() throws {
        var line = InvoiceLine(name: "Formation", quantity: 1, unitPrice: 100, vatRate: 20)
        line.setVATRate(0)
        line.vatExemptionReason = motif
        let xml = String(decoding: try CIIXMLGenerator().generate(invoice: invoice([line])), as: UTF8.self)
        XCTAssertTrue(xml.contains("<ram:CategoryCode>E</ram:CategoryCode>"))
        XCTAssertFalse(xml.contains("<ram:CategoryCode>Z</ram:CategoryCode>"))
        XCTAssertTrue(xml.contains("<ram:ExemptionReason>\(motif)</ram:ExemptionReason>"))
    }

    func testNonZeroRateRestoresStandardAndClearsTheReason() {
        var line = InvoiceLine(name: "Formation", quantity: 1, unitPrice: 100, vatRate: 0, vatCategory: .exempt,
                               vatExemptionReason: motif)
        line.setVATRate(20)
        XCTAssertEqual(line.vatCategory, .standard)
        XCTAssertNil(line.vatExemptionReason)

        line.setVATRate(5.5)
        XCTAssertEqual(line.vatRate, 5.5)
        XCTAssertEqual(line.vatCategory, .standard)
    }

    /// Resélectionner 0 % dans le sélecteur ne défait pas une catégorie choisie ensuite dans
    /// le menu Catégorie (ici K), ni son motif.
    func testReselectingTheSameRateKeepsTheChosenCategory() {
        let reason = "Exonération de TVA, article 262 ter I du CGI"
        var line = InvoiceLine(name: "Machine", quantity: 1, unitPrice: 100, vatRate: 0, vatCategory: .intraCommunity,
                               vatExemptionReason: reason)
        line.setVATRate(0)
        XCTAssertEqual(line.vatCategory, .intraCommunity)
        XCTAssertEqual(line.vatExemptionReason, reason)
    }

    /// Une ligne Z enregistrée reste Z tant que son taux ne change pas : pas de migration.
    func testStoredZeroRatedLineKeepsItsCategory() throws {
        let json = #"{"name":"A","quantity":1,"unitPrice":100,"vatRate":0,"vatCategory":"Z"}"#
        var line = try JSONDecoder().decode(InvoiceLine.self, from: Data(json.utf8))
        XCTAssertEqual(line.vatCategory, .zeroRated)
        line.setVATRate(0)
        XCTAssertEqual(line.vatCategory, .zeroRated)

        let legacy = #"{"name":"A","quantity":1,"unitPrice":100,"vatRate":0}"#
        XCTAssertEqual(try JSONDecoder().decode(InvoiceLine.self, from: Data(legacy.utf8)).vatCategory, .zeroRated,
                       "une ancienne ligne sans catégorie est relue en Z, comme elle a été émise")
    }

    // MARK: - blank(after:)

    func testBlankLineWithoutPreviousLineIsStandardTwentyPercent() {
        let line = InvoiceLine.blank(after: nil)
        XCTAssertEqual(line.name, "")
        XCTAssertEqual(line.quantity, 1)
        XCTAssertEqual(line.unitPrice, 0)
        XCTAssertEqual(line.vatRate, 20)
        XCTAssertEqual(line.vatCategory, .standard)
    }

    func testBlankLineContinuesTheExemptionOfThePreviousLine() {
        let previous = InvoiceLine(name: "Formation", quantity: 2, unitPrice: 300, vatRate: 0, vatCategory: .exempt,
                                   vatExemptionReason: motif)
        let line = InvoiceLine.blank(after: previous)
        XCTAssertNotEqual(line.id, previous.id)
        XCTAssertEqual(line.name, "")
        XCTAssertEqual(line.vatRate, 0)
        XCTAssertEqual(line.vatCategory, .exempt)
        XCTAssertEqual(line.vatExemptionReason, motif, "le motif, contrôlé ligne par ligne, n'est pas à retaper")
        XCTAssertFalse(EN16931BusinessRules.evaluate(invoice: invoice([previous, line])).contains { $0.ruleId == "BR-E-10" })
    }

    /// Un motif resté sur une ligne Z (catégorie sans motif) n'est pas propagé.
    func testBlankLineDropsALeftoverReasonOnACategoryWithoutOne() {
        let previous = InvoiceLine(name: "A", quantity: 1, unitPrice: 100, vatRate: 0, vatCategory: .zeroRated,
                                   vatExemptionReason: motif)
        let line = InvoiceLine.blank(after: previous)
        XCTAssertEqual(line.vatCategory, .zeroRated)
        XCTAssertNil(line.vatExemptionReason)
    }

    func testBlankLineKeepsANonZeroRate() {
        let line = InvoiceLine.blank(after: InvoiceLine(name: "A", quantity: 1, unitPrice: 100, vatRate: 10))
        XCTAssertEqual(line.vatRate, 10)
        XCTAssertEqual(line.vatCategory, .standard)
        XCTAssertNil(line.vatExemptionReason)
    }

    // MARK: - Rappel BT-152-ZERO

    /// La catégorie Z reste possible (menu Catégorie) ; le rappel oriente vers E sans
    /// confondre taux zéro et exonération.
    func testZeroRatedReminderPointsToTheExemptCategory() {
        let line = InvoiceLine(name: "A", quantity: 1, unitPrice: 100, vatRate: 0, vatCategory: .zeroRated)
        let reminder = EN16931BusinessRules.evaluate(invoice: invoice([line])).first { $0.ruleId == "BT-152-ZERO" }
        XCTAssertEqual(reminder?.severity, .warning)
        XCTAssertTrue(reminder?.message.contains("catégorie E « Exonérée »") ?? false, reminder?.message ?? "")
        XCTAssertTrue(reminder?.message.contains("rare en France") ?? false)
    }
}
