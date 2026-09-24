import XCTest
import FacturXCore

/// BR-CL-23 côté app : un code d'unité hors de la liste du Schematron (UN/ECE Rec 20 + Rec 21)
/// bloque l'export d'une facture émise, comme la PDP la rejetterait ; sur une facture reçue, ce
/// n'est qu'un avertissement. Le contrôle porte sur le code tel que le XML l'écrira.
final class UnitCodeRuleTests: XCTestCase {

    private func invoice(units: [String]) -> Invoice {
        Invoice(
            number: "2026-0102",
            seller: InvoiceParty(name: "Mon Entreprise SARL", street: "12 rue du Commerce", postcode: "75001", city: "Paris",
                                 vatNumber: "FR44732829320", siren: "732829320", contactEmail: "contact@exemple.fr",
                                 endpointID: "732829320", endpointSchemeID: "0225"),
            buyer: InvoiceParty(name: "Client Exemple SAS", street: "8 avenue des Champs", postcode: "75008", city: "Paris",
                                siren: "303265045", endpointID: "303265045", endpointSchemeID: "0225"),
            buyerReference: "REF-1",
            lines: units.enumerated().map { InvoiceLine(name: "Article \($0.offset + 1)", quantity: 1, unit: $0.element, unitPrice: 100) },
            paymentIBAN: "FR7630006000011234567890189",
            paymentBIC: "AGRIFRPP",
            paymentTerms: "Paiement à 30 jours"
        )
    }

    private func brCL23(_ invoice: Invoice, context: EN16931RuleContext = .issued) -> [BusinessRuleResult] {
        EN16931BusinessRules.evaluate(invoice: invoice, context: context).filter { $0.ruleId == "BR-CL-23" }
    }

    private func emittedUnitCodes(_ invoice: Invoice) throws -> [String] {
        let doc = try XMLDocument(data: CIIXMLGenerator().generate(invoice: invoice))
        return try doc.nodes(forXPath: "//*[local-name()='BilledQuantity']/@unitCode").compactMap(\.stringValue)
    }

    func testProposedUnitsAndBlankUnitPass() {
        XCTAssertEqual(brCL23(invoice(units: NormRefs.units.map(\.code) + [""])), [])
    }

    /// Ligne en « Pièce (PCE) » saisie avant la correction : l'erreur cite la ligne, le code et
    /// l'unité à choisir à la place.
    func testLegacyCodeIsABlockingErrorNamingTheLineAndItsReplacement() {
        let results = brCL23(invoice(units: ["C62", "PCE"]))
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.severity, .error)
        XCTAssertEqual(results.first?.message,
                       "BR-CL-23 : Ligne 2 — le code d'unité « PCE » (BT-130) n'est pas dans la liste UN/ECE Rec 20 et Rec 21 : la PDP rejetterait la facture ; choisissez « Pièce (H87) », la même unité.")
    }

    func testEveryLegacyCodeNamesItsOwnReplacement() {
        let legacy = ["KTM", "PCE", "PCK", "BX", "ROL"]
        let results = brCL23(invoice(units: legacy))
        XCTAssertEqual(results.count, legacy.count)
        for (idx, code) in legacy.enumerated() {
            let label = NormRefs.units.first { $0.code == NormRefs.legacyUnitReplacements[code] }!.label
            XCTAssertTrue(results.contains { $0.message.contains("Ligne \(idx + 1) — le code d'unité « \(code) »") && $0.message.contains("« \(label) »") },
                          "\(code) → \(label)")
        }
    }

    func testOtherOffListCodeAsksForAUnitOfTheList() {
        let results = brCL23(invoice(units: ["EACH"]))
        XCTAssertEqual(results.map(\.severity), [.error])
        XCTAssertTrue(results.first?.message.hasSuffix("; choisissez une unité de la liste.") ?? false, results.first?.message ?? "")
    }

    func testOffListCodeBlocksTheExport() {
        XCTAssertTrue(FacturXValidator().validate(invoice: invoice(units: ["H87"])).isValid, "référence exportable")
        let result = FacturXValidator().validate(invoice: invoice(units: ["PCE"]))
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.businessRules.contains { $0.ruleId == "BR-CL-23" && $0.severity == .error })
    }

    /// Facture d'achat : le code est celui du fournisseur, rien à corriger de notre côté.
    func testReceivedInvoiceOnlyWarns() {
        let results = brCL23(invoice(units: ["PCE", "EACH"]), context: .received)
        XCTAssertEqual(results.map(\.severity), [.warning, .warning])
        XCTAssertFalse(results.contains { $0.message.contains("PDP") || $0.message.contains("choisissez") })
    }

    /// Le Schematron compare l'attribut tel quel, casse comprise : le contrôle porte sur la même
    /// chaîne que le XML. Espaces autour : retirées à l'émission, donc admises ; minuscules :
    /// émises telles quelles, donc refusées.
    func testCodeIsCheckedAsEmitted() throws {
        let padded = invoice(units: [" H87 "])
        XCTAssertEqual(try emittedUnitCodes(padded), ["H87"])
        XCTAssertEqual(brCL23(padded), [])

        let lowercase = invoice(units: ["h87"])
        XCTAssertEqual(try emittedUnitCodes(lowercase), ["h87"])
        XCTAssertEqual(brCL23(lowercase).map(\.severity), [.error])
    }

    /// `hasAdmittedUnitCode` pilote le liseré du sélecteur d'unité : il doit dire la même chose
    /// que la règle, ligne par ligne.
    func testHasAdmittedUnitCodeAgreesWithTheRule() {
        let units = ["C62", "", " KMT", "PCE", "EACH", "h87", "XRO"]
        let inv = invoice(units: units)
        let flagged = Set(brCL23(inv).compactMap { result in
            (1...units.count).first { result.message.contains("Ligne \($0) —") }
        })
        for (idx, line) in inv.lines.enumerated() {
            XCTAssertEqual(line.hasAdmittedUnitCode, !flagged.contains(idx + 1), "« \(units[idx]) »")
        }
        XCTAssertEqual(flagged, [4, 5, 6])
    }
}
