import XCTest
import FacturXCore

final class FacturXCoreTests: XCTestCase {

    private func sampleInvoice() -> Invoice {
        Invoice(
            number: "2026-0001",
            type: .commercialInvoice,
            issueDate: makeDate("2026-09-01"),
            dueDate: makeDate("2026-09-30"),
            currency: "EUR",
            profile: .en16931,
            seller: InvoiceParty(
                name: "Mon Entreprise SARL",
                street: "12 rue du Commerce",
                postcode: "75001",
                city: "Paris",
                country: "FR",
                vatNumber: "FR12345678901",
                siren: "123456789",
                contactEmail: "[email protected]",
                endpointID: "123456789",
                endpointSchemeID: "0225"
            ),
            buyer: InvoiceParty(
                name: "Client Exemple SAS",
                street: "8 avenue des Champs",
                postcode: "75008",
                city: "Paris",
                country: "FR",
                siren: "987654321",
                endpointID: "987654321",
                endpointSchemeID: "0225"
            ),
            buyerReference: "CLIENT-REF-42",
            lines: [
                InvoiceLine(name: "Prestation de conseil", quantity: 2, unit: "DAY", unitPrice: 600, vatRate: 20),
                InvoiceLine(name: "Frais de déplacement", quantity: 1, unit: "C62", unitPrice: 150, vatRate: 20)
            ],
            paymentIBAN: "FR7630006000011234567890189",
            paymentBIC: "AGRIFRPP",
            paymentTerms: "Paiement à 30 jours",
            billingMode: .m1
        )
    }

    func testTotals() {
        let inv = sampleInvoice()
        XCTAssertEqual(inv.lineTotal, 1350.00, accuracy: 0.001)
        XCTAssertEqual(inv.taxTotal, 270.00, accuracy: 0.001)
        XCTAssertEqual(inv.grandTotal, 1620.00, accuracy: 0.001)
    }

    func testXMLContainsEN16931URN() throws {
        let xml = try CIIXMLGenerator().generate(invoice: sampleInvoice())
        let s = String(data: xml, encoding: .utf8) ?? ""
        XCTAssertTrue(s.contains("urn:cen.eu:en16931:2017"))
        XCTAssertTrue(s.contains("<ram:CrossIndustryInvoice") == false)
        XCTAssertTrue(s.contains("<rsm:CrossIndustryInvoice"))
        XCTAssertTrue(s.contains("factur-x") == false)
        XCTAssertTrue(s.contains("AFRelationship") == false)
    }

    func testXMLStructureRequiredElements() throws {
        let xml = try CIIXMLGenerator().generate(invoice: sampleInvoice())
        let s = String(data: xml, encoding: .utf8) ?? ""
        XCTAssertTrue(s.contains("<ram:ID>2026-0001</ram:ID>"))
        XCTAssertTrue(s.contains("<ram:TypeCode>380</ram:TypeCode>"))
        XCTAssertTrue(s.contains("format=\"102\">20260901<"))
        XCTAssertTrue(s.contains("<ram:InvoiceCurrencyCode>EUR</ram:InvoiceCurrencyCode>"))
        XCTAssertTrue(s.contains("<ram:SpecifiedTaxRegistration>"))
        XCTAssertTrue(s.contains("schemeID=\"VA\">FR12345678901"))
        XCTAssertTrue(s.contains("schemeID=\"0002\">123456789"))
        XCTAssertTrue(s.contains("<ram:BilledQuantity unitCode=\"DAY\">2.0000"))
        XCTAssertTrue(s.contains("factur-x.xml") == false)
    }

    func testXMLContainsBillingMode() throws {
        let xml = try CIIXMLGenerator().generate(invoice: sampleInvoice())
        let s = String(data: xml, encoding: .utf8) ?? ""
        XCTAssertTrue(s.contains("BusinessProcessSpecifiedDocumentContextParameter"))
        XCTAssertTrue(s.contains("<ram:ID>M1</ram:ID>"))
    }

    func testXMLContainsEndpointIDs() throws {
        let xml = try CIIXMLGenerator().generate(invoice: sampleInvoice())
        let s = String(data: xml, encoding: .utf8) ?? ""
        XCTAssertTrue(s.contains("<ram:URIUniversalCommunication>"),
                      "BT-34/BT-49 doivent être émis via ram:URIUniversalCommunication")
        XCTAssertTrue(s.contains("schemeID=\"0225\">123456789<"),
                      "L'identifiant émetteur (BT-34) doit porter schemeID 0225")
        XCTAssertTrue(s.contains("schemeID=\"0225\">987654321<"),
                      "L'identifiant destinataire (BT-49) doit porter schemeID 0225")
        XCTAssertFalse(s.contains("<ram:ID schemeID=\"0225\">"),
                       "Le ram:ID nu ne doit plus porter schemeID (non conforme CII EN16931)")
    }

    func testXMLContainsLegalNotes() throws {
        let xml = try CIIXMLGenerator().generate(invoice: sampleInvoice())
        let s = String(data: xml, encoding: .utf8) ?? ""
        XCTAssertTrue(s.contains("<ram:SubjectCode>PMT</ram:SubjectCode>"))
        XCTAssertTrue(s.contains("<ram:SubjectCode>PMD</ram:SubjectCode>"))
        XCTAssertTrue(s.contains("<ram:SubjectCode>AAB</ram:SubjectCode>"))
    }

