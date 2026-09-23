import XCTest
import Security
@testable import FacturXCore

/// Les tests ne partagent leur état avec aucune autre exécution du bundle, et ne touchent
/// jamais aux données réelles de l'app (domaine UserDefaults, service du Trousseau) : voir
/// `AppPersistence`.
final class AppPersistenceTests: XCTestCase {

    private let probeKey = "facturx.tests.apppersistence.probe.v1"

    func testSuiteAndKeychainServiceAreNamedAfterAUUIDSpecificToThisProcess() throws {
        let prefix = "fr.arverneo.facturxmacapp.tests."
        let run = try XCTUnwrap(AppPersistence.unitTestRun, "XCTest est chargé : la suite de tests doit être active")
        XCTAssertTrue(run.name.hasPrefix(prefix), run.name)
        XCTAssertNotNil(UUID(uuidString: String(run.name.dropFirst(prefix.count))), run.name)
        XCTAssertTrue(AppPersistence.defaults === run.defaults)
        XCTAssertEqual(AppPersistence.keychainService, run.name)
        XCTAssertEqual(KeychainStore.service, run.name)
        XCTAssertNotEqual(KeychainStore.service, AppPersistence.appKeychainService)
    }

    func testStoresPersistInTheSuiteNeverInTheXCTestProcessDomain() {
        XCTAssertFalse(AppPersistence.defaults === UserDefaults.standard)
        AppPersistence.defaults.set("isolé", forKey: probeKey)
        defer { AppPersistence.defaults.removeObject(forKey: probeKey) }
        XCTAssertNil(UserDefaults.standard.object(forKey: probeKey))
    }

    func testKeychainStoreWritesLandInThisProcessServiceNeverInTheAppOne() {
        KeychainStore.set("s3cret", forKey: probeKey)
        defer { KeychainStore.delete(forKey: probeKey) }
        XCTAssertTrue(keychainHasEntry(service: AppPersistence.keychainService, account: probeKey))
        XCTAssertFalse(keychainHasEntry(service: AppPersistence.appKeychainService, account: probeKey))
    }

    func testEraseEmptiesTheSuiteAndRemovesEveryKeychainEntry() {
        let run = AppPersistence.UnitTestRun()
        run.defaults.set("x", forKey: probeKey)
        let accounts = ["a", "b", "c"]
        for account in accounts {
            let item: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: run.name,
                kSecAttrAccount as String: account,
                kSecValueData as String: Data("x".utf8)
            ]
            XCTAssertEqual(SecItemAdd(item as CFDictionary, nil), errSecSuccess)
        }

        run.erase()

        XCTAssertNil(run.defaults.object(forKey: probeKey))
        for account in accounts {
            XCTAssertFalse(keychainHasEntry(service: run.name, account: account), account)
        }
    }

    func testRemovePlistsDeletesOnlyTestSuitesLeftBehindByFinishedRuns() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("facturx-tests-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let prefix = AppPersistence.UnitTestRun.namePrefix
        let finished = dir.appendingPathComponent("\(prefix)\(UUID().uuidString).plist")
        let running = dir.appendingPathComponent("\(prefix)\(UUID().uuidString).plist")
        let app = dir.appendingPathComponent("\(AppPersistence.appKeychainService).plist")
        for file in [finished, running, app] {
            try Data("{}".utf8).write(to: file)
        }
        let anHourAgo = Date().addingTimeInterval(-3600)
        try fm.setAttributes([.modificationDate: anHourAgo], ofItemAtPath: finished.path)
        try fm.setAttributes([.modificationDate: anHourAgo], ofItemAtPath: app.path)

        AppPersistence.UnitTestRun.removePlists(olderThan: 2 * 60, in: dir)

        XCTAssertFalse(fm.fileExists(atPath: finished.path))
        XCTAssertTrue(fm.fileExists(atPath: running.path), "une exécution en cours garde sa suite")
        XCTAssertTrue(fm.fileExists(atPath: app.path), "le domaine de l'app n'est jamais touché")
    }

    /// Garde-fou : un store ou un test qui écrirait directement dans `UserDefaults.standard`
    /// ou dans le Trousseau contournerait l'isolation (et, pour le Trousseau, viserait le
    /// service réel de l'app).
    func testNoCoreOrTestSourceBypassesAppPersistence() throws {
        let thisFile = URL(fileURLWithPath: #filePath)
        let testsDir = thisFile.deletingLastPathComponent()
        let coreDir = testsDir.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/FacturXCore")
        let allowed: Set<String> = ["AppPersistence.swift", "KeychainStore.swift", thisFile.lastPathComponent]
        var offenders: [String] = []
        for dir in [coreDir, testsDir] {
            let files = (FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
                .filter { $0.pathExtension == "swift" }
            XCTAssertFalse(files.isEmpty, "aucun source trouvé dans \(dir.path)")
            for file in files where !allowed.contains(file.lastPathComponent) {
                let source = try String(contentsOf: file, encoding: .utf8)
                for pattern in ["UserDefaults.standard", "SecItem"] where source.contains(pattern) {
                    offenders.append("\(file.lastPathComponent) : \(pattern)")
                }
            }
        }
        XCTAssertEqual(offenders, [], "passer par AppPersistence.defaults et KeychainStore")
    }

    private func keychainHasEntry(service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true
        ]
        var result: AnyObject?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    }
}
