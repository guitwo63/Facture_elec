import XCTest
@testable import FacturXCore

/// Couvre la table de paramétrage des codes d'événement SUPER PDP (Réglages > Tables >
/// Statuts SUPER PDP) : libellés modifiables et règles de mise à jour vers le statut
/// fonctionnel de la facture — la passerelle proposée pour éviter de coder en dur le
/// mapping entre les codes `fr:2XX` et `InvoiceStatus` (voir `PDPStatusMapper` côté app).
final class SuperPDPStatusCodeStoreTests: XCTestCase {

    private let env = AppEnvironment.shared
    private let storageKey = "facturx.superpdp.statusCodes.v1"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: env.key(storageKey))
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: env.key(storageKey))
        super.tearDown()
    }

    func testDefaultCodesCoverTheOfficialFrTable() {
        let ids = Set(SuperPDPStatusCodeStore.defaultCodes.map(\.id))
        for code in ["fr:200", "fr:201", "fr:202", "fr:203", "fr:204", "fr:205", "fr:206", "fr:207", "fr:208", "fr:209", "fr:210", "fr:211", "fr:212", "fr:213"] {
            XCTAssertTrue(ids.contains(code), "code officiel \(code) absent des valeurs par défaut")
        }
    }

    func testFunctionalTransitionMatchesTheCorrectedMapping() {
        let store = SuperPDPStatusCodeStore()
        XCTAssertEqual(store.functionalTransition(for: "fr:205"), .accepted)
        XCTAssertEqual(store.functionalTransition(for: "fr:207"), .disputed)
        XCTAssertEqual(store.functionalTransition(for: "fr:210"), .refused)
        XCTAssertEqual(store.functionalTransition(for: "fr:212"), .paid)
    }

    func testInformationalCodesHaveNoFunctionalTransition() {
        let store = SuperPDPStatusCodeStore()
        for code in ["fr:200", "fr:201", "fr:202", "fr:203", "fr:204", "fr:208", "fr:209", "fr:211"] {
            XCTAssertNil(store.functionalTransition(for: code), "\(code) devrait rester informatif")
        }
    }

    func testOverrideLookupIsCaseInsensitive() {
        let store = SuperPDPStatusCodeStore()
        XCTAssertEqual(store.functionalTransition(for: "FR:205"), .accepted)
    }

    func testUpsertPersistsCustomLabelAcrossReload() {
        let store = SuperPDPStatusCodeStore()
        store.upsert(PDPEventCodeOverride(id: "fr:205", label: "Approuvée par le client", functionalTransition: InvoiceStatus.accepted.rawValue, isSystemDefined: true))

        let reloaded = SuperPDPStatusCodeStore()
        XCTAssertEqual(reloaded.override(for: "fr:205")?.label, "Approuvée par le client")
    }

    func testAdminCanChangeTheFunctionalTransitionOfAKnownCode() {
        let store = SuperPDPStatusCodeStore()
        store.upsert(PDPEventCodeOverride(id: "fr:208", label: "En attente", functionalTransition: InvoiceStatus.disputed.rawValue, isSystemDefined: true))
        XCTAssertEqual(store.functionalTransition(for: "fr:208"), .disputed)
    }

    func testAdminCanAddACustomCodeNotYetKnownByAName() {
        let store = SuperPDPStatusCodeStore()
        store.upsert(PDPEventCodeOverride(id: "fr:220", label: "Nouveau code 1.33.0", functionalTransition: nil, isSystemDefined: false))
        XCTAssertEqual(store.override(for: "fr:220")?.label, "Nouveau code 1.33.0")
    }

    func testSystemDefinedCodesCannotBeRemoved() {
        let store = SuperPDPStatusCodeStore()
        let countBefore = store.overrides.count
        guard let known = store.override(for: "fr:212") else { return XCTFail("fr:212 introuvable") }
        store.remove(known)
        XCTAssertEqual(store.overrides.count, countBefore, "un code officiel ne doit jamais être supprimable")
    }

    func testCustomCodesCanBeRemoved() {
        let store = SuperPDPStatusCodeStore()
        let custom = PDPEventCodeOverride(id: "fr:999", label: "Test", isSystemDefined: false)
        store.upsert(custom)
        XCTAssertNotNil(store.override(for: "fr:999"))
        store.remove(custom)
        XCTAssertNil(store.override(for: "fr:999"))
    }

    /// Régression du même type que celle corrigée pour InvoiceStatusStore : charger une
    /// table partielle (comme si une version antérieure n'avait persisté qu'un
    /// sous-ensemble des codes connus) doit compléter les codes manquants sans perdre les
    /// personnalisations déjà faites, ni les codes ajoutés manuellement par l'administrateur.
    func testLoadMergesNewDefaultCodesWithoutLosingCustomizationsOrCustomEntries() throws {
        let partial = [
            PDPEventCodeOverride(id: "fr:205", label: "Personnalisé", functionalTransition: InvoiceStatus.accepted.rawValue, isSystemDefined: true),
            PDPEventCodeOverride(id: "fr:999", label: "Code maison", isSystemDefined: false)
        ]
        let data = try JSONEncoder().encode(partial)
        UserDefaults.standard.set(data, forKey: env.key(storageKey))

        let reloaded = SuperPDPStatusCodeStore()
        XCTAssertEqual(reloaded.override(for: "fr:205")?.label, "Personnalisé")
        XCTAssertNotNil(reloaded.override(for: "fr:999"), "le code ajouté manuellement doit être conservé")
        XCTAssertEqual(reloaded.functionalTransition(for: "fr:212"), .paid, "les codes absents du fichier partiel doivent revenir avec leur règle par défaut")
    }

    func testResetToDefaultsDiscardsCustomizations() {
        let store = SuperPDPStatusCodeStore()
        store.upsert(PDPEventCodeOverride(id: "fr:205", label: "Personnalisé", functionalTransition: nil, isSystemDefined: true))
        store.resetToDefaults()
        XCTAssertEqual(store.functionalTransition(for: "fr:205"), .accepted)
    }
}