    func testXMLNoEmptyPersonName() throws {
        var inv = sampleInvoice()
        inv.seller = InvoiceParty(
            name: "Test", street: "", postcode: "", city: "",
            contactName: "   ", contactEmail: "[email protected]"
        )
        let xml = try CIIXMLGenerator().generate(invoice: inv)
        let s = String(data: xml, encoding: .utf8) ?? ""
        XCTAssertFalse(s.contains("<ram:PersonName></ram:PersonName>"),
                       "PersonName ne doit pas être vide")
        XCTAssertTrue(s.contains("DefinedTradeContact"))
    }

    func testPostalAddressOrder() throws {
        let xml = try CIIXMLGenerator().generate(invoice: sampleInvoice())
        let s = String(data: xml, encoding: .utf8) ?? ""
        if let addrRange = s.range(of: "<ram:PostalTradeAddress>") {
            let addr = s[addrRange.lowerBound..<(s.range(of: "</ram:PostalTradeAddress>", range: addrRange.upperBound..<s.endIndex)?.upperBound ?? s.endIndex)]
            let order = ["PostcodeCode", "LineOne", "CityName", "CountryID"].map { addr.range(of: "<ram:\($0)>") }
            XCTAssertNotNil(order[0])
            for i in 0..<(order.count - 1) {
                if let a = order[i], let b = order[i + 1] {
                    XCTAssertLessThan(a.lowerBound, b.lowerBound, "Order violation in PostalTradeAddress")
                }
            }
        }
    }

    func testEmbedProducesFacturXWithAttachment() throws {
        let invoice = sampleInvoice()
        let generator = FacturXGenerator()
        let data = try generator.generate(invoice: invoice)
        let s = String(data: data, encoding: .isoLatin1) ?? ""
        XCTAssertTrue(s.contains("/AFRelationship /Alternative"))
        XCTAssertTrue(s.contains("/EmbeddedFiles"))
        XCTAssertTrue(s.contains("factur-x.xml"))
        XCTAssertTrue(s.contains("/AF "))
        XCTAssertTrue(s.contains("urn:factur-x:pdfa:CrossIndustryDocument:invoice:1p0#"))
        XCTAssertTrue(s.contains("fx:ConformanceLevel>EN 16931"))
        XCTAssertTrue(s.contains("<pdfaid:part>3</pdfaid:part>"))
    }

    func testEmbeddedFilesNamesNotDoubleNested() throws {
        let invoice = sampleInvoice()
        let data = try FacturXGenerator().generate(invoice: invoice)
        let s = String(data: data, encoding: .isoLatin1) ?? ""
        XCTAssertFalse(s.contains("<< /Names << /EmbeddedFiles"),
                       "L'arbre Names ne doit pas être doublement enveloppé dans /Names.")
        XCTAssertTrue(s.contains("<< /EmbeddedFiles << /Names ["),
                     "La structure /Names /EmbeddedFiles doit être directement accessible.")
    }

    func testValidatorPassesOnValidInvoice() {
        let v = FacturXValidator().validate(invoice: sampleInvoice())
        XCTAssertTrue(v.isValid, "Erreurs inattendues : \(v.errors)")
        XCTAssertTrue(v.warnings.isEmpty || v.warnings.allSatisfy { !$0.contains("BT-49") && !$0.contains("BT-34") },
                      "Ne doit pas avertir sur BT-49/BT-34 si endpointID présent")
    }

    func testValidatorFailsOnEmptyInvoice() {
        let inv = Invoice(number: "", seller: InvoiceParty(name: "", street: "", postcode: "", city: ""),
                          buyer: InvoiceParty(name: "", street: "", postcode: "", city: ""))
        let v = FacturXValidator().validate(invoice: inv)
        XCTAssertFalse(v.isValid)
        XCTAssertTrue(v.errors.contains(where: { $0.contains("numéro de facture") }))
        XCTAssertTrue(v.errors.contains(where: { $0.contains("émetteur") }))
        XCTAssertTrue(v.errors.contains(where: { $0.contains("destinataire") }))
        XCTAssertTrue(v.errors.contains(where: { $0.contains("au moins une ligne") }))
    }

    func testValidatorFailsOnNegativePrice() {
        var inv = sampleInvoice()
        inv.lines[0].unitPrice = -50
        let v = FacturXValidator().validate(invoice: inv)
        XCTAssertFalse(v.isValid)
        XCTAssertTrue(v.errors.contains(where: { $0.contains("prix unitaire ne peut pas être négatif") }))
    }

    func testValidatorPDFDetectsFacturXAttachment() throws {
        let data = try FacturXGenerator().generate(invoice: sampleInvoice())
        let v = FacturXValidator().validate(pdf: data)
        XCTAssertTrue(v.isValid, "Erreurs PDF : \(v.errors)")
    }

    func testValidatorPDFFailsOnBarePDF() {
        let renderer = InvoicePDFRenderer()
        let pdf = renderer.render(invoice: sampleInvoice())
        let v = FacturXValidator().validate(pdf: pdf)
        XCTAssertFalse(v.isValid)
        XCTAssertTrue(v.errors.contains(where: { $0.contains("factur-x.xml") }))
        XCTAssertTrue(v.errors.contains(where: { $0.contains("/EmbeddedFiles") }))
    }

    private func makeDate(_ s: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.date(from: s)!
    }
}
