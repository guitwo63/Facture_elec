import XCTest
import FacturXCore

/// Le test le plus fort de ce fichier est le round-trip `CIIXMLGenerator` → `CIIXMLParser` :
/// toute régression de fidélité du modèle `Invoice` à travers la sérialisation CII le fait
/// échouer immédiatement.
final class CIIXMLParserTests: XCTestCase {

    private func makeDate(_ s: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.date(from: s)!
    }

    private func richInvoice() -> Invoice {
        var invoice = Invoice(
            number: "SUP-2026-0042",
            type: .commercialInvoice,
            issueDate: makeDate("2026-09-01"),
            dueDate: makeDate("2026-09-30"),
            currency: "EUR",
            profile: .en16931,
            seller: InvoiceParty(
                name: "Fournisseur Test SARL",
                street: "12 rue du Commerce",
                postcode: "75001",
                city: "Paris",
                country: "FR",
                vatNumber: "FR12345678901",
                siren: "123456789",
                contactName: "Marie Dupont",
                contactEmail: "marie@fournisseur-test.fr",
                contactPhone: "+33102030405",
                endpointID: "123456789",
                endpointSchemeID: "0225"
            ),
            buyer: InvoiceParty(
                name: "Notre Société SAS",
                street: "8 avenue des Champs",
                postcode: "75008",
                city: "Paris",
                country: "FR",
                siren: "987654321",
                endpointID: "987654321",
                endpointSchemeID: "0225"
            ),
            buyerReference: "CLIENT-REF-42",
            purchaseOrderRef: "BC-2026-100",
            lines: [
                InvoiceLine(name: "Prestation de conseil", quantity: 2, unit: "DAY", unitPrice: 600, vatRate: 20,
                            optionalFields: [
                                OptionalField(tagName: "ram:GlobalID", value: "3017620422003"),
                                OptionalField(tagName: "ram:SellerAssignedID", value: "ART-V-12"),
                                OptionalField(tagName: "ram:BuyerAssignedID", value: "ART-A-34"),
                                OptionalField(tagName: "ram:BuyerOrderReferencedDocument/ram:LineID", value: "10"),
                            ]),
                InvoiceLine(name: "Export hors UE", quantity: 1, unit: "C62", unitPrice: 300, vatRate: 0, vatCategory: .export, vatExemptionReason: "Exportation hors UE — art. 262 I du CGI")
            ],
            paymentIBAN: "FR7630006000011234567890189",
            paymentBIC: "AGRIFRPP",
            paymentTerms: "Paiement à 30 jours",
            notes: "Merci de votre confiance",
            billingMode: .m1,
            legalNotePMT: "Pénalité forfaitaire de 40 EUR",
            legalNotePMD: "Taux légal x3",
            legalNoteAAB: "Pas d'escompte"
        )
        invoice.contractRef = "CONTRAT-2026-7"
        invoice.tenderRef = "AO-2026-3"
        invoice.receivingAdviceRef = "BR-2026-1"
        invoice.despatchAdviceRef = "BL-2026-1"
        return invoice
    }

    func testRoundTripPreservesEveryField() throws {
        let original = richInvoice()
        let xml = try CIIXMLGenerator().generate(invoice: original)
        let parsed = try CIIXMLParser().parse(xml: xml)

        XCTAssertEqual(parsed.number, original.number)
        XCTAssertEqual(parsed.type, original.type)
        XCTAssertEqual(parsed.currency, original.currency)
        XCTAssertEqual(parsed.profile, original.profile)
        XCTAssertEqual(parsed.billingMode, original.billingMode)
        XCTAssertEqual(parsed.issueDate.timeIntervalSince1970, original.issueDate.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(parsed.dueDate.timeIntervalSince1970, original.dueDate.timeIntervalSince1970, accuracy: 1)

        XCTAssertEqual(parsed.seller.name, original.seller.name)
        XCTAssertEqual(parsed.seller.street, original.seller.street)
        XCTAssertEqual(parsed.seller.postcode, original.seller.postcode)
        XCTAssertEqual(parsed.seller.city, original.seller.city)
        XCTAssertEqual(parsed.seller.country, original.seller.country)
        XCTAssertEqual(parsed.seller.siren, original.seller.siren)
        XCTAssertEqual(parsed.seller.vatNumber, original.seller.vatNumber)
        XCTAssertEqual(parsed.seller.contactName, original.seller.contactName)
        XCTAssertEqual(parsed.seller.contactEmail, original.seller.contactEmail)
        XCTAssertEqual(parsed.seller.contactPhone, original.seller.contactPhone)
        XCTAssertEqual(parsed.seller.endpointID, original.seller.endpointID)

        XCTAssertEqual(parsed.buyer.name, original.buyer.name)
        XCTAssertEqual(parsed.buyer.siren, original.buyer.siren)
        XCTAssertEqual(parsed.buyer.endpointID, original.buyer.endpointID)

        XCTAssertEqual(parsed.buyerReference, original.buyerReference)
        XCTAssertEqual(parsed.purchaseOrderRef, original.purchaseOrderRef)
        XCTAssertEqual(parsed.contractRef, original.contractRef)
        XCTAssertEqual(parsed.tenderRef, original.tenderRef)
        XCTAssertEqual(parsed.receivingAdviceRef, original.receivingAdviceRef)
        XCTAssertEqual(parsed.despatchAdviceRef, original.despatchAdviceRef)

        XCTAssertEqual(parsed.paymentIBAN, original.paymentIBAN)
        XCTAssertEqual(parsed.paymentBIC, original.paymentBIC)
        XCTAssertEqual(parsed.paymentTerms, original.paymentTerms)
        XCTAssertEqual(parsed.notes, original.notes)
        XCTAssertEqual(parsed.legalNotePMT, original.legalNotePMT)
        XCTAssertEqual(parsed.legalNotePMD, original.legalNotePMD)
        XCTAssertEqual(parsed.legalNoteAAB, original.legalNoteAAB)

        XCTAssertEqual(parsed.lines.count, original.lines.count)
        XCTAssertEqual(parsed.lines[0].name, original.lines[0].name)
        XCTAssertEqual(parsed.lines[0].quantity, original.lines[0].quantity, accuracy: 0.0001)
        XCTAssertEqual(parsed.lines[0].unit, original.lines[0].unit)
        XCTAssertEqual(parsed.lines[0].unitPrice, original.lines[0].unitPrice, accuracy: 0.0001)
        XCTAssertEqual(parsed.lines[0].vatRate, original.lines[0].vatRate, accuracy: 0.0001)
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: parsed.lines[0].optionalFields.map { ($0.tagName, $0.value) }),
            Dictionary(uniqueKeysWithValues: original.lines[0].optionalFields.map { ($0.tagName, $0.value) })
        )

