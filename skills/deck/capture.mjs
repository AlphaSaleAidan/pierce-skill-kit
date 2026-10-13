// Screenshot every slide of a deck (engine contract: .slide / .active, #N hash nav, 1440x810 stage).
// Writes deck-NN.png (1440x810) + phone-NN.png (390px stacked view in 1400px strips). Prints the slide count.
// Usage: node capture.mjs <deck-url> <out-dir>
import fs from 'node:fs'
import { chromium } from 'playwright'

const [url, out] = process.argv.slice(2)
if (!url || !out) { console.error('usage: node capture.mjs <deck-url> <out-dir>'); process.exit(2) }
fs.mkdirSync(out, { recursive: true })
const b = await chromium.launch()
const p = await b.newPage({ viewport: { width: 1440, height: 810 }, deviceScaleFactor: 1 })
await p.goto(url + '#1', { waitUntil: 'load' })
const n = await p.evaluate(() => document.querySelectorAll('.slide').length)
if (!n) { console.error('no .slide elements — deck does not follow the engine contract'); process.exit(1) }
for (let i = 1; i <= n; i++) {
  await p.goto(url + '#' + i, { waitUntil: 'load' }); await p.waitForTimeout(1200)
  await p.screenshot({ path: `${out}/deck-${String(i).padStart(2, '0')}.png` })
}
await p.setViewportSize({ width: 390, height: 844 })
await p.goto(url + '#1', { waitUntil: 'load' }); await p.waitForTimeout(1200)
// phone view as 390x1400 strips (a 6000px full page downscales to unreadable for the judge)
const tall = await p.evaluate(() => document.documentElement.scrollHeight)
for (let y = 0, k = 1; y < tall; y += 1400, k++)
  await p.screenshot({ path: `${out}/phone-${String(k).padStart(2, '0')}.png`, fullPage: true, clip: { x: 0, y, width: 390, height: Math.min(1400, tall - y) } })
await b.close()
console.log(n)
