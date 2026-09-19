import Foundation

/// Résolution "réglage global + surcharge par société" partagée par les tables de réglages
/// (Réglages > Tables). Fonctions libres plutôt qu'un protocole que chaque store devrait
/// adopter — la logique de fusion est strictement identique partout, mais chaque store garde
/// sa propre persistance et sa propre API publique typée, fidèle au style déjà établi par
/// `InvoiceStore`/`OrderStore`/`QuoteStore` (chacun duplique son propre
/// `numberFormatOverrides` plutôt que de partager une abstraction).
public enum SocietyScopedCatalog {

    /// Résout UN élément identifié par `id` : la surcharge de la société pour cet id, sinon
    /// `nil` (à l'appelant de retomber sur son propre repli global/défaut codé en dur — voir
    /// chaque store, qui a déjà cette chaîne de repli pour le cas sans société).
    public static func resolvedElement<T: Identifiable>(id: T.ID, overrideForSociety: [T]?) -> T? {
        overrideForSociety?.first { $0.id == id }
    }

    /// Résout la LISTE complète (pour un picker) : la liste globale, avec les entrées de la
    /// société superposées par id — remplace un id déjà présent, ajoute un id nouveau (une
    /// société peut à la fois personnaliser une entrée existante et en ajouter une qui lui
    /// est propre). Préserve l'ordre de la liste globale ; les entrées propres à la société
    /// sont ajoutées à la suite, dans leur ordre d'origine.
    public static func resolvedList<T: Identifiable>(global: [T], overrideForSociety: [T]?) -> [T] {
        guard let overrideForSociety, !overrideForSociety.isEmpty else { return global }
        var byID = Dictionary(uniqueKeysWithValues: global.map { ($0.id, $0) })
        var order = global.map(\.id)
        for item in overrideForSociety {
            if byID[item.id] == nil { order.append(item.id) }
            byID[item.id] = item
        }
        return order.compactMap { byID[$0] }
    }

    /// Équivalent de `resolvedList` pour un dictionnaire (`KindColorStore`) : fusionne la
    /// surcharge de la société par-dessus le réglage global, clé par clé.
    public static func resolvedDict<K: Hashable, V>(global: [K: V], overrideForSociety: [K: V]?) -> [K: V] {
        guard let overrideForSociety, !overrideForSociety.isEmpty else { return global }
        return global.merging(overrideForSociety) { _, new in new }
    }
}
