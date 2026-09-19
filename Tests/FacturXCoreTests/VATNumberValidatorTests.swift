import XCTest
@testable import FacturXCore

/// BR-CO-09 (EN16931) : le préfixe d'un n° TVA doit être un code pays ISO 3166-1 alpha-2,
/// sauf la Grèce qui peut utiliser "EL" au lieu de "GR" — voir VATNumberValidator.swift.
final class VATNumberValidatorTests: XCTestCase {

    func testNilOrEmptyIsConsideredValid() {
        XCTAssertTrue(VATNumberValidator.hasValidCountryPrefix(nil), "rien à valider ici — l'obligation de présence relève d'autres règles")
        XCTAssertTrue(VATNumberValidator.hasValidCountryPrefix(""))
        XCTAssertTrue(VATNumberValidator.hasValidCountryPrefix("   "))
    }

    func testValidCountryPrefixesPass() {
        XCTAssertTrue(VATNumberValidator.hasValidCountryPrefix("FR12345678901"))
        XCTAssertTrue(VATNumberValidator.hasValidCountryPrefix("DE123456789"))
        XCTAssertTrue(VATNumberValidator.hasValidCountryPrefix("be0123456789"), "insensible à la casse")
    }

    func testGreeceElExceptionPasses() {
        XCTAssertTrue(VATNumberValidator.hasValidCountryPrefix("EL123456789"),
                     "la Grèce peut utiliser EL au lieu du code ISO GR — exception explicite de BR-CO-09")
        XCTAssertTrue(VATNumberValidator.hasValidCountryPrefix("GR123456789"), "le vrai code ISO GR reste aussi valide")
    }

    func testUnknownOrMissingPrefixFails() {
        XCTAssertFalse(VATNumberValidator.hasValidCountryPrefix("XX123456789"), "XX n'est pas un code ISO 3166-1 alpha-2")
        XCTAssertFalse(VATNumberValidator.hasValidCountryPrefix("12345678901"), "préfixe numérique, pas un code pays")
        XCTAssertFalse(VATNumberValidator.hasValidCountryPrefix("F"), "trop court pour contenir un préfixe pays")
    }
}
