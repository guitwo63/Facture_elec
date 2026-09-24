import XCTest
@testable import FacturXCore

/// Contrôles B2B du destinataire alignés sur ARVERNX-SaaS (`einvoicing/en16931/rules.py`,
/// `_b2b_buyer_rules`), décision de Guillaume du 2026-09-24 :
/// - BR-FR-21 en erreur : une adresse électronique de l'annuaire (schéma 0225) qui ne désigne pas
///   le SIREN du destinataire, c'est-à-dire ni « SIREN » ni « SIREN_… ». C'est la forme d'ARVERNX,
///   celle que l'application compose elle-même depuis l'annuaire (`PartyRoutingAddress.composedAddress`).
///   Une adresse restée d'un autre client, ou un SIREN corrigé sans l'adresse, enverrait la facture
///   à une autre entreprise.
/// - BR-FR-11 en avertissement : un destinataire établi en France sans SIREN. Une entreprise
///   assujettie en a un ; un particulier, non.
/// Le Schematron France CTC n'applique ces deux règles qu'avec la note BAR = B2B, que l'application
/// n'émet pas : les tests l'ajoutent au XML généré pour rejouer les assertions officielles.
/// L'avertissement BR-FR-21 pour un autre schéma que 0225 (PR #161) est dans
/// `ElectronicAddressSchemeTests`.
final class FrenchBuyerB2BRulesTests: XCTestCase {

    // MARK: - Outils

    /// Facture conforme aux validateurs officiels : destinataire établi en France, SIREN
    /// 303265045, adresse 0225 saisie qui le désigne.
    private func invoice(_ adjust: (inout Invoice) -> Void = { _ in }) -> Invoice {
        var invoice = Invoice(
            number: "2026-0501",
            seller: InvoiceParty(name: "Mon Entreprise SARL", street: "12 rue du Commerce", postcode: "75001", city: "Paris",
                                 vatNumber: "FR44732829320", siren: "732829320", endpointID: "732829320", endpointSchemeID: "0225"),
            buyer: InvoiceParty(name: "Client Exemple SAS", street: "8 avenue des Champs", postcode: "75008", city: "Paris",
                                siren: "303265045", endpointID: "303265045", endpointSchemeID: "0225"),
            buyerReference: "REF-1",
            lines: [InvoiceLine(name: "Article", quantity: 3, unit: "H87", unitPrice: 123.45, vatRate: 20)],
            paymentTerms: "Paiement à 30 jours")
        adjust(&invoice)
        return invoice
    }

    /// Le destinataire de `invoice()` avec cette adresse, sous ce schéma.
    private func buyerAddress(_ address: String?, scheme: String = "0225") -> Invoice {
        invoice { $0.buyer.endpointID = address; $0.buyer.endpointSchemeID = scheme }
    }

    private func rules(_ invoice: Invoice, _ ruleId: String, context: EN16931RuleContext = .issued) -> [BusinessRuleResult] {
        EN16931BusinessRules.evaluate(invoice: invoice, context: context).filter { $0.ruleId == ruleId }
    }

    /// Ce qui bloque l'export, le dépôt SUPER PDP et sa validation (pré-contrôle de l'éditeur).
    private func isExportable(_ invoice: Invoice) -> Bool {
        FacturXValidator().validate(invoice: invoice).isValid
    }

    private func xml(_ invoice: Invoice) throws -> String {
        String(decoding: try CIIXMLGenerator().generate(invoice: invoice), as: UTF8.self)
    }

    /// Adresses 0225 qui ne désignent pas le SIREN 303265045. Les deux dernières commencent par
    /// lui : le Schematron les admet (`starts-with`), pas la forme « SIREN » / « SIREN_… ».
    private let otherAddresses: [(label: String, address: String)] = [
        ("SIREN d'un autre", "732829320"),
        ("SIREN_SIRET d'un autre", "732829320_73282932000074"),
        ("suffixe d'un autre", "552100554_ACHATS"),
        ("SIRET seul, sans « _ »", "30326504500018"),
        ("SIREN suivi d'un tiret", "303265045-ACHATS"),
    ]

