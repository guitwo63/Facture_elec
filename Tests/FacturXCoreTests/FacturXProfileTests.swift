import XCTest
import FacturXCore

/// Profil Factur-X (BT-24). `CIIXMLGenerator` produit toujours la structure du profil
/// EN 16931 : conforme en EN 16931 et EXTENDED, rejetée par le XSD de MINIMUM, BASIC WL et
/// BASIC (mesure du 2026-09-23 contre le XSD et le Schematron officiels de chaque profil,
/// détaillée dans docs/mapping-factur-x.md). Seuls EN 16931 et EXTENDED sont donc proposés
/// à l'émission ; les autres profils restent décodables (factures existantes et reçues).
final class FacturXProfileTests: XCTestCase {

    private let keys = [
        "facturx.invoices.v1",
        "facturx.number.prefix.v1",
        "facturx.number.includeyear.v1",
        "facturx.number.start.v1",
        "facturx.number.useseparator.v1",
        "facturx.number.overrides.bysociety.v1"
    ]

    override func setUp() {
        super.setUp()
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    override func tearDown() {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        super.tearDown()
    }

    private func makeDate(_ s: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.date(from: s)!
    }

    /// Même facture que `FacturXCoreTests.sampleInvoice()` (valide contre les validateurs
    /// officiels en EN 16931), dans le profil demandé.
    private func sampleInvoice(profile: FacturXProfile) -> Invoice {
        Invoice(
            number: "2026-0001",
            type: .commercialInvoice,
            issueDate: makeDate("2026-09-01"),
            dueDate: makeDate("2026-09-30"),
            profile: profile,
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

    // MARK: - Profils proposés à la saisie

    func testOnlyEN16931AndExtendedAreOfferedForIssuing() {
        XCTAssertEqual(FacturXProfile.selectableCases(), [.en16931, .extended])
        XCTAssertEqual(FacturXProfile.allCases.filter(\.isIssuable), [.en16931, .extended])
    }

    /// Même principe que les cadres de facturation 8 et 9 : une société ou une facture
    /// encore dans un ancien profil l'affiche toujours dans son sélecteur.
    func testLegacyProfileStaysSelectableWhenAlreadyChosen() {
        for legacy in [FacturXProfile.minimum, .basicWL, .basic] {
            XCTAssertEqual(FacturXProfile.selectableCases(current: legacy), [legacy, .en16931, .extended], legacy.rawValue)
        }
        XCTAssertEqual(FacturXProfile.selectableCases(current: .extended), [.en16931, .extended])
    }

    // MARK: - Décodage des données existantes

    func testEveryProfileStillDecodesOnInvoicesAndCompanies() throws {
        XCTAssertEqual(FacturXProfile.allCases.map(\.rawValue), ["MINIMUM", "BASIC WL", "BASIC", "EN 16931", "EXTENDED"],
                       "valeurs enregistrées dans les données existantes : ne jamais les changer")
        for profile in FacturXProfile.allCases {
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(sampleInvoice(profile: .en16931))) as? [String: Any])
            json["profile"] = profile.rawValue
            let invoice = try JSONDecoder().decode(Invoice.self, from: JSONSerialization.data(withJSONObject: json))
            XCTAssertEqual(invoice.profile, profile)

            let company = DirectoryEntry(kinds: [.societe], party: invoice.seller, profile: profile)
            let decodedCompany = try JSONDecoder().decode(DirectoryEntry.self, from: JSONEncoder().encode(company))
            XCTAssertEqual(decodedCompany.profile, profile)
        }
    }

    /// Le profil d'une facture reçue est lu dans son XML, quel qu'il soit.
    func testParserKeepsTheDeclaredProfileOfAReceivedInvoice() throws {
        for profile in FacturXProfile.allCases {
            let xml = try CIIXMLGenerator().generate(invoice: sampleInvoice(profile: profile))
            XCTAssertEqual(try CIIXMLParser().parse(xml: xml).profile, profile)
        }
    }

    // MARK: - Export (BR-PROFIL)

    func testLegacyProfileBlocksTheExportOfAnIssuedInvoice() {
        for profile in FacturXProfile.allCases {
            let invoice = sampleInvoice(profile: profile)
            let rule = EN16931BusinessRules.evaluate(invoice: invoice).first { $0.ruleId == "BR-PROFIL" }
            let result = FacturXValidator().validate(invoice: invoice)
            if profile.isIssuable {
                XCTAssertNil(rule, profile.rawValue)
                XCTAssertTrue(result.isValid, "\(profile.rawValue) : \(result.errors) \(result.businessRules.map(\.message))")
            } else {
                XCTAssertEqual(rule?.severity, .error, profile.rawValue)
                XCTAssertTrue(rule?.message.contains("profil \(profile.rawValue)") ?? false, rule?.message ?? "")
                XCTAssertTrue(rule?.message.contains("Repassez la facture en EN 16931") ?? false, "la correction doit être indiquée")
                XCTAssertFalse(result.isValid, profile.rawValue)
                XCTAssertFalse(result.warnings.contains { $0.contains(profile.rawValue) }, "pas d'avertissement en double de BR-PROFIL")
            }
        }
    }

    /// Le profil d'un document reçu a été choisi par son émetteur, qui a produit le XML.
    func testReceivedInvoiceIsNotBlockedByItsProfile() {
        for profile in FacturXProfile.allCases {
            let results = EN16931BusinessRules.evaluate(invoice: sampleInvoice(profile: profile), context: .received)
            XCTAssertFalse(results.contains { $0.ruleId == "BR-PROFIL" }, profile.rawValue)
        }
    }

    // MARK: - Nouvelles factures

    func testNewDraftNeverInheritsALegacyCompanyProfile() {
        let store = InvoiceStore()
        let directory = PartyDirectory()
        let expectations: [(FacturXProfile, FacturXProfile)] = [
            (.minimum, .en16931), (.basicWL, .en16931), (.basic, .en16931), (.en16931, .en16931), (.extended, .extended),
        ]
        for (companyProfile, expected) in expectations {
            let company = DirectoryEntry(kinds: [.societe], party: sampleInvoice(profile: .en16931).seller, profile: companyProfile)
            directory.entries = [company]
            let draft = store.newDraft(directory: directory, preferredSellerEntryID: company.id)
            XCTAssertEqual(draft.profile, expected, "société en \(companyProfile.rawValue)")
        }
    }

    func testInvoicesCreatedFromALegacyInvoiceUseEN16931() {
        let store = InvoiceStore()
        let expectations: [(FacturXProfile, FacturXProfile)] = [
            (.minimum, .en16931), (.basicWL, .en16931), (.basic, .en16931), (.en16931, .en16931), (.extended, .extended),
        ]
        for (origin, expected) in expectations {
            let invoice = sampleInvoice(profile: origin)
            XCTAssertEqual(store.duplicate(from: invoice).profile, expected, "doublon d'une facture \(origin.rawValue)")
            XCTAssertEqual(store.newCreditNote(from: invoice).profile, expected, "avoir d'une facture \(origin.rawValue)")
            XCTAssertEqual(store.newDeposit(from: invoice).profile, expected, "acompte d'une facture \(origin.rawValue)")
            XCTAssertEqual(store.newFinalSettlement(from: invoice, deposits: []).profile, expected, "solde d'une facture \(origin.rawValue)")
        }
    }

    // MARK: - XML des profils proposés

    func testIssuableProfilesDeclareTheirURN() throws {
        let en16931 = String(decoding: try CIIXMLGenerator().generate(invoice: sampleInvoice(profile: .en16931)), as: UTF8.self)
        XCTAssertTrue(en16931.contains("<ram:ID>urn:cen.eu:en16931:2017</ram:ID>"))
        let extended = String(decoding: try CIIXMLGenerator().generate(invoice: sampleInvoice(profile: .extended)), as: UTF8.self)
        XCTAssertTrue(extended.contains("<ram:ID>urn:cen.eu:en16931:2017#conformant#urn:factur-x.eu:1p0:extended</ram:ID>"))
    }
}
