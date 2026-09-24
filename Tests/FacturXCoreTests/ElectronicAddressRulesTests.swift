import XCTest
@testable import FacturXCore

/// Adresse électronique de l'émetteur (BT-34) et du destinataire (BT-49) sous le schéma 0225
/// de l'annuaire, constat du 2026-09-24 (croisement de la PR #156 avec les validateurs
/// officiels). Schematron France CTC, règle fatale BR-FR-23 (BR-FR-23_BT-34, BR-FR-23_BT-49) :
/// `custom:is-valid-schemeid-format(.)`, soit `matches($value, '^[A-Za-z0-9+\-_.]+$')` sans
/// `normalize-space`, sur tout `URIUniversalCommunication/URIID[@schemeID='0225']`.
///
/// L'application ne contrôlait rien : une adresse saisie avec une espace, un « @ » ou un « : »
/// passait l'export, et la PDP rejetait la facture. Le générateur émet l'adresse saisie sans
/// espaces autour, sinon le SIREN, sous le schéma 0225 par défaut (vide, « FR:SIRENE » et
/// « 0183 » deviennent 0225). Règle reprise d'ARVERNX-SaaS : erreur bloquante, sur l'adresse
/// telle qu'émise. Le « + », que le test du Schematron admet mais que ni son message ni
/// l'Annexe A ne citent, y est refusé aussi.
final class ElectronicAddressRulesTests: XCTestCase {

    // MARK: - Outils

