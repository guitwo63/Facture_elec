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

    /// Régression : vue en conditions réelles (tableau de bord SUPER PDP, dépôt
    /// facture-FA-2026-0011.pdf) sur un rapport is_valid=false dont les 3 échecs visibles au
    /// tableau de bord ("Message (1/3)"…) n'étaient dans aucun cas sous `failures` — la clé
    /// effectivement peuplée pour ce validateur était `messages`, jusque-là toujours vide dans
    /// la réponse de référence et donc jamais lue. L'app affichait "non conforme — 0 erreur(s)",
    /// sans aucun détail, malgré 3 échecs bien réels et consultables sur le tableau de bord.
    func testParsesFailuresFromMessagesFieldWhenFailuresIsEmpty() throws {
        let json = """
        {
          "data": [
            {
              "is_valid": false,
              "subreports": [
                {
                  "validator": "FNFE_RFE_INVOICE/Factur-X/EN16931/2xslt/FACTUR-X_EN16931.xslt",
                  "checks_count": 84,
                  "failures": [],
                  "messages": [
                    {
                      "message": "[PEPPOL-EN16931-R008]-Document MUST not contain empty elements. (still status warning)",
                      "raw": "svrl:failed-assert PEPPOL-EN16931-R008",
                      "location": "/CrossIndustryInvoice/.../PostcodeCode"
                    }
                  ]
                }
              ]
            }
          ]
        }
        """
        let report = try SuperPDPService().parseValidationReport(data: Data(json.utf8))
        XCTAssertFalse(report.isValid)
        XCTAssertEqual(report.errors.count, 1, "le contenu de messages doit être récupéré même quand failures est vide")
        XCTAssertTrue(report.errors.contains { $0.contains("PEPPOL-EN16931-R008") })
    }

    /// Un validateur dont failures ET messages sont tous deux peuplés ne doit pas dupliquer
    /// (comportement pas rencontré en pratique mais gardé prévisible) — chaque entrée compte
    /// une fois par tableau, les deux tableaux sont simplement concaténés.
    func testFailuresAndMessagesAreBothReadWithoutCrashingWhenBothPresent() throws {
        let json = """
        {"data": [{"is_valid": false, "subreports": [
          {"validator": "EN16931.xslt", "checks_count": 2,
           "failures": [{"message": "[BR-1]-A"}],
           "messages": [{"message": "[BR-2]-B"}]}
        ]}]}
        """
        let report = try SuperPDPService().parseValidationReport(data: Data(json.utf8))
        XCTAssertEqual(report.errors.count, 2)
        XCTAssertTrue(report.errors.contains { $0.contains("BR-1") })
        XCTAssertTrue(report.errors.contains { $0.contains("BR-2") })
    }

    /// Une règle Schematron échoue une fois par ligne fautive, avec le même message : seule la
    /// `location` diffère. Le rapport garde un message par échec (le compteur « n erreur(s) »
    /// en dépend), donc deux textes égaux : le panneau SUPER PDP ne peut pas se servir du texte
    /// comme identité de `ForEach` (`id: \.self`), il utilise la position.
    func testSameSchematronMessageOnSeveralLinesIsKeptOncePerFailure() throws {
        let json = """
        {"data": [{"is_valid": false, "subreports": [
          {"validator": "FNFE_RFE_INVOICE/Factur-X/EN16931/2xslt/FACTUR-X_EN16931.xslt", "checks_count": 107,
           "failures": [
             {"message": "[BR-Z-05]-In an Invoice line (BG-25) where the Invoiced item VAT category code (BT-151) is \\"Zero rated\\" the Invoiced item VAT rate (BT-152) shall be 0 (zero).",
              "location": "/CrossIndustryInvoice/.../IncludedSupplyChainTradeLineItem[2]/.../ApplicableTradeTax[1]"},
             {"message": "[BR-Z-05]-In an Invoice line (BG-25) where the Invoiced item VAT category code (BT-151) is \\"Zero rated\\" the Invoiced item VAT rate (BT-152) shall be 0 (zero).",
              "location": "/CrossIndustryInvoice/.../IncludedSupplyChainTradeLineItem[3]/.../ApplicableTradeTax[1]"}
           ],
           "messages": []},
          {"validator": "FNFE_RFE_INVOICE/Factur-X/EN16931/2xslt/BR-FR-Flux2-Schematron-CII_WARNING.xslt", "checks_count": 74,
           "failures": [{"message": "[BR-FR-WARN-1]-Same advice."}, {"message": "[BR-FR-WARN-1]-Same advice."}],
           "messages": []}
        ]}]}
        """
        let report = try SuperPDPService().parseValidationReport(data: Data(json.utf8))
        XCTAssertEqual(report.errors.count, 2, "un message par ligne fautive, même si le texte est identique")
        XCTAssertEqual(Set(report.errors).count, 1, "les deux erreurs ont le même texte : il ne peut pas servir d'identité")
        XCTAssertEqual(report.warnings.count, 2)
        XCTAssertEqual(Set(report.warnings).count, 1)
    }
}