    /// Adresses 0225 qui désignent le SIREN 303265045 (`PartyRoutingAddress.composedAddress`).
    private let designating = ["303265045", "303265045_30326504500018", "303265045_ACHATS", "303265045_30326504500018_SERVICE-COMPTA"]

    // MARK: - BR-FR-21 : adresse de l'annuaire au nom d'un autre SIREN

    /// Une adresse 0225 qui ne désigne pas le SIREN du destinataire bloque l'export. Le message
    /// cite l'adresse, le SIREN et la forme attendue. L'avertissement « hors de l'annuaire » ne
    /// s'y ajoute pas : un seul résultat BR-FR-21.
    func testA0225AddressThatDoesNotDesignateTheBuyerSirenIsAnError() {
        for (label, address) in otherAddresses {
            let invoice = buyerAddress(address)
            let found = rules(invoice, "BR-FR-21")
            XCTAssertEqual(found.map(\.severity), [.error], label)
            let message = found.first?.message ?? ""
            XCTAssertTrue(message.contains("(BT-49) « \(address) »"), label)
            XCTAssertTrue(message.contains("SIREN 303265045"), label)
            XCTAssertTrue(message.contains("« 303265045 » ou commencer par « 303265045_ »"), label)
            XCTAssertTrue(message.contains("la PDP"), label)
            XCTAssertFalse(isExportable(invoice), label)
        }
    }

    /// Un ancien schéma que le générateur émet en 0225 (vide, « FR:SIRENE », « 0183 ») est
    /// contrôlé comme 0225 : c'est l'adresse du XML qui compte.
    func testOldSchemesEmittedIn0225AreCheckedToo() {
        for scheme in ["", "FR:SIRENE", "0183", " 0225 "] {
            let found = rules(buyerAddress("732829320", scheme: scheme), "BR-FR-21")
            XCTAssertEqual(found.map(\.severity), [.error], "« \(scheme) »")
        }
    }

    /// L'adresse et le SIREN sont comparés tels que le XML les écrit, sans espaces autour.
    func testAddressAndSirenAreComparedAsEmitted() {
        XCTAssertEqual(rules(invoice { $0.buyer.endpointID = "  303265045_ACHATS \n"; $0.buyer.siren = " 303265045 " }, "BR-FR-21").map(\.message), [])
        XCTAssertEqual(rules(invoice { $0.buyer.endpointID = " 732829320 "; $0.buyer.siren = " 303265045 " }, "BR-FR-21").map(\.severity), [.error])
    }

    /// Une adresse qui désigne le SIREN (« SIREN », « SIREN_SIRET », « SIREN_suffixe »,
    /// « SIREN_SIRET_code ») passe, comme l'adresse déduite du SIREN quand rien n'est saisi.
    func testAnAddressDesignatingTheBuyerSirenPasses() {
        for address in designating + [" "] {
            let invoice = buyerAddress(address)
            XCTAssertEqual(rules(invoice, "BR-FR-21").map(\.message), [], address)
            XCTAssertTrue(isExportable(invoice), address)
        }
        XCTAssertEqual(rules(buyerAddress(nil), "BR-FR-21").map(\.message), [])
    }

    /// Hors du champ de l'erreur, comme dans ARVERNX : destinataire étranger, sans SIREN (BR-FR-11
    /// l'avertit), SIREN mal formé (BR-FR-32 le bloque), identifiant d'un autre schéma que 0002,
    /// facture reçue, et l'adresse de l'émetteur, que BR-FR-21 ne vise pas.
    func testTheErrorStaysWithinItsScope() {
        let cases: [(String, Invoice, EN16931RuleContext)] = [
            ("destinataire belge", invoice { $0.buyer.country = "BE"; $0.buyer.endpointID = "732829320" }, .issued),
            ("sans SIREN", invoice { $0.buyer.siren = nil; $0.buyer.endpointID = "732829320" }, .issued),
            ("SIREN vidé", invoice { $0.buyer.siren = "  "; $0.buyer.endpointID = "732829320" }, .issued),
            ("SIREN mal formé", invoice { $0.buyer.siren = "303 265 045"; $0.buyer.endpointID = "732829320" }, .issued),
            ("identifiant de schéma 0208", invoice { $0.buyer.legalSchemeID = "0208"; $0.buyer.endpointID = "732829320" }, .issued),
            ("facture reçue", buyerAddress("732829320"), .received),
            ("adresse 0225 de l'émetteur", invoice { $0.seller.endpointID = "303265045" }, .issued),
        ]
        for (label, invoice, context) in cases {
            XCTAssertEqual(rules(invoice, "BR-FR-21", context: context).map(\.message), [], label)
        }
        // Le pays est comparé sans espaces ni casse, comme pour l'avertissement.
        XCTAssertEqual(rules(invoice { $0.buyer.country = " fr "; $0.buyer.endpointID = "732829320" }, "BR-FR-21").map(\.severity), [.error])
    }

