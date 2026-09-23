# Évolution 3 — Analyse des API SUPER PDP et propositions d'intégrations

Source : OpenAPI `https://www.superpdp.tech/openapi/#superpdp` (OAS 3.0.4, serveur `https://api.superpdp.tech`, version `1.33.0.beta`).

## 1. État des lieux : endpoints déjà intégrés

Le service `SuperPDPService` (`Sources/FacturXCore/SuperPDPService.swift`) couvre déjà :

| Domaine API | Endpoint | Implémentation actuelle |
|---|---|---|
| Authentification | `POST /oauth2/token` (client_credentials) | `fetchToken(credentials:)` |
| Société courante | `GET /v1.beta/companies/me` | `getCompany(credentials:)` |
| Annuaire destinataires | `GET /v1.beta/directory_entries?query=` | `searchRecipient(siretOrSiren:credentials:)` |
| Validation facture | `POST /v1.beta/validation_reports` | `validateInvoice(fileData:credentials:)` |
| Dépôt facture | `POST /v1.beta/invoices` | `submitInvoice(fileData:credentials:)` |
| Statut facture | `GET /v1.beta/invoices/{id}` | `getInvoiceStatus(remoteID:credentials:)` |
| Événements de cycle de vie | `POST /v1.beta/invoice_events` | `sendInvoiceEvent(remoteID:statusCode:credentials:reportedData:)` |

Côté UI, l'application propose déjà : saisie des credentials + test de connexion, recherche d'annuaire (`SuperPDPSearchSheet`), dépôt de facture Factur-X, suivi du statut distant, et envoi d'événements de cycle de vie (statuts `fr:204`…`fr:212`).

## 2. Endpoints disponibles NON intégrés

L'OpenAPI expose des domaines entiers non couverts par l'app :

### A. Cycle de vie des factures (côté réception / historisation)
- `GET /v1.beta/invoices` — lister les factures (reçues et émises), pagination, filtres.
- `POST /v1.beta/invoices/convert` — conversion entre formats (JSON ↔ CII ↔ UBL ↔ Factur-X « readable view »).
- `GET /v1.beta/invoices/generate_test_invoice` — générer une facture de test (JSON).
- `GET /v1.beta/invoices/{id}/download` — télécharger la facture déposée (PDF Factur-X ou XML).

### B. Annuaire français (L'annuaire de la facturation électronique)
- `GET /v1.beta/french_directory/companies` — rechercher une entreprise française par SIREN/nom.
- `GET /v1.beta/french_directory/entries` — consulter les entrées d'annuaire (adresses électroniques de réception) du répertoire national.

### C. Gestion fine de l'annuaire SUPER PDP
- `POST /v1.beta/directory_entries` — créer une entrée d'annuaire (adresse de réception).
- `DELETE /v1.beta/directory_entries/{id}` — supprimer une entrée.
- `GET /v1.beta/directory_entries/{id}` — consulter une entrée précise.

### D. Événements (lecture, historique)
- `GET /v1.beta/invoice_events` — lister les événements d'une facture (historique complet du cycle de vie), pagination pour synchronisation.

### E. E-Reporting (obligation de transmission à la DGFiP)
- `POST /v1.beta/b2bint_invoices` / `GET /v1.beta/b2bint_invoices` — factures B2B intra-Community.
- `POST /v1.beta/b2bint_payments` / `GET /v1.beta/b2bint_payments` — paiements B2B intra-Community.
- `POST /v1.beta/b2c_transactions` / `GET /v1.beta/b2c_transactions` — transactions B2C.
- `POST /v1.beta/b2c_payments` / `GET /v1.beta/b2c_payments` — paiements B2C.
- `GET /v1.beta/ereportings` / `GET /v1.beta/ereportings/preview` / `GET /v1.beta/ereportings/{id}` — consultation/prévisualisation des e-reportings.

