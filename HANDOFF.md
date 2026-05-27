# HANDOFF — 2026-05-27 (PDT)

Short, self-contained maintenance session. Picked up cold (browse-gateway arc parked — see note below), then chased one concrete bug: the Claude Code statusline on the Axiom (Linux) host rendered the git-branch Powerline glyph as the literal string `\xee\x82\xa0`. Diagnosed it to a non-POSIX `printf` escape, fixed it in both dotfiles and on the live Axiom host, and compounded the learning into `docs/solutions/`. Closed with a quick diagnostic: Axiom's "10:33pm" is the VPS clock running on UTC (see gotchas). Tree is clean, everything pushed; no code changes since `74695c7`.

## What We Built

- **`de51edc` — `fix(statusline): octal escape for branch glyph so dash renders it`.** Changed `claude/statusline-command.sh` line 36 from `printf "...\xee\x82\xa0..."` (hex escape for U+E0A0) to octal `\356\202\240`, plus rewrote the comment to explain the dash/POSIX gap. Verified the octal form emits bytes `ee 82 a0` identically in `/bin/sh`, `dash`, and `bash`.
- **Patched the live file on Axiom** via `! python3 -c '...'` (literal raw-string `.replace()`) — the dotfiles commit alone does NOT reach Axiom (it's not a dotfiles-managed target post-VPS-decommission). User confirmed the glyph now renders.
- **`71bb507` — `docs(solutions): printf \xHH not POSIX — use octal; refresh PUA sibling`.** Ran `/ce-compound` (Full mode). Created `docs/solutions/code-quality/printf-hex-escape-not-posix-use-octal.md` (bug track, `runtime_error`/`tooling`/`wrong_api`, frontmatter validated). Also refreshed the sibling `docs/solutions/code-quality/claude-code-bash-tool-strips-pua-glyphs.md` (Phase 2.5): its on-disk-output guidance recommended `printf '\xHH'` without the dash caveat and missed octal — added the octal pointer + cross-reference, bumped `updated:`.
- **tmux:** renamed window `local:1` from "Hermes" → "Agents" (kept glyph U+F4BC + ember `#D97757`), persisted to the sidecar.

## Decisions Made

- **Filed the new learning in `code-quality/`, not `runtime-errors/`** (where the schema's `runtime_error`→`runtime-errors/` mapping pointed). Rationale: the two closest sibling docs (PUA-glyph stripping, tmux-format-hex mangling) already cluster in `code-quality/`; co-locating the escape/glyph/portability gotcha family beats schema purity for discoverability. `runtime-errors/` holds one unrelated doc.
- **Made the Phase 2.5 sibling-doc refresh surgically by hand** instead of spinning up the full `ce-compound-refresh` skill — it was a verified 4-line correctness fix already in hand; a whole skill invocation was disproportionate.
- **Skipped Phase 3** (specialized reviews) — the doc's snippets are all verified one-liners and already minimal.
- **Root cause is `wrong_api`** (non-portable `printf` escape), severity `low` (cosmetic glyph; branch name always showed).

## What Didn't Work

- **First Axiom patch attempt (`grep -q`/`sed` find-and-replace) silently no-oped** — printed `NO_HEX_ESCAPE` while the escape was plainly still in the file. Two compounding causes: (1) bash double-quotes collapsed `\\x`→`\x`; (2) **GNU `grep`/`sed` interpret `\xHH` in a pattern as the byte `0xEE` itself**, so it searched for the rendered glyph bytes (absent from the file) and matched nothing. Fix: literal Python `.replace()` with single-quoted raw strings — no regex engine. (This became its own section in the new doc.)
- **The Edit tool serialized a typed em-dash into a literal `—`** in the sibling doc — the inverse of the escape-mangling the doc is about. Caught on byte-inspection (`xxd`); fixed via a `chr(92)`-built Python literal replace (avoids typing either the em-dash or `—`, both of which the harness transforms on input). Worth remembering: **build literal escape-text search strings from `chr(92)`, never type the backslash sequence directly into a tool arg.**

## What's Next

- **Nothing pending in dotfiles.** This arc is closed — both commits pushed, tree clean, no open PRs.
- **Parked (not this repo's work):** the **browse-gateway** arc. Implementation lives in `~/Projects/browse-gateway` (public repo); its context is in that repo's gitignored `CONTEXT.local.md`, and dotfiles only retains custody of the private planning docs (`docs/brainstorms/2026-05-27-self-hosted-browser-gateway-requirements.md`, `docs/plans/2026-05-27-001-feat-browse-gateway-plan.md`). To resume it: `cd ~/Projects/browse-gateway && claude` → read `CONTEXT.local.md` → start U1 (the stealth kill-gate). The prior HANDOFF (overwritten by this one) covered that arc in full; git history has it at commit `61095bc`.

## Gotchas & Watch-outs

- **`printf \xHH` and `\uXXXX` are bash/coreutils-only.** For any non-ASCII byte in a `#!/bin/sh` or `sh`-invoked script, use octal `\ooo`. Portability check before committing byte escapes: `for s in dash bash sh; do $s -c 'printf "\356\202\240"' | xxd; done` — all must emit `ee82a0`.
- **dotfiles ≠ Axiom delivery.** Fixing a `claude/` file in dotfiles does not propagate to Axiom (no active Linux dotfiles target since the 2026-05-21 VPS decommission). Any `~/.claude/*` fix that must reach Axiom has to be applied to the live host separately — user ran it via the `!` prefix this session.
- **Editing literal escape text on Linux: never use `grep`/`sed`** — their `\x` is a byte escape and misfires on the exact strings being edited. Use a literal-string replace (Python raw string, or `perl -pe` with `quotemeta`) and make it self-verifying (`PATCHED`/`NOT_FOUND`).
- The statusline comment on Axiom's live file still references the old hex form (only the functional `printf` line was patched) — harmless drift; resync the whole file from the repo if it ever matters.
- **The VPS clock is UTC (Axiom reports UTC time, 7h ahead of PDT).** Verified 2026-05-27: Axiom's "10:33pm" = 22:33 UTC = 3:33pm PDT. So any "today/tonight/this morning" framing from Axiom is UTC-relative, and after ~5pm PDT its calendar date rolls a day ahead of the user's. Left on UTC by choice (unambiguous server logs); to align it, run `sudo timedatectl set-timezone America/Los_Angeles` on the host. Not changed this session.