        XCTAssertEqual(parsed.lines[1].vatCategory, .export)
        XCTAssertEqual(parsed.lines[1].vatExemptionReason, original.lines[1].vatExemptionReason)

        XCTAssertEqual(parsed.lineTotal, original.lineTotal, accuracy: 0.01)
        XCTAssertEqual(parsed.grandTotal, original.grandTotal, accuracy: 0.01)
    }

    func testMalformedXMLThrowsRatherThanCrashing() {
        let malformed = "<not-even-xml".data(using: .utf8)!
        XCTAssertThrowsError(try CIIXMLParser().parse(xml: malformed)) { error in
            XCTAssertEqual(error as? CIIXMLParserError, .invalidXML)
        }
    }

    func testMissingInvoiceNumberThrows() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rsm:CrossIndustryInvoice xmlns:rsm="urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100" xmlns:ram="urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100">
          <rsm:ExchangedDocument></rsm:ExchangedDocument>
          <rsm:SupplyChainTradeTransaction></rsm:SupplyChainTradeTransaction>
        </rsm:CrossIndustryInvoice>
        """.data(using: .utf8)!
        XCTAssertThrowsError(try CIIXMLParser().parse(xml: xml)) { error in
            guard case .missingRequiredField = error as? CIIXMLParserError else {
                return XCTFail("attendu .missingRequiredField, obtenu \(error)")
            }
        }
    }

    /// Un `ram:TypeCode` hors des 4 cas connus (le flux FR EN16931 en accepte 16 au total —
    /// voir `CIIXMLGenerator.xmlTypeCode`) ne doit ni planter ni être silencieusement perdu.
    func testUnmappedTypeCodeFallsBackAndPreservesOriginalValue() throws {
        var invoice = richInvoice()
        invoice.type = .commercialInvoice
        let xml = try CIIXMLGenerator().generate(invoice: invoice)
        guard var xmlString = String(data: xml, encoding: .utf8) else { return XCTFail() }
        xmlString = xmlString.replacingOccurrences(of: "<ram:TypeCode>380</ram:TypeCode>", with: "<ram:TypeCode>389</ram:TypeCode>")
        let patched = xmlString.data(using: .utf8)!

        let parsed = try CIIXMLParser().parse(xml: patched)
        XCTAssertEqual(parsed.type, .commercialInvoice, "repli par défaut pour un code non mappé")
        XCTAssertEqual(parsed.optionalFields.first { $0.tagName == "ram:TypeCode" }?.value, "389", "le code d'origine doit être conservé, pas perdu")
    }

    func testDeclaredVsRecomputedTotalMismatchIsSurfacedAsAWarningNotAnError() throws {
        let invoice = richInvoice()
        let xml = try CIIXMLGenerator().generate(invoice: invoice)
        guard var xmlString = String(data: xml, encoding: .utf8) else { return XCTFail() }
        // Falsifie le total TTC déclaré pour simuler un document incohérent (saisie
        // manuelle erronée côté fournisseur, ou XML corrompu).
        let grandTotalPattern = "<ram:GrandTotalAmount>\(String(format: "%.2f", invoice.grandTotal))</ram:GrandTotalAmount>"
        XCTAssertTrue(xmlString.contains(grandTotalPattern), "le total attendu doit être présent dans le XML généré pour que ce test soit valide")
        xmlString = xmlString.replacingOccurrences(of: grandTotalPattern, with: "<ram:GrandTotalAmount>999999.99</ram:GrandTotalAmount>")
        let patched = xmlString.data(using: .utf8)!

        let (parsed, warnings) = try CIIXMLParser().parseWithWarnings(xml: patched)
        XCTAssertFalse(warnings.isEmpty, "un écart de total déclaré doit être signalé")
        XCTAssertEqual(parsed.grandTotal, invoice.grandTotal, accuracy: 0.01, "le total recalculé reste correct malgré la valeur déclarée falsifiée — l'avertissement ne doit jamais bloquer le parse")
    }

    func testMatchingDeclaredTotalsProduceNoWarning() throws {
        let invoice = richInvoice()
        let xml = try CIIXMLGenerator().generate(invoice: invoice)
        let (_, warnings) = try CIIXMLParser().parseWithWarnings(xml: xml)
        XCTAssertTrue(warnings.isEmpty)
    }

    func testParseDepositedFileDetectsBareXML() throws {
        let invoice = richInvoice()
        let xml = try CIIXMLGenerator().generate(invoice: invoice)
        let parsed = try CIIXMLParser.parseDepositedFile(xml)
        XCTAssertEqual(parsed.number, invoice.number)
    }
}
