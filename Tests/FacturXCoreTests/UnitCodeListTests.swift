import XCTest
import CryptoKit
import FacturXCore

/// BR-CL-23 : le code d'unité (BT-130) doit figurer dans la liste des unités du Schematron
/// (UN/ECE Rec 20 avec l'extension Rec 21, `UnitCodeList`). Jusqu'au 2026-09-24, cinq des vingt
/// unités proposées n'y étaient pas (KTM, PCE, PCK, BX, ROL) : une facture dont une ligne était
/// en « Pièce (PCE) » partait à la PDP pour y être rejetée (« Value of '@unitCode' is not
/// allowed », vérifié avec le Schematron EN16931 officiel), sans que l'app ne signale rien.
final class UnitCodeListTests: XCTestCase {

    private func party(_ name: String, siren: String) -> InvoiceParty {
        InvoiceParty(name: name, street: "1 rue A", postcode: "75001", city: "Paris", country: "FR", siren: siren)
    }

    /// Valeurs de `BilledQuantity/@unitCode` dans le XML, dans l'ordre des lignes.
    private func emittedUnitCodes(_ xml: Data) throws -> [String] {
        let doc = try XMLDocument(data: xml)
        return try doc.nodes(forXPath: "//*[local-name()='BilledQuantity']/@unitCode").compactMap(\.stringValue)
    }

    /// La liste embarquée est la liste 8 du codedb, entière et sans retouche : même nombre de
    /// codes, même empreinte que les codes officiels triés et joints par une espace (calculée sur
    /// `FACTUR-X_EN16931_codedb.xml` de factur-x 6.8).
    func testEmbeddedListIsTheOfficialOne() {
        XCTAssertEqual(UnitCodeList.codes.count, 2162)
        let digest = SHA256.hash(data: Data(UnitCodeList.codes.sorted().joined(separator: " ").utf8))
        XCTAssertEqual(digest.map { String(format: "%02x", $0) }.joined(),
                       "873b3bd175eccd63ab6fcb4003c94dde5cbee25884316490d9d1a753380d30df")
        for code in ["C62", "DAY", "HUR", "KMT", "H87", "XPK", "XBX", "XRO", "EA", "10", "ZZ"] {
            XCTAssertTrue(UnitCodeList.contains(code), code)
        }
        for code in ["KTM", "PCE", "PCK", "BX", "ROL", "EACH", "h87", ""] {
            XCTAssertFalse(UnitCodeList.contains(code), code)
        }
    }

    func testEveryProposedUnitIsInTheSchematronList() {
        for ref in NormRefs.units {
            XCTAssertTrue(UnitCodeList.contains(ref.code), "« \(ref.label) » : code refusé par le Schematron (BR-CL-23)")
        }
    }

    func testProposedUnitsAreDistinctAndShowTheirOwnCode() {
        XCTAssertEqual(Set(NormRefs.units.map(\.code)).count, NormRefs.units.count)
        for ref in NormRefs.units {
            XCTAssertTrue(ref.label.hasSuffix(" (\(ref.code))"), ref.label)
        }
    }

    /// Les anciens codes sont refusés par le Schematron et ne sont plus proposés ; chaque code
    /// de remplacement est admis et proposé sous le nom d'unité d'avant.
    func testLegacyCodesAreRefusedAndReplacedUnderTheSameName() {
        let names = ["KTM": "Kilomètre", "PCE": "Pièce", "PCK": "Paquet", "BX": "Boîte", "ROL": "Rouleau"]
        XCTAssertEqual(Set(NormRefs.legacyUnitReplacements.keys), Set(names.keys))
        for (legacy, replacement) in NormRefs.legacyUnitReplacements {
            XCTAssertFalse(UnitCodeList.contains(legacy), legacy)
            XCTAssertFalse(NormRefs.units.contains { $0.code == legacy }, legacy)
            XCTAssertTrue(UnitCodeList.contains(replacement), replacement)
            XCTAssertEqual(NormRefs.units.first { $0.code == replacement }?.label, "\(names[legacy]!) (\(replacement))")
        }
    }

    /// Ce que le Schematron contrôle vraiment : l'attribut du XML émis. Une ligne par unité
    /// proposée, plus une ligne sans unité, émise en C62.
    func testEveryEmittedUnitCodeIsInTheSchematronList() throws {
        let units = NormRefs.units.map(\.code) + [""]
        let invoice = Invoice(number: "2026-0101", seller: party("Vendeur", siren: "732829320"),
                              buyer: party("Client", siren: "303265045"),
                              lines: units.enumerated().map {
                                  InvoiceLine(name: "Article \($0.offset + 1)", quantity: 1, unit: $0.element, unitPrice: 10)
                              })
        let emitted = try emittedUnitCodes(CIIXMLGenerator().generate(invoice: invoice))
        XCTAssertEqual(emitted, NormRefs.units.map(\.code) + ["C62"])
        for code in emitted {
            XCTAssertTrue(UnitCodeList.contains(code), code)
        }
    }
}
