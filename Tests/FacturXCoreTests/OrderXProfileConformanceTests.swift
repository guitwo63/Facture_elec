import XCTest
import FacturXCore

/// Order-X contre le XSD du profil qu'il déclare, corrigé le 2026-09-23 après mesure avec les
/// XSD et Schematron officiels (paquet factur-x) : le récapitulatif de TVA d'en-tête n'est admis
/// qu'en EXTENDED, BASIC n'admet ni TVA ni description de ligne, et la référence de commande
/// doit précéder celle du devis dans les trois profils. Ces tests figent la structure validée
/// (séquences reprises des XSD) sans remplacer les validateurs eux-mêmes.
final class OrderXProfileConformanceTests: XCTestCase {

    // MARK: - Séquences des XSD Order-X (types concernés)

    /// HeaderTradeAgreementType d'EXTENDED ; BASIC et COMFORT en sont des sous-ensembles, dans
    /// le même ordre.
    private let headerAgreementSequence = [
        "BuyerReference", "SellerTradeParty", "BuyerTradeParty", "BuyerRequisitionerTradeParty",
        "ProductEndUserTradeParty", "ApplicableTradeDeliveryTerms", "SellerOrderReferencedDocument",
        "BuyerOrderReferencedDocument", "QuotationReferencedDocument", "ContractReferencedDocument",
        "RequisitionReferencedDocument", "AdditionalReferencedDocument", "BuyerAgentTradeParty",
        "CatalogueReferencedDocument", "BlanketOrderReferencedDocument", "PreviousOrderReferencedDocument",
        "PreviousOrderChangeReferencedDocument", "PreviousOrderResponseReferencedDocument",
        "SpecifiedProcuringProject", "UltimateCustomerOrderReferencedDocument",
    ]

    /// HeaderTradeSettlementType, par profil.
    private let headerSettlementSequence: [OrderXProfile: [String]] = [
        .basic: ["OrderCurrencyCode", "SpecifiedTradeSettlementHeaderMonetarySummation",
                 "ReceivableSpecifiedTradeAccountingAccount"],
        .comfort: ["OrderCurrencyCode", "InvoiceeTradeParty", "SpecifiedTradeSettlementPaymentMeans",
                   "SpecifiedTradeAllowanceCharge", "SpecifiedTradePaymentTerms",
                   "SpecifiedTradeSettlementHeaderMonetarySummation", "ReceivableSpecifiedTradeAccountingAccount"],
        .extended: ["TaxCurrencyCode", "OrderCurrencyCode", "InvoiceCurrencyCode", "InvoicerTradeParty",
                    "InvoiceeTradeParty", "SpecifiedTradeSettlementPaymentMeans", "ApplicableTradeTax",
                    "SpecifiedTradeAllowanceCharge", "SpecifiedLogisticsServiceCharge", "SpecifiedTradePaymentTerms",
                    "SpecifiedTradeSettlementHeaderMonetarySummation", "ReceivableSpecifiedTradeAccountingAccount"],
    ]

    /// LineTradeSettlementType, par profil.
    private let lineSettlementSequence: [OrderXProfile: [String]] = [
        .basic: ["SpecifiedTradeSettlementLineMonetarySummation"],
        .comfort: ["ApplicableTradeTax", "SpecifiedTradeAllowanceCharge",
                   "SpecifiedTradeSettlementLineMonetarySummation", "ReceivableSpecifiedTradeAccountingAccount"],
        .extended: ["ApplicableTradeTax", "SpecifiedTradeAllowanceCharge",
                    "SpecifiedTradeSettlementLineMonetarySummation", "ReceivableSpecifiedTradeAccountingAccount"],
    ]

    /// TradeProductType, par profil (début de séquence : ce que l'app peut émettre).
    private let tradeProductSequence: [OrderXProfile: [String]] = [
        .basic: ["GlobalID", "SellerAssignedID", "BuyerAssignedID", "Name"],
        .comfort: ["GlobalID", "SellerAssignedID", "BuyerAssignedID", "Name", "Description"],
        .extended: ["ID", "GlobalID", "SellerAssignedID", "BuyerAssignedID", "IndustryAssignedID", "ModelID",
                    "Name", "Description"],
    ]

