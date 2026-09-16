import XCTest
@testable import FacturXCore

final class ModuleSettingsTests: XCTestCase {

    func testDefaultsEnableEveryModule() {
        let settings = ModuleSettings()
        XCTAssertTrue(settings.ordersEnabled, "une installation existante ne doit pas perdre un module au silence")
        XCTAssertTrue(settings.quotesEnabled)
    }

    func testDecodingToleratesMissingFieldsFromOlderPersistedData() throws {
        let legacyJSON = "{}"
        let decoded = try JSONDecoder().decode(ModuleSettings.self, from: Data(legacyJSON.utf8))
        XCTAssertTrue(decoded.ordersEnabled)
        XCTAssertTrue(decoded.quotesEnabled)
    }

    func testDecodingRespectsExplicitlyDisabledModules() throws {
        let json = #"{"ordersEnabled":false,"quotesEnabled":true}"#
        let decoded = try JSONDecoder().decode(ModuleSettings.self, from: Data(json.utf8))
        XCTAssertFalse(decoded.ordersEnabled)
        XCTAssertTrue(decoded.quotesEnabled)
    }
}

final class ModuleStoreTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "facturx.modules.v1")
        super.tearDown()
    }

    func testSaveThenReloadPersistsDisabledModules() {
        let store = ModuleStore()
        store.settings.ordersEnabled = false
        store.save()

        let reloaded = ModuleStore()
        XCTAssertFalse(reloaded.settings.ordersEnabled)
        XCTAssertTrue(reloaded.settings.quotesEnabled)
    }
}
