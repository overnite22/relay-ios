# Relay pour iPhone

Client iPhone natif (SwiftUI) d'un serveur **Relay**, gestionnaire de connexions auto-hébergé
(SSH, RDP, VNC, coffre d'identifiants, synchronisation d'inventaire). Version **0.3.0**.
Cible iOS 26.0+, interface en français, aucune dépendance tierce.

## Fonctionnalités

- **Appairage par QR code** : Relay web → Administration → Appareils. Le jeton d'appareil (`rlt_…`) est stocké
  dans le Keychain, sur cet iPhone uniquement, et révocable depuis Relay web.
- **Connexions** : arborescence des dossiers, recherche globale, favoris, récents, témoin de disponibilité.
- **Sessions SSH, RDP et VNC** dans l'app, via le tunnel Guacamole du serveur :
  - rendu natif CoreGraphics (calques, images PNG/JPEG/WebP, curseur distant) ;
  - modes **pavé tactile** et **toucher direct**, zoom au pincement, molette à deux doigts ;
  - clavier avec Échap, Tab, Ctrl, Alt, flèches, F1–F12, et prise en charge des claviers matériels ;
  - presse-papiers dans les deux sens, Ctrl+Alt+Suppr, rotation avec redimensionnement de la session ;
  - enregistrement de session à la demande.
- **Plusieurs sessions** ouvertes à la fois : réduction, sélecteur de sessions, **espaces de travail** (groupes d'entrées ouverts ensemble).
- **Consoles Proxmox** (VM et conteneurs) dans l'app, relayées par guacd côté serveur.
- **Connexion rapide** SSH/RDP sans créer de fiche.
- **Disponibilité** : entrées injoignables, accessibles ou sans mesure, retest à la demande.
- **Coffre** : utilisateur, mot de passe, clé SSH et codes TOTP, derrière Face ID ; copie avec expiration.
- **Enregistrements** : relecture des sessions enregistrées (lecture, pause, ±10 s, vitesse ×0,5 à ×8, pauses sautées), suppression.
- **Journal d'activité** du serveur.

Les entrées Web s'ouvrent dans Safari.

## Prérequis côté serveur

- Une version de Relay qui propose **Administration → Appareils** (jetons d'appareil) ;
  pour les consoles Proxmox, `RELAY_BRIDGE_HOST` (nom par lequel guacd joint Relay).
- Si Relay est derrière un SSO (oauth2-proxy…), le chemin **`/api/`** doit être exempté du SSO :
  l'app s'authentifie avec `Authorization: Bearer`, sans cookie. Relay contrôle lui-même chaque requête.

## Sécurité

- Le jeton ne quitte le Keychain que pour l'en-tête `Authorization` vers le serveur appairé.
- HTTPS obligatoire (HTTP seulement pour `localhost`), redirections refusées, session réseau éphémère sans cookies ni cache.
- Les secrets du coffre ne sont jamais stockés : ils sont demandés au serveur à l'affichage, après Face ID,
  et copiés avec une expiration de 90 secondes, sans synchronisation iCloud.
- L'aperçu de l'app est masqué dans le sélecteur d'apps.
- Les tests n'utilisent que des données fictives (aucun serveur réel).

## Architecture

| Dossier | Rôle |
| --- | --- |
| `RelayKit/` | Paquet Swift sans UIKit : modèles, client API, appairage, protocole Guacamole. Testé sous Linux et macOS. |
| `Relay/Core` | Session de l'app, Keychain, Face ID |
| `Relay/Features/Session` | Rendu Guacamole (CoreGraphics), moteur, écran distant, clavier |
| `Relay/Features/*` | Appairage, connexions, disponibilité, coffre, connexion rapide, journal, réglages |
| `RelayTests` / `RelayUITests` | Tests du rendu au pixel près et parcours UI avec captures |
| `scripts/` | Génération du projet Xcode et de l'icône, contrôle des sources |

## Développement

Voir [docs/INSTALLATION.md](docs/INSTALLATION.md) : compilation par GitHub Actions et installation sans Mac.

```bash
node scripts/generate-project.mjs     # après ajout/suppression d'un fichier .swift
node scripts/check-source.mjs         # avant chaque commit
swift test --package-path RelayKit    # tests de RelayKit (Linux ou macOS)
```
