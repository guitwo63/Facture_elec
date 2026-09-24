import XCTest
import PDFKit
@testable import FacturXCore

/// Factures hors euro : BR-FR-CO-12 (Schematron France CTC, fatal) exige, dès que la devise de
/// facture (BT-5) n'est pas l'euro, la devise de comptabilité EUR (BT-6) et le montant de la TVA
/// en euros (BT-111). Constat du 2026-09-24, reproduit contre les validateurs officiels (XSD
/// Factur-X 1.09, Schematron EN16931, EXTENDED et France CTC, via les paquets Python factur-x et
/// saxonche) : toute facture en USD, GBP, CHF, CAD, JPY ou CNY était rejetée, alors que
/// l'application la déclarait exportable. Vérifié le même jour sur 26 factures générées par
/// l'application : avec un taux de change, le XML passe les trois validateurs, en EN 16931 comme
/// en EXTENDED ; sans taux, l'application bloque l'export (BR-FR-CO-12) exactement comme la PDP ;
/// une facture en euros reste identique à l'octet près, XML et PDF.
///
/// Choix de l'utilisateur (2026-09-24) : un taux de change saisi sur la facture ou repris de la BCE
/// (voir `ECBReferenceRateServiceTests`) ; l'avoir garde le taux de sa facture, les autres copies
/// repartent sans taux.
final class NonEuroCurrencyTests: XCTestCase {

    private let settlementPath = "CrossIndustryInvoice/SupplyChainTradeTransaction/ApplicableHeaderTradeSettlement"

    private let keys = [
        "facturx.invoices.v1",
        "facturx.number.prefix.v1",
        "facturx.number.includeyear.v1",
        "facturx.number.start.v1",
        "facturx.number.useseparator.v1",
        "facturx.number.overrides.bysociety.v1",
    ]

    override func setUp() {
        super.setUp()
        keys.forEach { AppPersistence.defaults.removeObject(forKey: $0) }
    }

    override func tearDown() {
        keys.forEach { AppPersistence.defaults.removeObject(forKey: $0) }
        super.tearDown()
    }

    // MARK: - Outils

    private let seller = InvoiceParty(name: "Mon Entreprise SARL", street: "12 rue du Commerce", postcode: "75001", city: "Paris",
                                      vatNumber: "FR44732829320", siren: "732829320", endpointID: "732829320", endpointSchemeID: "0225")
    private let buyer = InvoiceParty(name: "Client Exemple SAS", street: "8 avenue des Champs", postcode: "75008", city: "Paris",
                                     siren: "303265045", endpointID: "303265045", endpointSchemeID: "0225")

    /// 3 × 123,45 à 20 % : 370,35 HT, TVA 74,07, TTC 444,42. En euros, conforme aux trois
    /// validateurs officiels ; en dollars sans taux, rejetée par BR-FR-CO-12 (vérifié le 2026-09-24).
    private func invoice(_ currency: String = "USD", rate: Double? = nil, profile: FacturXProfile = .en16931,
                         lines: [InvoiceLine]? = nil) -> Invoice {
        Invoice(number: "2026-0101", currency: currency, profile: profile, seller: seller, buyer: buyer, buyerReference: "REF-1",
                lines: lines ?? [InvoiceLine(name: "Article", quantity: 3, unit: "H87", unitPrice: 123.45, vatRate: 20)],
                paymentTerms: "Paiement à 30 jours", billingMode: .m1, exchangeRate: rate)
    }

    private func xml(_ invoice: Invoice) throws -> String {
        String(decoding: try CIIXMLGenerator().generate(invoice: invoice), as: UTF8.self)
    }

    /// Élément désigné par un chemin de noms locaux (préfixes ignorés), ex. "A/B/C".
    private func elements(_ xml: String, _ path: String) throws -> [XMLElement] {
        let doc = try XMLDocument(data: Data(xml.utf8))
        let steps = path.split(separator: "/").map { "*[local-name()='\($0)']" }
        return try doc.nodes(forXPath: "/" + steps.joined(separator: "/")).compactMap { $0 as? XMLElement }
    }

    private func childNames(_ element: XMLElement?) -> [String] {
        element?.children?.compactMap { ($0 as? XMLElement)?.localName } ?? []
    }

    private func rules(_ invoice: Invoice, context: EN16931RuleContext = .issued) -> [BusinessRuleResult] {
        EN16931BusinessRules.evaluate(invoice: invoice, context: context).filter { $0.ruleId == "BR-FR-CO-12" }
    }

    private func pdfText(_ invoice: Invoice) throws -> String {
        try XCTUnwrap(PDFDocument(data: InvoicePDFRenderer().render(invoice: invoice))?.string, "texte du PDF illisible")
    }

