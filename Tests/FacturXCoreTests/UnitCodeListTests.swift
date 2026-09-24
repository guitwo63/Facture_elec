import XCTest
import FacturXCore

/// BR-CL-23 : le code d'unité (BT-130) doit figurer dans la liste des unités du Schematron
/// (UN/ECE Rec 20 avec l'extension Rec 21, `SchematronUnitCodes`). Jusqu'au 2026-09-24, cinq des
/// vingt unités proposées n'y étaient pas (KTM, PCE, PCK, BX, ROL) : une facture dont une ligne
/// était en « Pièce (PCE) » partait à la PDP pour y être rejetée (« Value of '@unitCode' is not
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

    /// Garde-fou : la liste embarquée est la liste officielle entière, pas une liste tronquée ou
    /// prise dans une autre liste du codedb.
    func testEmbeddedSchematronListIsComplete() {
        XCTAssertEqual(SchematronUnitCodes.all.count, SchematronUnitCodes.count)
        for code in ["C62", "DAY", "HUR", "KMT", "H87", "XPK", "XBX", "XRO", "10", "ZZ"] {
            XCTAssertTrue(SchematronUnitCodes.all.contains(code), code)
        }
    }

    func testEveryProposedUnitIsInTheSchematronList() {
        for ref in NormRefs.units {
            XCTAssertTrue(SchematronUnitCodes.all.contains(ref.code),
                          "« \(ref.label) » : code refusé par le Schematron (BR-CL-23)")
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
            XCTAssertFalse(SchematronUnitCodes.all.contains(legacy), legacy)
            XCTAssertFalse(NormRefs.units.contains { $0.code == legacy }, legacy)
            XCTAssertTrue(SchematronUnitCodes.all.contains(replacement), replacement)
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
            XCTAssertTrue(SchematronUnitCodes.all.contains(code), code)
        }
    }
}
