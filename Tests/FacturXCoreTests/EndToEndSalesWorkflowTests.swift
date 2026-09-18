import XCTest
@testable import FacturXCore

/// Scénario bout-en-bout : création d'un client, d'un devis, d'une commande, puis
/// facturation depuis la commande ET depuis le devis (les deux chemins existants),
/// avec les mêmes tiers et les mêmes lignes d'un bout à l'autre. Complète les
/// tests unitaires (numérotation, statuts, XML... déjà couverts isolément
/// ailleurs) en vérifiant qu'ils s'enchaînent correctement sur un enchaînement
/// réaliste qu'aucun test unitaire pris seul ne couvre, puis exerce les
/// fonctions transverses (génération/validation Factur-X et Order-X, audit,
/// relances, export/import) sur les documents produits par ce même scénario.
final class EndToEndSalesWorkflowTests: XCTestCase {

    private let persistedKeys = [
        "facturx.directory.v1",
        "facturx.quotes.v1",
        "orderx.orders.v1", "orderx.defaultbuyer.entryid.v1", "orderx.buyerSellerSemantics.migrated.v1",
        "orderx.number.prefix.v1", "orderx.number.includeyear.v1", "orderx.number.start.v1", "orderx.number.useseparator.v1",
        "facturx.invoices.v1", "facturx.mycompany.v1", "facturx.defaultseller.entryid.v1",
        "facturx.number.prefix.v1", "facturx.number.includeyear.v1", "facturx.number.start.v1",
        "facturx.number.useseparator.v1", "facturx.number.overrides.bysociety.v1",
        "facturx.audit.v1",
    ]