    /// Midi du jour donné (AAAA-MM-JJ) dans le fuseau de l'application, comme un cours de la BCE.
    private func day(_ iso: String) -> Date {
        DocumentDate.date(xmlString: iso.replacingOccurrences(of: "-", with: ""))!
    }

    // MARK: - Assertions officielles, rejouées sur le XML

    /// Assertion d'un Schematron officiel recopiée telle quelle depuis le XSLT du paquet factur-x
    /// 6.8 (contexte, variables, test), évaluée en XQuery par `XMLDocument` sur le XML généré. Seule
    /// retouche : dans BR-DEC-13 et BR-DEC-15, `. = round(. * 100) div 100` s'écrit avec `number(.)`.
    /// XPath 2.0 convertit de lui-même l'élément en xs:double ; le XQuery de Foundation lève
    /// « invalid type for operator », et un prédicat en erreur y passe pour faux sans le dire.
    /// `testOfficialAssertionsCatchWhatTheGeneratorMustNeverEmit` vérifie que chaque assertion
    /// détecte bien sa violation dans ce banc.
    private struct OfficialAssertion {
        let id: String
        let context: String
        var variables: [(name: String, select: String)] = []
        let test: String
        /// `successful-report` : signalé quand le test est vrai, et non quand il est faux.
        var isReport = false
    }

    /// Les assertions des Schematron sur les devises et les montants de TVA de l'en-tête.
    private let officialAssertions: [OfficialAssertion] = [
        // cii-schematron-fr-ctc/BR-FR-Flux2-Schematron-CII.xslt (flag fatal).
        OfficialAssertion(
            id: "BR-FR-CO-12_BT-5",
            context: "rsm:CrossIndustryInvoice",
            variables: [
                ("invoiceCurrency", "rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeSettlement/ram:InvoiceCurrencyCode"),
                ("accountingCurrency", "rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeSettlement/ram:TaxCurrencyCode"),
                ("taxAmountEUR", "rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeSettlement/ram:SpecifiedTradeSettlementHeaderMonetarySummation/ram:TaxTotalAmount[@currencyID='EUR']"),
            ],
            test: "not($invoiceCurrency != 'EUR') or ($accountingCurrency = 'EUR' and string($taxAmountEUR))"),
        // facturx-en16931/Factur-X_1.09_EN16931.xsl.
        OfficialAssertion(
            id: "FX-SCH-A-000129 [BR-53]",
            context: "//ram:SpecifiedTradeSettlementHeaderMonetarySummation",
            test: "not(/rsm:CrossIndustryInvoice/rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeSettlement/ram:TaxCurrencyCode) or (/rsm:CrossIndustryInvoice/rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeSettlement/ram:TaxCurrencyCode and (ram:TaxTotalAmount/@currencyID = /rsm:CrossIndustryInvoice/rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeSettlement/ram:TaxCurrencyCode) and not(/rsm:CrossIndustryInvoice/rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeSettlement/ram:TaxCurrencyCode = /rsm:CrossIndustryInvoice/rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeSettlement/ram:InvoiceCurrencyCode))"),
        OfficialAssertion(
            id: "FX-SCH-A-000126 [BR-DEC-15]",
            context: "//ram:SpecifiedTradeSettlementHeaderMonetarySummation",
            test: "not(ram:TaxTotalAmount) or ram:TaxTotalAmount[(@currencyID =/rsm:CrossIndustryInvoice/rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeSettlement/ram:TaxCurrencyCode and number(.) = round(number(.) * 100) div 100) or not (/rsm:CrossIndustryInvoice/rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeSettlement/ram:TaxCurrencyCode)]"),
        OfficialAssertion(
            id: "FX-SCH-A-000007 [BR-DEC-13]",
            context: "//ram:SpecifiedTradeSettlementHeaderMonetarySummation",
            test: "not(ram:TaxTotalAmount) or ram:TaxTotalAmount[(@currencyID =/rsm:CrossIndustryInvoice/rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeSettlement/ram:InvoiceCurrencyCode and number(.) = round(number(.) * 100) div 100) or not (@currencyID =/rsm:CrossIndustryInvoice/rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeSettlement/ram:InvoiceCurrencyCode)]"),
        OfficialAssertion(
            id: "FX-SCH-A-000121 [BR-CO-15]",
            context: "//ram:SpecifiedTradeSettlementHeaderMonetarySummation",
            test: "every $Currency in /rsm:CrossIndustryInvoice/rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeSettlement/ram:InvoiceCurrencyCode satisfies ( ( count(/rsm:CrossIndustryInvoice/rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeSettlement/ram:SpecifiedTradeSettlementHeaderMonetarySummation/ram:TaxTotalAmount[@currencyID = $Currency]) = 1 and xs:decimal((/rsm:CrossIndustryInvoice/rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeSettlement/ram:SpecifiedTradeSettlementHeaderMonetarySummation/ram:GrandTotalAmount)[1]) = round( ( xs:decimal((/rsm:CrossIndustryInvoice/rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeSettlement/ram:SpecifiedTradeSettlementHeaderMonetarySummation/ram:TaxBasisTotalAmount)[1]) + xs:decimal((/rsm:CrossIndustryInvoice/rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeSettlement/ram:SpecifiedTradeSettlementHeaderMonetarySummation/ram:TaxTotalAmount[@currencyID = $Currency])[1]) ) * 100 ) div 100 ) or ( xs:decimal((/rsm:CrossIndustryInvoice/rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeSettlement/ram:SpecifiedTradeSettlementHeaderMonetarySummation/ram:GrandTotalAmount)[1]) = xs:decimal((/rsm:CrossIndustryInvoice/rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeSettlement/ram:SpecifiedTradeSettlementHeaderMonetarySummation/ram:TaxBasisTotalAmount)[1]) ) )"),
        OfficialAssertion(
            id: "FX-SCH-A-000130 [BR-CO-14]",
            context: "//ram:SpecifiedTradeSettlementHeaderMonetarySummation/ram:TaxTotalAmount[@currencyID=/rsm:CrossIndustryInvoice/rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeSettlement/ram:InvoiceCurrencyCode]",
            test: ". = (round(sum(/rsm:CrossIndustryInvoice/rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeSettlement/ram:ApplicableTradeTax/ram:CalculatedAmount)*10*10)div 100)"),
        OfficialAssertion(
            id: "FX-SCH-A-000042",
            context: "/rsm:CrossIndustryInvoice/rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeSettlement/ram:SpecifiedTradeSettlementHeaderMonetarySummation",
            test: "count(ram:TaxTotalAmount[@currencyID=../../ram:InvoiceCurrencyCode])<=1"),
        OfficialAssertion(
            id: "FX-SCH-A-000192",
            context: "/rsm:CrossIndustryInvoice/rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeSettlement/ram:SpecifiedTradeSettlementHeaderMonetarySummation",
            test: "count(ram:TaxTotalAmount[@currencyID=../../ram:TaxCurrencyCode])<=1"),
        OfficialAssertion(
            id: "TaxTotalAmount hors devise de facture et de comptabilité (« not used »)",
            context: "/rsm:CrossIndustryInvoice/rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeSettlement/ram:SpecifiedTradeSettlementHeaderMonetarySummation/ram:TaxTotalAmount[ not(@currencyID=../../ram:InvoiceCurrencyCode) and  not(@currencyID=../../ram:TaxCurrencyCode)]",
            test: "true()",
            isReport: true),
    ]

