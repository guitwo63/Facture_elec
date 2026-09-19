import XCTest
@testable import FacturXCore

/// Couvre le passage de `DirectoryEntry.kind` (un seul type) à `.kinds` (multi-sélecteur),
/// avec l'ajout du type `.interco` — voir `PartyDirectory.swift`.
final class DirectoryEntryKindTests: XCTestCase {

    private func party(_ name: String = "Tiers") -> InvoiceParty {
        InvoiceParty(name: name, street: "", postcode: "", city: "")
    }

    // MARK: - DirectoryEntryKind.selectable

    func testSelectableExcludesBothButIncludesInterco() {
        XCTAssertFalse(DirectoryEntryKind.selectable.contains(.both))
        XCTAssertTrue(DirectoryEntryKind.selectable.contains(.interco))
        XCTAssertEqual(Set(DirectoryEntryKind.selectable), [.client, .societe, .fournisseur, .interco])
    }

    // MARK: - Construction

    func testInitDefaultsToClientWhenKindsIsEmpty() {
        let entry = DirectoryEntry(kinds: [], party: party())
        XCTAssertEqual(entry.kinds, [.client], "un tiers sans type ne doit jamais exister — repli sur Client")
    }

    func testInitAcceptsMultipleKinds() {
        let entry = DirectoryEntry(kinds: [.client, .interco], party: party())
        XCTAssertEqual(entry.kinds, [.client, .interco])
    }

    // MARK: - Migration : ancien champ singulier "kind"

    func testDecodingLegacySingleKindClient() throws {
        let json = """
        {"id":"\(UUID().uuidString)","kind":"client","party":{"name":"A","street":"","postcode":"","city":""}}
        """.data(using: .utf8)!
        let entry = try JSONDecoder().decode(DirectoryEntry.self, from: json)
        XCTAssertEqual(entry.kinds, [.client])
    }

    func testDecodingLegacyBothExpandsToClientAndFournisseur() throws {
        let json = """
        {"id":"\(UUID().uuidString)","kind":"both","party":{"name":"A","street":"","postcode":"","city":""}}
        """.data(using: .utf8)!
        let entry = try JSONDecoder().decode(DirectoryEntry.self, from: json)
        XCTAssertEqual(entry.kinds, [.client, .fournisseur],
                        "une fiche « both » existante doit devenir Client + Fournisseur, pas rester ambiguë")
    }

    func testDecodingWithNeitherKindsNorKindDefaultsToClient() throws {
        let json = """
        {"id":"\(UUID().uuidString)","party":{"name":"A","street":"","postcode":"","city":""}}
        """.data(using: .utf8)!
        let entry = try JSONDecoder().decode(DirectoryEntry.self, from: json)
        XCTAssertEqual(entry.kinds, [.client])
    }

    func testNewKindsFieldTakesPrecedenceOverLegacyKindIfBothPresent() throws {
        let json = """
        {"id":"\(UUID().uuidString)","kind":"client","kinds":["fournisseur","interco"],
         "party":{"name":"A","street":"","postcode":"","city":""}}
        """.data(using: .utf8)!
        let entry = try JSONDecoder().decode(DirectoryEntry.self, from: json)
        XCTAssertEqual(entry.kinds, [.fournisseur, .interco])
    }

    // MARK: - Round-trip Codable (données neuves)

    func testRoundTripPreservesMultipleKindsIncludingInterco() throws {
        let entry = DirectoryEntry(kinds: [.client, .interco, .fournisseur], party: party("Multi"))
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(DirectoryEntry.self, from: data)
        XCTAssertEqual(decoded.kinds, [.client, .interco, .fournisseur])
    }

    func testEncodedDataNeverWritesLegacySingularKindKey() throws {
        let entry = DirectoryEntry(kinds: [.client], party: party())
        let data = try JSONEncoder().encode(entry)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNil(obj?["kind"], "les nouvelles données ne doivent plus écrire l'ancien champ singulier")
        XCTAssertNotNil(obj?["kinds"])
    }

