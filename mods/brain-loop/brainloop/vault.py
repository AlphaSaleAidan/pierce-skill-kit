"""The vault: an Obsidian-compatible linked brain (one note per entity, [[links]] + backlinks) built from the kit's
ledgers. Open the folder in Obsidian, or use the /brain page (`brain-loop page`).

Note types (folders): projects/ people/ commitments/ decisions/ plans/ rules/ memory/  + index.md
Sources (all from config): the entity registry (JSON), orders.tsv, reports.tsv, decisions.md, plans/<project>/*.md,
Claude memory folders, and an optional money ledger TSV.

Hand edits survive rebuilds: only the block between GEN_START/GEN_END and generator-owned frontmatter keys are
rewritten. Text you write below the end marker is kept. Frontmatter keys starting with `my_` are yours and win:
my_status, my_owner, my_chase_after, my_note, my_link (entity slugs that replace the matched ones), my_title.
Every text passes common.mask; nothing under .secrets / .env is read.
"""
import json
import re
import time
from datetime import timedelta
from pathlib import Path

from . import common as C
from .common import CLOSED, GEN_END, GEN_START, NOW, compact, mask, one, parse_fm, slug

FOLDERS = {"project": "projects", "person": "people", "commitment": "commitments", "decision": "decisions",
           "rule": "rules", "memory": "memory", "plan": "plans"}
WAITING = "waiting-on-owner"
# days from asked_on to chase_after, per kind (a due date wins)
CHASE_GAP = {WAITING: 1, "ask": 2, "money-in": 7, "money-out": 14}


def load_entities(path=None):
    """Registry JSON -> ({slug: entity}, {CaseSensitiveAlias: (words it must not be followed by)}).
    {"projects": {slug: {title, aliases}}, "people": {slug: {title, aliases, emails, role, kind}},
     "case_sensitive": {"Sam": ["plan"]}}"""
    try:
        d = json.loads(Path(path or C.ENTITIES).read_text())
    except (OSError, ValueError):
        d = {}
    ents = {}
    for typ, key in (("project", "projects"), ("person", "people")):
        for s, e in (d.get(key) or {}).items():
            ents[s] = {"title": e.get("title") or s, "aliases": list(e.get("aliases") or []), "type": typ,
                       "emails": list(e.get("emails") or []), "role": e.get("role"), "kind": e.get("kind")}
    case = {k: tuple(v or ()) for k, v in (d.get("case_sensitive") or {}).items()}
    return ents, case


# ------------------------------------------------------------------ entity resolution
class Resolver:
    """Finds which projects/people a piece of text is about (aliases, emails; case rules for short names)."""

    def __init__(self, ents, case=None):
        self.ents = ents
        case = case or {}
        self.rx = []
        for s, e in ents.items():
            pats_ci, pats_cs = [], []
            for a in {e["title"], *e["aliases"]}:
                if not a or len(a) < 2:
                    continue
                key = next((c for c in case if c.lower() == a.lower()), None)
                if key is not None:
                    avoid = "".join(rf"(?!\s+{re.escape(w)}\b)" for w in case[key])
                    pats_cs.append(rf"(?<![\w@./-]){re.escape(key)}(?![\w@-]){avoid}")
                else:
                    pats_ci.append(rf"(?<![\w@./-]){re.escape(a)}(?![\w@-])")
            for em in e.get("emails", []):
                pats_ci.append(re.escape(em))
            if pats_ci:
                self.rx.append((s, re.compile("|".join(pats_ci), re.I)))
            if pats_cs:
                self.rx.append((s, re.compile("|".join(pats_cs))))
        self.by_name = {}
        for s, e in ents.items():
            for a in {s, e["title"], *e["aliases"]}:
                self.by_name.setdefault(compact(a), s)

    def has(self, s, text):
        return any(rx.search(text or "") for x, rx in self.rx if x == s)

    def find(self, text):
        found = []
        for s, rx in self.rx:
            if s not in found and rx.search(text or ""):
                found.append(s)
        return found

    def project_of(self, col):
        """A ledger's project column ('acme-site', 'Acme', 'acme-checkout') -> project slug."""
        c = compact(col)
        if not c:
            return None
        if c in self.by_name and self.ents[self.by_name[c]]["type"] == "project":
            return self.by_name[c]
        hits = [s for s in self.find(re.sub(r"[-_]", " ", col)) if self.ents[s]["type"] == "project"]
        if hits:
            return hits[0]
        for name, s in sorted(self.by_name.items(), key=lambda x: -len(x[0])):
            if self.ents[s]["type"] == "project" and len(name) >= 4 and c.startswith(name):
                return s
        return None


# ------------------------------------------------------------------ the build
class Note:
    def __init__(self, nid, ntype, title, fm=None):
        self.id, self.type, self.title = nid, ntype, title
        self.fm = fm or {}
        self.body = []        # markdown lines inside the generated block
        self.links = []       # outgoing note ids (ordered, unique)
        self.text = ""        # plain text used for mention matching
        self.raw = ""         # full body text (memory notes) for fact sentences
        self.date = ""

    def link(self, nid):
        if nid and nid != self.id and nid not in self.links:
            self.links.append(nid)


