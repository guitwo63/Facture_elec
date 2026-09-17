import XCTest
@testable import FacturXCore

final class PaymentTermsPresetTests: XCTestCase {

    func testMatchingRecognizesKnownPresetText() {
        XCTAssertEqual(PaymentTermsPreset.matching("Comptant"), .comptant)
        XCTAssertEqual(PaymentTermsPreset.matching("Paiement à 30 jours"), .net30)
        XCTAssertEqual(PaymentTermsPreset.matching("Paiement à 30 jours fin de mois"), .finDeMois30)
        XCTAssertEqual(PaymentTermsPreset.matching("Paiement à réception"), .aReception)
    }

    func testMatchingTrimsWhitespace() {
        XCTAssertEqual(PaymentTermsPreset.matching("  Comptant  "), .comptant)
    }

    func testMatchingFallsBackToPersonaliseForUnknownText() {
        XCTAssertEqual(PaymentTermsPreset.matching("Virement à 45 jours"), .personnalise)
    }

    func testMatchingFallsBackToPersonaliseForNilOrEmpty() {
        XCTAssertEqual(PaymentTermsPreset.matching(nil), .personnalise)
        XCTAssertEqual(PaymentTermsPreset.matching(""), .personnalise)
        XCTAssertEqual(PaymentTermsPreset.matching("   "), .personnalise)
    }

    func testPersonaliseHasNoResolvedText() {
        XCTAssertNil(PaymentTermsPreset.personnalise.text)
    }

    func testEveryNonPersonaliseCaseRoundTrips() {
        for preset in PaymentTermsPreset.allCases where preset != .personnalise {
            XCTAssertEqual(PaymentTermsPreset.matching(preset.text), preset, "\(preset) devrait se retrouver lui-même une fois son texte résolu")
        }
    }
}
