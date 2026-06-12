# HANDOFF — 2026-06-12 (morning PDT)

A long multi-day session (June 9–12) that started as VPS maintenance and grew an
entire personal-web-presence arc: fixed Axiom's Claude install + lifecycle on
openclaw-prod, bought the identity domains, built and shipped davidv.sh
(Next.js on Vercel, two domains, symmetric routing), and replaced the PDF-runbook
workflow with a private `/ops` living-documentation section. One new solution doc
compounded into this repo. Board empty; no open PRs.

## What We Built

**VPS (openclaw-prod):**
- Axiom Claude Code: was pinned to stable channel (2.1.153) — set
  `autoUpdatesChannel: latest` in axiom's settings, updated to 2.1.170.
- Killed the "Multiple installations" false positive for good: axiom's npm
  prefix moved `~/.local` → `~/.npm-global` (`~/.npmrc`), three npm globals
  reinstalled at pinned versions, compat symlinks left in `~/.local/bin`
  (agent-browser, ast-grep, browse, sg — intentional, don't clean up).
- Settings sync: axiom's `~/.claude/settings.json` is now a **generated file**
  — repo base + `~/.claude/settings.overlay.jq`, rebuilt by
  `~/.local/bin/sync-dotfiles` (pull + regen). Sync command:
  `ssh root@openclaw-prod 'sudo -u axiom /home/axiom/.local/bin/sync-dotfiles'`.
- Axiom lifecycle consolidated: killed the 5-day orphan claude (manual
  `su - axiom` session from a Tailscale SSH window); the **AXIOM tmux pane**
  (axiom-tmux.service) is now the one home, running 2.1.170 with `--continue`.
- Docker: renamed `syncthing-d95veq7chb3d8gllyj6vhpqy` → `syncthing-hermes`
  (compose `container_name`), removed the disabled openclaw service block +
  orphan volume declaration from `/opt/openclaw/docker-compose.yml` (timestamped
  backups alongside; the `openclaw-state` Docker volume itself preserved).

**Domains (Vercel registrar, under team `david-villavicencios-projects`):**
- Bought `villavicencio.dev` ($9.99, renews $13) and `davidv.sh` ($22, renews
  **$60**) — both auto-renew ON, expire 2026-06-11+1yr. Found via the new
  `/v1/registrar` API (old `/v4` endpoints sunsetted Nov 2025).
- `dav.id` confirmed taken (PANDI whois: registered 2016, expires 2027).
  `villavi.dev` identified as available cheap sayable alias ($9.99/$13) — not bought.

**davidv.sh site (repo `~/Projects/davidv.sh`, private GitHub villavicencio/davidv.sh):**
- Next.js 16 + @next/mdx on Vercel, both domains attached, push-to-deploy via
  git integration. Symmetric routing: `davidv.sh/*` →307→ `villavicencio.dev/*`
  except `/x/*` (experiments) and `/ops/*`; `.dev/x|ops/*` →307→ `.sh`.
- **`/ops` private living docs**: middleware magic-link cookie gate
  (`OPS_SECRET`; unauthorized → bare 404; `robots: noindex`). Three pages:
  `/ops/axiom`, `/ops/atlas` (ported playbooks), `/ops/shipsigma-deliverability`
  (v3 — DNS audit scorecard, persistent checklists, capacity calculator, ramp
  chart, GFM tables).
- README decision log: 307→308 flip revisit ~2026-12-11 (calendar event set).

**Docs & knowledge:**
- New solution doc (4c50bf6): `docs/solutions/integration-issues/`
  `static-vercel-to-nextjs-mdx-conversion-traps.md` — NODE_ENV poisoning builds,
  Vercel framework preset null, remark-gfm/singleTilde. New category dir.
- PDFs on Desktop (axiom-ops-playbook, atlas-ops-playbook, domain-decision) —
  superseded for playbooks by the `/ops` pages.
- Memories added: axiom claude lifecycle, davidv.sh living-docs workflow,
  npm-prefix fix; axiom dotfiles-clone memory updated (sync-dotfiles).

## Decisions Made
- **Runbooks → `/ops` MDX pages, not PDFs** (saved as preference memory).
  Update = edit page.mdx + push; re-verify facts + bump `<Verified>` badge.
- **Settings sync via overlay-merge, not symlink** on axiom: Claude Code's
  runtime writes would dirty the clone and break `--ff-only`; machine deltas
  live in the overlay (channel, theme, vercel plugin, local marketplace path;
  deletes eagle MCP, skills-private, model pin).
- **307 (temporary) redirects deliberately** — browsers cache 301s and paths may
  flip from redirect to experiment; revisit Dec 11.
- **Magic-link cookie auth over Vercel Authentication** for `/ops` — path-scoped,
  free, no third party; fails closed (404).
- **`davidv.sh` over `vill.sh`** for the alias: the .sh exists to be spoken;
  "vill" re-imports the spelling problem.
- Volume figure in the deliverability playbook is **TBV** — user validating the
  real daily send number; calculator is the tool once known.

## What Didn't Work
- `vercel domains add` CLI (interactive prompts) — used the API
  (`POST /v10/projects/{id}/domains`) instead.
- Vercel encrypted env values can't be read back via API — when the clipboard
  got overwritten mid-flight, the fix was rotate + redeploy; secret now also in
  the repo's untracked `.env.local`.
- who.is gateway claimed "no WHOIS data" for dav.id — PANDI's own `whois.id`
  (slow but authoritative) showed it registered. Don't trust gateways for .id.
- First Next.js deploy served platform errors despite READY — framework preset
  was null (see solution doc).

## What's Next
1. **Validate Ship Sigma's real daily send volume** → plug into
   `/ops/shipsigma-deliverability` (calculator + prose); also run the
   learndmarc.com alignment test and the Phase-1 checklist there.
2. **Decide the `NODE_ENV=development` removal** from `zsh/zshenv:145` —
   flagged twice now (build crash + solution doc); behavior change → branch+PR.
3. **`M claude/settings.json`** (uncommitted): Claude Code wrote
   `"model": "claude-fable-5[1m]"` on June 9. Commit to record the pin (axiom's
   overlay already strips it) or discard. Left pending deliberately.
4. Optional: buy `villavi.dev` ($9.99/$13) as the cheap sayable alias.
5. Dec 11: calendar event fires — consider 307→308 flip (README decision log).

## Gotchas & Watch-outs
- **`OPS_SECRET` lives in Vercel env + `~/Projects/davidv.sh/.env.local`
  (untracked).** Losing both = rotate + redeploy. Magic URL must be visited
  once per browser/device; cookie lasts 1 year.
- **`davidv.sh` renews at $60/yr** (all Vercel .sh do — purchase $22 was
  year-one only). Auto-renew is ON; flip via `PATCH /v1/registrar/.../auto-renew`
  if the bit stops being worth it.
- **Axiom settings.json is generated** — edit `~/.claude/settings.overlay.jq`,
  never the file; bare `git pull` on the clone doesn't regen (use sync-dotfiles).
- **Don't launch claude ad-hoc on the VPS** (`su - axiom` → claude) — that's the
  orphan failure mode; everything via the AXIOM pane
  (`ssh -t root@openclaw-prod 'sudo -u axiom tmux attach -t AXIOM'`, prefix C-b).
- **Vercel project framework preset must stay `nextjs`** for davidv.sh — null
  preset = platform NOT_FOUND/MIDDLEWARE_INVOCATION_FAILED on READY deploys.
- **remark-gfm needs `singleTilde: false`** in any MDX with `~/paths` — and the
  string/tuple plugin form for Turbopack serializability.
- Next 16 deprecation: `middleware.ts` → "proxy" convention. Works with a
  warning; rename eventually.
- The deliverability playbook's DNS facts: SPF/DKIM verified by live audit;
  **Exclaimer alignment still unverified** (learndmarc test pending);
  shipsigma.com volume figure TBV.
