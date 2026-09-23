# Mapping Factur-X / EN 16931 — champs application ↔ balises CII ↔ règles métier

Table de correspondance entre les champs de l'application (`Sources/FacturXCore/Models.swift`), les balises CII émises (`Sources/FacturXCore/CIIXMLGenerator.swift`) et les règles métier EN 16931 (`Sources/FacturXCore/EN16931BusinessRules.swift`).

**Colonne Règle** : identifiant de la règle qui s'applique au champ (vide = pas de règle spécifique). Les règles en **erreur** bloquent la conformité ; celles en *avertissement* sont signalées sans bloquer.

## En-tête de facture

| Champ application | Balise CII / UBL | BT/BG | Règle | Sévérité |
|---|---|---|---|---|
| `invoice.number` | `rsm:ExchangedDocument/ram:ID` | BT-1 | BR-1 | erreur |
| `invoice.type` | `rsm:ExchangedDocument/ram:TypeCode` | BT-3 | BR-FR-04 | avertissement (387 → 380) |
| `invoice.issueDate` | `rsm:ExchangedDocument/ram:IssueDateTime/udt:DateTimeString` | BT-2 | BR-2 | avertissement |
| `invoice.dueDate` | `ram:SpecifiedTradePaymentTerms/ram:DueDateDateTime` | BT-9 | BR-9 | avertissement |
| `invoice.currency` | `ram:ApplicableHeaderTradeSettlement/ram:InvoiceCurrencyCode` | BT-5 | BR-5 | erreur |
| `invoice.profile` | `ram:GuidelineSpecifiedDocumentContextParameter/ram:ID` | BT-24 | BR-PROFIL | avertissement |
| `invoice.billingMode` | `ram:BusinessProcessSpecifiedDocumentContextParameter/ram:ID` | BT-23 | BR-FR-CO-08, BR-FR-CO-09, BR-FR-MV-02, BR-FR-BD-02 | erreur |
| `invoice.buyerReference` | `ram:BuyerReference` | BT-10 | — | — |
| `invoice.purchaseOrderRef` | `ram:BuyerOrderReferencedDocument/ram:IssuerAssignedID` | BT-13 | — | — |
| `invoice.contractRef` | `ram:ContractReferencedDocument/ram:IssuerAssignedID` | BT-12 | — | — |
| `invoice.tenderRef` | `ram:AdditionalReferencedDocument/ram:IssuerAssignedID` + `ram:TypeCode` = `50` | BT-17 | — | — |
| `invoice.receivingAdviceRef` | `ram:ReceivingAdviceReferencedDocument/ram:IssuerAssignedID` | BT-15 | — | — |
| `invoice.despatchAdviceRef` | `ram:DespatchAdviceReferencedDocument/ram:IssuerAssignedID` | BT-16 | — | — |
| `invoice.precedingInvoiceRef` | `ram:ApplicableHeaderTradeSettlement/.../ram:IssuerAssignedID` (invoiceReferencedXML) | BT-25 | BR-FR-CO-05 | erreur |
| `invoice.precedingInvoiceDate` | `ram:ApplicableHeaderTradeSettlement/.../ram:FormattedIssueDateTime` | BT-26 | BR-FR-CO-05 | erreur |
| `invoice.notes` | `ram:IncludedNote/ram:Content` (sans SubjectCode) | BT-22 | — | — |
| `invoice.legalNotePMT` | `ram:IncludedNote/ram:Content` + `ram:SubjectCode` = `PMT` | BT-21 (PMT) | BR-FR-05 | avertissement |
| `invoice.legalNotePMD` | `ram:IncludedNote/ram:Content` + `ram:SubjectCode` = `PMD` | BT-21 (PMD) | BR-FR-05 | avertissement |
| `invoice.legalNoteAAB` | `ram:IncludedNote/ram:Content` + `ram:SubjectCode` = `AAB` | BT-21 (AAB) | BR-FR-05 | avertissement |

## Émetteur / Destinataire (Party)

