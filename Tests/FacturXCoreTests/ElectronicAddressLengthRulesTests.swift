import XCTest
@testable import FacturXCore

/// Longueur de l'adresse électronique de l'émetteur (BT-34) et du destinataire (BT-49), constat
/// du 2026-09-24 (séance BR-FR-23, PR #159). Schematron France CTC, règle fatale BR-FR-25
/// (BR-FR-25_BT-34, BR-FR-25_BT-49) : `string-length(.) le 125` sur tout
/// `URIUniversalCommunication/URIID` de la partie, quel que soit son schéma.
///
/// L'application ne contrôlait rien : une adresse de plus de 125 caractères passait l'export, et
/// la PDP rejetait la facture. Règle reprise d'ARVERNX-SaaS (`electronic_address.MAX_LENGTH`) :
/// erreur bloquante, sur l'adresse telle qu'émise (`CIIXMLGenerator.xmlEndpoint` : celle saisie,
/// sans espaces autour, sinon le SIREN). `string-length` compte des points de code : ni des
/// caractères Swift (« e » suivi d'un accent combinant en fait deux), ni des unités UTF-16 (un
/// émoji n'en fait qu'un), ni des octets.
final class ElectronicAddressLengthRulesTests: XCTestCase {

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

    private func lengthRules(_ invoice: Invoice, context: EN16931RuleContext = .issued) -> [BusinessRuleResult] {
        EN16931BusinessRules.evaluate(invoice: invoice, context: context).filter { $0.ruleId == "BR-FR-25" }
    }

    /// Ce qui bloque l'export, le dépôt SUPER PDP et sa validation (pré-contrôle de l'éditeur).
    private func isExportable(_ invoice: Invoice) -> Bool {
        FacturXValidator().validate(invoice: invoice).isValid
    }

    private func xml(_ invoice: Invoice) throws -> String {
        String(decoding: try CIIXMLGenerator().generate(invoice: invoice), as: UTF8.self)
    }

    /// Adresse de l'annuaire (caractères admis en 0225) de `length` caractères : le SIREN, « _ »
    /// et un suffixe.
    private func directoryAddress(_ length: Int) -> String {
        "732829320_" + String(repeating: "A", count: length - 10)
    }

    private func a(_ count: Int) -> String { String(repeating: "a", count: count) }

    // MARK: - Limite de 125 caractères

    func testAnAddressOf125CharactersIsAdmitted() {
        let invoice = invoice { $0.seller.endpointID = directoryAddress(125); $0.buyer.endpointID = directoryAddress(125) }
        XCTAssertEqual(lengthRules(invoice).map(\.message), [])
        XCTAssertTrue(isExportable(invoice))
    }

    func testALongerSellerAddressBlocks() {
        for length in [126, 200] {
            let invoice = invoice { $0.seller.endpointID = directoryAddress(length) }
            let rules = lengthRules(invoice)
            XCTAssertEqual(rules.map(\.severity), [.error], "\(length)")
            XCTAssertTrue(rules.first?.message.contains("(BT-34)") == true, "\(length)")
            XCTAssertTrue(rules.first?.message.contains("\(length) caractères") == true, "\(length)")
            XCTAssertTrue(rules.first?.message.contains("125") == true, "\(length)")
            XCTAssertFalse(isExportable(invoice), "\(length)")
            // Caractères admis en 0225 : seule la longueur est en cause.
            XCTAssertFalse(EN16931BusinessRules.evaluate(invoice: invoice).contains { $0.ruleId == "BR-FR-23" }, "\(length)")
        }
    }

    func testALongerBuyerAddressBlocks() {
        for length in [126, 200] {
            let invoice = invoice { $0.buyer.endpointID = directoryAddress(length) }
            let rules = lengthRules(invoice)
            XCTAssertEqual(rules.map(\.severity), [.error], "\(length)")
            XCTAssertTrue(rules.first?.message.contains("(BT-49)") == true, "\(length)")
            XCTAssertTrue(rules.first?.message.contains("\(length) caractères") == true, "\(length)")
            XCTAssertFalse(isExportable(invoice), "\(length)")
        }
    }