    /// Sous un autre schéma que 0225, l'adresse ne désigne rien dans l'annuaire : c'est toujours
    /// l'avertissement de la PR #161, jamais l'erreur, même si elle ne commence pas par le SIREN.
    func testOtherSchemesKeepTheWarning() {
        for (scheme, address) in [("EM", "factures@client.fr"), ("0009", "73282932000074"), ("9957", "FR44732829320")] {
            XCTAssertEqual(rules(buyerAddress(address, scheme: scheme), "BR-FR-21").map(\.severity), [.warning], scheme)
        }
    }

    // MARK: - BR-FR-11 : destinataire établi en France sans SIREN

    /// Un destinataire établi en France sans SIREN : un avertissement, qui dit quoi faire pour une
    /// entreprise et qu'un particulier peut l'ignorer. La facture reste exportable.
    func testAFrenchBuyerWithoutSirenGetsAWarning() {
        let cases: [(String, Invoice)] = [
            ("sans SIREN, adresse e-mail", invoice { $0.buyer.siren = nil; $0.buyer.endpointID = "client@exemple.fr"; $0.buyer.endpointSchemeID = "EM" }),
            ("SIREN vidé", invoice { $0.buyer.siren = ""; $0.buyer.endpointID = "client@exemple.fr"; $0.buyer.endpointSchemeID = "EM" }),
            ("SIREN fait d'espaces", invoice { $0.buyer.siren = "   "; $0.buyer.endpointID = "client@exemple.fr"; $0.buyer.endpointSchemeID = "EM" }),
            ("sans SIREN, adresse 0225", invoice { $0.buyer.siren = nil }),
            ("pays « fr »", invoice { $0.buyer.country = " fr "; $0.buyer.siren = nil }),
        ]
        for (label, invoice) in cases {
            let found = rules(invoice, "BR-FR-11")
            XCTAssertEqual(found.map(\.severity), [.warning], label)
            let message = found.first?.message ?? ""
            XCTAssertTrue(message.contains("sans SIREN (BT-47)"), label)
            XCTAssertTrue(message.contains("entreprise assujettie"), label)
            XCTAssertTrue(message.contains("particulier"), label)
            XCTAssertTrue(isExportable(invoice), label)
        }
    }

    /// Sans SIREN ni adresse, BR-FR-12 bloque toujours ; BR-FR-11 s'y ajoute.
    func testWithoutSirenNorAddressBRFR12StillBlocks() {
        let invoice = invoice { $0.buyer.siren = nil; $0.buyer.endpointID = nil }
        XCTAssertEqual(rules(invoice, "BR-FR-12").map(\.severity), [.error])
        XCTAssertEqual(rules(invoice, "BR-FR-11").map(\.severity), [.warning])
        XCTAssertFalse(isExportable(invoice))
    }

    /// Pas d'avertissement pour un destinataire à SIREN (même mal formé : BR-FR-32 le bloque), un
    /// destinataire étranger ou sans pays, une facture reçue, ni pour l'émetteur (BR-FR-10).
    func testNoWarningOutsideItsScope() {
        let cases: [(String, Invoice, EN16931RuleContext)] = [
            ("SIREN valide", invoice(), .issued),
            ("SIREN mal formé", invoice { $0.buyer.siren = "303 265 045" }, .issued),
            ("destinataire allemand", invoice {
                $0.buyer.country = "DE"; $0.buyer.siren = nil; $0.buyer.endpointID = "rechnung@kunde.de"; $0.buyer.endpointSchemeID = "EM"
            }, .issued),
            ("pays vide", invoice { $0.buyer.country = ""; $0.buyer.siren = nil }, .issued),
            ("facture reçue", invoice { $0.buyer.siren = nil }, .received),
            ("émetteur sans SIREN", invoice { $0.seller.siren = nil }, .issued),
        ]
        for (label, invoice, context) in cases {
            XCTAssertEqual(rules(invoice, "BR-FR-11", context: context).map(\.message), [], label)
        }
    }

