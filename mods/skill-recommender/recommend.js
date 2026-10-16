#!/usr/bin/env node
// skill-recommender: on substantial prompts, and after a task fails twice, tell Claude which installed skills fit
// and have it ask you once: "Switch to <skill>?". Reads the index skill-route-sync writes; local keyword match, no API.
//
//   recommend.js prompt          UserPromptSubmit hook (reads the hook JSON on stdin)
//   recommend.js tool            PostToolUse / PostToolUseFailure hook: counts failures, suggests on the 2nd
//   recommend.js match "<text>"  print the matches for a piece of text (for tuning)
//   recommend.js stats [days]    summary of suggestions and how they were answered (default 7 days)
//
// Env: SKILL_INDEX (~/.claude/skill-index.json), SKILL_REC_DIR (~/.cache/skill-recommender), SKILL_REC_MIN (score
// gate, default 9), SKILL_REC_STOP (extra comma-separated words to ignore, e.g. your own name), SKILL_REC_IGNORE (comma list never suggested; default the always-on lead/tab skills), SKILL_REC_OFF=1 to silence it without uninstalling.
'use strict';
const fs = require('fs'), path = require('path'), os = require('os'), crypto = require('crypto');
const HOME = os.homedir();
const INDEX = process.env.SKILL_INDEX || path.join(process.env.CLAUDE_CONFIG_DIR || path.join(HOME, '.claude'), 'skill-index.json');
const DIR = process.env.SKILL_REC_DIR || path.join(HOME, '.cache', 'skill-recommender');
const MIN = Number(process.env.SKILL_REC_MIN || 9);
const IGNORE = new Set((process.env.SKILL_REC_IGNORE || 'terminal-lead,project-tab,using-superpowers,superpowers:using-superpowers').split(','));
const MAX = 3, ERR_TRIP = 2;

const STOP = new Set(('a an the and or but if then so to of in on at by for with from into onto over under is are was were be been being it its this that these those ' +
  'i me my we our you your he she they them their can could should would will just also not no yes do does did done make made get got use using used want need ' +
  'please let lets now new all any some more most very really like up out about as what when where which who how why there here than too only one two ' +
  'skill skills claude code file files thing things way work working stuff run running help us it\'s don\'t can\'t i\'m ' +
  'wants answer question ask have has had time right every each good great result show until once current pick number mention actual ' +
  'human comment nothing problem cause sure check look looks thing see keep send sent go going back first last next today tonight ' +
  'session lead brief report tab tabs monitor').split(/\s+/).concat((process.env.SKILL_REC_STOP || '').toLowerCase().split(',').filter(Boolean)));