### F. Mandats de facturation (auto-factoring / self-billing)
- `POST /v1.beta/company_mandates` / `GET /v1.beta/company_mandates` / `GET /v1.beta/company_mandates/{id}` / `DELETE /v1.beta/company_mandates/{id}` / `GET /v1.beta/company_mandates/{id}/download`.

### G. Sessions OAuth2
- `GET /v1.beta/oauth2_sessions/me` — vérifier le statut d'autorisation de la session (nécessaire car un 403 peut être retourné tant que la relation user↔entreprise n'est pas vérifiée).

### H. Gestion société (PATCH)
- `POST /v1.beta/companies` / `PATCH /v1.beta/companies` — créer/mettre à jour la société (champs comme `has_vat_on_debits`).

## 3. Propositions d'intégrations (priorisées)

### Priorité 1 — Boucler le cycle facture (valeur immédiate)

**P1.1 — Téléchargement de la facture déposée (`GET /invoices/{id}/download`)**
- Dans la fiche facture, ajouter un bouton « Télécharger la copie déposée » qui récupère le PDF Factur-X tel qu'il a été transmis à SUPER PDP.
- Justification : preuve de dépôt, archive conforme, utile en cas de litige/relance.

**P1.2 — Historique des événements (`GET /invoice_events`)**
- Remplacer/étendre le statut instantané par un historique horodaté (dépôt, acceptation, rejet, encaissement `fr:212`, annulation `fr:320`).
- Justification : traçabilité du cycle de vie, audit, correspond au besoin de justifier le statut de paiement.

**P1.3 — Validation pré-dépôt dans l'éditeur (`POST /validation_reports`)**
- Le service existe déjà côté core, mais il n'est pas exposé comme action distincte dans l'éditeur. Ajouter un bouton « Valider sur SUPER PDP » avant dépôt, qui affiche le rapport (erreurs/warnings) de la PDP distante en complément de la validation locale `FacturXValidator`.
- Justification : évite les rejets de dépôt (gain de temps, conforme à la PDP réelle).

### Priorité 2 — Qualité des données et annuaire

**P2.1 — Annuaire français (`GET /french_directory/companies` + `/entries`)**
- Ajouter une recherche dans l'annuaire national en complément de l'annuaire SUPER PDP : à partir d'un SIREN, récupérer l'adresse électronique Peppol officielle et pré-remplir le `InvoiceParty` (endpointID/scheme).
- Justification : adresse de routage fiable, réduit les erreurs de dépôt, utile même si le destinataire n'est pas encore inscrit chez SUPER PDP.

**P2.2 — Vérification de session (`GET /oauth2_sessions/me`)**
- Après la connexion (test de connexion), afficher l'état d'autorisation de la session et guider l'utilisateur si la relation user↔entreprise n'est pas encore vérifiée (sinon l'app reçoit des 403 inexplicables).
- Justification : diagnostic clair des erreurs 403, meilleure expérience d'onboarding.

### Priorité 3 — E-Reporting (obligation réglementaire)

**P3.1 — Transmission e-reporting B2C / B2B-int**
- Pour les factures B2C et les transactions B2B intra-Community, générer et transmettre les données e-reporting (`b2c_transactions`, `b2c_payments`, `b2bint_invoices/payments`).
- Justification : conformité à l'obligation e-reporting de la réforme, valeur métier forte (sinon l'utilisateur doit le faire ailleurs).

**P3.2 — Consultation/prévisualisation des e-reportings**
- `GET /ereportings` + `GET /ereportings/preview` : visualiser les e-reportings transmis et leur aperçu avant envoi.

### Priorité 4 — Avancées

**P4.1 — Conversion de formats (`POST /invoices/convert`)**
- Permettre la conversion de la facture locale vers UBL ou « readable view » Factur-X (utile pour des canaux clients non Peppol).
- Justification : interopérabilité multi-format sans dépendre uniquement du CII.

