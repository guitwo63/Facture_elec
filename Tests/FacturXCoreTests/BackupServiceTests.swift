import XCTest
@testable import FacturXCore

final class PCloudCredentialsTests: XCTestCase {
    func testIsConfiguredRequiresUsernameAndPassword() {
        var creds = PCloudCredentials()
        XCTAssertFalse(creds.isConfigured)
        creds.username = "alice@exemple.fr"
        XCTAssertFalse(creds.isConfigured, "mot de passe manquant")
        creds.password = "secret"
        XCTAssertTrue(creds.isConfigured)
    }

    func testRegionMapsToCorrectAPIHost() {
        XCTAssertEqual(PCloudRegion.us.apiHost, "api.pcloud.com")
        XCTAssertEqual(PCloudRegion.eu.apiHost, "eapi.pcloud.com")
    }

    func testDefaultRegionIsEU() {
        XCTAssertEqual(PCloudCredentials().region, .eu)
    }

    func testDecodingToleratesMissingFieldsFromOlderPersistedData() throws {
        let legacyJSON = """
        {"username":"alice@exemple.fr","password":"secret"}
        """
        let decoded = try JSONDecoder().decode(PCloudCredentials.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(decoded.region, .eu)
        XCTAssertEqual(decoded.backupFolderPath, "/Facture_elec Sauvegardes")
    }
}

final class PCloudServiceTests: XCTestCase {
    func testLoginRejectsUnconfiguredCredentialsWithoutNetworkCall() async {
        do {
            _ = try await PCloudService().login(credentials: PCloudCredentials())
            XCTFail("devrait lever notConfigured")
        } catch let error as PCloudError {
            guard case .notConfigured = error else {
                return XCTFail("erreur inattendue : \(error)")
            }
        } catch {
            XCTFail("erreur inattendue : \(error)")
        }
    }

    func testUploadRejectsUnconfiguredCredentialsWithoutNetworkCall() async {
        do {
            _ = try await PCloudService().upload(data: Data(), filename: "x.json", credentials: PCloudCredentials(), auth: "token")
            XCTFail("devrait lever notConfigured")
        } catch let error as PCloudError {
            guard case .notConfigured = error else {
                return XCTFail("erreur inattendue : \(error)")
            }
        } catch {
            XCTFail("erreur inattendue : \(error)")
        }
    }
}

final class BackupServiceTests: XCTestCase {

