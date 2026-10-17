# Skill router: pick the skill at the start of every task
Rule: match the use-case, invoke the skill, say which in one line. Two fit → the more specific wins.
Nothing fits → say so and proceed. Only list skills that are actually installed.
Third-party names below are suggestions (see SKILLS.md for sources); delete rows you don't have.
`skill-route-sync` appends every other installed skill in an auto section at the bottom and keeps it current;
move a row up here (by hand) once you use it often.

## Use-case → engine (optional, if you also run Codex)
| Job | Engine |
|---|---|
| Direction, taste, secrets, MCP steps, outbound sends, verification | Claude (lead) |
| Substantial build, numbered fix round, refactor, parallel lane | Claude writes the brief → `codex` |
| Lint, deps, renames, test sweeps, format conversion | `codex` on a cheap model |
| Money / auth / email / DNS / deploy diff | `codex review` as a second opinion, then Claude verifies |
| Verify a lane's output, read logs | a fresh subagent that didn't build it |
| GPU jobs (face edit, 4K upscale, voice conversion) | a GPU machine you own (`remote-gpu-render`) |

## Use-case → skill
| You are doing… | Skill(s) |
|---|---|
| Any build (process spine) | brainstorm → write plan → execute plan → verify before done |
| Managing tabs, briefs, reports (the lead) | `terminal-lead` |
| Working a brief in a project tab | `project-tab` |
| Hand a build/review to a Codex model | `codex` |
| **Before ANY paid generation** | `credit-discipline-for-generation` |
| Client commercial / ad / video deliverable end to end | `commercial-production-pipeline` |
| Recreate a reference video's motion graphics with your footage | `studio-vfx` |
| Kinetic typography / "text flying around" | `kinetic-type-physics` |
| Which Higgsfield model / MCP call pattern | `higgsfield-production-routing` |
| Green-screen talent into a generated location | `greenscreen-to-ai-plate-comp` |
| 3D set from storyboard panels (cameras, continuity, depth, tour) | `blender-set-from-storyboard` |
| Consenting voice delivering an actor's performance; phone/radio VO | `performance-voice-conversion` |
| Lip lag, side-eye/gaze, picking AI clip windows | `lip-sync-and-gaze-qc` |
| Rebuild a fan edit from clean sources (music sync, cadence, grade) | `edit-rebuild-from-clean-sources` |
| Wrong logo printed in an AI clip | `ai-video-logo-replace` |
| Beat accents (flash frames, double exposures, ghosts) | `beat-synced-overlays` |
| GPU passes on your own NVIDIA PC over SSH | `remote-gpu-render` |
| QC any video before a client sees it | `video-qc-reviewer` |
| Edit real footage by conversation | `video-use` (third-party) |
| New marketing site or "remake this website" | `website-build` (+ `design-motion-principles` for motion) |
| Need a UI element, icon, animation, 3D model, font, photo or sound | `find-component` (its `sources.md` lists where to look) |
| Pitch / sales deck | `deck` |
| Same-day prep for a booked sales meeting (site + deck + demo phone agent) | `sales-appointment-prep` |
| Which of your separate Claude accounts a tab or job runs on | `claude-accounts` |
| Give a collaborator a walled-off workspace on your server | `collab-sandbox` |
| Put a consenting person into footage you own | `person-into-existing-scene` |
| iOS / SwiftUI code (Apple's Xcode 27 guidance) | `swiftui-specialist`, `swiftui-whats-new-27`, `uikit-app-modernization` (third-party) |
| Before an App Store submission | `review-readiness-check`, then the matching review audit (third-party) |
| Reverse-engineer a shipped binary or package (no source) | `reverse-engineer-anything` (REA, third-party); not for normal source repos |
| Grade or improve a Vapi phone agent | `phone-qa` (+ Vapi's own prompt-builder skill) |
| Hard bug / perf regression | <your debugging skill> |
| Review a diff before merge | <your code-review skill> + `codex` review on money paths |
| Verify a web app in a browser | <your browser-testing skill> |
| Write or fix a skill | <your skill-authoring skill> |

## Per-project map (optional)
- **acme-app:** <skills you reach for on this project>
- **client-a (video):** `commercial-production-pipeline`, `credit-discipline-for-generation`, `video-qc-reviewer`
