import XCTest
@testable import FacturXCore

/// `parseValidationReport` cherchait `errors`/`warnings` au premier niveau du JSON, des clés
/// qui n'existent pas dans la vraie réponse de l'API SUPER PDP (confirmé sur sa référence
/// OpenAPI publique : `validation_report.subreports[].failures[].message`). Résultat en
/// conditions réelles : une facture rejetée (is_valid=false, deux erreurs BR-Z-05/BR-Z-09
/// visibles sur le tableau de bord SUPER PDP) s'affichait dans l'app comme "non conforme —
/// 0 erreur(s)", sans qu'aucun détail ne soit récupéré. Ces tests figent le format réel.
final class SuperPDPValidationReportTests: XCTestCase {

    /// Extrait (simplifié) d'une vraie réponse /v1.beta/validation_reports pour une facture
    /// rejetée par le validateur EN16931 officiel, avec le 3e validateur (schematron français
    /// non bloquant) dont le nom contient "WARNING".
    private let realisticJSON = """
    {
      "data": [
        {
          "conformance_level": "urn:cen.eu:en16931:2017",
          "duration": 47,
          "file_name": "facture-2026-0032.pdf",
          "file_size": 12345,
          "format": "urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100",
          "is_valid": false,
          "subreports": [
            {
              "checks_count": 1,
              "validator": "FNFE_RFE_INVOICE/CII/1xsd-CII_D22B_uncoupled/CrossIndustryInvoice_100pD22B.xsd",
              "failures": [],
              "messages": []
            },
            {
              "checks_count": 107,
              "validator": "FNFE_RFE_INVOICE/Factur-X/EN16931/2xslt/FACTUR-X_EN16931.xslt",
              "failures": [
                {
                  "message": "[BR-Z-09]-The VAT category tax amount (BT-117) in a VAT breakdown (BG-23) where VAT category code (BT-118) is \\"Zero rated\\" shall equal 0 (zero).",
                  "raw": "svrl:failed-assert BR-Z-09",
                  "location": "/CrossIndustryInvoice/.../ApplicableTradeTax[2]/CategoryCode[1]"
                },
                {
                  "message": "[BR-Z-05]-In an Invoice line (BG-25) where the Invoiced item VAT category code (BT-151) is \\"Zero rated\\" the Invoiced item VAT rate (BT-152) shall be 0 (zero).",
                  "raw": "svrl:failed-assert BR-Z-05",
                  "location": "/CrossIndustryInvoice/.../IncludedSupplyChainTradeLineItem[2]/.../ApplicableTradeTax[1]"
                }
              ],
              "messages": []
            },
            {
              "checks_count": 74,
              "validator": "FNFE_RFE_INVOICE/Factur-X/EN16931/2xslt/BR-FR-Flux2-Schematron-CII_WARNING.xslt",
              "failures": [
                {
                  "message": "[BR-FR-WARN-1]-Some non-blocking recommendation.",
                  "raw": "svrl:failed-assert BR-FR-WARN-1",
                  "location": "/CrossIndustryInvoice/..."
                }
              ],
              "messages": []
            }
          ]
        }
      ]
    }
    """

    func testParsesFailuresFromSubreportsAsErrors() throws {
        let report = try SuperPDPService().parseValidationReport(data: Data(realisticJSON.utf8))
        XCTAssertFalse(report.isValid)
        XCTAssertEqual(report.errors.count, 2, "les deux échecs du validateur EN16931 (BR-Z-09, BR-Z-05) doivent être récupérés")
        XCTAssertTrue(report.errors.contains { $0.contains("BR-Z-09") })
        XCTAssertTrue(report.errors.contains { $0.contains("BR-Z-05") })
    }

    func testWarningValidatorFailuresGoToWarningsNotErrors() throws {
        let report = try SuperPDPService().parseValidationReport(data: Data(realisticJSON.utf8))
        XCTAssertEqual(report.warnings.count, 1)
        XCTAssertTrue(report.warnings.contains { $0.contains("BR-FR-WARN-1") })
        XCTAssertFalse(report.errors.contains { $0.contains("BR-FR-WARN-1") },
                      "un validateur \"WARNING\" ne doit pas gonfler le compte d'erreurs bloquantes")
    }

    func testValidReportHasNoErrors() throws {
        let validJSON = """
        {"data": [{"is_valid": true, "subreports": [
          {"checks_count": 1, "validator": "xsd", "failures": [], "messages": []},
          {"checks_count": 107, "validator": "EN16931.xslt", "failures": [], "messages": []}
        ]}]}
        """
        let report = try SuperPDPService().parseValidationReport(data: Data(validJSON.utf8))
        XCTAssertTrue(report.isValid)
        XCTAssertTrue(report.errors.isEmpty)
    }

    func testMissingSubreportsDoesNotCrash() throws {
        let minimalJSON = """
        {"data": [{"is_valid": false}]}
        """
        let report = try SuperPDPService().parseValidationReport(data: Data(minimalJSON.utf8))
        XCTAssertFalse(report.isValid)
        XCTAssertTrue(report.errors.isEmpty)
    }
}
