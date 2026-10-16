#!/bin/sh
# Checks skill-route-sync (index, router auto section, hand rows untouched, confirm, dry run, kit check) and the
# skill-recommender hooks (fires on a tough prompt, quiet on chit-chat, no repeats, suggests after 2 failures, log).
#   sh tests/skills-test.sh      (needs node)
cd "$(dirname "$0")/.." || exit 1
command -v node >/dev/null || { echo "skills test skipped: no node"; exit 0; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
mk() { mkdir -p "$T/skills/$1"; printf -- '---\nname: %s\ndescription: %s\n---\nbody\n' "$1" "$2" > "$T/skills/$1/SKILL.md"; }
mk lip-sync-and-gaze-qc "Use when a talking shot looks off: mouth moves before the words, lip sync drift, gaze drifts off-lens."
mk cold-email "Write B2B cold emails and follow-up sequences that get replies."
mk privacy-manifest-check "Detects missing PrivacyInfo.xcprivacy privacy manifest files for iOS App Store review."
mk website-build "Recipe for a premium marketing website: React, Tailwind, GSAP, visual verify."
mkdir -p "$T/skills/folded"; printf -- '---\nname: folded\ndescription: >-\n  A folded description\n  over two lines about video captions.\n---\n' > "$T/skills/folded/SKILL.md"
printf '# Router\n| Job | Skill |\n|---|---|\n| Cold outreach | `cold-email` |\n' > "$T/router.md"
export SKILL_DIRS="$T/skills" SKILL_INDEX="$T/index.json" SKILL_ROUTER="$T/router.md" SKILL_CONFIRMED="$T/conf.json"

# --- skill-route-sync ---
out=$(bin/skill-route-sync --dry-run); [ ! -f "$T/index.json" ] || fail "dry run wrote the index"
echo "$out" | grep -q "new (5)" || fail "dry run didn't list 5 new skills: $out"
bin/skill-route-sync >/dev/null || fail "sync exited non-zero"
node -e 'const i=require(process.argv[1]); if(i.count!==5) process.exit(1); if(!/folded description over two lines/.test(i.skills.folded.description)) process.exit(2)' "$T/index.json" || fail "index count or folded description wrong"
grep -q '| Cold outreach | `cold-email` |' "$T/router.md" || fail "hand-written row changed"
grep -q 'skill-route-sync:auto start' "$T/router.md" || fail "no auto section"
grep -q '`cold-email` |.*auto' "$T/router.md" && fail "a hand-routed skill was repeated in the auto section"
grep -q '`lip-sync-and-gaze-qc`.*auto, review' "$T/router.md" || fail "new skill not routed as auto, review"
[ "$(bin/skill-route-sync)" = "$(printf '5 skills indexed -> %s\nno changes' "$T/index.json")" ] || fail "second run not idempotent"
bin/skill-route-sync --confirm lip-sync-and-gaze-qc "Quality & grading" >/dev/null || fail "confirm failed"
grep -q '`lip-sync-and-gaze-qc`.*| reviewed |' "$T/router.md" || fail "confirmed skill still marked for review"
grep -q '### Quality & grading' "$T/router.md" || fail "confirmed category not used"
bin/skill-route-sync --confirm nope >/dev/null 2>&1 && fail "confirm accepted an unknown skill"
rm -rf "$T/skills/folded"; bin/skill-route-sync | grep -q -- "- folded" || fail "removed skill not reported"
mkdir -p "$T/kit/skills"; cp -r "$T/skills/cold-email" "$T/skills/website-build" "$T/kit/skills/"
printf '| `cold-email` | x |\n' > "$T/kit/SKILLS.md"
bin/skill-route-sync --kit "$T/kit" >/dev/null && fail "kit check passed with a skill missing from SKILLS.md"
[ -f "$T/kit/skills/index.json" ] || fail "kit index not written"

# --- skill-recommender ---
# scores scale with the number of installed skills; this index has 5, a real one hundreds
R=mods/skill-recommender/recommend.js; export SKILL_REC_DIR="$T/rec" SKILL_REC_MIN=5
hook() { printf '%s' "$2" | node "$R" "$1"; }
o=$(hook prompt '{"session_id":"s1","prompt":"the talking head clip has lip sync drift, the mouth moves before the words"}')
echo "$o" | grep -q 'lip-sync-and-gaze-qc' || fail "no suggestion on a tough prompt: $o"
echo "$o" | grep -q 'Switch to <skill>?' || fail "suggestion lacks the one-line ask"
[ -z "$(hook prompt '{"session_id":"s1","prompt":"yes"}')" ] || fail "fired on 'yes'"
[ -z "$(hook prompt '{"session_id":"s2","prompt":"what time is it in Berlin"}')" ] || fail "fired on chit-chat"
grep -q '"outcome":"accepted"' "$T/rec/log.jsonl" || fail "'yes' after a suggestion not logged as accepted"
[ -z "$(hook prompt '{"session_id":"s1","prompt":"fix the lip sync drift on the talking head clip again"}')" ] || fail "re-suggested the same skill in a session"
hook prompt '{"session_id":"s3","prompt":"write a sequence of follow ups for outreach to prospects"}' >/dev/null
f='{"session_id":"s3","hook_event_name":"PostToolUseFailure","tool_name":"Bash","error":"cold email template missing for the B2B follow-up sequence"}'
[ -z "$(hook tool "$f")" ] || fail "suggested after one failure"
hook tool "$f" | grep -q 'cold-email' || fail "no suggestion after the second failure"
o=$(printf '{"session_id":"s4","prompt":"%s"}' "add the privacy manifest check to the landing page site build" | node "$R" prompt)
echo "$o" | grep -q 'privacy-manifest-check' && fail "Apple-only skill suggested without an Apple word"
grep -q 'talking head' "$T/rec/log.jsonl" && fail "log stores prompt text"
node "$R" stats | grep -q 'suggestions' || fail "stats line missing"
SKILL_REC_OFF=1 hook prompt '{"session_id":"s5","prompt":"the talking head clip has lip sync drift, the mouth moves before the words"}' | grep -q . && fail "SKILL_REC_OFF didn't silence it"
echo "skills test passed"
