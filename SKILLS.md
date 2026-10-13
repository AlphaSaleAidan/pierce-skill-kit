# Skills

Everything in `skills/` was written for real production work and then generalized: no client names, no
private infra, placeholders where you plug in your own values. Each folder is a standard Claude Code skill
(`SKILL.md` + small scripts/references). Copy the ones you want into `~/.claude/skills/`. A ready
use-case → skill table lives in [`skill-router.md`](skill-router.md).

Scripts marked **untested as generalized** in their own `Status` section were rewritten from job scripts
without a fresh end-to-end run. Try them on a few frames first.

## Lead & tabs
| Skill | What it does | When to use | Needs |
|---|---|---|---|
| `terminal-lead` | How the lead session runs tabs, briefs, orders and reports | Every lead monitor round | this kit, tmux |
| `project-tab` | How a project tab plans, uses subagents, proves work and reports | Start of every brief | this kit |
| `codex` | Hands a build, fix round or adversarial review to a Codex model; Claude keeps the brief, secrets and verification | Big builds, mechanical grinds, second-model review of money-path diffs | Codex CLI + an OpenAI account |

## Quality & grading
| Skill | What it does | When to use | Needs |
|---|---|---|---|
| `video-qc-reviewer` | Fresh-eyes frame-by-frame QC: machine checks, contact sheets, client-zoom crops, a severity-ranked findings table | Before any video goes to a client, or when "it looks off" | ffmpeg, Python (OpenCV, Pillow) |
| `lip-sync-and-gaze-qc` | Measures lip lag (mouth vs voice) and gaze/head angle; picks the best clip window; mouth-only re-sync | A talking shot looks off, or choosing which seconds of an AI clip to use | Python, mediapipe, ffmpeg; FaceFusion for gaze edits |
| `phone-qa` | Grades a Vapi phone agent against a written bar: programmatic call grader, simulated test callers, rubric judge, capped fix loop | After building a phone agent, or when it "sounds robotic/laggy" | Vapi API key; test calls are metered (dry run prints the cost first) |

## Video & 3D production
| Skill | What it does | When to use | Needs |
|---|---|---|---|
| `commercial-production-pipeline` | The gates for a client video job: brief, reference breakdown, storyboard sign-off, build, QC, review rounds, delivery rules | Any client ad/spot/edit end to end, or a job stuck in revision loops | — (links the specialist skills) |
| `studio-vfx` | Recreate a reference video's motion-graphics look with your own footage: effect breakdown, brand DNA, named components, RVM matte, composite, review | "Make our footage look like this reference" | ffmpeg, Python + onnxruntime (RVM model), a browser; optional image-generation API |
| `kinetic-type-physics` | Per-letter kinetic typography engine (springs, velocity blur, echoes) + an 18-effect catalogue + a frame-exact verification loop | Text "flying around" in a reference and yours looks basic | Node, a headless Chrome/puppeteer, ffmpeg, Python (Pillow) |
| `higgsfield-production-routing` | Which Higgsfield model/MCP call for which production job, call patterns, refusal handling, what failed | Choosing a model, or a Higgsfield job failed/was refused | Higgsfield MCP (paid credits) |
| `greenscreen-to-ai-plate-comp` | Green-screen talent into a generated location: AI merge vs raw key over an animated, depth-blurred plate | Composite looks pasted, floats, or the plate is a dead still | Higgsfield (or similar), ffmpeg, Python, Depth Anything V2 Small |
| `blender-set-from-storyboard` | Build a Blender set from boards: cameras matched "relatively close", continuity checks, depth passes, browser tour | A commercial needs a 3D layout from storyboard panels | Blender 4.2+, Python |
| `performance-voice-conversion` | Convert an actor's original performance into a **consenting** target voice (Seed-VC), warp new words, measured phone EQ | Re-voicing a line with the owner's written consent | Seed-VC on a GPU, ffmpeg + rubberband, Python (scipy) |
| `edit-rebuild-from-clean-sources` | Rebuild a social edit from clean sources: sample-accurate music sync, cadence map, per-section grade, jitter-free framing | Remaking/upgrading a TikTok/Reels edit you have rights to | ffmpeg, yt-dlp, Python (numpy/scipy) |
| `ai-video-logo-replace` | Swap a wrong printed logo on an AI clip without regenerating: HSV detect, track, inpaint, multiply-blend | A good generation came back with the wrong label | Python (OpenCV, Pillow), ffmpeg |
| `beat-synced-overlays` | Kick-scored flash frames, double exposures and ghost overlays as a separate overlay pass | A montage feels flat or accents land off the beat | Python (numpy/scipy, Pillow) |
| `remote-gpu-render` | Run FaceFusion / Real-ESRGAN / Seed-VC on a Windows NVIDIA PC you own over SSH; CUDA gotchas; verify from the output file | A GPU job is too slow on a CPU server | A Windows PC with an NVIDIA card, OpenSSH |

