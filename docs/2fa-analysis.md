# Étude — Double authentification (mail, application, clé)

Note d'analyse uniquement — pas d'implémentation dans cette PR.

## 1. Contexte : ce qui existe aujourd'hui

L'authentification (`Sources/FacturXCore/Auth.swift`) est **100% locale, mono-poste** :
- Pas de serveur, pas de base de données réseau : les utilisateurs et leurs mots de passe (SHA256 + sel itéré) sont stockés dans `UserDefaults` sur la machine.
- Aucune notion de session distante, de jeton, ni de canal de communication externe (pas d'envoi d'email possible aujourd'hui — voir le chantier #3 de cette même PR).
- Chaque comptable/admin utilise l'app sur son propre Mac ; il n'y a pas de compte "cloud" partagé entre appareils.

Cette architecture change fondamentalement ce qu'une 2FA peut réalistement apporter et comment elle doit être implémentée.

## 2. Les trois options demandées

### A. Code par e-mail (OTP)
- **Principe** : à la connexion, générer un code à 6 chiffres, l'envoyer par email, le vérifier.
- **Dépendance** : nécessite un service d'envoi d'email fonctionnel — c'est justement le chantier #3 (SMTP paramétrable) de cette PR. Sans lui, cette option est bloquée.
- **Complexité** : faible une fois #3 en place (génération de code + expiration + champ de saisie).
- **Limite de sécurité** : si l'email de l'utilisateur est sur le même Mac (Mail.app), la 2FA n'ajoute presque rien contre quelqu'un qui a déjà accès physique au poste — le principal scénario que la 2FA doit couvrir (vol du mot de passe seul, sans accès à l'appareil) reste couvert, mais pas le vol de l'appareil déverrouillé.

### B. Application d'authentification (TOTP — Google Authenticator, Authy…)
- **Principe** : standard ouvert (RFC 6238), un secret partagé est généré une fois (affiché en QR code), l'app mobile génère un code à 6 chiffres qui change toutes les 30s, indépendamment de tout réseau.
- **Dépendance** : **aucune** — ne nécessite ni serveur ni service d'email. Implémentable entièrement en local (génération HMAC-SHA1, affichage d'un QR code).
- **Complexité** : moyenne — il faut : générer/stocker le secret par utilisateur (chiffré, pas en clair), afficher un QR code (image, pas de dépendance externe si on génère le SVG/PNG nous-mêmes), vérifier le code saisi avec une fenêtre de tolérance (±1 pas de 30s).
- **Avantage** : la meilleure balance sécurité/simplicité pour une architecture 100% locale comme celle-ci. C'est le standard de facto pour ce type d'app.

### C. Clé de sécurité matérielle (FIDO2/WebAuthn/YubiKey)
- **Principe** : la norme WebAuthn est conçue pour le **web** (navigateur ↔ serveur avec un domaine HTTPS vérifiable) ou les plateformes avec un vrai fournisseur d'identité système.
- **Dépendance** : nécessite soit un serveur web avec certificat TLS valide (l'app n'en a pas — c'est un exécutable Swift local, pas un service web), soit l'intégration à l'API `ASAuthorizationPlatformPublicKeyCredentialProvider` d'Apple, qui elle-même suppose un identifiant de relying party (domaine) et généralement un compte iCloud/Apple ID pour la synchronisation des clés (Passkeys).
- **Complexité** : **élevée**, disproportionnée par rapport à l'architecture actuelle. Nécessiterait de repenser une partie du modèle d'identité de l'app.
- **Verdict** : hors de portée réaliste sans refonte plus large (par exemple si l'app évoluait vers un vrai backend).

## 3. Recommandation

**Prioriser l'option B (TOTP)**, pour trois raisons :
1. Aucune dépendance externe (pas besoin d'attendre/coupler avec le chantier email #3).
2. Standard largement supporté (toute app d'authentification du marché fonctionne).
3. Complexité d'implémentation raisonnable, cohérente avec le reste de l'architecture (tout en local, rien à héberger).

**Option A (email) en complément**, une fois le SMTP du chantier #3 opérationnel — comme méthode de récupération si l'utilisateur perd son app TOTP (cas d'usage classique : "code de secours par email").

**Option C (clé matérielle) écartée** pour l'instant : le gain de sécurité ne justifie pas la refonte d'architecture qu'elle impliquerait à ce stade.

## 4. Portée d'une future implémentation (si validée)

Si tu valides la direction TOTP, une implémentation ultérieure devrait couvrir :
- `User` : nouveau champ `totpSecret: String?` (chiffré, jamais exposé en clair après la configuration initiale) + `totpEnabled: Bool`.
- Écran de configuration (Réglages > Profil) : génération du secret, affichage du QR code, saisie de vérification avant activation.
- Flux de connexion : après mot de passe valide, si `totpEnabled`, demander le code à 6 chiffres avant d'ouvrir la session.
- Codes de récupération (10 codes à usage unique, affichés une seule fois à l'activation) — pour ne pas bloquer l'utilisateur qui perd son téléphone.
- Option admin : pouvoir désactiver la 2FA d'un utilisateur qui a perdu l'accès (nécessite un chemin de secours humain, comme pour tout système de 2FA).

Cette portée n'est **pas implémentée dans cette PR** — à valider et à planifier séparément.

## 5. Mise à jour — implémentation (chantier A, second volet)

L'option B (TOTP) recommandée ci-dessus a été implémentée :
- `TOTPService` (`Sources/FacturXCore/TOTPService.swift`) : génération/vérification RFC 6238 (HMAC-SHA1, fenêtre de tolérance ±1 pas), génération de secret et d'URI `otpauth://` pour QR code, 100% local, aucune dépendance externe.
- `User.totpEnabled` / `totpSecret` / codes de récupération (10 codes à usage unique, hachés comme les mots de passe) — champs optionnels avec migration silencieuse pour les données existantes.
- **Paramètre solution (global)** : `TwoFactorSettings.enabledSolutionWide`, réglable par un administrateur dans Réglages > Application > Sécurité. Désactivé, aucun utilisateur ne peut activer ni utiliser la 2FA, même déjà configurée.
- Écran de configuration dans le profil (QR code + clé manuelle + confirmation + affichage unique des codes de récupération), second facteur demandé à la connexion si activé, et un chemin de secours admin (désactivation depuis la gestion utilisateurs) pour un utilisateur ayant perdu son application TOTP.
- Option A (email) et Option C (clé matérielle) restent non implémentées, conformément à la recommandation ci-dessus.

## 6. Approfondissement — options A (email) et C (clé matérielle), après TOTP

Étude uniquement, comme demandé — aucune implémentation dans cette PR. Ce qui a changé depuis la section 1 : le SMTP (chantier « alertes email ») est maintenant implémenté (`SMTPService`), donc l'option A n'est plus bloquée par une dépendance manquante — elle mérite une vraie spécification plutôt que d'être reléguée à « plus tard ».

### A. Code par e-mail — proposition concrète, maintenant réalisable

- **Positionnement** : pas seulement un secours pour TOTP, mais une **deuxième méthode de 2FA à part entière**, au choix de l'utilisateur — certains n'installeront jamais d'application d'authentification, l'email reste plus universellement accepté dans un cabinet comptable.
- **Adresse d'envoi** : aucun nouveau champ nécessaire — `User.username` est déjà validé comme adresse email (`EmailValidator.isValid`, obligatoire à la création du compte), donc directement réutilisable comme destinataire.
- **Flux** : après mot de passe valide, si la méthode choisie est « email », générer un code à 6 chiffres, l'envoyer via `SMTPService.send(...)`, le garder **en mémoire seulement** (jamais persisté) avec une expiration courte (5 minutes) et un nombre d'essais limité (3), le vérifier comme le fait déjà `AuthStore.completeTwoFactorLogin` pour le code TOTP.
- **Limite de sécurité déjà identifiée, toujours valable** : si la boîte mail est configurée sur le même Mac (Mail.app avec session déjà ouverte), la protection contre un vol de l'appareil déjà déverrouillé est nulle — mais ce n'est pas le scénario principal visé par une 2FA. Contre un mot de passe seul compromis à distance (le cas le plus fréquent : réutilisation de mot de passe, hameçonnage), la protection reste réelle tant que la messagerie elle-même exige une authentification séparée.
- **Complexité** : faible maintenant que `SMTPService` existe — essentiellement une génération de code + une fenêtre d'expiration + un écran de saisie, sur le même schéma que le flux TOTP déjà en place.
- **Recommandation** : implémentable directement dans un prochain chantier si validé, en étendant `TwoFactorSettings`/`AuthStore` pour accepter une méthode par utilisateur (TOTP ou email) plutôt qu'un simple booléen global.

### C. Clé de sécurité matérielle — verdict inchangé, raisonnement précisé

Reconsidéré spécifiquement pour vérifier si quelque chose a changé côté plateforme : non. Deux voies existent techniquement pour parler à une clé FIDO2 (YubiKey…) depuis une app macOS, aucune ne convient à cette architecture :
1. **WebAuthn via `AuthenticationServices`** (`ASAuthorizationSecurityKeyPublicKeyCredentialProvider`) : c'est l'API supportée par Apple, mais elle reste structurellement liée au modèle WebAuthn — un **relying party identifier**, en pratique un nom de domaine vérifiable. Une app locale sans domaine ne peut pas s'en servir correctement ; ce serait un prérequis du chantier « mode web » (`docs/web-mode-proposal.md`), pas quelque chose d'ajoutable isolément.
2. **CTAP direct** (parler au protocole bas niveau de la clé sans passer par WebAuthn, en USB/NFC/Bluetooth via IOKit) : techniquement envisageable, mais Apple n'expose pas d'API publique supportée pour ça sur macOS — il faudrait réimplémenter un client FIDO2 depuis les échanges USB HID bruts, un projet à part entière, disproportionné par rapport au gain pour cette app.

**Verdict inchangé : hors de portée tant que l'app reste 100% locale sans domaine.** À reconsidérer uniquement si le chantier mode web se concrétise.
