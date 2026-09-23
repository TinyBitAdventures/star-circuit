// Headless check of https://starcircuit.localhost: console errors, each
// interactive piece, and screenshots into website/shots/.
// Run: node website/tools/check-site.mjs  (uses ~/node_modules/playwright)
import { createRequire } from 'module';
import { mkdirSync } from 'fs';
import { homedir } from 'os';
const require = createRequire(homedir() + '/node_modules/');
const { chromium } = require('playwright');
const out = new URL('../shots/', import.meta.url).pathname;
mkdirSync(out, { recursive: true });
const url = process.env.URL || 'https://starcircuit.localhost/';
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1440, height: 900 }, ignoreHTTPSErrors: true });
const errors = [];
page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
page.on('pageerror', (e) => errors.push(String(e)));
page.on('requestfailed', (r) => errors.push('failed: ' + r.url()));
await page.goto(url, { waitUntil: 'networkidle' });
await page.waitForTimeout(800);
await page.screenshot({ path: out + '01-hero.png' });
// hold warp
const warp = page.locator('#warp-btn');
const box = await warp.boundingBox();
await page.mouse.move(box.x + 20, box.y + 10);
await page.mouse.down();
await page.waitForTimeout(1200);
await page.screenshot({ path: out + '02-warp.png' });
await page.mouse.up();
// robots
await page.locator('#robots').scrollIntoViewIfNeeded();
await page.waitForTimeout(900);
await page.locator('.robot-tab').nth(1).click();
await page.waitForTimeout(700);
await page.locator('#robots').screenshot({ path: out + '03-robots.png' });
console.log('robot name after click:', await page.locator('#robot-name').textContent());
// modes
await page.locator('#modes').scrollIntoViewIfNeeded();
await page.locator('.mode-tab[data-mode="volcano"]').click();
await page.waitForTimeout(800);
await page.locator('#modes').screenshot({ path: out + '04-modes.png' });
// galaxy: hover the home star, then plot a route between two stars
await page.locator('#galaxy').scrollIntoViewIfNeeded();
await page.waitForTimeout(800);
const pts = await page.evaluate(() => {
	const cv = document.getElementById('galaxy-map');
	const r = cv.getBoundingClientRect();
	const s = window.STAR_CIRCUIT.data.stars;
	const b = s.reduce((b, st) => ({ minx: Math.min(b.minx, st.x), maxx: Math.max(b.maxx, st.x), minz: Math.min(b.minz, st.z), maxz: Math.max(b.maxz, st.z) }), { minx: 1e9, maxx: -1e9, minz: 1e9, maxz: -1e9 });
	const pad = 60, k = Math.min((r.width - pad * 2) / (b.maxx - b.minx), (r.height - pad * 2) / (b.maxz - b.minz));
	const at = (st) => [r.left + r.width / 2 + (st.x - (b.minx + b.maxx) / 2) * k, r.top + r.height / 2 + (st.z - (b.minz + b.maxz) / 2) * k];
	return [at(s[0]), at(s[3])];
});
await page.mouse.click(pts[0][0], pts[0][1]);
await page.mouse.click(pts[1][0], pts[1][1]);
await page.waitForTimeout(500);
await page.locator('#galaxy').screenshot({ path: out + '05-galaxy.png' });
console.log('star card:', (await page.locator('#star-card').innerText()).replace(/\n/g, ' | ').slice(0, 220));
// music: play a track and check it advances
await page.locator('#music').scrollIntoViewIfNeeded();
await page.locator('#tracks button').nth(8).click();
await page.waitForTimeout(2500);
const t = await page.evaluate(() => { const a = [...document.querySelectorAll('audio')]; return document.getElementById('time').textContent; });
console.log('music time after 2.5s:', t, 'title:', await page.locator('#now-title').textContent());
await page.locator('#music').screenshot({ path: out + '06-music.png' });
// mini-game
await page.locator('#play').scrollIntoViewIfNeeded();
await page.locator('#game-start').click();
const g = await page.locator('#hyper-game').boundingBox();
await page.mouse.move(g.x + g.width / 2, g.y + g.height * 0.6);
await page.mouse.down();
for (let i = 0; i < 40; i++) { await page.mouse.move(g.x + g.width * (0.35 + 0.3 * Math.sin(i / 5)), g.y + g.height * 0.55); await page.waitForTimeout(100); }
await page.locator('#play').screenshot({ path: out + '07-game.png' });
await page.mouse.up();
// mobile layout
await page.setViewportSize({ width: 390, height: 844 });
await page.goto(url, { waitUntil: 'networkidle' });
await page.waitForTimeout(600);
await page.screenshot({ path: out + '08-mobile.png', fullPage: false });
const overflow = await page.evaluate(() => {
	const wide = [...document.querySelectorAll('body *')].filter((el) => el.getBoundingClientRect().right > innerWidth + 1).slice(0, 5).map((el) => el.tagName + '.' + el.className);
	return document.documentElement.scrollWidth > innerWidth + 1 ? wide : false;
});
console.log('mobile horizontal overflow:', overflow);
console.log('errors:', errors.length ? errors : 'none');
await browser.close();
