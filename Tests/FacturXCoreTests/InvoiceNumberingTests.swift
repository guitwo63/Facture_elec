import XCTest
@testable import FacturXCore

final class InvoiceNumberingTests: XCTestCase {

    private let keys = [
        "facturx.invoices.v1",
        "facturx.number.prefix.v1",
        "facturx.number.includeyear.v1",
        "facturx.number.start.v1",
        "facturx.number.useseparator.v1",
        "facturx.number.overrides.bysociety.v1"
    ]

    override func setUp() {
        super.setUp()
        keys.forEach { AppPersistence.defaults.removeObject(forKey: $0) }
    }

    override func tearDown() {
        keys.forEach { AppPersistence.defaults.removeObject(forKey: $0) }
        super.tearDown()
    }

    // MARK: - InvoiceNumberingFormat

    func testDecodingNumberingFormatWithMissingFieldsUsesDefaults() throws {
        let json = "{}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(InvoiceNumberingFormat.self, from: json)
        XCTAssertEqual(decoded, InvoiceNumberingFormat())
    }

    // MARK: - Format effectif par société

    func testCompanyWithoutOverrideUsesDefaultFormat() {
        let store = InvoiceStore()
        store.numberPrefix = "FAC"
        let cid = UUID()
        XCTAssertEqual(store.numberingFormat(for: cid).prefix, "FAC")
        XCTAssertEqual(store.previewNextNumber(companyID: cid), store.previewNextNumber(companyID: nil))
    }

    func testOverrideAppliesOnlyToItsOwnCompany() {
        let store = InvoiceStore()
        store.numberPrefix = "FAC"
        let cidA = UUID()
        let cidB = UUID()
        store.numberFormatOverrides[cidA] = InvoiceNumberingFormat(prefix: "ALPHA", includeYear: false, start: 1, useSeparator: false)

        XCTAssertTrue(store.previewNextNumber(companyID: cidA).hasPrefix("ALPHA"))
        XCTAssertTrue(store.previewNextNumber(companyID: cidB).hasPrefix("FAC"))
        XCTAssertTrue(store.previewNextNumber(companyID: nil).hasPrefix("FAC"))
    }

    func testOverrideStartNumberIsIndependentOfDefault() {
        let store = InvoiceStore()
        store.numberStart = 1
        let cid = UUID()
        store.numberFormatOverrides[cid] = InvoiceNumberingFormat(prefix: "X", includeYear: false, start: 500, useSeparator: false)
        XCTAssertEqual(store.nextNumber(companyID: cid), "X0500")
    }

    func testRemovingOverrideRevertsToDefaultFormat() {
        let store = InvoiceStore()
        store.numberPrefix = "FAC"
        let cid = UUID()
        store.numberFormatOverrides[cid] = InvoiceNumberingFormat(prefix: "SPECIAL", includeYear: false, start: 1, useSeparator: false)
        XCTAssertEqual(store.numberingFormat(for: cid).prefix, "SPECIAL")

        store.numberFormatOverrides.removeValue(forKey: cid)
        XCTAssertEqual(store.numberingFormat(for: cid).prefix, "FAC")
    }

    func testCountersStayIndependentPerCompanyRegardlessOfFormat() {
        let store = InvoiceStore()
        store.numberPrefix = "FAC"
        store.numberIncludeYear = false
        store.numberUseSeparator = false
        let cidA = UUID()
        let cidB = UUID()
        let first = store.nextNumber(companyID: cidA)
        store.upsert(Invoice(number: first, seller: InvoiceParty(name: "", street: "", postcode: "", city: ""), buyer: InvoiceParty(name: "", street: "", postcode: "", city: ""), companyID: cidA))
        XCTAssertEqual(first, "FAC0001")
        XCTAssertEqual(store.nextNumber(companyID: cidA), "FAC0002", "la société A a maintenant une facture, son compteur avance")
        XCTAssertEqual(store.nextNumber(companyID: cidB), "FAC0001", "la société B n'a aucune facture : son compteur reste au numéro de début")
    }

    // MARK: - Persistance

    func testOverridesPersistAcrossReload() {
        let store = InvoiceStore()
        let cid = UUID()
        store.numberFormatOverrides[cid] = InvoiceNumberingFormat(prefix: "PERSIST", includeYear: true, start: 42, useSeparator: true)
        store.save()

        let reloaded = InvoiceStore()
        XCTAssertEqual(reloaded.numberFormatOverrides[cid]?.prefix, "PERSIST")
        XCTAssertEqual(reloaded.numberFormatOverrides[cid]?.start, 42)
    }

    // MARK: - Régression : doublon de numéro après suppression d'un brouillon

