import XCTest
import FacturXCore

final class OrderXCoreTests: XCTestCase {

    private func sampleOrder() -> SalesOrder {
        SalesOrder(
            number: "CD2026-0001",
            type: .order,
            issueDate: makeDate("2026-09-01"),
            requestedDeliveryDate: makeDate("2026-09-15"),
            currency: "EUR",
            profile: .comfort,
            buyer: InvoiceParty(
                name: "Société Exemple SAS",
                street: "8 avenue des Champs",
                postcode: "75008",
                city: "Paris",
                country: "FR",
                siren: "987654321",
                endpointID: "987654321",
                endpointSchemeID: "0225"
            ),
            seller: InvoiceParty(
                name: "Mon Entreprise SARL",
                street: "12 rue du Commerce",
                postcode: "75001",
                city: "Paris",
                country: "FR",
                vatNumber: "FR12345678901",
                siren: "123456789",
                contactEmail: "contact@monentreprise.fr",
                endpointID: "123456789",
                endpointSchemeID: "0225"
            ),
            buyerReference: "ACHAT-REF-42",
            lines: [
                InvoiceLine(name: "Licence logicielle", quantity: 2, unit: "C62", unitPrice: 600, vatRate: 20),
                InvoiceLine(name: "Support technique", quantity: 10, unit: "HUR", unitPrice: 90, vatRate: 20)
            ],
            requestedResponseTypeCode: "AC"
        )
    }

    func testOrderTotals() {
        let order = sampleOrder()
        XCTAssertEqual(order.lineTotal, 2100.00, accuracy: 0.001)
        XCTAssertEqual(order.taxTotal, 420.00, accuracy: 0.001)
        XCTAssertEqual(order.grandTotal, 2520.00, accuracy: 0.001)
    }

    /// `SalesOrder.seller` = notre société, comme Devis/Facture : la conversion
    /// ne doit plus permuter les parties (contrairement à avant l'inversion du
    /// modèle, où `buyer` désignait notre société sur la commande).
    func testToInvoiceKeepsSellerAndBuyerAsIs() {
        let order = sampleOrder()
        let invoice = order.toInvoice(number: "FAC-0001")
        XCTAssertEqual(invoice.seller.name, order.seller.name)
        XCTAssertEqual(invoice.buyer.name, order.buyer.name)
        XCTAssertEqual(invoice.paymentIBAN, order.seller.iban)
        XCTAssertEqual(invoice.paymentTerms, order.seller.paymentTerms)
    }

    func testXMLContainsOrderXURN() throws {
        let xml = try OrderCIOXMLGenerator().generate(order: sampleOrder())
        let s = String(data: xml, encoding: .utf8) ?? ""
        XCTAssertTrue(s.contains("urn:order-x.eu:1p0:comfort"))
        XCTAssertTrue(s.contains("<rsm:SCRDMCCBDACIOMessageStructure"))
        XCTAssertTrue(s.contains("factur-x") == false)
        XCTAssertTrue(s.contains("AFRelationship") == false)
    }

    func testXMLUsesCIONamespaces() throws {
        let xml = try OrderCIOXMLGenerator().generate(order: sampleOrder())
        let s = String(data: xml, encoding: .utf8) ?? ""
        XCTAssertTrue(s.contains("xmlns:rsm=\"urn:un:unece:uncefact:data:SCRDMCCBDACIOMessageStructure:100\""))
        XCTAssertTrue(s.contains("xmlns:ram=\"urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:128\""))
        XCTAssertTrue(s.contains("xmlns:udt=\"urn:un:unece:uncefact:data:standard:UnqualifiedDataType:128\""))
    }

    func testXMLStructureRequiredElements() throws {
        let xml = try OrderCIOXMLGenerator().generate(order: sampleOrder())
        let s = String(data: xml, encoding: .utf8) ?? ""
        XCTAssertTrue(s.contains("<ram:ID>CD2026-0001</ram:ID>"))
        XCTAssertTrue(s.contains("<ram:TypeCode>220</ram:TypeCode>"))
        XCTAssertTrue(s.contains("format=\"102\">20260901<"))
        XCTAssertTrue(s.contains("<ram:OrderCurrencyCode>EUR</ram:OrderCurrencyCode>"))
        XCTAssertTrue(s.contains("<ram:RequestedQuantity unitCode=\"C62\">2.0000"))
        XCTAssertTrue(s.contains("<ram:RequestedResponseTypeCode>AC</ram:RequestedResponseTypeCode>"))
        XCTAssertTrue(s.contains("<ram:BuyerReference>ACHAT-REF-42</ram:BuyerReference>"))
        XCTAssertTrue(s.contains("RequestedDeliverySupplyChainEvent"))
        XCTAssertTrue(s.contains("format=\"102\">20260915<"))
    }

