import XCTest
@testable import FacturXCore

/// SIREN du vendeur (BT-30) et de l'acheteur (BT-47), constat du 2026-09-24 (croisement F.33
/// d'ARVERNX-SaaS avec les validateurs officiels). Schematron France CTC, deux règles fatales :
/// - BR-FR-10 : le SIREN du vendeur, émis sous le schéma 0002, est obligatoire et fait
///   d'exactement 9 chiffres (`matches(normalize-space($siren), '^\d{9}$')`, sans clé de Luhn),
///   même quand une adresse électronique satisfait BR-FR-13 ;
/// - BR-FR-32 : tout identifiant légal de schéma 0002, celui de l'acheteur compris, a 9 chiffres.
///
/// L'application n'en faisait qu'un avertissement (`SireneValidator.isValidSiren`, qui retirait
/// les non-chiffres : « 732 829 320 » y passait, le XML le portait tel quel et la PDP le rejetait),
/// et rien du tout quand le SIREN du vendeur manquait. Règle reprise d'ARVERNX (décision de
/// Guillaume) : erreurs bloquantes ; SIREN du vendeur manquant en erreur sur une facture émise
/// seulement ; clé de Luhn fausse en simple avertissement (contrôle interne, BT-30-LUHN et
/// BT-47-LUHN, faute d'une règle officielle).
final class SirenRulesTests: XCTestCase {

    // MARK: - Outils