    private let xqueryProlog = """
    declare namespace rsm = "urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100";
    declare namespace ram = "urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100";
    declare namespace xs = "http://www.w3.org/2001/XMLSchema";

    """

    /// Identifiants des assertions officielles que le XML ne respecte pas.
    private func officialFailures(_ xml: String) throws -> [String] {
        let doc = try XMLDocument(data: Data(xml.utf8))
        var failed: [String] = []
        for assertion in officialAssertions {
            for case let node as XMLNode in try doc.objects(forXQuery: xqueryProlog + assertion.context) {
                let lets = assertion.variables.map { "let $\($0.name) := \($0.select)\n" }.joined()
                let query = xqueryProlog + (assertion.variables.isEmpty ? assertion.test : lets + "return " + assertion.test)
                let holds = try XCTUnwrap(node.objects(forXQuery: query).first as? NSNumber, assertion.id).boolValue
                if holds == assertion.isReport { failed.append(assertion.id) }
            }
        }
        return failed
    }

    /// Le cas demandé contre les validateurs officiels : en dollars, la facture avec taux passe
    /// les assertions officielles sur les devises (et l'application l'exporte) ; sans taux, elle
    /// échoue à BR-FR-CO-12 comme à la PDP, et l'application la bloque par la même règle.
    func testOfficialCurrencyAssertionsAcceptAUSDInvoiceWithARateAndRejectOneWithout() throws {
        let withRate = invoice("USD", rate: 1.1411)
        XCTAssertEqual(try officialFailures(xml(withRate)), [])
        XCTAssertTrue(FacturXValidator().validate(invoice: withRate).isValid)

        let withoutRate = invoice("USD")
        XCTAssertEqual(try officialFailures(xml(withoutRate)), ["BR-FR-CO-12_BT-5"])
        let validation = FacturXValidator().validate(invoice: withoutRate)
        XCTAssertFalse(validation.isValid)
        XCTAssertEqual(validation.businessRules.filter { $0.severity == .error }.map(\.ruleId), ["BR-FR-CO-12"])
    }

