"""Shared config, dates, frontmatter and secret masking for brain-loop.

Every path comes from the environment. bin/brain-loop fills it from the kit config ($LK_CONFIG, see config.example,
section "brain-loop"), so `python3 -m brainloop` with no env at all still works on the kit's defaults.
"""
import json
import os
import re
import shlex
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path


def _p(name, default=""):
    v = os.environ.get(name, "").strip() or default
    return Path(os.path.expanduser(v)) if v else None


LK_HOME = _p("LK_HOME", "~/.pierce-skill-kit")
VAULT = _p("BRAIN_VAULT", str(LK_HOME / "brain"))
REPORTS = _p("BRAIN_REPORTS", str(LK_HOME / "reports.tsv"))
ORDERS = _p("BRAIN_ORDERS", str(LK_HOME / "orders.tsv"))
DECISIONS = _p("BRAIN_DECISIONS", str(LK_HOME / "decisions.md"))
PLANS = _p("BRAIN_PLANS", str(LK_HOME / "plans"))
ENTITIES = _p("BRAIN_ENTITIES", str(LK_HOME / "brain-entities.json"))
LEDGER = _p("BRAIN_LEDGER")  # optional money ledger TSV; unset = no money notes
MEMORY_DIRS = [Path(os.path.expanduser(x)) for x in os.environ.get("BRAIN_MEMORY_DIRS", "").split(":") if x.strip()]
ROUTER_DIR = _p("BRAIN_ROUTER_DIR", str(LK_HOME / "brain-loop"))
COMPLIANCE = _p("BRAIN_COMPLIANCE", str(LK_HOME / "compliance.tsv"))
SOURCE_ROOT = _p("BRAIN_SOURCE_ROOT")  # show source paths relative to this (the example vault uses it)
OWNER = os.environ.get("BRAIN_OWNER", "").strip() or "owner"  # the human, as notes name them
LEAD_DIR = _p("LK_LEAD_DIR", "~/lead")
LEAD_TARGET = os.environ.get("LK_LEAD", "hub:Lead")
SAY_CMD = os.environ.get("BRAIN_SAY", "").strip()  # optional command that messages the lead (gets the text as $1)
CLAUDE_CMD = os.environ.get("LK_CLAUDE", "").strip() or "claude"
GRADE_MODEL = os.environ.get("BRAIN_GRADE_MODEL", "").strip() or "sonnet"
JEV_URL = os.environ.get("BRAIN_JEV_URL", "").strip() or "https://openrouter.ai/api/alpha/decisions"
JEV_MODEL = os.environ.get("LK_CHECK_MODEL", "").strip() or "typesafe/jev-1.13"
KEY_FILE = _p("LK_CHECK_KEY_FILE", "~/.secrets/openrouter.env")
JEV_CAP = float(os.environ.get("BRAIN_JEV_CAP_USD", "0") or 0)          # monthly $ cap; 0 = Jev gate closed
JEV_DAY_ALERT = float(os.environ.get("BRAIN_JEV_DAY_ALERT_USD", "0") or 0) or JEV_CAP / 10

# BRAIN_NOW pins "now" (the example vault and the tests use it); otherwise UTC now, like every kit log
NOW = datetime.fromisoformat(os.environ["BRAIN_NOW"][:16]) if os.environ.get("BRAIN_NOW") else datetime.now(timezone.utc).replace(tzinfo=None, second=0, microsecond=0)
YEAR = NOW.year

GEN_START = "<!-- brain:generated (rebuilt on every refresh; write your own notes below the end marker) -->"
GEN_END = "<!-- /brain:generated -->"
CLOSED = {"done", "closed", "paid", "void", "dropped", "cancelled", "superseded"}

# never read anything under these
FORBIDDEN = ("/.secrets", "/.env", ".env.", "/node_modules/", "/.git/")

_SECRET_RX = [
    re.compile(r"\b(sk|rk|pk)_(live|test)_[A-Za-z0-9]{8,}"),
    re.compile(r"\bsk-(ant-|proj-|or-v1-)?[A-Za-z0-9_\-]{16,}"),
    re.compile(r"\bgh[pousr]_[A-Za-z0-9]{20,}"),
    re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}"),
    re.compile(r"\bxox[abprs]-[A-Za-z0-9\-]{10,}"),
    re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
    re.compile(r"\bAIza[0-9A-Za-z_\-]{30,}"),
    re.compile(r"\beyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}"),
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"),
    re.compile(r"(?i)(bearer\s+)[A-Za-z0-9._\-]{20,}"),
    # KEY=value / "key": "value" / key: value, quoted or not
    re.compile(r"(?i)\b([A-Z0-9_]*(?:api[_-]?key|secret|token|password|passwd|pwd|private[_-]?key|auth)[A-Z0-9_]*)"
               r"(\s*[:=]\s*[\"']?)([^\s\"'`,;}{]{8,})"),
]


