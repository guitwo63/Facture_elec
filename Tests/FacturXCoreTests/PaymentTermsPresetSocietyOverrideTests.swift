import XCTest
@testable import FacturXCore

/// Résolution par société des préréglages de conditions de paiement, telle que l'appliquent
/// l'éditeur de facture, la fiche tiers et la facture guidée (`matchingPreset(for:companyID:)`
/// et `preset(id:companyID:)`, tous deux lus dans `list(for:)`) : un préréglage personnalisé
/// pour la société A n'est proposé, reconnu et appliqué que sur les documents de A. Voir
/// `ValueTableSocietyOverrideCatalogTests.swift` pour la liste elle-même.
final class PaymentTermsPresetSocietyOverrideTests: XCTestCase {

    private let keys = [
        "facturx.paymentTermsPresets.v1",
        "facturx.paymentTermsPresets.bysociety.v1",
        "facturx.directory.v1",
        "facturx.directory.societeInterco.migrated.v1",
    ]

    override func setUp() {
        super.setUp()
        keys.forEach { AppPersistence.defaults.removeObject(forKey: $0) }
        PartyDirectory.shared.entries = []
    }

    override func tearDown() {
        PartyDirectory.shared.entries = []
        keys.forEach { AppPersistence.defaults.removeObject(forKey: $0) }
        super.tearDown()
    }

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Paris")!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @discardableResult
    private func designatePrincipale(_ name: String = "Principale") -> UUID {
        let entry = DirectoryEntry(kinds: [.societe], party: InvoiceParty(name: name, street: "", postcode: "", city: ""))
        PartyDirectory.shared.upsert(entry)
        PartyDirectory.shared.setPrincipale(entry.id)
        return entry.id
    }

    func testCompanyOnlyPresetIsOfferedMatchedAndAppliedOnlyForItsCompany() {
        let store = PaymentTermsPresetStore()
        let cidA = UUID(); let cidB = UUID()
        let net45 = PaymentTermsPreset(id: "net45A", label: "45 jours net", text: "Paiement à 45 jours", dueRule: .days(45))
        store.setOverride(net45, companyID: cidA)

        XCTAssertTrue(store.list(for: cidA).contains { $0.id == "net45A" })
        XCTAssertFalse(store.list(for: cidB).contains { $0.id == "net45A" })
        XCTAssertEqual(store.matchingPreset(for: "Paiement à 45 jours", companyID: cidA), net45)
        XCTAssertEqual(store.matchingPresetID(for: "Paiement à 45 jours", companyID: cidA), "net45A")
        XCTAssertNil(store.matchingPreset(for: "Paiement à 45 jours", companyID: cidB), "B : saisie libre (Personnalisé)")
        XCTAssertEqual(store.preset(id: "net45A", companyID: cidA), net45)
        XCTAssertNil(store.preset(id: "net45A", companyID: cidB))
    }

    func testCustomizedDueRuleAppliesOnlyToItsCompany() {
        let store = PaymentTermsPresetStore()
        let cidA = UUID(); let cidB = UUID()
        var net30 = store.presets.first { $0.id == "net30" }!
        net30.dueRule = .days(45)
        store.setOverride(net30, companyID: cidA)
        let issue = date(2026, 3, 15)

        // Choix du préréglage dans le menu : l'échéance suit la règle de la société du document.
        XCTAssertEqual(store.preset(id: "net30", companyID: cidA)?.dueRule.dueDate(from: issue, calendar: calendar), date(2026, 4, 29))
        XCTAssertEqual(store.preset(id: "net30", companyID: cidB)?.dueRule.dueDate(from: issue, calendar: calendar), date(2026, 4, 14))
        // Même texte, deux règles : le préréglage actif (recalcul à la date de facture, champ
        // Échéance grisé) dépend lui aussi de la société.
        XCTAssertEqual(store.matchingPreset(for: "Paiement à 30 jours", companyID: cidA)?.dueRule, .days(45))
        XCTAssertEqual(store.matchingPreset(for: "Paiement à 30 jours", companyID: cidB)?.dueRule, .days(30))
    }

    func testCustomizedTextReplacesGlobalTextForItsCompanyOnly() {
        let store = PaymentTermsPresetStore()
        let cidA = UUID(); let cidB = UUID()
        var net30 = store.presets.first { $0.id == "net30" }!
        net30.text = "Paiement à 30 jours net, sans escompte"
        store.setOverride(net30, companyID: cidA)

        XCTAssertEqual(store.preset(id: "net30", companyID: cidA)?.text, "Paiement à 30 jours net, sans escompte")
        XCTAssertEqual(store.matchingPresetID(for: "Paiement à 30 jours net, sans escompte", companyID: cidA), "net30")
        XCTAssertNil(store.matchingPreset(for: "Paiement à 30 jours", companyID: cidA), "le texte global n'est plus celui du préréglage de A")
        XCTAssertEqual(store.matchingPresetID(for: "Paiement à 30 jours", companyID: cidB), "net30")
    }

    func testNilCompanyStillResolvesToPrincipaleThenGlobal() {
        let store = PaymentTermsPresetStore()
        let net60 = PaymentTermsPreset(id: "net60", label: "60 jours net", text: "Paiement à 60 jours", dueRule: .days(60))

        // Sans société principale : réglage global seul, les surcharges d'une société ignorées.
        store.setOverride(net60, companyID: UUID())
        XCTAssertNil(store.matchingPreset(for: "Paiement à 60 jours", companyID: nil))
        XCTAssertEqual(store.matchingPresetID(for: "Paiement à 30 jours", companyID: nil), "net30")

        let principaleID = designatePrincipale()
        store.setOverride(net60, companyID: principaleID)
        XCTAssertEqual(store.matchingPreset(for: "Paiement à 60 jours", companyID: nil), net60)
        XCTAssertEqual(store.preset(id: "net60", companyID: nil), net60)
        XCTAssertNil(store.preset(id: "net60", companyID: UUID()), "une autre société n'hérite pas de la principale")
    }

    func testMatchingPresetTrimsAndIgnoresEmptyText() {
        let store = PaymentTermsPresetStore()
        let cid = UUID()
        XCTAssertEqual(store.matchingPreset(for: "  Comptant  ", companyID: cid)?.id, "comptant")
        XCTAssertNil(store.matchingPreset(for: nil, companyID: cid))
        XCTAssertNil(store.matchingPreset(for: "   ", companyID: cid))
    }
}