    /// Toutes les devises du sélecteur, et EXTENDED : conformes avec un taux, bloquées sans.
    func testEveryPickerCurrencyPassesTheOfficialAssertionsOnlyWithARate() throws {
        for code in NormRefs.currencies.map(\.code) where code != "EUR" {
            for profile in [FacturXProfile.en16931, .extended] {
                let label = "\(code) \(profile.rawValue)"
                XCTAssertEqual(try officialFailures(xml(invoice(code, rate: 1.5, profile: profile))), [], label)
                XCTAssertEqual(try officialFailures(xml(invoice(code, profile: profile))), ["BR-FR-CO-12_BT-5"], label)
                XCTAssertEqual(rules(invoice(code, profile: profile)).count, 1, label)
                XCTAssertTrue(rules(invoice(code, rate: 1.5, profile: profile)).isEmpty, label)
            }
        }
    }

    /// Le banc lui-même : chaque assertion rejouée détecte sa violation, sur des XML retouchés à
    /// la main que le générateur ne produit jamais. Pour chacun, Saxon a donné les mêmes échecs
    /// sur ces assertions le 2026-09-24 (plus le XSD et BR-FR-DEC-01, que ce banc ne rejoue pas).
    /// À noter : un BT-110 à trois décimales échappe à BR-DEC-13 dès qu'un BT-111 est présent,
    /// le prédicat officiel étant satisfait par le montant en euros ; BR-CO-14 le détecte.
    func testOfficialAssertionsCatchWhatTheGeneratorMustNeverEmit() throws {
        let euro = try xml(invoice("EUR"))
        let euroWithTaxCurrency = euro.replacingOccurrences(
            of: "      <ram:InvoiceCurrencyCode>EUR", with: "      <ram:TaxCurrencyCode>EUR</ram:TaxCurrencyCode>\n      <ram:InvoiceCurrencyCode>EUR")
        XCTAssertEqual(try officialFailures(euroWithTaxCurrency), ["FX-SCH-A-000129 [BR-53]"])
        let euroTax = #"<ram:TaxTotalAmount currencyID="EUR">74.07</ram:TaxTotalAmount>"#
        XCTAssertTrue(euro.contains(euroTax))
        XCTAssertEqual(try officialFailures(euro.replacingOccurrences(of: euroTax, with: euroTax.replacingOccurrences(of: "74.07", with: "74.071"))),
                       ["FX-SCH-A-000007 [BR-DEC-13]", "FX-SCH-A-000130 [BR-CO-14]"])

        // 74,07 USD de TVA, 61,72 EUR au taux de 1,2.
        let usd = try xml(invoice("USD", rate: 1.2))
        let usdTax = #"        <ram:TaxTotalAmount currencyID="USD">74.07</ram:TaxTotalAmount>"#
        let eurTax = #"        <ram:TaxTotalAmount currencyID="EUR">61.72</ram:TaxTotalAmount>"#
        XCTAssertTrue(usd.contains(usdTax + "\n" + eurTax + "\n"))
        let cases: [(String, String, String, [String])] = [
            ("BT-111 à trois décimales", eurTax, eurTax.replacingOccurrences(of: "61.72", with: "61.725"),
             ["FX-SCH-A-000126 [BR-DEC-15]"]),
            ("BT-6 sans BT-111", eurTax + "\n", "",
             ["BR-FR-CO-12_BT-5", "FX-SCH-A-000129 [BR-53]", "FX-SCH-A-000126 [BR-DEC-15]"]),
            ("BT-110 à trois décimales", usdTax, usdTax.replacingOccurrences(of: "74.07", with: "74.071"),
             ["FX-SCH-A-000130 [BR-CO-14]"]),
            ("BT-110 faux", usdTax, usdTax.replacingOccurrences(of: "74.07", with: "74.08"),
             ["FX-SCH-A-000121 [BR-CO-15]", "FX-SCH-A-000130 [BR-CO-14]"]),
            ("BT-110 en double", usdTax, usdTax + "\n" + usdTax,
             ["FX-SCH-A-000121 [BR-CO-15]", "FX-SCH-A-000042"]),
            ("TVA dans une troisième devise", eurTax, eurTax + "\n" + eurTax.replacingOccurrences(of: "EUR", with: "GBP"),
             ["TaxTotalAmount hors devise de facture et de comptabilité (« not used »)"]),
        ]
        for (label, original, replacement, expected) in cases {
            XCTAssertEqual(try officialFailures(usd.replacingOccurrences(of: original, with: replacement)), expected, label)
        }
    }

    // MARK: - XML : BT-6 et BT-111

