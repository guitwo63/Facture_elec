import Foundation

/// Libellé français d'un code technique d'action du journal d'audit (`AuditLogEntry.action`,
/// ex. "invoice_created"). `id` est le code technique tel qu'émis par `AuditStore.record` —
/// il n'est pas modifiable depuis la table de paramétrage, seul `label` l'est.
public struct AuditActionLabel: Codable, Hashable, Identifiable {
    public var id: String
    public var label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

/// Table de paramétrage des libellés du journal d'audit (Réglages > Tables > Journal) —
/// le journal (`AuditLogView`, accessible à tous les rôles depuis #87) affichait jusque-là
/// les codes techniques bruts (`status_change`, `pdp_deposit_sent`…) dans sa colonne
/// « Action », peu lisibles pour un utilisateur non technique.
public final class AuditActionLabelStore: ObservableObject {
    public static let shared = AuditActionLabelStore()

    @Published public var overrides: [AuditActionLabel]
    /// Surcharge éparse par société (Réglages > Tables) — voir `SocietyScopedCatalog`.
    @Published public var overridesBySociety: [UUID: [AuditActionLabel]] = [:]

    private let defaults = UserDefaults.standard
    private let env = AppEnvironment.shared
    private var storageKey: String { env.key("facturx.auditactionlabels.v1") }
    private var overridesBySocietyKey: String { env.key("facturx.auditactionlabels.bysociety.v1") }

    public static let defaultLabels: [AuditActionLabel] = [
        AuditActionLabel(id: "status_change", label: "Changement de statut"),
        AuditActionLabel(id: "invoice_created", label: "Facture créée"),
        AuditActionLabel(id: "invoice_updated", label: "Facture modifiée"),
        AuditActionLabel(id: "invoice_deleted", label: "Facture supprimée"),
        AuditActionLabel(id: "invoice_edit_unlocked_by_admin", label: "Modification déverrouillée par un administrateur"),
        AuditActionLabel(id: "order_created", label: "Commande créée"),
        AuditActionLabel(id: "order_updated", label: "Commande modifiée"),
        AuditActionLabel(id: "order_deleted", label: "Commande supprimée"),
        AuditActionLabel(id: "quote_created", label: "Devis créé"),
        AuditActionLabel(id: "quote_updated", label: "Devis modifié"),
        AuditActionLabel(id: "quote_deleted", label: "Devis supprimé"),
        AuditActionLabel(id: "directory_entry_created", label: "Tiers créé"),
        AuditActionLabel(id: "directory_entry_updated", label: "Tiers modifié"),
        AuditActionLabel(id: "directory_entry_deleted", label: "Tiers supprimé"),
        AuditActionLabel(id: "pdp_deposit_sent", label: "Dépôt PDP envoyé"),
        AuditActionLabel(id: "pdp_deposit_error", label: "Dépôt PDP échoué"),
        AuditActionLabel(id: "pdp_status_received", label: "Statut PDP reçu"),
        AuditActionLabel(id: "pdp_status_sent", label: "Statut PDP envoyé"),
        AuditActionLabel(id: "pdp_status_error", label: "Interrogation PDP échouée"),
        AuditActionLabel(id: "pdp_status_send_error", label: "Envoi du statut PDP échoué"),
        AuditActionLabel(id: "login_success", label: "Connexion réussie"),
        AuditActionLabel(id: "login_password_ok", label: "Mot de passe vérifié (double authentification requise)"),
        AuditActionLabel(id: "login_failed", label: "Échec de connexion"),
        AuditActionLabel(id: "login_blocked", label: "Connexion bloquée"),
        AuditActionLabel(id: "logout", label: "Déconnexion"),
        AuditActionLabel(id: "account_locked", label: "Compte verrouillé (échecs répétés)"),
        AuditActionLabel(id: "session_expired", label: "Session expirée"),
        AuditActionLabel(id: "user_created", label: "Utilisateur créé"),
        AuditActionLabel(id: "user_deleted", label: "Utilisateur supprimé"),
        AuditActionLabel(id: "seed_admin", label: "Administrateur initial créé"),
        AuditActionLabel(id: "password_changed", label: "Mot de passe modifié"),
        AuditActionLabel(id: "role_changed", label: "Rôle modifié"),
        AuditActionLabel(id: "scope_changed", label: "Périmètre de sociétés modifié"),
        AuditActionLabel(id: "twofactor_enabled", label: "Double authentification activée"),
        AuditActionLabel(id: "twofactor_disabled", label: "Double authentification désactivée"),
        AuditActionLabel(id: "email_verification_sent", label: "Email de validation envoyé"),
        AuditActionLabel(id: "email_verified", label: "Email validé"),
        AuditActionLabel(id: "smtp_alert_error", label: "Échec d'envoi d'une alerte email"),
        AuditActionLabel(id: "backup_auto_launch_success", label: "Sauvegarde automatique réussie"),
        AuditActionLabel(id: "backup_auto_launch_failed", label: "Sauvegarde automatique échouée"),
    ]

