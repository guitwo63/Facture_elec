import XCTest
@testable import FacturXCore

/// Order-X n'admet que trois codes type de document : 220 (commande), 230 (modification) et
/// 231 (réponse), d'après `ORDERX_code2type` de la bibliothèque de référence factur-x. L'app
/// émettait 221 et 222, « commande ouverte » et « commande ponctuelle » dans l'UNTDID 1001. Le
/// XSD et le Schematron les acceptent, mais la bibliothèque les refuse (« This is not a valid
/// Order-X TypeCode »). Les métadonnées XMP disaient en outre toujours ORDER.
final class OrderTypeCodeTests: XCTestCase {

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
        UserDefaults.standard.removeObject(forKey: ordersKey)
        UserDefaults.standard.removeObject(forKey: migratedKey)
    }

    private func order(_ type: OrderTypeCode, number: String = "CD2026-0009") -> SalesOrder {
        SalesOrder(
            number: number, type: type,
            buyer: InvoiceParty(name: "Client Exemple SAS", street: "8 avenue des Champs", postcode: "75008", city: "Paris",
                                siren: "987654321", endpointID: "987654321", endpointSchemeID: "0225"),
            seller: InvoiceParty(name: "Mon Entreprise SARL", street: "12 rue du Commerce", postcode: "75001", city: "Paris",
                                 siren: "123456789", endpointID: "123456789", endpointSchemeID: "0225"),
            lines: [InvoiceLine(name: "Licence logicielle", quantity: 1, unit: "C62", unitPrice: 100, vatRate: 20)]
        )
    }

    /// Commande telle qu'une version antérieure l'aurait enregistrée, avec `type` = `legacy`.
    private func persisted(_ order: SalesOrder, type legacy: String) throws -> [String: Any] {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(order)) as? [String: Any])
        json["type"] = legacy
        return json
    }

    func testOnlyTheThreeOrderXCodesAreEmitted() throws {
        XCTAssertEqual(OrderTypeCode.allCases.map(\.rawValue), ["220", "230", "231"])
        for type in OrderTypeCode.allCases {
            let xml = String(decoding: try OrderCIOXMLGenerator().generate(order: order(type)), as: UTF8.self)
            XCTAssertTrue(xml.contains("<ram:TypeCode>\(type.rawValue)</ram:TypeCode>"), type.rawValue)
        }
    }

    /// Une commande enregistrée avec un ancien code est relue avec le bon, puis réécrite ainsi.
    func testLegacyCodesAreReadAsTheOrderXOnes() throws {
        let expected: [(String, OrderTypeCode)] = [("221", .orderChange), ("222", .orderResponse), ("220", .order),
                                                   ("230", .orderChange), ("231", .orderResponse), ("999", .order)]
        for (legacy, type) in expected {
            let data = try JSONSerialization.data(withJSONObject: persisted(order(.order), type: legacy))
            let decoded = try JSONDecoder().decode(SalesOrder.self, from: data)
            XCTAssertEqual(decoded.type, type, legacy)
            let reencoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any])
            XCTAssertEqual(reencoded["type"] as? String, type.rawValue, legacy)
        }
    }

    /// `OrderStore` décode la liste d'un bloc : sans la relecture des anciens codes, une seule
    /// commande en 221 vidait la liste, et la sauvegarde suivante l'aurait écrasée.
    func testStoreKeepsEveryOrderSavedWithLegacyCodes() throws {
        let list = [
            try persisted(order(.order, number: "CD-1"), type: "220"),
            try persisted(order(.order, number: "CD-2"), type: "221"),
            try persisted(order(.order, number: "CD-3"), type: "222"),
        ]
        UserDefaults.standard.set(try JSONSerialization.data(withJSONObject: list), forKey: ordersKey)
        UserDefaults.standard.set(true, forKey: migratedKey)

        let store = OrderStore()
        XCTAssertEqual(store.orders.map(\.number).sorted(), ["CD-1", "CD-2", "CD-3"])
        XCTAssertEqual(store.orders.first { $0.number == "CD-2" }?.type, .orderChange)
        XCTAssertEqual(store.orders.first { $0.number == "CD-3" }?.type, .orderResponse)
    }

    func testPDFMetadataCarriesTheDocumentType() throws {
        let expected: [(OrderTypeCode, String, String)] = [
            (.order, "ORDER", "Order"), (.orderChange, "ORDER_CHANGE", "Order Change"),
            (.orderResponse, "ORDER_RESPONSE", "Order Response"),
        ]
        for (type, documentType, name) in expected {
            let pdf = try OrderXGenerator().generate(order: order(type))
            let text = try XCTUnwrap(String(data: pdf, encoding: .isoLatin1))
            XCTAssertTrue(text.contains("<fx:DocumentType>\(documentType)</fx:DocumentType>"), type.rawValue)
            XCTAssertTrue(text.contains("Client Exemple SAS: \(name) CD2026-0009"), "titre XMP, \(type.rawValue)")
            XCTAssertTrue(OrderXValidator().validate(pdf: pdf).isValid, type.rawValue)
        }
    }
}
