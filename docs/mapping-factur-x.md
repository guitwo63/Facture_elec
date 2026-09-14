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
| `invoice.billingMode` | `ram:BusinessProcessSpecifiedDocumentContextParameter/ram:ID` | BT-23 | — | — |
| `invoice.buyerReference` | `ram:BuyerReference` | BT-10 | — | — |
| `invoice.purchaseOrderRef` | `ram:BuyerOrderReferencedDocument/ram:IssuerAssignedID` | BT-13 | — | — |
| `invoice.contractRef` | `ram:ContractReferencedDocument/ram:IssuerAssignedID` | BT-12 | — | — |
| `invoice.tenderRef` | `ram:TendererReferencedDocument/ram:IssuerAssignedID` | BT-17 | — | — |
| `invoice.receivingAdviceRef` | `ram:ReceivingAdviceReferencedDocument/ram:IssuerAssignedID` | BT-18 | — | — |
| `invoice.despatchAdviceRef` | `ram:DespatchAdviceReferencedDocument/ram:IssuerAssignedID` | BT-19 | — | — |
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
| `line.orderReference` | `ram:BuyerOrderReferencedDocument` (niveau ligne) | BT-132 | — | — |

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
| BR-PROFIL | profil (BT-24) | avertissement | Profil limité ; EN 16931 recommandé |

## Notes d'implémentation

- **Encadré rouge** : les champs marqués en erreur sont entourés d'un liseré rouge dans l'éditeur après validation (voir `fieldHighlight` dans `FacturXMacApp.swift`).
- **Code type 387** (facture de solde) : émis en `380` dans le CII car non admis par le flux FR EN16931 ; le type métier interne `finalSettlement` est conservé pour la UI et le calcul du net à payer.
- **internalCreditNote** (INT) : émis en `381` (avoir) dans le CII pour la conformité.
- **TotalPrepaidAmount** : doit suivre `GrandTotalAmount` dans l'ordre du XSD (sinon erreur de validation).
- Les totaux (lineTotal, taxTotal, grandTotal, netToPay) sont calculés, non saisis ; leurs règles (BR-12/13/53/CO-16) ne sont pas mappées à un champ d'encadré.
