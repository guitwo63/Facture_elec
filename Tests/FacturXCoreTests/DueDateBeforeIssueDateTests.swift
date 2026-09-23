import XCTest
import FacturXCore

/// BR-FR-CO-07 (Schematron France CTC, fatal à la PDP) : l'échéance (BT-9) ne peut pas précéder
/// la date de facture (BT-2), sauf facture d'acompte (386) ou cadre « déjà payée » (B2/S2/M2).
/// Longtemps un simple avertissement (sous un identifiant erroné, « BR-9 »), qui laissait exporter
/// et déposer sur SUPER PDP un XML que la PDP rejetait. Les cas bloqués / autorisés ci-dessous ont été confrontés au
/// Schematron officiel (paquets Python factur-x et saxonche) sur le XML de l'app le 2026-09-23.
final class DueDateBeforeIssueDateTests: XCTestCase {

    /// Scénarios d'un utilisateur à Paris : le XML écrit le jour du fuseau de l'app.
    override func invokeTest() {
        inAppTimeZone("Europe/Paris") { super.invokeTest() }
    }

    // MARK: - Outils

    private func utc(_ s: String) -> Date {
        ISO8601DateFormatter().date(from: s)!
    }

    /// Même facture que `FacturXCoreTests.sampleInvoice()` — sans erreur de règle métier.
    private func sampleInvoice() -> Invoice {
        Invoice(
            number: "2026-0001",
            type: .commercialInvoice,
            issueDate: utc("2026-09-01T10:00:00Z"),
            dueDate: utc("2026-09-30T10:00:00Z"),
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

    /// Veille de la date de facture de `sampleInvoice()`, à la même heure.
    private var dayBefore: Date { utc("2026-08-31T10:00:00Z") }

    private func dueDateRules(_ invoice: Invoice, context: EN16931RuleContext = .issued) -> [BusinessRuleResult] {
        EN16931BusinessRules.evaluate(invoice: invoice, context: context).filter { $0.ruleId == "BR-FR-CO-07" }
    }

    /// Dates BT-2 et BT-9 telles qu'écrites dans le XML généré (format 102).
    private func xmlDates(_ invoice: Invoice) throws -> (issue: String, due: String) {
        let doc = try XMLDocument(data: CIIXMLGenerator().generate(invoice: invoice))
        func value(_ parent: String) throws -> String {
            try doc.nodes(forXPath: "//*[local-name()='\(parent)']/*[local-name()='DateTimeString']").first?.stringValue ?? ""
        }
        return (try value("IssueDateTime"), try value("DueDateDateTime"))
    }

    // MARK: - Facture normale : bloquée

    func testDueDateBeforeIssueDateBlocksCommercialInvoice() {
        var invoice = sampleInvoice()
        invoice.dueDate = dayBefore

        let rules = dueDateRules(invoice)
        XCTAssertEqual(rules.map(\.severity), [.error])
        XCTAssertTrue(rules.first?.message.contains("du 31/08/2026") == true, "cite l'échéance du XML")
        XCTAssertTrue(rules.first?.message.contains("du 01/09/2026") == true, "cite la date de facture du XML")

        let validation = FacturXValidator().validate(invoice: invoice)
        XCTAssertFalse(validation.isValid, "export et dépôt SUPER PDP doivent être bloqués")
        XCTAssertEqual(validation.businessRules.filter { $0.severity == .error }.map(\.ruleId), ["BR-FR-CO-07"])
        XCTAssertEqual(validation.totalErrorCount, 1, "une seule erreur, pas de doublon côté validateur")
        XCTAssertEqual(validation.businessRules.filter { $0.message.contains("(BT-9)") }.map(\.ruleId), ["BR-FR-CO-07"],
                       "plus d'avertissement distinct sur l'échéance")
        XCTAssertFalse(validation.warnings.contains { $0.contains("échéance") })
    }

    func testReceivedInvoiceIsCheckedToo() {
        var invoice = sampleInvoice()
        invoice.dueDate = dayBefore
        XCTAssertEqual(dueDateRules(invoice, context: .received).map(\.severity), [.error],
                       "règle de cohérence des données, pas une obligation propre à l'émetteur")
    }

    /// Le Schematron n'exempte que les codes 386/500/503 et les cadres B2/S2/M2 : ni les avoirs
    /// (381, et INT émis en 381), ni la rectificative (384), ni le solde (387 émis en 380), ni
    /// le cadre 4 (définitive après acompte).
    func testOtherTypesAndBillingModesAreNotExempt() {
        var cases: [(String, Invoice)] = []
        for type in [InvoiceTypeCode.creditNote, .internalCreditNote, .correction, .finalSettlement] {
            var invoice = sampleInvoice()
            invoice.type = type
            invoice.precedingInvoiceRef = "2026-0000"
            invoice.precedingInvoiceDate = utc("2026-08-01T10:00:00Z")
            cases.append((type.rawValue, invoice))
        }
        for mode in [BillingMode.b4, .s4, .m4, .s1, .b7] {
            var invoice = sampleInvoice()
            invoice.billingMode = mode
            cases.append((mode.rawValue, invoice))
        }
        for (label, var invoice) in cases {
            invoice.dueDate = dayBefore
            XCTAssertEqual(dueDateRules(invoice).map(\.severity), [.error], label)
            XCTAssertFalse(FacturXValidator().validate(invoice: invoice).isValid, label)
        }
    }

    // MARK: - Exceptions : autorisées, sans aucun signalement

    /// Dans un cas exempté, avancer l'échéance avant la date de facture ne change rien à ce qui
    /// est signalé : ni erreur, ni avertissement (l'ancien avertissement s'y affichait aussi).
    private func assertEarlierDueDateChangesNothing(_ label: String, file: StaticString = #filePath, line: UInt = #line,
                                                    _ configure: (inout Invoice) -> Void) {
        var later = sampleInvoice()
        configure(&later)
        var earlier = later
        earlier.dueDate = dayBefore

        XCTAssertEqual(EN16931BusinessRules.evaluate(invoice: earlier), EN16931BusinessRules.evaluate(invoice: later),
                       label, file: file, line: line)
        let validation = FacturXValidator().validate(invoice: earlier)
        XCTAssertTrue(validation.isValid, "\(label) : \(validation.businessRules.filter { $0.severity == .error }.map(\.message))",
                      file: file, line: line)
        XCTAssertEqual(validation.warnings, FacturXValidator().validate(invoice: later).warnings, label, file: file, line: line)
    }

    func testDepositInvoiceMayHaveDueDateBeforeIssueDate() {
        assertEarlierDueDateChangesNothing("386") { $0.type = .deposit }
    }

    func testAlreadyPaidBillingModesMayHaveDueDateBeforeIssueDate() {
        for mode in [BillingMode.b2, .s2, .m2] {
            assertEarlierDueDateChangesNothing(mode.rawValue) { invoice in
                invoice.billingMode = mode
                invoice.prepaidAmount = invoice.grandTotal
            }
        }
    }

    // MARK: - Comparaison au jour près, sur les dates du XML

    func testSameDayDueDateIsAllowedEvenAtAnEarlierTime() throws {
        var invoice = sampleInvoice()
        invoice.issueDate = utc("2026-09-01T15:00:00Z")
        invoice.dueDate = utc("2026-09-01T08:00:00Z")

        let dates = try xmlDates(invoice)
        XCTAssertEqual(dates.issue, dates.due, "le XML ne porte que le jour")
        XCTAssertTrue(dueDateRules(invoice).isEmpty, "le Schematron accepte une échéance égale à la date de facture")
        XCTAssertTrue(FacturXValidator().validate(invoice: invoice).isValid)
    }

    /// La règle juge les dates que la PDP recevra, pas les instants saisis : autour de minuit
    /// UTC, ou pour une échéance « fin de mois » calculée à 00:00 heure de Paris (le XML l'a
    /// longtemps écrite la veille, en UTC ; elle porte désormais le jour du fuseau de l'app).
    /// Formulé comme un invariant, vrai quel que soit le fuseau des dates du XML.
    func testRuleFollowsTheDatesWrittenInTheXML() throws {
        var paris = Calendar(identifier: .gregorian)
        paris.timeZone = TimeZone(identifier: "Europe/Paris")!
        let endOfSeptember = utc("2026-09-30T10:00:00Z")

        let pairs: [(issue: Date, due: Date)] = [
            (utc("2026-09-01T10:00:00Z"), utc("2026-08-31T10:00:00Z")),
            (utc("2026-09-01T10:00:00Z"), utc("2026-09-02T10:00:00Z")),
            (utc("2026-09-01T00:10:00Z"), utc("2026-08-31T23:50:00Z")),
            (utc("2026-09-01T23:50:00Z"), utc("2026-09-01T00:10:00Z")),
            (endOfSeptember, PaymentTermsDueRule.endOfMonthPlusDays(0).dueDate(from: endOfSeptember, calendar: paris)),
        ]
        var outcomes: Set<Bool> = []
        for (issue, due) in pairs {
            var invoice = sampleInvoice()
            invoice.issueDate = issue
            invoice.dueDate = due
            let dates = try xmlDates(invoice)
            let blocked = !dueDateRules(invoice).isEmpty
            XCTAssertEqual(blocked, dates.due < dates.issue, "XML : émission \(dates.issue), échéance \(dates.due)")
            outcomes.insert(blocked)
        }
        XCTAssertEqual(outcomes, [true, false], "l'échantillon doit contenir des cas bloqués et autorisés")
    }
}
