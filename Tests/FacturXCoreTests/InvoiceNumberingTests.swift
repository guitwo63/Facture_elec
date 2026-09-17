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
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    override func tearDown() {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
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