    private let transaction = "SCRDMCCBDACIOMessageStructure/SupplyChainTradeTransaction"

    // MARK: - Outils

    private func makeDate(_ s: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.date(from: s)!
    }

    /// Commande qui remplit tout ce que le générateur sait émettre : références, contacts,
    /// description de ligne, trois taux (dont une exonération motivée).
    private func fullOrder(_ profile: OrderXProfile) -> SalesOrder {
        var lines = [
            InvoiceLine(name: "Licence logicielle", quantity: 2, unit: "C62", unitPrice: 600, vatRate: 20),
            InvoiceLine(name: "Livres", quantity: 3, unit: "C62", unitPrice: 25, vatRate: 5.5),
            InvoiceLine(name: "Formation", quantity: 1, unit: "DAY", unitPrice: 900, vatRate: 0, vatCategory: .exempt,
                        vatExemptionReason: "Exonération, article 261-4-4° du CGI"),
        ]
        lines[0].description = "Licence annuelle, 5 postes"
        var order = SalesOrder(
            number: "CD2026-0042", type: .order, issueDate: makeDate("2026-09-01"),
            requestedDeliveryDate: makeDate("2026-09-15"), currency: "EUR", profile: profile,
            buyer: InvoiceParty(name: "Client Exemple SAS", street: "8 avenue des Champs", postcode: "75008", city: "Paris",
                                vatNumber: "FR98765432109", siren: "987654321", contactName: "Paul Durand",
                                contactEmail: "achats@client.fr", contactPhone: "0605040302",
                                endpointID: "987654321", endpointSchemeID: "0225"),
            seller: InvoiceParty(name: "Mon Entreprise SARL", street: "12 rue du Commerce", postcode: "75001", city: "Paris",
                                 vatNumber: "FR12345678901", siren: "123456789", contactName: "Jeanne Martin",
                                 contactEmail: "contact@exemple.fr", contactPhone: "0102030405",
                                 endpointID: "123456789", endpointSchemeID: "0225"),
            buyerReference: "ACHAT-REF-42", lines: lines, requestedResponseTypeCode: "AC"
        )
        order.quotationRef = "DV2026-0007"
        order.contractRef = "CT-2026-01"
        order.blanketOrderRef = "CA-2026-02"
        order.previousOrderChangeRef = "MOD-01"
        order.previousOrderResponseRef = "REP-01"
        order.notes = "Livraison en matinée"
        return order
    }

    private func document(_ order: SalesOrder) throws -> XMLDocument {
        try XMLDocument(data: OrderCIOXMLGenerator().generate(order: order))
    }

    /// Éléments désignés par un chemin de noms locaux (préfixes ignorés), ex. "A/B/C".
    private func elements(_ doc: XMLDocument, _ path: String) throws -> [XMLElement] {
        let steps = path.split(separator: "/").map { "*[local-name()='\($0)']" }
        return try doc.nodes(forXPath: "/" + steps.joined(separator: "/")).compactMap { $0 as? XMLElement }
    }

    private func childNames(_ element: XMLElement?) -> [String] {
        element?.children?.compactMap { ($0 as? XMLElement)?.localName } ?? []
    }

    /// Chaque enfant doit appartenir à la séquence XSD, dans l'ordre de celle-ci.
    private func assertFollowsSequence(_ names: [String], _ sequence: [String], _ context: String,
                                       file: StaticString = #filePath, line: UInt = #line) {
        let indices = names.map { sequence.firstIndex(of: $0) }
        XCTAssertFalse(indices.contains(nil), "\(context) : élément hors séquence XSD dans \(names)", file: file, line: line)
        let known = indices.compactMap { $0 }
        XCTAssertEqual(known, known.sorted(), "\(context) : ordre contraire au XSD : \(names)", file: file, line: line)
    }

