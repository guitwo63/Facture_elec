import XCTest
@testable import FacturXCore

final class BackupRetentionTests: XCTestCase {

    func testKeepsOnlyTheNMostRecentNames() {
        let names = [
            "facture_elec_sauvegarde_2026-09-17_0300.json",
            "facture_elec_sauvegarde_2026-09-16_0300.json",
            "facture_elec_sauvegarde_2026-09-15_0300.json",
            "facture_elec_sauvegarde_2026-09-14_0300.json",
            "facture_elec_sauvegarde_2026-09-13_0300.json"
        ]
        let toDelete = BackupRetention.namesToDelete(sortedDescendingNames: names, keep: 3)
        XCTAssertEqual(toDelete, [
            "facture_elec_sauvegarde_2026-09-14_0300.json",
            "facture_elec_sauvegarde_2026-09-13_0300.json"
        ])
    }

    func testReturnsEmptyWhenFewerFilesThanRetentionCount() {
        let names = ["a.json", "b.json"]
        XCTAssertTrue(BackupRetention.namesToDelete(sortedDescendingNames: names, keep: 3).isEmpty)
    }

    func testKeepZeroDeletesEverything() {
        let names = ["a.json", "b.json"]
        XCTAssertEqual(BackupRetention.namesToDelete(sortedDescendingNames: names, keep: 0), ["a.json", "b.json"])
    }

    func testNegativeKeepDeletesNothingRatherThanCrashing() {
        let names = ["a.json", "b.json"]
        XCTAssertTrue(BackupRetention.namesToDelete(sortedDescendingNames: names, keep: -1).isEmpty)
    }
}

final class BackupStrategySettingsTests: XCTestCase {

    func testDefaultsMatchStatedPolicy() {
        let settings = BackupStrategySettings()
        XCTAssertEqual(settings.retentionCount, 3)
        XCTAssertFalse(settings.autoBackupOnLaunch)
        XCTAssertNil(settings.localBackupFolderPath)
    }

    func testDecodingToleratesMissingFieldsFromOlderPersistedData() throws {
        let legacyJSON = "{}"
        let decoded = try JSONDecoder().decode(BackupStrategySettings.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(decoded.retentionCount, 3)
        XCTAssertFalse(decoded.autoBackupOnLaunch)
    }
}
