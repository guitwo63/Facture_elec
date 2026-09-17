# FacturXMacApp

Application macOS native (SwiftUI) qui génère des **factures électroniques au format Factur-X** (profil **EN 16931**), conformes à la réforme française de la facturation électronique.

Une facture Factur-X est un **PDF/A-3** contenant un fichier **XML Cross Industry Invoice (CII)** embarqué sous le nom `factur-x.xml` avec `/AFRelationship /Alternative`, accompagné des métadonnées XMP Factur-X.

## Conformité

- **Profil** : EN 16931 (URN `urn:cen.eu:en16931:2017`) — le profil de référence européen, recommandé pour la majorité des PME.
- **XML CII** : généré selon le schéma UN/CEFACT D22B. La structure et l'ordre des éléments suivent strictement le XSD officiel Factur-X 1.09 EN 16931. La logique de génération a été **validée contre le XSD officiel** via la librairie de référence `factur-x` (Python) — voir `ref/gen_swift_mirror.py`.
- **Profils supportés** : MINIMUM, BASIC WL, BASIC, EN 16931, EXTENDED (URN officielles FNFE-MPE).
- **Conteneur PDF/A-3** : le PDF embarque le XML en pièce jointe (`/EmbeddedFiles` + `/AF`), avec `/AFRelationship /Alternative` et le bloc XMP `fx:` (DocumentType, DocumentFileName, Version, ConformanceLevel) et `pdfaid:part=3`.

> Note : le conteneur produit est conforme à la structure Factur-X (XML + XMP + AF). La certification PDF/A-3 **stricte** (validation veraPDF) exige un *output intent* ICC (profil sRGB). Pour une conformité PDF/A-3 complète, validez et complétez si besoin avec Mustang/veraPDF — voir « Validation » ci-dessous.

## Contenu

```
FacturXMacApp/
├── Package.swift                 # Swift Package (macOS 13+)
├── Sources/
│   ├── FacturXCore/              # Bibliothèque (testable, sans UI)
│   │   ├── Models.swift           # Invoice, InvoiceParty, InvoiceLine, profils
│   │   ├── CIIXMLGenerator.swift  # Générateur XML CII EN 16931
│   │   ├── InvoicePDFRenderer.swift   # Rendu PDF lisible (CoreGraphics)
│   │   ├── FacturXEmbedder.swift  # Embarquement PDF/A-3 + XMP
│   │   ├── FacturXValidator.swift # Validation interne (données + PDF)
│   │   ├── FacturXGenerator.swift # Façade
│   │   ├── InvoiceStore.swift     # Persistance (UserDefaults)
│   │   └── Auth.swift            # Utilisateurs, rôles, périmètre sociétés
│   └── FacturXMacApp/            # App SwiftUI (menu, fenêtres, édition)
│       ├── FacturXMacApp.swift
│       └── AuthViews.swift       # Connexion, administration users/sociétés
└── Tests/FacturXCoreTests/       # Tests unitaires (montants, XML, embarquement, auth)
```

## Gestion des utilisateurs et périmètre

L'application intègre une connexion par **identifiant / mot de passe** (hachage SHA256 + sel itéré) et deux profils :

