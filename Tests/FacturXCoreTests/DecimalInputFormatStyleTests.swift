import XCTest
@testable import FacturXCore

/// Saisie des champs décimaux (quantité, prix unitaire, montant déjà payé, taux de TVA « Autre… »).
/// Avec le format `.number` standard en français, un point était lu en silence comme la fin du
/// nombre ou comme un séparateur de milliers : « 12.5 » donnait 12, « 12.50 » 1250 (constaté le
/// 2026-09-24 sur une réplique hors écran d'un champ de l'app, en locale fr_FR).
final class DecimalInputFormatStyleTests: XCTestCase {
    private let french = Locale(identifier: "fr_FR")

    private func read(_ text: String) -> Double? {
        DecimalInputParseStrategy.number(text)
    }

    // MARK: - Lecture

    func testReadsACommaOrADotAsTheDecimalSeparator() {
        XCTAssertEqual(read("12,5"), 12.5)
        XCTAssertEqual(read("12.5"), 12.5, "lu 12 par .number")
        XCTAssertEqual(read("1.5"), 1.5, "lu 1 par .number")
        XCTAssertEqual(read("0.5"), 0.5, "lu 0 par .number")
        XCTAssertEqual(read("12.50"), 12.5, "lu 1250 par .number")
        XCTAssertEqual(read("12.500"), 12.5, "un seul séparateur est décimal, même suivi de 3 chiffres")
        XCTAssertEqual(read(",5"), 0.5)
        XCTAssertEqual(read("5,"), 5)
        XCTAssertEqual(read("-5,25"), -5.25)
        XCTAssertEqual(read("\u{2212}5,25"), -5.25, "signe moins typographique")
        XCTAssertEqual(read("+5"), 5)
        XCTAssertEqual(read("007"), 7)
    }

    /// Ambiguïté assumée : un seul séparateur suivi de 3 chiffres est décimal, à la française pour
    /// la virgule comme à l'anglaise pour le point. Un français écrit 1234 « 1 234 », pas « 1.234 ».
    func testASingleSeparatorFollowedByThreeDigitsIsDecimal() {
        XCTAssertEqual(read("1,234"), 1.234)
        XCTAssertEqual(read("1.234"), 1.234)
    }

    func testReadsThousandsSeparators() {
        XCTAssertEqual(read("1 234,5"), 1234.5)
        XCTAssertEqual(read("1\u{00A0}234,5"), 1234.5, "espace insécable")
        XCTAssertEqual(read("1\u{202F}234,5"), 1234.5, "espace fine insécable, séparateur de milliers du format français")
        XCTAssertEqual(read("1\u{2009}234,5"), 1234.5, "espace fine")
        XCTAssertEqual(read("1'234.5"), 1234.5)
        XCTAssertEqual(read("1’234,5"), 1234.5)
        XCTAssertEqual(read("1 234.5"), 1234.5)
        XCTAssertEqual(read("18.123,45"), 18123.45)
        XCTAssertEqual(read("18,123.45"), 18123.45, "lu 18,123 par .number")
        XCTAssertEqual(read("1.234.567"), 1234567)
        XCTAssertEqual(read("1,234,567"), 1234567)
        XCTAssertEqual(read("1 234 567,89"), 1234567.89)
        XCTAssertEqual(read("1.234.567,89"), 1234567.89)
        XCTAssertEqual(read("1,234,567.89"), 1234567.89)
    }

    /// Des milliers séparés vont par 3 chiffres : une faute de frappe est refusée (le champ garde
    /// sa valeur) plutôt que lue comme un autre nombre.
    func testRejectsMalformedThousandsGroupsInsteadOfGuessing() {
        for text in ["12..5", "12 5", "1,2.5", "12.5,3", "12.345.67", "1234 567", "1  234", "1,23,456.78", "1.234.5", "1 234,5 6"] {
            XCTAssertNil(read(text), text)
        }
    }

    func testIgnoresACurrencySymbolOrPercentAtEitherEnd() {
        XCTAssertEqual(read("12,50 €"), 12.5, "copié d'une cellule de tableur au format monétaire")
        XCTAssertEqual(read("12.50€"), 12.5)
        XCTAssertEqual(read("€12.50"), 12.5)
        XCTAssertEqual(read("$1,234.56"), 1234.56)
        XCTAssertEqual(read("-12,50 €"), -12.5)
        XCTAssertEqual(read("8,5 %"), 8.5)
        XCTAssertNil(read("12,50 EUR"), "des lettres ne sont pas un symbole")
        XCTAssertNil(read("12€50"), "un symbole au milieu n'est pas ignoré")
        XCTAssertNil(read("12 €€"))
    }

    func testTrimsSurroundingWhitespaceAndNewlines() {
        XCTAssertEqual(read(" 163,25 "), 163.25)
        XCTAssertEqual(read("12,5\n"), 12.5, "cellule de tableur copiée, suivie d'un retour à la ligne")
        XCTAssertEqual(read("\t12.5"), 12.5)
    }

    func testRejectsTextThatIsNotAFiniteNumber() {
        let invalid = ["", "   ", "abc", "12,5abc", "1e3", "inf", "nan", "0x10", "--5", "5-", "1,2.3,4",
                       "12,5\t3", "12,5\n3", ",", ".", "-", "€", "１２", "1e999"]
        for text in invalid {
            XCTAssertNil(read(text), text.debugDescription)
        }
    }

