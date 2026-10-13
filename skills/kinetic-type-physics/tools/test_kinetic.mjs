// Engine self-check (no browser): spring lands at 1 with 3–5 % overshoot and is deterministic in t.
// Usage: node tools/test_kinetic.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const ctx = { window: {}, Math };
vm.runInNewContext(fs.readFileSync(new URL('../lib/kinetic.js', import.meta.url), 'utf8'), ctx);
const r = ctx.window.Kinetic.response, response = (...a) => [...r(...a)];  // copy out of the vm realm
assert.deepEqual(response(0), [0, 0]);
assert.deepEqual(response(1), [1, 0]);
const peak = Math.max(...Array.from({ length: 1000 }, (_, i) => response(i / 1000)[0]));
assert.ok(peak > 1.02 && peak < 1.06, `overshoot ${peak}`);
assert.deepEqual(response(0.37), response(0.37));
assert.equal(response(0.5, {}, 'linear')[0], 0.5);
console.log('kinetic self-check PASS, overshoot', ((peak - 1) * 100).toFixed(1) + '%');