    func testForeignInvoiceWithARateEmitsTheAccountingCurrencyAndTheVATInEuros() throws {
        let s = try xml(invoice("USD", rate: 1.2))
        let settlement = try XCTUnwrap(elements(s, settlementPath).first)
        // Ordre du XSD : TaxCurrencyCode avant InvoiceCurrencyCode.
        XCTAssertEqual(Array(childNames(settlement).prefix(2)), ["TaxCurrencyCode", "InvoiceCurrencyCode"])
        XCTAssertEqual(try elements(s, settlementPath + "/TaxCurrencyCode").map(\.stringValue), ["EUR"])
        XCTAssertEqual(try elements(s, settlementPath + "/InvoiceCurrencyCode").map(\.stringValue), ["USD"])

        let summation = try XCTUnwrap(elements(s, settlementPath + "/SpecifiedTradeSettlementHeaderMonetarySummation").first)
        XCTAssertEqual(childNames(summation),
                       ["LineTotalAmount", "TaxBasisTotalAmount", "TaxTotalAmount", "TaxTotalAmount", "GrandTotalAmount", "DuePayableAmount"])
        let taxTotals = try elements(s, settlementPath + "/SpecifiedTradeSettlementHeaderMonetarySummation/TaxTotalAmount")
        XCTAssertEqual(taxTotals.map { $0.attribute(forName: "currencyID")?.stringValue }, ["USD", "EUR"])
        // 74,07 USD ÷ 1,2 = 61,725 : arrondi au pair, 61,72.
        XCTAssertEqual(taxTotals.map(\.stringValue), ["74.07", "61.72"])
        // Les montants en devise de facture ne changent pas.
        XCTAssertEqual(try elements(s, settlementPath + "/SpecifiedTradeSettlementHeaderMonetarySummation/GrandTotalAmount").map(\.stringValue), ["444.42"])
    }

    func testForeignInvoiceWithoutARateEmitsNeither() throws {
        let s = try xml(invoice("USD"))
        XCTAssertTrue(try elements(s, settlementPath + "/TaxCurrencyCode").isEmpty)
        XCTAssertEqual(try elements(s, settlementPath + "/SpecifiedTradeSettlementHeaderMonetarySummation/TaxTotalAmount")
            .map { $0.attribute(forName: "currencyID")?.stringValue }, ["USD"])
    }

    /// BT-6 doit différer de BT-5 (FX-SCH-A-000129) : jamais de BT-6 sur une facture en euros,
    /// même si un taux y est resté (devise repassée en EUR hors éditeur, import…). Le XML est
    /// alors identique à l'octet près à celui d'une facture sans taux, donc à celui d'avant.
    func testEuroInvoiceXMLIsUnchangedByALeftoverRate() throws {
        let plain = try xml(invoice("EUR"))
        XCTAssertEqual(try xml(invoice("EUR", rate: 1.1411)), plain)
        XCTAssertFalse(plain.contains("TaxCurrencyCode"))
        XCTAssertEqual(try elements(plain, settlementPath + "/SpecifiedTradeSettlementHeaderMonetarySummation/TaxTotalAmount")
            .map { $0.attribute(forName: "currencyID")?.stringValue }, ["EUR"])
        XCTAssertNil(invoice("EUR", rate: 1.1411).taxTotalInEuros)
    }

    /// Un export hors UE (catégorie G) a une TVA nulle : BT-111 vaut 0.00, que BR-FR-CO-12 admet.
    func testZeroVATForeignInvoiceEmitsZeroVATInEuros() throws {
        let export = InvoiceLine(name: "Machine", quantity: 1, unit: "H87", unitPrice: 1000, vatRate: 0, vatCategory: .export,
                                 vatExemptionReason: "Exonération de TVA, article 262 I du CGI")
        let s = try xml(invoice("USD", rate: 1.1411, lines: [export]))
        XCTAssertEqual(try elements(s, settlementPath + "/SpecifiedTradeSettlementHeaderMonetarySummation/TaxTotalAmount").map(\.stringValue),
                       ["0.00", "0.00"])
        XCTAssertEqual(try officialFailures(s), [])
    }

    /// La devise est émise sans espaces autour, et c'est cette chaîne que la règle compare à EUR.
    func testCurrencyIsTrimmedInTheXMLAndInTheRule() throws {
        let s = try xml(invoice(" USD ", rate: 1.2))
        XCTAssertEqual(try elements(s, settlementPath + "/InvoiceCurrencyCode").map(\.stringValue), ["USD"])
        XCTAssertEqual(try elements(s, settlementPath + "/SpecifiedTradeSettlementHeaderMonetarySummation/TaxTotalAmount")
            .map { $0.attribute(forName: "currencyID")?.stringValue }, ["USD", "EUR"])
        XCTAssertNil(invoice(" EUR ", rate: 1.2).taxTotalInEuros)
        XCTAssertTrue(rules(invoice(" EUR ")).isEmpty)
    }

    // MARK: - BT-111 : calcul

