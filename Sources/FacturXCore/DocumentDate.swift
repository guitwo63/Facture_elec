import Foundation

/// Jour calendaire des dates de document écrites ou lues dans le XML : date de facture (BT-2),
/// échéance (BT-9), date de la facture antérieure (BT-26), date de livraison, dates Order-X, et
/// date citée dans les métadonnées XMP du PDF.
///
/// Le jour est pris dans le **fuseau de l'application** (`NSTimeZone.default`, le fuseau du Mac
/// tant que l'app n'en impose pas un autre). C'est celui du sélecteur de date de l'éditeur, du
/// PDF (`DateFormatter()` sans fuseau explicite) et du calcul des échéances (`Calendar.current`
/// dans `PaymentTermsDueRule`). Le XML porte donc toujours le jour affiché et imprimé, quelle
/// que soit l'heure enregistrée avec la date : échéance « fin de mois » calculée à 00:00,
/// facture créée à 00:30… Les dates étaient auparavant écrites en UTC : à Paris, un instant
/// entre 00:00 et 01:00 (02:00 en été) s'écrivait la veille dans le XML.
enum DocumentDate {
    /// Relu à chaque appel, pour suivre un changement de fuseau (et le fuseau fixé par les tests).
    private static var appCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = NSTimeZone.default
        return calendar
    }

    /// Format 102 de la syntaxe CII (AAAAMMJJ), par exemple "20260930".
    static func xmlString(_ date: Date) -> String {
        let c = appCalendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04ld%02ld%02ld", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Le même jour au format ISO 8601 (AAAA-MM-JJ) des métadonnées XMP, par exemple "2026-09-30".
    static func isoString(_ date: Date) -> String {
        let c = appCalendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04ld-%02ld-%02ld", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Lit une date au format 102 et la place à midi de ce jour, dans le fuseau de l'application.
    /// Midi plutôt que minuit : le jour affiché reste le même si le fuseau du Mac change ensuite
    /// (jusqu'à ±11 h). Midi existe aussi tous les jours, alors que minuit est sauté certains
    /// jours de changement d'heure dans quelques fuseaux. `nil` si la chaîne n'est pas une date
    /// AAAAMMJJ valide : "20260231" est refusé, pas reporté au 3 mars.
    static func date(xmlString: String) -> Date? {
        guard xmlString.count == 8, xmlString.allSatisfy({ $0.isASCII && $0.isNumber }),
              let year = Int(xmlString.prefix(4)),
              let month = Int(xmlString.dropFirst(4).prefix(2)),
              let day = Int(xmlString.suffix(2))
        else { return nil }
        let calendar = appCalendar
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) else { return nil }
        let read = calendar.dateComponents([.year, .month, .day], from: date)
        guard read.year == year, read.month == month, read.day == day else { return nil }
        return date
    }
}