    // MARK: - Assertions officielles, rejouées sur le XML avec la note BAR = B2B

    /// Assertions BR-FR-21_BT-49 et BR-FR-11_BT-47 du Schematron France CTC
    /// (`cii-schematron-fr-ctc/BR-FR-Flux2-Schematron-CII.xslt` du paquet factur-x 6.8, flag fatal),
    /// évaluées sur leur contexte `rsm:CrossIndustryInvoice` : variables et test recopiés tels quels,
    /// le test en valeur booléenne effective comme un `xsl:when`.
    private let prolog = """
    declare namespace rsm = "urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100";
    declare namespace ram = "urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100";
    """

    private var officialBRFR21: String {
        prolog + """
        let $barTreatment := rsm:ExchangedDocument/ram:IncludedNote[ram:SubjectCode = 'BAR']/ram:Content
        let $docType := rsm:ExchangedDocument/ram:TypeCode
        let $siren := rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeAgreement/ram:BuyerTradeParty/ram:SpecifiedLegalOrganization/ram:ID
        let $endpointID := rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeAgreement/ram:BuyerTradeParty/ram:URIUniversalCommunication/ram:URIID
        let $endpointSchemeID := rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeAgreement/ram:BuyerTradeParty/ram:URIUniversalCommunication/ram:URIID/@schemeID
        let $isB2B := $barTreatment = 'B2B'
        let $isExcludedDocType := $docType = ('389', '501', '500', '471', '473', '261', '502')
        return boolean(not($isB2B and not($isExcludedDocType)) or (starts-with($endpointID, $siren) and $endpointSchemeID = '0225'))
        """
    }

    private var officialBRFR11: String {
        prolog + """
        let $barTreatment := rsm:ExchangedDocument/ram:IncludedNote[ram:SubjectCode = 'BAR']/ram:Content
        let $siren := rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeAgreement/ram:BuyerTradeParty/ram:SpecifiedLegalOrganization/ram:ID[@schemeID = '0002']
        return boolean(not($barTreatment = 'B2B') or matches($siren, '^\\d{9}$'))
        """
    }

    /// Le XML avec la note BAR = B2B ajoutée dans `ExchangedDocument` (toujours valide au XSD).
    private func withBARB2BNote(_ xml: String) -> String {
        let closing = "</rsm:ExchangedDocument>"
        XCTAssertEqual(xml.components(separatedBy: closing).count, 2)
        return xml.replacingOccurrences(of: closing, with:
            "<ram:IncludedNote><ram:Content>B2B</ram:Content><ram:SubjectCode>BAR</ram:SubjectCode></ram:IncludedNote>" + closing)
    }

    /// Vrai si l'assertion officielle tient sur ce XML.
    private func holds(_ assertion: String, _ xml: String) throws -> Bool {
        let root = try XCTUnwrap(XMLDocument(data: Data(xml.utf8)).rootElement())
        return try XCTUnwrap(root.objects(forXQuery: assertion).first as? NSNumber).boolValue
    }

