import XCTest
@testable import FacturXCore

final class DataPortabilityTests: XCTestCase {

    private func sampleInvoice() -> Invoice {
        Invoice(
            number: "FAC-PORT-1",
            dueDate: Date(timeIntervalSince1970: 1_800_000_000),
            seller: InvoiceParty(name: "Vendeur", street: "1 rue A", postcode: "75001", city: "Paris"),
            buyer: InvoiceParty(name: "Client", street: "2 rue B", postcode: "75002", city: "Paris"),
            lines: [InvoiceLine(name: "Prestation", quantity: 2, unitPrice: 100, vatRate: 20)]
        )
    }

    func testExportImportRoundTripPreservesInvoiceData() throws {
        let original = [sampleInvoice()]
        let data = try DataPortability.exportJSON(original)
        let decoded = try DataPortability.importJSON(Invoice.self, from: data)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].number, "FAC-PORT-1")
        XCTAssertEqual(decoded[0].lines.count, 1)
        XCTAssertEqual(decoded[0].grandTotal, original[0].grandTotal, accuracy: 0.001)
        XCTAssertEqual(decoded[0].dueDate.timeIntervalSince1970, original[0].dueDate.timeIntervalSince1970, accuracy: 1)
    }

    func testExportProducesHumanReadableJSON() throws {
        let data = try DataPortability.exportJSON([sampleInvoice()])
        let text = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("FAC-PORT-1"))
        XCTAssertTrue(text.contains("\n"), "sortie prétty-printed attendue, pas une seule ligne")
    }

    func testImportThrowsDecodingErrorOnMalformedData() {
        let garbage = Data("{ceci n'est pas du JSON valide".utf8)
        XCTAssertThrowsError(try DataPortability.importJSON(Invoice.self, from: garbage)) { error in
            guard case DataPortabilityError.decodingFailed = error else {
                return XCTFail("attendu decodingFailed, obtenu \(error)")
            }
        }
    }

    func testImportThrowsWhenJSONShapeDoesNotMatchExpectedType() throws {
        let wrongShape = try DataPortability.exportJSON(["juste une liste de chaînes"])
        XCTAssertThrowsError(try DataPortability.importJSON(Invoice.self, from: wrongShape))
    }
}

final class AppConfigurationBundleTests: XCTestCase {

    func testCaptureReadsCurrentSettingsFromAllStores() {
        let invoiceStore = InvoiceStore()
        invoiceStore.numberPrefix = "FAC"
        invoiceStore.numberStart = 42
        let orderStore = OrderStore()
        orderStore.numberPrefix = "CDE"
        let invoiceStatusStore = InvoiceStatusStore()
        let orderStatusStore = OrderStatusStore()
        let tagStore = TagStore()
        tagStore.tags = [PartyTag(name: "VIP", hexColor: "FF0000")]
        let kindColorStore = KindColorStore()
        kindColorStore.colors[.client] = "00FF00"

        let bundle = AppConfigurationBundle.capture(
            invoiceStore: invoiceStore, orderStore: orderStore,
            invoiceStatusStore: invoiceStatusStore, orderStatusStore: orderStatusStore,
            tagStore: tagStore, kindColorStore: kindColorStore
        )

        XCTAssertEqual(bundle.invoiceNumberPrefix, "FAC")
        XCTAssertEqual(bundle.invoiceNumberStart, 42)
        XCTAssertEqual(bundle.orderNumberPrefix, "CDE")
        XCTAssertEqual(bundle.tags.first?.name, "VIP")
        XCTAssertEqual(bundle.kindColors["client"], "00FF00")
    }

    func testApplyWritesBundleValuesBackToStores() {
        let bundle = AppConfigurationBundle(
            invoiceNumberPrefix: "IMPORTED-FAC",
            invoiceNumberStart: 7,
            orderNumberPrefix: "IMPORTED-CDE",
            tags: [PartyTag(name: "Prioritaire", hexColor: "0000FF")],
            kindColors: ["client": "ABCDEF"]
        )
        let invoiceStore = InvoiceStore()
        let orderStore = OrderStore()
        let invoiceStatusStore = InvoiceStatusStore()
        let orderStatusStore = OrderStatusStore()
        let tagStore = TagStore()
        let kindColorStore = KindColorStore()

        bundle.apply(
            invoiceStore: invoiceStore, orderStore: orderStore,
            invoiceStatusStore: invoiceStatusStore, orderStatusStore: orderStatusStore,
            tagStore: tagStore, kindColorStore: kindColorStore
        )

        XCTAssertEqual(invoiceStore.numberPrefix, "IMPORTED-FAC")
        XCTAssertEqual(invoiceStore.numberStart, 7)
        XCTAssertEqual(orderStore.numberPrefix, "IMPORTED-CDE")
        XCTAssertEqual(tagStore.tags.first?.name, "Prioritaire")
        XCTAssertEqual(kindColorStore.colors[.client], "ABCDEF")
    }

    func testCaptureThenApplyRoundTripsThroughJSON() throws {
        let sourceInvoiceStore = InvoiceStore()
        sourceInvoiceStore.numberPrefix = "ROUNDTRIP"
        let sourceBundle = AppConfigurationBundle.capture(
            invoiceStore: sourceInvoiceStore, orderStore: OrderStore(),
            invoiceStatusStore: InvoiceStatusStore(), orderStatusStore: OrderStatusStore(),
            tagStore: TagStore(), kindColorStore: KindColorStore()
        )
        let data = try DataPortability.exportJSON([sourceBundle])
        let decoded = try DataPortability.importJSON(AppConfigurationBundle.self, from: data)
        XCTAssertEqual(decoded.first?.invoiceNumberPrefix, "ROUNDTRIP")

        let targetInvoiceStore = InvoiceStore()
        decoded[0].apply(
            invoiceStore: targetInvoiceStore, orderStore: OrderStore(),
            invoiceStatusStore: InvoiceStatusStore(), orderStatusStore: OrderStatusStore(),
            tagStore: TagStore(), kindColorStore: KindColorStore()
        )
        XCTAssertEqual(targetInvoiceStore.numberPrefix, "ROUNDTRIP")
    }
}
