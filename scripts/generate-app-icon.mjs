// Génère l'icône (1024×1024, RVB opaque) depuis un dessin vectoriel original.
// Usage : node scripts/generate-app-icon.mjs <chemin vers playwright>
// Le rendu passe par Chromium (canvas) ; l'encodage PNG est fait ici, sans canal alpha.
import fs from "node:fs";
import zlib from "node:zlib";

const playwright = process.argv[2];
if (!playwright) throw new Error("Usage : node scripts/generate-app-icon.mjs <module playwright>");
const { chromium } = await import(playwright);

const svg = `
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#0a1b36"/><stop offset="1" stop-color="#1f6fd8"/>
    </linearGradient>
    <linearGradient id="screen" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#0d1420"/><stop offset="1" stop-color="#16233a"/>
    </linearGradient>
  </defs>
  <rect width="1024" height="1024" fill="url(#bg)"/>
  <!-- Écran -->
  <rect x="170" y="200" width="684" height="470" rx="56" fill="url(#screen)" stroke="#ffffff" stroke-width="30"/>
  <!-- Invite de commande -->
  <polyline points="270,330 380,420 270,510" fill="none" stroke="#3fb950" stroke-width="44" stroke-linecap="round" stroke-linejoin="round"/>
  <line x1="430" y1="510" x2="600" y2="510" stroke="#ffffff" stroke-width="40" stroke-linecap="round"/>
  <!-- Pied et liaison -->
  <rect x="452" y="670" width="120" height="70" fill="#ffffff"/>
  <rect x="330" y="730" width="364" height="44" rx="22" fill="#ffffff"/>
  <!-- Relais : deux nœuds reliés -->
  <line x1="260" y1="860" x2="764" y2="860" stroke="#ffffff" stroke-opacity="0.55" stroke-width="18" stroke-linecap="round" stroke-dasharray="2 46"/>
  <circle cx="230" cy="860" r="44" fill="#3fb950"/>
  <circle cx="794" cy="860" r="44" fill="#ffffff"/>
</svg>`;

const browser = await chromium.launch({ args: ["--no-sandbox"] });
const page = await browser.newPage();
await page.setContent("<canvas id=c width=1024 height=1024></canvas>");
const pixels = await page.evaluate(async (source) => {
  const img = new Image();
  img.src = "data:image/svg+xml;charset=utf-8," + encodeURIComponent(source);
  await img.decode();
  const ctx = document.getElementById("c").getContext("2d");
  ctx.fillStyle = "#0a1b36";
  ctx.fillRect(0, 0, 1024, 1024);
  ctx.drawImage(img, 0, 0);
  return Array.from(ctx.getImageData(0, 0, 1024, 1024).data);
}, svg);
await browser.close();

const w = 1024, h = 1024;
const raw = Buffer.alloc((w * 3 + 1) * h);
for (let y = 0; y < h; y++) {
  raw[y * (w * 3 + 1)] = 0;
  for (let x = 0; x < w; x++) {
    const s = (y * w + x) * 4, d = y * (w * 3 + 1) + 1 + x * 3;
    raw[d] = pixels[s]; raw[d + 1] = pixels[s + 1]; raw[d + 2] = pixels[s + 2];
  }
}
const table = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
const crc = (b) => { let c = 0xffffffff; for (const x of b) c = table[(c ^ x) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
const chunk = (t, d) => { const l = Buffer.alloc(4); l.writeUInt32BE(d.length); const td = Buffer.concat([Buffer.from(t), d]); const c = Buffer.alloc(4); c.writeUInt32BE(crc(td)); return Buffer.concat([l, td, c]); };
const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2;
const png = Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", zlib.deflateSync(raw, { level: 9 })), chunk("IEND", Buffer.alloc(0))]);
for (const out of ["Relay/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png", "Relay/Resources/Assets.xcassets/RelayMark.imageset/RelayMark.png"]) {
  fs.mkdirSync(out.replace(/\/[^/]+$/, ""), { recursive: true });
  fs.writeFileSync(out, png);
}
console.log("Icône générée (" + png.length + " octets).");
