# Étude de faisabilité — Version « mode Web » de Facture_elec

Document de proposition uniquement — **aucun code n'est livré dans cette PR**. Objectif : évaluer si un mode web est réaliste, et si oui, proposer une architecture cible moderne, sécurisée et administrable, avec un chemin de migration qui ne remet pas en cause l'application desktop existante du jour au lendemain.

## 1. Résumé

**C'est réaliste, et moins coûteux que ça n'en a l'air**, pour une raison structurelle : le code métier (génération Factur-X/Order-X, validation EN 16931, statuts, intégration SUPER PDP/Chorus Pro, SMTP) vit déjà dans un module séparé — `FacturXCore` — qui ne dépend de SwiftUI/AppKit que sur 2 fichiers (le rendu PDF). Un serveur web peut réutiliser ce module presque tel quel plutôt que de réécrire toute la logique métier dans un autre langage.

**Recommandation** : un backend **Vapor (Swift)** réutilisant `FacturXCore`, une base **PostgreSQL**, un frontend **SPA TypeScript** consommant une API JSON, déployés progressivement à côté de l'app desktop (pas à sa place, dans un premier temps).

## 2. Ce qui change fondamentalement (pas seulement technique)

Avant l'architecture, trois changements de nature, pas de degré :

1. **Le modèle de confiance change.** Aujourd'hui, les données (factures, identifiants SUPER PDP, mots de passe) ne quittent jamais le Mac de l'utilisateur — c'est un vrai atout pour des données comptables sensibles. En mode web, les données transitent par un serveur que quelqu'un doit sécuriser, surveiller et maintenir à jour en continu. Ce n'est plus un projet fini, c'est un service à opérer.
2. **Un coût récurrent apparaît** : hébergement, nom de domaine, certificat TLS (gratuit via Let's Encrypt, mais à renouveler/automatiser), sauvegardes de la base, monitoring. Aujourd'hui le coût marginal d'un utilisateur de plus est nul (il installe l'app) ; en mode web il y a un serveur à dimensionner.
3. **La conformité RGPD devient explicite.** Des données de facturation (identité de sociétés, emails de contacts, historique de paiement) hébergées sur un serveur mutualisé impliquent : localisation des données (idéalement UE), registre de traitement, politique de rétention, procédure de notification de violation. En local sur le Mac de chaque comptable, cette question ne se posait pas dans les mêmes termes.

Aucun de ces points n'est bloquant, mais ce sont des décisions produit/juridiques, pas seulement des choix d'architecture — à trancher avant de lancer le développement, pas après.

## 3. Architecture cible proposée

### 3.1 Backend : Vapor, en réutilisant `FacturXCore`

