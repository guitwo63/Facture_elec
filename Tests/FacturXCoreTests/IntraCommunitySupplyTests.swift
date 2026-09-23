import XCTest
import FacturXCore

/// Livraison intracommunautaire (catégorie K) et pays de livraison (BT-80), corrigés le
/// 2026-09-23 après reproduction contre les validateurs officiels (XSD Factur-X 1.09 et
/// Schematron EN16931, EXTENDED et France CTC, exécutés via factur-x et saxonche) : le XML
/// de toute facture K était rejeté faute de BT-80 (BR-IC-12), et une facture K sans n° TVA
/// de l'une des parties (BR-IC-02) restait exportable.
final class IntraCommunitySupplyTests: XCTestCase {

    private let deliveryPath = "CrossIndustryInvoice/SupplyChainTradeTransaction/ApplicableHeaderTradeDelivery"

    // MARK: - Outils

    private func makeDate(_ s: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.date(from: s)!
    }

    private func intraCommunityLine() -> InvoiceLine {
        InvoiceLine(name: "Machine-outil", quantity: 1, unitPrice: 1000, vatRate: 0, vatCategory: .intraCommunity,
                    vatExemptionReason: "Exonération de TVA, article 262 ter I du CGI")
    }

    /// Vendeur français, acheteur allemand, une ligne K : conforme telle quelle aux trois
    /// validateurs officiels (vérifié le 2026-09-23).
    private func intraCommunityInvoice() -> Invoice {
        Invoice(
            number: "2026-0042",
            issueDate: makeDate("2026-09-01"),
            dueDate: makeDate("2026-09-30"),
            seller: InvoiceParty(name: "Mon Entreprise SARL", street: "12 rue du Commerce", postcode: "75001", city: "Paris",
                                 country: "FR", vatNumber: "FR44732829320", siren: "732829320"),
            buyer: InvoiceParty(name: "Kunde GmbH", street: "Hauptstrasse 1", postcode: "10115", city: "Berlin",
                                country: "DE", vatNumber: "DE123456789", endpointID: "DE123456789", endpointSchemeID: "9930"),
            lines: [intraCommunityLine()],
            billingMode: .b1
        )
    }

    private func xml(_ invoice: Invoice) throws -> String {
        String(decoding: try CIIXMLGenerator().generate(invoice: invoice), as: UTF8.self)
    }

    /// Élément désigné par un chemin de noms locaux (préfixes ignorés), ex. "A/B/C".
    private func element(_ xml: String, _ path: String, file: StaticString = #filePath, line: UInt = #line) throws -> XMLElement? {
        let doc = try XMLDocument(data: Data(xml.utf8))
        let steps = path.split(separator: "/").map { "*[local-name()='\($0)']" }
        let found = try doc.nodes(forXPath: "/" + steps.joined(separator: "/")).first as? XMLElement
        if found == nil { XCTFail("Élément introuvable : \(path)", file: file, line: line) }
        return found
    }

    private func childNames(_ element: XMLElement?) -> [String] {
        element?.children?.compactMap { ($0 as? XMLElement)?.localName } ?? []
    }

    private func rules(_ invoice: Invoice, _ ruleId: String) -> [BusinessRuleResult] {
        EN16931BusinessRules.evaluate(invoice: invoice).filter { $0.ruleId == ruleId }
    }

    // MARK: - BR-IC-12 : pays de livraison (BT-80) émis

    func testIntraCommunityInvoiceEmitsTheBuyerCountryAsDeliverToCountry() throws {
        let invoice = intraCommunityInvoice()
        XCTAssertNil(invoice.deliveryCountry, "rien de saisi")
        XCTAssertEqual(invoice.effectiveDeliveryCountry, "DE", "repli sur le pays de l'acheteur (BT-55)")

        let s = try xml(invoice)
        let shipTo = try element(s, deliveryPath + "/ShipToTradeParty")
        XCTAssertEqual(childNames(shipTo), ["PostalTradeAddress"])
        XCTAssertEqual(childNames(try element(s, deliveryPath + "/ShipToTradeParty/PostalTradeAddress")), ["CountryID"])
        XCTAssertEqual(try element(s, deliveryPath + "/ShipToTradeParty/PostalTradeAddress/CountryID")?.stringValue, "DE")
        XCTAssertTrue(FacturXValidator().validate(invoice: invoice).isValid)
    }