    /// Arrondi au pair, calculé en décimal comme ARVERNX : en `Double`, 1,15 ÷ 2 (0,575 exactement)
    /// donne 0,57499… et s'arrondit à 0,57 ; le calcul exact donne 0,575, arrondi au pair à 0,58.
    func testVATInEurosIsRoundedHalfEvenOnTheExactQuotient() {
        func taxInEuros(price: Double, rate: Double) -> Double? {
            // TVA à 20 % d'une ligne à `price` : 5,75 → 1,15 ; 5,45 → 1,09 ; 1,10 → 0,22.
            invoice("USD", rate: rate, lines: [InvoiceLine(name: "Article", quantity: 1, unit: "H87", unitPrice: price, vatRate: 20)]).taxTotalInEuros
        }
        XCTAssertEqual(taxInEuros(price: 5.75, rate: 2), 0.58)     // 0,575 → 0,58 (8 pair)
        XCTAssertEqual(taxInEuros(price: 5.45, rate: 2), 0.54)     // 0,545 → 0,54 (4 pair)
        XCTAssertEqual(taxInEuros(price: 1.10, rate: 0.8), 0.28)   // 0,275 → 0,28
        XCTAssertEqual(taxInEuros(price: 123.45 * 3, rate: 1.1411), 64.91)
        XCTAssertEqual(taxInEuros(price: 370.35, rate: 163.25), 0.45)
        // Le piège évité : l'arrondi du quotient en Double.
        XCTAssertEqual((1.15 / 2).rounded(toPlaces: 2), 0.57)
    }

    func testNoVATInEurosWithoutAPositiveFiniteRateOrWithoutCurrency() {
        for rate in [nil, 0, -1.2, .nan, .infinity] as [Double?] {
            XCTAssertNil(invoice("USD", rate: rate).taxTotalInEuros, "\(String(describing: rate))")
        }
        XCTAssertNil(invoice("", rate: 1.2).taxTotalInEuros, "devise vide : BR-05 bloque, rien à convertir")
        XCTAssertFalse(try xml(invoice("", rate: 1.2)).contains("TaxCurrencyCode"))
    }

    // MARK: - Règle BR-FR-CO-12

    func testForeignInvoiceWithoutRateIsBlocked() throws {
        let found = rules(invoice("GBP"))
        XCTAssertEqual(found.count, 1)
        let rule = try XCTUnwrap(found.first)
        XCTAssertEqual(rule.severity, .error)
        XCTAssertTrue(rule.message.contains("Facture en GBP (BT-5)"), rule.message)
        XCTAssertTrue(rule.message.contains("indiquez le taux de change (1 EUR = … GBP)"), rule.message)
        XCTAssertTrue(rule.message.contains("« Taux BCE »"), rule.message)
    }

    func testInvalidRateIsBlockedWithItsOwnMessage() throws {
        for rate in [0, -1.2, .nan] as [Double] {
            let rule = try XCTUnwrap(rules(invoice("USD", rate: rate)).first, "\(rate)")
            XCTAssertEqual(rule.severity, .error)
            XCTAssertTrue(rule.message.contains("doit être un nombre positif"), rule.message)
        }
    }

    func testEuroInvoiceAndEmptyCurrencyNeverTriggerIt() {
        XCTAssertTrue(rules(invoice("EUR")).isEmpty)
        // Devise vide : BR-05 suffit.
        let empty = invoice("")
        XCTAssertTrue(rules(empty).isEmpty)
        XCTAssertTrue(EN16931BusinessRules.evaluate(invoice: empty).contains { $0.ruleId == "BR-05" })
    }

    /// Sur une facture reçue, la TVA en euros est celle que son émetteur a déclarée : rien à
    /// corriger chez nous.
    func testReceivedInvoiceIsNotChecked() {
        XCTAssertTrue(rules(invoice("USD"), context: .received).isEmpty)
    }

    // MARK: - Saisie du taux

    /// Le champ du taux relit la virgule comme le point décimal. Avec le format numérique standard
    /// en français, « 1.1464 », le cours tel que la BCE le publie, se lisait 1 sans aucune erreur
    /// (constaté le 2026-09-24 sur une réplique du champ, en locale fr_FR) : 1 EUR = 1 USD. Format
    /// commun aux champs décimaux de l'app (`DecimalInputFormatStyle`, voir ses tests).
    func testRateEntryReadsACommaOrADotAsTheDecimalSeparator() throws {
        let strategy = DecimalInputParseStrategy()
        XCTAssertEqual(try strategy.parse("1,1464"), 1.1464)
        XCTAssertEqual(try strategy.parse("1.1464"), 1.1464)
        XCTAssertEqual(try strategy.parse(" 163,25 "), 163.25)
        XCTAssertEqual(try strategy.parse("18 123,45"), 18123.45)
        XCTAssertEqual(try strategy.parse("18\u{202F}123,45"), 18123.45, "espace fine insécable, séparateur de milliers en français")
        XCTAssertEqual(try strategy.parse("18.123,45"), 18123.45)
        XCTAssertEqual(try strategy.parse("18,123.45"), 18123.45)
        XCTAssertEqual(try strategy.parse("1.234.567"), 1234567)
        for text in ["abc", "1,2.3,4", "nan", "inf", ""] {
            XCTAssertThrowsError(try strategy.parse(text), text)
        }
    }