[Vapor](https://vapor.codes) est le framework serveur Swift le plus mature (routing, middleware, JSON, WebSockets si besoin plus tard). Intérêt concret ici : `Package.swift` peut ajouter une troisième target `FacturXServer` qui dépend de `FacturXCore` exactement comme `FacturXMacApp` le fait déjà :

```swift
.executableTarget(
    name: "FacturXServer",
    dependencies: ["FacturXCore", .product(name: "Vapor", package: "vapor")],
    path: "Sources/FacturXServer"
)
```

Ce qui se réutilise **sans modification** : `CIIXMLGenerator`, `OrderCIOXMLGenerator`, `FacturXValidator`, `EN16931BusinessRules`, `FacturXEmbedder`/`OrderXEmbedder`, `SuperPDPService`, `ChorusProService`, `SMTPService`, `IBANValidator`, tous les modèles (`Invoice`, `Order`/`SalesOrder`, `Quote`, `InvoiceParty`, `InvoiceLine`…), la logique de statuts (`InvoiceStatusStore`, `OrderStatusStore`).

Ce qui doit être adapté : les classes `ObservableObject` (`InvoiceStore`, `OrderStore`, `QuoteStore`, `AuthStore`…) sont pensées pour un état en mémoire local persistant en `UserDefaults` — côté serveur, ce rôle est repris par une couche de persistance base de données (§3.2) et les mutations passent par des endpoints HTTP au lieu de bindings SwiftUI.

**Point d'attention réel** : `InvoicePDFRenderer` et `OrderPDFRenderer` dépendent d'`AppKit`/`CoreGraphics`/`CoreText`, indisponibles sur Linux. Deux options :
- **Option A (la plus rapide)** : héberger le serveur Vapor sur macOS (Mac mini/Mac Studio en co-location, ou une instance EC2 Mac/MacStadium) — le rendu PDF continue de fonctionner sans réécriture. Coût d'hébergement plus élevé qu'un Linux classique, mais zéro régression sur le rendu PDF existant.
- **Option B (portable, plus de travail)** : remplacer le rendu par génération HTML/CSS (réutilisant les mêmes données) + conversion PDF via un moteur headless (ex. Chromium via Puppeteer, ou une bibliothèque Swift pure). Permet un hébergement Linux standard, moins coûteux, mais demande de réécrire l'habillage visuel des factures/commandes.

Recommandation : démarrer avec l'option A (aucune régression, mise en service rapide), migrer vers B seulement si le coût d'hébergement macOS devient un problème réel.

### 3.2 Persistance : PostgreSQL

`UserDefaults` est mono-poste par construction — inutilisable dès qu'il y a plusieurs utilisateurs concurrents. PostgreSQL est le choix par défaut pour une app métier de ce type (transactionnel, JSON natif pour les champs semi-structurés comme `optionalFields`, écosystème Swift mature via [Fluent](https://docs.vapor.codes/fluent/overview/) ou SQL direct via `PostgresNIO`).

Migration des modèles : les `struct` `Codable` existants (`Invoice`, `Order`, `Quote`, `InvoiceParty`…) se transposent directement en tables/colonnes ou, pour aller plus vite au départ, en colonnes `JSONB` (un `Invoice` complet dans une colonne JSON avec quelques colonnes indexées à côté — `id`, `number`, `companyID`, `status`, `dueDate` — pour les requêtes fréquentes). C'est un compromis pragmatique : moins de normalisation qu'un schéma relationnel complet, mais migration quasi mécanique depuis les modèles actuels, et une vraie table relationnelle peut être introduite plus tard sans changer l'API.

### 3.3 Authentification & sécurité

- **Mots de passe** : remplacer le SHA256+sel maison (`Auth.swift`) par un hachage dédié aux mots de passe (bcrypt ou argon2, disponibles via Vapor). Le SHA256 itéré actuel est acceptable pour un stockage 100% local, mais pas pour un service exposé sur Internet où les attaques par force brute sont automatisées.
- **Sessions** : JWT signé (courte durée + refresh token) ou sessions serveur classiques avec cookie `HttpOnly` + `Secure`. Pas de mot de passe/API key dans le `localStorage` du navigateur.
- **2FA** : le TOTP prévu au chantier A s'intègre naturellement ici — et devient même plus utile qu'en local, puisque le risque couvert (identifiants volés à distance, sans accès physique à un poste) est précisément celui d'un service exposé sur Internet.
- **Clés secrètes** (identifiants SUPER PDP, SMTP, futures clés cloud du chantier C) : aujourd'hui en `UserDefaults`, acceptable en local. En mode web, elles doivent aller dans un secret manager (Vault, AWS/GCP Secrets Manager, ou au minimum chiffrées en base avec une clé hors base) — jamais en clair dans une table SQL accessible par tous les processus applicatifs.
- **TLS obligatoire partout**, y compris entre le reverse proxy et le backend si les deux ne sont pas sur la même machine.
- **RBAC** : le système de rôles existant (`UserRole`, `AuthStore.visibleInvoiceCompanyIDs`/`visibleOrderCompanyIDs`) se retranspose directement en contrôle d'accès côté serveur — c'est un vrai atout, cette logique de périmètre par société existe déjà et n'a pas besoin d'être repensée.
- **CSRF** : nécessaire uniquement si le frontend utilise des cookies de session pour l'authentification (pas nécessaire avec un token porté en en-tête `Authorization`).
- **Rate limiting** sur `/login` et toute route d'authentification, pour limiter le bruteforce.
- **Audit trail** : `AuditStore` existe déjà (journal actor/action/objet) — à faire persister en base au lieu de `UserDefaults`, avec rétention définie.

### 3.4 Frontend

Deux options réalistes :

| | SPA (TypeScript, ex. React/Vue) | Rendu serveur (Vapor + Leaf) |
|---|---|---|
| Interactivité (tableaux dynamiques, formulaires complexes comme les éditeurs de factures) | Très bonne | Limitée, plus de rechargements de page |
| Coût de développement initial | Plus élevé (nouveau frontend à écrire entièrement) | Plus faible (réutilise les templates côté serveur) |
| Séparation des équipes (un futur dev frontend dédié) | Facilite | Moins pertinent |
| Offline / app mobile future | Bonne base (API déjà découplée) | Nécessiterait une réécriture |

**Recommandation** : SPA TypeScript consommant l'API JSON du backend Vapor. L'app actuelle a des interactions riches (statuts dynamiques, éditeurs de lignes, recherche SUPER PDP en direct) qui se prêtent mal à un rendu serveur classique. Un framework composant (React ou Vue, au choix de qui l'implémentera) suffit, sans framework applicatif lourd.

### 3.5 Multi-environnement (test/production)

Le système actuel (`AppEnvironment`, clés `UserDefaults` suffixées par environnement) se retranspose en deux déploiements séparés (deux bases, deux jeux de credentials SUPER PDP) plutôt qu'un paramètre applicatif — plus sûr : impossible de mélanger accidentellement les deux comme pourrait le permettre un simple flag en base partagée.

### 3.6 Administrabilité

- **CI/CD** : `swift build` + `swift test` déjà en place localement → à automatiser via GitHub Actions (build du serveur, tests `FacturXCoreTests` inchangés, déploiement sur validation).
- **Conteneurisation** : image Docker pour le backend (même sur macOS via une VM si l'option PDF A est retenue, sinon conteneur Linux classique en option B).
- **Observabilité** : logs structurés + métriques de base (latence API, erreurs SUPER PDP/Chorus Pro) — inexistant aujourd'hui car inutile en mono-poste, indispensable dès qu'un serveur tourne sans supervision humaine directe.
- **Sauvegardes** : sauvegarde automatisée de PostgreSQL (pg_dump planifié ou réplication), à coordonner avec le chantier C (sauvegarde cloud) qui pourrait devenir la destination de ces sauvegardes serveur également.

## 4. Plan de migration incrémental

Ne pas basculer d'un coup — l'app desktop reste la référence jusqu'à preuve que le mode web est fiable :

1. **Phase 0** — Extraire le peu qui reste de spécifique-desktop dans `FacturXCore` si besoin (déjà largement fait : seuls les 2 renderers PDF dépendent d'AppKit).
2. **Phase 1** — Serveur Vapor minimal exposant une API en lecture seule (consultation de factures) branchée sur les données existantes, pour valider l'intégration `FacturXCore` côté serveur sans risque sur les données de production.
3. **Phase 2** — Persistance PostgreSQL + migration des données existantes (script one-shot lisant les `UserDefaults` exportées et les insérant en base).
4. **Phase 3** — Authentification serveur (remplace `AuthStore` local), RBAC, 2FA.
5. **Phase 4** — API en écriture complète (création/modification factures, commandes, devis, dépôt SUPER PDP depuis le serveur).
6. **Phase 5** — Frontend web complet, en parallèle de l'app desktop (qui peut à terme devenir un client optionnel de la même API, ou rester un mode 100% local pour qui le préfère — les deux ne sont pas exclusifs).

Chaque phase est livrable et testable seule ; aucune n'exige d'arrêter l'app desktop existante.

## 5. Ce qui reste à décider avant de lancer le développement

Ce ne sont pas des questions techniques :
- Qui héberge, et où (UE pour la conformité RGPD) ?
- Qui porte la responsabilité de la sécurité du serveur en continu (mises à jour, supervision, réponse à incident) ?
- Le mode web remplace-t-il le desktop à terme, ou coexiste-t-il durablement (deux publics différents) ?
- Budget d'hébergement récurrent acceptable (macOS hosting a un coût non négligeable si l'option A est retenue) ?

## 6. Conclusion

Techniquement, la base de code actuelle rend ce projet plus abordable qu'une réécriture complète ne le laisserait penser, grâce à la séparation déjà existante entre `FacturXCore` (portable) et l'UI (spécifique macOS). Le risque principal n'est pas la faisabilité technique mais l'engagement organisationnel que représente le passage d'un logiciel installé à un service opéré en continu. Recommandation : valider les questions de la section 5 avant tout développement, puis avancer par les phases de la section 4.
