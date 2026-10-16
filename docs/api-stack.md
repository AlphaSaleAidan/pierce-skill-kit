# API stack (example)

A typical set of services behind a lead + tabs setup, what each is for, and how to store the keys. You won't
need most of them; start with the core table. **No key value ever goes in a repo, chat, screenshot or recording.** Costs are rough (Oct 2026); check each pricing page before you sign up.
Env var names are the usual ones each tool's SDK/CLI reads. Keep them consistent so scripts work everywhere.

How to plug these into Claude safely (MCP vs CLI, keys by path, capped headless runs): [toolbelt.md](toolbelt.md).

## Core
| Service | What it's for here | Rough cost | Get the key | Env var |
|---|---|---|---|---|
| Anthropic / Claude Code | The lead + every tab | Max subscription ($100–200/mo per account); API pay-per-use if scripted | claude.ai login / console.anthropic.com | `ANTHROPIC_API_KEY` (only for API scripts) |
| OpenRouter | Cheap one-off model calls from scripts, many models behind one key | Pay-per-use, top up $10+ | openrouter.ai/keys | `OPENROUTER_API_KEY` |
| GitHub (`gh`) | Repos, PRs, Actions | Free / $4 mo | `gh auth login` (no file needed) | `GH_TOKEN` (CI only) |
| Vercel | Preview + prod hosting for sites | Free hobby; Pro $20/mo | vercel.com/account/tokens | `VERCEL_TOKEN` |
| Cloudflare | DNS, tunnels for preview links | Free for most of it | dash.cloudflare.com → API Tokens (scoped) | `CLOUDFLARE_API_TOKEN` |
| Supabase | Database + auth for apps | Free tier; Pro $25/mo per project | project → Settings → API | `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` |
| Resend | Sending app email (verified domain) | Free 3k/mo; $20/mo after | resend.com/api-keys | `RESEND_API_KEY` |

## Extra models (optional)
| Service | What it's for | Rough cost | Env var |
|---|---|---|---|
| Google Gemini | Long-context reads, vision, cheap bulk | Free tier + pay-per-use | `GEMINI_API_KEY` |
| DeepSeek / Kimi (Moonshot) / xAI | Cheap alternates for bulk text jobs | Pay-per-use, low | `DEEPSEEK_API_KEY`, `MOONSHOT_API_KEY`, `XAI_API_KEY` |
| OpenAI | Only if a tool needs it | Pay-per-use | `OPENAI_API_KEY` |
| Replicate | Run open models without a GPU | Pay-per-second | `REPLICATE_API_TOKEN` |

## Voice + phone agents
| Service | What it's for | Rough cost | Env var |
|---|---|---|---|
| Vapi | Phone/voice agents | ~$0.05/min + model/voice costs | `VAPI_API_KEY` |
| Telnyx | Phone numbers + SMS (US texting needs 10DLC registration) | Numbers ~$1/mo + usage | `TELNYX_API_KEY` |
| Deepgram | Speech-to-text | $200 free credit, then per-minute | `DEEPGRAM_API_KEY` |
| Fish Audio / Cartesia | Text-to-speech voices | Pay-per-use / plans from ~$5/mo | `FISH_AUDIO_API_KEY`, `CARTESIA_API_KEY` |

## Images, video, design
| Service | What it's for | Rough cost | Env var |
|---|---|---|---|
| fal | Image/video generation via API | Pay-per-generation | `FAL_KEY` |
| Higgsfield | Image/video generation via MCP (logs in, no file) | Credit packs | n/a |

## Money, shipping, signatures
| Service | What it's for | Rough cost | Env var |
|---|---|---|---|
| Stripe | Payments. **Test mode first; live keys only with the human's OK** | 2.9% + 30¢ | `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET` |
| Shippo | Shipping labels | Pay-per-label | `SHIPPO_API_KEY` |
| DocuSign / OpenSign | Contracts + e-signatures (OpenSign = free/open-source) | DocuSign plans ~$10+/mo | `DOCUSIGN_*`, `OPENSIGN_API_KEY` |

## Google, files, backups
| Service | What it's for | Rough cost | Env var / file |
|---|---|---|---|
| Google Cloud OAuth | Gmail drafts, Drive, Search Console, GA4 | Free | OAuth client JSON file + refresh token file |
| rclone | Copy files to Drive/Dropbox/S3 | Free | `~/.config/rclone/rclone.conf` (keep chmod 600) |
| Dropbox | Big file handoffs | Free / plans | `DROPBOX_ACCESS_TOKEN` |
| restic | Encrypted off-box backups | Free + storage cost | `RESTIC_PASSWORD_FILE`, `RESTIC_REPOSITORY` |
| Zoho Mail | Business mailboxes on your own domain | Free / ~$1/user/mo | app password file |

## Bots + app stores (when a project needs them)
Discord / Telegram bots (`DISCORD_BOT_TOKEN`, `TELEGRAM_BOT_TOKEN`) · Instagram Graph API · App Store Connect API
(`.p8` key file + key id + issuer id).

## How to store keys
1. One folder: `mkdir -p ~/.secrets && chmod 700 ~/.secrets`.
2. One file per service, e.g. `~/.secrets/openrouter` holding `OPENROUTER_API_KEY=…`, then `chmod 600`.
3. `~/.secrets/README.md` = an index: file name, service, what uses it, date added. **Never values.**
4. Scripts load by path (`set -a; . ~/.secrets/openrouter; set +a`). Point Claude at the *path*, never paste the value.
5. Never put a value in chats, commits, memory, CLAUDE.md, screenshots or recordings. Add `.env*` to `.gitignore`.
6. A key that was ever pasted anywhere gets rotated. No exceptions.
7. Money APIs: test mode first. Every metered loop gets a spend cap, and a dollar quote is approved before the run.
8. Scope keys down (read-only, one project) wherever the service allows.
9. Masking must also catch unquoted values (`KEY=abc`), not just quoted ones.

See also the Secrets and Money rows in [RULES.md](../RULES.md).
