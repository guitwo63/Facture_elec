import XCTest
@testable import FacturXCore

/// Schéma de l'adresse électronique (BT-34-1 émetteur, BT-49-1 destinataire), constat du
/// 2026-09-24 (séance BR-FR-23, PR #159). Le sélecteur proposait « SIRET (0183) », « Code RNA
/// (0193) » et « Numéro TVA (0200) » : dans la liste EAS (liste 17 du codedb Factur-X), 0183 est
/// l'IDE suisse, 0193 l'identifiant UBL.BE (Belgique) et 0200 le code d'entité légale lituanien
/// (listes publiques Peppol et de la Commission européenne). Le générateur réécrivait 0183 en
/// 0225 et émettait 0193 et 0200 tels quels : codes EAS valides, le XSD et les Schematron
/// EN16931 et France CTC ne voyaient rien, mais l'adresse ne désignait rien dans l'annuaire
/// français. Aucun schéma e-mail (EM) non plus : le message BR-FR-23 ne pouvait pas le proposer.
///
/// Décision de Guillaume (2026-09-24) : les quatre schémas d'ARVERNX-SaaS, mêmes libellés, et
/// l'avertissement BR-FR-21 d'ARVERNX pour un destinataire français à SIREN dont l'adresse n'est
/// pas dans l'annuaire. Aucune fiche ni aucun document ne portait 0183, 0193 ou 0200 (comptage en
/// lecture seule du 2026-09-24) : pas de migration. Un document déjà émis garde son XML.
final class ElectronicAddressSchemeTests: XCTestCase {

    // MARK: - Outils

