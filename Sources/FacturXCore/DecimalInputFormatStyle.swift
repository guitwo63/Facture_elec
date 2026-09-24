import Foundation

/// Saisie d'un nombre décimal (quantité, prix unitaire, montant, taux de TVA ou de change) :
/// affiché selon les réglages régionaux du Mac comme avec `.number` (« 12,5 » en français), mais
/// sans séparateur de milliers, et relu avec la virgule comme avec le point décimal.
///
/// Le format numérique standard (`.number`) relit en français un point comme la fin du nombre ou
/// comme un séparateur de milliers, sans aucune erreur : « 12.5 » donnait 12, « 0.5 » 0, « 12.50 »
/// 1250 et « 1,234.56 » 1,234 (constaté le 2026-09-24 sur une réplique hors écran d'un champ de
/// l'app, en locale fr_FR). Une valeur collée depuis un tableur ou un site anglophone était donc
/// faussée en silence.
public struct DecimalInputFormatStyle: ParseableFormatStyle {
    /// Décimales affichées au plus. Par défaut 6, comme le format `.number` : le champ réécrit la
    /// valeur telle qu'il l'affiche dès qu'on y entre puis qu'on en sort, une valeur enregistrée
    /// n'est donc pas arrondie autrement qu'avant.
    public var maximumFractionDigits: Int
    public var locale: Locale

    public init(maximumFractionDigits: Int = 6, locale: Locale = .autoupdatingCurrent) {
        self.maximumFractionDigits = max(0, maximumFractionDigits)
        self.locale = locale
    }

    public var parseStrategy: DecimalInputParseStrategy { DecimalInputParseStrategy() }

    public func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...maximumFractionDigits)).grouping(.never).locale(locale))
    }

    public func locale(_ locale: Locale) -> DecimalInputFormatStyle {
        DecimalInputFormatStyle(maximumFractionDigits: maximumFractionDigits, locale: locale)
    }
}

public extension FormatStyle where Self == DecimalInputFormatStyle {
    /// `TextField(…, value: $double, format: .decimalInput)` : virgule ou point décimal, 6 décimales
    /// au plus. À utiliser à la place de `.number` pour tout champ décimal.
    static var decimalInput: DecimalInputFormatStyle { DecimalInputFormatStyle() }
}

public struct DecimalInputParseStrategy: ParseStrategy {
    public init() {}

    public func parse(_ value: String) throws -> Double {
        guard let number = Self.number(value) else {
            throw CocoaError(.formatting, userInfo: [NSDebugDescriptionErrorKey: "Nombre illisible : « \(value) »"])
        }
        return number
    }

    /// Lit « 12,5 », « 12.5 », « 1 234,5 », « 1.234,5 » ou « 1,234.5 » :
    /// - de la virgule et du point, le dernier est décimal et l'autre sépare les milliers ;
    /// - seul et présent une fois, l'un ou l'autre est décimal ; répété (« 1.234.567 »), il sépare
    ///   les milliers ;
    /// - les espaces, dont l'espace fine insécable U+202F du format français, et les apostrophes
    ///   (« 1'234.5 ») séparent aussi les milliers ;
    /// - des milliers séparés vont par 3 chiffres : « 12..5 », « 12 5 » ou « 1,2.5 » sont refusés
    ///   plutôt que lus 125 ;
    /// - un symbole monétaire ou « % » en tête ou en fin est ignoré (« 12,50 € », « $12.50 »),
    ///   comme le faisait `.number` ; le signe moins typographique U+2212 vaut « - ».
    ///
    /// Un seul séparateur suivi de 3 chiffres reste ambigu : « 1,234 » est lu 1,234 à la française,
    /// et « 1.234 » 1,234 à l'anglaise. nil pour tout autre texte (vide, lettres, exposant,
    /// tabulation entre deux nombres collés…) et pour un nombre non fini.
    public static func number(_ text: String) -> Double? {
        var body = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        if let first = body.first, isSymbol(first) { body = body.dropFirst() }
        if let last = body.last, isSymbol(last) { body = body.dropLast() }
        body = trimmed(body)
        var sign = ""
        if let first = body.first, first == "-" || first == "+" || first == "\u{2212}" {
            sign = first == "+" ? "" : "-"
            body = trimmed(body.dropFirst())
        }

        let commas = body.filter { $0 == "," }.count
        let dots = body.filter { $0 == "." }.count
        let decimal: Character?
        if commas > 0 && dots > 0 {
            decimal = body.lastIndex(of: ",")! > body.lastIndex(of: ".")! ? "," : "."
        } else if commas + dots == 1 {
            decimal = commas == 1 ? "," : "."
        } else {
            decimal = nil
        }

        var integerPart = body
        var fractionPart: Substring = ""
        if let decimal {
            let parts = body.split(separator: decimal, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            integerPart = parts[0]
            fractionPart = parts[1]
        }
        guard fractionPart.allSatisfy(isDigit) else { return nil }

        let groups = integerPart.split(omittingEmptySubsequences: false) { char in
            char == "," || char == "." || char == "'" || char == "’" || isSpace(char)
        }
        guard groups.allSatisfy({ $0.allSatisfy(isDigit) }) else { return nil }
        if groups.count > 1 {
            guard (1...3).contains(groups[0].count), groups.dropFirst().allSatisfy({ $0.count == 3 }) else { return nil }
        }
        let integerDigits = groups.joined()
        guard !integerDigits.isEmpty || !fractionPart.isEmpty else { return nil }

        let normalized = sign + (integerDigits.isEmpty ? "0" : integerDigits) + (fractionPart.isEmpty ? "" : "." + fractionPart)
        guard let value = Double(normalized), value.isFinite else { return nil }
        return value
    }

    private static func isDigit(_ char: Character) -> Bool {
        char.isASCII && char.isWholeNumber
    }

    /// Espace simple, insécable (U+00A0), fine insécable (U+202F), fine (U+2009)… : catégorie
    /// Unicode Zs. Une tabulation ou un retour à la ligne n'en est pas.
    private static func isSpace(_ char: Character) -> Bool {
        char.unicodeScalars.count == 1 && char.unicodeScalars.first!.properties.generalCategory == .spaceSeparator
    }

    private static func isSymbol(_ char: Character) -> Bool {
        char == "%" || (char.unicodeScalars.count == 1 && char.unicodeScalars.first!.properties.generalCategory == .currencySymbol)
    }

    private static func trimmed(_ text: Substring) -> Substring {
        var text = text
        while let first = text.first, isSpace(first) { text = text.dropFirst() }
        while let last = text.last, isSpace(last) { text = text.dropLast() }
        return text
    }
}