const WORK = /\b(build|fix|debug|diagnos\w*|design|redesign|deploy|ship|research|refactor|implement|create|write|review|audit|test|render|edit|generate|make|add|set ?up|migrat\w*|optimi[sz]e|investigate|analy[sz]e|grade|scrape|automate|launch|prep\w*|remake|recreate|convert|port|upgrade|integrate|check|decompile|reverse.engineer|explain how|broken|fail\w*|error\w*|bug\w*|crash\w*|drift\w*|wrong|slow|stutter\w*|lag\w*|jitter\w*|glitch\w*|doesn'?t work|not working|isn'?t working|stuck|offload|(looks?|sounds?|feels?) (off|fake|bad|wrong|weird|pasted|robotic|laggy|choppy|flat|basic|ai)|i need|i want|we need|can we|could you|can you)\b/i;
const TRIVIAL = /^\s*(y|yes|yep|yeah|no|nope|n|ok(ay)?|k|sure|thanks?( you)?|ty|go( ahead)?|do it|continue|proceed|next|done|lgtm|good|great|cool|nice|stop|wait|hi|hello|hey)\b[\s.!?]*$/i;
const APPLE = /\b(ios|ipados|iphone|ipad|swift(ui)?|uikit|xcode|app store|testflight|storekit|apple|macos app|visionos|watchos)\b/i;
const WEB = /(react|next|vercel|web|css|tailwind|shadcn|gsap)/i;
const YES = /^\s*(y|yes|yep|yeah|sure|ok(ay)?|do it|switch|go ahead|please)\b/i, NO = /^\s*(n|no|nope|nah|keep|don'?t|stay)\b/i;

const tok = s => (String(s).toLowerCase().match(/[a-z0-9][a-z0-9+#.-]*[a-z0-9+#]|[a-z0-9]/g) || [])
  .map(w => w.replace(/(ing|ed|es|s)$/, m => (w.length > 5 ? '' : m))).filter(w => w.length > 1 && !STOP.has(w));

// ---- index + BM25 ----
function loadIndex() {
  let idx; try { idx = JSON.parse(fs.readFileSync(INDEX, 'utf8')); } catch { return null; }
  const docs = [];
  for (const s of Object.values(idx.skills || {})) {
    if (s.name.includes(':') && idx.skills[s.name.split(':').pop()]) continue;   // plugin copy of a direct install
    const nameToks = tok(s.name.split(':').pop().replace(/-/g, ' '));
    const t = nameToks.concat(nameToks, tok(s.description));                       // name words count double
    const tf = {}; for (const w of t) tf[w] = (tf[w] || 0) + 1;
    if (IGNORE.has(s.name)) continue;
    docs.push({ s, tf, len: t.length, nameSet: new Set(nameToks) });
  }
  const df = {}; for (const d of docs) for (const w in d.tf) df[w] = (df[w] || 0) + 1;
  const avg = docs.reduce((a, d) => a + d.len, 0) / (docs.length || 1);
  return { docs, df, avg, N: docs.length };
}
function match(ix, text, skip = new Set()) {
  const seq = tok(text), q = [...new Set(seq)]; if (!q.length) return [];
  const pos = {}; seq.forEach((w, i) => (pos[w] = pos[w] || []).push(i));
  // two different matched words within 4 words of each other in the prompt ("privacy manifest", "cold email sequence")
  const phrase = hits => hits.some((a, i) => hits.slice(i + 1).some(b => pos[a].some(x => pos[b].some(y => Math.abs(x - y) <= 4))));
  const k1 = 1.2, b = 0.75, out = [], need = 2 + Math.floor(q.length / 30);
  // platform guard: Apple-only skills need an Apple word in the prompt; web/React skills stay out of Apple prompts
  const apple = APPLE.test(text);
  for (const d of ix.docs) {
    if (skip.has(d.s.name)) continue;
    if (d.s.category === 'Apple & iOS' ? !apple : apple && WEB.test(d.s.name)) continue;
    let score = 0, hits = [], rareName = false;
    for (const w of q) {
      const f = d.tf[w]; if (!f) continue;
      const idf = Math.log(1 + (ix.N - ix.df[w] + 0.5) / (ix.df[w] + 0.5));
      score += idf * (f * (k1 + 1)) / (f + k1 * (1 - b + b * d.len / ix.avg)); hits.push(w);
      if (d.nameSet.has(w) && ix.df[w] <= Math.max(1, 0.08 * ix.N)) rareName = true;   // a name word few other skills use
    }
    // a clear fit: shared words that sit together in the prompt, enough of them (more for long prompts, where chance overlaps pile up), one of them a
    // distinctive word from the skill's name; or many shared words and a high score
    if (phrase(hits) && ((rareName && hits.length >= need && score >= MIN) || (hits.length >= need + 2 && score >= MIN * 1.5))) out.push({ name: d.s.name, score: +score.toFixed(2), hits, why: why(d.s.description), category: d.s.category });
  }
  out.sort((a, b) => b.score - a.score);
  // keep only clear fits: within 60% of the best, at most MAX
  return out.filter(o => o.score >= out[0]?.score * 0.75).slice(0, MAX);
}
const why = d => { d = String(d).replace(/\s+/g, ' ').replace(/^use (this )?(skill )?(when|for|to)\s*/i, ''); const s = d.split(/(?<=[.;])\s/)[0]; return s.length > 110 ? s.slice(0, 107) + '…' : s; };

// ---- state + log ----
const sid = id => String(id || 'none').replace(/[^a-zA-Z0-9_-]/g, '').slice(0, 80) || 'none';
const statePath = id => path.join(DIR, 'sessions', sid(id) + '.json');
function load(id) { try { return JSON.parse(fs.readFileSync(statePath(id), 'utf8')); } catch { return { suggested: [], errors: 0, pending: null, task: '' }; } }
function save(id, st) { try { fs.mkdirSync(path.dirname(statePath(id)), { recursive: true }); fs.writeFileSync(statePath(id), JSON.stringify(st)); } catch {} }
function log(rec) { try { fs.mkdirSync(DIR, { recursive: true }); fs.appendFileSync(path.join(DIR, 'log.jsonl'), JSON.stringify({ ts: new Date().toISOString(), ...rec }) + '\n'); } catch {} }
const hash = s => crypto.createHash('sha1').update(String(s)).digest('hex').slice(0, 10);   // the log never stores your prompt

// skills already invoked in this session (from the transcript tail): don't suggest what's in use
function loadedSkills(transcript) {
  const got = new Set();
  try {
    const st = fs.statSync(transcript), fd = fs.openSync(transcript, 'r'), n = Math.min(st.size, 400000), buf = Buffer.alloc(n);
    fs.readSync(fd, buf, 0, n, st.size - n); fs.closeSync(fd);
    for (const m of buf.toString('utf8').matchAll(/"name":"Skill","input":\{"skill":"([^"]+)"/g)) got.add(m[1]);
    for (const m of buf.toString('utf8').matchAll(/<command-name>\/?([^<\s]+)<\/command-name>/g)) got.add(m[1]);
  } catch {}
  return got;
}
const bare = n => n.split(':').pop();
function skipSet(st, transcript) {
  const s = new Set(st.suggested);
  for (const n of loadedSkills(transcript)) { s.add(n); s.add(bare(n)); }
  return s;
}

function note(ms, reason) {
  const list = ms.map(m => `\`${m.name}\` (${m.why})`).join('; ');
  return `[skill-recommender] ${reason}: ${list}. If one of these would clearly do this better than your current approach, ` +
    `ask the user once, in one line: "Switch to <skill>?" (name the one you'd pick), then follow their answer. ` +
    `If none fits better, ignore this note and don't mention it.`;
}
function emit(event, text) { process.stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: event, additionalContext: text } })); }

function readStdin() { try { return JSON.parse(fs.readFileSync(0, 'utf8') || '{}'); } catch { return {}; } }

// ---- modes ----
const mode = process.argv[2];
if (process.env.SKILL_REC_OFF === '1' && (mode === 'prompt' || mode === 'tool')) process.exit(0);

if (mode === 'prompt') {
  const h = readStdin(), prompt = String(h.prompt || ''), st = load(h.session_id);
  // answer to the last suggestion?
  if (st.pending) {
    const used = loadedSkills(h.transcript_path).has(st.pending.skill);
    const outcome = YES.test(prompt) || used ? 'accepted' : NO.test(prompt) ? 'declined' : 'ignored';
    log({ event: 'answer', session: sid(h.session_id), skill: st.pending.skill, outcome });
    st.pending = null;
  }
  st.errors = 0;                                                  // a new prompt starts a new attempt
  const tough = !TRIVIAL.test(prompt) && !/^\s*[\/<!]/.test(prompt) &&
    (prompt.length >= 280 || (prompt.length >= 40 && WORK.test(prompt)));
  if (tough) {
    st.task = prompt.slice(0, 2000);
    const ix = loadIndex();
    const ms = ix ? match(ix, prompt, skipSet(st, h.transcript_path)) : [];
    if (ms.length) {
      st.suggested.push(...ms.map(m => m.name)); st.pending = { skill: ms[0].name };
      log({ event: 'suggest', trigger: 'prompt', session: sid(h.session_id), prompt: hash(prompt), skills: ms.map(m => [m.name, m.score]) });
      emit('UserPromptSubmit', note(ms, 'Skills that fit this task'));
    }
  }
  save(h.session_id, st);
} else if (mode === 'tool') {
  const h = readStdin(), st = load(h.session_id);
  const r = h.tool_response;
  const failed = h.hook_event_name === 'PostToolUseFailure' || (r && typeof r === 'object' &&
    (r.is_error === true || r.isError === true || (typeof r.exitCode === 'number' && r.exitCode !== 0)));
  if (failed) {
    st.errors = (st.errors || 0) + 1;
    if (st.errors === ERR_TRIP && st.task) {
      const err = String(h.error || (r && (r.stderr || r.error || r.content)) || '').slice(0, 1500);
      const ix = loadIndex();
      const ms = ix ? match(ix, st.task + ' ' + err, skipSet(st, h.transcript_path)) : [];
      if (ms.length) {
        st.suggested.push(...ms.map(m => m.name)); st.pending = { skill: ms[0].name };
        log({ event: 'suggest', trigger: 'errors', session: sid(h.session_id), tool: h.tool_name, skills: ms.map(m => [m.name, m.score]) });
        emit(h.hook_event_name || 'PostToolUse', note(ms, `This task has failed ${ERR_TRIP} times; skills that may handle it better`));
      }
    }
    save(h.session_id, st);
  }
} else if (mode === 'match') {
  const ix = loadIndex(); if (!ix) { console.error(`no index at ${INDEX}; run skill-route-sync`); process.exit(1); }
  const text = process.argv.slice(3).join(' ');
  const tough = !TRIVIAL.test(text) && (text.length >= 280 || (text.length >= 40 && WORK.test(text)));
  console.log(`tough: ${tough}`);
  for (const m of match(ix, text)) console.log(`${m.score.toFixed(1).padStart(5)}  ${m.name}  [${m.hits.join(' ')}]`);
} else if (mode === 'stats') {
  const days = Number(process.argv[3] || 7), since = Date.now() - days * 864e5;
  let lines = []; try { lines = fs.readFileSync(path.join(DIR, 'log.jsonl'), 'utf8').trim().split('\n').map(l => JSON.parse(l)); } catch {}
  lines = lines.filter(l => Date.parse(l.ts) >= since);
  const sug = lines.filter(l => l.event === 'suggest'), ans = lines.filter(l => l.event === 'answer');
  const c = o => ans.filter(a => a.outcome === o).length;
  const top = {}; for (const s of sug) for (const [n] of s.skills) top[n] = (top[n] || 0) + 1;
  const best = Object.entries(top).sort((a, b) => b[1] - a[1]).slice(0, 5).map(([n, k]) => `${n} ${k}`).join(', ');
  console.log(`last ${days}d: ${sug.length} suggestions (${sug.filter(s => s.trigger === 'errors').length} after repeated failures); ` +
    `accepted ${c('accepted')}, declined ${c('declined')}, ignored ${c('ignored')}${best ? `; most suggested: ${best}` : ''}`);
} else {
  console.error('usage: recommend.js prompt|tool|match "<text>"|stats [days]'); process.exit(2);
}