    func testRateIsShownInTheAppLanguageWithoutThousandsSeparator() throws {
        let french = DecimalInputFormatStyle(locale: Locale(identifier: "fr_FR"))
        XCTAssertEqual(french.format(1.1464), "1,1464")
        XCTAssertEqual(french.format(18123.45), "18123,45")
        XCTAssertEqual(french.format(1.12345678), "1,123457")
        XCTAssertEqual(french.format(138), "138")
        XCTAssertEqual(DecimalInputFormatStyle(locale: Locale(identifier: "en_US")).format(1.1464), "1.1464")
        for rate in [1.1464, 163.25, 0.86523, 18123.45] {
            XCTAssertEqual(try french.parseStrategy.parse(french.format(rate)), rate)
        }
    }

    // MARK: - Devise et taux dans le modèle

    func testChangingTheCurrencyClearsTheRate() {
        var inv = invoice("USD", rate: 1.1411)
        inv.exchangeRateReferenceDate = day("2026-09-23")
        inv.setCurrency("USD")
        XCTAssertEqual(inv.exchangeRate, 1.1411, "même devise : rien ne change")
        XCTAssertNotNil(inv.exchangeRateReferenceDate)

        inv.setCurrency("GBP")
        XCTAssertEqual(inv.currency, "GBP")
        XCTAssertNil(inv.exchangeRate, "1 EUR = 1,1411 USD serait faux en GBP")
        XCTAssertNil(inv.exchangeRateReferenceDate)

        inv.setExchangeRate(0.8652)
        inv.setCurrency("EUR")
        XCTAssertNil(inv.exchangeRate)
    }

    func testManualRateDropsTheECBDayButAnUnchangedRateKeepsIt() {
        var inv = invoice("USD")
        inv.applyReferenceRate(ECBReferenceRate(currency: "USD", rate: 1.146, day: day("2026-09-18")))
        XCTAssertEqual(inv.exchangeRate, 1.146)
        XCTAssertEqual(inv.exchangeRateReferenceDate, day("2026-09-18"))

        inv.setExchangeRate(1.146)
        XCTAssertEqual(inv.exchangeRateReferenceDate, day("2026-09-18"), "champ validé sans modification")

        inv.setExchangeRate(1.15)
        XCTAssertEqual(inv.exchangeRate, 1.15)
        XCTAssertNil(inv.exchangeRateReferenceDate, "ce n'est plus le cours de la BCE")
    }

