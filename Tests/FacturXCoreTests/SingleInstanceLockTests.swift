import XCTest
@testable import FacturXCore

final class SingleInstanceLockTests: XCTestCase {

    func testSecondInstanceCannotAcquireWhileFirstHoldsLock() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("facturx-test-\(UUID().uuidString).lock")
        defer { try? FileManager.default.removeItem(at: url) }

        let first = SingleInstanceLock(url: url)
        let second = SingleInstanceLock(url: url)

        XCTAssertTrue(first.acquire(), "La première instance doit obtenir le verrou")
        XCTAssertFalse(second.acquire(), "Une deuxième instance ne doit pas pouvoir acquérir le même verrou")

        first.release()
        XCTAssertTrue(second.acquire(), "Après libération, une autre instance doit pouvoir acquérir le verrou")
        second.release()
    }
}