    /// Avant cette correction, nextNumber() comptait les factures existantes (paddedStart +
    /// count) au lieu de se baser sur le plus haut numéro utilisé. Supprimer une facture du
    /// milieu de la séquence décale ce compte, et la prochaine facture créée pouvait alors
    /// recevoir un numéro déjà pris par une facture restante de numéro plus élevé — un vrai
    /// doublon de numéro de facture, pas seulement une réutilisation esthétique.
    ///
    /// Le comportement voulu est allé plus loin ensuite (retour utilisateur après la
    /// première correction) : un numéro jamais "consommé" par une facture existante doit
    /// être recyclé pour la prochaine facture plutôt que de rester à jamais inutilisé —
    /// voir `testDeletingAMiddleInvoiceRecyclesItsFreedNumber` ci-dessous.
    func testDeletingAMiddleInvoiceNeverProducesADuplicateNumber() {
        let store = InvoiceStore()
        store.numberPrefix = "FAC"
        store.numberIncludeYear = false
        store.numberUseSeparator = false
        let party = InvoiceParty(name: "", street: "", postcode: "", city: "")

        let n1 = store.nextNumber()
        let inv1 = Invoice(number: n1, seller: party, buyer: party)
        store.upsert(inv1)
        let n2 = store.nextNumber()
        let inv2 = Invoice(number: n2, seller: party, buyer: party)
        store.upsert(inv2)
        let n3 = store.nextNumber()
        let inv3 = Invoice(number: n3, seller: party, buyer: party)
        store.upsert(inv3)
        XCTAssertEqual([n1, n2, n3], ["FAC0001", "FAC0002", "FAC0003"])

        store.delete(inv2)
        XCTAssertEqual(store.invoices.map(\.number).sorted(), ["FAC0001", "FAC0003"])

        let n4 = store.nextNumber()
        XCTAssertFalse(store.invoices.contains { $0.number == n4 }, "le nouveau numéro ne doit jamais déjà exister")
    }

    /// Le numéro d'une facture supprimée (FAC0002, jamais consommé par une facture restante)
    /// est recyclé pour la prochaine facture créée, au lieu de toujours repartir après le
    /// plus haut numéro existant (FAC0003) — demande explicite après test de la première
    /// version de cette correction.
    func testDeletingAMiddleInvoiceRecyclesItsFreedNumber() {
        let store = InvoiceStore()
        store.numberPrefix = "FAC"
        store.numberIncludeYear = false
        store.numberUseSeparator = false
        let party = InvoiceParty(name: "", street: "", postcode: "", city: "")

        let inv1 = Invoice(number: store.nextNumber(), seller: party, buyer: party)
        store.upsert(inv1)
        let inv2 = Invoice(number: store.nextNumber(), seller: party, buyer: party)
        store.upsert(inv2)
        let inv3 = Invoice(number: store.nextNumber(), seller: party, buyer: party)
        store.upsert(inv3)

        store.delete(inv2)
        XCTAssertEqual(store.nextNumber(), "FAC0002", "FAC0002 est libre (aucune facture restante ne le porte) : il doit être recyclé")
    }

    // MARK: - Condition de paiement par défaut

    func testNewDraftDefaultsToThirtyDaysNetWhenSellerHasNoOwnTerms() {
        let store = InvoiceStore()
        let draft = store.newDraft()
        XCTAssertEqual(draft.paymentTerms, "Paiement à 30 jours")
    }

    func testNewDraftUsesSellersOwnPaymentTermsWhenSet() {
        let directory = PartyDirectory()
        var entry = DirectoryEntry(kinds: [.societe], party: InvoiceParty(name: "Vendeur", street: "", postcode: "", city: ""))
        entry.party.paymentTerms = "Comptant"
        directory.upsert(entry)
        let store = InvoiceStore()
        let draft = store.newDraft(directory: directory, preferredSellerEntryID: entry.id)
        XCTAssertEqual(draft.paymentTerms, "Comptant", "la condition propre à la société prime sur le défaut 30 jours")
    }

    func testNoOverridesMeansExistingSingleSocietyBehaviorIsUnchanged() {
        // Une installation existante (une seule société, jamais de réglage par société créé)
        // ne doit voir aucune différence de comportement après cette évolution.
        let store = InvoiceStore()
        store.numberPrefix = "FAC"
        store.numberStart = 7
        XCTAssertTrue(store.numberFormatOverrides.isEmpty)
        let cid = UUID()
        XCTAssertEqual(store.previewNextNumber(companyID: cid), store.previewNextNumber(companyID: nil))
        XCTAssertTrue(store.previewNextNumber(companyID: cid).contains("0007"))
    }
}
