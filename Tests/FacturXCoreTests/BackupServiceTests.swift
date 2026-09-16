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

    private func sampleInvoice() -> Invoice {
        Invoice(
            number: "FAC-BAK-1",
            seller: InvoiceParty(name: "Vendeur", street: "1 rue A", postcode: "75001", city: "Paris"),
            buyer: InvoiceParty(name: "Client", street: "2 rue B", postcode: "75002", city: "Paris"),
            lines: [InvoiceLine(name: "Prestation", quantity: 1, unitPrice: 100, vatRate: 20)]
        )
    }

    func testCaptureReadsCurrentDataFromAllStores() {
        let invoiceStore = InvoiceStore()
        invoiceStore.invoices = [sampleInvoice()]
        let orderStore = OrderStore()
        orderStore.orders = []
        let directory = PartyDirectory()
        directory.entries = []

        let bundle = BackupService.capture(invoiceStore: invoiceStore, orderStore: orderStore, directory: directory)

        XCTAssertEqual(bundle.invoices.count, 1)
        XCTAssertEqual(bundle.invoices.first?.number, "FAC-BAK-1")
        XCTAssertFalse(bundle.appVersion.isEmpty)
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

        BackupService.restore(bundle, invoiceStore: invoiceStore, orderStore: orderStore, directory: directory)

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

        BackupService.restore(bundle, invoiceStore: invoiceStore, orderStore: orderStore, directory: directory)
        BackupService.restore(bundle, invoiceStore: invoiceStore, orderStore: orderStore, directory: directory)

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
}
