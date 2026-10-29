# Claude Code config: settings, hooks, permissions, tmux indicators

Moved out of the always-loaded `CLAUDE.md` on 2026-10-22 (VIL-402), word for word except
for heading levels. `CLAUDE.md` keeps the one-line rules and points here.

## tmux-window-namer skill (external plugin + repo-side tmux infra)
The **tmux-window-namer skill itself now lives in an external Claude Code plugin**
(the `dv` plugin), not this repo. What this repo keeps is the **tmux-side
infrastructure** the skill drives: the skill stores per-window state in two tmux
user options (`@win_glyph`, `@win_glyph_color`) read by the ternary in
`tmux/tmux.display.conf`'s `window-status-format`. Title text always uses default
tmux colors so inactive tabs naturally dim — only the glyph carries palette color.
Persistence is a JSON sidecar at `~/.config/tmux/window-meta.json`, written by
`tmux/scripts/save-window-meta.sh` and re-applied on every client attach via
`tmux/scripts/restore-window-meta.sh` (wired up in `tmux/tmux.general.conf`
with `set-hook -g client-attached`). The curated palette the skill draws from is
part of the plugin, not this repo.

## Statusline meters (`claude/statusline-command.sh`)
- **Colors are protan-safe.** The meters ramp blue → gray → yellow. David's red cones are at 0%, and
  red/green meters fail that: under a protanopia simulation (Machado 2009) the old lime reads as
  bright yellow and the old salmon red as a dull gray-olive, so the meter got *dimmer* as it
  filled. Blue–yellow is the axis protans keep, and luminance rises along the ramp, so "fuller"
  also reads as "brighter".
- **Context meter.** A bar over the model's whole window (`context_window_size`, 1M when absent),
  labeled in tokens. Its color doesn't follow the bar: it ramps to yellow on the way to
  `CTX_HANDOFF`, the 200k hand-off cue (VIL-402: every turn re-reads the whole context, so a
  session should end there), and past it the fill turns solid. Ahead of the fill a dim ╎ marks the
  hand-off cue and a white ┃ marks `autoCompactWindow`, read live from `settings.json`, so moving
  it moves the marker; no setting, no marker. A shaded runway between the two read as context
  already used, so the track stays plain.
- **Slider width (VIL-82).** 20 cells, 5 points each. Three meters render ~105 columns, which fits a
  full-width pane but wraps in a split one, so 20 is the ceiling. Halving the step from 10 separated
  most pairs that used to share a cell (1%/4%, 5%/9%, 17%/22%), but nearest-cell rounding still
  merges values inside one band, and a pair straddling the new boundaries can regress (3% and 7%
  split at 10 cells and collide at 20): a net gain, not a guarantee for any one pair.

## A hook symlinked into the repo is branch-fragile — land the file before wiring it
No hook is tracked today (the last, `tmux-attention.sh`, was retired 2026-10-28). A new one goes
in `claude/hooks/`, gets a Dotbot `link:` in `dotbot-conf/darwin.yaml` plus a `create:` for
`~/.claude/hooks`, and its `settings.json` entries.

A hook linked that way points **into this working tree**, so it resolves against
whatever branch is checked out. A hook whose file exists only on a *feature* branch goes
dangling the moment you switch away, and Claude Code then prints a non-blocking error on
**every** `SessionStart` and `UserPromptSubmit`, in every session, across every project:

```text
SessionStart:startup hook error
Failed with non-blocking status code: /bin/sh: ~/.claude/hooks/<hook>.sh: No such file or directory
```

Observed 2026-08-25 with a hook registered in `settings.json` and symlinked while on its feature
branch, then broken by a routine `git checkout` of an unrelated branch.

**So: do not register a hook in `settings.json` until its file is on `master`.** If you need it
live before the PR merges, install a *copy* rather than a symlink — a copy is branch-independent:

```bash
tmp="$(mktemp)"
mkdir -p ~/.claude/hooks &&
git show <branch>:claude/hooks/<hook>.sh > "$tmp" && chmod +x "$tmp" &&
  mv -f "$tmp" ~/.claude/hooks/<hook>.sh
```

Write to a temp file and `mv` over the destination — **do not redirect straight at the hook
path.** When that path is still the dangling symlink, `>` follows the link and creates its
*target*: verified 2026-08-25, the redirect **succeeds silently**, the symlink stays a
symlink, and the content lands at the target path inside the repo working tree. So the hook
still does not exist where Claude Code looks for it, and you have also dropped an untracked
file into the repo. `mv -f` replaces the link itself, atomically.

Re-run `./install` after the merge to restore the tracked symlink, which is safe once the file
is on the default branch and therefore present on every branch cut from it.

