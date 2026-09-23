import XCTest
import FacturXCore

/// Champs optionnels du catalogue et cadres de facturation (BT-23), corrigés le 2026-09-23
/// après reproduction contre les validateurs officiels (XSD Factur-X 1.09 EN16931, Schematron
/// EN16931 et France CTC, exécutés via les paquets Python factur-x et saxonche sur le XML de
/// cette app). Ces tests figent la structure validée — ordre des éléments compris, repris des
/// séquences du XSD — sans remplacer les validateurs eux-mêmes.
final class OptionalFieldsConformanceTests: XCTestCase {

    // MARK: - Séquences du XSD Factur-X 1.09 EN16931 (types concernés)

    private let headerAgreementSequence = [
        "BuyerReference", "SellerTradeParty", "BuyerTradeParty", "SellerTaxRepresentativeTradeParty",
        "SellerOrderReferencedDocument", "BuyerOrderReferencedDocument", "ContractReferencedDocument",
        "AdditionalReferencedDocument", "SpecifiedProcuringProject",
    ]
    private let headerDeliverySequence = [
        "ShipToTradeParty", "ActualDeliverySupplyChainEvent", "DespatchAdviceReferencedDocument",
        "ReceivingAdviceReferencedDocument",
    ]
    private let tradeProductSequence = [
        "GlobalID", "SellerAssignedID", "BuyerAssignedID", "Name", "Description",
        "ApplicableProductCharacteristic", "DesignatedProductClassification", "OriginTradeCountry",
    ]
    private let lineAgreementSequence = [
        "BuyerOrderReferencedDocument", "GrossPriceProductTradePrice", "NetPriceProductTradePrice",
    ]

    private let agreementPath = "CrossIndustryInvoice/SupplyChainTradeTransaction/ApplicableHeaderTradeAgreement"
    private let deliveryPath = "CrossIndustryInvoice/SupplyChainTradeTransaction/ApplicableHeaderTradeDelivery"
    private let firstLinePath = "CrossIndustryInvoice/SupplyChainTradeTransaction/IncludedSupplyChainTradeLineItem[1]"

    // MARK: - Outils