    func testLegacyInvoiceDecodesWithoutARateAndTheRateRoundTrips() throws {
        let legacyJSON = """
        {"id":"\(UUID().uuidString)","number":"F-1","currency":"USD",
         "seller":{"name":"S","street":"","postcode":"","city":"","country":"FR","legalSchemeID":"0002","endpointSchemeID":"0225"},
         "buyer":{"name":"B","street":"","postcode":"","city":"","country":"FR","legalSchemeID":"0002","endpointSchemeID":"0225"}}
        """
        let legacy = try JSONDecoder().decode(Invoice.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(legacy.currency, "USD")
        XCTAssertNil(legacy.exchangeRate)
        XCTAssertNil(legacy.exchangeRateReferenceDate)

        var inv = invoice("USD")
        inv.applyReferenceRate(ECBReferenceRate(currency: "USD", rate: 1.1411, day: day("2026-09-23")))
        let decoded = try JSONDecoder().decode(Invoice.self, from: JSONEncoder().encode(inv))
        XCTAssertEqual(decoded.exchangeRate, 1.1411)
        XCTAssertEqual(decoded.exchangeRateReferenceDate, day("2026-09-23"))
        XCTAssertEqual(decoded, inv)
    }

    // MARK: - Documents dérivés

    /// Même choix que le SaaS ARVERNX : l'avoir annule la TVA en euros de sa facture, au même taux ;
    /// le duplicata, l'acompte et le solde sont datés d'aujourd'hui et repartent sans taux, donc
    /// bloqués par BR-FR-CO-12 jusqu'à la saisie.
    func testCreditNoteKeepsTheRateOfItsInvoiceWhileOtherCopiesStartWithout() {
        let store = InvoiceStore()
        var source = invoice("USD")
        source.number = store.nextNumber()
        source.status = .issued
        source.applyReferenceRate(ECBReferenceRate(currency: "USD", rate: 1.1411, day: day("2026-09-23")))

        let credit = store.newCreditNote(from: source)
        XCTAssertEqual(credit.currency, "USD")
        XCTAssertEqual(credit.exchangeRate, 1.1411)
        XCTAssertEqual(credit.exchangeRateReferenceDate, day("2026-09-23"))
        XCTAssertEqual(credit.taxTotalInEuros, source.taxTotalInEuros)
        XCTAssertTrue(rules(credit).isEmpty)

        let copies = [("duplicata", store.duplicate(from: source)),
                      ("acompte", store.newDeposit(from: source)),
                      ("solde", store.newFinalSettlement(from: source, deposits: []))]
        for (label, copy) in copies {
            XCTAssertEqual(copy.currency, "USD", label)
            XCTAssertNil(copy.exchangeRate, label)
            XCTAssertNil(copy.exchangeRateReferenceDate, label)
            XCTAssertEqual(rules(copy).count, 1, label)
        }
        XCTAssertEqual(source.exchangeRate, 1.1411, "l'original garde son taux")
    }

    // MARK: - PDF

    func testForeignInvoicePDFShowsTheVATInEurosAndTheRate() throws {
        var inv = invoice("USD", rate: 1.1411)
        var text = try pdfText(inv)
        XCTAssertTrue(text.contains("Total TVA en EUR:"), text)
        XCTAssertTrue(text.contains("EUR 64.91"), text)
        XCTAssertTrue(text.contains("Taux de change : 1 EUR = 1.1411 USD"), text)
        XCTAssertFalse(text.contains("Cours de référence BCE"), "taux saisi à la main : pas de source")

        inv.applyReferenceRate(ECBReferenceRate(currency: "USD", rate: 1.146, day: day("2026-09-18")))
        text = try pdfText(inv)
        XCTAssertTrue(text.contains("Taux de change : 1 EUR = 1.146 USD"), text)
        XCTAssertTrue(text.contains("Cours de référence BCE du 18/09/2026"), text)
        XCTAssertTrue(text.contains("(table Banque de France)"), text)
    }

    func testRateIsPrintedWithoutTrailingZeros() {
        XCTAssertEqual(ExchangeRateText.string(1.146), "1.146")
        XCTAssertEqual(ExchangeRateText.string(163.25), "163.25")
        XCTAssertEqual(ExchangeRateText.string(138), "138")
        XCTAssertEqual(ExchangeRateText.string(0.86523), "0.86523")
    }

    /// Une facture en euros, ou hors euro sans taux, n'a ni la ligne ni la mention (le PDF d'une
    /// facture en euros est resté identique au pixel près, vérifié le 2026-09-24).
    func testPDFWithoutVATInEurosHasNoEuroLines() throws {
        for inv in [invoice("EUR"), invoice("EUR", rate: 1.1411), invoice("USD")] {
            let text = try pdfText(inv)
            XCTAssertFalse(text.contains("Total TVA en EUR"), text)
            XCTAssertFalse(text.contains("Taux de change"), text)
        }
    }

    /// La ligne « Total TVA en EUR » garde son libellé avant son montant, et la mention du taux
    /// reste dans la page, sous le bloc des totaux.
    func testEuroVATRowAndRateMentionStayInsideTheTotalsBlock() throws {
        var inv = invoice("USD")
        inv.prepaidAmount = 100
        inv.applyReferenceRate(ECBReferenceRate(currency: "USD", rate: 1.146, day: day("2026-09-18")))
        let doc = try XCTUnwrap(PDFDocument(data: InvoicePDFRenderer().render(invoice: inv)))
        let page = try XCTUnwrap(doc.page(at: 0))
        func box(_ text: String) throws -> CGRect {
            let found = doc.findString(text, withOptions: []).map { $0.bounds(for: page) }
            XCTAssertEqual(found.count, 1, "« \(text) »")
            return try XCTUnwrap(found.first)
        }
        let label = try box("Total TVA en EUR:")
        let amount = try box("EUR 64.63")
        XCTAssertLessThan(abs(label.midY - amount.midY), 3, "même ligne")
        XCTAssertLessThan(label.maxX, amount.minX, "le libellé chevauche son montant")
        let net = try box("Net à payer:")
        XCTAssertLessThan(label.midY, net.midY, "sous le net à payer")
        var previous = label
        for line in ["Taux de change : 1 EUR = 1.146 USD", "Cours de référence BCE du 18/09/2026", "(table Banque de France)"] {
            let b = try box(line)
            XCTAssertLessThan(b.midY, previous.midY, "« \(line) » sous la ligne précédente")
            XCTAssertEqual(b.minX, label.minX, accuracy: 1, "aligné sur les libellés des totaux")
            XCTAssertLessThanOrEqual(b.maxX, page.bounds(for: .mediaBox).width - 50, "« \(line) » sort de la marge")
            previous = b
        }
    }
}
