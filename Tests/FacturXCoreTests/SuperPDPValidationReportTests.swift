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
    /// d'avertissements) dont le nom contient "WARNING".
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
        XCTAssertEqual(Array(report.errors.prefix(2)).map { String($0.prefix(9)) }, ["[BR-Z-09]", "[BR-Z-05]"],
                       "les deux échecs du validateur EN16931 doivent être récupérés, dans l'ordre du rapport")
    }

    /// Rapport non conforme : ce que liste le validateur WARNING en est aussi une cause (un seul
    /// avertissement suffit à is_valid=false, vérifié le 2026-09-23). Il compte donc comme erreur,
    /// après ceux des validateurs précédents : le panneau ne peut plus annoncer « non conforme —
    /// 0 erreur(s) ».
    func testWarningValidatorEntriesCountAsErrorsWhenReportIsInvalid() throws {
        let report = try SuperPDPService().parseValidationReport(data: Data(realisticJSON.utf8))
        XCTAssertEqual(report.errors.count, 3)
        XCTAssertEqual(report.errors.last, "[BR-FR-WARN-1]-Some non-blocking recommendation.")
        XCTAssertTrue(report.warnings.isEmpty)
    }

    /// Sur un rapport conforme (jamais vu avec un message : un seul suffit à is_valid=false), ce
    /// que liste le validateur WARNING reste un avertissement, avec son libellé de ligne.
    func testValidReportKeepsWarningValidatorEntriesAsWarnings() throws {
        let json = """
        {"data": [{"is_valid": true, "subreports": [
          {"validator": "FNFE_RFE_INVOICE/Factur-X/EN16931/2xslt/FACTUR-X_EN16931.xslt", "checks_count": 103,
           "failures": [], "messages": []},
          {"validator": "FNFE_RFE_INVOICE/Factur-X/EN16931/2xslt/BR-FR-Flux2-Schematron-CII_WARNING.xslt", "checks_count": 69,
           "failures": [],
           "messages": [{"message": "[BR-FR-WARN-1]-Some non-blocking recommendation.", "raw": "svrl:failed-assert BR-FR-WARN-1",
                         "location": "/*:CrossIndustryInvoice[1]/*:SupplyChainTradeTransaction[1]/*:IncludedSupplyChainTradeLineItem[3]/*:SpecifiedTradeProduct[1]"}]}
        ]}]}
        """
        var report = try SuperPDPService().parseValidationReport(data: Data(json.utf8))
        report.lineNames = ["Prestation A", "Prestation B", "Prestation C"]
        XCTAssertTrue(report.isValid)
        XCTAssertTrue(report.errors.isEmpty)
        XCTAssertEqual(report.warningEntries.map(report.displayText(for:)), ["Ligne 3 (Prestation C) — [BR-FR-WARN-1]-Some non-blocking recommendation."])
    }

    /// Vraie réponse (2026-09-23) pour une facture fictive générée par l'app, mention PMT vidée,
    /// recopiée telle quelle. BR-FR-05 y est un `flag="warning"` du validateur « …_WARNING.xslt »,
    /// sous `messages`, et suffit à is_valid=false. Le panneau affichait « non conforme —
    /// 0 erreur(s) » avec BR-FR-05 sous « Avertissements » ; il compte maintenant une erreur.
    private let realBRFR05ReportJSON = #"""
    {
      "data": [
        {
          "file_name": "invoice.xml",
          "file_size": 43125,
          "is_valid": false,
          "duration": 90,
          "format": "factur-x",
          "conformance_level": "urn:cen.eu:en16931:2017",
          "subreports": [
            {
              "validator": "FNFE_RFE_INVOICE/Factur-X/EN16931/1xsd/Factur-X_EN16931.xsd",
              "checks_count": 1,
              "messages": [],
              "failures": []
            },
            {
              "validator": "FNFE_RFE_INVOICE/Factur-X/EN16931/2xslt/FACTUR-X_EN16931.xslt",
              "checks_count": 101,
              "messages": [],
              "failures": []
            },
            {
              "validator": "FNFE_RFE_INVOICE/Factur-X/EN16931/2xslt/BR-FR-Flux2-Schematron-CII_WARNING.xslt",
              "checks_count": 69,
              "messages": [
                {
                  "message": "BR-FR-05/BT-22 : La mention relative aux frais de recouvrement (code PMT) est absente. Elle est obligatoire dans les notes (BG-1).",
                  "raw": "<svrl:failed-assert test=\"exists($notes[ram:SubjectCode = &apos;PMT&apos;])\" id=\"BR-FR-05_BT-22_PMT\" flag=\"warning\" location=\"/*:CrossIndustryInvoice[namespace-uri()=&apos;urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100&apos;][1]/*:ExchangedDocument[namespace-uri()=&apos;urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100&apos;][1]\">\n    <svrl:text>\n        BR-FR-05/BT-22 : La mention relative aux frais de recouvrement (code PMT) est absente. Elle est obligatoire dans les notes (BG-1).\n      </svrl:text>\n</svrl:failed-assert>",
                  "location": "/*:CrossIndustryInvoice[namespace-uri()='urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100'][1]/*:ExchangedDocument[namespace-uri()='urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100'][1]",
                  "rule": "BR-FR-05_BT-22_PMT"
                }
              ],
              "failures": []
            }
          ]
        }
      ]
    }
    """#

    func testRealBRFR05ReportCountsAsOneError() throws {
        let report = try SuperPDPService().parseValidationReport(data: Data(realBRFR05ReportJSON.utf8))
        XCTAssertFalse(report.isValid)
        XCTAssertEqual(report.errors, ["BR-FR-05/BT-22 : La mention relative aux frais de recouvrement (code PMT) est absente. Elle est obligatoire dans les notes (BG-1)."],
                       "« non conforme — 1 erreur(s) », plus « 0 erreur(s) »")
        XCTAssertTrue(report.warnings.isEmpty)
        XCTAssertEqual(report.errorEntries.map(report.displayText(for:)), report.errors, "échec d'en-tête (ExchangedDocument) : pas de « Ligne n »")
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
        XCTAssertEqual(report.errors.count, 4, "un message par ligne fautive, même si le texte est identique (rapport non conforme : ceux du validateur WARNING compris)")
        XCTAssertEqual(Set(report.errors).count, 2, "quatre erreurs pour deux textes : le texte ne peut pas servir d'identité")
        XCTAssertTrue(report.warnings.isEmpty)
    }

    // MARK: - Ligne en cause (`location`)

    /// Vraie réponse de POST /v1.beta/validation_reports (2026-09-23) pour une facture fictive
    /// générée par l'app, lignes 2 et 3 en catégorie Z à 20 %. Recopiée telle quelle, sauf `raw`
    /// (le fragment SVRL complet) abrégé. `location` est le chemin SVRL du XSLT officiel, et
    /// `rule` un champ absent de l'OpenAPI (1.34.0.beta), ignoré.
    private let realReportJSON = """
    {
      "data": [
        {
          "file_name": "invoice.xml",
          "file_size": 45673,
          "is_valid": false,
          "duration": 69,
          "format": "factur-x",
          "conformance_level": "urn:cen.eu:en16931:2017",
          "subreports": [
            {
              "validator": "FNFE_RFE_INVOICE/Factur-X/EN16931/1xsd/Factur-X_EN16931.xsd",
              "checks_count": 1,
              "messages": [],
              "failures": []
            },
            {
              "validator": "FNFE_RFE_INVOICE/Factur-X/EN16931/2xslt/FACTUR-X_EN16931.xslt",
              "checks_count": 130,
              "messages": [],
              "failures": [
                {
                  "message": "[BR-Z-09]-The VAT category tax amount (BT-117) in a VAT breakdown (BG-23) where VAT category code (BT-118) is \\"Zero rated\\" shall equal 0 (zero).",
                  "raw": "svrl:failed-assert BR-Z-09",
                  "location": "/*:CrossIndustryInvoice[namespace-uri()='urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100'][1]/*:SupplyChainTradeTransaction[namespace-uri()='urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100'][1]/*:ApplicableHeaderTradeSettlement[namespace-uri()='urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100'][1]/*:ApplicableTradeTax[namespace-uri()='urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100'][2]/*:CategoryCode[namespace-uri()='urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100'][1]",
                  "rule": "BR-Z-09"
                },
                {
                  "message": "[BR-Z-05]-In an Invoice line (BG-25) where the Invoiced item VAT category code (BT-151) is \\"Zero rated\\" the Invoiced item VAT rate (BT-152) shall be 0 (zero).",
                  "raw": "svrl:failed-assert BR-Z-05",
                  "location": "/*:CrossIndustryInvoice[namespace-uri()='urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100'][1]/*:SupplyChainTradeTransaction[namespace-uri()='urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100'][1]/*:IncludedSupplyChainTradeLineItem[namespace-uri()='urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100'][2]/*:SpecifiedLineTradeSettlement[namespace-uri()='urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100'][1]/*:ApplicableTradeTax[namespace-uri()='urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100'][1]",
                  "rule": "BR-Z-05"
                },
                {
                  "message": "[BR-Z-05]-In an Invoice line (BG-25) where the Invoiced item VAT category code (BT-151) is \\"Zero rated\\" the Invoiced item VAT rate (BT-152) shall be 0 (zero).",
                  "raw": "svrl:failed-assert BR-Z-05",
                  "location": "/*:CrossIndustryInvoice[namespace-uri()='urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100'][1]/*:SupplyChainTradeTransaction[namespace-uri()='urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100'][1]/*:IncludedSupplyChainTradeLineItem[namespace-uri()='urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100'][3]/*:SpecifiedLineTradeSettlement[namespace-uri()='urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100'][1]/*:ApplicableTradeTax[namespace-uri()='urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100'][1]",
                  "rule": "BR-Z-05"
                }
              ]
            },
            {
              "validator": "FNFE_RFE_INVOICE/Factur-X/EN16931/2xslt/BR-FR-Flux2-Schematron-CII_WARNING.xslt",
              "checks_count": 83,
              "messages": [],
              "failures": []
            }
          ]
        }
      ]
    }
    """

    /// BR-Z-05 échoue sur les lignes 2 et 3 avec le même message : le rang lu dans `location` et
    /// la désignation relevée à la validation les départagent à l'affichage. Le compteur et le
    /// texte brut ne changent pas, et BR-Z-09 (2e sous-total de TVA d'en-tête,
    /// `ApplicableTradeTax[2]`) ne vise aucune ligne.
    func testRealReportLabelsEachFailingLine() throws {
        var report = try SuperPDPService().parseValidationReport(data: Data(realReportJSON.utf8))
        // Les désignations de la facture fictive qui a produit ce rapport.
        report.lineNames = ["Prestation correcte", "Article Z fautif A", "Article Z fautif B"]
        XCTAssertEqual(report.errors.count, 3, "un échec = une erreur, comme avant")
        XCTAssertEqual(report.errorEntries.map(\.lineNumber), [nil, 2, 3])
        let brZ05 = "[BR-Z-05]-In an Invoice line (BG-25) where the Invoiced item VAT category code (BT-151) is \"Zero rated\" the Invoiced item VAT rate (BT-152) shall be 0 (zero)."
        XCTAssertEqual(report.errorEntries.map(report.displayText(for:)), [
            report.errors[0],
            "Ligne 2 (Article Z fautif A) — \(brZ05)",
            "Ligne 3 (Article Z fautif B) — \(brZ05)",
        ])
        XCTAssertEqual(report.errors[1], report.errors[2], "le texte brut reste celui du validateur")
    }

    /// Sans désignation relevée pour ce rang (aucune, rang au-delà, désignation vide), le libellé
    /// garde le rang seul ; une désignation est débarrassée de ses blancs.
    func testLineLabelFallsBackToRankWithoutDesignation() {
        let onLine2 = SuperPDPValidationMessage(message: "[BR-X]-M", location: "/ram:IncludedSupplyChainTradeLineItem[2]")
        let onLine3 = SuperPDPValidationMessage(message: "[BR-X]-M", location: "/ram:IncludedSupplyChainTradeLineItem[3]")
        var report = SuperPDPValidationReport(isValid: false, errorEntries: [onLine2, onLine3])
        XCTAssertEqual(report.displayText(for: onLine2), "Ligne 2 — [BR-X]-M", "aucune désignation relevée")
        report.lineNames = ["Première", "  Deuxième \n"]
        XCTAssertEqual(report.displayText(for: onLine2), "Ligne 2 (Deuxième) — [BR-X]-M")
        XCTAssertEqual(report.displayText(for: onLine3), "Ligne 3 — [BR-X]-M", "rang au-delà des lignes relevées")
        report.lineNames = ["Première", "   "]
        XCTAssertEqual(report.displayText(for: onLine2), "Ligne 2 — [BR-X]-M", "désignation vide")
    }

    /// Le rang est le dernier prédicat numérique de l'étape `IncludedSupplyChainTradeLineItem`,
    /// quel que soit le style de chemin. Une étape d'en-tête indexée, une étape de ligne sans rang
    /// ou un rang nul ne donnent rien.
    func testInvoiceLineNumberFromLocationFormats() {
        func line(_ location: String) -> Int? { SuperPDPValidationMessage.invoiceLineNumber(in: location) }
        let rsm = "[namespace-uri()='urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100']"
        let ram = "[namespace-uri()='urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100']"
        XCTAssertEqual(line("/*:CrossIndustryInvoice\(rsm)[1]/*:SupplyChainTradeTransaction\(rsm)[1]/*:IncludedSupplyChainTradeLineItem\(ram)[12]"), 12,
                       "règle dont le contexte est la ligne elle-même, rang à deux chiffres")
        XCTAssertEqual(line("/rsm:CrossIndustryInvoice[1]/rsm:SupplyChainTradeTransaction[1]/ram:IncludedSupplyChainTradeLineItem[4]/ram:SpecifiedTradeProduct[1]/ram:Name[1]"), 4)
        XCTAssertEqual(line("/Q{urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100}IncludedSupplyChainTradeLineItem[5]/Q{urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100}SpecifiedLineTradeSettlement[1]"), 5)
        XCTAssertEqual(line("/CrossIndustryInvoice/.../IncludedSupplyChainTradeLineItem[2]/.../ApplicableTradeTax[1]"), 2)
        XCTAssertNil(line("/*:CrossIndustryInvoice\(rsm)[1]/*:SupplyChainTradeTransaction\(rsm)[1]/*:ApplicableHeaderTradeSettlement\(ram)[1]/*:ApplicableTradeTax\(ram)[2]"))
        XCTAssertNil(line("/rsm:CrossIndustryInvoice/rsm:SupplyChainTradeTransaction/ram:IncludedSupplyChainTradeLineItem/ram:SpecifiedTradeProduct"),
                     "sans rang explicite, on ne devine pas")
        XCTAssertNil(line("/ram:IncludedSupplyChainTradeLineItem[0]"))
        XCTAssertNil(line("/CrossIndustryInvoice/.../PostcodeCode"))
        XCTAssertNil(line(""))
    }

    /// Les entrées du schematron français (validateur WARNING) reçoivent aussi le libellé de ligne.
    /// Une entrée sans `location` (texte simple, clé absente, erreur générique du rapport) reste
    /// telle quelle.
    func testWarningValidatorEntriesGetLineLabelAndEntriesWithoutLocationStayPlain() throws {
        let json = """
        {"data": [{"is_valid": false, "error": "Fichier illisible", "subreports": [
          {"validator": "FNFE_RFE_INVOICE/Factur-X/EN16931/2xslt/FACTUR-X_EN16931.xslt", "checks_count": 2,
           "failures": ["[BR-1]-Texte seul", {"message": "[BR-2]-Sans location", "raw": "svrl:failed-assert BR-2"}],
           "messages": []},
          {"validator": "FNFE_RFE_INVOICE/Factur-X/EN16931/2xslt/BR-FR-Flux2-Schematron-CII_WARNING.xslt", "checks_count": 74,
           "failures": [{"message": "[BR-FR-WARN-1]-Some non-blocking recommendation.", "raw": "svrl:failed-assert BR-FR-WARN-1",
                         "location": "/*:CrossIndustryInvoice[1]/*:SupplyChainTradeTransaction[1]/*:IncludedSupplyChainTradeLineItem[3]/*:SpecifiedTradeProduct[1]"}],
           "messages": []}
        ]}]}
        """
        var report = try SuperPDPService().parseValidationReport(data: Data(json.utf8))
        report.lineNames = ["Prestation A", "Prestation B", "Prestation C"]
        XCTAssertEqual(report.errorEntries.map(report.displayText(for:)), [
            "[BR-1]-Texte seul",
            "[BR-2]-Sans location",
            "Ligne 3 (Prestation C) — [BR-FR-WARN-1]-Some non-blocking recommendation.",
            "Fichier illisible",
        ], "rapport non conforme : l'entrée du validateur WARNING compte comme erreur")
        XCTAssertTrue(report.warnings.isEmpty)
    }
}