    /// Ce jour-là dans le fuseau de l'app, comme une date saisie dans l'éditeur.
    private func makeDate(_ s: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: s)!
    }

    /// Même facture que `FacturXCoreTests.sampleInvoice()` — valide contre les trois
    /// validateurs officiels telle quelle (vérifié le 2026-09-23).
    private func sampleInvoice() -> Invoice {
        Invoice(
            number: "2026-0001",
            type: .commercialInvoice,
            issueDate: makeDate("2026-09-01"),
            dueDate: makeDate("2026-09-30"),
            seller: InvoiceParty(name: "Mon Entreprise SARL", street: "12 rue du Commerce", postcode: "75001", city: "Paris",
                                 vatNumber: "FR12345678901", siren: "123456789", contactEmail: "contact@exemple.fr",
                                 endpointID: "123456789", endpointSchemeID: "0225"),
            buyer: InvoiceParty(name: "Client Exemple SAS", street: "8 avenue des Champs", postcode: "75008", city: "Paris",
                                siren: "987654321", endpointID: "987654321", endpointSchemeID: "0225"),
            buyerReference: "CLIENT-REF-42",
            lines: [
                InvoiceLine(name: "Prestation de conseil", quantity: 2, unit: "DAY", unitPrice: 600, vatRate: 20),
                InvoiceLine(name: "Frais de déplacement", quantity: 1, unit: "C62", unitPrice: 150, vatRate: 20),
            ],
            paymentIBAN: "FR7630006000011234567890189",
            paymentBIC: "AGRIFRPP",
            paymentTerms: "Paiement à 30 jours",
            billingMode: .m1
        )
    }

    private func xml(_ invoice: Invoice) throws -> String {
        String(decoding: try CIIXMLGenerator().generate(invoice: invoice), as: UTF8.self)
    }

    /// Élément désigné par un chemin de noms locaux (préfixes ignorés), ex. "A/B[1]/C".
    private func element(_ invoice: Invoice, _ path: String, file: StaticString = #filePath, line: UInt = #line) throws -> XMLElement? {
        let doc = try XMLDocument(data: CIIXMLGenerator().generate(invoice: invoice))
        let steps = path.split(separator: "/").map { step -> String in
            let parts = step.split(separator: "[", maxSplits: 1)
            let predicate = parts.count > 1 ? "[" + parts[1] : ""
            return "*[local-name()='\(parts[0])']\(predicate)"
        }
        let found = try doc.nodes(forXPath: "/" + steps.joined(separator: "/")).first as? XMLElement
        if found == nil { XCTFail("Élément introuvable : \(path)", file: file, line: line) }
        return found
    }

    private func childNames(_ element: XMLElement?) -> [String] {
        element?.children?.compactMap { ($0 as? XMLElement)?.localName } ?? []
    }

    private func child(_ element: XMLElement?, _ name: String) -> XMLElement? {
        element?.children?.compactMap { $0 as? XMLElement }.first { $0.localName == name }
    }

    /// Chaque enfant doit appartenir à la séquence XSD, dans l'ordre de celle-ci.
    private func assertFollowsSequence(_ names: [String], _ sequence: [String], file: StaticString = #filePath, line: UInt = #line) {
        let indices = names.map { sequence.firstIndex(of: $0) }
        XCTAssertFalse(indices.contains(nil), "Élément hors séquence XSD dans \(names)", file: file, line: line)
        let known = indices.compactMap { $0 }
        XCTAssertEqual(known, known.sorted(), "Ordre contraire au XSD : \(names)", file: file, line: line)
    }

    private func everyCatalogueField(for template: OptionalFieldTemplate) -> OptionalField {
        OptionalField(tagName: template.tagName, value: template.tagName == "ram:GlobalID" ? "3017620422003" : "VAL-\(template.bt)")
    }

    // MARK: - Catalogue : numéros BT de la norme EN 16931

    func testCatalogueUsesEN16931BusinessTermNumbers() {
        XCTAssertEqual(OptionalFieldCatalogue.header.map { "\($0.bt) \($0.tagName)" }, [
            "BT-10 ram:BuyerReference",
            "BT-11 ram:SpecifiedProcuringProject/ram:ID",
            "BT-12 ram:ContractReferencedDocument/ram:IssuerAssignedID",
            "BT-15 ram:ReceivingAdviceReferencedDocument/ram:IssuerAssignedID",
            "BT-16 ram:DespatchAdviceReferencedDocument/ram:IssuerAssignedID",
            "BT-17 ram:AdditionalReferencedDocument/ram:IssuerAssignedID",
        ])
        XCTAssertEqual(OptionalFieldCatalogue.line.map { "\($0.bt) \($0.tagName)" }, [
            "BT-132 ram:BuyerOrderReferencedDocument/ram:LineID",
            "BT-155 ram:SellerAssignedID",
            "BT-156 ram:BuyerAssignedID",
            "BT-157 ram:GlobalID",
        ])
        for template in OptionalFieldCatalogue.header + OptionalFieldCatalogue.line {
            XCTAssertTrue(template.help.hasPrefix(template.bt + " "), "L'aide de \(template.label) doit citer son BT (\(template.bt))")
        }
    }

    /// BT-156 était proposé à la saisie mais jamais émis : plus aucun champ du catalogue ne
    /// doit pouvoir être perdu silencieusement.
    func testEveryCatalogueFieldIsEmittedInTheXML() throws {
        for template in OptionalFieldCatalogue.header {
            var invoice = sampleInvoice()
            invoice.optionalFields = [everyCatalogueField(for: template)]
            XCTAssertTrue(try xml(invoice).contains(">\(everyCatalogueField(for: template).value)<"), "\(template.bt) non émis")
        }
        for template in OptionalFieldCatalogue.line {
            var invoice = sampleInvoice()
            invoice.lines[0].optionalFields = [everyCatalogueField(for: template)]
            XCTAssertTrue(try xml(invoice).contains(">\(everyCatalogueField(for: template).value)<"), "\(template.bt) non émis")
        }
    }

    // MARK: - BT-11 : projet (XSD : Name obligatoire)

    func testProjectReferenceCarriesTheNameRequiredByTheXSD() throws {
        var invoice = sampleInvoice()
        invoice.optionalFields.append(OptionalField(tagName: "ram:SpecifiedProcuringProject/ram:ID", value: "PROJ-42"))
        let project = try element(invoice, agreementPath + "/SpecifiedProcuringProject")
        XCTAssertEqual(childNames(project), ["ID", "Name"])
        XCTAssertEqual(child(project, "ID")?.stringValue, "PROJ-42")
        XCTAssertEqual(child(project, "Name")?.stringValue, "Project reference")
    }

    // MARK: - BT-17 : appel d'offres (TendererReferencedDocument hors profil)

    func testTenderReferenceIsAnAdditionalReferencedDocumentOfType50() throws {
        var invoice = sampleInvoice()
        invoice.tenderRef = "AO-2026-3"
        invoice.contractRef = "CT-1"
        invoice.purchaseOrderRef = "BC-1"
        invoice.optionalFields.append(OptionalField(tagName: "ram:SpecifiedProcuringProject/ram:ID", value: "PROJ-42"))

        XCTAssertFalse(try xml(invoice).contains("TendererReferencedDocument"))
        let tender = try element(invoice, agreementPath + "/AdditionalReferencedDocument")
        XCTAssertEqual(childNames(tender), ["IssuerAssignedID", "TypeCode"])
        XCTAssertEqual(child(tender, "IssuerAssignedID")?.stringValue, "AO-2026-3")
        XCTAssertEqual(child(tender, "TypeCode")?.stringValue, "50")
        assertFollowsSequence(childNames(try element(invoice, agreementPath)), headerAgreementSequence)
    }

    func testLegacyTenderTagIsMigratedWhenDecoding() throws {
        var legacy = sampleInvoice()
        legacy.optionalFields.append(OptionalField(tagName: "ram:TendererReferencedDocument/ram:IssuerAssignedID", value: "AO-OLD"))
        let decoded = try JSONDecoder().decode(Invoice.self, from: JSONEncoder().encode(legacy))
        XCTAssertEqual(decoded.tenderRef, "AO-OLD")
        XCTAssertFalse(decoded.optionalFields.contains { $0.tagName.hasPrefix("ram:TendererReferencedDocument") })
        XCTAssertEqual(decoded.optionalFields.count, legacy.optionalFields.count, "renommée sur place, pas dupliquée")

        // Clé de premier niveau `tenderRef` d'un format encore plus ancien.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(sampleInvoice())) as? [String: Any])
        json["tenderRef"] = "AO-TRES-VIEUX"
        let veryOld = try JSONDecoder().decode(Invoice.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(veryOld.tenderRef, "AO-TRES-VIEUX")
        XCTAssertTrue(try xml(veryOld).contains("<ram:IssuerAssignedID>AO-TRES-VIEUX</ram:IssuerAssignedID>"))
    }

    func testParserReadsTenderFromBothTheEN16931FormAndTheLegacyTag() throws {
        var invoice = sampleInvoice()
        invoice.tenderRef = "AO-2026-3"
        let current = try xml(invoice)
        XCTAssertEqual(try CIIXMLParser().parse(xml: Data(current.utf8)).tenderRef, "AO-2026-3")

        // XML émis par une version antérieure de l'app (ou par un tiers en profil EXTENDED).
        let legacy = current.replacingOccurrences(
            of: "<ram:AdditionalReferencedDocument>\n        <ram:IssuerAssignedID>AO-2026-3</ram:IssuerAssignedID>\n        <ram:TypeCode>50</ram:TypeCode>\n      </ram:AdditionalReferencedDocument>",
            with: "<ram:TendererReferencedDocument>\n        <ram:IssuerAssignedID>AO-2026-3</ram:IssuerAssignedID>\n      </ram:TendererReferencedDocument>")
        XCTAssertNotEqual(legacy, current)
        XCTAssertEqual(try CIIXMLParser().parse(xml: Data(legacy.utf8)).tenderRef, "AO-2026-3")

        // Une pièce justificative (code 916) n'est pas une référence d'appel d'offres.
        let supportingDocument = current.replacingOccurrences(of: "<ram:TypeCode>50</ram:TypeCode>", with: "<ram:TypeCode>916</ram:TypeCode>")
        XCTAssertNil(try CIIXMLParser().parse(xml: Data(supportingDocument.utf8)).tenderRef)
    }

    // MARK: - BT-12 / BT-15 / BT-16 : contrat, réception, livraison

    func testDespatchAdviceComesBeforeReceivingAdviceAsTheXSDRequires() throws {
        var invoice = sampleInvoice()
        invoice.receivingAdviceRef = "BR-2026-1"
        invoice.despatchAdviceRef = "BL-2026-1"
        let delivery = try element(invoice, deliveryPath)
        XCTAssertEqual(childNames(delivery), ["ActualDeliverySupplyChainEvent", "DespatchAdviceReferencedDocument", "ReceivingAdviceReferencedDocument"])
        XCTAssertEqual(child(child(delivery, "DespatchAdviceReferencedDocument"), "IssuerAssignedID")?.stringValue, "BL-2026-1")
        XCTAssertEqual(child(child(delivery, "ReceivingAdviceReferencedDocument"), "IssuerAssignedID")?.stringValue, "BR-2026-1")
    }

    // MARK: - BT-132 : référence de ligne de commande

    func testLineOrderReferenceIsTheOrderLineID() throws {
        var invoice = sampleInvoice()
        invoice.lines[0].optionalFields = [OptionalField(tagName: "ram:BuyerOrderReferencedDocument/ram:LineID", value: "10")]
        let agreement = try element(invoice, firstLinePath + "/SpecifiedLineTradeAgreement")
        XCTAssertEqual(childNames(agreement), ["BuyerOrderReferencedDocument", "NetPriceProductTradePrice"])
        XCTAssertEqual(childNames(child(agreement, "BuyerOrderReferencedDocument")), ["LineID"])
        XCTAssertEqual(child(child(agreement, "BuyerOrderReferencedDocument"), "LineID")?.stringValue, "10")
    }

    /// Ex-« Réf. contrat ligne » (rejeté par le XSD) et ex-« Réf. commande ligne »
    /// (IssuerAssignedID signalé hors profil par le Schematron EN16931) : plus proposés,
    /// valeurs déjà saisies conservées mais jamais émises.
    func testRetiredLineTagsAreKeptButNeverEmitted() throws {
        let retired = [
            "ram:ContractReferencedDocument/ram:IssuerAssignedID",
            "ram:BuyerOrderReferencedDocument/ram:IssuerAssignedID",
        ]
        var invoice = sampleInvoice()
        invoice.lines[0].optionalFields = [
            OptionalField(tagName: retired[0], value: "CT-LIGNE-1"),
            OptionalField(tagName: retired[1], value: "PO-77"),
        ]
        let s = try xml(invoice)
        XCTAssertFalse(s.contains("CT-LIGNE-1"))
        XCTAssertFalse(s.contains("PO-77"))
        XCTAssertFalse(s.contains("<ram:ContractReferencedDocument>"))
        XCTAssertEqual(childNames(try element(invoice, firstLinePath + "/SpecifiedLineTradeAgreement")), ["NetPriceProductTradePrice"])

        let decoded = try JSONDecoder().decode(Invoice.self, from: JSONEncoder().encode(invoice))
        XCTAssertEqual(decoded.lines[0].optionalFields.map(\.value), ["CT-LIGNE-1", "PO-77"], "valeurs conservées")
        for tag in retired {
            XCTAssertNil(OptionalFieldCatalogue.template(forTag: tag, location: .line))
            XCTAssertTrue(OptionalFieldCatalogue.help(forTag: tag, location: .line).contains("non émise"))
        }
    }

    // MARK: - BT-155 / BT-156 / BT-157 : identifiants de l'article

    func testProductIdentifiersAreEmittedInTheXSDOrder() throws {
        var invoice = sampleInvoice()
        invoice.lines[0].description = "Détail"
        // Saisis dans le désordre : l'ordre du XML ne dépend pas de celui de la saisie.
        invoice.lines[0].optionalFields = [
            OptionalField(tagName: "ram:BuyerAssignedID", value: "ART-A-34"),
            OptionalField(tagName: "ram:GlobalID", value: "3017620422003"),
            OptionalField(tagName: "ram:SellerAssignedID", value: "ART-V-12"),
        ]
        let product = try element(invoice, firstLinePath + "/SpecifiedTradeProduct")
        XCTAssertEqual(childNames(product), ["GlobalID", "SellerAssignedID", "BuyerAssignedID", "Name", "Description"])
        XCTAssertEqual(child(product, "GlobalID")?.attribute(forName: "schemeID")?.stringValue, "0160")
        XCTAssertEqual(child(product, "SellerAssignedID")?.stringValue, "ART-V-12")
        XCTAssertEqual(child(product, "BuyerAssignedID")?.stringValue, "ART-A-34")
    }

    func testGTINValidatorChecksLengthAndGS1CheckDigit() {
        for valid in ["96385074", "036000291452", "3017620422003", "10012345678902"] {
            XCTAssertTrue(GTINValidator.isValid(valid), valid)
        }
        for invalid in ["SKU-1234", "3017620422004", "301762042200", "", "30176204220O3"] {
            XCTAssertFalse(GTINValidator.isValid(invalid), invalid)
        }
    }

    func testNonGTINValueInBT157IsFlaggedWithoutBlocking() {
        var invoice = sampleInvoice()
        invoice.lines[0].optionalFields = [OptionalField(tagName: "ram:GlobalID", value: "SKU-1234")]
        let flagged = EN16931BusinessRules.evaluate(invoice: invoice).filter { $0.ruleId == "BT-157-GTIN" }
        XCTAssertEqual(flagged.map(\.severity), [.warning])
        XCTAssertTrue(FacturXValidator().validate(invoice: invoice).isValid)

        invoice.lines[0].optionalFields = [OptionalField(tagName: "ram:GlobalID", value: "3017620422003")]
        XCTAssertFalse(EN16931BusinessRules.evaluate(invoice: invoice).contains { $0.ruleId == "BT-157-GTIN" })
    }

    // MARK: - Tous les champs ensemble

    func testInvoiceWithEveryCatalogueFieldFollowsTheXSDSequences() throws {
        var invoice = sampleInvoice()
        invoice.optionalFields = OptionalFieldCatalogue.header.map(everyCatalogueField)
        invoice.lines[0].optionalFields = OptionalFieldCatalogue.line.map(everyCatalogueField)
        invoice.lines[0].description = "Détail de la prestation"
        invoice.purchaseOrderRef = "BC-2026-1"

        assertFollowsSequence(childNames(try element(invoice, agreementPath)), headerAgreementSequence)
        assertFollowsSequence(childNames(try element(invoice, deliveryPath)), headerDeliverySequence)
        assertFollowsSequence(childNames(try element(invoice, firstLinePath + "/SpecifiedTradeProduct")), tradeProductSequence)
        assertFollowsSequence(childNames(try element(invoice, firstLinePath + "/SpecifiedLineTradeAgreement")), lineAgreementSequence)
        XCTAssertTrue(FacturXValidator().validate(invoice: invoice).isValid)
    }

    // MARK: - BT-23 : cadre de facturation

    func testBillingModeLabelsFollowTheLetterAndDigitMeaning() {
        let nature: [Character: String] = ["B": "Biens", "S": "Services", "M": "Double"]
        let framework: [Character: String] = ["1": "dépôt d'une facture", "2": "facture déjà payée", "4": "définitive après acompte"]
        for mode in BillingMode.allCases {
            let code = Array(mode.rawValue)
            XCTAssertTrue(mode.label.hasPrefix(nature[code[0]]!), mode.label)
            XCTAssertTrue(mode.label.hasSuffix("(\(mode.rawValue))"), mode.label)
            if let expected = framework[code[1]] {
                XCTAssertTrue(mode.label.contains(expected), mode.label)
            }
        }
        XCTAssertEqual(Set(BillingMode.allCases.map(\.label)).count, BillingMode.allCases.count, "libellés distincts")
    }

    func testGroupLineModesAreOfferedOnlyWhenAlreadySelected() {
        let offered = BillingMode.selectableCases()
        XCTAssertEqual(offered.count, 14)
        XCTAssertFalse(offered.contains { $0.rawValue.hasSuffix("8") || $0.rawValue.hasSuffix("9") })
        XCTAssertEqual(BillingMode.selectableCases(current: .m1), offered)
        XCTAssertTrue(BillingMode.selectableCases(current: .s8).contains(.s8), "une facture existante en S8 doit rester affichable")
    }

    func testGroupLineModesBlockIssuedInvoicesOnly() {
        for (mode, rule) in [(BillingMode.b8, "BR-FR-MV-02"), (.s8, "BR-FR-MV-02"), (.m9, "BR-FR-BD-02")] {
            var invoice = sampleInvoice()
            invoice.billingMode = mode
            XCTAssertTrue(EN16931BusinessRules.evaluate(invoice: invoice).contains { $0.ruleId == rule && $0.severity == .error }, mode.rawValue)
            XCTAssertFalse(FacturXValidator().validate(invoice: invoice).isValid, mode.rawValue)
            XCTAssertFalse(EN16931BusinessRules.evaluate(invoice: invoice, context: .received).contains { $0.ruleId == rule },
                           "\(mode.rawValue) : un document reçu a pu être construit avec ses lignes de regroupement")
        }
    }

    func testAlreadyPaidModeRequiresPaidAmountEqualToTotal() throws {
        var invoice = sampleInvoice()
        invoice.billingMode = .s2
        XCTAssertTrue(EN16931BusinessRules.evaluate(invoice: invoice).contains { $0.ruleId == "BR-FR-CO-09" && $0.severity == .error })
        XCTAssertFalse(FacturXValidator().validate(invoice: invoice).isValid)

        invoice.prepaidAmount = invoice.grandTotal
        let rules = EN16931BusinessRules.evaluate(invoice: invoice).filter { $0.ruleId == "BR-FR-CO-09" }
        XCTAssertEqual(rules.map(\.severity), [.warning], "reste le rappel : échéance = date du paiement")
        XCTAssertTrue(FacturXValidator().validate(invoice: invoice).isValid)
        let s = try xml(invoice)
        XCTAssertTrue(s.contains("<ram:TotalPrepaidAmount>1620.00</ram:TotalPrepaidAmount>"))
        XCTAssertTrue(s.contains("<ram:DuePayableAmount>0.00</ram:DuePayableAmount>"))
        XCTAssertEqual(invoice.prepaidAmountLabel, "Montant déjà payé")
    }

    /// BR-FR-CO-09 compare BT-113 au total TTC : sans BT-113, même une facture à zéro échoue.
    func testAlreadyPaidModeAlwaysEmitsThePaidAmount() throws {
        var invoice = sampleInvoice()
        invoice.billingMode = .b2
        invoice.lines = [InvoiceLine(name: "Remplacement sous garantie", quantity: 1, unitPrice: 0, vatRate: 20)]
        XCTAssertTrue(try xml(invoice).contains("<ram:TotalPrepaidAmount>0.00</ram:TotalPrepaidAmount>"))

        invoice.billingMode = .b1
        XCTAssertFalse(try xml(invoice).contains("TotalPrepaidAmount"))
        XCTAssertEqual(invoice.prepaidAmountLabel, "Acompte déjà payé")
    }

    func testFinalAfterDepositModeIsRefusedOnADepositInvoice() {
        var invoice = sampleInvoice()
        invoice.billingMode = .m4
        XCTAssertFalse(EN16931BusinessRules.evaluate(invoice: invoice).contains { $0.ruleId == "BR-FR-CO-08" })

        invoice.type = .deposit
        let rule = EN16931BusinessRules.evaluate(invoice: invoice).first { $0.ruleId == "BR-FR-CO-08" }
        XCTAssertEqual(rule?.severity, .error)
        XCTAssertTrue(rule?.message.contains("M1") ?? false, "la correction proposée est le cadre 1 de même nature")
        XCTAssertFalse(FacturXValidator().validate(invoice: invoice).isValid)
    }

    func testDepositAndFinalSettlementFrameworks() {
        XCTAssertEqual(BillingMode.b4.forDeposit, .b1)
        XCTAssertEqual(BillingMode.s4.forDeposit, .s1)
        XCTAssertEqual(BillingMode.m4.forDeposit, .m1)
        XCTAssertEqual(BillingMode.s2.forDeposit, .s2)
        XCTAssertEqual(BillingMode.b1.forFinalSettlement, .b4)
        XCTAssertEqual(BillingMode.s1.forFinalSettlement, .s4)
        XCTAssertEqual(BillingMode.m1.forFinalSettlement, .m4)
        XCTAssertEqual(BillingMode.s5.forFinalSettlement, .s5, "hors cadre 1 : inchangé")
        XCTAssertEqual(BillingMode.m4.forFinalSettlement, .m4)
    }
}
