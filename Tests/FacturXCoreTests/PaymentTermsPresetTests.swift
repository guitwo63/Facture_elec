import XCTest
@testable import FacturXCore

final class PaymentTermsPresetStoreTests: XCTestCase {

    private let storageKey = "facturx.paymentTermsPresets.v1"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        super.tearDown()
    }

    func testDefaultsContainFourBuiltInPresets() {
        let store = PaymentTermsPresetStore()
        XCTAssertEqual(store.presets.count, 4)
        XCTAssertEqual(store.presets.map(\.id), ["comptant", "net30", "finDeMois30", "aReception"])
    }

    func testMatchingPresetIDRecognizesKnownText() {
        let store = PaymentTermsPresetStore()
        XCTAssertEqual(store.matchingPresetID(for: "Comptant"), "comptant")
        XCTAssertEqual(store.matchingPresetID(for: "Paiement à 30 jours"), "net30")
        XCTAssertEqual(store.matchingPresetID(for: "Paiement à 30 jours fin de mois"), "finDeMois30")
        XCTAssertEqual(store.matchingPresetID(for: "Paiement à réception"), "aReception")
    }

    func testMatchingPresetIDTrimsWhitespace() {
        let store = PaymentTermsPresetStore()
        XCTAssertEqual(store.matchingPresetID(for: "  Comptant  "), "comptant")
    }

    func testMatchingPresetIDReturnsNilForUnknownOrEmptyText() {
        let store = PaymentTermsPresetStore()
        XCTAssertNil(store.matchingPresetID(for: "Virement à 45 jours"))
        XCTAssertNil(store.matchingPresetID(for: nil))
        XCTAssertNil(store.matchingPresetID(for: ""))
        XCTAssertNil(store.matchingPresetID(for: "   "))
    }

    func testAppendPersistsNewPreset() {
        let store = PaymentTermsPresetStore()
        store.append(PaymentTermsPreset(id: "net60", label: "60 jours net", text: "Paiement à 60 jours"))

        let reloaded = PaymentTermsPresetStore()
        XCTAssertEqual(reloaded.presets.count, 5)
        XCTAssertEqual(reloaded.matchingPresetID(for: "Paiement à 60 jours"), "net60")
    }

    func testUpsertUpdatesExistingPresetInPlace() {
        let store = PaymentTermsPresetStore()
        var comptant = store.presets[0]
        comptant.label = "Paiement immédiat"
        store.upsert(comptant)

        XCTAssertEqual(store.presets.count, 4, "upsert sur un id existant ne doit pas dupliquer")
        XCTAssertEqual(store.presets[0].label, "Paiement immédiat")
    }

    func testRemoveDeletesPresetAndPersists() {
        let store = PaymentTermsPresetStore()
        store.remove(at: 0)

        let reloaded = PaymentTermsPresetStore()
        XCTAssertEqual(reloaded.presets.count, 3)
        XCTAssertNil(reloaded.matchingPresetID(for: "Comptant"))
    }

    func testResetRestoresBuiltInDefaults() {
        let store = PaymentTermsPresetStore()
        store.append(PaymentTermsPreset(id: "custom", label: "X", text: "Y"))
        store.remove(at: 0)

        store.reset()

        XCTAssertEqual(store.presets.map(\.id), ["comptant", "net30", "finDeMois30", "aReception"])
    }
}