## Claude Code `settings.json` — copy-seeded, never symlinked
`claude/settings.json` is the **only** tracked config delivered by copy rather than a
Dotbot `link:` (its Windows sibling `windows/claude-settings.json` is copy-seeded the same
way by `install.ps1` — see `docs/reference/windows.md`). The Otty config was the other one until Otty was uninstalled and its
tracking removed (2026-09-03); the reasoning below is the same one that governed it, and
the mechanism is written up in
`docs/solutions/integration-issues/otty-config-symlink-hostile-atomic-rename-2026-08-07.md`
— still worth reading, because the trap is about `rename(2)` and not about Otty.
`helpers/install_claude_settings.sh` seeds
`~/.claude/settings.json` **only when absent**, so a live config is never clobbered.

**Do not "fix" this by restoring a `link:` entry.** The file has independent writers
besides this repo — Claude Code itself (`effortLevel`, `tui`, notification prefs, `autoMode`)
and agent-integration installers (Orca's agent hooks today; herdr's until 2026-10-22, Otty's
until 2026-09-03) — each rewriting it in place. A symlink there survives until the first write, after which the live file is a regular
file and the repo copy is a silently-orphaned stale twin.

That already happened. The link was replaced at some point before 2026-08-25 and the repo copy
went stale from **2026-08-07** — its last commit — while the live file drifted for eighteen days.
Nothing surfaced it: `git status` stayed clean, because from git's side nothing had changed.

**The damage was not cosmetic.** In that window the live file regrew a legacy top-level
`allowedTools` key holding 18 rules while `permissions.allow` fell to 1 — silently re-arming the
precedence trap PR #127 removed (see "one allowlist, not two" below). It also accumulated an
`autoMode.environment` block naming a *different project's* trusted repo and services, in the
cross-machine user-scope file whose own `"//"` header forbids machine- or project-specific values.

Because a copy can drift, `dot drift` reports Claude settings alongside Brewfile and npm, and
**warns loudly if `allowedTools` ever reappears**. It compares **capture-normalized** forms —
the live file legitimately carries machine-local keys that are deliberately untracked, so a raw
diff would report permanent un-actionable drift. To record live changes:

Desk Macs (Linux and hal's server profile get no seeded settings: there the migration only
folds `allowedTools` and removes retired hooks, and `dot drift` doesn't compare them):

```bash
dot drift                                            # see what diverged
# A hook or plugin you changed live on purpose: make the same change in claude/settings.json first.
python3 helpers/migrate_claude_settings.py           # then this, by hand, every time: adds tracked
                                                     # keys, hooks and plugins the live file lacks,
                                                     # removes retired hooks (capture refuses while any remain)
bash helpers/install_claude_settings.sh --capture    # regenerate claude/settings.json, then commit
```

Windows, in Git Bash (no `dot` there; `python3` is usually the Store placeholder, and a PC set
up only by `install.ps1` has uv but no Python, so the migration runs through uv):

```bash
bash helpers/report_drift.sh                                    # see what diverged
# A hook or plugin you changed live on purpose: make the same change in windows/claude-settings.json first.
python helpers/migrate_claude_settings.py                       # then this, by hand, every time,
                                                                # if Python works
uv run --no-project python helpers/migrate_claude_settings.py   # instead, on a PC with no Python
bash helpers/install_claude_settings.sh --capture               # regenerates windows/claude-settings.json, then commit
```

On either, that first step matters. The migration adds back a tracked top-level key, hook
(matched on event and exact command) or plugin the live file lacks. So while the tracked file
still has the old entry, it puts that entry back, and an edited hook would then run twice. Once the tracked file matches your change, the migration has
nothing of it to restore. It also removes retired hooks (`RETIRED_HOOKS`); `--capture` refuses while any remain, so it never writes one back.

`--capture` regenerates rather than `cp`s: it drops the machine-local keys
(`effortLevel`, `modelSettings`, `autoMode`, `mcpServers`, and `allowedTools` — which must never be tracked),
re-prepends the tracked `"//"` header, and rewrites absolute `$HOME` paths back to `~/`
(installers write literal `/Users/<you>/...`; Claude Code expands `~` in hook commands).
It refuses when the live file lacks a key the tracked file has (since 2026-10-22). That gap
means a tracked change never reached this machine, so run `helpers/migrate_claude_settings.py`
first. Only a key you removed on purpose gets deleted from the tracked file by hand.

**Hooks an installer writes stay untracked (VIL-431, 2026-10-23).** Orca's agent hooks
(commands under `~/.orca/agent-hooks/`) and iTerm2's status hook (`~/.config/iterm2/cc-status`)
are written into the live file by their own installers, which write them back on reinstall.
Tracking them would only seed them onto machines without that app. So `--capture` leaves out
any hook whose command contains one of those paths, drops a hook group or event left empty, and
`dot drift` compares the same way. The list is `INSTALLER_HOOKS` in
`helpers/lib/claude-settings-keys.sh`, which both scripts source. A new app whose installer adds
hooks gets its path added there.

Capture also refuses when the live file lacks a tracked hook (same event and command) or a
plugin the tracked `enabledPlugins` lists, just as it does for a missing top-level key: it
would otherwise drop them from the tracked file. For an entry this machine never got,
`helpers/migrate_claude_settings.py` adds the missing ones back, beside any installer hooks,
then re-capture. For a hook you edited or removed live on purpose, make the same change in
`claude/settings.json` by hand and re-capture. Don't run the migration for that: hooks match
on their exact command, so it would add the old one back beside the edit and both would run. A plugin turned off live is
stored as `false`, so it counts as present and stays off. A tracked object whose live value
is `null` or a list counts as missing, and the migration replaces it with the tracked value
(the backup keeps the old file). An entry you removed on purpose is
deleted from the tracked file by hand. Windows tracks no hooks, so only plugins apply there.

**Agents cannot write this file** — the auto-mode classifier blocks it by design, so it stops an
agent widening its own permissions. `helpers/migrate_claude_settings.py` exists for a machine
whose settings predate this scheme (folds `allowedTools` back into `permissions.allow`);
it is idempotent, backs up first, and **you run it yourself**, not an agent. On Windows,
under Git Bash, you run it as `python`, since `python3` there is the Microsoft Store
placeholder (or `uv run --no-project python helpers/migrate_claude_settings.py` on a PC with no
Python of its own).

## Claude Code permissions: one allowlist, not two

**`permissions.allow` is the allowlist. There is no `allowedTools` key** — do not
reintroduce one (discovered 2026-08-07).

`allowedTools` is a legacy top-level key. When both exist, **the legacy key wins
and `permissions.allow` is silently inert.** Nothing warns you: rules in
`permissions.allow` simply never take effect, and the failure looks like "the
rule doesn't work" rather than "the rule isn't being read."

This cost a real debugging session. `Bash(gh pr merge:*)` sat in
`permissions.allow` (added by PR #121) while every merge still prompted, because
the live `allowedTools` list — which had 17 read-only-ish rules and no merge
entry — was the one actually consulted. Adding the same rule to `allowedTools`
fixed it instantly, which is what proved the precedence.

Both lists are now consolidated into `permissions.allow` in
`claude/settings.json`. If a permission rule ever appears to be ignored, check
for a resurrected `allowedTools` **before** assuming the auto-mode classifier is
gating the command.

**This regressed once already, and will again.** On 2026-08-25 the live
`~/.claude/settings.json` was found with `allowedTools` back at 18 rules and
`permissions.allow` down to 1 — #127 silently undone, because the repo copy had
been orphaned from its symlink and nobody was comparing (see "copy-seeded, never
symlinked" above). The consolidation lives in a file three other installers
rewrite, so treat it as a **recurring** hazard, not a closed one: `dot drift` now
warns whenever the legacy key reappears, and
`helpers/migrate_claude_settings.py` folds it back.

Related but distinct: the auto-mode classifier **does** independently block
agent edits to `~/.claude/settings.json` itself, regardless of allow rules. That
is intended — it stops an agent widening its own permissions — and is not the
same mechanism. Permission-file edits are a human job. The classifier also blocks secret-store
writes such as `gh secret delete` ("Secret-Store Writes", seen 2026-10-12 on VIL-284), so hand
the exact command to David to run with `!` instead of retrying. It also blocks moving a secret
from a local file to anywhere David can read it remotely: printing it into the chat ("Credential
Materialization") or writing it into an Apple Note ("Credential Leakage"), both seen 2026-10-12
with davidv.sh's `OPS_SECRET`. Opening the magic link on the Mac (`open -a Safari …`) and
`pbcopy` were allowed. Away from the Mac, David reads the value from the Vercel dashboard himself.
It also blocks writing an unattended agent's instructions ("Create Unsafe Agents", seen
2026-10-18 on `plan-prompt.md`, VIL-396, when the pilot runner still lived in this repo's
`pilot/`; it is now the private `villavicencio/hal-pilot` repo, VIL-515). David unblocked it
with an `Edit(pilot/**)` rule in this repo's `.claude/settings.local.json`. A new home for
agent code needs its own human-added rule matching its own paths: in `hal-pilot` the file is at
the repo root, so the rule there is `Edit(plan-prompt.md)` in `hal-pilot/.claude/settings.local.json`.

**Allow rules don't override the classifier's trust boundary; `autoMode.environment` sets it.**
On 2026-10-27 (VIL-515) `gh repo create villavicencio/hal-pilot --private --push` was blocked as
"Public Data-Sharing Upload" although `Bash(gh repo:*)` was allowed. The live
`autoMode.environment` (user scope, untracked) still had browse-gateway's lines, including
`**Source control**: villavicencio/browse-gateway … only`, so every other repo under the account
counted as outside the boundary. David widened that one line to the whole `villavicencio` GitHub
account (any repo there, public or private, is his) and the same command went through. When the
classifier blocks an action on David's own repos, read that block before adding allow rules. Its
other lines (trusted repo, sensitive files, prod hosts) are still browse-gateway's.

**Resolving a review thread is an "External System Writes" soft block** even on a PR the agent
is working on: that rule's PR-work exception covers only posting a comment and editing the
title or body. On 2026-10-27 David added an `autoMode.allow` entry (after `"$defaults"`, so the
built-in exceptions stay) that clears `resolveReviewThread` on a `villavicencio` PR the user
asked the agent to work on or the agent opened, once the agent has pushed the fix in that
session. `autoMode` is read only from user, managed and `--settings` scope, never from a
repo's `.claude/settings*.json`; its entries are prose, not tool patterns. Check the effective
lists with `claude auto-mode config`, and read a built-in rule with
`claude auto-mode defaults --label '<rule name>'`.

**`Write(path)` rules are inert — file-permission checks match `Edit(path)` only**, and an
`Edit(…)` rule covers every file-editing tool (Write, Edit, NotebookEdit). Claude Code warns at
startup: `Permission deny rule … Write(<glob>) is not matched by file permission checks — only
Edit(path) rules are.` Seen 2026-08-27 in borealis's `.claude/settings.local.json`, which carried
both `Edit(//…/Containers/com.dvillavicencio.borealis/**)` and a `Write(…)` twin; the `Write`
entry was dropped. A deny written only as `Write(…)` protects nothing.

**A `*` belongs after the subcommand, never mid-command.** In a `Bash(...)` allow
rule the wildcard matches *anything* at that position — including flags and extra
arguments you never intended to pre-approve — and it approves them with no prompt.
`Bash(mv ~/path/_parked/* ~/path/)` reads like "move the parked versions back," but
the `*` also matches inserted options and additional operands, so the rule blesses a
whole family of `mv` invocations rather than the one it was written for. Write the
exact operands (`Bash(mv ~/path/_parked/2.1.112 ~/path/_parked/2.1.113 ~/path/)`),
or use the trailing prefix form `Bash(cmd:*)` after the subcommand. Corrected in
`.claude/settings.local.json` 2026-08-26 after David flagged it.

The same shape hides in the `Bash(cmd *)` space-star form, which is **not** the
`:*` prefix-match idiom and is broad in exactly this way. Prune on sight; these
files are gitignored, so nothing but a manual pass keeps them honest.

**Which file, measured 2026-08-27** — an earlier version of this paragraph attributed
another project's rules to this repo's file, so state the counts rather than the
impression:

| File | Rules | Space-star | ssh grant |
|---|---|---|---|
| `dotfiles/.claude/settings.local.json` | 91 | **0** | scoped: `Bash(ssh root@openclaw-prod:*)` and three narrower |
| `~/Projects/agents/.claude/settings.local.json` | 221 | 6 | **`Bash(ssh:*)`** — any host, any command |

This repo's file is clean of the space-star shape and its ssh grants name the VPS
explicitly. The unscoped `Bash(ssh:*)` is Argus's, and is the broadest grant in
either file — worth knowing before repeating "we have ~35 of these," which was true
of neither file when checked.

**Check for a subsuming prefix rule before rewriting a flagged one.** A finding of
the mid-command-`*` shape is worth acting on, but rewriting the operands is often
the wrong repair: if a broad `Bash(cmd:*)` for the same command sits elsewhere in
the list, the narrow rule grants nothing the broad one has not already granted, and
tightening it narrows the real surface by zero. **Delete the subsumed rule instead**,
and make the decision about the broad one — that is where the actual grant lives.
Observed 2026-08-27 on `~/Projects/agents/.claude/settings.local.json`: a flagged
`Bash(ls <path>/discord_*.md <path>/…)` rule sat four entries above a plain
`Bash(ls:*)`, and its target directory
(`~/.claude/projects/-Users-dvillavicencio-Projects-openclaw/memory`) no longer
existed — dead *and* redundant, across three narrow `ls` rules in a 224-rule file.
The generalisation: these files accrete rules at prompt-approval time and never
garbage-collect, so audit by command (group every rule for one binary and look for
the broadest) rather than one flagged line at a time.