    /// Le banc lui-même, sur des XML retouchés à la main : sans note BAR, les deux assertions
    /// tiennent toujours ; avec elle, BR-FR-21 tombe pour une adresse 0225 qui ne commence pas par
    /// le SIREN, et BR-FR-11 sans SIREN de 9 chiffres sous le schéma 0002 (mêmes verdicts que Saxon
    /// avec les XSLT officiels, vérifié le 2026-09-24).
    func testTheReplayedAssertionsFireOnHandEditedXML() throws {
        let valid = try xml(invoice())
        let address = #"<ram:URIID schemeID="0225">303265045</ram:URIID>"#
        let siren = #"<ram:ID schemeID="0002">303265045</ram:ID>"#
        XCTAssertTrue(valid.contains(address))
        XCTAssertTrue(valid.contains(siren))
        for assertion in [officialBRFR21, officialBRFR11] {
            XCTAssertTrue(try holds(assertion, valid))
            XCTAssertTrue(try holds(assertion, withBARB2BNote(valid)))
        }
        let other = valid.replacingOccurrences(of: address, with: #"<ram:URIID schemeID="0225">732829320</ram:URIID>"#)
        XCTAssertTrue(try holds(officialBRFR21, other))
        XCTAssertFalse(try holds(officialBRFR21, withBARB2BNote(other)))
        let siret = valid.replacingOccurrences(of: address, with: #"<ram:URIID schemeID="0225">30326504500018</ram:URIID>"#)
        XCTAssertTrue(try holds(officialBRFR21, withBARB2BNote(siret)))
        let spaced = valid.replacingOccurrences(of: siren, with: #"<ram:ID schemeID="0002">303 265 045</ram:ID>"#)
        XCTAssertFalse(try holds(officialBRFR11, withBARB2BNote(spaced)))
        let belgian = valid.replacingOccurrences(of: siren, with: #"<ram:ID schemeID="0208">0303265045</ram:ID>"#)
        XCTAssertFalse(try holds(officialBRFR11, withBARB2BNote(belgian)))
    }

    /// Pour un destinataire établi en France, l'application signale BR-FR-21 (erreur ou
    /// avertissement) exactement quand l'assertion officielle tombe, sauf l'écart voulu : une
    /// adresse qui commence par le SIREN sans être « SIREN » ni « SIREN_… » est une erreur ici,
    /// comme dans ARVERNX, et passe le Schematron. L'erreur, elle, ne vise que le schéma 0225.
    func testBRFR21MatchesTheOfficialAssertionExceptTheSirenForm() throws {
        var cases: [(String, Invoice)] = otherAddresses.map { ($0.label, buyerAddress($0.address)) }
        cases += designating.map { ("« \($0) »", buyerAddress($0)) }
        cases += [
            ("adresse déduite du SIREN", buyerAddress(nil)),
            ("ancien FR:SIRENE", buyerAddress("732829320", scheme: "FR:SIRENE")),
            ("e-mail", buyerAddress("factures@client.fr", scheme: "EM")),
            ("SIRET en 0009", buyerAddress("30326504500018", scheme: "0009")),
        ]
        let sirenForm: Set<String> = ["SIRET seul, sans « _ »", "SIREN suivi d'un tiret"]
        for (label, invoice) in cases {
            let found = rules(invoice, "BR-FR-21")
            let official = try holds(officialBRFR21, withBARB2BNote(xml(invoice)))
            if sirenForm.contains(label) {
                XCTAssertTrue(official, label)
                XCTAssertEqual(found.map(\.severity), [.error], label)
            } else {
                XCTAssertEqual(found.isEmpty, official, label)
            }
            let emittedIn0225 = CIIXMLGenerator.xmlEndpoint(invoice.buyer)?.schemeID == "0225"
            XCTAssertEqual(found.contains { $0.severity == .error }, !found.isEmpty && emittedIn0225, label)
        }
    }

    /// Pour un destinataire établi en France, l'application signale son SIREN (BR-FR-11 absent,
    /// BR-FR-32 mal formé) exactement quand l'assertion officielle BR-FR-11 tombe.
    func testBRFR11MatchesTheOfficialAssertion() throws {
        for siren in [nil, "", "  ", "303265045", " 303265045 ", "303 265 045", "30326504", "3032650450", "30326504A"] as [String?] {
            let invoice = invoice { $0.buyer.siren = siren; $0.buyer.endpointID = "factures@client.fr"; $0.buyer.endpointSchemeID = "EM" }
            let flagged = !rules(invoice, "BR-FR-11").isEmpty || !rules(invoice, "BR-FR-32").isEmpty
            let official = try holds(officialBRFR11, withBARB2BNote(xml(invoice)))
            XCTAssertEqual(flagged, !official, "« \(siren ?? "nil") »")
        }
    }
}
