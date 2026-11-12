# Sécurité

- Aucun jeton, mot de passe, nom d'hôte réel ni adresse privée dans le dépôt : `scripts/check-source.mjs`
  le vérifie à chaque push (adresses IPv4 privées, e-mails, clés, jetons, mots privés listés localement).
- Les données de test sont fictives (`example.com`, `192.0.2.0/24`).
- Signaler un problème : ouvrir une issue sans y joindre de secret.