    func testEnteredDeliveryCountryReplacesTheBuyerCountry() throws {
        var invoice = intraCommunityInvoice()
        invoice.deliveryCountry = " at "
        XCTAssertEqual(invoice.optionalFields.map(\.tagName), ["ram:ShipToTradeParty/ram:PostalTradeAddress/ram:CountryID"],
                       "saisi comme champ optionnel d'en-tête du catalogue")
        XCTAssertEqual(OptionalFieldCatalogue.template(forTag: invoice.optionalFields[0].tagName, location: .header)?.bt, "BT-80")
        XCTAssertEqual(invoice.effectiveDeliveryCountry, "AT", "émis en majuscules, sans espaces")
        XCTAssertEqual(try element(try xml(invoice), deliveryPath + "/ShipToTradeParty/PostalTradeAddress/CountryID")?.stringValue, "AT")
        XCTAssertTrue(FacturXValidator().validate(invoice: invoice).isValid)
    }

    func testNoDeliverToPartyWithoutIntraCommunityLineOrEnteredCountry() throws {
        var invoice = intraCommunityInvoice()
        invoice.lines = [InvoiceLine(name: "Installation", quantity: 1, unitPrice: 200, vatRate: 20)]
        XCTAssertNil(invoice.effectiveDeliveryCountry)
        XCTAssertFalse(try xml(invoice).contains("ShipToTradeParty"), "hors catégorie K, BT-80 n'est émis que s'il est saisi")

        invoice.deliveryCountry = "BE"
        XCTAssertEqual(try element(try xml(invoice), deliveryPath + "/ShipToTradeParty/PostalTradeAddress/CountryID")?.stringValue, "BE")
    }

    /// BR-IC-11 (date de livraison BT-72 ou période) est respectée par la date de livraison
    /// toujours émise ; le livré à la précède, comme l'impose la séquence du XSD.
    func testDeliveryBlockFollowsTheXSDSequence() throws {
        var invoice = intraCommunityInvoice()
        invoice.deliveryCountry = "AT"
        invoice.despatchAdviceRef = "BL-2026-7"
        invoice.receivingAdviceRef = "BR-2026-9"
        XCTAssertEqual(childNames(try element(try xml(invoice), deliveryPath)), [
            "ShipToTradeParty", "ActualDeliverySupplyChainEvent", "DespatchAdviceReferencedDocument", "ReceivingAdviceReferencedDocument",
        ])
    }

    // MARK: - BR-IC-02 : n° de TVA de l'émetteur et de l'acheteur

    func testIntraCommunitySupplyRequiresBothVATNumbers() {
        XCTAssertTrue(rules(intraCommunityInvoice(), "BR-IC-02").isEmpty)

        var noBuyerVAT = intraCommunityInvoice()
        noBuyerVAT.buyer.vatNumber = nil
        var noSellerVAT = intraCommunityInvoice()
        noSellerVAT.seller.vatNumber = "  "
        var neither = noBuyerVAT
        neither.seller.vatNumber = ""
        for (invoice, missing) in [(noBuyerVAT, "celui de l'acheteur"), (noSellerVAT, "celui de l'émetteur"), (neither, "les deux")] {
            let found = rules(invoice, "BR-IC-02")
            XCTAssertEqual(found.map(\.severity), [.error], missing)
            XCTAssertTrue(found.first?.message.hasSuffix("il manque \(missing).") ?? false, found.first?.message ?? missing)
            XCTAssertFalse(FacturXValidator().validate(invoice: invoice).isValid, missing)
        }

        var extended = noBuyerVAT
        extended.profile = .extended
        XCTAssertEqual(rules(extended, "BR-IC-02").count, 1, "BR-IC-02 figure aussi dans le Schematron EXTENDED")
    }

