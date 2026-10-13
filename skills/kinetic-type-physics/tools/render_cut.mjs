// Frame-accurate render of a cut page: drives the page's own position(t)/render(t)
// per frame (no wall-clock), seeks presenter videos, screenshots 1600x900.
// Usage: node render_cut.mjs <url-or-file.html[?query]> <out_dir> [fps] [duration] [start]
//   Relative names resolve against BASE_URL (e.g. your local static server). Needs `npm i puppeteer`
//   (or puppeteer-core + CHROME_PATH=/path/to/chrome).
import puppeteer from 'puppeteer';
import fs from 'node:fs';
const [,, file, out, fpsArg, durArg, startArg] = process.argv;
if (!file || !out) { console.error('usage: node render_cut.mjs <url|file.html> <out_dir> [fps] [duration] [start]'); process.exit(2); }
const START = +startArg || 0, FPS = +fpsArg || 30;
const url = /^https?:|^file:/.test(file) ? file : new URL(file, process.env.BASE_URL || `file://${process.cwd()}/`).href;
fs.mkdirSync(out, { recursive: true });
const browser = await puppeteer.launch({ executablePath: process.env.CHROME_PATH || undefined,
  args: ['--no-sandbox', '--disable-dev-shm-usage', '--autoplay-policy=no-user-gesture-required'], headless: 'new' });
const page = await browser.newPage();
await page.setViewport({ width: 1600, height: 900, deviceScaleFactor: 1 });
await page.goto(url, { waitUntil: 'load' });
await new Promise(r => setTimeout(r, 6000)); // let presenter clips load
await page.addStyleTag({ content: '#playOverlay,#timecode,#pause{display:none!important}' });
const duration = +durArg || await page.evaluate(() => duration);
const frames = Math.round((durArg ? +durArg : duration - START) * FPS);
console.log(`rendering ${frames} frames @${FPS}fps`);
for (let i = 0; i < frames; i++) {
  const t = START + i / FPS;
  await page.evaluate(async (t) => {
    paused = true; elapsed = t; position(t);
    const vids = [...document.querySelectorAll('#presenter video.active')];
    await Promise.all(vids.map(v => new Promise(res => {
      if (!v.seeking) return res();
      const done = () => { v.removeEventListener('seeked', done); res(); };
      v.addEventListener('seeked', done); setTimeout(done, 400);
    })));
    render(t);
  }, t);
  await page.screenshot({ path: `${out}/f${String(i).padStart(5, '0')}.jpg`, type: 'jpeg', quality: 92 });
}
await browser.close();
console.log('done', frames);
