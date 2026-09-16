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