| Champ application | Balise CII | BT/BG | Règle | Sévérité |
|---|---|---|---|---|
| `seller.name` | `ram:SellerTradeParty/ram:Name` | BT-27 | BR-6 | erreur |
| `seller.country` | `ram:SellerTradeParty/ram:PostalTradeAddress/ram:CountryID` | BT-40 | BR-7 | erreur |
| `seller.siren` | `ram:SellerTradeParty/ram:SpecifiedLegalOrganization/ram:ID` | BT-30 | BR-49 | erreur |
| `seller.endpointID` | `ram:SellerTradeParty/ram:URIUniversalCommunication/ram:URIID` | BT-49 | BR-49 | erreur |
| `seller.vatNumber` | `ram:SellerTradeParty/ram:SpecifiedTaxRegistration/ram:ID` | BT-31 | — | — |
| `seller.street` | `ram:SellerTradeParty/ram:PostalTradeAddress/ram:LineOne` | BT-35 | — | — |
| `seller.postcode` | `ram:SellerTradeParty/ram:PostalTradeAddress/ram:PostcodeCode` | BT-38 | — | — |
| `seller.city` | `ram:SellerTradeParty/ram:PostalTradeAddress/ram:CityName` | BT-37 | — | — |
| `seller.contactName` | `ram:SellerTradeParty/ram:DefinedTradeContact/ram:PersonName` | BT-41 | — | — |
| `seller.contactPhone` | `ram:SellerTradeParty/ram:DefinedTradeContact/ram:TelephoneUniversalCommunication` | BT-42 | — | — |
| `seller.contactEmail` | `ram:SellerTradeParty/ram:DefinedTradeContact/ram:EmailURIUniversalCommunication` | BT-43 | — | — |
| `seller.iban` | `ram:PayeePartyCreditorFinancialAccount/ram:IBANID` (paiement) | BT-90 | BR-50 | avertissement (longueur) |
| `buyer.name` | `ram:BuyerTradeParty/ram:Name` | BT-44 | BR-25 | erreur |
| `buyer.country` | `ram:BuyerTradeParty/ram:PostalTradeAddress/ram:CountryID` | BT-55 | BR-26 | erreur |
| `buyer.siren` | `ram:BuyerTradeParty/ram:SpecifiedLegalOrganization/ram:ID` | BT-47 | BR-46 | erreur |
| `buyer.endpointID` | `ram:BuyerTradeParty/ram:URIUniversalCommunication/ram:URIID` | BT-34 | BR-46 | erreur |
| `buyer.vatNumber` | `ram:BuyerTradeParty/ram:SpecifiedTaxRegistration/ram:ID` | BT-48 | — | — |
| `buyer.street` | `ram:BuyerTradeParty/ram:PostalTradeAddress/ram:LineOne` | BT-50 | — | — |
| `buyer.postcode` | `ram:BuyerTradeParty/ram:PostalTradeAddress/ram:PostcodeCode` | BT-53 | — | — |
| `buyer.city` | `ram:BuyerTradeParty/ram:PostalTradeAddress/ram:CityName` | BT-52 | — | — |
| `buyer.contactName` | `ram:BuyerTradeParty/ram:DefinedTradeContact/ram:PersonName` | BT-56 | — | — |
| `buyer.contactPhone` | `ram:BuyerTradeParty/ram:DefinedTradeContact/ram:TelephoneUniversalCommunication` | BT-57 | — | — |
| `buyer.contactEmail` | `ram:BuyerTradeParty/ram:DefinedTradeContact/ram:EmailURIUniversalCommunication` | BT-58 | — | — |

## Lignes de facture (InvoiceLine)

| Champ application | Balise CII | BT/BG | Règle | Sévérité |
|---|---|---|---|---|
| `line.id` (index) | `ram:AssociatedDocumentLineDocument/ram:LineID` | BT-126 | — | — |
| `line.name` | `ram:SpecifiedTradeProduct/ram:Name` | BT-153 | BR-21 | erreur |
| `line.description` | `ram:SpecifiedTradeProduct/ram:Description` | BT-154 | — | — |
| `line.quantity` | `ram:SpecifiedLineTradeDelivery/ram:BilledQuantity` | BT-129 | BR-16 | erreur |
| `line.unit` | `ram:BilledQuantity/@unitCode` | BT-130 | BR-20 | avertissement |
| `line.unitPrice` | `ram:SpecifiedLineTradeAgreement/ram:NetPriceProductTradePrice/ram:ChargeAmount` | BT-146 | BR-17 | erreur |
| `line.vatRate` | `ram:SpecifiedLineTradeSettlement/ram:ApplicableTradeTax/ram:RateApplicablePercent` | BT-151 | BR-FR-06 | avertissement (négatif) |
| `line.vatCategory` (déduit du taux) | `ram:ApplicableTradeTax/ram:CategoryCode` | BT-151 | — | — |
| `line.lineTotal` | `ram:SpecifiedTradeSettlementLineMonetarySummation/ram:LineTotalAmount` | BT-149 | BR-27 | erreur |
| `line.orderReference` | — (usage interne : rattachement aux commandes, exports ; non émis) | — | — | — |

