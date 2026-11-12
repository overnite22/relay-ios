# Compiler et installer Relay sans Mac

La chaîne est gratuite : code (Linux) → GitHub Actions macOS → IPA non signée → iPhone.

## 1. Compiler

Chaque push lance la CI (dépôt public : minutes macOS gratuites) :

- contrôle des sources et tests de `RelayKit` sous Linux ;
- tests unitaires et UI sur le simulateur iPhone le plus récent ;
- captures d'écran des tests UI (artefact `screens`) ;
- IPA Release non signée (artefact `Relay-unsigned-ipa`).

Pour publier une version : **Actions → CI → Run workflow**, case *release* cochée.
La release `vX.Y.Z-N` contient `Relay-X.Y.Z-N.ipa`.

## 2. Installer sur l'iPhone

Avec un Apple ID gratuit, depuis un PC :

1. Télécharger l'IPA de la dernière release.
2. iPhone branché en USB, l'installer avec **iloader** ou **Sideloadly**.
3. Sur l'iPhone : Réglages → Général → VPN et gestion de l'appareil → faire confiance à son Apple ID,
   et activer le Mode développeur si demandé.

Limites de l'Apple ID gratuit : signature valable **7 jours** (actualisation automatique possible),
**3 apps** au maximum. Si l'identité de signature change, il faut appairer l'iPhone de nouveau.

## 3. Appairer

1. Dans Relay web : **Administration → Appareils**, nommer l'iPhone, **Appairer**.
2. Dans l'app : **Scanner le QR code d'appairage**. Le QR code n'est affiché qu'une fois.
3. Au premier accès, iOS demande l'accès au réseau local : l'accepter si le serveur Relay est sur le LAN.

Pour retirer l'accès : révoquer l'appareil dans Relay web, puis *Désappairer* dans l'onglet Plus.