    /// Facture conforme aux validateurs officiels, adresses 0225 saisies des deux côtés.
    private func invoice(_ adjust: (inout Invoice) -> Void = { _ in }) -> Invoice {
        var invoice = Invoice(
            number: "2026-0401",
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

    private func order(_ invoice: Invoice) -> SalesOrder {
        SalesOrder(number: "CD2026-0401", type: .order, buyer: invoice.buyer, seller: invoice.seller, lines: invoice.lines)
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

    private func orderXML(_ invoice: Invoice) throws -> String {
        String(decoding: try OrderCIOXMLGenerator().generate(order: order(invoice)), as: UTF8.self)
    }

    /// Une adresse typique de chaque schéma proposé.
    private let offered: [(scheme: String, address: String)] = [
        ("0225", "303265045_73282932000074"),
        ("0009", "30326504500018"),
        ("9957", "FR65303265045"),
        ("EM", "factures@client.fr"),
    ]

    // MARK: - Sélecteur

    /// Les quatre schémas d'ARVERNX-SaaS (`core/organisations/identity.py`, ENDPOINT_SCHEMES, et
    /// leurs libellés dans `web/src/api/societes.ts`), dans le même ordre. Plus de 0183, 0193 ni
    /// 0200, qui désignent un identifiant suisse, belge ou lituanien.
    func testThePickerOffersTheFourSchemesOfARVERNX() {
        XCTAssertEqual(NormRefs.endpointSchemes.map(\.code), ["0225", "0009", "9957", "EM"])
        XCTAssertEqual(NormRefs.endpointSchemes.map(\.label),
                       ["Annuaire français — SIREN (0225)", "SIRET (0009)", "N° TVA français (9957)", "E-mail (EM)"])
        for legacy in ["0183", "0193", "0200"] {
            XCTAssertFalse(NormRefs.endpointSchemes.contains { $0.code == legacy }, legacy)
        }
    }

    /// Chaque schéma proposé part tel quel, avec l'adresse saisie, pour l'émetteur comme pour le
    /// destinataire, en Factur-X comme en Order-X.
    func testEachOfferedSchemeIsEmittedAsChosen() throws {
        for (scheme, address) in offered {
            let expected = #"<ram:URIID schemeID="\#(scheme)">\#(address)</ram:URIID>"#
            let seller = invoice { $0.seller.endpointID = address; $0.seller.endpointSchemeID = scheme }
            let buyer = invoice { $0.buyer.endpointID = address; $0.buyer.endpointSchemeID = scheme }
            XCTAssertTrue(try xml(seller).contains(expected), scheme)
            XCTAssertTrue(try xml(buyer).contains(expected), scheme)
            XCTAssertTrue(try orderXML(seller).contains(expected), scheme)
            XCTAssertTrue(try orderXML(buyer).contains(expected), scheme)
            XCTAssertEqual(CIIXMLGenerator.xmlEndpoint(buyer.buyer).map { "\($0.id)|\($0.schemeID)" }, "\(address)|\(scheme)")
        }
    }

    /// Un document déjà émis garde son XML : « 0183 » (le « SIRET » de l'ancienne liste) et
    /// « FR:SIRENE » (plus ancien encore) partent toujours en 0225, 0193 et 0200 tels quels.
    func testTheSchemesOfTheOldListStillEmitWhatTheyEmitted() throws {
        let cases: [(String, String)] = [("0183", "0225"), ("FR:SIRENE", "0225"), ("", "0225"), ("0193", "0193"), ("0200", "0200")]
        for (stored, emitted) in cases {
            let invoice = invoice { $0.buyer.endpointID = "30326504500018"; $0.buyer.endpointSchemeID = stored }
            let expected = #"<ram:URIID schemeID="\#(emitted)">30326504500018</ram:URIID>"#
            XCTAssertTrue(try xml(invoice).contains(expected), "« \(stored) »")
            XCTAssertTrue(try orderXML(invoice).contains(expected), "« \(stored) »")
        }
    }

    // MARK: - BR-FR-23 : une adresse e-mail sous le schéma de l'annuaire

    /// Une adresse e-mail saisie sous le schéma 0225 reste refusée (BR-FR-23), et le message
    /// propose désormais le schéma e-mail.
    func testAnEmailUnderTheDirectorySchemeSuggestsTheEmailScheme() {
        for scheme in ["0225", "", "FR:SIRENE", "0183"] {
            let seller = rules(invoice { $0.seller.endpointID = "compta@monentreprise.fr"; $0.seller.endpointSchemeID = scheme }, "BR-FR-23")
            let buyer = rules(invoice { $0.buyer.endpointID = "factures@client.fr"; $0.buyer.endpointSchemeID = scheme }, "BR-FR-23")
            for (label, found) in [("émetteur", seller), ("destinataire", buyer)] {
                XCTAssertEqual(found.map(\.severity), [.error], "\(label), « \(scheme) »")
                XCTAssertTrue(found.first?.message.contains("choisissez le schéma « E-mail (EM) »") == true, "\(label), « \(scheme) »")
            }
        }
    }

    /// Une adresse mal formée sans « @ » n'est pas une adresse e-mail : le message garde son
    /// remède, sans parler du schéma e-mail.
    func testOtherMalformedAddressesDoNotMentionTheEmailScheme() {
        for address in ["732829320 01", "urn:732829320", "732829320_Comptabilité"] {
            let found = rules(invoice { $0.seller.endpointID = address }, "BR-FR-23")
            XCTAssertEqual(found.map(\.severity), [.error], address)
            XCTAssertFalse(found.first?.message.contains("EM") == true, address)
            XCTAssertTrue(found.first?.message.contains("videz-la pour émettre le SIREN") == true, address)
        }
        let derived = rules(invoice { $0.seller.endpointID = nil; $0.seller.siren = "732 829 320" }, "BR-FR-23")
        XCTAssertFalse(derived.first?.message.contains("EM") == true)
    }

    /// Sous le schéma EM, l'adresse e-mail passe BR-FR-23 : la facture de l'émetteur est
    /// exportable, sans aucun avertissement sur son adresse.
    func testAnEmailUnderTheEmailSchemeIsExportable() {
        let invoice = invoice { $0.seller.endpointID = "compta@monentreprise.fr"; $0.seller.endpointSchemeID = "EM" }
        XCTAssertEqual(rules(invoice, "BR-FR-23").map(\.message), [])
        XCTAssertEqual(rules(invoice, "BR-FR-21").map(\.message), [])
        XCTAssertTrue(isExportable(invoice))
    }

    // MARK: - BR-FR-21 : destinataire français hors de l'annuaire

    /// Un destinataire établi en France, à SIREN, dont l'adresse n'est pas dans l'annuaire (EM,
    /// 0009, 9957, ou un ancien 0193 / 0200 resté tel quel) : un avertissement, qui cite le
    /// schéma et la forme attendue. La facture reste exportable : un particulier ou un client hors
    /// du e-invoicing peut recevoir sa facture par e-mail.
    func testAFrenchBuyerOutsideTheDirectoryGetsAWarning() {
        let cases: [(String, String, String)] = [
            ("EM", "factures@client.fr", "« E-mail (EM) »"),
            ("0009", "30326504500018", "« SIRET (0009) »"),
            ("9957", "FR65303265045", "« N° TVA français (9957) »"),
            ("0200", "FR65303265045", "« 0200 »"),
            (" EM ", "factures@client.fr", "« E-mail (EM) »"),
        ]
        for (scheme, address, quoted) in cases {
            let invoice = invoice { $0.buyer.endpointID = address; $0.buyer.endpointSchemeID = scheme }
            let found = rules(invoice, "BR-FR-21")
            XCTAssertEqual(found.map(\.severity), [.warning], scheme)
            let message = found.first?.message ?? ""
            XCTAssertTrue(message.contains("(BT-49)"), scheme)
            XCTAssertTrue(message.contains("schéma \(quoted)"), scheme)
            XCTAssertTrue(message.contains("0225"), scheme)
            XCTAssertTrue(message.contains("« 303265045 » ou « 303265045_… »"), scheme)
            XCTAssertTrue(message.contains("hors du e-invoicing"), scheme)
            XCTAssertTrue(isExportable(invoice), scheme)
        }
    }

    /// Pas d'avertissement quand l'adresse émise est dans l'annuaire (saisie en 0225, déduite du
    /// SIREN, ancien schéma émis en 0225), ni hors de son champ : destinataire étranger, sans
    /// SIREN (ou SIREN mal formé, que BR-FR-32 signale), identifiant d'un autre schéma que 0002,
    /// facture reçue, émetteur.
    func testNoWarningInTheDirectoryOrOutsideTheRule() {
        let cases: [(String, Invoice, EN16931RuleContext)] = [
            ("SIREN en 0225", invoice(), .issued),
            ("SIREN_SIRET en 0225", invoice { $0.buyer.endpointID = "303265045_30326504500018" }, .issued),
            ("adresse déduite du SIREN", invoice { $0.buyer.endpointID = nil; $0.buyer.endpointSchemeID = "EM" }, .issued),
            ("adresse vidée", invoice { $0.buyer.endpointID = "  "; $0.buyer.endpointSchemeID = "9957" }, .issued),
            ("ancien 0183, émis en 0225", invoice { $0.buyer.endpointID = "303265045"; $0.buyer.endpointSchemeID = "0183" }, .issued),
            ("ancien FR:SIRENE, émis en 0225", invoice { $0.buyer.endpointSchemeID = "FR:SIRENE" }, .issued),
            ("destinataire belge", invoice {
                $0.buyer.country = "BE"; $0.buyer.endpointID = "factures@client.be"; $0.buyer.endpointSchemeID = "EM"
            }, .issued),
            ("sans SIREN", invoice { $0.buyer.siren = nil; $0.buyer.endpointID = "factures@client.fr"; $0.buyer.endpointSchemeID = "EM" }, .issued),
            ("SIREN vidé", invoice { $0.buyer.siren = " "; $0.buyer.endpointID = "factures@client.fr"; $0.buyer.endpointSchemeID = "EM" }, .issued),
            ("SIREN mal formé", invoice { $0.buyer.siren = "303 265 045"; $0.buyer.endpointID = "factures@client.fr"; $0.buyer.endpointSchemeID = "EM" }, .issued),
            ("identifiant de schéma 0208", invoice {
                $0.buyer.legalSchemeID = "0208"; $0.buyer.endpointID = "factures@client.fr"; $0.buyer.endpointSchemeID = "EM"
            }, .issued),
            ("facture reçue", invoice { $0.buyer.endpointID = "factures@client.fr"; $0.buyer.endpointSchemeID = "EM" }, .received),
            ("émetteur en EM", invoice { $0.seller.endpointID = "compta@monentreprise.fr"; $0.seller.endpointSchemeID = "EM" }, .issued),
        ]
        for (label, invoice, context) in cases {
            XCTAssertEqual(rules(invoice, "BR-FR-21", context: context).map(\.message), [], label)
        }
        // Le pays est comparé sans espaces ni casse : un destinataire « fr » à SIREN est averti.
        let lowercase = invoice { $0.buyer.country = " fr "; $0.buyer.endpointID = "factures@client.fr"; $0.buyer.endpointSchemeID = "EM" }
        XCTAssertEqual(rules(lowercase, "BR-FR-21").map(\.severity), [.warning])
    }

    // MARK: - Assertion officielle BR-FR-21, rejouée sur le XML

    /// Assertion BR-FR-21_BT-49 du Schematron France CTC (`cii-schematron-fr-ctc/BR-FR-Flux2-Schematron-CII.xslt`
    /// du paquet factur-x 6.8, flag fatal), évaluée sur son contexte `rsm:CrossIndustryInvoice` :
    /// variables et test recopiés tels quels, le test en valeur booléenne effective comme un
    /// `xsl:when`. Elle ne vaut qu'avec la note BAR = B2B, que l'application n'émet pas ; le banc
    /// l'ajoute au XML généré, comme la plateforme qui reconnaît une facture entre entreprises
    /// françaises.
    private let officialBRFR21 = """
    declare namespace rsm = "urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100";
    declare namespace ram = "urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100";
    let $barTreatment := rsm:ExchangedDocument/ram:IncludedNote[ram:SubjectCode = 'BAR']/ram:Content
    let $docType := rsm:ExchangedDocument/ram:TypeCode
    let $siren := rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeAgreement/ram:BuyerTradeParty/ram:SpecifiedLegalOrganization/ram:ID
    let $endpointID := rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeAgreement/ram:BuyerTradeParty/ram:URIUniversalCommunication/ram:URIID
    let $endpointSchemeID := rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeAgreement/ram:BuyerTradeParty/ram:URIUniversalCommunication/ram:URIID/@schemeID
    let $isB2B := $barTreatment = 'B2B'
    let $isExcludedDocType := $docType = ('389', '501', '500', '471', '473', '261', '502')
    return boolean(not($isB2B and not($isExcludedDocType)) or (starts-with($endpointID, $siren) and $endpointSchemeID = '0225'))
    """

    private let barB2BNote = "<ram:IncludedNote><ram:Content>B2B</ram:Content><ram:SubjectCode>BAR</ram:SubjectCode></ram:IncludedNote>"

    /// Le XML avec la note BAR = B2B ajoutée dans `ExchangedDocument`.
    private func withBARB2BNote(_ xml: String) throws -> String {
        let closing = "</rsm:ExchangedDocument>"
        XCTAssertEqual(xml.components(separatedBy: closing).count, 2)
        return xml.replacingOccurrences(of: closing, with: barB2BNote + closing)
    }

    /// Vrai si l'assertion officielle tient.
    private func officialBRFR21Holds(_ xml: String) throws -> Bool {
        let root = try XCTUnwrap(XMLDocument(data: Data(xml.utf8)).rootElement())
        return try XCTUnwrap(root.objects(forXQuery: officialBRFR21).first as? NSNumber).boolValue
    }

    /// Le banc lui-même : sans note BAR, l'assertion tient toujours ; avec la note, elle tombe dès
    /// que le schéma du destinataire n'est pas 0225 ou que son adresse ne commence pas par son
    /// SIREN (mêmes verdicts que Saxon avec le XSLT officiel, vérifié le 2026-09-24).
    func testTheReplayedAssertionFiresOnHandEditedXML() throws {
        let valid = try xml(invoice())
        let buyer = #"<ram:URIID schemeID="0225">303265045</ram:URIID>"#
        XCTAssertTrue(valid.contains(buyer))
        XCTAssertTrue(try officialBRFR21Holds(valid))
        XCTAssertTrue(try officialBRFR21Holds(withBARB2BNote(valid)))
        let email = valid.replacingOccurrences(of: buyer, with: #"<ram:URIID schemeID="EM">factures@client.fr</ram:URIID>"#)
        XCTAssertTrue(try officialBRFR21Holds(email))
        XCTAssertFalse(try officialBRFR21Holds(withBARB2BNote(email)))
        let otherSiren = valid.replacingOccurrences(of: buyer, with: #"<ram:URIID schemeID="0225">732829320</ram:URIID>"#)
        XCTAssertFalse(try officialBRFR21Holds(withBARB2BNote(otherSiren)))
        let siret = valid.replacingOccurrences(of: buyer, with: #"<ram:URIID schemeID="0225">303265045_30326504500018</ram:URIID>"#)
        XCTAssertTrue(try officialBRFR21Holds(withBARB2BNote(siret)))
    }

    /// Pour un destinataire français à SIREN, l'application avertit exactement quand l'assertion
    /// officielle tombe sur le XML généré, note BAR = B2B ajoutée. Écart voulu, hors de la décision
    /// du 2026-09-24 : un destinataire sans SIREN ou étranger n'est pas averti (le Schematron
    /// exigerait 0225 sous la note B2B, qu'on ne suppose pas pour eux ; un destinataire français
    /// sans SIREN reçoit l'avertissement BR-FR-11). Une adresse 0225 d'un autre SIREN est une
    /// erreur, comme dans ARVERNX : `FrenchBuyerB2BRulesTests`.
    func testTheWarningMatchesTheOfficialAssertionForAFrenchBuyerWithASiren() throws {
        var cases: [(String, Invoice)] = offered.map { scheme, address in
            ("schéma \(scheme)", invoice { $0.buyer.endpointID = address; $0.buyer.endpointSchemeID = scheme })
        }
        cases += [
            ("adresse déduite du SIREN", invoice { $0.buyer.endpointID = nil; $0.buyer.endpointSchemeID = "EM" }),
            ("ancien 0183", invoice { $0.buyer.endpointID = "303265045_ACHATS"; $0.buyer.endpointSchemeID = "0183" }),
            ("ancien 0193", invoice { $0.buyer.endpointID = "W751234567"; $0.buyer.endpointSchemeID = "0193" }),
            ("ancien 0200", invoice { $0.buyer.endpointID = "FR65303265045"; $0.buyer.endpointSchemeID = "0200" }),
        ]
        for (label, invoice) in cases {
            let official = try officialBRFR21Holds(withBARB2BNote(xml(invoice)))
            XCTAssertEqual(rules(invoice, "BR-FR-21").isEmpty, official, label)
        }
    }
}