class Brain:
    def __init__(self, vault=None):
        self.root = Path(vault or C.VAULT)
        self.notes = {}
        ents, case = load_entities()
        for s, fm in self._existing_registry().items():  # aliases/emails added by hand in the vault win
            if s in ents:
                ents[s]["aliases"] = sorted(set(ents[s]["aliases"]) | set(fm.get("aliases") or []))
                if fm.get("emails"):
                    ents[s]["emails"] = sorted(set(ents[s]["emails"]) | set(fm["emails"]))
        self.ents = ents
        self.R = Resolver(ents, case)
        self.reports = []
        self.mem_names = {}

    def _existing_registry(self):
        out = {}
        for folder in ("projects", "people"):
            d = self.root / folder
            for p in d.glob("*.md") if d.is_dir() else []:
                fm, _ = parse_fm(p.read_text(errors="ignore"))
                out[p.stem] = fm
        return out

    def add(self, note):
        self.notes[note.id] = note
        return note

    def mention_links(self, note, text, project_col=None):
        """Link a note to every project/person its text (or ledger project column) names."""
        ps = []
        if project_col:
            p = self.R.project_of(project_col)
            if p:
                ps.append(p)
        for s in self.R.find(text):
            if s not in ps:
                ps.append(s)
        for s in ps:
            note.link(s)
        return ps

    @staticmethod
    def _tsv(path):
        if not path or not Path(path).is_file():
            return []
        return [(i + 1, line.rstrip("\n").split("\t")) for i, line in enumerate(open(path, errors="ignore")) if i > 0]

    # ---------------- sources
    def load_hubs(self):
        for s, e in self.ents.items():
            fm = {"type": e["type"], "aliases": sorted({e["title"], *e["aliases"]} - {s})}
            for k in ("emails", "role", "kind"):
                if e.get(k):
                    fm[k] = e[k]
            self.add(Note(s, e["type"], e["title"], fm))

    def load_orders(self):
        """orders.tsv (the kit's `order` ledger): id opened project tab status ask note."""
        for ln, c in self._tsv(C.ORDERS):
            if len(c) < 6:
                continue
            oid, opened, proj, tab, status, ask = c[:6]
            note_txt = c[6] if len(c) > 6 else ""
            st = status.strip().lower()
            n = Note(f"c-order-{oid}", "commitment", one(ask, 90), {
                "type": "commitment", "kind": "ask", "status": st, "open": st not in CLOSED,
                "owner": tab or proj, "owed_to": C.OWNER, "asked_on": C.date(opened), "source": C.src(C.ORDERS, ln)})
            n.text = mask(f"{ask} {note_txt}")
            n.date = C.date(opened)
            n.body = [f"**The {C.OWNER}'s ask (order #{oid}, {opened}):** {mask(ask)}", "",
                      f"- status: **{st}** · owner tab: {tab or '?'} · project column: {proj}"]
            if note_txt:
                n.body.append(f"- last note: {mask(note_txt)}")
            n.body.append(f"- source: `{C.src(C.ORDERS, ln)}`")
            n.fm["project"] = self.mention_links(n, n.text, proj)[:1] or None
            self.add(n)

    def load_reports(self):
        """reports.tsv (the kit's `report`): time project status message proof tab.
        Every report feeds the hubs; needs-human reports from the last 7 days (newest 4 per project) become
        waiting-on-owner commitments."""
        rows = []
        for ln, c in self._tsv(C.REPORTS):
            if len(c) < 4:
                continue
            rows.append({"when": C.date(c[0]), "proj": c[1], "status": c[2], "msg": mask(c[3]),
                         "proof": mask(c[4]) if len(c) > 4 else "", "tab": c[5] if len(c) > 5 else "",
                         "src": C.src(C.REPORTS, ln)})
        for r in rows:
            pj = self.R.project_of(r["proj"])
            r["ents"] = set(self.R.find(r["msg"])) | ({pj} if pj else set())
        self.reports = rows
        cutoff = (NOW - timedelta(days=7)).strftime("%Y-%m-%dT%H:%M")
        per = {}
        for r in reversed(rows):
            if r["status"] != "needs-human" or r["when"] < cutoff:
                continue
            k = r["proj"].lower()
            per[k] = per.get(k, 0) + 1
            if per[k] > 4:
                continue
            nid = f"c-wait-{r['when'][5:16].replace(':', '').replace('T', '-')}-{slug(r['proj'], 20)}"
            n = Note(nid, "commitment", one(f"{r['proj']}: {r['msg']}", 90), {
                "type": "commitment", "kind": WAITING, "status": "waiting", "open": True,
                "owner": C.OWNER, "owed_to": r["tab"] or r["proj"], "asked_on": r["when"], "source": r["src"]})
            n.text = r["msg"]
            n.date = r["when"]
            n.body = [f"**{r['proj']} tab needs the {C.OWNER} ({r['when'][5:16]}):** {r['msg']}", "",
                      f"- source: `{r['src']}`"] + ([f"- proof: {r['proof']}"] if r["proof"] else [])
            n.fm["project"] = self.mention_links(n, n.text, r["proj"])[:1] or None
            self.add(n)

    def load_ledger(self):
        """Optional money ledger TSV (BRAIN_LEDGER): id added direction(in|out) who what amount due status project note.
        open/overdue rows are owed now; pending = contingent (not counted); paid/void closed."""
        for ln, c in self._tsv(C.LEDGER):
            if len(c) < 8:
                continue
            c = (c + [""] * 10)[:10]
            lid, added, direction, who, what, amount, due, status, proj, note_txt = c
            kind = "money-out" if direction.strip().lower() == "out" else "money-in"
            st = status.strip().lower()
            try:
                amt = float(amount.replace(",", "").replace("$", "") or 0)
            except ValueError:
                amt = 0.0
            n = Note(f"c-{'in' if kind == 'money-in' else 'out'}-{slug(lid, 20)}", "commitment", one(f"{who}: {what}", 90), {
                "type": "commitment", "kind": kind, "status": st, "open": st in ("open", "overdue"),
                "owner": C.OWNER if kind == "money-in" else f"{C.OWNER} (pays)",
                "owed_to": C.OWNER if kind == "money-in" else who, "from": who if kind == "money-in" else C.OWNER,
                "amount": amt, "due": due or None, "asked_on": C.date(added) or C.date(due),
                "source": C.src(C.LEDGER, ln)})
            n.text = mask(f"{who} {proj} {what} {note_txt}")
            n.date = C.date(added)
            arrow = f"{who} -> {C.OWNER}" if kind == "money-in" else f"{C.OWNER} -> {who}"
            n.body = [f"**{arrow}: ${amt:,.2f}** · {mask(what)}", "",
                      f"- status: **{st}**" + (" (contingent: not counted as owed)" if st == "pending" else "")
                      + (f" · due {due}" if due else " · no due date"),
                      f"- project: {mask(proj)}"]
            if note_txt:
                n.body.append(f"- note: {mask(note_txt)}")
            n.body.append(f"- source: `{C.src(C.LEDGER, ln)}`")
            n.fm["project"] = self.mention_links(n, f"{who} {what}", proj)[:1] or None
            self.add(n)

    def load_decisions(self):
        """decisions.md: one decision per line, '2026-10-10 acme-site: text' (the kit's format), or a table row
        '| when | project | goal | decision | why | undo |'."""
        p = C.DECISIONS
        if not p or not p.is_file():
            return
        seen = set()
        for i, line in enumerate(open(p, errors="ignore"), 1):
            proj = goal = why = undo = ""
            b = re.match(r"\s*(?:[-*] )?~?(\d{4}-\d{2}-\d{2}|\d{2}-\d{2})(?:[ T]~?(\d{1,2}:\d{2}))?\s+"
                         r"(?:([\w.\-]+):\s+)?(.{10,})", line)
            if b and not line.startswith(("|", "#")):
                when = C.date(f"{b.group(1)} {b.group(2) or '00:00'}")
                proj, dec = b.group(3) or "", b.group(4).strip()
            elif line.startswith("| ") and not re.match(r"\|\s*(when|-+)\s*\|", line, re.I):
                cells = [x.strip() for x in line.strip().strip("|").split("|")]
                if len(cells) < 4:
                    continue
                when, proj, goal, dec = C.date(cells[0]), cells[1], cells[2], cells[3]
                why = cells[4] if len(cells) > 4 else ""
                undo = cells[5] if len(cells) > 5 else ""
            else:
                continue
            nid = f"d-{when[:16].replace(':', '').replace('T', '-')}-{slug(dec, 30)}"
            if nid in seen:
                continue
            seen.add(nid)
            dec = mask(dec)
            n = Note(nid, "decision", one(dec, 90), {"type": "decision", "when": when, "source": C.src(p, i)})
            n.text = f"{proj} {goal} {dec} {why}"
            n.date = when
            n.body = [f"**Decision ({when[:16].replace('T', ' ')}{', ' + proj if proj else ''}):** {dec}"]
            if goal:
                n.body.append(f"- serves: {mask(goal)}")
            if why:
                n.body.append(f"- why: {mask(why)}")
            if undo:
                n.body.append(f"- undo: {mask(undo)}")
            n.body.append(f"- source: `{C.src(p, i)}`")
            n.fm["project"] = self.mention_links(n, n.text, proj)[:1] or None
            self.add(n)

    def load_plans(self):
        """Plans (plans/<project>/*.md, the tab-plan skill): who owns what now. Orders a plan lists under
        '## Rows' ('- 3, 4 | the ask') get that plan's owner tab."""
        root = C.PLANS
        for p in sorted(root.rglob("*.md")) if root and root.is_dir() else []:
            if not C.allowed(p):
                continue
            t = mask(p.read_text(errors="ignore"))
            title = (re.match(r"#\s*(.+)", t) or re.match(r"(.+)", t) or [None, p.stem])[1].strip()
            st = re.search(r"Status:\s*([\w-]+)", t)
            owner = re.search(r"Owner tab:\s*([^|\n]+)", t)
            opened = re.search(r"Opened:\s*([\d\-T:]+)", t)
            done_cp, open_cp = len(re.findall(r"^- \[x\] CP", t, re.M | re.I)), len(re.findall(r"^- \[ \] CP", t, re.M))
            nid = "plan-" + slug(f"{p.parent.name}-{p.stem}", 70)
            n = Note(nid, "plan", title, {"type": "plan", "status": (st.group(1).lower() if st else None),
                                          "owner_tab": owner.group(1).strip() if owner else p.parent.name,
                                          "opened": C.date(opened.group(1)) if opened else C.mtime(p),
                                          "checkpoints": f"{done_cp}/{done_cp + open_cp}", "source": C.src(p)})
            n.text = t
            stamps = sorted(C.date(x) for x in re.findall(r"\b(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}|\d{2}-\d{2}T\d{2}:\d{2})\b",
                                                          C.section(t, "Progress log")))
            n.date = stamps[-1] if stamps else n.fm["opened"]
            n.body = [f"**Plan** · owner tab **{n.fm['owner_tab']}** · status {n.fm['status'] or '?'} · checkpoints "
                      f"{n.fm['checkpoints']} · updated {n.date[:16].replace('T', ' ')}", "", f"source: `{C.src(p)}`"]
            for h in ("Goal", "Next steps", "Rows", "Decisions needed", "Checkpoints"):
                body = C.section(t, h)
                if body:
                    n.body += ["", f"## {h}", body[:2500]]
            log = C.section(t, "Progress log").splitlines()
            if log:
                n.body += ["", "## Progress log (last 6)"] + log[-6:]
            ids = set()
            for line in C.section(t, "Rows").splitlines():
                m = re.match(r"\s*-\s*([\d,\s]+)\|", line)
                if m:
                    ids |= {int(x) for x in re.findall(r"\d+", m.group(1))}
            for i in sorted(ids):
                c = self.notes.get(f"c-order-{i}")
                if c:
                    n.link(c.id)
                    c.link(nid)
                    if (n.fm["status"] or "active") == "active":
                        c.fm["owner"] = n.fm["owner_tab"]
                        c.fm["plan"] = f"[[{nid}]]"
                        c.body.insert(2, f"- **owned since {n.fm['opened'][5:10]} by tab {n.fm['owner_tab']}** "
                                         f"via plan [[{nid}|{title}]]")
            self.mention_links(n, t[:4000], p.parent.name)
            self.add(n)

    def load_memory(self):
        """Claude memory folders (BRAIN_MEMORY_DIRS): feedback files become rules, the rest memory notes."""
        files = [p for d in C.MEMORY_DIRS if d.is_dir() for p in sorted(d.glob("*.md"))
                 if p.name != "MEMORY.md" and C.allowed(p)]
        for p in files:
            fm, _ = parse_fm(p.read_text(errors="ignore"))
            name = fm.get("name") or p.stem
            self.mem_names[compact(name)] = slug(name, 80)
            self.mem_names[compact(p.stem)] = slug(name, 80)
        for p in files:
            raw = p.read_text(errors="ignore")
            fm, body = parse_fm(raw)
            name = fm.get("name") or p.stem
            mtype = fm.get("type") or (p.stem.split("_")[0] if "_" in p.stem else "memory")
            mod = re.search(r"modified:\s*(\d{4}-\d{2}-\d{2}T\d{2}:\d{2})", raw[:1200])
            ntype = "rule" if mtype == "feedback" else "memory"
            desc = fm.get("description") or ""
            nid = slug(name, 80)
            if nid in self.notes:
                nid = slug(p.stem, 80)
            n = Note(nid, ntype, one(desc or name, 90), {
                "type": ntype, "memory_type": mtype, "description": mask(desc), "source": C.src(p),
                "modified": mod.group(1) if mod else C.mtime(p)})
            body = mask(body.strip())
            n.text = f"{name} {desc} {body}"
            n.raw = body
            n.date = n.fm["modified"]
            for ref in re.findall(r"\[\[([^\]|#]+)", body):
                tgt = self.mem_names.get(compact(ref))
                if tgt:
                    n.link(tgt)
            ps = self.mention_links(n, f"{desc}\n{body[:6000]}")
            n.body = [f"> {mask(desc)}" if desc else "", "",
                      body if len(body) < 6000 else body[:6000] + f"\n\n… (truncated; full file `{C.src(p)}`)", "",
                      f"source: `{C.src(p)}`"]
            if ps:
                n.body.append("mentions: " + ", ".join(f"[[{s}|{self.ents[s]['title']}]]" for s in ps))
            self.add(n)

    # ---------------- hubs (project + person notes)
    @staticmethod
    def _sentences(text):
        return [s.strip() for s in re.split(r"(?<=[.;!?])\s+|\n+| \| ", text or "") if len(s.strip()) > 20]

    MONEY_RX = re.compile(r"(?i)\$\s?\d[\d,.]*k?\b.*\b(owe|owed|owes|balance|invoice|unpaid|collect|deposit|retainer|due|"
                          r"paid|commission|split|%|bill)|\b(owe|owed|owes|balance|invoice|unpaid|collect|deposit|retainer|"
                          r"commission)\b.*\$\s?\d")

    def fill_hubs(self):
        backlinks = {}
        for n in self.notes.values():
            for t in n.links:
                backlinks.setdefault(t, []).append(n.id)
        for s, e in self.ents.items():
            hub = self.notes[s]
            refs = [self.notes[i] for i in backlinks.get(s, []) if i in self.notes]
            comm = [r for r in refs if r.type == "commitment"]
            open_c = sorted([c for c in comm if self.is_open(c)], key=lambda c: c.fm.get("asked_on") or "")
            closed_c = sorted([c for c in comm if not self.is_open(c)], key=lambda c: c.date or "", reverse=True)
            decs = sorted([r for r in refs if r.type == "decision"], key=lambda r: r.date, reverse=True)
            plans = sorted([r for r in refs if r.type == "plan"], key=lambda r: r.date, reverse=True)
            mems = sorted([r for r in refs if r.type in ("memory", "rule")], key=lambda r: r.date, reverse=True)
            reps = sorted([r for r in self.reports if s in r["ents"]], key=lambda r: r["when"], reverse=True)
            last = max([r["when"] for r in reps[:1]] + [d.date for d in decs[:1]] + [c.date for c in comm if c.date] + [""])
            co = {}
            for r in refs:
                for t in r.links:
                    if t in self.ents and t != s:
                        co[t] = co.get(t, 0) + 1
            money_open = sum(float(c.fm.get("amount") or 0) for c in open_c if c.fm.get("kind") == "money-in")
            hub.fm.update({"last_seen": last or None, "open_items": len(open_c),
                           "money_owed_to_us": round(money_open, 2) or None})
            hub.date = last
            b = hub.body
            b.append(f"**{e['type'].title()}**" + (f" · {e['role']}" if e.get("role") else "")
                     + (f" · {', '.join(e['emails'])}" if e.get("emails") else "")
                     + (f" · last activity {last[:10]}" if last else ""))
            b += ["", f"## Open items ({len(open_c)})"]
            b += [self._citem(c) for c in open_c] or ["- none on record"]
            money = [c for c in comm if c.fm.get("kind") in ("money-in", "money-out")]
            msents = []
            for x in mems[:40] + decs[:30]:
                for s_ in self._sentences(x.raw or x.text):
                    if self.MONEY_RX.search(s_) and (e["type"] == "project" or self.R.has(s, s_)):
                        msents.append((x.date, one(s_, 260), x.id))
            for r in reps[:60]:
                for s_ in self._sentences(r["msg"]):
                    if self.MONEY_RX.search(s_) and self.R.has(s, s_):
                        msents.append((r["when"], one(s_, 260), r["src"]))
            if money or msents:
                b += ["", "## Money"]
                for c in sorted(money, key=lambda c: (not self.is_open(c), c.fm.get("due") or "9")):
                    b.append(self._citem(c))
                seen = set()
                for d, s_, where in sorted(msents, key=lambda x: x[0], reverse=True)[:8]:
                    k = compact(s_)[:60]
                    if k in seen:
                        continue
                    seen.add(k)
                    ref = f"[[{where}]]" if where in self.notes else f"`{where}`"
                    b.append(f"- {d[:10]}: {s_} ({ref})")
            facts = self._key_facts(s, e, mems, reps)
            if facts:
                b += ["", "## Key facts (newest first, each cited)"] + facts
            if co:
                top = sorted(co.items(), key=lambda x: -x[1])[:14]
                b += ["", "## Connected", " · ".join(f"[[{t}|{self.ents[t]['title']}]]" for t, _ in top)]
                for t, _ in top:
                    hub.link(t)
            if plans:
                b += ["", "## Plans"] + [f"- [[{p.id}|{one(p.title, 110)}]] · {p.fm.get('status') or '?'} · "
                                         f"owner {p.fm.get('owner_tab')}" for p in plans[:8]]
            if decs:
                b += ["", "## Recent decisions"] + [f"- {d.date[:10]} [[{d.id}|{one(d.title, 110)}]]" for d in decs[:8]]
            if reps:
                b += ["", "## Recent reports"]
                b += [f"- {r['when'][:16].replace('T', ' ')} **{r['status']}** ({r['proj']}): {one(r['msg'], 240)}  `{r['src']}`"
                      for r in reps[:8]]
            if mems:
                b += ["", "## Memory notes"] + [f"- [[{m.id}|{one(m.title, 110)}]]" for m in mems[:15]]
            if closed_c:
                b += ["", f"## Closed items (latest {min(8, len(closed_c))} of {len(closed_c)})"]
                b += [self._citem(c) for c in closed_c[:8]]
            for x in open_c + closed_c[:8] + plans[:8] + decs[:8] + mems[:15]:
                hub.link(x.id)

    def _key_facts(self, s, e, mems, reps):
        out, seen = [], set()
        for m in mems[:12]:
            d = m.fm.get("description") or ""
            if d and (e["type"] == "project" or self.R.has(s, d)):
                k = compact(d)[:60]
                if k not in seen:
                    seen.add(k)
                    out.append(f"- {m.date[:10]}: {one(d, 300)} ([[{m.id}]])")
        if e["type"] == "person":
            for m in mems[:20]:
                for s_ in self._sentences(m.raw or m.text)[:80]:
                    if len(out) < 10 and self.R.has(s, s_):
                        k = compact(s_)[:60]
                        if k not in seen:
                            seen.add(k)
                            out.append(f"- {m.date[:10]}: {one(s_, 280)} ([[{m.id}]])")
            for r in reps[:20]:
                for s_ in self._sentences(r["msg"]):
                    if len(out) < 14 and self.R.has(s, s_):
                        k = compact(s_)[:60]
                        if k not in seen:
                            seen.add(k)
                            out.append(f"- {r['when'][:10]}: {one(s_, 280)} (`{r['src']}`)")
        return out[:14]

    @staticmethod
    def is_open(c):
        my = str(c.fm.get("my_status") or "").lower()
        if my:
            return my not in CLOSED
        return bool(c.fm.get("open"))

    @staticmethod
    def _citem(c):
        f = c.fm
        bits = [f.get("my_status") or f.get("status") or "?"]
        if f.get("amount"):
            bits.append(f"${float(f['amount']):,.0f}")
        if f.get("my_owner") or f.get("owner"):
            bits.append(f"owner {f.get('my_owner') or f.get('owner')}")
        if f.get("asked_on"):
            a = C.age_days(f["asked_on"])
            bits.append(f"asked {f['asked_on'][5:10]}" + (f" ({a:.0f}d ago)" if a is not None else ""))
        if f.get("due"):
            bits.append(f"due {f['due']}")
        elif f.get("kind") in ("money-in", "money-out"):
            bits.append("no due date")
        return f"- [[{c.id}|{one(c.title, 100)}]] · {' · '.join(bits)}"

    # ---------------- commitment scheduling + hand overrides
    def schedule(self):
        for n in self.notes.values():
            if n.type != "commitment":
                continue
            f = n.fm
            asked = C.dt(f.get("asked_on") or "") or NOW
            chase = asked + timedelta(days=CHASE_GAP.get(f.get("kind"), 3))
            if f.get("due"):
                d = C.dt(C.date(str(f["due"])))
                if d:
                    chase = d
            f["chase_after"] = f.get("my_chase_after") or chase.strftime("%Y-%m-%d")
            if f.get("my_link"):  # hand relabel: these entities replace the ones the source text matched
                want = [x.strip() for x in str(f["my_link"]).split(",") if x.strip() in self.ents]
                n.links = [x for x in n.links if x not in self.ents] + want
                n.body.insert(0, f"> Relabeled by hand: belongs to {', '.join(f'[[{x}]]' for x in want)} "
                                 f"(the source says otherwise; see my_note).\n")
            if f.get("my_title"):
                n.title = str(f["my_title"])
            for s in n.links:
                if s in self.ents and self.ents[s]["type"] == "person":
                    f.setdefault("people", [])
                    f["people"].append(f"[[{s}]]")
            if f.get("project"):
                f["project"] = f"[[{f['project'][0]}]]" if isinstance(f["project"], list) else f["project"]

    def _merge_existing(self):
        """Carry over my_* keys from notes already in the vault (hand edits win)."""
        for n in self.notes.values():
            p = self._path(n)
            if p.exists():
                fm, _ = parse_fm(p.read_text(errors="ignore"))
                for k, v in fm.items():
                    if k.startswith("my_") and v not in ("", []):
                        n.fm[k] = v

    # ---------------- write
    def build(self):
        t0 = time.time()
        self.load_hubs()
        self.load_orders()
        self.load_reports()
        self.load_ledger()
        self.load_decisions()
        self.load_plans()
        self.load_memory()
        self._merge_existing()
        self.schedule()
        self.fill_hubs()
        self._index_note()
        stats = self._write()
        stats["secs"] = round(time.time() - t0, 1)
        return stats

    def _path(self, n):
        if n.id == "index":
            return self.root / "index.md"
        return self.root / FOLDERS[n.type] / f"{n.id}.md"

    def _index_note(self):
        n = Note("index", "index", "Brain home", {"type": "index"})
        opens = self.open_items()
        n.body = ["Every open ask, item waiting on the " + C.OWNER + " and money item, oldest chase date first. One note "
                  "per project, person, commitment, decision, plan and rule; links go both ways.", "",
                  f"## Open items ({len(opens)}), chase in this order"]
        n.body += [self._citem(self.notes[o["id"]]) + f" · chase {o['chase_after']}" for o in opens[:60]]
        money = [c for c in self.notes.values() if c.type == "commitment" and c.fm.get("kind") in ("money-in", "money-out")]
        if money:
            n.body += ["", "## Money (ledger)"]
            groups = (("Owed to us now (open/overdue)", lambda c: c.fm["kind"] == "money-in" and self.is_open(c)),
                      ("Contingent (pending, not counted)", lambda c: c.fm["kind"] == "money-in" and c.fm.get("status") == "pending"),
                      ("We owe (open)", lambda c: c.fm["kind"] == "money-out" and self.is_open(c)))
            for label, pred in groups:
                sel = [c for c in money if pred(c)]
                tot = sum(float(c.fm.get("amount") or 0) for c in sel)
                n.body.append(f"- **{label}: ${tot:,.2f}** ({len(sel)} items)")
                n.body += ["  " + self._citem(c) for c in sel[:20]]
        n.body += ["", "## Projects", " · ".join(f"[[{s}|{e['title']}]]" for s, e in self.ents.items() if e["type"] == "project")]
        n.body += ["", "## People", " · ".join(f"[[{s}|{e['title']}]]" for s, e in self.ents.items() if e["type"] == "person")]
        n.links = list(self.ents)
        self.notes["index"] = n

    def open_items(self):
        out = []
        for n in self.notes.values():
            if n.type == "commitment" and self.is_open(n):
                f = n.fm
                out.append({"id": n.id, "title": n.title, "kind": f.get("kind"), "status": f.get("my_status") or f.get("status"),
                            "owner": f.get("my_owner") or f.get("owner"), "chase_after": f.get("chase_after"),
                            "asked_on": f.get("asked_on")})
        out.sort(key=lambda o: (o["chase_after"] or "9999", o["asked_on"] or ""))
        return out

    def _write(self):
        self.root.mkdir(parents=True, exist_ok=True)
        for f in FOLDERS.values():
            (self.root / f).mkdir(exist_ok=True)
        backlinks = {}
        for n in self.notes.values():
            for t in n.links:
                if t in self.notes:
                    backlinks.setdefault(t, []).append(n.id)
        written, keep = 0, set()
        for n in sorted(self.notes.values(), key=lambda x: x.id):
            p = self._path(n)
            keep.add(p)
            user_part = ""
            if p.exists():
                old = p.read_text(errors="ignore")
                if GEN_END in old:
                    user_part = old.split(GEN_END, 1)[1]
            bl = [b for b in backlinks.get(n.id, []) if b not in n.links]
            body = [f"# {n.title}", ""] + n.body
            outs = [x for x in n.links if x in self.notes]
            if outs and n.type in ("commitment", "decision"):
                body += ["", "links: " + " · ".join(f"[[{x}|{one(self.notes[x].title, 50)}]]" for x in outs)]
            if bl:
                body += ["", f"## Backlinks ({len(bl)})"] + [f"- [[{b}|{one(self.notes[b].title, 90)}]]" for b in
                                                            sorted(bl, key=lambda x: (self.notes[x].date or "", x), reverse=True)[:40]]
            fm = dict(n.fm)
            fm["title"] = n.title
            text = C.frontmatter(fm) + "\n" + GEN_START + "\n" + "\n".join(body).rstrip() + "\n" + GEN_END + (user_part or "\n")
            if not p.exists() or p.read_text(errors="ignore") != text:
                p.write_text(text)
                written += 1
        # notes whose source disappeared: delete only if nobody wrote in them
        removed = 0
        for f in FOLDERS.values():
            for p in (self.root / f).glob("*.md"):
                if p in keep:
                    continue
                old = p.read_text(errors="ignore")
                fm, _ = parse_fm(old)
                if (old.split(GEN_END, 1)[1].strip() if GEN_END in old else old.strip()) or any(k.startswith("my_") for k in fm):
                    continue
                p.unlink()
                removed += 1
        nodes = sorted(self.notes.values(), key=lambda x: x.id)
        graph = {"built": NOW.strftime("%Y-%m-%dT%H:%M"),
                 "nodes": [{"id": n.id, "type": n.type, "title": n.title, "open": self.is_open(n) if n.type == "commitment" else None,
                            "kind": n.fm.get("kind"), "status": n.fm.get("my_status") or n.fm.get("status"),
                            "date": (n.date or "")[:10], "deg": len(n.links) + len(backlinks.get(n.id, []))} for n in nodes],
                 "links": [[n.id, t] for n in nodes for t in n.links if t in self.notes]}
        tmp = self.root / ".brain.json.tmp"
        tmp.write_text(json.dumps(graph, ensure_ascii=False, indent=0) + "\n")
        tmp.replace(self.root / ".brain.json")
        counts = {}
        for n in self.notes.values():
            counts[n.type] = counts.get(n.type, 0) + 1
        return {"notes": len(self.notes), "by_type": dict(sorted(counts.items())), "links": len(graph["links"]),
                "written": written, "removed": removed, "open_items": len(self.open_items())}


