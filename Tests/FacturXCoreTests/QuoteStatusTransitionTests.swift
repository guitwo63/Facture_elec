import XCTest
@testable import FacturXCore

final class QuoteStatusTransitionTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "facturx.quotestatuses.v1")
        super.tearDown()
    }

    func testDefaultTransitionsMatchStandardLifecycle() {
        let store = QuoteStatusStore()
        XCTAssertEqual(store.allowedTransitions(from: .draft), [.sent])
        XCTAssertEqual(store.allowedTransitions(from: .sent), [.accepted, .refused, .expired])
        XCTAssertEqual(store.allowedTransitions(from: .accepted), [])
        XCTAssertEqual(store.allowedTransitions(from: .refused), [])
        XCTAssertEqual(store.allowedTransitions(from: .expired), [])
    }

    func testTransitionsAreConfigurable() {
        let store = QuoteStatusStore()
        guard let idx = store.overrides.firstIndex(where: { $0.id == QuoteStatus.draft.rawValue }) else {
            return XCTFail("Statut brouillon introuvable")
        }
        store.overrides[idx].transitionCodes = [QuoteStatus.expired.rawValue]
        XCTAssertEqual(store.allowedTransitions(from: .draft), [.expired])
    }

    func testOverrideFallsBackToStatusDefaultsWhenNotConfigured() {
        let store = QuoteStatusStore()
        let override = store.override(for: .accepted)
        XCTAssertEqual(override.label, QuoteStatus.accepted.label)
        XCTAssertEqual(override.hexColor, QuoteStatus.accepted.hexColor)
    }

    func testLabelCustomizationIsReflectedInOverride() {
        let store = QuoteStatusStore()
        guard let idx = store.overrides.firstIndex(where: { $0.id == QuoteStatus.sent.rawValue }) else {
            return XCTFail("Statut envoyé introuvable")
        }
        store.overrides[idx].label = "En attente de réponse"
        XCTAssertEqual(store.override(for: .sent).label, "En attente de réponse")
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
        let legacy = QuoteStatus.allCases.map {
            LegacyOverride(id: $0.rawValue, label: "Ancien " + $0.label, systemImage: $0.systemImage, hexColor: $0.hexColor)
        }
        let data = try JSONEncoder().encode(legacy)
        UserDefaults.standard.set(data, forKey: "facturx.quotestatuses.v1")

        let store = QuoteStatusStore()
        XCTAssertEqual(store.override(for: .draft).label, "Ancien Brouillon")
        XCTAssertEqual(store.override(for: .draft).transitionCodes, [])
    }

    func testSaveThenReloadPersistsCustomizations() {
        let store = QuoteStatusStore()
        guard let idx = store.overrides.firstIndex(where: { $0.id == QuoteStatus.refused.rawValue }) else {
            return XCTFail("Statut refusé introuvable")
        }
        store.overrides[idx].label = "Décliné"
        store.overrides[idx].hexColor = "112233"
        store.save()

        let reloaded = QuoteStatusStore()
        XCTAssertEqual(reloaded.override(for: .refused).label, "Décliné")
        XCTAssertEqual(reloaded.override(for: .refused).hexColor, "112233")
    }

    func testResetRestoresDefaults() {
        let store = QuoteStatusStore()
        guard let idx = store.overrides.firstIndex(where: { $0.id == QuoteStatus.draft.rawValue }) else {
            return XCTFail("Statut brouillon introuvable")
        }
        store.overrides[idx].label = "Provisoire"
        store.save()

        store.reset()
        XCTAssertEqual(store.override(for: .draft).label, QuoteStatus.draft.label)
    }
}
