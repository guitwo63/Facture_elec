import XCTest
import CryptoKit
@testable import FacturXCore

/// BR-CL-25 : le schéma de l'adresse électronique émise (BT-34-1, BT-49-1) doit être un code de la
/// liste EAS (liste 17 du codedb Factur-X EN16931, 102 codes, `EASCodeList`). Le Schematron
/// EN16931 refuse tout autre code (« Value of '@schemeID' is not allowed », sans identifiant de
/// règle) ; EXTENDED-CTC-FR le nomme BR-CL-25, fatal. Le sélecteur ne propose que quatre codes
/// admis, mais un import CSV de tiers, un XML reçu ou une ancienne fiche peuvent en apporter un
/// autre (« SIRET », « em » en minuscules…), que le générateur écrit tel quel. Jusqu'ici l'app ne
/// disait rien et la PDP rejetait la facture.
///
/// Décision de Guillaume (2026-09-24) : erreur sur une facture émise, avertissement sur une
/// facture reçue, comme BR-CL-23 pour les unités. Même liste qu'ARVERNX-SaaS (`EAS_CODES`).
final class EASSchemeRuleTests: XCTestCase {

    // MARK: - Outils

    /// Facture conforme aux validateurs officiels, adresses 0225 saisies des deux côtés.
    private func invoice(_ adjust: (inout Invoice) -> Void = { _ in }) -> Invoice {
        var invoice = Invoice(
            number: "2026-0601",
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

    private func rules(_ invoice: Invoice, _ ruleId: String, context: EN16931RuleContext = .issued) -> [BusinessRuleResult] {
        EN16931BusinessRules.evaluate(invoice: invoice, context: context).filter { $0.ruleId == ruleId }
    }

    private func isExportable(_ invoice: Invoice) -> Bool {
        FacturXValidator().validate(invoice: invoice).isValid
    }

    private func xml(_ invoice: Invoice) throws -> String {
        String(decoding: try CIIXMLGenerator().generate(invoice: invoice), as: UTF8.self)
    }

    /// Schémas refusés par le Schematron EN16931, avec une adresse qui passerait sous EM ou 0009.
    private let refused: [(scheme: String, address: String)] = [
        ("SIRET", "73282932000074"),
        ("em", "compta@monentreprise.fr"),
        ("EMAIL", "compta@monentreprise.fr"),
        ("FR:SIRET", "73282932000074"),
        ("0219", "73282932000074"),
        ("1234", "73282932000074"),
    ]

    /// Schémas admis tels que stockés : les quatre proposés, les anciens émis en 0225 (vide,
    /// « FR:SIRENE », « 0183 »), d'autres codes EAS (anciens 0193 et 0200, Peppol 0088, TVA
    /// allemande 9930) et un code entouré d'espaces, que le générateur retire.
    private let admitted = ["0225", "0009", "9957", "EM", "", "FR:SIRENE", "0183", "0193", "0200", "0088", "9930", " EM "]

    // MARK: - Liste

    /// La liste embarquée est la liste 17 du codedb, entière et sans retouche : même nombre de
    /// codes, même empreinte que les codes officiels triés et joints par une espace (calculée sur
    /// `FACTUR-X_EN16931_codedb.xml` de factur-x 6.8 ; même empreinte pour `EAS_CODES` d'ARVERNX).
    func testEmbeddedListIsTheOfficialOne() {
        XCTAssertEqual(EASCodeList.codes.count, 102)
        let digest = SHA256.hash(data: Data(EASCodeList.codes.sorted().joined(separator: " ").utf8))
        XCTAssertEqual(digest.map { String(format: "%02x", $0) }.joined(),
                       "5bcabde1cc5024aab3b0514b3fed920a9dccf9ae856eb326a44ec99da375f30d")
        for code in ["0225", "0009", "9957", "EM", "0002", "0088", "0183", "0193", "0200", "0208", "9930", "AN", "AU"] {
            XCTAssertTrue(EASCodeList.contains(code), code)
        }
        // 0219 et 0220 ne sont que dans la liste d'EXTENDED-CTC-FR : le Schematron EN16931 les refuse.
        for code in ["em", "SIRET", "FR:SIRENE", "", " 0225", "0219", "0220", "0001"] {
            XCTAssertFalse(EASCodeList.contains(code), "« \(code) »")
        }
    }

    func testEveryOfferedSchemeIsAnEASCode() {
        for ref in NormRefs.endpointSchemes {
            XCTAssertTrue(EASCodeList.contains(ref.code), "« \(ref.label) » : schéma refusé par le Schematron (BR-CL-25)")
        }
    }

    // MARK: - BR-CL-25

    /// Sur une facture émise, un schéma hors de la liste bloque l'export, pour l'émetteur comme
    /// pour le destinataire. Le message cite le schéma tel que le XML l'écrit, et la partie.
    func testANonEASSchemeBlocksAnIssuedInvoice() throws {
        for (scheme, address) in refused {
            let seller = invoice { $0.seller.endpointID = address; $0.seller.endpointSchemeID = scheme }
            let buyer = invoice { $0.buyer.endpointID = address; $0.buyer.endpointSchemeID = scheme }
            for (label, invoice, bt) in [("émetteur", seller, "BT-34"), ("destinataire", buyer, "BT-49")] {
                XCTAssertTrue(try xml(invoice).contains(#"<ram:URIID schemeID="\#(scheme)">"#), "\(label), \(scheme)")
                let found = rules(invoice, "BR-CL-25")
                XCTAssertEqual(found.map(\.severity), [.error], "\(label), \(scheme)")
                let message = found.first?.message ?? ""
                XCTAssertTrue(message.contains("« \(scheme) »"), "\(label), \(scheme)")
                XCTAssertTrue(message.contains("\(label == "émetteur" ? "de l'émetteur" : "du destinataire") (\(bt)-1)"), "\(label), \(scheme)")
                XCTAssertTrue(message.contains("liste EAS"), "\(label), \(scheme)")
                XCTAssertTrue(message.contains("la PDP rejetterait la facture"), "\(label), \(scheme)")
                XCTAssertTrue(message.contains("E-mail (EM)"), "\(label), \(scheme)")
                XCTAssertFalse(isExportable(invoice), "\(label), \(scheme)")
            }
        }
    }

    /// Sur une facture reçue, c'est le schéma du fournisseur : un avertissement, sans remède.
    func testANonEASSchemeIsOnlyAWarningOnAReceivedInvoice() {
        for (scheme, address) in refused {
            let invoice = invoice { $0.seller.endpointID = address; $0.seller.endpointSchemeID = scheme }
            let found = rules(invoice, "BR-CL-25", context: .received)
            XCTAssertEqual(found.map(\.severity), [.warning], scheme)
            XCTAssertFalse(found.first?.message.contains("la PDP") == true, scheme)
        }
    }

    /// Les schémas admis passent, émis tels quels ou en 0225, sans BR-CL-25 ni changement du XML.
    func testAdmittedSchemesPass() {
        for scheme in admitted {
            for invoice in [invoice { $0.seller.endpointID = "732829320_ACHATS"; $0.seller.endpointSchemeID = scheme },
                            invoice { $0.buyer.endpointID = "303265045_ACHATS"; $0.buyer.endpointSchemeID = scheme }] {
                XCTAssertEqual(rules(invoice, "BR-CL-25").map(\.message), [], "« \(scheme) »")
                XCTAssertTrue(invoice.seller.hasAdmittedEndpointScheme && invoice.buyer.hasAdmittedEndpointScheme, "« \(scheme) »")
            }
        }
    }

    /// Sans adresse saisie, le générateur émet le SIREN sous 0225 : un schéma stocké hors liste
    /// n'est pas écrit, il n'y a rien à signaler.
    func testAStoredSchemeWithoutAddressIsNotEmitted() throws {
        for address in [nil, "", "  "] as [String?] {
            let invoice = invoice { $0.buyer.endpointID = address; $0.buyer.endpointSchemeID = "SIRET" }
            XCTAssertTrue(try xml(invoice).contains(#"<ram:URIID schemeID="0225">303265045</ram:URIID>"#))
            XCTAssertEqual(rules(invoice, "BR-CL-25").map(\.message), [])
            XCTAssertTrue(invoice.buyer.hasAdmittedEndpointScheme)
        }
    }

    /// Le liseré rouge de l'éditeur vise la partie dont le schéma est refusé, et elle seule.
    func testOnlyThePartyWithTheRefusedSchemeIsFlagged() {
        let invoice = invoice { $0.buyer.endpointID = "factures@client.fr"; $0.buyer.endpointSchemeID = "email" }
        XCTAssertFalse(invoice.buyer.hasAdmittedEndpointScheme)
        XCTAssertTrue(invoice.seller.hasAdmittedEndpointScheme)
    }

    // MARK: - Assertion officielle, rejouée sur le XML

    /// Assertion BR-CL-25 d'`EXTENDED-CTC-FR-CII.xslt` (paquet factur-x 6.8, flag fatal), évaluée
    /// sur chacun de ses contextes `ram:URIUniversalCommunication/ram:URIID[@schemeID]` : test
    /// recopié tel quel, en valeur booléenne effective comme un `xsl:when`. Sa liste compte 104
    /// codes : les 102 du codedb, plus 0219 et 0220, que le Schematron EN16931 refuse (vérifié avec
    /// Saxon le 2026-09-24). Celui-ci lit sa liste dans le codedb (`document(...)`), que XCTest ne
    /// charge pas : l'empreinte de `testEmbeddedListIsTheOfficialOne` en tient lieu.
    private let officialBRCL25 = """
    declare namespace ram = "urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100";
    boolean(((not(contains(normalize-space(@schemeID), ' ')) and contains(' 0002 0007 0009 0037 0060 0088 0096 0097 0106 0130 0135 0142 0147 0151 0154 0158 0170 0177 0183 0184 0188 0190 0191 0192 0193 0194 0195 0196 0198 0199 0200 0201 0202 0203 0204 0205 0208 0209 0210 0211 0212 0213 0215 0216 0217 0218 0219 0220 0221 0225 0230 0235 0240 0244 0242 0245 0246 0248 9910 9913 9914 9915 9918 9919 9920 9922 9923 9924 9925 9926 9927 9928 9929 9930 9931 9932 9933 9934 9935 9936 9937 9938 9939 9940 9941 9942 9943 9944 9945 9946 9947 9948 9949 9950 9951 9952 9953 9957 9959 AN AQ AS AU EM ', concat(' ', normalize-space(@schemeID), ' ')))))
    """

    /// Nombre de contextes de l'assertion (adresses électroniques des parties) où elle tombe.
    private func officialFailures(_ xml: String) throws -> Int {
        let doc = try XMLDocument(data: Data(xml.utf8))
        let contexts = try doc.objects(forXQuery: """
            declare namespace ram = "urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100";
            //ram:URIUniversalCommunication/ram:URIID[@schemeID]
            """).compactMap { $0 as? XMLNode }
        XCTAssertEqual(contexts.count, 2)
        return try contexts.filter { node in
            try XCTUnwrap(node.objects(forXQuery: officialBRCL25).first as? NSNumber).boolValue == false
        }.count
    }

    /// Le banc lui-même, sur des XML retouchés à la main (mêmes verdicts que Saxon).
    func testTheReplayedAssertionFiresOnHandEditedXML() throws {
        let valid = try xml(invoice())
        let seller = #"<ram:URIID schemeID="0225">732829320</ram:URIID>"#
        XCTAssertTrue(valid.contains(seller))
        XCTAssertEqual(try officialFailures(valid), 0)
        for (scheme, failures) in [("SIRET", 1), ("em", 1), ("0219", 0), (" EM ", 0), ("0225 0009", 1)] {
            let edited = valid.replacingOccurrences(of: seller, with: #"<ram:URIID schemeID="\#(scheme)">732829320</ram:URIID>"#)
            XCTAssertEqual(try officialFailures(edited), failures, "« \(scheme) »")
        }
    }

    /// L'application bloque exactement ce que l'assertion officielle refuse, sauf l'écart voulu
    /// de 0219 et 0220 : admis par EXTENDED-CTC-FR, refusés par le Schematron EN16931.
    func testTheErrorMatchesTheOfficialAssertion() throws {
        for scheme in refused.map(\.scheme) + admitted {
            for invoice in [invoice { $0.seller.endpointID = "732829320_ACHATS"; $0.seller.endpointSchemeID = scheme },
                            invoice { $0.buyer.endpointID = "303265045_ACHATS"; $0.buyer.endpointSchemeID = scheme }] {
                let appErrors = rules(invoice, "BR-CL-25").filter { $0.severity == .error }.count
                let official = try officialFailures(xml(invoice))
                XCTAssertEqual(appErrors, scheme == "0219" ? 1 : official, "« \(scheme) »")
            }
        }
    }
}
