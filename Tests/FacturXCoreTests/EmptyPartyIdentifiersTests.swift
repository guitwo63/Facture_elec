import XCTest
import FacturXCore

/// Un n° TVA ou un SIREN vidé dans l'éditeur est enregistré "" et non nil
/// (`Binding(_:replacingNilWith:)`). Le générateur l'émettait comme identifiant vide, rejeté
/// par les Schematron officiels (BR-CO-09 pour le n° TVA, BR-FR-32 pour le SIREN), alors que
/// l'application autorisait l'export. Constaté le 2026-09-23 sur une facture S dont le n° TVA
/// de l'acheteur avait été effacé.
final class EmptyPartyIdentifiersTests: XCTestCase {

    private let agreementPath = "CrossIndustryInvoice/SupplyChainTradeTransaction/ApplicableHeaderTradeAgreement"

    private func invoice() -> Invoice {
        Invoice(
            number: "2026-0043",
            seller: InvoiceParty(name: "Mon Entreprise SARL", street: "12 rue du Commerce", postcode: "75001", city: "Paris",
                                 vatNumber: "FR44732829320", siren: "732829320"),
            buyer: InvoiceParty(name: "Client Exemple SAS", street: "8 avenue des Champs", postcode: "75008", city: "Paris",
                                vatNumber: "FR61987654321", siren: "987654321", endpointID: "987654321"),
            lines: [InvoiceLine(name: "Prestation de conseil", quantity: 2, unit: "DAY", unitPrice: 600, vatRate: 20)]
        )
    }

    private func xml(_ invoice: Invoice) throws -> String {
        String(decoding: try CIIXMLGenerator().generate(invoice: invoice), as: UTF8.self)
    }

    private func childNames(_ xml: String, _ party: String, file: StaticString = #filePath, line: UInt = #line) throws -> [String] {
        let doc = try XMLDocument(data: Data(xml.utf8))
        let steps = (agreementPath + "/" + party).split(separator: "/").map { "*[local-name()='\($0)']" }
        guard let element = try doc.nodes(forXPath: "/" + steps.joined(separator: "/")).first as? XMLElement else {
            XCTFail("\(party) introuvable", file: file, line: line)
            return []
        }
        return element.children?.compactMap { ($0 as? XMLElement)?.localName } ?? []
    }

    func testClearedVATNumberIsNotEmitted() throws {
        for cleared in ["", "   "] {
            var inv = invoice()
            inv.buyer.vatNumber = cleared
            let s = try xml(inv)
            XCTAssertFalse(try childNames(s, "BuyerTradeParty").contains("SpecifiedTaxRegistration"), "« \(cleared) »")
            XCTAssertTrue(try childNames(s, "SellerTradeParty").contains("SpecifiedTaxRegistration"))
            XCTAssertFalse(s.contains("schemeID=\"VA\"></ram:ID>"))
            XCTAssertFalse(s.contains("schemeID=\"VA\">   </ram:ID>"))
        }
    }

    func testVATNumberIsEmittedTrimmed() throws {
        var inv = invoice()
        inv.buyer.vatNumber = " FR61987654321 "
        XCTAssertTrue(try xml(inv).contains("<ram:ID schemeID=\"VA\">FR61987654321</ram:ID>"))
    }

    func testClearedSirenIsNotEmittedButTheElectronicAddressStays() throws {
        var inv = invoice()
        inv.buyer.siren = ""
        let names = try childNames(try xml(inv), "BuyerTradeParty")
        XCTAssertFalse(names.contains("SpecifiedLegalOrganization"))
        XCTAssertTrue(names.contains("URIUniversalCommunication"), "adresse électronique (BT-49) saisie à part")
        XCTAssertTrue(FacturXValidator().validate(invoice: inv).isValid)
    }

    func testClearedIdentifiersAreReadBackAsAbsent() throws {
        var inv = invoice()
        inv.buyer.vatNumber = ""
        inv.buyer.siren = ""
        let parsed = try CIIXMLParser().parse(xml: CIIXMLGenerator().generate(invoice: inv))
        XCTAssertNil(parsed.buyer.vatNumber)
        XCTAssertNil(parsed.buyer.siren)
        XCTAssertEqual(parsed.seller.vatNumber, "FR44732829320")
        XCTAssertEqual(parsed.seller.siren, "732829320")
    }
}
