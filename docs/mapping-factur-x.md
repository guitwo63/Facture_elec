# Mapping Factur-X / EN 16931 — champs application ↔ balises CII ↔ règles métier

Table de correspondance entre les champs de l'application (`Sources/FacturXCore/Models.swift`), les balises CII émises (`Sources/FacturXCore/CIIXMLGenerator.swift`) et les règles métier EN 16931 (`Sources/FacturXCore/EN16931BusinessRules.swift`).

**Colonne Règle** : identifiant de la règle qui s'applique au champ (vide = pas de règle spécifique). Les règles en **erreur** bloquent la conformité ; celles en *avertissement* sont signalées sans bloquer.

**Sources des numéros** : numéros BT/BG du modèle sémantique EN 16931 et identifiants de règle tels que les citent les Schematron officiels fournis par le paquet PyPI `factur-x` — EN 16931 : `facturx-en16931/Factur-X_1.09_EN16931.xsl` (les numéros à un chiffre s'y écrivent BR-01…BR-09) ; France CTC : `cii-schematron-fr-ctc/BR-FR-Flux2-Schematron-CII.xslt` (BR-FR-*). BR-CL-04 (liste ISO 4217 des devises), sans identifiant dans le Schematron Factur-X EN16931, est nommée dans les artefacts CEN du même paquet (`cii-extended-ctc-fr/EXTENDED-CTC-FR-CII.xslt`). Un contrôle propre à l'application, sans règle officielle, porte un identifiant interne « BT-<n>-<MOTIF> » (n = terme métier contrôlé), jamais un BR-xx qui désignerait une autre règle officielle.

## En-tête de facture

| Champ application | Balise CII / UBL | BT/BG | Règle | Sévérité |
|---|---|---|---|---|
| `invoice.number` | `rsm:ExchangedDocument/ram:ID` | BT-1 | BR-02 | erreur |
| `invoice.type` | `rsm:ExchangedDocument/ram:TypeCode` | BT-3 | BR-FR-04 | — (respectée à l'émission : 387 émis en 380, INT en 381) |
| `invoice.issueDate` | `rsm:ExchangedDocument/ram:IssueDateTime/udt:DateTimeString` | BT-2 | BT-2-FUTURE (contrôle interne) | avertissement (date future) |
| `invoice.dueDate` | `ram:SpecifiedTradePaymentTerms/ram:DueDateDateTime` | BT-9 | BR-FR-CO-07 | erreur (sauf acompte 386 et cadres B2/S2/M2) |
| `invoice.currency` | `ram:ApplicableHeaderTradeSettlement/ram:InvoiceCurrencyCode` | BT-5 | BR-05 (présence), BR-CL-04 (code ISO 4217) | erreur (code absent de la liste de référence : avertissement) |
| `invoice.profile` | `ram:GuidelineSpecifiedDocumentContextParameter/ram:ID` | BT-24 | BR-PROFIL | erreur (MINIMUM, BASIC WL, BASIC) |
| `invoice.billingMode` | `ram:BusinessProcessSpecifiedDocumentContextParameter/ram:ID` | BT-23 | BR-FR-CO-08, BR-FR-CO-09, BR-FR-MV-02, BR-FR-BD-02 | erreur |
| `invoice.buyerReference` | `ram:BuyerReference` | BT-10 | — | — |
| `invoice.purchaseOrderRef` | `ram:BuyerOrderReferencedDocument/ram:IssuerAssignedID` | BT-13 | — | — |
| `invoice.contractRef` | `ram:ContractReferencedDocument/ram:IssuerAssignedID` | BT-12 | — | — |
| `invoice.tenderRef` | `ram:AdditionalReferencedDocument/ram:IssuerAssignedID` + `ram:TypeCode` = `50` | BT-17 | — | — |
| `invoice.receivingAdviceRef` | `ram:ReceivingAdviceReferencedDocument/ram:IssuerAssignedID` | BT-15 | — | — |
| `invoice.despatchAdviceRef` | `ram:DespatchAdviceReferencedDocument/ram:IssuerAssignedID` | BT-16 | — | — |
| `invoice.deliveryCountry` (champ optionnel) | `ram:ApplicableHeaderTradeDelivery/ram:ShipToTradeParty/ram:PostalTradeAddress/ram:CountryID` — sur une facture K, pays de l'acheteur à défaut de saisie (`effectiveDeliveryCountry`) | BT-80 | BR-IC-12 (respectée à l'émission), BR-CL-14 (code ISO 3166-1), BT-80-UE (contrôle interne) | erreur (code invalide) / avertissement (BT-80-UE) |
| `invoice.precedingInvoiceRef` | `ram:ApplicableHeaderTradeSettlement/.../ram:IssuerAssignedID` (invoiceReferencedXML) | BT-25 | BR-FR-CO-04 (rectificative 384), BR-FR-CO-05 (avoir 381), BT-25-SOLDE (facture de solde, contrôle interne) | erreur |
| `invoice.precedingInvoiceDate` | `ram:ApplicableHeaderTradeSettlement/.../ram:FormattedIssueDateTime` | BT-26 | BR-FR-CO-04, BR-FR-CO-05, BT-25-SOLDE | erreur |
| `invoice.notes` | `ram:IncludedNote/ram:Content` (sans SubjectCode) ; pas émise si vide ou faite d'espaces | BT-22 | — | — |
| `invoice.legalNotePMT` | `ram:IncludedNote/ram:Content` + `ram:SubjectCode` = `PMT` | BT-22 (BT-21 = PMT) | BR-FR-05 | erreur (facture émise) |
| `invoice.legalNotePMD` | `ram:IncludedNote/ram:Content` + `ram:SubjectCode` = `PMD` | BT-22 (BT-21 = PMD) | BR-FR-05 | erreur (facture émise) |
| `invoice.legalNoteAAB` | `ram:IncludedNote/ram:Content` + `ram:SubjectCode` = `AAB` | BT-22 (BT-21 = AAB) | BR-FR-05 | erreur (facture émise) |

Les notes (BT-22) sont émises sans leurs espaces de début et de fin, comme sur le PDF. Une note vide ou faite d'espaces n'est pas émise : `<ram:Content>   </ram:Content>` est un élément vide pour PEPPOL-EN16931-R008, et SUPER PDP répond alors `is_valid=false`. Une mention légale dans ce cas manque donc au XML, et BR-FR-05 bloque la facture. BR-FR-05 est fatale dans le Schematron France CTC. SUPER PDP la range dans les avertissements (validateur `…_WARNING.xslt`, `flag="warning"`) mais répond quand même `is_valid=false` pour chacune des trois mentions, sur un 380, un 381 ou un 386 (vérifié le 2026-09-23 sur des factures fictives).

## Émetteur / Destinataire (Party)

| Champ application | Balise CII | BT/BG | Règle | Sévérité |
|---|---|---|---|---|
| `seller.name` | `ram:SellerTradeParty/ram:Name` | BT-27 | BR-06 | erreur |
| `seller.country` | `ram:SellerTradeParty/ram:PostalTradeAddress/ram:CountryID` | BT-40 | BR-09 | erreur |
| `seller.siren` | `ram:SellerTradeParty/ram:SpecifiedLegalOrganization/ram:ID` (schéma 0002) | BT-30 | BR-FR-10 (9 chiffres, clé Luhn), BR-FR-13 (SIREN ou identifiant électronique) | avertissement (format) / erreur (ni l'un ni l'autre) |
| `seller.siret` | — (non émis ; serait le BT-29, schéma 0009) | — | BR-FR-09 (14 chiffres, clé Luhn) | avertissement |
| `seller.endpointID` | `ram:SellerTradeParty/ram:URIUniversalCommunication/ram:URIID` (schéma 0225 ; déduit du SIREN si vide) | BT-34 | BR-FR-13 | erreur |
| `seller.vatNumber` | `ram:SellerTradeParty/ram:SpecifiedTaxRegistration/ram:ID` | BT-31 | BR-CO-09 (préfixe pays), BR-S-02 / BR-E-02 / BR-Z-02 / BR-IC-02 (obligatoire avec une ligne S / E / Z / K), BR-O-02 (interdit avec une ligne O, hors EXTENDED) | erreur |
| `seller.street` | `ram:SellerTradeParty/ram:PostalTradeAddress/ram:LineOne` | BT-35 | — | — |
| `seller.postcode` | `ram:SellerTradeParty/ram:PostalTradeAddress/ram:PostcodeCode` | BT-38 | — | — |
| `seller.city` | `ram:SellerTradeParty/ram:PostalTradeAddress/ram:CityName` | BT-37 | — | — |
| `seller.contactName` | `ram:SellerTradeParty/ram:DefinedTradeContact/ram:PersonName` | BT-41 | — | — |
| `seller.contactPhone` | `ram:SellerTradeParty/ram:DefinedTradeContact/ram:TelephoneUniversalCommunication` | BT-42 | — | — |
| `seller.contactEmail` | `ram:SellerTradeParty/ram:DefinedTradeContact/ram:EmailURIUniversalCommunication` | BT-43 | — | — |
| `seller.iban` | recopié dans `invoice.paymentIBAN` au choix du tiers (voir Paiement) | BT-84 | BT-84-IBAN (contrôle interne) | voir Paiement |
| `buyer.name` | `ram:BuyerTradeParty/ram:Name` | BT-44 | BR-07 | erreur |
| `buyer.country` | `ram:BuyerTradeParty/ram:PostalTradeAddress/ram:CountryID` | BT-55 | BR-11 | erreur |
| `buyer.siren` | `ram:BuyerTradeParty/ram:SpecifiedLegalOrganization/ram:ID` (schéma 0002) | BT-47 | BR-FR-32 (9 chiffres, clé Luhn ; BR-FR-11 ne vaut qu'avec une note BAR = B2B, non émise), BR-FR-12 (SIREN ou identifiant électronique) | avertissement (format) / erreur (ni l'un ni l'autre) |
| `buyer.siret` | — (non émis ; serait le BT-46, schéma 0009) | — | BR-FR-09 (14 chiffres, clé Luhn) | avertissement |
| `buyer.endpointID` | `ram:BuyerTradeParty/ram:URIUniversalCommunication/ram:URIID` (schéma 0225 ; déduit du SIREN si vide) | BT-49 | BR-FR-12 | erreur |
| `buyer.vatNumber` | `ram:BuyerTradeParty/ram:SpecifiedTaxRegistration/ram:ID` | BT-48 | BR-CO-09 (préfixe pays), BR-IC-02 (obligatoire avec une ligne K), BR-O-02 (interdit avec une ligne O, hors EXTENDED) | erreur |
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
| `line.name` | `ram:SpecifiedTradeProduct/ram:Name` | BT-153 | BR-25 | erreur |
| `line.description` | `ram:SpecifiedTradeProduct/ram:Description` | BT-154 | — | — |
| `line.quantity` | `ram:SpecifiedLineTradeDelivery/ram:BilledQuantity` | BT-129 | BT-129-POSITIVE (contrôle interne : EN 16931 admet une quantité nulle ou négative) | erreur |
| `line.unit` | `ram:BilledQuantity/@unitCode` (C62 si vide ; les unités proposées sont toutes dans la liste du Schematron, UN/ECE Rec 20 et Rec 21, BR-CL-23 : voir `UnitCodeListTests`) | BT-130 | BR-23 | avertissement |
| `line.unitPrice` | `ram:SpecifiedLineTradeAgreement/ram:NetPriceProductTradePrice/ram:ChargeAmount` | BT-146 | BR-27 | erreur |
| `line.vatRate` | `ram:SpecifiedLineTradeSettlement/ram:ApplicableTradeTax/ram:RateApplicablePercent` (absent en catégorie O : BR-O-05) | BT-152 | BR-Z-05, BR-E-05, BR-AE-05, BR-IC-05, BR-G-05, BR-O-05 (taux non nul hors catégorie S) et BR-S-05 (taux nul ou négatif en catégorie S) ; BR-FR-16 (taux hors de la liste des taux français) ; BT-152-ZERO (rappel, contrôle interne) | erreur ; erreur ; avertissement |
| `line.vatCategory` (suit le taux saisi : S, ou E à 0 %, voir « Catégorie de TVA d'une ligne à 0 % ») | `ram:ApplicableTradeTax/ram:CategoryCode` | BT-151 | BR-O-12 (une ligne O exclut toute autre catégorie, hors EXTENDED) | erreur |
| `line.vatExemptionReason` | `ram:ApplicableHeaderTradeSettlement/ram:ApplicableTradeTax/ram:ExemptionReason` (ventilation de TVA ; émis seulement en E, AE, K, G et O, BR-S-10 et BR-Z-10 l'interdisant en S et en Z) | BT-120 | BR-E-10, BR-AE-10, BR-IC-10, BR-G-10, BR-O-10 | erreur |
| `line.lineTotal` | `ram:SpecifiedTradeSettlementLineMonetarySummation/ram:LineTotalAmount` | BT-131 | BT-131-CALCUL (contrôle interne : quantité × prix unitaire) | erreur |
| `line.orderReference` | — (usage interne : rattachement aux commandes, exports ; non émis) | — | — | — |

## Totaux (SpecifiedTradeSettlementHeaderMonetarySummation)

| Champ application | Balise CII | BT/BG | Règle | Sévérité |
|---|---|---|---|---|
| `invoice.lineTotal` (calculé) | `ram:LineTotalAmount` | BT-106 | BR-CO-10 | erreur |
| `invoice.lineTotal` (base TVA) | `ram:TaxBasisTotalAmount` | BT-109 | — | — |
| `invoice.taxTotal` (calculé) | `ram:TaxTotalAmount` | BT-110 | BR-CO-14 | erreur |
| `invoice.grandTotal` (calculé) | `ram:GrandTotalAmount` | BT-112 | BR-CO-15 | erreur |
| `invoice.prepaidAmount` | `ram:TotalPrepaidAmount` | BT-113 | BT-113-SOLDE (facture de solde, contrôle interne) ; BR-FR-CO-09 (cadre 2) | avertissement ; erreur |
| `invoice.netToPay` (calculé) | `ram:DuePayableAmount` | BT-115 | BR-CO-16 | — (respectée par construction, non contrôlée) |

## Paiement (SpecifiedTradeSettlementPaymentMeans)

| Champ application | Balise CII | BT/BG | Règle | Sévérité |
|---|---|---|---|---|
| `invoice.paymentIBAN` | `ram:PayeePartyCreditorFinancialAccount/ram:IBANID` | BT-84 | BT-84-IBAN (contrôle interne : BR-50/BR-61 n'exigent que la présence) | erreur (clé mod 97) / avertissement (longueur, casse) |
| `invoice.paymentBIC` | `ram:PayeeSpecifiedCreditorFinancialInstitution/ram:BICID` | BT-86 | — | — |
| `invoice.paymentTerms` | `ram:SpecifiedTradePaymentTerms/ram:Description` | BT-20 | — | — |

## Récapitulatif des règles métier

| Règle | Champ concerné | Sévérité | Message |
|---|---|---|---|
| BR-02 | numéro (BT-1) | erreur | Numéro de facture obligatoire |
| BR-05 | devise (BT-5) | erreur | Devise obligatoire |
| BR-06 | nom émetteur (BT-27) | erreur | Nom de l'émetteur obligatoire |
| BR-07 | nom destinataire (BT-44) | erreur | Nom du destinataire obligatoire |
| BR-09 | pays émetteur (BT-40) | erreur | Pays de l'émetteur obligatoire |
| BR-11 | pays destinataire (BT-55) | erreur | Pays du destinataire obligatoire |
| BR-16 | lignes (BG-25) | erreur | Au moins une ligne obligatoire |
| BR-23 | unité (BT-130) | avertissement | Unité non renseignée (C62 émis par défaut) |
| BR-25 | désignation (BT-153) | erreur | Désignation obligatoire |
| BR-27 | prix unitaire (BT-146) | erreur | Prix unitaire non négatif |
| BR-CL-04 | devise (BT-5) | erreur / avertissement | Code ISO 4217 à 3 lettres ; avertissement si absent de la liste de référence |
| BR-CL-14 | pays de livraison (BT-80) | erreur | Code pays ISO 3166-1 (liste du Schematron : plus 1A et XI) |
| BR-CO-09 | n° TVA émetteur / destinataire (BT-31 / BT-48) | erreur | Préfixe pays ISO 3166-1 alpha-2 (EL admis pour la Grèce) |
| BR-CO-10 | total HT (BT-106) | erreur | Total HT ≠ somme des montants nets de ligne (BT-131) |
| BR-CO-14 | total TVA (BT-110) | erreur | Total TVA ≠ somme des montants de TVA par taux (BT-117) |
| BR-CO-15 | total TTC (BT-112) | erreur | Total TTC ≠ total HT (BT-109) + total TVA (BT-110) |
| BR-S-02 / BR-E-02 / BR-Z-02 | n° TVA émetteur (BT-31) | erreur | Obligatoire avec une ligne à TVA normale (S) / exonérée (E) / à taux zéro (Z), d'après la catégorie de la ligne |
| BR-IC-02 | n° TVA émetteur et acheteur (BT-31, BT-48) | erreur | Tous deux obligatoires avec une ligne en livraison intracommunautaire (K) |
| BR-O-02 / BR-O-12 | n° TVA (BT-31, BT-48) / catégorie de TVA (BT-151) | erreur | Facture avec une ligne hors champ de TVA (O), hors EXTENDED : aucun n° TVA ; aucune ligne d'une autre catégorie (BR-O-11 : une seule ventilation) |
| BR-Z-05, BR-E-05, BR-AE-05, BR-IC-05, BR-G-05, BR-O-05 | taux de TVA (BT-152) | erreur | Taux non nul avec une catégorie autre que S (catégorie K : règles BR-IC-*) |
| BR-S-05 | taux de TVA (BT-152) | erreur | Taux nul ou négatif en catégorie S (ligne à 0 % mise en « Taux normal » ; le menu Catégorie d'une ligne à 0 % ne propose plus S) |
| BR-E-10, BR-AE-10, BR-IC-10, BR-G-10, BR-O-10 | motif d'exonération (BT-120) | erreur | Motif obligatoire pour la catégorie de TVA (BT-151) de la ligne |
| BR-FR-04 | code type (BT-3) | — | Respectée à l'émission : 387 émis en 380, INT en 381 |
| BR-FR-05 | mentions légales (BT-22, BT-21 = PMT/PMD/AAB) | erreur | Mentions PMT/PMD/AAB obligatoires FR sur une facture émise, quel qu'en soit le type ; vide ou faite d'espaces = absente ; facture reçue : non contrôlée |
| BR-FR-09 | SIRET émetteur / destinataire | avertissement | 14 chiffres, clé Luhn (SIRET non émis dans le XML) |
| BR-FR-10 | SIREN émetteur (BT-30) | avertissement | 9 chiffres, clé Luhn |
| BR-FR-12 | identifiant électronique destinataire (BT-49) | erreur | SIREN ou identifiant électronique obligatoire (BT-49 déduit du SIREN si vide) |
| BR-FR-13 | identifiant électronique émetteur (BT-34) | erreur | SIREN ou identifiant électronique obligatoire (BT-34 déduit du SIREN si vide) |
| BR-FR-16 | taux de TVA (BT-152) | erreur | Taux absent de la liste fermée des taux français (0 ; 0,9 ; 1,05 ; 1,75 ; 2,1 ; 5,5 ; 7 ; 8,5 ; 9,2 ; 9,6 ; 10 ; 13 ; 19,6 ; 20 ; 20,6), comparé sous sa forme émise ; facture reçue : taux négatif seulement, en avertissement |
| BR-FR-32 | SIREN destinataire (BT-47) | avertissement | 9 chiffres (schéma 0002), clé Luhn |
| BR-FR-CO-04 | facture antérieure (BT-25/26) | erreur | Facture rectificative (384) : référence + date obligatoires |
| BR-FR-CO-05 | facture antérieure (BT-25/26) | erreur | Avoir (381) : référence + date obligatoires |
| BR-FR-CO-07 | échéance (BT-9) | erreur | Échéance antérieure à la date de facture (BT-2), au jour près dans le XML ; admise seulement pour un acompte (386) ou un cadre déjà payée (B2/S2/M2) |
| BR-FR-CO-08 | cadre de facturation (BT-23) | erreur | Cadre 4 (définitive après acompte) interdit sur un acompte (386) |
| BR-FR-CO-09 | cadre de facturation (BT-23) | erreur / avertissement | Cadre 2 (déjà payée) : montant payé (BT-113) = total TTC, net à payer nul ; rappel : échéance = date du paiement |
| BR-FR-MV-02 / BR-FR-BD-02 | cadre de facturation (BT-23) | erreur | Cadres 8 (multi-vendeurs) / 9 (bidirectionnel) : lignes GROUP non produites par l'app |
| BT-2-FUTURE | date d'émission (BT-2) | avertissement | Date postérieure à aujourd'hui — contrôle interne |
| BT-25-SOLDE | facture antérieure (BT-25/26) | erreur | Facture de solde (émise en 380) : référence à l'acompte obligatoire — contrôle interne |
| BT-80-UE | pays de livraison (BT-80) | avertissement | Livraison intracommunautaire (K) vers le pays de l'émetteur ou hors de l'UE — contrôle interne |
| BT-84-IBAN | IBAN (BT-84) | erreur / avertissement | Clé mod 97 ; longueur, casse — contrôle interne |
| BT-113-SOLDE | montant déjà payé (BT-113) | avertissement | Facture de solde sans montant d'acomptes — contrôle interne |
| BT-129-POSITIVE | quantité (BT-129) | erreur | Quantité doit être positive — contrôle interne |
| BT-131-CALCUL | montant net de ligne (BT-131) | erreur | Montant net ≠ quantité × prix unitaire — contrôle interne |
| BT-152-ZERO | taux de TVA (BT-152) | avertissement | Taux nul en catégorie Z, rare en France : choisir E (exonérée, avec motif) pour une opération exonérée, sinon vérifier que le taux n'a pas été oublié — contrôle interne |
| BT-157-GTIN | identifiant normalisé de l'article (BT-157) | avertissement | Valeur qui n'est pas un GTIN (émise avec le schéma 0160) — contrôle interne |
| BR-PROFIL | profil (BT-24) | erreur | Profil MINIMUM, BASIC WL ou BASIC : XML non conforme au XSD du profil, export bloqué — contrôle interne |

## Notes d'implémentation

- **Encadré rouge** : les champs marqués en erreur sont entourés d'un liseré rouge dans l'éditeur après validation (voir `fieldHighlight` dans `InvoicesTabView.swift`).
- **Dates du XML** : format 102 (AAAAMMJJ), dans le **fuseau de l'application** (`NSTimeZone.default`, le fuseau du Mac). Le XML porte donc le jour affiché dans l'éditeur et imprimé sur le PDF, quelle que soit l'heure enregistrée avec la date. Point unique : `DocumentDate`, utilisé par `CIIXMLGenerator.xmlDate` (BT-2, BT-9, BT-26, date de livraison), `CIIXMLParser`, `OrderCIOXMLGenerator` et les métadonnées XMP du PDF (« Invoice … dated AAAA-MM-JJ »). Le parseur place le jour lu à midi dans ce fuseau : l'aller-retour parseur → générateur redonne la même date, et le jour affiché tient si le fuseau du Mac change ensuite (jusqu'à ±11 h). BR-FR-CO-07 compare les chaînes écrites dans le XML, comme le Schematron France CTC : une échéance du même jour que la facture est admise quelle que soit l'heure enregistrée. Historique : les dates étaient écrites en UTC. À Paris, un instant entre 00:00 et 01:00 (02:00 en été) s'écrivait donc la veille : échéances « fin de mois », calculées à 00:00 (un jour plus tôt que sur le PDF, et « fin de mois + 0 jour » au dernier jour du mois rejeté par BR-FR-CO-07), et factures créées juste après minuit. Régénérer une telle facture donne désormais un XML daté du lendemain de l'ancien, conforme à son PDF.
- **Code type 387** (facture de solde) : émis en `380` dans le CII car non admis par le flux FR EN16931 ; le type métier interne `finalSettlement` est conservé pour la UI et le calcul du net à payer.
- **internalCreditNote** (INT) : émis en `381` (avoir) dans le CII pour la conformité.
- **TotalPrepaidAmount** : doit suivre `GrandTotalAmount` dans l'ordre du XSD (sinon erreur de validation).
- **Identifiants vides** : un n° TVA (BT-31/BT-48) ou un SIREN (BT-30/BT-47) vidé dans l'éditeur est enregistré `""`, pas `nil`. Le générateur n'émet que la valeur rognée non vide : l'identifiant vide qu'il émettait était rejeté par BR-CO-09 (n° TVA) ou BR-FR-32 (SIREN), sans que l'application ne le signale, et un n° TVA vide comptait comme présent pour BR-O-02 (vérifié le 2026-09-23 contre les Schematron EN16931 et France CTC).
- **Taux de TVA** (BT-119, BT-152, `RateApplicablePercent`) : « 20 » pour un taux entier, « 5.50 » sinon (idem Order-X). Le BR-FR-16 du Schematron France CTC (fatal) compare la chaîne à une liste fermée où « 5.5 » et « 5.50 » passent, mais pas « 5.500 » ni « 6 » ; le contrôle BR-FR-16 de l'app compare cette même chaîne (`CIIXMLGenerator.xmlRate`) à la liste et bloque l'export, sauf sur une facture reçue, où seul un taux négatif est signalé. Jusqu'au 2026-09-23, 5,5 % était émis « 6 » : `rate.rounded()` appelait l'extension `Double.rounded(toPlaces:)` du module, qui n'a plus de valeur par défaut.
- **Catégorie de TVA d'une ligne à 0 %** : dans les éditeurs (facture, commande, achat, devis, « Facture guidée »), passer une ligne à 0 % la met en catégorie E « Exonérée ». Son motif (BT-120) est à saisir, et l'export reste bloqué tant qu'il manque (BR-E-10). Les autres catégories (Z, AE, K, G, O) se choisissent dans le menu Catégorie, sous la ligne. Un taux non nul remet la ligne en S et efface le motif. Point unique : `InvoiceLine.setVATRate(_:)`. « Ajouter une ligne » reprend le taux, la catégorie et le motif de la ligne précédente (`InvoiceLine.blank(after:)`). Jusqu'au 2026-09-23, 0 % donnait Z « Taux zéro », rare en France, sous le libellé « 0 % — Exonéré ». Les lignes enregistrées gardent leur catégorie, et une ancienne ligne sans catégorie est toujours relue en Z à 0 %, comme elle a été émise.
- **Catégorie O (hors champ de TVA)** : ni taux de ligne (BT-152, interdit par BR-O-05 dans les Schematron EN16931 comme EXTENDED) ni taux de ventilation (BT-119 : facultatif, BR-48 exemptant O ; omis par cohérence) ; le modèle garde `vatRate` = 0 et `CIIXMLParser` relit une ligne sans taux à 0 % hors catégorie S. BR-O-02 et BR-O-11/12 n'existent que dans le Schematron EN16931, d'où leur blocage hors EXTENDED. Vérifié le 2026-09-23 (XSD, Schematron EN16931, EXTENDED, EXTENDED-CTC-FR et France CTC). Avertissement EXTENDED connu, non bloquant et antérieur, aussi en catégorie E : BR-FXEXT-<catégorie>-08rev regroupe les lignes par motif d'exonération porté sur la ligne, que le générateur n'émet que dans la ventilation.
- Les totaux (lineTotal, taxTotal, grandTotal, netToPay) sont calculés, non saisis ; leurs règles (BR-CO-10/14/15, et BR-CO-16 respectée par construction) ne sont pas mappées à un champ d'encadré.


## Cadre de facturation (BT-23)

`BillingMode` : la lettre donne la nature de la facture — **B** = biens, **S** = services, **M** = facture double (biens et services non accessoires l'un de l'autre) — et le chiffre le cadre : **1** = dépôt d'une facture, **2** = facture déjà payée, **4** = facture définitive après acompte, **3** = sous-traitance avec paiement direct (commande publique), **5** / **6** = dépôt par un sous-traitant / un cotraitant, **7** = TVA déjà collectée, **8** = facture multi-vendeurs, **9** = facture bidirectionnelle. Libellés d'après le dossier de spécifications externes DGFiP (cas d'usage, v2.3) ; le Schematron France CTC admet ces 20 codes (BR-FR-08).

Contraintes du Schematron France CTC, reprises dans `EN16931BusinessRules` (bloquantes à l'export et au dépôt SUPER PDP) :
- **Cadre 2** (B2/S2/M2) — BR-FR-CO-09 : montant déjà payé (BT-113) = total TTC (BT-112), net à payer (BT-115) = 0, échéance (BT-9) = date du paiement (seule sa présence est vérifiable : rappel en avertissement), qui peut donc précéder la date de facture (exception à BR-FR-CO-07, comme les acomptes). Le champ « Montant déjà payé » s'affiche dans l'éditeur dès qu'un cadre 2 est choisi, et `TotalPrepaidAmount` est toujours émis dans ce cadre (même à 0).
- **Cadre 4** (B4/S4/M4) — BR-FR-CO-08 : interdit sur une facture d'acompte (386). `InvoiceStore.newDeposit` ramène un cadre 4 au cadre 1 de même nature ; `newFinalSettlement` passe un cadre 1 au cadre 4 (la facture de solde est la facture définitive après acompte).
- **Cadres 8 et 9** — BR-FR-MV-* / BR-FR-BD-* : exigent des lignes de regroupement par vendeur (sous-type `GROUP`) que le générateur ne produit pas. Plus proposés à la saisie (`BillingMode.selectableCases`) ; une facture existante qui les porte reste affichée, mais son export est bloqué.

## Profil Factur-X (BT-24)

`CIIXMLGenerator` produit toujours la structure du profil EN 16931 et ne change que l'URN du profil (`FacturXProfile.urn`). Ce XML est conforme en EN 16931 et en EXTENDED, qui englobe EN 16931, mais pas dans les profils plus restreints.

**Mesure du 2026-09-23** : 36 cas de facture (exemple des tests, socle sans champ facultatif, chaque champ optionnel seul, contacts, IBAN/BIC, avoir, rectificative, acompte, solde, cadre 2, catégories de TVA, tout ensemble) × 5 profils, validés contre le XSD et le Schematron Factur-X 1.09 **du profil déclaré** et contre le Schematron France CTC (paquet `factur-x` 6.8, Schematron exécutés avec `saxonche`). Pour chaque XML rejeté, les éléments refusés ont été retirés un à un jusqu'à validation, pour obtenir la liste complète de ce que le profil ne peut pas porter.

| Profil | XSD valide | Données de l'app que le profil ne peut pas porter |
|---|---|---|
| MINIMUM | 0/36 | Lignes, notes (dont les mentions légales PMT/PMD/AAB), adresses postales hors pays, adresses électroniques BT-34/BT-49, date de livraison, ventilation de TVA, échéance et conditions de paiement, total des lignes, IBAN/BIC, contacts, BT-11/12/15/16/17, n° de TVA de l'acheteur. Même réduit à ce qu'il admet, le XML reste rejeté par le Schematron France CTC (BR-FR-05, BR-FR-12, BR-FR-13). |
| BASIC WL | 0/36 | Lignes (BG-25) dans tous les cas ; en outre contacts vendeur/acheteur, `ram:Information` « SEPA » (BT-82, émis avec tout IBAN), BIC (BT-86), BT-11, BT-15, BT-17. |
| BASIC | 22/36 | Contacts vendeur/acheteur, `ram:Information` « SEPA » (toute facture avec IBAN est donc rejetée), BIC, BT-11, BT-15, BT-17 ; sur les lignes : BT-132, BT-154 (description), BT-155, BT-156. |
| EN 16931 | 36/36 | — |
| EXTENDED | 36/36 | — |

**Règle retenue** (option « EN 16931 + EXTENDED ») :
- Seuls EN 16931 et EXTENDED sont proposés à la saisie (`FacturXProfile.selectableCases`) ; un ancien profil déjà enregistré sur une société reste affiché dans son sélecteur (réglages), avec un avertissement.
- Une nouvelle facture n'hérite jamais d'un ancien profil (`FacturXProfile.forNewInvoice`) : création depuis la société, doublon, avoir, acompte et solde passent en EN 16931.
- Une facture émise encore en MINIMUM, BASIC WL ou BASIC est bloquée à l'export et au dépôt (BR-PROFIL, erreur). L'éditeur affiche alors un sélecteur « Profil Factur-X (BT-24) », et seulement dans ce cas, pour la repasser en EN 16931 ou EXTENDED.
- Tous les profils restent décodables : factures existantes, et factures reçues dont le profil est lu dans le XML (`CIIXMLParser`). BR-PROFIL ne s'applique pas à une facture reçue (`EN16931RuleContext.received`).

## Livraison intracommunautaire (catégorie K) et pays de livraison (BT-80)

Règles BR-IC-* du Schematron EN16931, présentes aussi dans celui d'EXTENDED (hormis BR-IC-01 et BR-IC-08, respectées par construction : la ventilation de TVA est calculée à partir des lignes) :
- **BR-IC-12** — pays de livraison (BT-80) obligatoire. Le générateur émet `ApplicableHeaderTradeDelivery/ShipToTradeParty/PostalTradeAddress/CountryID`, premier enfant de la livraison dans la séquence du XSD, avec le pays saisi dans le champ optionnel « Pays de livraison » (BT-80), mis en majuscules, ou à défaut **le pays de l'acheteur (BT-55)**, le bien partant en général à son adresse (`Invoice.effectiveDeliveryCountry`). Le livré à se réduit au pays, seule donnée de livraison que l'application connaît. BT-80 n'est pas imprimé sur le PDF, comme les autres champs optionnels d'en-tête (décision de l'utilisateur du 2026-09-23). Hors catégorie K, BT-80 n'est émis que s'il est saisi : le XML d'une facture sans K ni BT-80 est inchangé à l'octet près.
- **BR-IC-11** — date de livraison (BT-72) ou période de facturation (BG-14) : respectée par construction, le générateur émet toujours une date de livraison (la date de facture).
- **BR-IC-02** — n° de TVA de l'émetteur (BT-31) et de l'acheteur (BT-48) : erreur bloquante. Le représentant fiscal (BT-63), que la règle admet à la place du BT-31, n'est pas géré par l'application : le BT-31 est donc exigé.
- **BR-IC-05 / BR-IC-10** — taux nul et motif d'exonération (BT-120) : contrôlés par les règles de catégorie de TVA des lignes.
- **BR-CL-14** — un pays de livraison saisi doit figurer dans la liste du Schematron (ISO 3166-1, plus 1A pour le Kosovo et XI pour l'Irlande du Nord) : erreur bloquante, que la facture soit en catégorie K ou non. Erreurs typiques : EL (préfixe de TVA de la Grèce, dont le code pays est GR) et UK (GB).
- **BT-80-UE** (contrôle interne, avertissement) : un BT-80 accepté par le Schematron peut rester incohérent avec la catégorie K, par exemple une livraison vers le pays de l'émetteur (le repli sur un acheteur établi en France), ou hors de l'UE, ce qui relève de l'exportation (catégorie G). Le message indique quand le pays vient du repli sur l'acheteur.

Relecture (`CIIXMLParser`) : BT-80 est lu dans le livré à d'en-tête, sous le même champ optionnel. Le sous-arbre `ShipToTradeParty` est isolé : ses éléments portent les noms de ceux du vendeur et de l'acheteur, et la fermeture de son adresse faisait basculer la lecture sur l'acheteur, ce qui perdait les avis d'expédition et de réception (BT-16, BT-15) qui le suivent.

**Vérification (2026-09-23)** : 14 factures, dont 12 en catégorie K (BT-80 par défaut, saisi, en minuscules, invalide, hors UE ; K + S ; profil EXTENDED ; avec avis d'expédition et de réception ; tous les champs optionnels ; n° de TVA manquant), contre le XSD Factur-X 1.09 et le Schematron du profil déclaré (EN16931 ou EXTENDED) et contre le Schematron France CTC. Avant : les 12 factures K étaient rejetées (BR-IC-12, et en plus BR-IC-02 pour deux d'entre elles) alors que l'application autorisait l'export. Après : validateurs officiels et application rendent le même verdict dans les 14 cas.

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
| Pays de livraison | `ram:ShipToTradeParty/ram:PostalTradeAddress/ram:CountryID` | BT-80 | `ApplicableHeaderTradeDelivery/ShipToTradeParty/PostalTradeAddress/CountryID` | premier enfant de la livraison, mis en majuscules ; sur une facture K, pays de l'acheteur à défaut de saisie (voir la section catégorie K) |
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

## Order-X (commandes) : structure par profil

`OrderCIOXMLGenerator` suit le XSD du profil que la commande déclare (`OrderXProfile`, URN `urn:order-x.eu:1p0:…`) :

| Profil | Récapitulatif de TVA d'en-tête (`ApplicableTradeTax`) | TVA de ligne | Description de ligne |
|---|---|---|---|
| BASIC | non | non | non |
| COMFORT | non | oui | oui |
| EXTENDED | oui | oui | oui |

Dans les trois profils, la référence de commande (`BuyerOrderReferencedDocument`) précède celle du devis (`QuotationReferencedDocument`), et le total de TVA (`TaxTotalAmount`) reste émis. **Vérification (2026-09-23)** : pour chaque profil, une commande minimale et une commande complète (références, contacts, description, trois taux dont une exonération) passent le XSD et le Schematron Order-X de ce profil (paquet `factur-x`, dossiers `orderx-<profil>/`). Avant ce correctif, seul EXTENDED passait, et seulement sans référence de devis. Le Schematron Order-X ne contrôle ni les taux ni le code type du document.
