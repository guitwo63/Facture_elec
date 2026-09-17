import Foundation

/// Les 3 paliers de relance d'une facture échue, du plus conciliant au plus formel.
/// Réutilise les données déjà présentes sur la facture (dueDate, legalNotePMT, legalNotePMD) :
/// aucun nouveau champ n'est nécessaire, seul le déclenchement manquait.
public enum PaymentReminderLevel: String, CaseIterable, Identifiable {
    case friendly
    case formalNotice
    case legalPenalty

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .friendly: return "Rappel amical"
        case .formalNotice: return "Mise en demeure"
        case .legalPenalty: return "Majoration légale"
        }
    }

    public var systemImage: String {
        switch self {
        case .friendly: return "bell"
        case .formalNotice: return "exclamationmark.triangle"
        case .legalPenalty: return "gavel"
        }
    }
}

public struct PaymentReminderEmail {
    public let subject: String
    public let body: String
}

public enum PaymentReminderComposer {

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "dd/MM/yyyy"
        df.locale = Locale(identifier: "fr_FR")
        return df
    }()

    public static func compose(level: PaymentReminderLevel, for invoice: Invoice) -> PaymentReminderEmail {
        let clientName = invoice.buyer.name.trimmingCharacters(in: .whitespaces)
        let civility = clientName.isEmpty ? "Madame, Monsieur" : clientName
        let amount = String(format: "%.2f %@", invoice.netToPay, invoice.currency)
        let dueDateStr = dateFormatter.string(from: invoice.dueDate)
        let days = max(invoice.overdueDays, 0)
        let sellerName = invoice.seller.name.trimmingCharacters(in: .whitespaces)

        switch level {
        case .friendly:
            return PaymentReminderEmail(
                subject: "Rappel — facture \(invoice.number) échue depuis le \(dueDateStr)",
                body: """
                \(civility),

                Nous nous permettons de vous rappeler que la facture n° \(invoice.number), d'un montant de \(amount), \
                arrivait à échéance le \(dueDateStr) (soit \(days) jour(s)) et ne semble pas encore réglée à ce jour.

                Il s'agit probablement d'un simple oubli : nous vous remercions par avance de procéder au règlement \
                dans les meilleurs délais, ou de nous signaler si un paiement est déjà en cours.

                Cordialement,
                \(sellerName)
                """
            )
        case .formalNotice:
            return PaymentReminderEmail(
                subject: "Mise en demeure — facture \(invoice.number) impayée",
                body: """
                \(civility),

                Malgré notre précédent rappel, la facture n° \(invoice.number), d'un montant de \(amount), \
                dont l'échéance était fixée au \(dueDateStr), demeure impayée à ce jour (\(days) jour(s) de retard).

                Nous vous mettons en demeure de régler cette somme dans un délai de 8 jours à compter de la réception \
                de ce courrier. À défaut de règlement dans ce délai, nous nous verrons contraints d'appliquer les \
                pénalités de retard et l'indemnité forfaitaire de recouvrement prévues par la loi et rappelées sur la facture.

                Cordialement,
                \(sellerName)
                """
            )
        case .legalPenalty:
            return PaymentReminderEmail(
                subject: "Majoration légale appliquée — facture \(invoice.number)",
                body: """
                \(civility),

                La facture n° \(invoice.number), d'un montant de \(amount), échue depuis le \(dueDateStr) \
                (\(days) jour(s) de retard), reste impayée malgré nos relances précédentes.

                Conformément à la réglementation en vigueur et aux mentions légales figurant sur la facture, \
                les majorations suivantes s'appliquent désormais de plein droit :

                — \(invoice.legalNotePMD)
                — \(invoice.legalNotePMT)

                Le montant total réclamé intègre désormais ces pénalités, en plus du principal de \(amount). \
                Nous vous invitons à régulariser cette situation sans délai.

                Cordialement,
                \(sellerName)
                """
            )
        }
    }
}
