# Parité avec Relay (web et PC)

L'app couvre toutes les fonctions de Relay web, sauf la gestion des appareils, volontairement réservée
au web (un téléphone perdu ne doit pas pouvoir en appairer d'autres). Ce tableau relie chaque API du
serveur à son écran : quand le serveur évolue, il indique quoi adapter, et sert de cahier des charges
pour un autre client mobile.

| API Relay | RelayKit | Écran de l'app |
| --- | --- | --- |
| `GET /api/me` | `me()` | Appairage, Plus → Serveur |
| `GET /api/tree` | `tree()` | Connexions (arborescence, recherche, favoris, récents) |
| `GET/POST/PUT/DELETE /api/entries` | `entryInput`, `saveEntry`, `deleteEntry` | Fiche → Modifier, menu contextuel, + |
| `POST /api/folders`, `PUT/DELETE /api/folders/{id}` | `saveFolder`, `deleteFolder` | Dossier → Actions, + |
| `PUT /api/folders/{id}/credentials` | `setFolderCredentials` | Modifier le dossier → Identifiants par défaut |
| `POST /api/entries/{id}/connect` (`native` pour Proxmox) | `connect` | Sessions SSH, RDP, VNC, consoles Proxmox |
| `POST /api/quick-connect` | `quickConnect` | Plus → Connexion rapide |
| `GET /api/tunnel` (WebSocket Guacamole) | `GuacTunnel`, `GuacClientCore` | Session (rendu, clavier, presse-papiers, fichiers) |
| `GET /api/connection-status`, `POST …/test-connection` | `connectionStatus`, `testConnection` | Témoins, Disponibilité, retests |
| `GET/POST/PUT/DELETE /api/credentials`, `reveal`, `totp` | `credentials`, `saveCredential`, `reveal`, `totp` | Coffre |
| `…/attachments` | `attachments`, `addAttachment`, `attachmentData` | Fiche → Pièces jointes |
| `/api/workspaces` | `workspaces`, `saveWorkspace` | Plus → Espaces de travail |
| `/api/commands/*`, `/api/known-hosts/forget` | `startRun`, `run`, `savedCommands`… | Onglet Commandes |
| `/api/recordings` | `recordings`, `recordingData` | Plus → Enregistrements |
| `/api/sources/*` | `sources`, `saveSource`, `syncSource`… | Plus → Sources de synchro |
| `/api/duplicates`, `…/merge` | `duplicates`, `merge` | Plus → Doublons |
| `/api/import/rdm/*` | `previewImport`, `applyImport` | Plus → Importer depuis RDM |
| `/api/backups/*` | `exportBackup`, `restoreBackup` | Plus → Sauvegarde |
| `GET /api/audit` | `audit` | Plus → Journal d'activité |
| `/api/devices` | — | Réservé à Relay web (refusé aux jetons d'appareil) |

## Quand Relay gagne une fonction

1. Ajouter l'appel dans `RelayKit` avec un test (`swift test --package-path RelayKit`, Linux suffit).
2. Ajouter l'écran ou l'action, puis la réponse factice dans `Relay/App/UITestSupport.swift`.
3. Ajouter un test UI avec capture, et une ligne à ce tableau.
4. Le serveur refuse les champs JSON inconnus : n'envoyer un nouveau champ qu'aux versions de Relay qui le connaissent.