## Totaux (SpecifiedTradeSettlementHeaderMonetarySummation)

| Champ application | Balise CII | BT/BG | Règle | Sévérité |
|---|---|---|---|---|
| `invoice.lineTotal` (calculé) | `ram:LineTotalAmount` | BT-106 | BR-12 | erreur |
| `invoice.lineTotal` (base TVA) | `ram:TaxBasisTotalAmount` | BT-116 | — | — |
| `invoice.taxTotal` (calculé) | `ram:TaxTotalAmount` | BT-110 | BR-53 | erreur |
| `invoice.grandTotal` (calculé) | `ram:GrandTotalAmount` | BT-112 | BR-13 | erreur |
| `invoice.prepaidAmount` | `ram:TotalPrepaidAmount` | BT-113 | BR-AC-01 | avertissement (solde) |
| `invoice.netToPay` (calculé) | `ram:DuePayableAmount` | BT-115 | BR-CO-16 | erreur (cohérence) |

## Paiement (SpecifiedTradeSettlementPaymentMeans)

| Champ application | Balise CII | BT/BG | Règle | Sévérité |
|---|---|---|---|---|
| `invoice.paymentIBAN` | `ram:PayeePartyCreditorFinancialAccount/ram:IBANID` | BT-90 | BR-50 | avertissement |
| `invoice.paymentBIC` | `ram:PayeeSpecifiedCreditorFinancialInstitution/ram:BICID` | BT-91 | BR-50 | avertissement |
| `invoice.paymentTerms` | `ram:SpecifiedTradePaymentTerms/ram:Description` | BT-20 | — | — |

## Récapitulatif des règles métier

| Règle | Champ concerné | Sévérité | Message |
|---|---|---|---|
| BR-1 | numéro (BT-1) | erreur | Numéro de facture obligatoire |
| BR-2 | date émission (BT-2) | avertissement | Date postérieure à aujourd'hui |
| BR-5 | devise (BT-5) | erreur | Devise obligatoire (ISO 4217) |
| BR-6 | nom émetteur (BT-27) | erreur | Nom de l'émetteur obligatoire |
| BR-7 | pays émetteur (BT-40) | erreur | Pays de l'émetteur obligatoire |
| BR-9 | échéance (BT-9) | avertissement | Échéance antérieure à l'émission |
| BR-13 | total TTC (BT-112) | erreur | Total TTC ≠ HT + TVA |
| BR-12 | total HT (BT-106) | erreur | Total HT ≠ somme des lignes |
| BR-15 | lignes (BG-25) | erreur | Au moins une ligne obligatoire |
| BR-16 | quantité (BT-129) | erreur | Quantité doit être positive |
| BR-17 | prix unitaire (BT-146) | erreur | Prix unitaire non négatif |
| BR-20 | unité (BT-130) | avertissement | Unité non renseignée |
| BR-21 | désignation (BT-153) | erreur | Désignation obligatoire |
| BR-25 | nom destinataire (BT-44) | erreur | Nom du destinataire obligatoire |
| BR-26 | pays destinataire (BT-55) | erreur | Pays du destinataire obligatoire |
| BR-27 | total ligne (BT-149) | erreur | Total ligne ≠ quantité × prix |
| BR-46 | SIREN/endpoint destinataire (BT-34) | erreur | Identifiant destinataire obligatoire |
| BR-49 | SIREN/endpoint émetteur (BT-49) | erreur | Identifiant émetteur obligatoire |
| BR-50 | IBAN (BT-90) | avertissement | Longueur/majuscules IBAN |
| BR-53 | total TVA (BT-110) | erreur | Total TVA ≠ somme par taux |
| BR-AC-01 | acompte payé (BT-113) | avertissement | Solde : acompte attendu |
| BR-CO-16 | net à payer (BT-115) | erreur | BT-115 = BT-112 − BT-113 + BT-114 |
| BR-FR-04 | code type (BT-3) | avertissement | Code type non admis flux FR |
| BR-FR-05 | mentions légales (BT-21) | avertissement | Mentions PMT/PMD/AAB obligatoires FR |
| BR-FR-06 | taux TVA (BT-151) | avertissement | Taux négatif inhabituel |
| BR-FR-CO-05 | facture antérieure (BT-25/26) | erreur | Référence + date obligatoires |
| BR-FR-CO-08 | cadre de facturation (BT-23) | erreur | Cadre 4 (définitive après acompte) interdit sur un acompte (386) |
| BR-FR-CO-09 | cadre de facturation (BT-23) | erreur / avertissement | Cadre 2 (déjà payée) : montant payé (BT-113) = total TTC, net à payer nul ; rappel : échéance = date du paiement |
| BR-FR-MV-02 / BR-FR-BD-02 | cadre de facturation (BT-23) | erreur | Cadres 8 (multi-vendeurs) / 9 (bidirectionnel) : lignes GROUP non produites par l'app |
| BT-157-GTIN | identifiant normalisé de l'article (BT-157) | avertissement | Valeur qui n'est pas un GTIN (émise avec le schéma 0160) — contrôle interne |
| BR-PROFIL | profil (BT-24) | avertissement | Profil limité ; EN 16931 recommandé |