    override func setUp() {
        super.setUp()
        persistedKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    override func tearDown() {
        persistedKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        super.tearDown()
    }

    // MARK: - Construction du scénario

    private struct Pipeline {
        let directory: PartyDirectory
        let invoiceStore: InvoiceStore
        let audit: AuditStore
        let company: DirectoryEntry
        let client: DirectoryEntry
        let quote: Quote
        let order: SalesOrder
        let invoiceFromOrder: Invoice
        let invoiceFromQuote: Invoice
    }

    private func companyParty() -> InvoiceParty {
        InvoiceParty(
            name: "Mon Entreprise SARL", street: "12 rue du Commerce", postcode: "75001", city: "Paris",
            country: "FR", vatNumber: "FR12345678901", siren: "123456789",
            contactEmail: "contact@monentreprise.fr",
            endpointID: "123456789", endpointSchemeID: "0225",
            iban: "FR7630006000011234567890189", bic: "AGRIFRPP", paymentTerms: "Paiement à 30 jours"
        )
    }

    private func clientParty() -> InvoiceParty {
        InvoiceParty(
            name: "Client Exemple SAS", street: "8 avenue des Champs", postcode: "75008", city: "Paris",
            country: "FR", siren: "987654321", endpointID: "987654321", endpointSchemeID: "0225"
        )
    }

    /// Client → devis accepté → commande confirmée (reprenant les lignes du devis,
    /// sans ressaisie, comme le fait l'app) → une facture depuis la commande et une
    /// facture depuis le devis : les deux chemins de facturation existants.
    private func buildPipeline() -> Pipeline {
        let audit = AuditStore()

        let directory = PartyDirectory()
        directory.audit = audit
        directory.actorName = "e2e-test"
        let company = DirectoryEntry(kind: .societe, party: companyParty())
        let client = DirectoryEntry(kind: .client, party: clientParty(), note: "Créé par le test bout-en-bout")
        directory.upsert(company)
        directory.upsert(client)

        let quoteStore = QuoteStore()
        quoteStore.audit = audit
        quoteStore.actorName = "e2e-test"
        var quote = quoteStore.newDraft(seller: company.party, companyID: company.id)
        quote.buyer = client.party
        quote.lines = [
            InvoiceLine(name: "Prestation de conseil", quantity: 2, unit: "DAY", unitPrice: 600, vatRate: 20),
            InvoiceLine(name: "Support annuel", quantity: 1, unit: "C62", unitPrice: 300, vatRate: 10),
        ]
        quoteStore.upsert(quote)
        XCTAssertEqual(quote.status.allowedTransitions(), [.sent])
        quote.status = .sent
        quoteStore.upsert(quote)
        XCTAssertTrue(quote.status.allowedTransitions().contains(.accepted))
        quote.status = .accepted
        quoteStore.upsert(quote)

        let orderStore = OrderStore()
        orderStore.audit = audit
        orderStore.actorName = "e2e-test"
        var order = orderStore.newDraft(directory: directory, preferredSellerEntryID: company.id, companyID: company.id)
        order.buyer = client.party
        order.quotationRef = quote.number
        order.lines = quote.lines
        orderStore.upsert(order)
        for next in [OrderStatus.issued, .sentToSociete, .accepted, .confirmed] {
            XCTAssertTrue(order.status.allowedTransitions().contains(next), "\(order.status) → \(next) doit être autorisé")
            order.status = next
            orderStore.upsert(order)
        }

        let invoiceStore = InvoiceStore()
        invoiceStore.audit = audit
        invoiceStore.actorName = "e2e-test"
        let invoiceFromOrder = order.toInvoice(number: invoiceStore.nextNumber(companyID: company.id))
        invoiceStore.upsert(invoiceFromOrder)
        let invoiceFromQuote = quote.toInvoice(number: invoiceStore.nextNumber(companyID: company.id))
        invoiceStore.upsert(invoiceFromQuote)

        return Pipeline(
            directory: directory, invoiceStore: invoiceStore, audit: audit,
            company: company, client: client, quote: quote, order: order,
            invoiceFromOrder: invoiceFromOrder, invoiceFromQuote: invoiceFromQuote
        )
    }

    // MARK: - Scénario bout-en-bout

    func testPipelineCarriesSamePartiesAndTotalsFromClientToBothInvoices() {
        let p = buildPipeline()

        XCTAssertEqual(p.directory.entries.count, 2)

        XCTAssertEqual(p.quote.seller.name, p.company.party.name)
        XCTAssertEqual(p.quote.buyer.name, p.client.party.name)
        XCTAssertEqual(p.quote.status, .accepted)
        XCTAssertEqual(p.quote.grandTotal, 1770.00, accuracy: 0.001)

        // Non-régression directe du sens buyer/seller de SalesOrder (cf. la migration
        // couverte par OrderStorePartySemanticsMigrationTests) : seller doit rester
        // notre société, buyer le client — comme Devis/Facture.
        XCTAssertEqual(p.order.seller.name, p.company.party.name)
        XCTAssertEqual(p.order.buyer.name, p.client.party.name)
        XCTAssertEqual(p.order.quotationRef, p.quote.number)
        XCTAssertEqual(p.order.status, .confirmed)
        XCTAssertEqual(p.order.grandTotal, p.quote.grandTotal, accuracy: 0.001)

        XCTAssertEqual(p.invoiceFromOrder.seller.name, p.company.party.name)
        XCTAssertEqual(p.invoiceFromOrder.buyer.name, p.client.party.name)
        XCTAssertEqual(p.invoiceFromOrder.grandTotal, p.order.grandTotal, accuracy: 0.001)
        XCTAssertEqual(p.invoiceFromOrder.paymentIBAN, p.company.party.iban)
        XCTAssertEqual(p.invoiceFromOrder.lines.first?.orderReference, p.order.number,
                       "une facture issue d'une commande doit tracer son origine ligne par ligne")

        XCTAssertEqual(p.invoiceFromQuote.seller.name, p.company.party.name)
        XCTAssertEqual(p.invoiceFromQuote.buyer.name, p.client.party.name)
        XCTAssertEqual(p.invoiceFromQuote.grandTotal, p.quote.grandTotal, accuracy: 0.001)
        XCTAssertNil(p.invoiceFromQuote.lines.first?.orderReference,
                     "une facture issue directement d'un devis n'a pas de commande à référencer")

        XCTAssertNotEqual(p.invoiceFromOrder.number, p.invoiceFromQuote.number)
        XCTAssertTrue(IBANValidator.isValid(p.invoiceFromOrder.paymentIBAN))
    }

    func testStatusLifecyclesReachExpectedLockedTerminalStates() {
        let p = buildPipeline()

        XCTAssertTrue(p.quote.status.locksQuote)
        XCTAssertTrue(p.order.status.locksOrder)
        XCTAssertTrue(p.order.status.allowedTransitions().isEmpty)

        // La configuration par défaut du magasin de statuts (personnalisable en
        // Réglages > Statuts) doit refléter exactement le cycle de vie normé tant
        // que rien n'a été personnalisé — sinon réglages et code divergent en silence.
        let invoiceStatusStore = InvoiceStatusStore()
        var invoice = p.invoiceFromOrder
        for next in [InvoiceStatus.issued, .sent, .accepted, .paid] {
            XCTAssertEqual(invoiceStatusStore.allowedTransitions(from: invoice.status, isAdmin: false),
                           invoice.status.allowedTransitions())
            XCTAssertTrue(invoice.status.allowedTransitions().contains(next))
            invoice.status = next
            p.invoiceStore.upsert(invoice)
        }
        XCTAssertEqual(invoice.status, .paid)
        XCTAssertTrue(invoice.status.locksInvoice)
    }

    func testConvertedInvoicesPassFacturXGenerationAndValidation() throws {
        let p = buildPipeline()

        for invoice in [p.invoiceFromOrder, p.invoiceFromQuote] {
            let xml = try CIIXMLGenerator().generate(invoice: invoice)
            XCTAssertTrue((String(data: xml, encoding: .utf8) ?? "").contains(invoice.number))

            let modelValidation = FacturXValidator().validate(invoice: invoice)
            XCTAssertTrue(modelValidation.isValid, "Erreurs \(invoice.number) : \(modelValidation.errors)")

            let rules = EN16931BusinessRules.evaluate(invoice: invoice)
            XCTAssertTrue(rules.filter { $0.severity == .error }.isEmpty,
                          "Règles en erreur pour \(invoice.number) : \(rules.filter { $0.severity == .error }.map { $0.message })")

            let pdf = try FacturXGenerator().generate(invoice: invoice)
            XCTAssertTrue(FacturXValidator().validate(pdf: pdf).isValid)
        }
    }

    func testConfirmedOrderPassesOrderXGenerationAndValidation() throws {
        let p = buildPipeline()

        let xml = try OrderCIOXMLGenerator().generate(order: p.order)
        XCTAssertTrue((String(data: xml, encoding: .utf8) ?? "").contains(p.order.number))

        let modelValidation = OrderXValidator().validate(order: p.order)
        XCTAssertTrue(modelValidation.isValid, "Erreurs \(p.order.number) : \(modelValidation.errors)")

        let pdf = try OrderXGenerator().generate(order: p.order)
        XCTAssertTrue(OrderXValidator().validate(pdf: pdf).isValid)
    }

    func testAuditTrailRecordsEveryDocumentAndStatusChange() {
        let p = buildPipeline()
        let entries = p.audit.entries

        XCTAssertTrue(entries.contains { $0.action == "directory_entry_created" && $0.objectCode == p.company.displayName })
        XCTAssertTrue(entries.contains { $0.action == "directory_entry_created" && $0.objectCode == p.client.displayName })
        XCTAssertTrue(entries.contains { $0.action == "quote_created" && $0.objectCode == p.quote.number })
        XCTAssertTrue(entries.contains { $0.objectType == .quote && $0.statusTo == QuoteStatus.accepted.label })
        XCTAssertTrue(entries.contains { $0.action == "order_created" && $0.objectCode == p.order.number })
        XCTAssertTrue(entries.contains { $0.objectType == .order && $0.statusTo == OrderStatus.confirmed.label })
        XCTAssertTrue(entries.contains { $0.action == "invoice_created" && $0.objectCode == p.invoiceFromOrder.number })
        XCTAssertTrue(entries.contains { $0.action == "invoice_created" && $0.objectCode == p.invoiceFromQuote.number })
    }

    func testOverdueInvoiceGeneratesGraduatedPaymentReminders() {
        let p = buildPipeline()
        var invoice = p.invoiceFromQuote
        invoice.status = .issued
        invoice.dueDate = Date().addingTimeInterval(-15 * 86400)

        XCTAssertTrue(invoice.isOverdue)
        XCTAssertGreaterThan(invoice.overdueDays, 0)

        for level in PaymentReminderLevel.allCases {
            let email = PaymentReminderComposer.compose(level: level, for: invoice)
            XCTAssertTrue(email.subject.contains(invoice.number))
            XCTAssertTrue(email.body.contains(p.client.party.name))
        }
        let legalEmail = PaymentReminderComposer.compose(level: .legalPenalty, for: invoice)
        XCTAssertTrue(legalEmail.body.contains(invoice.legalNotePMD))
        XCTAssertTrue(legalEmail.body.contains(invoice.legalNotePMT))
    }

    func testDataPortabilityRoundTripPreservesEveryDocumentProducedByThePipeline() throws {
        let p = buildPipeline()

        XCTAssertEqual(try roundTrip([p.company, p.client]), [p.company, p.client])

        let quote = snappedToWholeSeconds(p.quote)
        XCTAssertEqual(try roundTrip([quote]), [quote])

        let order = snappedToWholeSeconds(p.order)
        XCTAssertEqual(try roundTrip([order]), [order])

        for invoice in [p.invoiceFromOrder, p.invoiceFromQuote] {
            let snapped = snappedToWholeSeconds(invoice)
            XCTAssertEqual(try roundTrip([snapped]), [snapped])
        }
    }

    // MARK: - Aides

    private func roundTrip<T: Codable>(_ items: [T]) throws -> [T] {
        try DataPortability.importJSON(T.self, from: DataPortability.exportJSON(items))
    }

    /// `DataPortability` encode les dates en ISO 8601 (précision à la seconde) :
    /// sans cet arrondi, comparer un document fraîchement créé (`Date()`, précision
    /// sous-seconde) à sa version réimportée échouerait à cause de cette troncature
    /// attendue, pas d'un vrai bug de sérialisation.
    private func snappedToWholeSeconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }

    private func snappedToWholeSeconds(_ quote: Quote) -> Quote {
        var q = quote
        q.issueDate = snappedToWholeSeconds(q.issueDate)
        q.validUntil = snappedToWholeSeconds(q.validUntil)
        return q
    }

    private func snappedToWholeSeconds(_ order: SalesOrder) -> SalesOrder {
        var o = order
        o.issueDate = snappedToWholeSeconds(o.issueDate)
        o.requestedDeliveryDate = snappedToWholeSeconds(o.requestedDeliveryDate)
        return o
    }

    private func snappedToWholeSeconds(_ invoice: Invoice) -> Invoice {
        var i = invoice
        i.issueDate = snappedToWholeSeconds(i.issueDate)
        i.createdAt = snappedToWholeSeconds(i.createdAt)
        i.dueDate = snappedToWholeSeconds(i.dueDate)
        return i
    }
}