def mask(text):
    for rx in _SECRET_RX:
        if rx.groups >= 3:
            text = rx.sub(lambda m: f"{m.group(1)}{m.group(2)}[masked]", text)
        elif rx.groups == 1 and rx.pattern.startswith("(?i)(bearer"):
            text = rx.sub(lambda m: f"{m.group(1)}[masked]", text)
        else:
            text = rx.sub("[masked]", text)
    return text


def allowed(path):
    p = str(path)
    return not any(f in p for f in FORBIDDEN) and not p.endswith(".env")


def compact(s):
    return re.sub(r"[^a-z0-9]", "", (s or "").lower())


def src(path, line=None):
    """A source path as notes show it: relative to BRAIN_SOURCE_ROOT when it's under it."""
    p = Path(path)
    if SOURCE_ROOT:
        try:
            p = p.resolve().relative_to(SOURCE_ROOT.resolve())
        except ValueError:
            pass
    return f"{p}#L{line}" if line else str(p)


# ------------------------------------------------------------------ dates
def date(s, fallback=""):
    """'2026-10-09T10:15Z' / '2026-10-09 10:15' / '10-09 10:15' / '10-17T02:54' -> '2026-10-09T10:15'"""
    s = (s or "").strip()
    m = re.match(r"(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{1,2}:\d{2}))?", s)
    if m:
        return f"{m.group(1)}-{m.group(2)}-{m.group(3)}T{(m.group(4) or '00:00').zfill(5)}"
    m = re.match(r"~?(\d{2})-(\d{2})(?:[ T]~?(\d{1,2}:\d{2}))?", s)
    if m:
        return f"{YEAR}-{m.group(1)}-{m.group(2)}T{(m.group(3) or '00:00').zfill(5)}"
    return fallback


def dt(s):
    try:
        return datetime.fromisoformat((s or "")[:16])
    except (ValueError, TypeError):
        return None


def age_days(s):
    d = dt(s)
    return round((NOW - d).total_seconds() / 86400, 1) if d else None


def mtime(p):
    return datetime.fromtimestamp(Path(p).stat().st_mtime, timezone.utc).strftime("%Y-%m-%dT%H:%M")


def slug(s, n=48):
    s = re.sub(r"[^a-z0-9]+", "-", (s or "").lower()).strip("-")
    return s[:n].rstrip("-") or "x"


def one(s, n=200):
    s = re.sub(r"\s+", " ", s or "").strip()
    return s if len(s) <= n else s[:n - 1].rstrip() + "…"


# ------------------------------------------------------------------ frontmatter
def yaml_val(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    return json.dumps(str(v), ensure_ascii=False)


def frontmatter(fm):
    out = ["---"]
    for k, v in fm.items():
        if v is None or v == "" or v == []:
            continue
        if isinstance(v, (list, tuple)):
            out.append(f"{k}:")
            out += [f"  - {yaml_val(x)}" for x in v]
        else:
            out.append(f"{k}: {yaml_val(v)}")
    out.append("---")
    return "\n".join(out)


def _unq(v):
    v = v.strip()
    if v.startswith('"'):
        try:
            return json.loads(v)
        except ValueError:
            return v.strip('"')
    if v in ("true", "false"):
        return v == "true"
    if re.fullmatch(r"-?\d+", v):
        return int(v)
    if re.fullmatch(r"-?\d+\.\d+", v):
        return float(v)
    return v.strip("'")


def parse_fm(text):
    """Tiny YAML reader for our own frontmatter: scalars and '- item' lists."""
    fm, key = {}, None
    m = re.match(r"---\n(.*?)\n---\n?", text, re.S)
    if not m:
        return fm, text
    for line in m.group(1).splitlines():
        li = re.match(r"\s+-\s+(.*)", line)
        if li and key:
            fm.setdefault(key, [])
            if isinstance(fm[key], list):
                fm[key].append(_unq(li.group(1)))
            continue
        kv = re.match(r"([A-Za-z_][\w\-]*):\s*(.*)", line)
        if kv:
            key = kv.group(1)
            fm[key] = _unq(kv.group(2)) if kv.group(2).strip() else []
    return fm, text[m.end():]


def section(t, head):
    """Body of a '## <head>...' markdown section ('' if missing)."""
    m = re.search(rf"^## {head}.*?$(.*?)(?=^## |\Z)", t, re.S | re.M)
    return m.group(1).strip() if m else ""


# ------------------------------------------------------------------ the lead
def say(text):
    """Tell the lead something: BRAIN_SAY if set, else type it into the lead's tmux window like tab-watch does."""
    try:
        if SAY_CMD:
            return subprocess.run(shlex.split(SAY_CMD) + [text], timeout=60).returncode == 0
        ok = subprocess.run(["tmux", "send-keys", "-t", LEAD_TARGET, "-l", text], timeout=20).returncode == 0
        time.sleep(0.5)
        return ok and subprocess.run(["tmux", "send-keys", "-t", LEAD_TARGET, "Enter"], timeout=20).returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False