## Design & web
| Skill | What it does | When to use | Needs |
|---|---|---|---|
| `website-build` | Recipe for a premium marketing/ecommerce site that doesn't read as AI-generated: direction pass, real assets, React/Vite/Tailwind/GSAP/Lenis build, visual verify | New site, landing page, or "remake this website" | Node, Playwright; optional image/video generation API |

## Sales & decks
| Skill | What it does | When to use | Needs |
|---|---|---|---|
| `deck` | Pitch-deck pipeline: sourced brief → build → capture every slide → rubric grade → fix rounds until every slide passes → share only a link that returns 200 | "Build/finish/grade the deck" | Node + Playwright, Python; a vision-capable reviewer subagent |

## Ops & accounts
| Skill | What it does | When to use | Needs |
|---|---|---|---|
| `credit-discipline-for-generation` | Storyboard + quote before spend, cheapest probe first, stills before video, a credit log that doubles as the invoice line | Before spending any paid generation credits or metered API calls | — |

## Recommended third-party skills
Installed alongside these and worth having. Link, don't copy — install from the source. Licenses below were
read from the LICENSE file each project ships; "see repo" means not verified here.

| Skills | Source | License |
|---|---|---|
| superpowers (brainstorming, writing-plans, executing-plans, systematic-debugging, verification-before-completion, …) | https://github.com/obra/superpowers | MIT |
| grill-me, handoff, tdd, codebase-design, diagnosing-bugs, … | https://github.com/mattpocock/skills | MIT |
| design-motion-principles | https://github.com/kylezantos/design-motion-principles | MIT |
| video-use | https://github.com/browser-use/video-use | MIT |
| brag (launch video from a project's code) | https://github.com/latent-spaces/brag | MIT |
| gsap-* (core, scrolltrigger, react, timeline, …) | https://github.com/greensock/gsap-skills | MIT |
| taste-skill (taste-core, soft/minimalist/brutalist, image-to-code) | https://github.com/Leonxlnx/taste-skill | MIT |
| impeccable (design audit) | https://github.com/pbakaus/impeccable | Apache-2.0 |
| marketing suite (cro, copywriting, pricing, cold-email, …) | https://github.com/coreyhaines31/marketingskills | MIT |
| claude-seo (seo, seo-technical, seo-local, …) | https://github.com/AgriciDaniel/claude-seo | MIT |
| find-bugs, code-review, security-review, gha-security-review, … | https://github.com/getsentry/skills | Apache-2.0 |
| n8n-*-official | https://github.com/n8n-io/skills | Apache-2.0 |
| agent-browser | https://github.com/vercel-labs/agent-browser | Apache-2.0 |
| cloudflare, wrangler, workers-best-practices, … | https://github.com/cloudflare/skills | Apache-2.0 |
| resend, resend-cli, react-email | https://github.com/resend/resend-skills | MIT |
| supabase, supabase-postgres-best-practices | https://github.com/supabase/agent-skills | MIT |
| higgsfield-generate, higgsfield-soul-id, … | https://github.com/higgsfield-ai/skills | MIT |
| remotion-* | https://github.com/remotion-dev/skills | see repo |
| vercel-react-best-practices, web-design-guidelines, … | https://github.com/vercel-labs/agent-skills | see repo |
| frontend-design, skill-creator, mcp-builder | https://github.com/anthropics/skills | see repo (varies per skill) |