    /// Facture conforme aux validateurs officiels, adresses 0225 saisies des deux côtés.
    private func invoice(_ adjust: (inout Invoice) -> Void = { _ in }) -> Invoice {
        var invoice = Invoice(
            number: "2026-0301",
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

    private func addressRules(_ invoice: Invoice, context: EN16931RuleContext = .issued) -> [BusinessRuleResult] {
        EN16931BusinessRules.evaluate(invoice: invoice, context: context).filter { $0.ruleId == "BR-FR-23" }
    }

    /// Ce qui bloque l'export, le dépôt SUPER PDP et sa validation (pré-contrôle de l'éditeur).
    private func isExportable(_ invoice: Invoice) -> Bool {
        FacturXValidator().validate(invoice: invoice).isValid
    }

    private func xml(_ invoice: Invoice) throws -> String {
        String(decoding: try CIIXMLGenerator().generate(invoice: invoice), as: UTF8.self)
    }

    /// Adresses refusées en 0225 : espace, « @ », « : », « / », accent, tabulation, espace
    /// insécable, chiffres pleine chasse, « & » (échappé dans le XML), « , », « # ».
    private let malformedAddresses = [
        "732829320 01", "factures@acme.fr", "urn:732829320", "732829320/01", "732829320_Comptabilité",
        "732829320\t01", "732829320\u{00A0}01", "７３２８２９３２０", "732829320&01", "732829320,01", "732829320#01",
    ]

    // MARK: - Adresse saisie

    /// Formes de l'annuaire : SIREN, SIREN_SIRET, SIREN_suffixe, SIREN_SIRET_code de routage. Le
    /// destinataire reçoit la même adresse sur son propre SIREN : une adresse 0225 qui ne le
    /// désigne pas est bloquée par BR-FR-21 (`FrenchBuyerB2BRulesTests`).
    func testDirectoryAddressesOfLettersDigitsAndSeparatorsAreAdmitted() {
        for address in ["732829320", "732829320_73282932000074", "732829320_FACTURES",
                        "732829320_73282932000074_SERVICE-ACHATS.01", "abcXYZ-_.09"] {
            let buyerAddress = address.hasPrefix("732829320") ? "303265045" + address.dropFirst(9) : "303265045_" + address
            let invoice = invoice { $0.seller.endpointID = address; $0.buyer.endpointID = buyerAddress }
            XCTAssertEqual(addressRules(invoice).map(\.message), [], address)
            XCTAssertTrue(isExportable(invoice), address)
        }
    }

    func testAMalformedSellerAddressBlocks() {
        for address in malformedAddresses {
            let invoice = invoice { $0.seller.endpointID = address }
            let rules = addressRules(invoice)
            XCTAssertEqual(rules.map(\.severity), [.error], address)
            XCTAssertTrue(rules.first?.message.contains("(BT-34)") == true, address)
            XCTAssertTrue(rules.first?.message.contains("« \(address) »") == true, address)
            XCTAssertTrue(rules.first?.message.contains("0225") == true, address)
            XCTAssertFalse(isExportable(invoice), address)
        }
    }

    func testAMalformedBuyerAddressBlocks() {
        for address in malformedAddresses {
            let invoice = invoice { $0.buyer.endpointID = address }
            let rules = addressRules(invoice)
            XCTAssertEqual(rules.map(\.severity), [.error], address)
            XCTAssertTrue(rules.first?.message.contains("(BT-49)") == true, address)
            XCTAssertTrue(rules.first?.message.contains("« \(address) »") == true, address)
            XCTAssertFalse(isExportable(invoice), address)
        }
    }

    func testBothMalformedAddressesRaiseOneErrorEach() {
        let messages = addressRules(invoice { $0.seller.endpointID = "a b"; $0.buyer.endpointID = "c@d" }).map(\.message)
        XCTAssertEqual(messages.count, 2)
        XCTAssertTrue(messages.first?.contains("(BT-34) « a b »") == true)
        XCTAssertTrue(messages.last?.contains("(BT-49) « c@d »") == true)
    }

    /// Le générateur retire les espaces et retours à la ligne d'autour : seule l'adresse émise
    /// compte, et le message la cite telle quelle.
    func testTheRuleChecksTheAddressAsEmitted() throws {
        let harmless = invoice { $0.seller.endpointID = " 732829320_FACTURES\n"; $0.buyer.endpointID = "\t303265045 " }
        XCTAssertEqual(addressRules(harmless).map(\.message), [])
        let xml = try xml(harmless)
        XCTAssertTrue(xml.contains(#"<ram:URIID schemeID="0225">732829320_FACTURES</ram:URIID>"#))
        XCTAssertTrue(xml.contains(#"<ram:URIID schemeID="0225">303265045</ram:URIID>"#))

        let inner = invoice { $0.seller.endpointID = "  732829320 01 " }
        XCTAssertTrue(try self.xml(inner).contains(#"<ram:URIID schemeID="0225">732829320 01</ram:URIID>"#))
        XCTAssertTrue(addressRules(inner).first?.message.contains("« 732829320 01 »") == true)
    }

    /// Le « + » passe le test du Schematron (`[A-Za-z0-9+\-_.]`), mais ni son message (« Seuls
    /// les caractères alphanumériques et les symboles "-", "_", "." sont autorisés ») ni
    /// l'Annexe A ne le citent : refusé, comme dans ARVERNX-SaaS.
    func testThePlusSignIsRefusedLikeInTheAnnexA() {
        let invoice = invoice { $0.seller.endpointID = "732829320+01" }
        XCTAssertEqual(addressRules(invoice).map(\.severity), [.error])
        XCTAssertFalse(isExportable(invoice))
    }

    // MARK: - Schéma

    /// La règle suit le schéma qu'écrit le générateur : 0225 aussi pour un schéma vide,
    /// « FR:SIRENE » (ancienne valeur) ou « 0183 », et espaces d'autour retirés.
    func testSchemesEmittedAs0225AreChecked() throws {
        for scheme in ["0225", "", "  ", "FR:SIRENE", "0183", " 0225 "] {
            let invoice = invoice { $0.seller.endpointID = "a b"; $0.seller.endpointSchemeID = scheme }
            XCTAssertTrue(try xml(invoice).contains(#"<ram:URIID schemeID="0225">a b</ram:URIID>"#), "« \(scheme) »")
            XCTAssertEqual(addressRules(invoice).count, 1, "« \(scheme) »")
        }
    }

    /// BR-FR-23 ne vise que le schéma 0225 : le format d'une adresse d'un autre schéma n'est
    /// contrôlé par aucun Schematron.
    func testAddressesOfAnotherSchemeAreNotChecked() {
        for scheme in ["0200", "0193", "0088"] {
            let invoice = invoice { $0.buyer.endpointID = "factures@acme.fr"; $0.buyer.endpointSchemeID = scheme }
            XCTAssertEqual(addressRules(invoice).map(\.message), [], scheme)
            XCTAssertTrue(isExportable(invoice), scheme)
        }
    }

    // MARK: - Adresse déduite du SIREN

    /// Sans adresse saisie, le générateur émet le SIREN sous le schéma 0225 : c'est lui que la
    /// règle contrôle, et le message le dit. Pour le vendeur, BR-FR-10 le signale aussi.
    func testAnAddressDerivedFromAMalformedSirenBlocks() {
        for endpoint in [nil, "", "   "] as [String?] {
            let label = "adresse \(endpoint.map { "« \($0) »" } ?? "nil")"
            let seller = invoice { $0.seller.endpointID = endpoint; $0.seller.siren = " 732 829 320" }
            let sellerRules = addressRules(seller)
            XCTAssertEqual(sellerRules.map(\.severity), [.error], label)
            XCTAssertTrue(sellerRules.first?.message.contains("(BT-34)") == true, label)
            XCTAssertTrue(sellerRules.first?.message.contains("SIREN « 732 829 320 »") == true, label)
            XCTAssertTrue(EN16931BusinessRules.evaluate(invoice: seller).contains { $0.ruleId == "BR-FR-10" }, label)

            // Identifiant légal d'un autre schéma (n° d'entreprise belge) : BR-FR-32 ne le vise
            // pas, mais il part en adresse 0225.
            let buyer = invoice {
                $0.buyer.endpointID = endpoint; $0.buyer.siren = "BE 0123 456 789"; $0.buyer.legalSchemeID = "0208"
            }
            let buyerRules = addressRules(buyer)
            XCTAssertEqual(buyerRules.map(\.severity), [.error], label)
            XCTAssertTrue(buyerRules.first?.message.contains("(BT-49)") == true, label)
            XCTAssertTrue(buyerRules.first?.message.contains("SIREN « BE 0123 456 789 »") == true, label)
            XCTAssertFalse(isExportable(buyer), label)
        }
    }

    /// Un SIREN de 9 chiffres donne une adresse admise ; sans SIREN ni adresse, rien n'est
    /// émis (BR-FR-12 / BR-FR-13 le signalent).
    func testAnAddressDerivedFromAWellFormedSirenOrAbsentIsFine() {
        XCTAssertEqual(addressRules(invoice { $0.seller.endpointID = nil; $0.buyer.endpointID = nil }).map(\.message), [])
        XCTAssertEqual(addressRules(invoice {
            $0.seller.endpointID = nil; $0.seller.siren = nil; $0.buyer.endpointID = ""; $0.buyer.siren = ""
        }).map(\.message), [])
    }

    // MARK: - Facture reçue

    /// Contrôle de format, comme celui du SIREN : en erreur sur une facture reçue aussi.
    func testAReceivedInvoiceChecksTheAddressFormatToo() {
        XCTAssertEqual(addressRules(invoice { $0.seller.endpointID = "factures@acme.fr" }, context: .received).map(\.severity), [.error])
        XCTAssertEqual(addressRules(invoice(), context: .received).map(\.message), [])
    }

    // MARK: - Adresse émise, validateur et liseré

    /// Variantes d'une partie : adresse saisie (rognée, schéma ramené à 0225 ou non), adresse
    /// déduite du SIREN, aucune adresse.
    private let partyVariants: [(String, (inout InvoiceParty) -> Void)] = [
        ("SIREN_suffixe", { $0.endpointID = "732829320_FACTURES" }),
        ("espaces autour, schéma vide", { $0.endpointID = " a b \n"; $0.endpointSchemeID = "" }),
        ("schéma FR:SIRENE", { $0.endpointID = "x@y"; $0.endpointSchemeID = "FR:SIRENE" }),
        ("schéma 0183", { $0.endpointID = "x"; $0.endpointSchemeID = "0183" }),
        ("schéma 0200 entouré d'espaces", { $0.endpointID = "x@y"; $0.endpointSchemeID = " 0200 " }),
        ("déduite du SIREN", { $0.endpointID = nil; $0.siren = " 732829320 " }),
        ("déduite d'un SIREN à espaces", { $0.endpointID = "  "; $0.siren = "BE 0123" }),
        ("aucune adresse", { $0.endpointID = nil; $0.siren = nil }),
        ("adresse et SIREN vidés", { $0.endpointID = ""; $0.siren = "" }),
    ]

    /// Adresse et schéma portés par le XML pour une partie, « adresse|schéma » ; `nil` sans
    /// `URIUniversalCommunication`.
    private func emittedEndpoint(_ xml: String, _ tradeParty: String) throws -> String? {
        let doc = try XMLDocument(data: Data(xml.utf8))
        let path = "rsm:CrossIndustryInvoice/rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeAgreement/ram:\(tradeParty)/ram:URIUniversalCommunication/ram:URIID"
        guard let node = try doc.objects(forXQuery: xqueryProlog + path).first as? XMLElement else { return nil }
        return "\(node.stringValue ?? "")|\(node.attribute(forName: "schemeID")?.stringValue ?? "")"
    }

    /// `CIIXMLGenerator.xmlEndpoint`, que la règle contrôle, est bien ce qu'écrit le XML.
    func testXmlEndpointIsWhatTheXMLCarries() throws {
        for (label, adjust) in partyVariants {
            let invoice = invoice { adjust(&$0.seller); adjust(&$0.buyer) }
            let xml = try xml(invoice)
            XCTAssertEqual(CIIXMLGenerator.xmlEndpoint(invoice.seller).map { "\($0.id)|\($0.schemeID)" },
                           try emittedEndpoint(xml, "SellerTradeParty"), label)
            XCTAssertEqual(CIIXMLGenerator.xmlEndpoint(invoice.buyer).map { "\($0.id)|\($0.schemeID)" },
                           try emittedEndpoint(xml, "BuyerTradeParty"), label)
        }
        XCTAssertEqual(CIIXMLGenerator.xmlEndpoint(invoice().seller).map { "\($0.id)|\($0.schemeID)" }, "732829320|0225")
        XCTAssertNil(CIIXMLGenerator.xmlEndpoint(invoice { $0.seller.endpointID = nil; $0.seller.siren = nil }.seller))
    }

    /// `hasAdmittedElectronicAddress`, qui pilote le liseré de la partie dans l'éditeur, dit la
    /// même chose que la règle, partie par partie.
    func testHasAdmittedElectronicAddressAgreesWithTheRule() {
        let malformed: [(inout InvoiceParty) -> Void] = malformedAddresses.map { address in { $0.endpointID = address } }
        for (idx, adjust) in (partyVariants.map(\.1) + malformed).enumerated() {
            for sellerSide in [true, false] {
                let invoice = invoice {
                    if sellerSide { adjust(&$0.seller) } else { adjust(&$0.buyer) }
                }
                let failures = appFailures(invoice)
                XCTAssertEqual(invoice.seller.hasAdmittedElectronicAddress, !failures.contains("BR-FR-23_BT-34"), "cas \(idx)")
                XCTAssertEqual(invoice.buyer.hasAdmittedElectronicAddress, !failures.contains("BR-FR-23_BT-49"), "cas \(idx)")
            }
        }
    }

    func testIsWellFormedDirectoryAddress() {
        for address in ["732829320", "732829320_73282932000074_CODE", "a-b_c.d", "Z9"] {
            XCTAssertTrue(ElectronicAddressValidator.isWellFormedDirectoryAddress(address), address)
        }
        // Espaces d'autour compris : c'est au générateur de les retirer. « + » refusé (Annexe A).
        for address in ["", " 732829320", "732829320 ", "a+b", "a@b", "é", "e\u{0301}", "٣", "７", "a\nb"] {
            XCTAssertFalse(ElectronicAddressValidator.isWellFormedDirectoryAddress(address), address)
        }
    }

    // MARK: - Assertion officielle, rejouée sur le XML

    /// Assertions BR-FR-23 du Schematron France CTC (`cii-schematron-fr-ctc/BR-FR-Flux2-Schematron-CII.xslt`
    /// du paquet factur-x 6.8, flag fatal) : contexte recopié tel quel, test = corps de la fonction
    /// `custom:is-valid-schemeid-format`, recopié tel quel avec `.` pour `$value`. Évalué en
    /// valeur booléenne effective, comme un `xsl:when`. Même banc que `SirenRulesTests`.
    private let officialAssertions: [(id: String, context: String)] = [
        ("BR-FR-23_BT-34", "rsm:CrossIndustryInvoice/rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeAgreement/ram:SellerTradeParty/ram:URIUniversalCommunication/ram:URIID[@schemeID='0225']"),
        ("BR-FR-23_BT-49", "rsm:CrossIndustryInvoice/rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeAgreement/ram:BuyerTradeParty/ram:URIUniversalCommunication/ram:URIID[@schemeID='0225']"),
    ]
    private let officialTest = #"matches(., '^[A-Za-z0-9+\-_.]+$')"#

    private let xqueryProlog = """
    declare namespace rsm = "urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100";
    declare namespace ram = "urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100";

    """

    /// Identifiants des assertions officielles que le XML ne respecte pas.
    private func officialFailures(_ xml: String) throws -> [String] {
        let doc = try XMLDocument(data: Data(xml.utf8))
        var failed: [String] = []
        for assertion in officialAssertions {
            for case let node as XMLNode in try doc.objects(forXQuery: xqueryProlog + assertion.context) {
                let holds = try XCTUnwrap(node.objects(forXQuery: "boolean(\(officialTest))").first as? NSNumber, assertion.id)
                if !holds.boolValue { failed.append(assertion.id) }
            }
        }
        return failed
    }

    /// Équivalent officiel des erreurs BR-FR-23 de l'application, d'après la partie citée.
    private func appFailures(_ invoice: Invoice) -> [String] {
        addressRules(invoice).map { $0.message.contains("(BT-34)") ? "BR-FR-23_BT-34" : "BR-FR-23_BT-49" }
    }

    /// Le banc lui-même : une adresse modifiée à la main dans un XML conforme fait échouer
    /// l'assertion de sa partie, et seulement sous le schéma 0225 (mêmes verdicts que Saxon avec
    /// le XSLT officiel, vérifié le 2026-09-24).
    func testTheReplayedAssertionFiresOnHandEditedAddresses() throws {
        let valid = try xml(invoice())
        XCTAssertEqual(try officialFailures(valid), [])
        let seller = #"<ram:URIID schemeID="0225">732829320</ram:URIID>"#
        let buyer = #"<ram:URIID schemeID="0225">303265045</ram:URIID>"#
        XCTAssertTrue(valid.contains(seller) && valid.contains(buyer))
        func edited(_ original: String, _ replacement: String) throws -> [String] {
            try officialFailures(valid.replacingOccurrences(of: original, with: replacement))
        }
        XCTAssertEqual(try edited(seller, #"<ram:URIID schemeID="0225">732 829 320</ram:URIID>"#), ["BR-FR-23_BT-34"])
        XCTAssertEqual(try edited(seller, #"<ram:URIID schemeID="0225"> 732829320</ram:URIID>"#), ["BR-FR-23_BT-34"])
        XCTAssertEqual(try edited(seller, #"<ram:URIID schemeID="0225"></ram:URIID>"#), ["BR-FR-23_BT-34"])
        XCTAssertEqual(try edited(buyer, #"<ram:URIID schemeID="0225">a@b.fr</ram:URIID>"#), ["BR-FR-23_BT-49"])
        XCTAssertEqual(try edited(buyer, #"<ram:URIID schemeID="0225">a+b</ram:URIID>"#), [])
        XCTAssertEqual(try edited(buyer, #"<ram:URIID schemeID="0200">a@b.fr</ram:URIID>"#), [])
    }

    /// Chaque cas : les rejets officiels attendus sur le XML généré (mêmes résultats avec Saxon
    /// et le XSLT officiel, vérifié le 2026-09-24), et l'application bloque exactement ces
    /// factures-là, par BR-FR-23 sur la même partie. Seul écart, voulu : le « + »
    /// (`testThePlusSignIsRefusedLikeInTheAnnexA`).
    func testTheAppBlocksExactlyWhatTheOfficialAssertionRejects() throws {
        let cases: [(String, Invoice, [String])] = [
            ("adresses valides", invoice(), []),
            ("SIREN_SIRET et SIREN_suffixe", invoice { $0.seller.endpointID = "732829320_73282932000074"; $0.buyer.endpointID = "303265045_ACHATS-2.B" }, []),
            ("espaces autour", invoice { $0.seller.endpointID = " 732829320 "; $0.buyer.endpointID = "303265045\n" }, []),
            ("espace à l'intérieur", invoice { $0.seller.endpointID = "732829320 01" }, ["BR-FR-23_BT-34"]),
            ("adresse e-mail", invoice { $0.seller.endpointID = "factures@acme.fr" }, ["BR-FR-23_BT-34"]),
            ("« : »", invoice { $0.buyer.endpointID = "urn:303265045" }, ["BR-FR-23_BT-49"]),
            ("« / »", invoice { $0.seller.endpointID = "732829320/01" }, ["BR-FR-23_BT-34"]),
            ("accent", invoice { $0.buyer.endpointID = "303265045_Comptabilité" }, ["BR-FR-23_BT-49"]),
            ("tabulation", invoice { $0.seller.endpointID = "732829320\t01" }, ["BR-FR-23_BT-34"]),
            ("espace insécable", invoice { $0.buyer.endpointID = "303265045\u{00A0}01" }, ["BR-FR-23_BT-49"]),
            ("chiffres pleine chasse", invoice { $0.seller.endpointID = "７３２８２９３２０" }, ["BR-FR-23_BT-34"]),
            ("« & » échappé", invoice { $0.seller.endpointID = "732829320&01" }, ["BR-FR-23_BT-34"]),
            ("les deux parties", invoice { $0.seller.endpointID = "a b"; $0.buyer.endpointID = "c d" }, ["BR-FR-23_BT-34", "BR-FR-23_BT-49"]),
            ("schéma vide", invoice { $0.seller.endpointID = "a b"; $0.seller.endpointSchemeID = "" }, ["BR-FR-23_BT-34"]),
            ("schéma FR:SIRENE", invoice { $0.seller.endpointID = "a b"; $0.seller.endpointSchemeID = "FR:SIRENE" }, ["BR-FR-23_BT-34"]),
            ("schéma 0183", invoice { $0.buyer.endpointID = "c d"; $0.buyer.endpointSchemeID = "0183" }, ["BR-FR-23_BT-49"]),
            ("autre schéma 0200", invoice { $0.buyer.endpointID = "factures@acme.fr"; $0.buyer.endpointSchemeID = "0200" }, []),
            ("adresse déduite d'un SIREN à espaces", invoice { $0.seller.endpointID = nil; $0.seller.siren = "732 829 320" }, ["BR-FR-23_BT-34"]),
            ("adresse déduite d'un identifiant 0208", invoice {
                $0.buyer.endpointID = ""; $0.buyer.siren = "BE 0123 456 789"; $0.buyer.legalSchemeID = "0208"
            }, ["BR-FR-23_BT-49"]),
            ("adresse déduite d'un SIREN valide", invoice { $0.seller.endpointID = nil; $0.buyer.endpointID = nil }, []),
        ]
        for (label, invoice, expected) in cases {
            let official = try officialFailures(xml(invoice))
            XCTAssertEqual(official, expected, label)
            XCTAssertEqual(appFailures(invoice), official, label)
            XCTAssertEqual(isExportable(invoice), official.isEmpty, label)
        }
    }
}