# ------------------------------------------------------------------ read side (MCP tools, page, hook)
class Vault:
    """Reads the built vault (cheap; reloads when .brain.json changes)."""

    STOP = set("what whats which who whom whose when where why how is are was were did does do the a an of for to on in "
               "and or our we us my me it its this that there right now any got get has have been with from about "
               "still yet left done".split())

    def __init__(self, root=None):
        self.root = Path(root or C.VAULT)
        self.mt = 0
        self.g = {"nodes": [], "links": []}
        self.nodes, self.out, self.inn, self.alias = {}, {}, {}, {}

    def load(self):
        p = self.root / ".brain.json"
        try:
            mt = p.stat().st_mtime
        except OSError:
            return self
        if mt != self.mt:
            self.g = json.loads(p.read_text())
            self.mt = mt
            self.__dict__.pop("kw", None)
            self.nodes = {n["id"]: n for n in self.g["nodes"]}
            self.out, self.inn = {}, {}
            for a, b in self.g["links"]:
                self.out.setdefault(a, []).append(b)
                self.inn.setdefault(b, []).append(a)
            self.alias = {}
            for n in self.g["nodes"]:
                self.alias.setdefault(compact(n["id"]), n["id"])
                if n["type"] in ("project", "person"):
                    self.alias.setdefault(compact(n["title"]), n["id"])
                    fm, _ = parse_fm(self.read(n["id"]))
                    for a in (fm.get("aliases") or []) + (fm.get("emails") or []):
                        self.alias.setdefault(compact(a), n["id"])
        return self

    def note_path(self, nid):
        if nid == "index":
            return self.root / "index.md"
        n = self.nodes.get(nid)
        return self.root / FOLDERS.get(n["type"] if n else "memory", "memory") / f"{nid}.md"

    def read(self, nid):
        p = self.note_path(nid)
        return p.read_text(errors="ignore") if p.exists() else ""

    def resolve(self, name):
        self.load()
        q = re.sub(r"(?i)'s\b", "", (name or "").strip())
        c = compact(q)
        if c in self.alias:
            return [self.alias[c]]
        # every word: an alias inside a question ("what does dana still owe us")
        words = re.findall(r"[A-Za-z0-9.@\-]+", q)
        hits = []
        for i in range(len(words)):
            for j in (3, 2, 1):
                k = compact(" ".join(words[i:i + j]))
                if len(k) >= 3 and k in self.alias and self.alias[k] not in hits:
                    hits.append(self.alias[k])
        if hits:
            # a person is more specific than a project ("Dana's invoice on acme-site" -> Dana first)
            hubs = [h for h in hits if self.nodes[h]["type"] == "person"] + \
                   [h for h in hits if self.nodes[h]["type"] == "project"]
            return hubs + [h for h in hits if h not in hubs]
        kw = self.keyword(q)
        if kw:
            return kw
        cands = [n["id"] for n in self.g["nodes"] if c and (c in compact(n["title"]) or c in compact(n["id"]))]
        cands.sort(key=lambda i: (self.nodes[i]["type"] not in ("person", "project"), -self.nodes[i]["deg"]))
        return cands[:5]

    def keyword(self, q):
        """No entity named: best notes by word overlap (title x3), hubs/commitments/plans first."""
        if not hasattr(self, "kw"):
            self.kw = {}
            for n in self.g["nodes"]:
                if n["type"] in ("project", "person", "commitment", "plan", "decision"):
                    body = re.sub(r"<!--.*?-->", " ", self.read(n["id"]))[:3000].lower()
                    self.kw[n["id"]] = (n["title"].lower(), body)
        terms = [t for t in re.findall(r"[a-z0-9][a-z0-9\-]+", q.lower()) if t not in self.STOP and len(t) > 2]
        if not terms:
            return []

        def stem(t):
            return t[:5] if len(t) > 5 else t
        sc = []
        for nid, (title, body) in self.kw.items():
            s_ = sum(3 * (stem(t) in title) + (stem(t) in body) for t in terms)
            if s_:
                pri = {"project": 1.0, "person": 1.0, "commitment": 0.9, "plan": 0.8, "decision": 0.7}[self.nodes[nid]["type"]]
                sc.append((s_ * pri, nid))
        sc.sort(reverse=True)
        return [nid for s_, nid in sc[:5] if s_ >= max(3, sc[0][0] * 0.6)] if sc else []

    def brain(self, entity, max_chars=12000):
        ids = self.resolve(entity)
        if not ids:
            return {"entity": entity, "found": False, "note": "no note matches; try brain_open() or another name",
                    "candidates": []}
        nid = ids[0]
        fm, body = parse_fm(self.read(nid))
        nb = []
        for t in list(dict.fromkeys(self.out.get(nid, []) + self.inn.get(nid, []))):
            n = self.nodes.get(t)
            if n:
                nb.append({"id": t, "type": n["type"], "title": n["title"], "status": n.get("status"), "open": n.get("open"),
                           "date": n.get("date"), "path": str(self.note_path(t))})
        order = {"commitment": 0, "person": 1, "project": 1, "plan": 2, "decision": 2, "rule": 3, "memory": 4}
        nb.sort(key=lambda x: (not x.get("open"), order.get(x["type"], 5), -(int(x["date"].replace("-", "") or 0) if x.get("date") else 0)))
        open_items = []
        for x in nb:
            if x["type"] == "commitment" and x.get("open"):
                f, b = parse_fm(self.read(x["id"]))
                if str(f.get("my_status") or "").lower() in CLOSED:
                    continue
                open_items.append({"id": x["id"], "title": x["title"], "kind": f.get("kind"), "status": f.get("my_status") or f.get("status"),
                                   "owner": f.get("my_owner") or f.get("owner"), "amount": f.get("amount"), "asked_on": f.get("asked_on"),
                                   "chase_after": f.get("my_chase_after") or f.get("chase_after"),
                                   "detail": one(re.sub(r"<!--.*?-->|\n#.*", " ", b), 500), "source": f.get("source")})
        body = re.sub(r"<!--.*?-->\n?", "", body)
        return {"entity": entity, "found": True, "id": nid, "type": self.nodes[nid]["type"], "path": str(self.note_path(nid)),
                "frontmatter": fm, "note": body[:max_chars] + ("\n…(truncated)" if len(body) > max_chars else ""),
                "open_items": open_items, "neighbors": nb[:40], "other_matches": ids[1:5]}

    def brain_open(self, owner=None, kind=None, limit=60):
        self.load()
        out = []
        for n in self.g["nodes"]:
            if n["type"] != "commitment" or not n.get("open"):
                continue
            f, _ = parse_fm(self.read(n["id"]))
            if str(f.get("my_status") or "").lower() in CLOSED:
                continue  # closed by hand since the last build
            o = f.get("my_owner") or f.get("owner") or ""
            if owner and compact(owner) not in compact(o):
                continue
            if kind and kind != f.get("kind"):
                continue
            out.append({"id": n["id"], "title": f.get("my_title") or n["title"], "kind": f.get("kind"),
                        "status": f.get("my_status") or f.get("status"), "owner": o, "owed_to": f.get("owed_to"),
                        "amount": f.get("amount"), "asked_on": f.get("asked_on"), "age_days": C.age_days(f.get("asked_on") or ""),
                        "chase_after": f.get("my_chase_after") or f.get("chase_after"),
                        "project": f.get("project"), "people": f.get("people"), "source": f.get("source")})
        out.sort(key=lambda o: (o["chase_after"] or "9999", o["asked_on"] or ""))
        return {"count": len(out), "built": self.g.get("built"), "items": out[:limit]}

    def mark(self, nid, status=None, owner=None, chase_after=None, note=None, link=None, title=None):
        """Hand-owned override on a note (my_* frontmatter keys): survives every rebuild."""
        self.load()
        p = self.note_path(nid)
        if nid not in self.nodes or not p.exists():
            return {"ok": False, "error": f"no note '{nid}'"}
        text = p.read_text(errors="ignore")
        m = re.match(r"---\n(.*?)\n---\n", text, re.S)
        if not m:
            return {"ok": False, "error": "note has no frontmatter"}
        if chase_after and not re.fullmatch(r"\d{4}-\d{2}-\d{2}", str(chase_after)):
            return {"ok": False, "error": "chase_after must be YYYY-MM-DD"}
        lines = m.group(1).splitlines()
        upd = {"my_status": status, "my_owner": owner, "my_chase_after": chase_after,
               "my_note": f"{NOW.strftime('%Y-%m-%d')}: {note}" if note else None, "my_link": link, "my_title": title}
        for k, v in upd.items():
            if v is None:
                continue
            lines = [x for x in lines if not x.startswith(k + ":")] + [f"{k}: {C.yaml_val(mask(str(v)))}"]
        p.write_text("---\n" + "\n".join(lines) + "\n---\n" + text[m.end():])
        return {"ok": True, "id": nid, "set": {k: v for k, v in upd.items() if v is not None}, "path": str(p)}

    def open_text(self, n=15):
        r = self.brain_open(limit=n)
        lines = [f"## Brain: {r['count']} open items (asks, waiting on the {C.OWNER}, money), chase order. "
                 f"Full list: brain_open(); one entity: brain(name). Vault: {self.root}"]
        for o in r["items"]:
            age = f"{o['age_days']:.0f}d" if o["age_days"] is not None else "?"
            amt = f" ${float(o['amount']):,.0f}" if o.get("amount") else ""
            lines.append(f"- [{o['kind']}|{o['status']}|owner {o['owner']}|{age} old|chase {o['chase_after']}]{amt} {o['title']}  ({o['id']})")
        return "\n".join(lines)
