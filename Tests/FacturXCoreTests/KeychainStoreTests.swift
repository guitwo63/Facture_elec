import XCTest
@testable import FacturXCore

final class KeychainStoreTests: XCTestCase {
    private let key = "facturx.tests.keychainstore.probe.v1"

    override func tearDown() {
        KeychainStore.delete(forKey: key)
        super.tearDown()
    }

    func testSetThenGetRoundTrips() {
        KeychainStore.set("s3cret", forKey: key)
        XCTAssertEqual(KeychainStore.get(forKey: key), "s3cret")
    }

    func testSetOverwritesPreviousValue() {
        KeychainStore.set("first", forKey: key)
        KeychainStore.set("second", forKey: key)
        XCTAssertEqual(KeychainStore.get(forKey: key), "second")
    }

    func testSettingEmptyStringDeletesTheEntry() {
        KeychainStore.set("s3cret", forKey: key)
        KeychainStore.set("", forKey: key)
        XCTAssertNil(KeychainStore.get(forKey: key))
    }

    func testGetReturnsNilForUnknownKey() {
        XCTAssertNil(KeychainStore.get(forKey: "facturx.tests.keychainstore.unknown.v1"))
    }

    func testDeleteRemovesEntry() {
        KeychainStore.set("s3cret", forKey: key)
        KeychainStore.delete(forKey: key)
        XCTAssertNil(KeychainStore.get(forKey: key))
    }
}