    func testVATNumbersAreNotRequiredWithoutIntraCommunityLine() {
        var invoice = intraCommunityInvoice()
        invoice.lines = [InvoiceLine(name: "Installation", quantity: 1, unitPrice: 200, vatRate: 20)]
        invoice.buyer.vatNumber = nil
        XCTAssertTrue(rules(invoice, "BR-IC-02").isEmpty)
    }

    // MARK: - BR-CL-14 : code pays saisi

    func testEnteredDeliveryCountryMustBeAnISOCode() {
        for wrong in ["EL", "UK", "Allemagne", "D"] {
            var invoice = intraCommunityInvoice()
            invoice.deliveryCountry = wrong
            let found = rules(invoice, "BR-CL-14")
            XCTAssertEqual(found.map(\.severity), [.error], wrong)
            XCTAssertFalse(FacturXValidator().validate(invoice: invoice).isValid, wrong)
        }
        // Liste du Schematron : ISO 3166-1, plus 1A (Kosovo) et XI (Irlande du Nord).
        for accepted in ["GR", "gb", "XI", "1A"] {
            var invoice = intraCommunityInvoice()
            invoice.deliveryCountry = accepted
            XCTAssertTrue(rules(invoice, "BR-CL-14").isEmpty, accepted)
        }
        var standard = intraCommunityInvoice()
        standard.lines = [InvoiceLine(name: "Installation", quantity: 1, unitPrice: 200, vatRate: 20)]
        standard.deliveryCountry = "EL"
        XCTAssertEqual(rules(standard, "BR-CL-14").count, 1, "contrôlé dès qu'il est saisi, catégorie K ou non")
    }

    // MARK: - BT-80-UE : pays de livraison peu plausible pour une livraison intracommunautaire

    func testDeliveryToTheSellerCountryIsFlaggedWithoutBlocking() {
        var invoice = intraCommunityInvoice()
        invoice.buyer.country = "FR"
        invoice.buyer.vatNumber = "FR61987654321"
        let found = rules(invoice, "BT-80-UE")
        XCTAssertEqual(found.map(\.severity), [.warning])
        XCTAssertTrue(found.first?.message.contains("FR (pays de l'acheteur") ?? false, "le repli sur l'acheteur est explicité")
        XCTAssertTrue(FacturXValidator().validate(invoice: invoice).isValid, "avertissement seulement")

        invoice.deliveryCountry = "BE"
        XCTAssertTrue(rules(invoice, "BT-80-UE").isEmpty, "livraison saisie vers un autre État membre")
    }

    func testDeliveryOutsideTheEUIsFlaggedWithoutBlocking() {
        var invoice = intraCommunityInvoice()
        invoice.deliveryCountry = "CH"
        let found = rules(invoice, "BT-80-UE")
        XCTAssertEqual(found.map(\.severity), [.warning])
        XCTAssertTrue(found.first?.message.contains("catégorie G") ?? false)

        for member in ["DE", "GR", "XI"] {
            invoice.deliveryCountry = member
            XCTAssertTrue(rules(invoice, "BT-80-UE").isEmpty, member)
        }
    }

    // MARK: - Relecture (CIIXMLParser)

    func testParserReadsTheDeliverToCountryAndKeepsTheFollowingReferences() throws {
        var invoice = intraCommunityInvoice()
        invoice.deliveryCountry = "AT"
        invoice.despatchAdviceRef = "BL-2026-7"
        invoice.receivingAdviceRef = "BR-2026-9"
        let parsed = try CIIXMLParser().parse(xml: Data(try xml(invoice).utf8))
        XCTAssertEqual(parsed.deliveryCountry, "AT")
        XCTAssertEqual(parsed.despatchAdviceRef, "BL-2026-7", "lu après le livré à")
        XCTAssertEqual(parsed.receivingAdviceRef, "BR-2026-9", "lu après le livré à")
        XCTAssertEqual(parsed.buyer.name, "Kunde GmbH")
        XCTAssertEqual(parsed.buyer.city, "Berlin")
    }