## Notes d'implémentation

- **Encadré rouge** : les champs marqués en erreur sont entourés d'un liseré rouge dans l'éditeur après validation (voir `fieldHighlight` dans `FacturXMacApp.swift`).
- **Code type 387** (facture de solde) : émis en `380` dans le CII car non admis par le flux FR EN16931 ; le type métier interne `finalSettlement` est conservé pour la UI et le calcul du net à payer.
- **internalCreditNote** (INT) : émis en `381` (avoir) dans le CII pour la conformité.
- **TotalPrepaidAmount** : doit suivre `GrandTotalAmount` dans l'ordre du XSD (sinon erreur de validation).
- **Taux de TVA** (BT-119, BT-152, `RateApplicablePercent`) : « 20 » pour un taux entier, « 5.50 » sinon (idem Order-X). BR-FR-16 (France CTC, fatal) compare la chaîne à une liste fermée où « 5.5 » et « 5.50 » passent, mais pas « 5.500 » ni « 6 ». Jusqu'au 2026-09-23, 5,5 % était émis « 6 » : `rate.rounded()` appelait l'extension `Double.rounded(toPlaces:)` du module, qui n'a plus de valeur par défaut.
- Les totaux (lineTotal, taxTotal, grandTotal, netToPay) sont calculés, non saisis ; leurs règles (BR-12/13/53/CO-16) ne sont pas mappées à un champ d'encadré.


## Cadre de facturation (BT-23)