    // MARK: - Structure par profil

    func testEveryProfileFollowsItsXSDSequences() throws {
        for profile in OrderXProfile.allCases {
            let doc = try document(fullOrder(profile))
            let agreement = try elements(doc, transaction + "/ApplicableHeaderTradeAgreement").first
            assertFollowsSequence(childNames(agreement), headerAgreementSequence, "\(profile.rawValue) en-tête (accord)")
            let settlement = try elements(doc, transaction + "/ApplicableHeaderTradeSettlement").first
            assertFollowsSequence(childNames(settlement), headerSettlementSequence[profile]!, "\(profile.rawValue) en-tête (règlement)")
            let items = try elements(doc, transaction + "/IncludedSupplyChainTradeLineItem")
            XCTAssertEqual(items.count, 3)
            for item in items {
                let product = item.elements(forName: "ram:SpecifiedTradeProduct").first
                assertFollowsSequence(childNames(product), tradeProductSequence[profile]!, "\(profile.rawValue) produit")
                let lineSettlement = item.elements(forName: "ram:SpecifiedLineTradeSettlement").first
                assertFollowsSequence(childNames(lineSettlement), lineSettlementSequence[profile]!, "\(profile.rawValue) règlement de ligne")
            }
        }
    }

    /// La commande (BuyerOrderReferencedDocument) précède le devis dans les trois profils :
    /// l'ordre inverse rendait le XML invalide dès qu'un devis était référencé.
    func testOrderReferencePrecedesQuotationReference() throws {
        for profile in OrderXProfile.allCases {
            let names = childNames(try elements(document(fullOrder(profile)), transaction + "/ApplicableHeaderTradeAgreement").first)
            let order = try XCTUnwrap(names.firstIndex(of: "BuyerOrderReferencedDocument"), profile.rawValue)
            let quotation = try XCTUnwrap(names.firstIndex(of: "QuotationReferencedDocument"), profile.rawValue)
            XCTAssertLessThan(order, quotation, profile.rawValue)
        }
    }

    // MARK: - TVA selon le profil

    func testHeaderVATBreakdownIsEmittedInExtendedOnly() throws {
        let path = transaction + "/ApplicableHeaderTradeSettlement/ApplicableTradeTax"
        XCTAssertEqual(try elements(document(fullOrder(.extended)), path).count, 3, "un sous-total par taux et catégorie")
        XCTAssertEqual(try elements(document(fullOrder(.comfort)), path).count, 0)
        XCTAssertEqual(try elements(document(fullOrder(.basic)), path).count, 0)
    }

    func testLineVATAndDescriptionAreDroppedInBasicOnly() throws {
        let tax = transaction + "/IncludedSupplyChainTradeLineItem/SpecifiedLineTradeSettlement/ApplicableTradeTax"
        let description = transaction + "/IncludedSupplyChainTradeLineItem/SpecifiedTradeProduct/Description"
        for profile in [OrderXProfile.comfort, .extended] {
            XCTAssertEqual(try elements(document(fullOrder(profile)), tax).count, 3, profile.rawValue)
            XCTAssertEqual(try elements(document(fullOrder(profile)), description).count, 1, profile.rawValue)
        }
        XCTAssertEqual(try elements(document(fullOrder(.basic)), tax).count, 0)
        XCTAssertEqual(try elements(document(fullOrder(.basic)), description).count, 0)
    }

    /// Sans récapitulatif d'en-tête, le total de TVA reste transmis dans tous les profils.
    func testTaxTotalIsKeptInEveryProfile() throws {
        for profile in OrderXProfile.allCases {
            let order = fullOrder(profile)
            let total = try elements(document(order), transaction + "/ApplicableHeaderTradeSettlement/SpecifiedTradeSettlementHeaderMonetarySummation/TaxTotalAmount").first
            XCTAssertEqual(total?.stringValue, String(format: "%.2f", order.taxTotal), profile.rawValue)
        }
    }
}
