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
                contactEmail: "contact@exemple.fr",
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

    func testExportInvoiceCSVContainsHeaderAndData() {
        let csv = ExportGenerator().invoiceCSV([sampleInvoice()])
        XCTAssertTrue(csv.contains("Numéro;Type;Statut"))
        XCTAssertTrue(csv.contains("2026-0001"))
        XCTAssertTrue(csv.contains("Mon Entreprise SARL"))
        XCTAssertTrue(csv.contains("Client Exemple SAS"))
        XCTAssertTrue(csv.contains("1620.00"))
    }

    func testExportInvoiceLinesCSVContainsLines() {
        let csv = ExportGenerator().invoiceLinesCSV([sampleInvoice()])
        XCTAssertTrue(csv.contains("N° facture;Type"))
        XCTAssertTrue(csv.contains("Prestation de conseil"))
        XCTAssertTrue(csv.contains("Frais de déplacement"))
    }

    func testExportWriteCSVBeginsWithBOM() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("export-bom-\(UUID().uuidString).csv")
        try ExportGenerator().writeCSV("Numéro;Type\r\nA;B", to: tmp)
        let data = try Data(contentsOf: tmp)
        XCTAssertEqual(data.prefix(3), Data([0xEF, 0xBB, 0xBF]))
        try? FileManager.default.removeItem(at: tmp)
    }

    func testExportOrderCSVContainsHeaderAndData() {
        let order = SalesOrder(
            number: "CMD-001",
            buyer: InvoiceParty(name: "Acheteur SARL", street: "1 rue A", postcode: "75001", city: "Paris", country: "FR"),
            seller: InvoiceParty(name: "Client SAS", street: "2 rue B", postcode: "75002", city: "Paris", country: "FR"),
            lines: [InvoiceLine(name: "Article A", quantity: 3, unitPrice: 100, vatRate: 20)]
        )
        let csv = ExportGenerator().orderCSV([order])
        XCTAssertTrue(csv.contains("Numéro;Type;Statut"))
        XCTAssertTrue(csv.contains("CMD-001"))
        XCTAssertTrue(csv.contains("Acheteur SARL"))
        XCTAssertTrue(csv.contains("Client SAS"))
        XCTAssertTrue(csv.contains("360.00"))
    }

    func testExportDirectoryCSVContainsEntry() {
        let entry = DirectoryEntry(
            kinds: [.client],
            party: InvoiceParty(name: "Test SARL", street: "1 rue X", postcode: "75001", city: "Paris", country: "FR", vatNumber: "FR11111111111", siren: "111111111"),
            note: "note test",
            contacts: [PartyContact(name: "Jean", email: "j@x.fr", phone: "0102", isActive: true, isDefault: true)]
        )
        let csv = ExportGenerator().directoryCSV([entry])
        XCTAssertTrue(csv.contains("Raison sociale;Type;SIREN"))
        XCTAssertTrue(csv.contains("Test SARL"))
        XCTAssertTrue(csv.contains("111111111"))
        XCTAssertTrue(csv.contains("Jean"))
    }

    func testImportDirectoryCSVParsesEntries() {
        let csv = "Raison sociale;SIREN;Ville;Contact (email)\r\nAlpha SARL;222222222;Lyon;a@x.fr\r\nBeta;333333333;Nice;\r\n;444444444;Paris;\r\n"
        let res = ExportGenerator().parseDirectoryCSV(csv)
        XCTAssertEqual(res.entries.count, 2)
        XCTAssertEqual(res.entries[0].party.name, "Alpha SARL")
        XCTAssertEqual(res.entries[0].party.siren, "222222222")
        XCTAssertEqual(res.entries[0].party.city, "Lyon")
        XCTAssertEqual(res.entries[0].defaultContact?.email, "a@x.fr")
        XCTAssertEqual(res.entries[1].party.name, "Beta")
        XCTAssertEqual(res.errors.count, 1)
    }

    func testImportDirectoryCSVMissingColumns() {
        let csv = "Nom;Ville\r\nAlpha;Lyon\r\n"
        let res = ExportGenerator().parseDirectoryCSV(csv)
        XCTAssertTrue(res.entries.isEmpty)
        XCTAssertFalse(res.errors.isEmpty)
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

    func testXMLOptionalFieldsHeaderAndLine() throws {
        var inv = sampleInvoice()
        inv.optionalFields = [
            OptionalField(tagName: "ram:SpecifiedProcuringProject/ram:ID", value: "PROJ-2026-42"),
        ]
        inv.lines[0].optionalFields = [
            OptionalField(tagName: "ram:GlobalID", value: "3017620422003"),
            OptionalField(tagName: "ram:BuyerOrderReferencedDocument/ram:LineID", value: "7"),
        ]
        let xml = try CIIXMLGenerator().generate(invoice: inv)
        let s = String(data: xml, encoding: .utf8) ?? ""
        XCTAssertTrue(s.contains("<ram:SpecifiedProcuringProject>"))
        XCTAssertTrue(s.contains("<ram:ID>PROJ-2026-42</ram:ID>"))
        XCTAssertTrue(s.contains("<ram:GlobalID schemeID=\"0160\">3017620422003</ram:GlobalID>"))
        XCTAssertTrue(s.contains("<ram:BuyerOrderReferencedDocument>"))
        XCTAssertTrue(s.contains("<ram:LineID>7</ram:LineID>"))
    }

    func testXMLHeaderReferencesViaOptionalFields() throws {
        var inv = sampleInvoice()
        inv.optionalFields = [
            OptionalField(tagName: "ram:ContractReferencedDocument/ram:IssuerAssignedID", value: "CT-2026-1"),
            OptionalField(tagName: "ram:AdditionalReferencedDocument/ram:IssuerAssignedID", value: "AO-42"),
            OptionalField(tagName: "ram:ReceivingAdviceReferencedDocument/ram:IssuerAssignedID", value: "BR-7"),
            OptionalField(tagName: "ram:DespatchAdviceReferencedDocument/ram:IssuerAssignedID", value: "BL-9"),
        ]
        let xml = try CIIXMLGenerator().generate(invoice: inv)
        let s = String(data: xml, encoding: .utf8) ?? ""
        XCTAssertTrue(s.contains("<ram:ContractReferencedDocument>"))
        XCTAssertTrue(s.contains("<ram:IssuerAssignedID>CT-2026-1</ram:IssuerAssignedID>"))
        XCTAssertTrue(s.contains("<ram:AdditionalReferencedDocument>"))
        XCTAssertTrue(s.contains("<ram:IssuerAssignedID>AO-42</ram:IssuerAssignedID>"))
        XCTAssertTrue(s.contains("<ram:TypeCode>50</ram:TypeCode>"))
        XCTAssertTrue(s.contains("<ram:ReceivingAdviceReferencedDocument>"))
        XCTAssertTrue(s.contains("<ram:IssuerAssignedID>BR-7</ram:IssuerAssignedID>"))
        XCTAssertTrue(s.contains("<ram:DespatchAdviceReferencedDocument>"))
        XCTAssertTrue(s.contains("<ram:IssuerAssignedID>BL-9</ram:IssuerAssignedID>"))
    }

    func testXMLNoEmptyPersonName() throws {
        var inv = sampleInvoice()
        inv.seller = InvoiceParty(
            name: "Test", street: "", postcode: "", city: "",
            contactName: "   ", contactEmail: "contact@exemple.fr"
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

    /// Ce jour-là dans le fuseau de l'app, comme une date saisie dans l'éditeur.
    private func makeDate(_ s: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)!
    }

    func testBusinessRulesPassOnValidInvoice() {
        let rules = EN16931BusinessRules.evaluate(invoice: sampleInvoice())
        let failing = rules.filter { $0.severity == .error }
        XCTAssertTrue(failing.isEmpty, "BR en erreur inattendues : \(failing.map { $0.message })")
    }

    func testBusinessRulesCreditNoteRequiresPrecedingRef() {
        var inv = sampleInvoice()
        inv.type = .creditNote
        inv.precedingInvoiceRef = nil
        inv.precedingInvoiceDate = nil
        let rules = EN16931BusinessRules.evaluate(invoice: inv)
        XCTAssertTrue(rules.contains { $0.ruleId == "BR-FR-CO-05" && $0.severity == .error },
                     "BR-FR-CO-05 doit signaler l'absence de référence pour un avoir")
    }

    func testBusinessRulesTotalsCoherence() {
        var inv = sampleInvoice()
        inv.lines.append(InvoiceLine(name: "Ligne test", quantity: 1, unit: "C62", unitPrice: 100, vatRate: 20))
        let rules = EN16931BusinessRules.evaluate(invoice: inv)
        XCTAssertFalse(rules.contains { $0.ruleId == "BR-CO-10" && $0.severity == .error },
                       "BR-CO-10 ne doit pas remonter si la somme des lignes est cohérente")
    }

    func testLuhnValidSiren() {
        XCTAssertTrue(SireneValidator.isValidSiren("732829320"))
        XCTAssertFalse(SireneValidator.isValidSiren("732829321"))
        XCTAssertFalse(SireneValidator.isValidSiren("123"))
        XCTAssertFalse(SireneValidator.isValidSiren(nil))
    }

    func testLuhnValidSiret() {
        XCTAssertTrue(SireneValidator.isValidSiret("73282932000074"))
        XCTAssertFalse(SireneValidator.isValidSiret("73282932000075"))
        XCTAssertFalse(SireneValidator.isValidSiret("732829320"))
        XCTAssertFalse(SireneValidator.isValidSiret(nil))
    }

    // MARK: - IBAN

    func testIBANValid() {
        XCTAssertTrue(IBANValidator.isValid("FR7630006000011234567890189"))
        XCTAssertTrue(IBANValidator.isValid("FR76 3000 6000 0112 3456 7890 189"))
        XCTAssertTrue(IBANValidator.isValid("DE89370400440532013000"))
        XCTAssertTrue(IBANValidator.isValid("GB82WEST12345698765432"))
    }

    func testIBANInvalid() {
        XCTAssertFalse(IBANValidator.isValid("FR7630006000011234567890188"))
        XCTAssertFalse(IBANValidator.isValid("FR763000600"))
        XCTAssertFalse(IBANValidator.isValid(nil))
        XCTAssertFalse(IBANValidator.isValid(""))
        XCTAssertFalse(IBANValidator.isValid("XX7630006000011234567890189"))
    }

    func testIBANFormatted() {
        XCTAssertEqual(IBANValidator.formatted("FR7630006000011234567890189"),
                       "FR76 3000 6000 0112 3456 7890 189")
        XCTAssertEqual(IBANValidator.formatted(nil), "")
    }

    func testIBANCountryCode() {
        XCTAssertEqual(IBANValidator.countryCode("FR7630006000011234567890189"), "FR")
        XCTAssertEqual(IBANValidator.countryCode("de89370400440532013000"), "DE")
        XCTAssertNil(IBANValidator.countryCode("F"))
    }

    // MARK: - Règles métier renforcées

    func testBusinessRulesInvalidIBAN() {
        var inv = sampleInvoice()
        inv.paymentIBAN = "FR7630006000011234567890188"
        let rules = EN16931BusinessRules.evaluate(invoice: inv)
        XCTAssertTrue(rules.contains { $0.ruleId == "BT-84-IBAN" && $0.severity == .error },
                     "BT-84-IBAN doit remonter une erreur pour un IBAN à clé invalide")
    }

    func testBusinessRulesInvalidSiren() {
        var inv = sampleInvoice()
        inv.seller = InvoiceParty(
            name: inv.seller.name, street: inv.seller.street, postcode: inv.seller.postcode,
            city: inv.seller.city, country: inv.seller.country, vatNumber: inv.seller.vatNumber,
            siren: "123456780", contactEmail: inv.seller.contactEmail,
            endpointID: inv.seller.endpointID, endpointSchemeID: inv.seller.endpointSchemeID
        )
        let rules = EN16931BusinessRules.evaluate(invoice: inv)
        XCTAssertTrue(rules.contains { $0.ruleId == "BT-30-LUHN" && $0.severity == .warning && $0.message.contains("SIREN") },
                     "BT-30-LUHN doit avertir sur un SIREN émetteur à clé Luhn fausse")
        XCTAssertFalse(rules.contains { $0.ruleId == "BR-FR-10" }, "9 chiffres : BR-FR-10 est respectée")
    }

    func testBusinessRulesUnknownCurrencyWarns() {
        var inv = sampleInvoice()
        inv.currency = "XXX"
        let rules = EN16931BusinessRules.evaluate(invoice: inv)
        XCTAssertTrue(rules.contains { $0.ruleId == "BR-CL-04" && $0.severity == .warning },
                     "BR-CL-04 doit avertir pour une devise hors liste ISO 4217 de référence")
    }

    func testBusinessRulesVATCategoryCoherence() {
        var inv = sampleInvoice()
        inv.lines = [InvoiceLine(name: "Ligne exonérée", quantity: 1, unit: "C62", unitPrice: 100, vatRate: 0)]
        let rules = EN16931BusinessRules.evaluate(invoice: inv)
        XCTAssertTrue(rules.contains { $0.ruleId == "BT-152-ZERO" },
                     "BT-152-ZERO doit signaler un taux nul pour inviter à vérifier l'exonération")
    }

    // MARK: - Export enrichi

    func testExportInvoiceLinesCSVContainsVATCategory() {
        let csv = ExportGenerator().invoiceLinesCSV([sampleInvoice()])
        XCTAssertTrue(csv.contains("Cat. TVA (BT-151)"))
        XCTAssertTrue(csv.contains(";S;"),
                     "La catégorie TVA S doit figurer pour les lignes à taux standard")
    }

    func testExportOrderLinesCSVContainsVATCategory() {
        let order = SalesOrder(
            number: "CMD-001",
            buyer: InvoiceParty(name: "Acheteur SARL", street: "1 rue A", postcode: "75001", city: "Paris", country: "FR"),
            seller: InvoiceParty(name: "Client SAS", street: "2 rue B", postcode: "75002", city: "Paris", country: "FR"),
            lines: [InvoiceLine(name: "Article A", quantity: 3, unitPrice: 100, vatRate: 20)]
        )
        let csv = ExportGenerator().orderLinesCSV([order])
        XCTAssertTrue(csv.contains("Cat. TVA (BT-151)"))
        XCTAssertTrue(csv.contains(";S;"))
    }

    func testSuperPDPInvoiceEventDetailLabels() {
        XCTAssertEqual(SuperPDPInvoiceEvent(statusCode: "fr:212").detailLabel, "Facture encaissée")
        XCTAssertEqual(SuperPDPInvoiceEvent(statusCode: "fr:207").detailLabel, "Accepté par le destinataire")
        XCTAssertEqual(SuperPDPInvoiceEvent(statusCode: "fr:206").detailLabel, "Refusé par le destinataire")
        XCTAssertEqual(SuperPDPInvoiceEvent(statusCode: "fr:320").detailLabel, "Facture annulée")
        XCTAssertEqual(SuperPDPInvoiceEvent(statusCode: "fr:220").detailLabel, "Facture rejetée par la PDP")
        XCTAssertTrue(SuperPDPInvoiceEvent(statusCode: "fr:999").detailLabel.contains("fr:999"))
    }

    func testSuperPDPFrenchCompanyToInvoiceParty() {
        let company = SuperPDPFrenchCompany(
            name: "ACME SAS",
            siren: "123456789",
            siret: "12345678900017",
            vatNumber: "FR12345678901",
            addressLine: "10 rue du Test",
            postcode: "75001",
            city: "Paris",
            country: "FR"
        )
        let party = company.toInvoiceParty()
        XCTAssertEqual(party.name, "ACME SAS")
        XCTAssertEqual(party.siren, "123456789")
        XCTAssertEqual(party.siret, "12345678900017")
        XCTAssertEqual(party.vatNumber, "FR12345678901")
        XCTAssertEqual(party.endpointID, "123456789")
        XCTAssertEqual(party.endpointSchemeID, "0225")
        XCTAssertEqual(party.city, "Paris")
        XCTAssertEqual(company.displaySubtitle, "SIREN 123456789 · FR12345678901 · Paris")
    }

    func testSuperPDPSessionAuthorization() {
        let s1 = SuperPDPSession(status: "active", isAuthorized: true, companyNumber: "123456789")
        XCTAssertTrue(s1.isAuthorized)
        let s2 = SuperPDPSession(status: "pending", isAuthorized: false)
        XCTAssertFalse(s2.isAuthorized)
    }
}
