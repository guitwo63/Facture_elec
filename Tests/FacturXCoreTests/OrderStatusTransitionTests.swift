import XCTest
@testable import FacturXCore

final class OrderStatusTransitionTests: XCTestCase {

    override func tearDown() {
        AppPersistence.defaults.removeObject(forKey: "orderx.statuses.v1")
        super.tearDown()
    }

    func testDefaultTransitionsMatchStandardLifecycle() {
        let store = OrderStatusStore()
        XCTAssertEqual(store.allowedTransitions(from: .draft, isAdmin: false), [.issued])
        XCTAssertEqual(store.allowedTransitions(from: .confirmed, isAdmin: false), [])
        XCTAssertEqual(store.allowedTransitions(from: .cancelled, isAdmin: false), [])
    }

    func testAdminCanForceAnyOtherStandardStatus() {
        let store = OrderStatusStore()
        let forAdmin = store.allowedTransitions(from: .confirmed, isAdmin: true)
        XCTAssertEqual(Set(forAdmin), Set(OrderStatus.allCases.filter { $0 != .confirmed }))
    }

    func testTransitionsAreConfigurable() {
        let store = OrderStatusStore()
        guard let idx = store.overrides.firstIndex(where: { $0.id == OrderStatus.draft.rawValue }) else {
            return XCTFail("Statut brouillon introuvable")
        }
        store.overrides[idx].transitionCodes = [OrderStatus.cancelled.rawValue]
        XCTAssertEqual(store.allowedTransitions(from: .draft, isAdmin: false), [.cancelled])
    }

    func testStandardStatusRemainsNonDeletable() {
        let store = OrderStatusStore()
        guard let idx = store.overrides.firstIndex(where: { $0.id == OrderStatus.confirmed.rawValue }) else {
            return XCTFail("Statut confirmée introuvable")
        }
        XCTAssertTrue(store.overrides[idx].isPDPStatus)
        let countBefore = store.overrides.count
        store.remove(at: idx)
        XCTAssertEqual(store.overrides.count, countBefore, "Un statut du cycle standard ne doit jamais être supprimable")
    }

    func testLoadToleratesPersistedDataWithoutTransitionCodes() throws {
        // Simule une donnée persistée avant l'introduction de transitionCodes,
        // pour vérifier que le décodage ne perd pas les personnalisations existantes.
        struct LegacyOverride: Codable {
            let id: String
            let label: String
            let systemImage: String
            let hexColor: String
        }
        let legacy = OrderStatus.allCases.map {
            LegacyOverride(id: $0.rawValue, label: "Ancien " + $0.label, systemImage: $0.systemImage, hexColor: $0.hexColor)
        }
        let data = try JSONEncoder().encode(legacy)
        AppPersistence.defaults.set(data, forKey: "orderx.statuses.v1")

        let store = OrderStatusStore()
        XCTAssertEqual(store.override(for: .draft).label, "Ancien Brouillon")
        XCTAssertEqual(store.override(for: .draft).transitionCodes, [])
    }
}