    // MARK: - kindsLabel / isPayee / isSupplierOnly

    func testKindsLabelJoinsInDeclarationOrderRegardlessOfInsertionOrder() {
        let entry = DirectoryEntry(kinds: [.interco, .client], party: party())
        XCTAssertEqual(entry.kindsLabel, "Client / Interco")
    }

    func testKindsLabelNeverShowsLegacyBothWording() {
        // Migré depuis "both" : le libellé doit refléter le cumul, pas l'ancien mot composé.
        let entry = DirectoryEntry(kinds: [.client, .fournisseur], party: party())
        XCTAssertEqual(entry.kindsLabel, "Client / Fournisseur")
        XCTAssertFalse(entry.kindsLabel.contains("/ Fournisseur / Client"))
    }

    func testIsPayeeTrueForFournisseurOrSociete() {
        XCTAssertTrue(DirectoryEntry(kinds: [.fournisseur], party: party()).isPayee)
        XCTAssertTrue(DirectoryEntry(kinds: [.societe], party: party()).isPayee)
        XCTAssertTrue(DirectoryEntry(kinds: [.client, .fournisseur], party: party()).isPayee)
    }

    func testIsPayeeFalseForClientOrInterco() {
        XCTAssertFalse(DirectoryEntry(kinds: [.client], party: party()).isPayee)
        XCTAssertFalse(DirectoryEntry(kinds: [.client, .interco], party: party()).isPayee)
    }

    func testIsSupplierOnlyTrueForFournisseurAloneOrWithInterco() {
        XCTAssertTrue(DirectoryEntry(kinds: [.fournisseur], party: party()).isSupplierOnly)
        XCTAssertTrue(DirectoryEntry(kinds: [.fournisseur, .interco], party: party()).isSupplierOnly,
                      "interco n'ajoute pas de capacité destinataire")
    }

    func testIsSupplierOnlyFalseWhenClientOrSocieteAlsoPresent() {
        XCTAssertFalse(DirectoryEntry(kinds: [.fournisseur, .client], party: party()).isSupplierOnly)
        XCTAssertFalse(DirectoryEntry(kinds: [.fournisseur, .societe], party: party()).isSupplierOnly)
    }

    // MARK: - Import/export CSV multi-types

    func testParseKindsHandlesLegacyCombinedStrings() {
        XCTAssertEqual(ExportGenerator.parseKinds("Client / Fournisseur"), [.client, .fournisseur])
        XCTAssertEqual(ExportGenerator.parseKinds("both"), [.client, .fournisseur])
        XCTAssertEqual(ExportGenerator.parseKinds("les deux"), [.client, .fournisseur])
    }

    func testParseKindsHandlesNewMultiValueFormat() {
        XCTAssertEqual(ExportGenerator.parseKinds("Client / Interco"), [.client, .interco])
        XCTAssertEqual(ExportGenerator.parseKinds("client,interco,fournisseur"), [.client, .interco, .fournisseur])
    }

    func testParseKindsFallsBackToClientWhenEmptyOrUnrecognized() {
        XCTAssertEqual(ExportGenerator.parseKinds(nil), [.client])
        XCTAssertEqual(ExportGenerator.parseKinds(""), [.client])
        XCTAssertEqual(ExportGenerator.parseKinds("xyz"), [.client])
    }

    func testDirectoryCSVRoundTripPreservesMultipleKinds() {
        let entry = DirectoryEntry(
            kinds: [.fournisseur, .interco],
            party: InvoiceParty(name: "Filiale Achats", street: "", postcode: "", city: "", siren: "555555555")
        )
        let gen = ExportGenerator()
        let csv = gen.directoryCSV([entry])
        let result = gen.parseDirectoryCSV(csv)
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries.first?.kinds, [.fournisseur, .interco])
    }
}
