# Étude — Structure générique d'import de documents depuis des applications tierces

Document de proposition uniquement — **aucun code n'est livré dans cette PR**. Contrairement aux autres chantiers de cette série, celui-ci n'a pas d'implémentation directe : l'énoncé (« import générique de documents depuis des applications tierces ») est trop ouvert pour être développé sans deviner ce qu'il recouvre réellement. Ce document explique pourquoi, situe ce qui existe déjà, et propose une architecture prête à être implémentée dès qu'un format cible concret est choisi.

## 1. Pourquoi pas de code dans cette PR

« Applications tierces » peut désigner des choses très différentes selon l'intention :
- un logiciel de comptabilité concurrent (Sage, EBP, Cegid, QuickBooks…) dont on voudrait reprendre les factures/tiers existants à la bascule vers cette app,
- un format d'échange normalisé (UBL, CII d'une autre plateforme, Peppol),
- un tableur avec une mise en forme quelconque, différente du CSV déjà défini par l'app (`ExportGenerator`),
- un export d'une autre PDP que SUPER PDP.

Deviner l'un de ces cas et construire un parseur pour un format précis, sans savoir lequel est réellement visé, a un vrai risque : produire du code mort si ce n'est pas le bon format, ou pire, donner une fausse impression de fonctionnalité (« l'import existe ») alors qu'il ne couvre qu'un cas très spécifique non demandé. C'est le genre d'erreur qu'il vaut mieux éviter en la signalant plutôt qu'en la commettant silencieusement.

## 2. Ce qui existe déjà (à ne pas reconstruire)

| Besoin | Déjà couvert par |
|---|---|
| Import de tiers depuis un CSV (format propre à l'app) | `ExportGenerator.parseDirectoryCSV` (Réglages > Données > Tiers) |
| Import fidèle de factures/commandes/tiers au format natif de l'app | `DataPortability` (chantier B — JSON structuré, import/export par module) |
| Pré-remplissage d'une commande à partir d'un document papier scanné | `ScannedDocumentParser` + `DocumentScanImportView` (chantier F — OCR local) |
| Sauvegarde/restauration complète | `BackupService` (chantier C) |

Ces quatre briques couvrent déjà : nos propres données (JSON), nos propres tiers en CSV, et du papier scanné. Ce qui manque réellement, c'est l'import de données **structurées mais dans un format qui n'est pas le nôtre** — un fichier produit par un autre logiciel.

## 3. Architecture proposée : adaptateurs d'import enfichables

Plutôt qu'un import « universel » (illusoire — aucun format ne peut tout lire), la proposition est une architecture ouverte : un protocole commun, et un adaptateur par format tiers, ajouté au fil des besoins réels sans toucher au reste de l'app.

```swift
public protocol DocumentImportAdapter {
    /// Nom affiché à l'utilisateur (ex. "Sage 50 — export CSV", "UBL 2.1").
    var displayName: String { get }

    /// Détection best-effort : ce fichier ressemble-t-il à ce format ?
    /// (extension + signature de contenu, jamais une simple extension seule).
    func canHandle(fileURL: URL, data: Data) -> Bool

    /// Convertit le contenu reconnu en enregistrements déjà au format de l'app.
    /// Ne modifie rien : c'est à l'appelant (UI) de relire, confirmer, puis
    /// appeler InvoiceStore.upsert / OrderStore.upsert / PartyDirectory.upsert —
    /// même principe de confirmation explicite que pour le scan OCR (chantier F).
    func parse(data: Data) throws -> ImportedDocumentSet
}

public struct ImportedDocumentSet {
    public var invoices: [Invoice]
    public var orders: [SalesOrder]
    public var parties: [DirectoryEntry]
    public var warnings: [String]   // ex. « TVA non reconnue sur la ligne 4, mise à 0 »
}

public enum DocumentImportRegistry {
    public static let adapters: [DocumentImportAdapter] = [
        // UBLImportAdapter(), SageCSVImportAdapter(), ... ajoutés un par un
    ]

    public static func adapter(for fileURL: URL, data: Data) -> DocumentImportAdapter? {
        adapters.first { $0.canHandle(fileURL: fileURL, data: data) }
    }
}
```

Ajouter un nouveau format = ajouter un fichier qui implémente `DocumentImportAdapter` et l'enregistrer dans `DocumentImportRegistry.adapters` — aucune autre partie de l'app à modifier. L'UI (un seul écran d'import générique) reste la même quel que soit le format détecté : choisir un fichier, afficher ce qui a été reconnu (et les avertissements), confirmer, importer.

## 4. Premier candidat concret, si validé : UBL (Universal Business Language)

**UBL est la seule proposition faite ici avec un vrai fondement**, contrairement aux autres pistes qui restent hypothétiques sans confirmation :
- UBL est, avec CII (déjà généré par cette app via `CIIXMLGenerator`), l'une des deux syntaxes officiellement reconnues par la norme européenne EN 16931 de facturation électronique.
- Chorus Pro (déjà intégré, `ChorusProService.swift`) accepte les deux syntaxes.
- L'API SUPER PDP elle-même expose un endpoint de conversion CII ↔ UBL (`/invoices/convert`, documenté dans `docs/integrations-superpdp.md`, priorité P4.1, non implémenté) — signe qu'UBL circule réellement dans cet écosystème, pas une hypothèse en l'air.

Un `UBLImportAdapter` lirait un XML UBL Invoice, en extrayant les champs qui ont un équivalent direct dans `Invoice`/`InvoiceParty`/`InvoiceLine` (numéro, dates, parties, lignes, TVA) — une tâche bornée, testable unitairement avec des fichiers UBL d'exemple publics (le standard OASIS en fournit).

## 5. Ce qui manque avant de développer quoi que ce soit

Une seule vraie question, à trancher par vous plutôt que devinée : **quel logiciel ou format précis faut-il pouvoir importer ?** Exemples de réponses possibles et leur suite immédiate :
- « Un export Sage/EBP/Cegid » → il faudra un fichier d'exemple réel (anonymisé si besoin) pour calibrer le parseur sur la mise en forme exacte, pas seulement sa description.
- « Du UBL » → développement direct possible dès la prochaine session, sur la base de la section 4.
- « Un export d'une autre PDP que SUPER PDP » → préciser laquelle et son format de sortie.
- « Autre chose » → à préciser, la liste ci-dessus n'est pas exhaustive.

## 6. Conclusion

L'architecture à adaptateurs (section 3) peut être posée dès qu'un premier format cible est choisi — elle ne dépend d'aucune décision préalable sur le mode web (chantier D) ni sur les autres chantiers de cette série. Ce qui bloque n'est pas technique : c'est de savoir quel fichier, produit par quel outil, doit réellement être lu.