    func testBothLongAddressesRaiseOneErrorEach() {
        let messages = lengthRules(invoice {
            $0.seller.endpointID = directoryAddress(126); $0.buyer.endpointID = directoryAddress(130)
        }).map(\.message)
        XCTAssertEqual(messages.count, 2)
        XCTAssertTrue(messages.first?.contains("(BT-34)") == true && messages.first?.contains("126 caractères") == true)
        XCTAssertTrue(messages.last?.contains("(BT-49)") == true && messages.last?.contains("130 caractères") == true)
    }

    /// Le générateur retire les espaces et retours à la ligne d'autour : seule l'adresse émise
    /// compte.
    func testTheRuleCountsTheAddressAsEmitted() throws {
        let padded = invoice {
            $0.seller.endpointID = "  " + directoryAddress(125) + "\n"; $0.buyer.endpointID = "\t" + directoryAddress(125) + " "
        }
        XCTAssertEqual(lengthRules(padded).map(\.message), [])
        XCTAssertTrue(try xml(padded).contains(#"<ram:URIID schemeID="0225">"# + directoryAddress(125) + "</ram:URIID>"))
    }

    // MARK: - Schéma

    /// BR-FR-25 vise l'adresse quel que soit son schéma, contrairement à BR-FR-23 (0225 seulement).
    func testTheLimitAppliesWhateverTheScheme() {
        for scheme in ["0225", "", "FR:SIRENE", "0183", "0200", "0088", "0009"] {
            let long = invoice { $0.buyer.endpointID = directoryAddress(126); $0.buyer.endpointSchemeID = scheme }
            XCTAssertEqual(lengthRules(long).map(\.severity), [.error], "« \(scheme) »")
            XCTAssertFalse(isExportable(long), "« \(scheme) »")
            let admitted = invoice { $0.buyer.endpointID = directoryAddress(125); $0.buyer.endpointSchemeID = scheme }
            XCTAssertEqual(lengthRules(admitted).map(\.message), [], "« \(scheme) »")
        }
    }

    // MARK: - Longueur comptée comme `string-length`

    /// Un « e » suivi d'un accent combinant (U+0301) fait deux points de code, que
    /// `string-length` compte deux fois, là où Swift ne voit qu'un caractère. Schéma 0200, où
    /// BR-FR-23 ne refuse pas l'accent.
    func testACombiningAccentCountsTwice() {
        let combining = a(124) + "e\u{0301}"
        XCTAssertEqual(combining.count, 125)
        let invoice = invoice { $0.buyer.endpointID = combining; $0.buyer.endpointSchemeID = "0200" }
        XCTAssertEqual(lengthRules(invoice).map(\.severity), [.error])
        XCTAssertTrue(lengthRules(invoice).first?.message.contains("126 caractères") == true)

        let precomposed = self.invoice { $0.buyer.endpointID = a(124) + "\u{00E9}"; $0.buyer.endpointSchemeID = "0200" }
        XCTAssertEqual(lengthRules(precomposed).map(\.message), [])
    }

    /// Un émoji (hors du plan multilingue de base) est un seul point de code, mais deux unités
    /// UTF-16. Saxon le compte une fois (vérifié le 2026-09-24). Le moteur XQuery de Foundation le
    /// compte deux fois : ce cas n'est pas rejoué plus bas.
    func testACharacterOutsideTheBasicPlaneCountsOnce() {
        let emoji = a(124) + "\u{1F600}"
        XCTAssertEqual(emoji.utf16.count, 126)
        XCTAssertEqual(lengthRules(invoice { $0.buyer.endpointID = emoji; $0.buyer.endpointSchemeID = "0200" }).map(\.message), [])
        XCTAssertEqual(lengthRules(invoice { $0.buyer.endpointID = "a" + emoji; $0.buyer.endpointSchemeID = "0200" }).map(\.severity), [.error])
    }

    /// Le lecteur XML réunit un retour chariot suivi d'un saut de ligne en un seul saut de ligne
    /// (XML 1.0, § 2.11), que Saxon compte une fois (vérifié le 2026-09-24). Un retour chariot
    /// seul reste un caractère.
    func testACarriageReturnLineFeedCountsOnce() {
        let crlf = a(62) + "\r\n" + a(62)
        XCTAssertEqual(crlf.unicodeScalars.count, 126)
        XCTAssertEqual(lengthRules(invoice { $0.buyer.endpointID = crlf; $0.buyer.endpointSchemeID = "0200" }).map(\.message), [])
        XCTAssertEqual(lengthRules(invoice { $0.buyer.endpointID = "a" + crlf; $0.buyer.endpointSchemeID = "0200" }).map(\.severity), [.error])
        XCTAssertEqual(lengthRules(invoice { $0.buyer.endpointID = a(63) + "\r" + a(62); $0.buyer.endpointSchemeID = "0200" }).map(\.severity), [.error])
    }

    /// `xmlLength` compte comme `string-length` dans le XML émis (mêmes longueurs avec Saxon,
    /// vérifié le 2026-09-24) ; « & », « < », « > » et « " », échappés, restent un caractère.
    func testXmlLengthCountsLikeStringLength() {
        let cases: [(String, Int)] = [
            ("", 0), ("732829320", 9), ("\u{00E9}", 1), ("e\u{0301}", 2), ("\u{1F600}", 1),
            ("a\r\nb", 3), ("a\rb", 3), ("a\nb", 3), ("\r\r\n", 2), ("&<>\"", 4),
        ]
        for (address, expected) in cases {
            XCTAssertEqual(ElectronicAddressValidator.xmlLength(address), expected, address.debugDescription)
        }
        XCTAssertEqual(ElectronicAddressValidator.maxLength, 125)
    }

    // MARK: - Adresse déduite du SIREN

    /// Sans adresse saisie, le générateur émet le SIREN sous le schéma 0225 : c'est lui que la
    /// règle contrôle, et le message le dit. Pour le vendeur, BR-FR-10 le signale aussi.
    func testAnAddressDerivedFromAnOverlongSirenBlocks() {
        for endpoint in [nil, "", "   "] as [String?] {
            let label = "adresse \(endpoint.map { "« \($0) »" } ?? "nil")"
            let seller = invoice { $0.seller.endpointID = endpoint; $0.seller.siren = String(repeating: "7", count: 126) }
            let sellerRules = lengthRules(seller)
            XCTAssertEqual(sellerRules.map(\.severity), [.error], label)
            XCTAssertTrue(sellerRules.first?.message.contains("(BT-34)") == true, label)
            XCTAssertTrue(sellerRules.first?.message.contains("SIREN") == true, label)
            XCTAssertTrue(EN16931BusinessRules.evaluate(invoice: seller).contains { $0.ruleId == "BR-FR-10" }, label)

            // Identifiant légal d'un autre schéma (n° d'entreprise belge) : BR-FR-32 ne le vise
            // pas, mais il part en adresse 0225.
            let buyer = invoice {
                $0.buyer.endpointID = endpoint; $0.buyer.siren = String(repeating: "1", count: 126); $0.buyer.legalSchemeID = "0208"
            }
            let buyerRules = lengthRules(buyer)
            XCTAssertEqual(buyerRules.map(\.severity), [.error], label)
            XCTAssertTrue(buyerRules.first?.message.contains("(BT-49)") == true, label)
            XCTAssertTrue(buyerRules.first?.message.contains("SIREN") == true, label)
            XCTAssertFalse(isExportable(buyer), label)
        }
    }

    // MARK: - Facture reçue, BR-FR-23

    /// Contrôle de format, comme BR-FR-23 : en erreur sur une facture reçue aussi.
    func testAReceivedInvoiceChecksTheLengthToo() {
        XCTAssertEqual(lengthRules(invoice { $0.seller.endpointID = directoryAddress(126) }, context: .received).map(\.severity), [.error])
        XCTAssertEqual(lengthRules(invoice(), context: .received).map(\.message), [])
    }

    /// Une adresse 0225 trop longue et mal formée enfreint les deux règles, signalées chacune.
    func testALongMalformedDirectoryAddressBreaksBothRules() {
        let rules = EN16931BusinessRules.evaluate(invoice: invoice { $0.seller.endpointID = "factures@" + a(120) })
        XCTAssertEqual(rules.map(\.ruleId).filter { $0 == "BR-FR-23" || $0 == "BR-FR-25" }.sorted(), ["BR-FR-23", "BR-FR-25"])
    }

    // MARK: - Liseré de la partie

    /// `hasAdmittedElectronicAddress`, qui pilote le liseré de la partie dans l'éditeur, couvre
    /// aussi la longueur : faux dès que BR-FR-23 ou BR-FR-25 vise l'adresse de cette partie.
    func testHasAdmittedElectronicAddressCoversTheLength() {
        let variants: [(String, admitted: Bool, (inout InvoiceParty) -> Void)] = [
            ("125 caractères", true, { $0.endpointID = self.directoryAddress(125) }),
            ("126 caractères", false, { $0.endpointID = self.directoryAddress(126) }),
            ("126 caractères, schéma 0200", false, { $0.endpointID = self.directoryAddress(126); $0.endpointSchemeID = "0200" }),
            ("accent combinant, schéma 0200", false, { $0.endpointID = self.a(124) + "e\u{0301}"; $0.endpointSchemeID = "0200" }),
            ("SIREN de 126 chiffres", false, { $0.endpointID = nil; $0.siren = String(repeating: "7", count: 126) }),
            ("mal formée et trop longue", false, { $0.endpointID = "factures@" + self.a(120) }),
            ("mal formée, courte", false, { $0.endpointID = "factures@acme.fr" }),
        ]
        for (label, admitted, adjust) in variants {
            for sellerSide in [true, false] {
                let invoice = invoice { if sellerSide { adjust(&$0.seller) } else { adjust(&$0.buyer) } }
                let side = "\(label), \(sellerSide ? "émetteur" : "destinataire")"
                XCTAssertEqual((sellerSide ? invoice.seller : invoice.buyer).hasAdmittedElectronicAddress, admitted, side)
                let parties = Set(EN16931BusinessRules.evaluate(invoice: invoice).filter { $0.ruleId == "BR-FR-23" || $0.ruleId == "BR-FR-25" }
                    .map { $0.message.contains("(BT-34)") ? "BT-34" : "BT-49" })
                XCTAssertEqual(invoice.seller.hasAdmittedElectronicAddress, !parties.contains("BT-34"), side)
                XCTAssertEqual(invoice.buyer.hasAdmittedElectronicAddress, !parties.contains("BT-49"), side)
            }
        }
    }

    // MARK: - Assertion officielle, rejouée sur le XML

    /// Assertions BR-FR-25 du Schematron France CTC (`cii-schematron-fr-ctc/BR-FR-Flux2-Schematron-CII.xslt`
    /// du paquet factur-x 6.8, flag fatal) : contextes et test recopiés tels quels, évalués en
    /// valeur booléenne effective, comme un `xsl:when`. Même banc que `ElectronicAddressRulesTests`.
    private let officialAssertions: [(id: String, context: String)] = [
        ("BR-FR-25_BT-34", "rsm:CrossIndustryInvoice/rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeAgreement/ram:SellerTradeParty/ram:URIUniversalCommunication/ram:URIID"),
        ("BR-FR-25_BT-49", "rsm:CrossIndustryInvoice/rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeAgreement/ram:BuyerTradeParty/ram:URIUniversalCommunication/ram:URIID"),
    ]
    private let officialTest = "string-length(.) le 125"

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

    /// Équivalent officiel des erreurs BR-FR-25 de l'application, d'après la partie citée.
    private func appFailures(_ invoice: Invoice) -> [String] {
        lengthRules(invoice).map { $0.message.contains("(BT-34)") ? "BR-FR-25_BT-34" : "BR-FR-25_BT-49" }
    }

    /// Le banc lui-même : une adresse modifiée à la main dans un XML conforme fait échouer
    /// l'assertion de sa partie au-delà de 125 caractères, quel que soit le schéma (mêmes verdicts
    /// que Saxon avec le XSLT officiel, vérifié le 2026-09-24).
    func testTheReplayedAssertionFiresOnHandEditedAddresses() throws {
        let valid = try xml(invoice())
        XCTAssertEqual(try officialFailures(valid), [])
        let seller = #"<ram:URIID schemeID="0225">732829320</ram:URIID>"#
        let buyer = #"<ram:URIID schemeID="0225">303265045</ram:URIID>"#
        XCTAssertTrue(valid.contains(seller) && valid.contains(buyer))
        func edited(_ original: String, _ replacement: String) throws -> [String] {
            try officialFailures(valid.replacingOccurrences(of: original, with: replacement))
        }
        XCTAssertEqual(try edited(seller, #"<ram:URIID schemeID="0225">"# + directoryAddress(125) + "</ram:URIID>"), [])
        XCTAssertEqual(try edited(seller, #"<ram:URIID schemeID="0225">"# + directoryAddress(126) + "</ram:URIID>"), ["BR-FR-25_BT-34"])
        XCTAssertEqual(try edited(buyer, #"<ram:URIID schemeID="0200">"# + a(126) + "</ram:URIID>"), ["BR-FR-25_BT-49"])
        XCTAssertEqual(try edited(buyer, "<ram:URIID>" + a(126) + "</ram:URIID>"), ["BR-FR-25_BT-49"])
        XCTAssertEqual(try edited(buyer, #"<ram:URIID schemeID="0200">"# + a(124) + "e\u{0301}</ram:URIID>"), ["BR-FR-25_BT-49"])
        XCTAssertEqual(try edited(buyer, #"<ram:URIID schemeID="0200">"# + a(124) + "&amp;</ram:URIID>"), [])
    }

    /// Chaque cas : les rejets officiels attendus sur le XML généré (mêmes résultats avec Saxon
    /// et le XSLT officiel, vérifié le 2026-09-24), et l'application bloque exactement ces
    /// factures-là, par BR-FR-25 sur la même partie. L'émoji, que Foundation compte mal, est
    /// vérifié à part (`testACharacterOutsideTheBasicPlaneCountsOnce`).
    func testTheAppBlocksExactlyWhatTheOfficialAssertionRejects() throws {
        let cases: [(String, Invoice, [String])] = [
            ("adresses courtes", invoice(), []),
            ("125 caractères des deux côtés", invoice {
                $0.seller.endpointID = directoryAddress(125); $0.buyer.endpointID = directoryAddress(125)
            }, []),
            ("126 caractères, émetteur", invoice { $0.seller.endpointID = directoryAddress(126) }, ["BR-FR-25_BT-34"]),
            ("126 caractères, destinataire", invoice { $0.buyer.endpointID = directoryAddress(126) }, ["BR-FR-25_BT-49"]),
            ("les deux parties", invoice {
                $0.seller.endpointID = directoryAddress(200); $0.buyer.endpointID = directoryAddress(126)
            }, ["BR-FR-25_BT-34", "BR-FR-25_BT-49"]),
            ("125 caractères entourés d'espaces", invoice { $0.seller.endpointID = " \t" + directoryAddress(125) + " \n" }, []),
            ("schéma vide", invoice { $0.seller.endpointID = directoryAddress(126); $0.seller.endpointSchemeID = "" }, ["BR-FR-25_BT-34"]),
            ("schéma 0200", invoice { $0.buyer.endpointID = directoryAddress(126); $0.buyer.endpointSchemeID = "0200" }, ["BR-FR-25_BT-49"]),
            ("accent combinant, 126 points de code", invoice {
                $0.buyer.endpointID = a(124) + "e\u{0301}"; $0.buyer.endpointSchemeID = "0200"
            }, ["BR-FR-25_BT-49"]),
            ("accent combinant, 125 points de code", invoice {
                $0.buyer.endpointID = a(123) + "e\u{0301}"; $0.buyer.endpointSchemeID = "0200"
            }, []),
            ("« & » échappé, 125 caractères", invoice { $0.buyer.endpointID = a(124) + "&"; $0.buyer.endpointSchemeID = "0200" }, []),
            ("« & » échappé, 126 caractères", invoice { $0.buyer.endpointID = a(125) + "&"; $0.buyer.endpointSchemeID = "0200" }, ["BR-FR-25_BT-49"]),
            ("retour chariot et saut de ligne, lus 125", invoice {
                $0.buyer.endpointID = a(62) + "\r\n" + a(62); $0.buyer.endpointSchemeID = "0200"
            }, []),
            ("retour chariot et saut de ligne, lus 126", invoice {
                $0.buyer.endpointID = a(63) + "\r\n" + a(62); $0.buyer.endpointSchemeID = "0200"
            }, ["BR-FR-25_BT-49"]),
            ("adresse déduite d'un identifiant 0208 de 126 caractères", invoice {
                $0.buyer.endpointID = nil; $0.buyer.siren = String(repeating: "1", count: 126); $0.buyer.legalSchemeID = "0208"
            }, ["BR-FR-25_BT-49"]),
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