    /// Facture conforme aux validateurs officiels : SIREN à clé juste des deux côtés, adresses
    /// électroniques saisies (BR-FR-13 et BR-FR-12 satisfaites sans le SIREN).
    private func invoice(_ adjust: (inout Invoice) -> Void = { _ in }) -> Invoice {
        var invoice = Invoice(
            number: "2026-0201",
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

    private let sirenRuleIDs: Set<String> = ["BR-FR-10", "BR-FR-32", "BR-FR-13", "BR-FR-12", "BT-30-LUHN", "BT-47-LUHN"]

    /// Règles d'identification des parties, « règle gravité », triées.
    private func sirenRules(_ invoice: Invoice, context: EN16931RuleContext = .issued) -> [String] {
        EN16931BusinessRules.evaluate(invoice: invoice, context: context)
            .filter { sirenRuleIDs.contains($0.ruleId) }
            .map { "\($0.ruleId) \($0.severity.rawValue)" }
            .sorted()
    }

    private func message(_ invoice: Invoice, _ ruleId: String) -> String {
        EN16931BusinessRules.evaluate(invoice: invoice).first { $0.ruleId == ruleId }?.message ?? ""
    }

    /// Ce qui bloque l'export, le dépôt SUPER PDP et sa validation (pré-contrôle de l'éditeur).
    private func isExportable(_ invoice: Invoice) -> Bool {
        FacturXValidator().validate(invoice: invoice).isValid
    }

    private func xml(_ invoice: Invoice) throws -> String {
        String(decoding: try CIIXMLGenerator().generate(invoice: invoice), as: UTF8.self)
    }

    // MARK: - SIREN du vendeur (BR-FR-10)

    func testValidSirensRaiseNothingAndTheInvoiceIsExportable() {
        XCTAssertEqual(sirenRules(invoice()), [])
        XCTAssertTrue(isExportable(invoice()))
    }

    /// Le cas qui passait sans un mot : adresse électronique saisie (BR-FR-13 satisfaite), aucun
    /// SIREN. Un champ vidé dans l'éditeur est enregistré "" et non nil.
    func testMissingSellerSirenBlocksEvenWithAnElectronicAddress() {
        for siren in [nil, "", "   "] as [String?] {
            let label = "SIREN du vendeur \(siren.map { "« \($0) »" } ?? "nil")"
            let invoice = invoice { $0.seller.siren = siren }
            XCTAssertEqual(sirenRules(invoice), ["BR-FR-10 error"], label)
            XCTAssertTrue(message(invoice, "BR-FR-10").contains("BT-30"), label)
            XCTAssertTrue(message(invoice, "BR-FR-10").contains("obligatoire"), label)
            XCTAssertFalse(isExportable(invoice), label)
        }
    }

    func testMissingSellerSirenAndAddressRaiseBothRules() {
        let invoice = invoice { $0.seller.siren = nil; $0.seller.endpointID = nil }
        XCTAssertEqual(sirenRules(invoice), ["BR-FR-10 error", "BR-FR-13 error"])
    }

    func testSellerSirenMustHaveExactlyNineDigits() {
        for siren in ["73282932", "7328293201", "7328293AB", "732 829 320", "732.829.320", "FR732829320"] {
            let invoice = invoice { $0.seller.siren = siren }
            XCTAssertEqual(sirenRules(invoice), ["BR-FR-10 error"], siren)
            XCTAssertTrue(message(invoice, "BR-FR-10").contains("9 chiffres"), siren)
            XCTAssertTrue(message(invoice, "BR-FR-10").contains("« \(siren) »"), siren)
            XCTAssertFalse(isExportable(invoice), siren)
        }
    }

    /// `normalize-space` ne juge que l'intérieur : des espaces autour ne gênent pas, et le
    /// générateur ne les écrit pas.
    func testSpacesAroundTheSirensAreHarmless() throws {
        let invoice = invoice { $0.seller.siren = " 732829320 "; $0.buyer.siren = "\t303265045 " }
        XCTAssertEqual(sirenRules(invoice), [])
        let xml = try xml(invoice)
        XCTAssertTrue(xml.contains(#"<ram:ID schemeID="0002">732829320</ram:ID>"#))
        XCTAssertTrue(xml.contains(#"<ram:ID schemeID="0002">303265045</ram:ID>"#))
    }

    /// Le Schematron ne vérifie pas la clé : 9 chiffres à clé fausse passent la PDP. Probable
    /// faute de frappe, signalée sans bloquer l'export.
    func testAWrongLuhnKeyOnlyWarns() {
        let seller = invoice { $0.seller.siren = "732829321" }
        XCTAssertEqual(sirenRules(seller), ["BT-30-LUHN warning"])
        XCTAssertTrue(message(seller, "BT-30-LUHN").contains("clé"))
        XCTAssertTrue(isExportable(seller))

        let buyer = invoice { $0.buyer.siren = "303265046" }
        XCTAssertEqual(sirenRules(buyer), ["BT-47-LUHN warning"])
        XCTAssertTrue(isExportable(buyer))
    }

    /// BR-FR-10 ne lit que l'identifiant de schéma 0002 : un identifiant légal d'un autre schéma
    /// (qu'une fiche peut tenir d'un XML reçu) ne remplace pas le SIREN du vendeur.
    func testSellerLegalIdentifierOfAnotherSchemeIsNotASiren() {
        let invoice = invoice { $0.seller.siren = "0123456789"; $0.seller.legalSchemeID = "0208" }
        XCTAssertEqual(sirenRules(invoice), ["BR-FR-10 error"])
        XCTAssertTrue(message(invoice, "BR-FR-10").contains("0002"))
    }

    // MARK: - SIREN de l'acheteur (BR-FR-32)

    func testBuyerSirenMustHaveExactlyNineDigits() {
        for siren in ["30326504", "3032650450", "303 265 045", "30326504X"] {
            let invoice = invoice { $0.buyer.siren = siren }
            XCTAssertEqual(sirenRules(invoice), ["BR-FR-32 error"], siren)
            XCTAssertTrue(message(invoice, "BR-FR-32").contains("BT-47"), siren)
            XCTAssertTrue(message(invoice, "BR-FR-32").contains("9 chiffres"), siren)
            XCTAssertFalse(isExportable(invoice), siren)
        }
    }

    /// Un acheteur sans SIREN reste admis quand il a une adresse électronique (BR-FR-12).
    func testBuyerWithoutSirenIsFineWithAnElectronicAddress() {
        for siren in [nil, "", "  "] as [String?] {
            XCTAssertEqual(sirenRules(invoice { $0.buyer.siren = siren }), [], siren ?? "nil")
        }
        XCTAssertEqual(sirenRules(invoice { $0.buyer.siren = nil; $0.buyer.endpointID = nil }), ["BR-FR-12 error"])
    }

    /// BR-FR-32 ne vise que le schéma 0002 : le n° d'entreprise belge (0208, 10 chiffres) d'un
    /// client n'est pas un SIREN.
    func testBuyerLegalIdentifierOfAnotherSchemeIsNotChecked() {
        let invoice = invoice { $0.buyer.siren = "0123456789"; $0.buyer.legalSchemeID = "0208" }
        XCTAssertEqual(sirenRules(invoice), [])
    }

    // MARK: - Facture reçue

    /// Obligation de l'émetteur : un fournisseur (étranger, par exemple) peut ne pas avoir de
    /// SIREN, et il n'y a rien à corriger de notre côté. Le format d'un SIREN présent reste
    /// contrôlé, comme les autres données.
    func testAReceivedInvoiceChecksTheSupplierSirenFormatButNotItsPresence() {
        XCTAssertEqual(sirenRules(invoice { $0.seller.siren = nil }, context: .received), [])
        XCTAssertEqual(sirenRules(invoice { $0.seller.siren = "0123456789"; $0.seller.legalSchemeID = "0208" }, context: .received), [])
        XCTAssertEqual(sirenRules(invoice { $0.seller.siren = "73282932" }, context: .received), ["BR-FR-10 error"])
        XCTAssertEqual(sirenRules(invoice { $0.seller.siren = "732829321" }, context: .received), ["BT-30-LUHN warning"])
    }

    // MARK: - SireneValidator

    /// Même jugement que le Schematron sur le SIREN émis (espaces admis seulement autour), plus
    /// la clé de Luhn. Chiffres ASCII seulement.
    func testIsValidSirenRequiresExactlyNineDigits() {
        XCTAssertTrue(SireneValidator.isValidSiren("732829320"))
        XCTAssertTrue(SireneValidator.isValidSiren(" 732829320 "))
        XCTAssertFalse(SireneValidator.isValidSiren("732 829 320"))
        XCTAssertFalse(SireneValidator.isValidSiren("732-829-320"))
        XCTAssertFalse(SireneValidator.isValidSiren("７３２８２９３２０"))
        XCTAssertFalse(SireneValidator.isValidSiren("732829321"))
        XCTAssertFalse(SireneValidator.isValidSiren(""))
        XCTAssertFalse(SireneValidator.isValidSiren(nil))
        // Le format seul (BR-FR-10, BR-FR-32) ignore la clé.
        XCTAssertTrue(SireneValidator.isWellFormedSiren("732829321"))
        XCTAssertFalse(SireneValidator.isWellFormedSiren("732 829 320"))
    }

    // MARK: - Assertions officielles, rejouées sur le XML

    /// Assertion du Schematron France CTC (`cii-schematron-fr-ctc/BR-FR-Flux2-Schematron-CII.xslt`
    /// du paquet factur-x, flag fatal), recopiée telle quelle : contexte, variables, test. Le test
    /// est évalué en valeur booléenne effective, comme un `xsl:when` (`string($endpointID)` de
    /// BR-FR-13 rend une chaîne). Même banc que `NonEuroCurrencyTests`.
    private struct OfficialAssertion {
        let id: String
        let context: String
        var variables: [(name: String, select: String)] = []
        let test: String
        /// Nomme la partie de l'identifiant fautif (contexte sous …TradeParty/SpecifiedLegalOrganization).
        var namesParty = false
    }

    private let officialAssertions: [OfficialAssertion] = [
        OfficialAssertion(
            id: "BR-FR-10_BT-30",
            context: "rsm:CrossIndustryInvoice",
            variables: [("siren", "rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeAgreement/ram:SellerTradeParty/ram:SpecifiedLegalOrganization/ram:ID[@schemeID = '0002']")],
            test: #"$siren and matches(normalize-space($siren), '^\d{9}$')"#),
        OfficialAssertion(
            id: "BR-FR-32-LEGALID",
            context: "//ram:SpecifiedLegalOrganization/ram:ID[@schemeID = '0002']",
            test: #"matches(normalize-space(.), '^\d{9}$')"#,
            namesParty: true),
        OfficialAssertion(
            id: "BR-FR-13_BT-34",
            context: "rsm:CrossIndustryInvoice",
            variables: [("endpointID", "rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeAgreement/ram:SellerTradeParty/ram:URIUniversalCommunication/ram:URIID")],
            test: "string($endpointID)"),
        OfficialAssertion(
            id: "BR-FR-12_BT-49",
            context: "rsm:CrossIndustryInvoice",
            variables: [("endpointID", "rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeAgreement/ram:BuyerTradeParty/ram:URIUniversalCommunication/ram:URIID")],
            test: "string($endpointID)"),
    ]

    private let xqueryProlog = """
    declare namespace rsm = "urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100";
    declare namespace ram = "urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100";

    """

    /// Identifiants des assertions officielles que le XML ne respecte pas, suivis pour BR-FR-32
    /// de la partie en cause, ex. « BR-FR-32-LEGALID SellerTradeParty ».
    private func officialFailures(_ xml: String) throws -> [String] {
        let doc = try XMLDocument(data: Data(xml.utf8))
        var failed: [String] = []
        for assertion in officialAssertions {
            for case let node as XMLNode in try doc.objects(forXQuery: xqueryProlog + assertion.context) {
                let lets = assertion.variables.map { "let $\($0.name) := \($0.select)\n" }.joined()
                let test = "boolean(\(assertion.test))"
                let query = xqueryProlog + (assertion.variables.isEmpty ? test : lets + "return " + test)
                let holds = try XCTUnwrap(node.objects(forXQuery: query).first as? NSNumber, assertion.id).boolValue
                guard !holds else { continue }
                if assertion.namesParty, let party = try node.objects(forXQuery: "local-name(../..)").first as? String {
                    failed.append("\(assertion.id) \(party)")
                } else {
                    failed.append(assertion.id)
                }
            }
        }
        return failed
    }

    /// Règle de l'application qui répond à chaque rejet officiel : le SIREN du vendeur relève
    /// de BR-FR-10 seule, même quand BR-FR-32 le vise aussi.
    private func appRule(forOfficial id: String) -> String {
        switch id {
        case "BR-FR-10_BT-30", "BR-FR-32-LEGALID SellerTradeParty": return "BR-FR-10"
        case "BR-FR-32-LEGALID BuyerTradeParty": return "BR-FR-32"
        case "BR-FR-13_BT-34": return "BR-FR-13"
        case "BR-FR-12_BT-49": return "BR-FR-12"
        default: return id
        }
    }

    /// Chaque cas : les rejets officiels attendus sur le XML généré (mêmes résultats avec Saxon
    /// et le XSLT officiel, vérifié le 2026-09-24), et l'application bloque exactement ces
    /// factures-là, par la règle correspondante.
    func testTheAppBlocksExactlyWhatTheOfficialSirenAssertionsReject() throws {
        let cases: [(String, Invoice, [String])] = [
            ("SIREN valides", invoice(), []),
            ("vendeur sans SIREN, avec adresse", invoice { $0.seller.siren = nil }, ["BR-FR-10_BT-30"]),
            ("vendeur au SIREN vidé", invoice { $0.seller.siren = "" }, ["BR-FR-10_BT-30"]),
            ("vendeur sans SIREN ni adresse", invoice { $0.seller.siren = nil; $0.seller.endpointID = nil },
             ["BR-FR-10_BT-30", "BR-FR-13_BT-34"]),
            ("SIREN du vendeur à 8 chiffres", invoice { $0.seller.siren = "73282932" },
             ["BR-FR-10_BT-30", "BR-FR-32-LEGALID SellerTradeParty"]),
            ("SIREN du vendeur à 10 chiffres", invoice { $0.seller.siren = "7328293201" },
             ["BR-FR-10_BT-30", "BR-FR-32-LEGALID SellerTradeParty"]),
            ("SIREN du vendeur avec des espaces", invoice { $0.seller.siren = "732 829 320" },
             ["BR-FR-10_BT-30", "BR-FR-32-LEGALID SellerTradeParty"]),
            ("SIREN du vendeur avec une lettre", invoice { $0.seller.siren = "7328293A0" },
             ["BR-FR-10_BT-30", "BR-FR-32-LEGALID SellerTradeParty"]),
            ("espaces autour des SIREN", invoice { $0.seller.siren = " 732829320 "; $0.buyer.siren = " 303265045" }, []),
            ("SIREN du vendeur à clé fausse", invoice { $0.seller.siren = "732829321" }, []),
            ("identifiant légal du vendeur de schéma 0208",
             invoice { $0.seller.siren = "0123456789"; $0.seller.legalSchemeID = "0208" }, ["BR-FR-10_BT-30"]),
            ("SIREN de l'acheteur à 8 chiffres", invoice { $0.buyer.siren = "30326504" }, ["BR-FR-32-LEGALID BuyerTradeParty"]),
            ("SIREN de l'acheteur avec des espaces", invoice { $0.buyer.siren = "303 265 045" }, ["BR-FR-32-LEGALID BuyerTradeParty"]),
            ("SIREN de l'acheteur à clé fausse", invoice { $0.buyer.siren = "303265046" }, []),
            ("acheteur sans SIREN, avec adresse", invoice { $0.buyer.siren = nil }, []),
            ("acheteur sans SIREN ni adresse", invoice { $0.buyer.siren = nil; $0.buyer.endpointID = nil }, ["BR-FR-12_BT-49"]),
            ("identifiant légal de l'acheteur de schéma 0208",
             invoice { $0.buyer.siren = "0123456789"; $0.buyer.legalSchemeID = "0208" }, []),
        ]
        for (label, invoice, expected) in cases {
            let official = try officialFailures(xml(invoice))
            XCTAssertEqual(official, expected, label)
            let appErrors = EN16931BusinessRules.evaluate(invoice: invoice)
                .filter { $0.severity == .error && sirenRuleIDs.contains($0.ruleId) }.map(\.ruleId)
            XCTAssertEqual(Set(appErrors), Set(official.map(appRule(forOfficial:))), label)
            XCTAssertEqual(isExportable(invoice), official.isEmpty, label)
        }
    }
}