    /// Les tests d'achat de cet incrément (3.1) passent par `BackupService.restore`, qui
    /// appelle `PurchaseInvoiceStore.upsert` — lequel persiste sur le vrai `UserDefaults`
    /// (comme les autres stores de ce fichier). Nettoyage explicite pour ne pas laisser de
    /// facture d'achat résiduelle polluer `PurchaseInvoiceStoreTests`, qui s'exécute dans le
    /// même processus de test.
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "facturx.purchaseinvoices.v1")
        super.tearDown()
    }

    private func sampleInvoice() -> Invoice {
        Invoice(
            number: "FAC-BAK-1",
            seller: InvoiceParty(name: "Vendeur", street: "1 rue A", postcode: "75001", city: "Paris"),
            buyer: InvoiceParty(name: "Client", street: "2 rue B", postcode: "75002", city: "Paris"),
            lines: [InvoiceLine(name: "Prestation", quantity: 1, unitPrice: 100, vatRate: 20)]
        )
    }

    private func sampleQuote() -> Quote {
        Quote(
            number: "DEV-BAK-1",
            seller: InvoiceParty(name: "Vendeur", street: "1 rue A", postcode: "75001", city: "Paris"),
            buyer: InvoiceParty(name: "Client", street: "2 rue B", postcode: "75002", city: "Paris")
        )
    }

    private func samplePurchaseInvoice(companyID: UUID? = nil) -> PurchaseInvoice {
        let invoice = Invoice(
            number: "ACH-BAK-1",
            seller: InvoiceParty(name: "Fournisseur", street: "1 rue A", postcode: "75001", city: "Paris"),
            buyer: InvoiceParty(name: "Mon Entreprise", street: "2 rue B", postcode: "75002", city: "Paris"),
            companyID: companyID,
            lines: [InvoiceLine(name: "Prestation", quantity: 1, unitPrice: 100, vatRate: 20)]
        )
        return PurchaseInvoice(invoice: invoice, status: .draft)
    }

    func testCaptureReadsCurrentDataFromAllStores() {
        let invoiceStore = InvoiceStore()
        invoiceStore.invoices = [sampleInvoice()]
        let orderStore = OrderStore()
        orderStore.orders = []
        let directory = PartyDirectory()
        directory.entries = []
        let quoteStore = QuoteStore()
        quoteStore.quotes = []

        let bundle = BackupService.capture(invoiceStore: invoiceStore, orderStore: orderStore, quoteStore: quoteStore, directory: directory, purchaseInvoiceStore: PurchaseInvoiceStore())

        XCTAssertEqual(bundle.invoices.count, 1)
        XCTAssertEqual(bundle.invoices.first?.number, "FAC-BAK-1")
        XCTAssertFalse(bundle.appVersion.isEmpty)
    }

    func testCaptureIncludesQuotes() {
        let quoteStore = QuoteStore()
        quoteStore.quotes = [sampleQuote()]

        let bundle = BackupService.capture(
            invoiceStore: InvoiceStore(), orderStore: OrderStore(),
            quoteStore: quoteStore, directory: PartyDirectory(), purchaseInvoiceStore: PurchaseInvoiceStore()
        )

        XCTAssertEqual(bundle.quotes.count, 1, "les devis doivent faire partie de la sauvegarde, au même titre que factures/commandes/tiers")
        XCTAssertEqual(bundle.quotes.first?.number, "DEV-BAK-1")
    }

    // MARK: - Incrément 3.1 (Réglages par société) : filtre société + module Achats

    func testCaptureIncludesPurchaseInvoices() {
        let purchaseStore = PurchaseInvoiceStore()
        purchaseStore.invoices = [samplePurchaseInvoice()]

        let bundle = BackupService.capture(
            invoiceStore: InvoiceStore(), orderStore: OrderStore(), quoteStore: QuoteStore(),
            directory: PartyDirectory(), purchaseInvoiceStore: purchaseStore
        )

        XCTAssertEqual(bundle.purchaseInvoices.count, 1, "les factures d'achat doivent faire partie de la sauvegarde, au même titre que les autres modules")
        XCTAssertEqual(bundle.purchaseInvoices.first?.invoice.number, "ACH-BAK-1")
    }

    func testRestoreUpsertsPurchaseInvoicesAdditively() {
        let bundle = BackupBundle(invoices: [], orders: [], parties: [], purchaseInvoices: [samplePurchaseInvoice()])
        let purchaseStore = PurchaseInvoiceStore()
        purchaseStore.invoices = []

        BackupService.restore(
            bundle, invoiceStore: InvoiceStore(), orderStore: OrderStore(), quoteStore: QuoteStore(),
            directory: PartyDirectory(), purchaseInvoiceStore: purchaseStore
        )

        XCTAssertEqual(purchaseStore.invoices.count, 1)
        XCTAssertEqual(purchaseStore.invoices.first?.invoice.number, "ACH-BAK-1")
    }

    func testCaptureWithoutCompanyIDIsUnfilteredIdenticalToPreviousBehavior() {
        let cidA = UUID(); let cidB = UUID()
        let invoiceStore = InvoiceStore()
        invoiceStore.invoices = [sampleInvoice(), sampleInvoice()]
        invoiceStore.invoices[0].companyID = cidA
        invoiceStore.invoices[1].companyID = cidB
        let purchaseStore = PurchaseInvoiceStore()
        purchaseStore.invoices = [samplePurchaseInvoice(companyID: cidA), samplePurchaseInvoice(companyID: cidB)]

        let bundle = BackupService.capture(
            invoiceStore: invoiceStore, orderStore: OrderStore(), quoteStore: QuoteStore(),
            directory: PartyDirectory(), purchaseInvoiceStore: purchaseStore
        )

        XCTAssertEqual(bundle.invoices.count, 2, "sans companyID, capture reste non filtrée — comportement identique à avant l'incrément 3.1")
        XCTAssertEqual(bundle.purchaseInvoices.count, 2)
    }

    func testCaptureWithCompanyIDFiltersAllFourModules() {
        let cidA = UUID(); let cidB = UUID()
        let invoiceStore = InvoiceStore()
        invoiceStore.invoices = [sampleInvoice(), sampleInvoice()]
        invoiceStore.invoices[0].companyID = cidA
        invoiceStore.invoices[1].companyID = cidB
        let quoteStore = QuoteStore()
        quoteStore.quotes = [sampleQuote(), sampleQuote()]
        quoteStore.quotes[0].companyID = cidA
        quoteStore.quotes[1].companyID = cidB
        let purchaseStore = PurchaseInvoiceStore()
        purchaseStore.invoices = [samplePurchaseInvoice(companyID: cidA), samplePurchaseInvoice(companyID: cidB)]
        let directory = PartyDirectory()
        let partyA = DirectoryEntry(kinds: [.client], party: InvoiceParty(name: "Client A", street: "", postcode: "", city: ""), companyID: cidA)
        let partyB = DirectoryEntry(kinds: [.client], party: InvoiceParty(name: "Client B", street: "", postcode: "", city: ""), companyID: cidB)
        directory.entries = [partyA, partyB]

        let bundle = BackupService.capture(
            invoiceStore: invoiceStore, orderStore: OrderStore(), quoteStore: quoteStore,
            directory: directory, purchaseInvoiceStore: purchaseStore, companyID: cidA
        )

        XCTAssertEqual(bundle.invoices.count, 1)
        XCTAssertEqual(bundle.quotes.count, 1)
        XCTAssertEqual(bundle.purchaseInvoices.count, 1)
        XCTAssertEqual(bundle.parties.count, 1)
        XCTAssertEqual(bundle.parties.first?.displayName, "Client A")
    }

    func testRestoreUpsertsQuotesAdditively() {
        let bundle = BackupBundle(invoices: [], orders: [], quotes: [sampleQuote()], parties: [])
        let quoteStore = QuoteStore()
        // Une exécution précédente de la suite peut avoir persisté des devis
        // de test sur le vrai UserDefaults (QuoteStore.init charge depuis le
        // disque) : on repart d'un état propre pour ce test.
        quoteStore.quotes = []

        BackupService.restore(
            bundle, invoiceStore: InvoiceStore(), orderStore: OrderStore(),
            quoteStore: quoteStore, directory: PartyDirectory(), purchaseInvoiceStore: PurchaseInvoiceStore()
        )

        XCTAssertEqual(quoteStore.quotes.count, 1)
        XCTAssertEqual(quoteStore.quotes.first?.number, "DEV-BAK-1")
    }

    func testRestoreUpsertsIntoTargetStoresAdditively() {
        let bundle = BackupBundle(invoices: [sampleInvoice()], orders: [], parties: [])
        let invoiceStore = InvoiceStore()
        let existing = Invoice(
            number: "FAC-EXISTING",
            seller: InvoiceParty(name: "S", street: "", postcode: "", city: ""),
            buyer: InvoiceParty(name: "B", street: "", postcode: "", city: "")
        )
        invoiceStore.invoices = [existing]
        let orderStore = OrderStore()
        let directory = PartyDirectory()
        let quoteStore = QuoteStore()

        BackupService.restore(bundle, invoiceStore: invoiceStore, orderStore: orderStore, quoteStore: quoteStore, directory: directory, purchaseInvoiceStore: PurchaseInvoiceStore())

        XCTAssertEqual(invoiceStore.invoices.count, 2, "la restauration doit ajouter, pas remplacer, les données existantes")
        XCTAssertTrue(invoiceStore.invoices.contains { $0.number == "FAC-EXISTING" })
        XCTAssertTrue(invoiceStore.invoices.contains { $0.number == "FAC-BAK-1" })
    }

    func testRestoreIsIdempotentForTheSameInvoiceID() {
        let invoice = sampleInvoice()
        let bundle = BackupBundle(invoices: [invoice], orders: [], parties: [])
        let invoiceStore = InvoiceStore()
        let orderStore = OrderStore()
        let directory = PartyDirectory()
        let quoteStore = QuoteStore()

        BackupService.restore(bundle, invoiceStore: invoiceStore, orderStore: orderStore, quoteStore: quoteStore, directory: directory, purchaseInvoiceStore: PurchaseInvoiceStore())
        BackupService.restore(bundle, invoiceStore: invoiceStore, orderStore: orderStore, quoteStore: quoteStore, directory: directory, purchaseInvoiceStore: PurchaseInvoiceStore())

        XCTAssertEqual(invoiceStore.invoices.filter { $0.id == invoice.id }.count, 1, "un même id importé deux fois ne doit pas se dupliquer")
    }

    func testBackupBundleRoundTripsThroughJSON() throws {
        let bundle = BackupBundle(invoices: [sampleInvoice()], orders: [], parties: [])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(bundle)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BackupBundle.self, from: data)
        XCTAssertEqual(decoded.invoices.first?.number, "FAC-BAK-1")
    }

    func testSuggestedFilenameIsTimestampedAndSafe() {
        let name = BackupBundle.suggestedFilename(date: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertTrue(name.hasSuffix(".json"))
        XCTAssertFalse(name.contains(" "))
        XCTAssertTrue(name.hasPrefix("facture_elec_sauvegarde_"))
    }

    /// Avant l'inversion buyer/seller de `SalesOrder`, `buyer` désignait notre
    /// société. Un bundle capturé par une version antérieure (donc sans
    /// `orderPartySemanticsVersion`, ou explicitement à 1) doit voir ses
    /// commandes permutées à la restauration, pour rejoindre le sens actuel.
    private func legacyOrder() -> SalesOrder {
        SalesOrder(
            number: "CD-BAK-LEGACY",
            buyer: InvoiceParty(name: "Mon Entreprise SARL", street: "", postcode: "", city: ""),
            seller: InvoiceParty(name: "Client Historique SAS", street: "", postcode: "", city: "")
        )
    }

    func testRestoreSwapsBuyerSellerForLegacyBackupVersion() {
        let bundle = BackupBundle(invoices: [], orders: [legacyOrder()], parties: [], orderPartySemanticsVersion: 1)
        let orderStore = OrderStore()
        orderStore.orders = []

        BackupService.restore(bundle, invoiceStore: InvoiceStore(), orderStore: orderStore, quoteStore: QuoteStore(), directory: PartyDirectory(), purchaseInvoiceStore: PurchaseInvoiceStore())

        let restored = orderStore.orders.first(where: { $0.number == "CD-BAK-LEGACY" })
        XCTAssertEqual(restored?.seller.name, "Mon Entreprise SARL", "un bundle d'avant l'inversion doit être permuté pour que notre société soit seller")
        XCTAssertEqual(restored?.buyer.name, "Client Historique SAS")
    }

    func testRestoreDoesNotSwapForCurrentBackupVersion() {
        let alreadyCorrect = SalesOrder(
            number: "CD-BAK-CURRENT",
            buyer: InvoiceParty(name: "Client Actuel SAS", street: "", postcode: "", city: ""),
            seller: InvoiceParty(name: "Mon Entreprise SARL", street: "", postcode: "", city: "")
        )
        let bundle = BackupBundle(invoices: [], orders: [alreadyCorrect], parties: [])
        let orderStore = OrderStore()
        orderStore.orders = []

        BackupService.restore(bundle, invoiceStore: InvoiceStore(), orderStore: orderStore, quoteStore: QuoteStore(), directory: PartyDirectory(), purchaseInvoiceStore: PurchaseInvoiceStore())

        let restored = orderStore.orders.first(where: { $0.number == "CD-BAK-CURRENT" })
        XCTAssertEqual(restored?.seller.name, "Mon Entreprise SARL", "un bundle déjà au sens actuel ne doit pas être re-permuté")
        XCTAssertEqual(restored?.buyer.name, "Client Actuel SAS")
    }

    func testBackupBundleDecodingDefaultsToLegacySemanticsVersionWhenFieldAbsent() throws {
        let legacyJSON = """
        {"createdAt":"2026-01-01T00:00:00Z","appVersion":"1.0","invoices":[],"orders":[],"parties":[]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BackupBundle.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(decoded.orderPartySemanticsVersion, 1, "un fichier antérieur à ce champ doit être traité comme l'ancien sens buyer/seller")
    }
}
