import Foundation

/// Une facture d'achat = un `Invoice` (modèle Factur-X, entièrement réutilisé — fournisseur
/// en `seller`, notre société en `buyer`) + son propre statut fonctionnel. Un type distinct
/// plutôt qu'un `Invoice` nu est nécessaire car `Invoice.status` est typé sur `InvoiceStatus`
/// (le cycle de vie ventes) — sans rapport avec le workflow de validation achats. Le champ
/// `invoice.status` lui-même reste à sa valeur par défaut et n'est jamais lu côté achats :
/// seul `PurchaseInvoice.status` fait foi.
public struct PurchaseInvoice: Codable, Hashable, Identifiable {
    public var invoice: Invoice
    public var status: PurchaseInvoiceStatus

    public var id: UUID { invoice.id }

    public init(invoice: Invoice, status: PurchaseInvoiceStatus) {
        self.invoice = invoice
        self.status = status
    }
}

/// Pendant d'`InvoiceStore` côté achats. Même forme (ObservableObject, singleton,
/// persistance UserDefaults-JSON via `AppEnvironment.key`, journal d'audit optionnel) mais
/// **sans sous-système de numérotation** : `invoice.number` est celui du fournisseur, reçu
/// tel quel — rien à générer nous-mêmes, contrairement à une facture de vente que nous
/// émettons. C'est la seule vraie asymétrie structurelle avec `InvoiceStore` ; voir
/// `docs/integrations-superpdp.md` pour le détail de la décision de séparer les deux stores
/// plutôt que d'ajouter un drapeau de direction sur `InvoiceStore`.
public final class PurchaseInvoiceStore: ObservableObject {
    public static let shared = PurchaseInvoiceStore()

    @Published public var invoices: [PurchaseInvoice]
    public weak var audit: AuditStore?
    public var actorName: String = "system"

    private let defaults = UserDefaults.standard
    private let env = AppEnvironment.shared
    private var storageKey: String { env.key("facturx.purchaseinvoices.v1") }

    public init() {
        self.invoices = []
        load()
    }

    public func load() {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([PurchaseInvoice].self, from: data) {
            invoices = decoded
        }
    }

    public func save() {
        if let data = try? JSONEncoder().encode(invoices) {
            defaults.set(data, forKey: storageKey)
        }
    }

    public func upsert(_ record: PurchaseInvoice) {
        let isNew = !invoices.contains(where: { $0.id == record.id })
        let previousStatus = invoices.first(where: { $0.id == record.id })?.status
        if let idx = invoices.firstIndex(where: { $0.id == record.id }) {
            invoices[idx] = record
        } else {
            invoices.insert(record, at: 0)
        }
        save()
        if let prev = previousStatus, prev != record.status {
            audit?.recordStatusChange(actor: actorName, objectType: .purchaseInvoice, objectCode: record.invoice.number,
                                      statusFrom: prev.label, statusTo: record.status.label, details: "facture d'achat", companyID: record.invoice.companyID)
        } else {
            audit?.record(actor: actorName, action: isNew ? "purchase_invoice_created" : "purchase_invoice_updated",
                           target: record.invoice.number, details: "facture d'achat",
                           objectType: .purchaseInvoice, objectCode: record.invoice.number, companyID: record.invoice.companyID)
        }
    }

    public func delete(_ record: PurchaseInvoice) {
        invoices.removeAll { $0.id == record.id }
        save()
        audit?.record(actor: actorName, action: "purchase_invoice_deleted", target: record.invoice.number, details: "facture d'achat",
                       objectType: .purchaseInvoice, objectCode: record.invoice.number, companyID: record.invoice.companyID)
    }

    /// Nouvelle saisie manuelle : fournisseur vide (à choisir dans l'annuaire), acheteur =
    /// notre société — réutilise `InvoiceStore.resolveDefaultSeller`/`myCompany`, la même
    /// résolution "qui sommes-nous" déjà utilisée côté ventes, plutôt que de la dupliquer.
    /// `salesStore` est injectable (comme `directory`) pour les tests ; les appelants réels
    /// n'ont jamais besoin de le préciser.
    public func newManualEntry(directory: PartyDirectory? = nil, companyID: UUID? = nil, salesStore: InvoiceStore = .shared) -> PurchaseInvoice {
        let dir = directory ?? PartyDirectory.shared
        let ourCompany = salesStore.resolveDefaultSeller(from: dir) ?? salesStore.myCompany
        let invoice = Invoice(
            number: "",
            seller: InvoiceParty(name: "", street: "", postcode: "", city: ""),
            buyer: ourCompany,
            companyID: companyID,
            lines: [InvoiceLine(name: "", quantity: 1, unitPrice: 0, vatRate: 20)]
        )
        return PurchaseInvoice(invoice: invoice, status: .draft)
    }

    /// Intègre une facture reçue (SUPER PDP ou tout autre import futur) : dédoublonnée par
    /// `superPDPRemoteID`, jamais insérée deux fois si déjà connue (rejouer une
    /// synchronisation ne doit jamais dupliquer un enregistrement).
    @discardableResult
    public func ingest(remoteID: String, parsed: Invoice, companyID: UUID?) -> PurchaseInvoice {
        if let existing = invoices.first(where: { $0.invoice.superPDPRemoteID == remoteID }) {
            return existing
        }
        var invoice = parsed
        invoice.superPDPRemoteID = remoteID
        invoice.companyID = companyID
        let record = PurchaseInvoice(invoice: invoice, status: .received)
        upsert(record)
        return record
    }
}
