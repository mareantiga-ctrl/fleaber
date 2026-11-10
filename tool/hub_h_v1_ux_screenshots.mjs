// Captura screenshots FleaHub H-v1 UX (Flutter web — scroll via wheel).
// Uso: node tool/hub_h_v1_ux_screenshots.mjs [baseUrl] [outDir]
import fs from 'fs';
import path from 'path';
import puppeteer from 'puppeteer';

const baseUrl = process.argv[2] ?? 'http://localhost:8787/fleahub-demo-ux';
const outDir =
  process.argv[3] ??
  `tool/reports/screenshots/fleahub_h_v1_ux_${new Date()
    .toISOString()
    .slice(0, 19)
    .replace(/:/g, '')
    .replace('T', '_')}`;

fs.mkdirSync(outDir, { recursive: true });

const shots = [
  { file: '01_hero.png', scrollY: 0, wait: 2500 },
  { file: '02_em_directo_agora.png', scrollY: 420, wait: 800 },
  { file: '03_gravados.png', scrollY: 780, wait: 800 },
  { file: '04_marketplace.png', scrollY: 1180, wait: 800 },
  { file: '05_opinioes.png', scrollY: 2100, wait: 800 },
  { file: '06_sobre.png', scrollY: 2700, wait: 800 },
  { file: '07_rodape_fleaber.png', scrollY: 99999, wait: 800 },
];

const browser = await puppeteer.launch({ headless: true, defaultViewport: null });
const page = await browser.newPage();
await page.setViewport({ width: 390, height: 844, deviceScaleFactor: 2 });
console.log(`A abrir ${baseUrl}`);
await page.goto(baseUrl, { waitUntil: 'networkidle2', timeout: 120000 });
await page.waitForFunction(
  () => document.title.includes('Maria Demo FleaHub') || document.title.includes('FleaHub'),
  { timeout: 120000 },
);
await new Promise((r) => setTimeout(r, 3000));

for (const s of shots) {
  await page.evaluate((y) => {
    const glass = document.querySelector('flt-glass-pane');
    if (glass) {
      glass.dispatchEvent(
        new WheelEvent('wheel', { deltaY: y, bubbles: true, cancelable: true }),
      );
    }
    window.scrollTo(0, y);
  }, s.scrollY);
  // Flutter web: múltiplos wheel events
  for (let i = 0; i < 8; i++) {
    await page.mouse.wheel({ deltaY: s.scrollY > 0 ? 120 : 0 });
    await new Promise((r) => setTimeout(r, 80));
  }
  await new Promise((r) => setTimeout(r, s.wait));
  const target = path.join(outDir, s.file);
  await page.screenshot({ path: target, fullPage: false });
  console.log(`OK ${s.file}`);
}

await page.screenshot({
  path: path.join(outDir, '00_full_page_attempt.png'),
  fullPage: true,
});

const readme = `# FleaHub H-v1 UX — screenshots

Handle demo: \`fleahub-demo-ux\`
URL: ${baseUrl}
Gerado: ${new Date().toISOString()}

Dados: demonstração UX staging (não métricas reais).

| Ficheiro | Secção |
|----------|--------|
| 01_hero.png | Hero |
| 02_em_directo_agora.png | Em directo agora |
| 03_gravados.png | Gravados |
| 04_marketplace.png | Marketplace |
| 05_opinioes.png | Opiniões |
| 06_sobre.png | Sobre |
| 07_rodape_fleaber.png | Rodapé / HubInstallBanner |
`;
fs.writeFileSync(path.join(outDir, 'README.md'), readme);
fs.writeFileSync(
  path.join('tool/reports/screenshots/fleahub_h_v1_ux_LATEST.txt'),
  path.resolve(outDir),
);
console.log(`Pasta: ${path.resolve(outDir)}`);
await browser.close();