**P4.2 — Gestion des mandats (`company_mandates`)**
- Gérer les mandats de facturation (self-billing / facturation pour le compte d'un tiers).
- Justification : cas métier comptable/cabinet, mais validation support SUPER PDP requise.

**P4.3 — Gestion fine de l'annuaire SUPER PDP (`POST/DELETE/GET directory_entries/{id}`)**
- Créer/gérer ses propres adresses de réception côté SUPER PDP depuis l'app.

## 4. Recommandation de périmètre pour cette évolution

**Périmètre implémenté dans cette PR (P1 + P2) :**

1. **P1.1** Téléchargement de la copie déposée — `SuperPDPService.downloadInvoice` + bouton « Copie PDP ».
2. **P1.2** Historique des événements de cycle de vie — `SuperPDPService.listInvoiceEvents` + feuille `SuperPDPEventsSheet`.
3. **P1.3** Validation pré-dépôt SUPER PDP dans l'éditeur — bouton « Valider PDP » + feuille `SuperPDPValidationSheet`.
4. **P2.1** Annuaire français national — `SuperPDPService.searchFrenchDirectory` + bouton « Annuaire FR » + feuille `SuperPDPFrenchDirectorySheet`.
5. **P2.2** Vérification de session OAuth (diagnostic 403) — `SuperPDPService.getSession` + bouton « Vérifier la session » dans Réglages.

Les Priorités 3-4 (e-reporting, conversion UBL, mandats, CRUD annuaire) restent des évolutions futures.

## 5. Détails techniques (implémentation P1)

- `SuperPDPService` :
  - `downloadInvoice(remoteID:credentials:) -> Data` → `GET /v1.beta/invoices/{id}/download`.
  - `listInvoiceEvents(remoteID:credentials:) -> [SuperPDPInvoiceEvent]` → `GET /v1.beta/invoice_events?invoice_id={id}`.
  - `getSession(credentials:) -> SuperPDPSession` → `GET /v1.beta/oauth2_sessions/me`.
  - `validateInvoice` déjà présent → exposer dans l'éditeur.
- Modèles : `SuperPDPInvoiceEvent` (status_code, created_at, details/notes).
- UI : boutons dans la fiche facture + feuille d'historique + diagnostic de session dans les réglages.

## 6. Mise à jour — chantier A (étude, sans implémentation dans cette PR)

Vérification faite directement dans `Sources/FacturXCore/SuperPDPService.swift` : P1 (`downloadInvoice`, `listInvoiceEvents`, `validateInvoice`) et P2 (`searchFrenchDirectory`, `getSession`) sont bien implémentés et exposés dans l'UI. Ce qui reste **non utilisé** aujourd'hui, sans changement depuis l'analyse initiale :

- **E-Reporting (P3)** — `b2bint_invoices/payments`, `b2c_transactions/payments`, `ereportings` : c'est le bloc le plus significatif encore non couvert, car c'est une **obligation réglementaire** (transmission à la DGFiP des opérations hors du champ facture électronique B2B domestique), pas juste une fonctionnalité de confort. À prioriser dès que l'app doit couvrir des flux B2C ou B2B intracommunautaires — sinon l'utilisateur doit déclarer ces flux par un autre moyen, ce qui est un vrai manque fonctionnel, pas une simple limitation technique.
- **Conversion de formats (P4.1)** — `POST /invoices/convert` (CII ↔ UBL ↔ vue lisible) : utile seulement si un client/partenaire exige un format non-CII ; pas de demande identifiée à ce jour côté utilisateur.
- **Mandats de facturation (P4.2)** — `company_mandates` : cas d'usage self-billing/cabinet comptable pour compte de tiers ; nécessite une validation métier (qui mandate qui, quelles responsabilités) avant tout développement, pas seulement du code.
- **Gestion fine de l'annuaire SUPER PDP (P4.3)** — CRUD `directory_entries/{id}` : l'app consomme déjà l'annuaire en lecture (recherche) ; créer/gérer ses propres entrées d'annuaire depuis l'app n'apporte de valeur que si l'utilisateur gère l'inscription de plusieurs sociétés lui-même plutôt que via le portail SUPER PDP.

**Recommandation inchangée** : rien dans ce lot ne justifie un développement immédiat sans un besoin utilisateur explicite, à l'exception de l'e-reporting si des flux B2C/B2B-int existent réellement dans l'activité facturée par l'app — dans ce cas, ce serait la seule priorité réglementaire (par opposition à fonctionnelle) de cette liste.

## 7. Mise à jour — complétion de la table des statuts de facture (2026-09-18)

Comparaison de `InvoiceStatus`/`InvoiceStatusStore.reformCode` avec la table officielle
"Meaning of fr:* statuses" de la doc SUPER PDP (`https://superpdp.tech/openapi`, schéma de
`POST /v1.beta/invoice_events`) :

| Code officiel | Signification | Créable via l'API | Avant cette mise à jour |
|---|---|---|---|
| fr:200 | Déposée | non (posé au dépôt) | `sentToPDP` ✓ |
| fr:201 | Envoyée | non | **absent** |
| fr:202 | Reçue | non | **absent** |
| fr:203 | Mise à disposition | non | **absent** |
| fr:204 | Accusé de réception | oui | **absent** |
| fr:205 | Acceptée | oui | absent (voir note ci-dessous) |
| fr:206 | Partiellement acceptée | oui | utilisé à tort pour `rejected` |
| fr:207 | Contestée | oui | utilisé à tort pour `accepted` |
| fr:208 | En attente | oui | **absent** |
| fr:209 | Complétée | oui | **absent** |
| fr:210 | Refusée | oui | absent (voir note ci-dessous) |
| fr:211 | Paiement envoyé | oui | **absent** |
| fr:212 | Paiement reçu | oui | `paid` ✓ (correct) |
| fr:213 | Rejetée | non | **absent** |
| fr:220 | (nouveau 1.33.0, pas encore documenté) | oui | non ajouté (pas de signification publiée) |
| fr:320 | — n'existe pas dans la table officielle | — | utilisé à tort pour `cancelled` |

**Ajouté dans cette évolution** (statuts manquants uniquement, sans toucher aux codes déjà en
usage) : `sentToRecipient` (fr:201), `receivedByRecipient` (fr:202), `madeAvailable` (fr:203),
`acknowledged` (fr:204), `onHold` (fr:208), `completed` (fr:209), `paymentSent` (fr:211),
`technicallyRejected` (fr:213). Les statuts réseau non créables via l'API (fr:200-203, fr:213)
ne sont accessibles qu'en réception (synchronisation du statut PDP), jamais via une transition
manuelle — voir `InvoiceStatusStore.networkOnlyReformCodes`.

**Non traité, volontairement séparé** : `accepted`/`rejected` restent sur fr:207/fr:206 (qui
signifient en réalité "Contestée"/"Partiellement acceptée", pas "Acceptée"/"Rejetée") et
`cancelled` reste sur fr:320 (qui n'existe pas du tout dans la table officielle). Corriger ces
trois codes déjà utilisés en production est un chantier distinct, pas fait ici pour ne pas
mélanger "compléter la table" et "corriger un mauvais code en usage" — voir aussi la note
ci-dessous sur `technicallyRejected`, qui recouvre déjà le sens que `rejected` devrait avoir.

## 8. Mise à jour — statuts de réforme précisés via les Spécifications Externes AIFE (2026-09-18)

La doc SUPER PDP dit explicitement "this is not a state machine" pour `status_code` — mais les
**Spécifications Externes AIFE** (chapitres 5-6, cycle de vie de la facture électronique
française) décrivent un modèle plus prescriptif, avec un vrai diagramme de transitions et des
règles métier. Confrontées à la table SUPER PDP, elles précisent deux points :

- **fr:207 "Contestée"** correspond au statut AIFE **LITIGEE** ("désaccord formalisé... un cas
  dérive de REFUSEE qui n'a pas été résolu sous 30 jours") — confirme que fr:207 ne veut
  toujours pas dire "Acceptée" (voir section 7).
- **fr:210 "Refusée"** correspond au statut AIFE **REFUSEE** ("l'acheteur conteste la facture :
  prix, livraison, conditions" — délai légal 90 jours pour réémettre après correction) : un vrai
  refus métier, distinct du rejet technique. **Ajouté** comme nouveau statut `refused`.
- **fr:213 "Rejetée"** correspond au statut AIFE **REJETEE_PPF_PDP** ("validation EN16931 + 24
  mentions FR a échoué, ou destinataire inconnu de l'annuaire") : un rejet **technique**, pas une
  décision du destinataire. Le statut ajouté en section 7 sous le nom `rejectedByRecipient` a
  donc été **renommé `technicallyRejected`** (libellé "Rejetée (validation technique)") pour
  refléter son vrai sens — ce qui, au passage, recouvre déjà ce que `rejected` (fr:206, encore
  mal codé) devrait représenter une fois corrigé : un point à clarifier dans le chantier "corriger
  fr:207/fr:206/fr:320" de la section 7.

Règle métier appliquée dans `allowedTransitions()` : une facture acceptée/approuvée
(`accepted`) ne redevient jamais "refusée" (`refused`) — seul un avoir permet de corriger une
contestation tardive après acceptation, conformément à la règle AIFE "Une facture APPROUVEE ne
peut pas devenir REFUSEE".

## 9. Changement d'architecture — séparation statut fonctionnel / journal PDP (2026-09-18)

Après les sections 7-8, `InvoiceStatus` comptait 15 cas mélangeant trois natures différentes :
purement local (`draft`/`issued`), télémétrie réseau sans aucune action de l'app
(`sentToRecipient`/`receivedByRecipient`/`madeAvailable`/`acknowledged`/`onHold`), et décision
métier (`accepted`/`rejected`/`refused`/`technicallyRejected`). Ça posait plusieurs problèmes
concrets, rencontrés en construisant les sections précédentes :

- Chaque nouveau code `fr:2XX` touchait ~10 endroits (label, icône, couleur, verrouillage,
  rang de cycle de vie, transitions, code réforme, `networkOnlyReformCodes`, mapping de
  réception, menu "Forcer", filtre de liste, table de réglages).
- `lifecycleRank` (un entier) devait simuler un ordre linéaire sur des issues qui n'en sont
  pas (`accepted`/`rejected`/`refused`/`technicallyRejected` au même "point" du cycle).
- La correction fr:206/fr:207 restait bloquée : le code exact envoyé et le statut qui pilote
  aussi le verrouillage/libellé étaient la même chose, donc corriger l'un risquait l'autre.
- `technicallyRejected` (fr:213) et `rejected` (fr:206, une fois corrigé) finissaient par
  représenter presque la même chose — doublon né du couplage statut/code.
- La doc SUPER PDP le dit elle-même : *"this is not a state machine... presence indicates an
  event has occurred rather than a current, exclusive state"* — forcer un journal
  d'événements dans un statut unique va contre la forme de la donnée.

**Décision : revenir à un statut fonctionnel réduit et stable, avec une passerelle isolée
vers le détail des événements PDP.**

### `InvoiceStatus` (9 cas, stable — voir aussi section 11)

| Statut | Rôle | Verrouille |
|---|---|---|
| `draft` | Brouillon | non |
| `issued` | Validée, non envoyée | oui |
| `sent` | Envoyée/déposée, pipeline PDP en cours | oui |
| `accepted` | Acceptée (métier) | oui |
| `disputed` | Contestée / en litige | oui |
| `refused` | Refusée (métier), éditable pour réémettre | non |
| `partiallyPaid` | Payée partiellement (ajouté section 11) | oui |
| `paid` | Payée (en totalité) | oui |
| `cancelled` | Annulée (forçage admin) | oui |

### Codes réforme corrigés au passage (`InvoiceStatusStore.reformCode`)

| Statut | Code | Avant (sections 7-8) |
|---|---|---|
| `sent` | `200` (implicite, jamais envoyé isolément) | `sentToPDP` → `"200"` (inchangé) |
| `accepted` | **`fr:205`** | `"fr:207"` (erroné — "Contestée") |
| `disputed` | `fr:207` | absent |
| `refused` | `fr:210` | inchangé |
| `partiallyPaid` | `fr:212` (même code que `paid`, section 11) | n'existait pas |
| `paid` | `fr:212` | inchangé |
| `draft`/`issued`/`cancelled` | aucun | `cancelled` avait `"fr:320"` (code inexistant) |

La correction fr:207 différée depuis la section 7 est donc faite ici, à l'occasion de la
reconstruction complète de la table — aucune raison de reporter une correction déjà identifiée
comme juste quand le modèle est de toute façon réécrit.

### La passerelle (`PDPStatusMapper.functionalTransition(for:)`, dans `SuperPDPStatusSync.swift`)

Le seul endroit à modifier pour ajouter/préciser un code SUPER PDP — un code absent reste
purement informationnel (visible dans le journal SUPER PDP de la facture) sans forcer de
changement de statut :

```swift
case "fr:205": return .accepted
case "fr:207": return .disputed
case "fr:206", "fr:210", "fr:213": return .refused
case "fr:212": return .paid
case "fr:320", "cancelled": return .cancelled
default: return nil   // fr:200-204, fr:208, fr:209, fr:211, fr:220… : informatif seulement
```

### Migration des données déjà persistées

`InvoiceStatus` a un `init(from decoder:)` sur mesure : un statut inconnu (l'un des 7 retirés
des sections 7-8, ou tout futur cas retiré) se recale sur l'équivalent le plus proche
(`sentToPDP`/`sentToRecipient`/`receivedByRecipient`/`madeAvailable`/`acknowledged`/`onHold` →
`sent` ; `rejected`/`technicallyRejected` → `refused` ; `completed` → `accepted` ;
`paymentSent` → `paid`) plutôt que d'échouer à décoder — une facture existante avec l'un de
ces statuts ne doit jamais disparaître silencieusement au chargement.

### Ce qui ne change pas

Le journal des événements SUPER PDP (`SuperPDPInvoiceEvent`/`listInvoiceEvents`, le panneau
"Journal SUPER PDP" de la fiche facture) reste la référence complète et fidèle du détail
réseau — il n'a jamais eu besoin d'être dupliqué dans `InvoiceStatus`. Le moteur de
synchronisation périodique (`PDPPeriodicSyncEngine`, section précédente) est inchangé dans sa
structure ; seule son étape "traduire le code reçu" passe par la passerelle plutôt que par un
mapping à 15 cibles.

## 10. La passerelle devient une table de paramétrage (2026-09-18)

`PDPStatusMapper.functionalTransition(for:)` (section 9) était un switch codé en dur — pour
ajuster un libellé ou une règle de mise à jour, il fallait modifier le code. Nouvelle table
**Réglages > Tables > Statuts SUPER PDP** (`SuperPDPStatusCodeStore`) : chaque code `fr:2XX`
connu a désormais un libellé français modifiable et une "règle de mise à jour" — le statut
fonctionnel qu'il déclenche, choisi dans une liste (ou "Aucune" pour un code purement
informationnel). `PDPStatusMapper.functionalTransition(for:)` consulte maintenant cette table
en premier, avec l'ancien switch (mots libres uniquement, plus les codes `fr:*`) en repli.

Contrairement à la table des statuts de facture (section 9), un bouton "Nouvelle valeur" a un
sens ici : un code SUPER PDP pas encore connu de l'app (ex. `fr:220`, ajouté en 1.33.0 sans
signification publiée au moment de l'écriture) peut être configuré dès que sa signification
est connue, sans mise à jour de l'app. Les 16 codes officiels connus par défaut (fr:200-213,
fr:220, fr:501) restent non supprimables ; un code ajouté par l'administrateur l'est.

## 11. Ajout du statut « Payée partiellement » (2026-09-18)

Demande initiale : pouvoir ajouter une nouvelle valeur dans la table des statuts de facture
(bouton "Nouvelle valeur" retiré section 9). Refusé tel quel — `Invoice.status` est typé sur
l'enum `InvoiceStatus` fermé, une entrée ajoutée depuis les réglages n'aurait jamais pu être
assignée à une vraie facture (même problème que le bug des entrées orphelines, section 9).
Clarifié avec l'utilisateur : il fallait un vrai 9ᵉ cas d'enum, pas une étiquette décorative.
Statut retenu : **`partiallyPaid`** — l'AIFE distingue `PAYEE_PARTIELLEMENT` de
`PAYEE_TOTALEMENT`/`ENCAISSEE`, jusque-là confondus dans le seul `paid`.

- **Rang de cycle de vie** : strictement entre `accepted`/`disputed`/`refused` (3) et
  `paid`/`cancelled` (désormais 5) — `partiallyPaid` prend le rang 4. Nécessaire pour que
  recevoir "paid" après "partiallyPaid" compte comme un avancement (`isAdvance`, comparaison
  stricte `>` dans `refreshSuperPDPStatus`/`PDPPeriodicSyncEngine`) plutôt que de rester bloqué.
- **Transitions** : `accepted → partiallyPaid → paid`, avec `partiallyPaid → disputed`
  toujours possible (un litige peut survenir après un premier règlement partiel).
- **Code réforme** : `fr:212`, **le même que `paid`** — la table officielle fr:2XX n'a qu'un
  événement générique "Paiement reçu", pas de distinction partiel/total au niveau du code
  réseau (le montant réel se transmettrait via `reportedData`, pas via le statut). Documenté
  dans `InvoiceStatusStore.reformCode` pour qu'un futur lecteur ne s'étonne pas du doublon.
- **Réception** : volontairement asymétrique. `SuperPDPStatusCodeStore` fait toujours
  résoudre `fr:212` reçu vers `.paid` (paiement total) — le statut réseau seul ne dit pas si
  le montant reçu couvre la facture en entier. `partiallyPaid` reste donc un statut **posé
  localement par le comptable**, jamais déduit automatiquement d'un événement PDP reçu.
  Réglable dans Réglages > Tables > Statuts SUPER PDP si SUPER PDP précise un jour la
  distinction par code.
- **Verrouillage** : oui, comme tous les statuts post-acceptation.
- **Pas de suivi de montant** : l'app ne stocke pas "combien reste dû" — `partiallyPaid` est
  une étiquette de statut, pas un solde. Hors périmètre de cette demande ; à revisiter si le
  besoin apparaît (nécessiterait un champ dédié sur `Invoice` et une UI de saisie du montant).
- **Sur une installation existante** : `transitionCodes` est volontairement admin-modifiable
  (case à cocher dans l'éditeur de statut, Réglages > Tables > Statuts des factures) — `load()`
  ne le réaligne donc jamais tout seul sur les valeurs par défaut du code (contrairement à
  `reformCode`, non éditable, réaligné à chaque chargement). Une table déjà personnalisée pour
  "Acceptée" ne gagne pas automatiquement "Payée partiellement" comme cible : il faut cocher
  la case manuellement une fois. Seul le nouveau statut lui-même (id inédit) reçoit ses
  transitions par défaut (`disputed`, `paid`) au premier chargement, comme toute nouvelle ligne.

## 12. Rapport de validation : la ligne en cause (2026-09-23)

`POST /v1.beta/validation_reports` range les échecs par validateur (`subreports[]`), dans
`failures[]` et `messages[]`, au schéma `message` : `message`, `raw`, `location`. L'OpenAPI
(1.34.0.beta) décrit `location` comme « location of error in the XML if available »,
optionnelle, sans exemple. Vérifié sur une vraie réponse (facture fictive, BR-Z-05 en échec sur
les lignes 2 et 3) : `location` est le chemin SVRL du XSLT officiel, repris tel quel.

```
/*:CrossIndustryInvoice[namespace-uri()='…'][1]/*:SupplyChainTradeTransaction[namespace-uri()='…'][1]/*:IncludedSupplyChainTradeLineItem[namespace-uri()='…'][2]/*:SpecifiedLineTradeSettlement[namespace-uri()='…'][1]/*:ApplicableTradeTax[namespace-uri()='…'][1]
```

- Les deux échecs BR-Z-05 avaient exactement le même `message` : seul le rang `[2]`/`[3]` les
  distinguait. Le rang est le dernier prédicat de l'étape `IncludedSupplyChainTradeLineItem`,
  après le filtre de namespace.
- `CIIXMLGenerator` émet les lignes dans l'ordre de l'éditeur, avec `LineID` (BT-126) = rang :
  la « ligne 2 » du rapport est la 2e ligne de l'éditeur.
- `raw` contient le fragment SVRL complet (`<svrl:failed-assert … location="…">…`).
- La réponse contient aussi un champ `rule` (ex. `BR-Z-05`) absent de l'OpenAPI. L'app ne s'en
  sert pas : le message commence déjà par `[BR-Z-05]`.
- L'endpoint est public (`security: []` dans l'OpenAPI) : il répond sans jeton.

Côté app, `SuperPDPValidationMessage` garde `message` et `location`. L'éditeur relève les
désignations des lignes (BT-153) avec le fichier envoyé et les range dans le rapport
(`lineNames`). `displayText(for:)` vaut alors « Ligne 2 (Désignation) — [BR-Z-05]-… » pour un
échec de ligne, « Ligne 2 — … » si la désignation manque, et le message seul sinon (en-tête,
pas de `location`). Relever les désignations à la validation garde le libellé juste même si
une ligne est ensuite supprimée ou déplacée dans l'éditeur. `errors`/`warnings` restent le
texte seul, un par échec : le compteur « n erreur(s) » ne change pas.

## 13. Rapport non conforme : tout ce qu'il liste compte comme erreur (2026-09-23)

Vérifié sur `POST /v1.beta/validation_reports` avec des factures fictives générées par l'app :

- `failures[]` reçoit les assertions SVRL sans `flag`, par exemple BR-Z-05 et BR-Z-09 pour une ligne en catégorie Z à 20 %. `messages[]` reçoit celles en `flag="warning"` (lisible dans `raw`), quel que soit le validateur :
  - `PEPPOL-EN16931-R008` (élément vide) vient du validateur EN16931 ;
  - BR-FR-05 vient du validateur `…/BR-FR-Flux2-Schematron-CII_WARNING.xslt`.
- Un seul élément, dans l'un ou l'autre tableau, suffit à `is_valid=false`.
  - Une mention PMT, PMD ou AAB manquante (BR-FR-05) rend ainsi le fichier non conforme, sur un 380, un 381 ou un 386. SUPER PDP la marque `flag="warning"`, alors que le Schematron France CTC officiel la classe fatale.
  - Aucun rapport conforme n'a jamais contenu de message.

**Avant** : le panneau classait les entrées par nom de validateur. Un rapport dont la seule cause était BR-FR-05 s'affichait « Validation SUPER PDP non conforme — 0 erreur(s) », avec BR-FR-05 sous « Avertissements ».

**Désormais** : `parseValidationReport` compte comme erreur tout ce que liste un rapport non conforme, dans l'ordre du rapport. Le nom « WARNING » ne sépare plus des avertissements que sur un rapport conforme. Le même rapport s'affiche « non conforme — 1 erreur(s) », BR-FR-05 sous « Erreurs ».

Un rapport `is_valid=false` ne dit pas si SUPER PDP refuse le dépôt : il faudrait un dépôt réel pour le vérifier. FA-2026-0011 a été déposée malgré un rapport `is_valid=false` à 3 `messages`. La PR #148 rend aussi BR-FR-05 bloquante dans l'app : ce cas ne peut alors plus partir de l'éditeur.
