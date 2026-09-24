import Foundation

// Sommes de factures sans mélange de devises : le tableau de bord additionnait toutes les factures
// et affichait le total avec la devise de la première, si bien qu'une facture en dollars gonflait
// un total en euros (constat du 2026-09-24, factures hors euro émissibles avec la PR #153). Aucune
// conversion : chaque montant reste dans la devise de ses factures (décision de Guillaume, un total
// par devise plutôt qu'un total converti en euros).

/// Montant dans une devise (BT-5).
public struct CurrencyAmount: Equatable, Hashable, Identifiable {
    /// Code normalisé par `CurrencyTotals.code(_:)` ; "" pour des factures sans devise (BR-05).
    public let currency: String
    public let amount: Double
    public var id: String { currency }

    public init(currency: String, amount: Double) {
        self.currency = currency
        self.amount = amount
    }
}

/// Montant dû par un client dans une devise : un client facturé en euros et en dollars a deux
/// soldes.
public struct ClientBalance: Equatable, Identifiable {
    public let name: String
    public let currency: String
    /// Total TTC des factures non payées, avoirs déduits.
    public let outstanding: Double
    /// Part de `outstanding` échue (`Invoice.isOverdue`).
    public let overdue: Double
    public var id: [String] { [currency, name] }

    public init(name: String, currency: String, outstanding: Double, overdue: Double) {
        self.name = name
        self.currency = currency
        self.outstanding = outstanding
        self.overdue = overdue
    }
}

public enum CurrencyTotals {
    /// Devise d'un total vide (aucune facture à additionner) : celle de la comptabilité.
    public static let defaultCurrency = "EUR"

    /// Nom affiché pour un client sans nom.
    public static let unnamedClient = "Client sans nom"

    /// Code servant à regrouper : sans espaces autour et en majuscules, « eur » et « EUR » étant la
    /// même devise. "" pour une facture sans devise.
    public static func code(_ currency: String) -> String {
        currency.trimmingCharacters(in: .whitespaces).uppercased()
    }

    public static func sameCurrency(_ lhs: String, _ rhs: String) -> Bool {
        code(lhs) == code(rhs)
    }

    /// Ordre d'affichage des devises : l'euro d'abord, puis les autres par ordre alphabétique, et
    /// les factures sans devise en dernier.
    static func precedes(_ lhs: String, _ rhs: String) -> Bool {
        func rank(_ code: String) -> Int {
            code == defaultCurrency ? 0 : (code.isEmpty ? 2 : 1)
        }
        return (rank(lhs), lhs) < (rank(rhs), rhs)
    }

    /// Total TTC (BT-112) compté en négatif pour un avoir, interne ou non.
    public static func signedAmount(_ invoice: Invoice) -> Double {
        invoice.type.isCreditNote ? -invoice.grandTotal : invoice.grandTotal
    }

    /// Somme des `signedAmount` par devise : une entrée par devise présente, dans l'ordre
    /// d'affichage, y compris pour un total nul (une facture et son avoir). Vide sans facture.
    public static func byCurrency(_ invoices: [Invoice]) -> [CurrencyAmount] {
        var sums: [String: Double] = [:]
        for invoice in invoices {
            sums[code(invoice.currency), default: 0] += signedAmount(invoice)
        }
        return sums.keys.sorted(by: precedes).map { CurrencyAmount(currency: $0, amount: cents(sums[$0]!)) }
    }

    /// Somme des `signedAmount` des seules factures en `currency`, les autres étant ignorées.
    public static func total(_ invoices: [Invoice], in currency: String) -> Double {
        cents(invoices.filter { sameCurrency($0.currency, currency) }.reduce(0) { $0 + signedAmount($1) })
    }

    /// Soldes par client et par devise des factures données, que l'appelant a restreintes aux
    /// factures non payées : devises dans l'ordre d'affichage, puis montant dû décroissant, puis
    /// nom. Le client est reconnu à son nom (BT-44).
    public static func clientBalances(_ invoices: [Invoice]) -> [ClientBalance] {
        struct Key: Hashable { let name: String; let currency: String }
        var sums: [Key: (outstanding: Double, overdue: Double)] = [:]
        for invoice in invoices {
            let name = invoice.buyer.name.trimmingCharacters(in: .whitespaces).isEmpty ? unnamedClient : invoice.buyer.name
            let key = Key(name: name, currency: code(invoice.currency))
            let amount = signedAmount(invoice)
            sums[key, default: (0, 0)].outstanding += amount
            if invoice.isOverdue { sums[key, default: (0, 0)].overdue += amount }
        }
        return sums.map { key, sum in
            ClientBalance(name: key.name, currency: key.currency, outstanding: cents(sum.outstanding), overdue: cents(sum.overdue))
        }
        .sorted { lhs, rhs in
            if lhs.currency != rhs.currency { return precedes(lhs.currency, rhs.currency) }
            if lhs.outstanding != rhs.outstanding { return lhs.outstanding > rhs.outstanding }
            return lhs.name < rhs.name
        }
    }

    /// Arrondi au centime, sans « -0.00 » : 0,30 - 0,10 - 0,20 donne -2,8e-17 en `Double`.
    private static func cents(_ value: Double) -> Double {
        let rounded = value.rounded(toPlaces: 2)
        return rounded == 0 ? 0 : rounded
    }
}