    /// Livré à complet, tel qu'un fournisseur peut l'émettre : ses nom, adresse et contact ne
    /// doivent rien écraser de l'acheteur, ni faire perdre les références qui le suivent.
    func testParserIgnoresTheDeliverToPartyDetails() throws {
        var invoice = intraCommunityInvoice()
        invoice.deliveryCountry = "AT"
        invoice.despatchAdviceRef = "BL-2026-7"
        let richShipTo = """
          <ram:ShipToTradeParty>
            <ram:ID>ENTREPOT-3</ram:ID>
            <ram:Name>Entrepôt de Linz</ram:Name>
            <ram:DefinedTradeContact>
              <ram:PersonName>Réception</ram:PersonName>
            </ram:DefinedTradeContact>
            <ram:PostalTradeAddress>
              <ram:PostcodeCode>4020</ram:PostcodeCode>
              <ram:LineOne>Hafenstrasse 5</ram:LineOne>
              <ram:CityName>Linz</ram:CityName>
              <ram:CountryID>AT</ram:CountryID>
            </ram:PostalTradeAddress>
            <ram:SpecifiedTaxRegistration>
              <ram:ID schemeID="VA">ATU12345678</ram:ID>
            </ram:SpecifiedTaxRegistration>
          </ram:ShipToTradeParty>
"""
        let original = try xml(invoice)
        let shipToStart = try XCTUnwrap(original.range(of: "          <ram:ShipToTradeParty>"))
        let shipToEnd = try XCTUnwrap(original.range(of: "</ram:ShipToTradeParty>\n"))
        let received = original.replacingCharacters(in: shipToStart.lowerBound..<shipToEnd.upperBound, with: richShipTo)

        let parsed = try CIIXMLParser().parse(xml: Data(received.utf8))
        XCTAssertEqual(parsed.deliveryCountry, "AT")
        XCTAssertEqual(parsed.despatchAdviceRef, "BL-2026-7")
        XCTAssertEqual(parsed.buyer.name, "Kunde GmbH")
        XCTAssertEqual(parsed.buyer.street, "Hauptstrasse 1")
        XCTAssertEqual(parsed.buyer.vatNumber, "DE123456789")
        XCTAssertNil(parsed.buyer.contactName)
    }

    /// Livré à de ligne (profil EXTENDED) : ignoré, sans perturber la lecture de la ligne.
    func testParserSkipsALineLevelDeliverToParty() throws {
        let original = try xml(intraCommunityInvoice())
        let lineShipTo = """
</ram:BilledQuantity>
            <ram:ShipToTradeParty>
              <ram:Name>Chantier</ram:Name>
              <ram:PostalTradeAddress><ram:CountryID>IT</ram:CountryID></ram:PostalTradeAddress>
            </ram:ShipToTradeParty>
"""
        XCTAssertTrue(original.contains("</ram:BilledQuantity>"))
        let received = original.replacingOccurrences(of: "</ram:BilledQuantity>", with: lineShipTo)

        let parsed = try CIIXMLParser().parse(xml: Data(received.utf8))
        XCTAssertEqual(parsed.deliveryCountry, "DE", "seul le livré à d'en-tête est le BT-80")
        XCTAssertEqual(parsed.lines.count, 1)
        XCTAssertEqual(parsed.lines.first?.vatCategory, .intraCommunity)
        XCTAssertEqual(parsed.lines.first?.unitPrice, 1000)
        XCTAssertEqual(parsed.buyer.name, "Kunde GmbH")
    }
}