    public init() {
        self.overrides = Self.defaultLabels
        load()
    }

    public func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([AuditActionLabel].self, from: data), !decoded.isEmpty else {
            overrides = Self.defaultLabels
            return
        }
        // Complète avec les codes apparus depuis (nouvelles fonctionnalités) sans écraser
        // les libellés déjà personnalisés par l'administrateur.
        var merged = decoded
        let knownIDs = Set(decoded.map(\.id))
        for def in Self.defaultLabels where !knownIDs.contains(def.id) {
            merged.append(def)
        }
        overrides = merged
        if let data = defaults.data(forKey: overridesBySocietyKey),
           let decoded = try? JSONDecoder().decode([UUID: [AuditActionLabel]].self, from: data) {
            overridesBySociety = decoded
        }
    }

    public func save() {
        if let data = try? JSONEncoder().encode(overrides) {
            defaults.set(data, forKey: storageKey)
        }
        if let data = try? JSONEncoder().encode(overridesBySociety) {
            defaults.set(data, forKey: overridesBySocietyKey)
        }
    }

    /// Commence (ou remplace) la personnalisation de ce libellé pour cette société.
    public func setOverride(_ override: AuditActionLabel, companyID: UUID) {
        var list = overridesBySociety[companyID] ?? []
        if let idx = list.firstIndex(where: { $0.id == override.id }) {
            list[idx] = override
        } else {
            list.append(override)
        }
        overridesBySociety[companyID] = list
        save()
    }

    /// Revient au réglage global pour ce libellé sur cette société.
    public func removeOverride(id: String, companyID: UUID) {
        overridesBySociety[companyID]?.removeAll { $0.id == id }
        if overridesBySociety[companyID]?.isEmpty == true {
            overridesBySociety.removeValue(forKey: companyID)
        }
        save()
    }

    /// Libellé français pour un code technique — retombe sur le code brut si aucun
    /// libellé n'est défini (ne devrait arriver que pour un code totalement inconnu).
    public func label(for actionCode: String) -> String {
        overrides.first(where: { $0.id == actionCode })?.label ?? actionCode
    }

    /// Variante par société — voir `InvoiceStatusStore.override(for:companyID:)`.
    public func label(for actionCode: String, companyID: UUID?) -> String {
        if let companyID, let match = SocietyScopedCatalog.resolvedElement(id: actionCode, overrideForSociety: overridesBySociety[companyID]) {
            return match.label
        }
        return label(for: actionCode)
    }

    public func upsert(_ item: AuditActionLabel) {
        if let idx = overrides.firstIndex(where: { $0.id == item.id }) {
            overrides[idx] = item
        } else {
            overrides.append(item)
        }
        save()
    }

    public func resetToDefaults() {
        overrides = Self.defaultLabels
        save()
    }
}
