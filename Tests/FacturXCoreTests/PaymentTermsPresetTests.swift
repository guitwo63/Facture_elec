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

    func testBuiltInPresetsCarryExpectedDueRules() {
        let byID = Dictionary(uniqueKeysWithValues: PaymentTermsPresetStore.defaults.map { ($0.id, $0.dueRule) })
        XCTAssertEqual(byID["comptant"], PaymentTermsDueRule.none)
        XCTAssertEqual(byID["net30"], .days(30))
        XCTAssertEqual(byID["finDeMois30"], .endOfMonthPlusDays(30))
        XCTAssertEqual(byID["aReception"], PaymentTermsDueRule.none)
    }

    /// Un préréglage persisté avant l'ajout de `dueRule` (ex. par une version antérieure
    /// de l'app) ne doit pas empêcher le décodage — cf. le pattern de migration sûre
    /// utilisé partout ailleurs (`decodeIfPresent(...) ?? default`).
    func testDecodingPresetWithoutDueRuleDefaultsToNone() throws {
        let legacyJSON = """
        {"id": "custom", "label": "Ancien", "text": "Paiement à 45 jours"}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PaymentTermsPreset.self, from: legacyJSON)
        XCTAssertEqual(decoded.dueRule, .none)
        XCTAssertEqual(decoded.text, "Paiement à 45 jours")
    }
}

final class PaymentTermsDueRuleTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Paris")!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testNoneReturnsIssueDateUnchanged() {
        let issue = date(2026, 3, 15)
        XCTAssertEqual(PaymentTermsDueRule.none.dueDate(from: issue, calendar: calendar), issue)
    }

    func testDaysAddsCalendarDays() {
        let issue = date(2026, 3, 15)
        let due = PaymentTermsDueRule.days(30).dueDate(from: issue, calendar: calendar)
        XCTAssertEqual(due, date(2026, 4, 14))
    }

    func testEndOfMonthPlusDaysUsesLastDayOfIssueMonth() {
        // Février 2026 (non bissextile) : 28 jours.
        let issue = date(2026, 2, 5)
        let due = PaymentTermsDueRule.endOfMonthPlusDays(30).dueDate(from: issue, calendar: calendar)
        XCTAssertEqual(due, date(2026, 3, 30), "28 fév + 30 jours")
    }

    func testEndOfMonthPlusDaysHandlesDecemberYearBoundary() {
        let issue = date(2026, 12, 10)
        let due = PaymentTermsDueRule.endOfMonthPlusDays(30).dueDate(from: issue, calendar: calendar)
        XCTAssertEqual(due, date(2027, 1, 30), "31 déc + 30 jours")
    }
}
