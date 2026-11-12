// Contrôle des sources avant commit (dépôt public) : fuites d'informations, secrets, cohérence du projet Xcode.
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";

const skip = new Set([".git", "node_modules", ".private-words", "build", "DerivedData", ".build", ".swiftpm"]);
const walk = (dir) => fs.readdirSync(dir, { withFileTypes: true }).filter((e) => !skip.has(e.name))
  .flatMap((e) => (e.isDirectory() ? walk(path.join(dir, e.name)) : [path.join(dir, e.name)]));
const files = walk(".");
// Facultatif, jamais commité : un mot privé par ligne (domaine, société, noms d'hôtes…).
const privateWords = fs.existsSync(".private-words")
  ? fs.readFileSync(".private-words", "utf8").split(/\r?\n/).map((w) => w.trim().toLowerCase()).filter((w) => w && !w.startsWith("#"))
  : [];

// Projet : chaque fichier .swift de l'app et des tests est référencé, identifiants uniques et définis.
const project = fs.readFileSync("Relay.xcodeproj/project.pbxproj", "utf8");
const projectPaths = [...project.matchAll(/\bpath\s*=\s*(?:"([^"\n]+)"|([^;\n]+));/g)].map((m) => (m[1] ?? m[2]).trim());
for (const file of files.filter((f) => f.endsWith(".swift") && /^(Relay|RelayTests|RelayUITests)\//.test(f.replaceAll("\\", "/")))) {
  assert(projectPaths.includes(file.replaceAll("\\", "/")), "Fichier absent du projet Xcode (lancer generate-project.mjs) : " + file);
}
const definitions = [...project.matchAll(/^([A-F0-9]{24}) = /gm)].map((m) => m[1]);
assert.equal(new Set(definitions).size, definitions.length, "Identifiants de projet dupliqués");
for (const match of project.matchAll(/\b[A-F0-9]{24}\b/g)) assert(definitions.includes(match[0]), "Référence de projet indéfinie");
assert.equal((project.match(/isa = PBXNativeTarget/g) || []).length, 3);
assert.equal((project.match(/IPHONEOS_DEPLOYMENT_TARGET = 26.0/g) || []).length, 6);

const binary = /\.(png|jpg|jpeg|gif|ico|ipa|zip)$/i;
for (const file of files.filter((f) => !binary.test(f) && !f.endsWith("check-source.mjs"))) {
  const text = fs.readFileSync(file, "utf8");
  assert(!/-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/.test(text), "Clé privée : " + file);
  assert(!/\b(?:ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{20,}|nbt_[A-Za-z0-9]+\.[A-Za-z0-9]{20,})\b/.test(text), "Identifiant possible : " + file);
  // Jetons d'appareil Relay : seuls les exemples factices (un seul caractère répété) sont admis.
  for (const [token] of text.matchAll(/\brlt_[A-Za-z0-9_-]{20,}/g)) {
    assert(new Set(token.slice(4)).size === 1, "Jeton Relay réel possible : " + file);
  }
  assert(!/(?<![\d.])(?:10\.\d{1,3}|192\.168|172\.(?:1[6-9]|2\d|3[01]))\.\d{1,3}\.\d{1,3}(?![\d.])/.test(text), "Adresse IPv4 privée : " + file);
  for (const [address] of text.matchAll(/[A-Za-z0-9._%+-]+@([A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,})/g)) {
    const domain = address.split("@").pop().toLowerCase();
    assert(/(?:^|\.)(?:example\.(?:com|org|net)|example|test|invalid|localhost)$/.test(domain) || domain === "users.noreply.github.com",
      "Adresse e-mail : " + file);
  }
  for (const word of privateWords) assert(!text.toLowerCase().includes(word), "Mot privé dans " + file);
  if (file.endsWith(".swift")) {
    assert(!/\b(?:print|debugPrint|NSLog)\s*\(/.test(text), "Journalisation : " + file);
    assert(!/try!|as!|TODO|FIXME/.test(text), "Code inachevé ou non sûr : " + file);
  }
}
console.log("Sources OK : " + files.length + " fichiers vérifiés, " + privateWords.length + " mots privés.");
