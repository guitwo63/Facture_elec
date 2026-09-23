import XCTest
@testable import FacturXCore

/// Avant cette migration, `SalesOrder.buyer` désignait notre société et
/// `.seller` le tiers — l'inverse de Devis/Facture. Ces tests vérifient la
/// migration one-shot de `OrderStore.load()` qui corrige les commandes déjà
/// persistées, sans jamais rejouer sur des commandes déjà migrées.
final class OrderStorePartySemanticsMigrationTests: XCTestCase {

    private let ordersKey = "orderx.orders.v1"
    private let migratedKey = "orderx.buyerSellerSemantics.migrated.v1"

    override func setUp() {
        super.setUp()
        resetPersistedState()
    }

    override func tearDown() {
        resetPersistedState()
        super.tearDown()
    }

    private func resetPersistedState() {
        AppPersistence.defaults.removeObject(forKey: ordersKey)
        AppPersistence.defaults.removeObject(forKey: migratedKey)
    }

    /// Représente une commande telle que persistée par une version antérieure
    /// à la migration : buyer = notre société, seller = le tiers.
    private func legacyOrder(number: String = "CD-LEGACY-1") -> SalesOrder {
        SalesOrder(
            number: number,
            buyer: InvoiceParty(name: "Mon Entreprise SARL", street: "", postcode: "", city: ""),
            seller: InvoiceParty(name: "Client Historique SAS", street: "", postcode: "", city: "")
        )
    }

    func testLoadSwapsBuyerAndSellerForOrdersPersistedBeforeMigration() throws {
        let data = try JSONEncoder().encode([legacyOrder()])
        AppPersistence.defaults.set(data, forKey: ordersKey)

        let store = OrderStore()

        XCTAssertEqual(store.orders.count, 1)
        XCTAssertEqual(store.orders[0].seller.name, "Mon Entreprise SARL", "après migration, notre société doit être seller, comme Devis/Facture")
        XCTAssertEqual(store.orders[0].buyer.name, "Client Historique SAS", "après migration, le tiers doit être buyer")
    }

    func testMigrationIsNotReplayedOnSubsequentLoads() throws {
        let data = try JSONEncoder().encode([legacyOrder()])
        AppPersistence.defaults.set(data, forKey: ordersKey)

        _ = OrderStore()
        // Un deuxième chargement (ex. relance de l'app) doit retrouver le même
        // sens, pas re-permuter buyer/seller à chaque lancement.
        let secondLoad = OrderStore()

        XCTAssertEqual(secondLoad.orders[0].seller.name, "Mon Entreprise SARL")
        XCTAssertEqual(secondLoad.orders[0].buyer.name, "Client Historique SAS")
    }

    func testNewDraftResolvesPreferredSellerEntryIntoSellerNotBuyer() {
        let store = OrderStore()
        let directory = PartyDirectory()
        let companyEntry = DirectoryEntry(
            kinds: [.societe],
            party: InvoiceParty(name: "Mon Entreprise SARL", street: "", postcode: "", city: "")
        )
        directory.entries = [companyEntry]

        let draft = store.newDraft(directory: directory, preferredSellerEntryID: companyEntry.id)

        XCTAssertEqual(draft.seller.name, "Mon Entreprise SARL", "la société émettrice par défaut doit remplir seller, comme pour Devis/Facture")
        XCTAssertEqual(draft.buyer.name, "", "buyer (le client) doit rester vide, à renseigner manuellement")
    }

    func testOrderCreatedAfterMigrationIsNeverSwapped() {
        // Pas de données préexistantes : le drapeau de migration est posé dès
        // le premier chargement (même à vide), donc une commande créée après
        // ne doit jamais être touchée par la migration.
        let store = OrderStore()
        let fresh = SalesOrder(
            number: "CD-NEW-1",
            buyer: InvoiceParty(name: "Nouveau Client", street: "", postcode: "", city: ""),
            seller: InvoiceParty(name: "Mon Entreprise SARL", street: "", postcode: "", city: "")
        )
        store.upsert(fresh)

        let reloaded = OrderStore()
        let found = reloaded.orders.first(where: { $0.number == "CD-NEW-1" })
        XCTAssertEqual(found?.buyer.name, "Nouveau Client")
        XCTAssertEqual(found?.seller.name, "Mon Entreprise SARL")
    }
}