    /// L'API de `ParseStrategy` qu'appelle le TextField : lève une erreur sur un texte illisible,
    /// et le champ garde alors sa valeur.
    func testParseThrowsOnUnreadableText() throws {
        let strategy = DecimalInputParseStrategy()
        XCTAssertEqual(try strategy.parse("12.5"), 12.5)
        XCTAssertThrowsError(try strategy.parse("abc"))
        XCTAssertThrowsError(try strategy.parse(""))
    }

    /// Les cas du champ du taux de change (PR #153, `ExchangeRateParseStrategy`), que ce format a
    /// vocation à remplacer, sont lus pareil.
    func testReadsTheExchangeRateEntryCasesTheSameWay() {
        XCTAssertEqual(read("1,1464"), 1.1464)
        XCTAssertEqual(read("1.1464"), 1.1464)
        XCTAssertEqual(read(" 163,25 "), 163.25)
        XCTAssertEqual(read("18 123,45"), 18123.45)
        XCTAssertEqual(read("18\u{202F}123,45"), 18123.45)
        XCTAssertEqual(read("18.123,45"), 18123.45)
        XCTAssertEqual(read("18,123.45"), 18123.45)
        XCTAssertEqual(read("1.234.567"), 1234567)
        for text in ["abc", "1,2.3,4", "nan", "inf", ""] {
            XCTAssertNil(read(text), text)
        }
    }

    // MARK: - Affichage

    func testShowsTheValueInTheAppLanguageWithoutThousandsSeparator() {
        let style = DecimalInputFormatStyle(locale: french)
        XCTAssertEqual(style.format(12.5), "12,5")
        XCTAssertEqual(style.format(1234.5), "1234,5")
        XCTAssertEqual(style.format(12.3456789), "12,345679", "6 décimales au plus, comme .number")
        XCTAssertEqual(style.format(100), "100")
        XCTAssertEqual(style.format(-5.25), "-5,25")
        XCTAssertEqual(DecimalInputFormatStyle(locale: Locale(identifier: "en_US")).format(1234.5), "1234.5")
        XCTAssertEqual(DecimalInputFormatStyle(maximumFractionDigits: 2, locale: french).format(12.3456), "12,35")
        XCTAssertEqual(DecimalInputFormatStyle(maximumFractionDigits: 2).locale(french).format(12.3456), "12,35",
                       "la locale de l'environnement (SwiftUI) garde le nombre de décimales")
        XCTAssertEqual(DecimalInputFormatStyle.decimalInput.maximumFractionDigits, 6)
    }

    /// Le champ réécrit la valeur telle qu'il l'affiche dès qu'on y entre puis qu'on en sort (vu
    /// sur la réplique hors écran, avec .number comme avec ce format) : une valeur enregistrée doit
    /// donc ressortir exactement comme avec .number, sans arrondi nouveau.
    func testStoredValuesComeBackAsWithTheStandardNumberFormat() throws {
        let style = DecimalInputFormatStyle(locale: french)
        let standard = FloatingPointFormatStyle<Double>.number.locale(french)
        var values: [Double] = [0, 0.1 + 0.2, 1.0 / 3, 2.0 / 3, 12.3456785, 1234567.891, 99999.9999995, 1e-7,
                                123456789.123456789, 5.5, 2.1, 0.05, 19.99, 1e15 + 0.3, -0.004, -1234.5]
        var seed: UInt64 = 20260924
        for _ in 0..<2000 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let mantissa = Double(seed >> 11) / Double(1 << 53)
            let exponent = Int((seed >> 3) % 16) - 6
            values.append((mantissa * pow(10, Double(exponent)) * ((seed & 1) == 0 ? 1 : -1)))
        }
        for value in values {
            let before = try standard.parseStrategy.parse(standard.format(value))
            XCTAssertEqual(read(style.format(value)), before, "\(value) : « \(style.format(value)) » / « \(standard.format(value)) »")
        }
    }

    // MARK: - Champs de l'app

    /// Aucun champ de l'app ne relit une saisie avec `.number` (`TextField(…, value:, format: .number)`),
    /// sauf les ports SMTP, des entiers (Int) sans décimale à lire.
    func testNoFieldOfTheAppReadsItsEntryWithTheStandardNumberFormat() throws {
        let appDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/FacturXMacApp")
        let files = (FileManager.default.enumerator(at: appDir, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty, "aucun source trouvé dans \(appDir.path)")
        let standardFormat = try NSRegularExpression(pattern: #"value:.*format:\s*\.number"#)
        var offenders: [String] = []
        var integerFields = 0
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
            for (index, line) in lines.enumerated()
            where standardFormat.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                if line.contains(".port, format: .number") {
                    integerFields += 1
                } else {
                    offenders.append("\(file.lastPathComponent):\(index + 1) : \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        XCTAssertEqual(offenders, [], "format: .decimalInput pour un champ décimal")
        XCTAssertGreaterThan(integerFields, 0, "l'expression doit reconnaître les champs du port SMTP")
    }
}