- **Administrateur** : accès à toutes les factures et à la **Gestion utilisateurs** (bouton à droite de la barre d'outils).
- **Comptable client** : ne voit et ne crée que les factures **rattachées à une des sociétés de son périmètre**.

Le **périmètre** est fondé sur la **structure des tiers** de l'annuaire : une société du périmètre est une **fiche société** (`DirectoryEntry`) de l'annuaire. À la création d'un comptable, on lui associe une ou plusieurs fiches sociétés ; chaque facture est rattachée à une société (`Invoice.companyID`) et le sélecteur d'émetteur ne propose au comptable que les sociétés de son périmètre.

Un **compte admin par défaut** (`[email protected]` / `admin`) est créé au premier lancement — **à modifier dès la première connexion**. L'identifiant d'un utilisateur doit être une **adresse e-mail** valide.

Les **Réglages** sont découpés en deux onglets :
- **Profil** (tous les utilisateurs) : informations du compte et changement de mot de passe.
- **Application** (admin uniquement) : recherche DINUM, annuaire Chorus Pro (PISTE), apparence, tags, numérotation.

## Compilation et exécution

Prérequis : macOS 13+ et Xcode 14+ (ou Swift 5.9+ en ligne de commande).

```bash
cd FacturXMacApp

# Construire
swift build

# Lancer l'app
swift run FacturXMacApp

# Ouvrir dans Xcode (interface graphique)
open Package.swift

# Tests
swift test
```

Dans Xcode : `Product > Run` (⌘R). L'app ouvre une fenêtre à deux colonnes : liste des factures à gauche, éditeur à droite. Bouton **« Générer le Factur-X »** → boîte de dialogue d'enregistrement → fichier `.pdf` hybride.

## Distribution (.app / .dmg)

```bash
scripts/package-mac.sh              # build natif (arch de la machine)
scripts/package-mac.sh --universal  # build universel arm64 + x86_64
```

Génère `dist/Factur-X.app` et `dist/Factur-X-<version>.dmg`. L'app est signée en local ("ad hoc", gratuit, sans compte Apple Developer) — nécessaire pour qu'elle se lance sur Apple Silicon, mais pas suffisant pour éviter l'avertissement Gatekeeper. Sur un autre Mac, au premier lancement : clic droit sur l'app > **Ouvrir** (sinon Réglages Système > Confidentialité et sécurité > « Ouvrir quand même »).

Pour un `.dmg` qui s'ouvre sans cet avertissement, il faut un compte Apple Developer (99$/an) et signer avec un certificat Developer ID + notariser (`xcrun notarytool`) — non fait ici.

## Utilisation

1. Renseignez l'émetteur (vous) et le destinataire.
2. Ajoutez les lignes (désignation, quantité, unité, prix unitaire HT, taux TVA).
3. Renseignez l'IBAN/BIC et les conditions de paiement.
4. Choisissez le **profil Factur-X** (EN 16931 par défaut).
5. Cliquez **« Valider »** pour vérifier la conformité de la facture (champs obligatoires, cohérence, profil).
6. Cliquez **Générer le Factur-X** → un contrôle de conformité est exécuté automatiquement avant et après la génération. Le PDF hybride n'est produit que si la validation passe.

Un panneau de validation affiche les erreurs (en rouge) et avertissements (en orange).

Les factures sont sauvegardées localement (UserDefaults) entre les sessions.

## Validation

L'application intègre un **validateur interne** (`FacturXValidator`) qui vérifie :
- les champs obligatoires de la facture (numéro, émetteur, destinataire, lignes) ;
- la cohérence des données (quantités positives, devise ISO 4217, dates) ;
- la structure du PDF généré (présence de `factur-x.xml`, `/AFRelationship /Alternative`, `/EmbeddedFiles`, `/AF`, métadonnées XMP Factur-X et PDF/A-3).

La validation est exécutée avant et après la génération. Le bouton **« Valider »** permet de la déclencher manuellement.

Le XML CII produit est conforme au XSD EN 16931. Pour vérifier le fichier final (PDF + XML embarqué) avec un outil externe :

- **Mustang** (validateur Factur-X/ZUGFeRD de référence) : https://www.mustangproject.org/
- **veraPDF** (validation du conteneur PDF/A-3) : https://verapdf.org/
- **API InvoiceXML** (validation en ligne XSD + Schematron EN 16931)

Une cross-validation Python est fournie dans `ref/` :
```bash
pip install factur-x lxml
python3 ref/gen_swift_mirror.py     # valide la logique CII contre le XSD officiel
```

## Limitations connues

- L'embarquement PDF/A-3 est réalisé par injection bas-niveau d'objets PDF (EmbeddedFile, Filespec, Names, /AF, Metadata XMP). Il produit un PDF valide lisible par les lecteurs et extracteurs Factur-X. La certification *stricte* PDF/A-3b (output intent ICC) n'est pas incluse ; utilisez Mustang/veraPDF pour un passage en production certifié, ou complétez le profil ICC sRGB.
- Pas de gestion des acomptes, des avoirs complexes, ni des extensions sectorielles (EXTENDED-CTC-FR) dans cette version de base.
- Le Schematron EN 16931 (règles métier BR-*) n'est pas exécuté à la génération ; des règles simples (cohérence des totaux, dates) sont vérifiées dans les tests, mais une validation Schematron complète doit être faite via un validateur externe avant transmission à une PDP.

## Contexte réglementaire

La réforme française de la facturation électronique impose, à partir de 2026, la transmission de factures structurées (machine-readable) via le PPF et des PDP. Factur-X (PDF/A-3 + XML CII) est l'un des trois formats acceptés (avec UBL 2.1 et CII standalone). Le profil EN 16931 est recommandé car il couvre le noyau sémantique européen complet.

## Module Order-X (commandes)

L'application intègre un **module de commandes** au format **Order-X** (profil **COMFORT**), accessible via l'onglet **« Commandes »** (structuré comme l'onglet Factures).

Une commande Order-X est un **PDF/A-3** contenant un fichier **XML Cross Industry Order (CIO)** embarqué sous le nom `order-x.xml` avec `/AFRelationship /Alternative`, accompagné des métadonnées XMP (`fx:DocumentType = ORDER`). Le **profil ventes** modélise une commande de ventes : l'**acheteur** émet une commande (TypeCode `220`) à destination de la **société**, en indiquant les lignes, la devise, et la date de livraison souhaitée.

### Conformité Order-X

- **Profil** : COMFORT (URN `urn:order-x.eu:1p0:comfort`).
- **XML CIO** : généré selon le schéma **UN/CEFACT SCRDMCCBDACIOMessageStructure D20B** (Cross Industry Order), distinct du XML CII des factures.
- **Racine** : `rsm:SCRDMCCBDACIOMessageStructure` (namespaces `:128` pour ram/qdt/udt, rsm `urn:un:unece:uncefact:data:SCRDMCCBDACIOMessageStructure:100`).
- **TypeCodes** : `220` (commande), `221` (modifications), `222` (réponses). Le profil ventes émet par défaut `220`.
- **Spécificités CIO** : `RequestedQuantity` (au lieu de `BilledQuantity`), `OrderCurrencyCode` (au lieu de `InvoiceCurrencyCode`), `RequestedDeliverySupplyChainEvent` (au lieu de `ActualDeliverySupplyChainEvent`), pas de `DuePayableAmount`.
- **Conteneur PDF/A-3** : le PDF embarque le XML en pièce jointe (`order-x.xml`) avec XMP `fx:DocumentType = ORDER`, `fx:DocumentFileName = order-x.xml`, namespace `urn:factur-x:pdfa:CrossIndustryDocument:1p0#` et `pdfaid:part = 3`.

### Contenu du module

```
Sources/FacturXCore/
├── OrderModels.swift           # SalesOrder, OrderXProfile, OrderTypeCode, OrderStatus
├── OrderCIOXMLGenerator.swift  # Générateur XML CIO D20B Order-X
├── OrderPDFRenderer.swift      # Rendu PDF lisible (CoreGraphics) — « COMMANDE »
├── OrderXEmbedder.swift        # Embarquement PDF/A-3 + XMP (order-x.xml)
├── OrderXValidator.swift       # Validation interne (données + PDF)
├── OrderXGenerator.swift      # Façade
└── OrderStore.swift            # Persistance (UserDefaults, clés orderx.*)
Tests/FacturXCoreTests/
└── OrderXCoreTests.swift      # 14 tests (totaux, XML CIO, embarquement, validation)
```

### Utilisation

1. Sélectionnez l'**acheteur** (émetteur de la commande) et la **société** (destinataire) via les annuaires réutilisés.
2. Ajoutez les lignes (désignation, quantité, unité, prix unitaire HT, taux TVA) et la **date de livraison souhaitée**.
3. Choisissez le **TypeCode** (`220` commande par défaut) et les références (devis, commande-cadre, etc.).
4. Cliquez **« Valider »** pour vérifier la conformité de la commande, puis **« Générer l'Order-X »** pour produire le PDF hybride.

Les commandes sont sauvegardées localement (UserDefaults, clés `orderx.*`) entre les sessions.

> Note : comme pour les factures, le conteneur produit est conforme à la structure Order-X (XML + XMP + AF). Une validation Schematron complète via un validateur externe reste recommandée avant transmission.

## Licence

Ce projet est distribué sous licence [Apache License 2.0](LICENSE).

Copyright © 2026 Arverneo