    func testXMLNoInvoiceElements() throws {
        let xml = try OrderCIOXMLGenerator().generate(order: sampleOrder())
        let s = String(data: xml, encoding: .utf8) ?? ""
        XCTAssertFalse(s.contains("BilledQuantity"), "Order-X utilise RequestedQuantity, pas BilledQuantity")
        XCTAssertFalse(s.contains("InvoiceCurrencyCode"), "Order-X utilise OrderCurrencyCode")
        XCTAssertFalse(s.contains("DuePayableAmount"), "Order-X n'a pas de DuePayableAmount")
        XCTAssertFalse(s.contains("ActualDeliverySupplyChainEvent"), "Order-X utilise RequestedDeliverySupplyChainEvent")
    }

    func testXMLContainsEndpointIDs() throws {
        let xml = try OrderCIOXMLGenerator().generate(order: sampleOrder())
        let s = String(data: xml, encoding: .utf8) ?? ""
        XCTAssertTrue(s.contains("<ram:URIUniversalCommunication>"))
        XCTAssertTrue(s.contains("schemeID=\"0225\">123456789<"))
        XCTAssertTrue(s.contains("schemeID=\"0225\">987654321<"))
    }

    func testXMLNoEmptyPersonName() throws {
        var order = sampleOrder()
        order.buyer = InvoiceParty(
            name: "Test", street: "", postcode: "", city: "",
            contactName: "   ", contactEmail: "achats@monentreprise.fr"
        )
        let xml = try OrderCIOXMLGenerator().generate(order: order)
        let s = String(data: xml, encoding: .utf8) ?? ""
        XCTAssertFalse(s.contains("<ram:PersonName></ram:PersonName>"))
        XCTAssertTrue(s.contains("DefinedTradeContact"))
    }

    func testEmbedProducesOrderXWithAttachment() throws {
        let order = sampleOrder()
        let generator = OrderXGenerator()
        let data = try generator.generate(order: order)
        let s = String(data: data, encoding: .isoLatin1) ?? ""
        XCTAssertTrue(s.contains("/AFRelationship /Alternative"))
        XCTAssertTrue(s.contains("/EmbeddedFiles"))
        XCTAssertTrue(s.contains("order-x.xml"))
        XCTAssertTrue(s.contains("/AF "))
        XCTAssertTrue(s.contains("urn:factur-x:pdfa:CrossIndustryDocument:1p0#"))
        XCTAssertTrue(s.contains("fx:DocumentType>ORDER"))
        XCTAssertTrue(s.contains("fx:DocumentFileName>order-x.xml"))
        XCTAssertTrue(s.contains("fx:ConformanceLevel>COMFORT"))
        XCTAssertTrue(s.contains("<pdfaid:part>3</pdfaid:part>"))
    }

    func testEmbeddedFilesNamesNotDoubleNested() throws {
        let order = sampleOrder()
        let data = try OrderXGenerator().generate(order: order)
        let s = String(data: data, encoding: .isoLatin1) ?? ""
        XCTAssertFalse(s.contains("<< /Names << /EmbeddedFiles"),
                       "L'arbre Names ne doit pas être doublement enveloppé dans /Names.")
        XCTAssertTrue(s.contains("<< /EmbeddedFiles << /Names ["),
                     "La structure /Names /EmbeddedFiles doit être directement accessible.")
    }

    func testValidatorPassesOnValidOrder() {
        let v = OrderXValidator().validate(order: sampleOrder())
        XCTAssertTrue(v.isValid, "Erreurs inattendues : \(v.errors)")
    }

    func testValidatorFailsOnEmptyOrder() {
        let order = SalesOrder(number: "", buyer: InvoiceParty(name: "", street: "", postcode: "", city: ""),
                               seller: InvoiceParty(name: "", street: "", postcode: "", city: ""))
        let v = OrderXValidator().validate(order: order)
        XCTAssertFalse(v.isValid)
        XCTAssertTrue(v.errors.contains(where: { $0.contains("numéro de commande") }))
        XCTAssertTrue(v.errors.contains(where: { $0.contains("acheteur") }))
        XCTAssertTrue(v.errors.contains(where: { $0.contains("société émettrice") }))
        XCTAssertTrue(v.errors.contains(where: { $0.contains("au moins une ligne") }))
    }

    func testValidatorFailsOnNegativePrice() {
        var order = sampleOrder()
        order.lines[0].unitPrice = -50
        let v = OrderXValidator().validate(order: order)
        XCTAssertFalse(v.isValid)
        XCTAssertTrue(v.errors.contains(where: { $0.contains("prix unitaire ne peut pas être négatif") }))
    }

    func testValidatorPDFOrderDetectsAttachment() throws {
        let data = try OrderXGenerator().generate(order: sampleOrder())
        let v = OrderXValidator().validate(pdf: data)
        XCTAssertTrue(v.isValid, "Erreurs PDF : \(v.errors)")
    }

    func testValidatorPDFFailsOnBarePDF() {
        let renderer = OrderPDFRenderer()
        let pdf = renderer.render(order: sampleOrder())
        let v = OrderXValidator().validate(pdf: pdf)
        XCTAssertFalse(v.isValid)
        XCTAssertTrue(v.errors.contains(where: { $0.contains("order-x.xml") }))
        XCTAssertTrue(v.errors.contains(where: { $0.contains("/EmbeddedFiles") }))
    }

    private func makeDate(_ s: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.date(from: s)!
    }
}