`BillingMode` : la lettre donne la nature de la facture — **B** = biens, **S** = services, **M** = facture double (biens et services non accessoires l'un de l'autre) — et le chiffre le cadre : **1** = dépôt d'une facture, **2** = facture déjà payée, **4** = facture définitive après acompte, **3** = sous-traitance avec paiement direct (commande publique), **5** / **6** = dépôt par un sous-traitant / un cotraitant, **7** = TVA déjà collectée, **8** = facture multi-vendeurs, **9** = facture bidirectionnelle. Libellés d'après le dossier de spécifications externes DGFiP (cas d'usage, v2.3) ; le Schematron France CTC admet ces 20 codes (BR-FR-08).

Contraintes du Schematron France CTC, reprises dans `EN16931BusinessRules` (bloquantes à l'export et au dépôt SUPER PDP) :
- **Cadre 2** (B2/S2/M2) — BR-FR-CO-09 : montant déjà payé (BT-113) = total TTC (BT-112), net à payer (BT-115) = 0, échéance (BT-9) = date du paiement (seule sa présence est vérifiable : rappel en avertissement). Le champ « Montant déjà payé » s'affiche dans l'éditeur dès qu'un cadre 2 est choisi, et `TotalPrepaidAmount` est toujours émis dans ce cadre (même à 0).
- **Cadre 4** (B4/S4/M4) — BR-FR-CO-08 : interdit sur une facture d'acompte (386). `InvoiceStore.newDeposit` ramène un cadre 4 au cadre 1 de même nature ; `newFinalSettlement` passe un cadre 1 au cadre 4 (la facture de solde est la facture définitive après acompte).
- **Cadres 8 et 9** — BR-FR-MV-* / BR-FR-BD-* : exigent des lignes de regroupement par vendeur (sous-type `GROUP`) que le générateur ne produit pas. Plus proposés à la saisie (`BillingMode.selectableCases`) ; une facture existante qui les porte reste affichée, mais son export est bloqué.

## Champs optionnels EN 16931 (catalogue + champs libres)

La section condensée « Champs optionnels » (en-tête + ligne) permet de saisir des champs optionnels du schéma EN 16931 non couverts par les champs dédiés. Chaque entrée couple un nom de balise CII et une valeur. Les champs du catalogue prédéfini (`OptionalFieldCatalogue`) sont émis dans le CII à leur position conforme ; les champs libres sont stockés et affichés mais non émis dans le XML.

| Champ optionnel | Clé (`tagName`) | BT | Émission CII | Remarque |
|---|---|---|---|---|
| Réf. acheteur | `ram:BuyerReference` | BT-10 | `ApplicableHeaderTradeAgreement/BuyerReference` | |
| Réf. projet | `ram:SpecifiedProcuringProject/ram:ID` | BT-11 | `.../SpecifiedProcuringProject/ID` + `Name` | `Name` obligatoire au XSD : valeur conventionnelle « Project reference » |
| Réf. contrat | `ram:ContractReferencedDocument/ram:IssuerAssignedID` | BT-12 | `.../ContractReferencedDocument/IssuerAssignedID` | |
| Réf. bon de réception | `ram:ReceivingAdviceReferencedDocument/ram:IssuerAssignedID` | BT-15 | `ApplicableHeaderTradeDelivery/ReceivingAdviceReferencedDocument` | émis après l'avis d'expédition (ordre du XSD) |
| Réf. bon de livraison | `ram:DespatchAdviceReferencedDocument/ram:IssuerAssignedID` | BT-16 | `ApplicableHeaderTradeDelivery/DespatchAdviceReferencedDocument` | |
| Réf. appel d'offres ou lot | `ram:AdditionalReferencedDocument/ram:IssuerAssignedID` | BT-17 | `.../AdditionalReferencedDocument` (`IssuerAssignedID` + `TypeCode` 50) | ancienne clé `ram:TendererReferencedDocument/...` migrée au décodage |
| N° ligne de commande | `ram:BuyerOrderReferencedDocument/ram:LineID` | BT-132 | `SpecifiedLineTradeAgreement/BuyerOrderReferencedDocument/LineID` | le n° de commande lui-même est le BT-13 (en-tête) |
| Réf. article vendeur | `ram:SellerAssignedID` | BT-155 | `SpecifiedTradeProduct/SellerAssignedID` | |
| Réf. article acheteur | `ram:BuyerAssignedID` | BT-156 | `SpecifiedTradeProduct/BuyerAssignedID` | n'était jamais émis avant le 2026-09-23 |
| Code GTIN (EAN) | `ram:GlobalID` | BT-157 | `SpecifiedTradeProduct/GlobalID` (`schemeID="0160"`) | schemeID exigé par BR-64 ; avertissement BT-157-GTIN si la valeur n'est pas un GTIN |

**Balises de ligne retirées** (`OptionalFieldCatalogue.retiredLineTags`) : `ram:ContractReferencedDocument/ram:IssuerAssignedID` (ex-« Réf. contrat ligne », rejeté par le XSD : pas de contrat par ligne en EN 16931) et `ram:BuyerOrderReferencedDocument/ram:IssuerAssignedID` (ex-« Réf. commande ligne », signalé hors profil par le Schematron EN16931). Les valeurs déjà saisies sont conservées et affichées, avec une aide qui l'explique, mais ne sont plus émises.

**Notes d'implémentation** :
- Les champs optionnels sont persistés sur `Invoice.optionalFields` et `InvoiceLine.optionalFields` (tableaux `OptionalField`, `Codable`, migration via `decodeIfPresent` -> `[]`).
- Ordre d'émission : celui des séquences du XSD (ex. `GlobalID`, `SellerAssignedID`, `BuyerAssignedID` avant `Name` ; avis d'expédition avant avis de réception ; `AdditionalReferencedDocument` entre le contrat et le projet), indépendamment de l'ordre de saisie. `OptionalFieldsConformanceTests` le vérifie.
- Les champs libres (balise non reconnue du catalogue) sont stockés et affichés mais ne sont pas injectés dans le XML pour ne pas risquer de casser la conformité.
- **Vérification (2026-09-23)** : chaque champ du catalogue, seul puis tous ensemble, et chaque cadre de facturation, contre le XSD Factur-X 1.09 EN16931 (`facturx.xml_check_xsd`) et les Schematron EN16931 (`Factur-X_1.09_EN16931.xsl`) et France CTC (`BR-FR-Flux2-Schematron-CII.xslt`), exécutés avec `saxonche`. Attention en relisant un rapport SVRL : le Schematron EN16931 de Factur-X ne pose quasiment jamais `flag="fatal"` (424 assertions sur 427 n'ont aucun flag) et signale les éléments hors profil par des `svrl:successful-report` — ne retenir que `flag="fatal"` masquerait toutes ses erreurs.
