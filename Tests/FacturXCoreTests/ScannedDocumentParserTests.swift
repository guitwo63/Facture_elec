import XCTest
@testable import FacturXCore

final class ScannedDocumentParserTests: XCTestCase {

    private let sampleOCRText = """
    ACME FOURNITURES SAS
    12 rue des Ateliers
    69003 Lyon
    SIREN 123 456 789

    BON DE COMMANDE
    Commande n° BC-2026-0451
    Date : 03/09/2026

    Désignation           Qté   Prix U.
    Câble HDMI 2m          10    4,50
    """

    func testExtractReferenceFindsOrderNumberAfterKeyword() {
        XCTAssertEqual(ScannedDocumentParser.extractReference(from: sampleOCRText), "BC-2026-0451")
    }

    func testExtractReferenceHandlesReferenceKeywordVariants() {
        XCTAssertEqual(ScannedDocumentParser.extractReference(from: "Réf : ABC123"), "ABC123")
        XCTAssertEqual(ScannedDocumentParser.extractReference(from: "Référence: XYZ-99"), "XYZ-99")
        XCTAssertEqual(ScannedDocumentParser.extractReference(from: "Devis n°D2026-77"), "D2026-77")
    }

    func testExtractReferenceReturnsNilWhenNoKeywordPresent() {
        XCTAssertNil(ScannedDocumentParser.extractReference(from: "Aucune information pertinente ici."))
    }

    func testExtractDateParsesFrenchFormat() {
        let date = ScannedDocumentParser.extractDate(from: sampleOCRText)
        XCTAssertNotNil(date)
        let comps = Calendar.current.dateComponents([.day, .month, .year], from: date!)
        XCTAssertEqual(comps.day, 3)
        XCTAssertEqual(comps.month, 9)
        XCTAssertEqual(comps.year, 2026)
    }

    func testExtractDateSwapsDayMonthWhenSecondValueIsInvalidAsMonth() {
        // "03/25/2026" : 25 ne peut pas être un mois, donc jour/mois doivent être
        // échangés pour obtenir le 25 mars 2026, plutôt que rejeté comme invalide.
        let date = ScannedDocumentParser.extractDate(from: "Le 03/25/2026 ceci n'est pas standard")
        XCTAssertNotNil(date)
        let comps = Calendar.current.dateComponents([.day, .month, .year], from: date!)
        XCTAssertEqual(comps.day, 25)
        XCTAssertEqual(comps.month, 3)
        XCTAssertEqual(comps.year, 2026)
    }

    func testExtractDateReturnsNilWhenBothInterpretationsAreInvalid() {
        // Ni 13/25 ni 25/13 ne sont des dates valides : aucune date ne doit être renvoyée.
        XCTAssertNil(ScannedDocumentParser.extractDate(from: "Le 13/25/2026 ceci n'est pas standard"))
    }

    func testExtractDateReturnsNilWhenNoDatePresent() {
        XCTAssertNil(ScannedDocumentParser.extractDate(from: "Pas de date ici"))
    }

    func testExtractSIRENFindsSpacedNineDigitNumber() {
        XCTAssertEqual(ScannedDocumentParser.extractSIREN(from: sampleOCRText), "123456789")
    }

    func testExtractSIRENFindsPlainNineDigitNumber() {
        XCTAssertEqual(ScannedDocumentParser.extractSIREN(from: "SIREN: 987654321 France"), "987654321")
    }

    func testExtractSIRENIgnoresNumbersWithWrongDigitCount() {
        XCTAssertNil(ScannedDocumentParser.extractSIREN(from: "Téléphone : 04 78 12 34"))
        XCTAssertNil(ScannedDocumentParser.extractSIREN(from: "Code postal 69003"))
    }

    func testExtractSIRENReturnsNilWhenAbsent() {
        XCTAssertNil(ScannedDocumentParser.extractSIREN(from: "Aucun numéro ici."))
    }
}
