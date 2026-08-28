---
title: "A displayed command must be runnable verbatim — the clipboard is a convenience, not the delivery channel"
date: 2026-08-25
category: best-practices
module: agent-command-delivery
problem_type: convention
component: tooling
severity: High
applies_when:
  - "Displaying a shell command for the user to run, when the same command was also staged with `pbcopy`"
  - "A path, one-liner, or quoted payload is long enough that eliding it with `...` looks like a readability win"
  - "The user dictates with speech-to-text, or runs any tool that writes to the pasteboard, so the clipboard is clobbered between copy and paste"
  - "Handing over a remote command with nested quoting, e.g. `ssh host` wrapping a quoted `cp && sed -i && bash -n` chain"
  - "The command mutates state, so a partially-executed prefix leaves a half-applied result"
  - "A displayed command uses a bare tool name that `zsh/alias.sh` aliases to a different binary — `ls` is `eza`"
symptoms:
  - "`python3: can't open file '...': [Errno 2] No such file or directory` — the literal ellipsis from the displayed text was pasted and run"
  - "`sed: -e expression #1, char 1: unknown command: '.'` — an elided remote one-liner ran with the ellipsis inside the quoted payload"
  - "The user reports the command failed even though what the agent put on the clipboard was correct"
  - "A multi-step `&&` chain ran only its first stage: the `cp -n` backup exists but the edit never applied"
  - "The user says \"I lost my clipboard\" or asks for a payload to be re-copied"
  - "`error: invalid value '<filename>' for '--time <FIELD>'` — `ls -t` hit the eza alias instead of ls"
  - "A listing written with `2>/dev/null` prints nothing and is misread as an empty directory"
root_cause: design_limitation
resolution_type: workflow_improvement
related_components:
  - development_workflow
  - verification
tags:
  - claude-code
  - clipboard
  - pbcopy
  - agent-output
  - shell-pitfalls
  - aliases
  - eza
  - quoting
  - ssh
  - macos
related_solutions:
  - "docs/solutions/code-quality/claude-code-bash-tool-strips-pua-glyphs.md — adjacent family: what the agent emits is not what arrives, silently and with no error"
  - "docs/solutions/runtime-errors/dot-doctor-heredoc-pipe-deadlock-2026-08-07.md — same remedy shape: put the payload in a real file and invoke it by path instead of inlining it into a fragile one-liner"
  - "docs/solutions/cross-machine/ssh-as-root-write-ownership-and-exit-propagation.md — same `ssh host '...'` one-liner shape, a different trap inside it"
  - "docs/solutions/best-practices/pr-check-pass-state-is-not-a-review-verdict.md — sibling in genre only: there the agent misreads an upstream signal, here it emits a defective artifact. Different cause, different fix"
---

# A displayed command is the contract — the clipboard is only a convenience channel

## Context

On 2026-08-25 an agent handed David two commands to run in his own terminal — work it could
not do itself (running a staged Python fixer that the permission classifier blocked, and
patching a root-owned launcher on `openclaw-prod`). It did the right thing by the standing
preference: it piped the full command to `pbcopy`. It also **displayed** each command
abbreviated with `...`, on the theory that a hundred-character scratchpad path is noise.

Both failed. Both failed because he pasted the *displayed* form, not the clipboard form.

**The mechanism is his dictation software.** David dictates with Monologue (Every.to), and
it **replaces clipboard contents**. So between the agent's `pbcopy` and his paste there is a
window in which his own dictation clobbers the clipboard — and that window is every
conversational turn. He has clipboard-history software and *could* paste from history, but
out of habit he copies what is on screen.

The two failures, verbatim:

1. Displayed `python3 /private/tmp/claude-505/.../scratchpad/fix-claude-settings.py`
   → `can't open file '...': [Errno 2] No such file or directory`
2. Displayed `ssh root@openclaw-prod 'cp -n … && sed -i ... && bash -n ...'`
   → `sed: -e expression #1, char 1: unknown command: '.'`

**The second one partially executed.** The `cp -n` clause ran and created the backup before
`sed` choked on the literal `...`. That was fail-safe *by accident of statement ordering*,
not by design: the cheap, reversible clause happened to come first. Reverse the two and the
same paste mutates the launcher with no backup, then reports a `cp` error.

### This is the third clipboard loss, and the first two were never written down

Prior sessions in this repo record the same clobber twice, both handled ad-hoc *(session
history)*:

- **2026-08-19** — *"I lost my clipboard."* The agent re-copied and correctly guessed the
  class of cause: *"it's probably a clipboard manager or Raycast doing its thing."* No rule
  was written.
- **2026-08-24** — *"Can you please put it back in my clipboard?"* Second independent loss,
  five days later, different session. Also handled ad-hoc.

The machine is unusually clipboard-crowded: a 2026-08-19 session inventoried **Maccy,
Supaste, Paste, and Raycast Clipboard History** all installed at once (Maccy is tracked at
`brew/Brewfile:157`). Monologue is simply the newest writer to a pasteboard that already had
several. **Treat the clipboard as a shared, volatile channel with other writers — not as
private storage.**

Per this repo's own end-of-turn sweep convention, a rule discovered mid-session lands in
`AGENTS.md`/`CLAUDE.md` or `docs/solutions/` *in the same turn*. Both prior losses were
narrated in chat and landed nowhere — which is why the third one had no rule to prevent it.

### What changed this time

Nothing in the prior sessions shows this specific failure *(session history)*. Every earlier
handoff printed the payload in full, or was a short invocation pointing at a staged file — so
the displayed text and the clipboard text agreed. **This is the first time the two channels
diverged**, which is precisely why a routine clipboard clobber turned into a
partially-executed command instead of a harmless "please re-copy" request.

### What the repo already said

Nothing. Greps for `clipboard`, `pbcopy`, `verbatim`, and `paste` across `AGENTS.md`,
`CLAUDE.md`, and `claude/CLAUDE.md` return no hits. The standing rule lived only in agent
memory — *"pipe the entire final output to `pbcopy` … Don't just show it inline"* — and
**this learning refines that preference rather than contradicting it.** David explicitly
wants `pbcopy` to continue; he called it "extremely convenient." Keep piping. The correction
is additive: *and* make the displayed form correct.

## Guidance

**Core rule: never display a command you would not want executed exactly as shown.** The
displayed text is the contract, because it is the copy the user can always see and the only
one you control.

### 1. No elision inside an executable block

No `...`, no shortened paths, no truncated flags, no `<placeholder>` in anything presented as
ready-to-run. If a path is 110 characters of session hash, print all 110. Length is not a
reason to shorten the *text* — it is a reason to shorten the *command* (rule 3). Ugly and
correct beats tidy and broken; the reader is not reading the path, they are selecting it.

### 2. Prefer a shape where the two channels cannot diverge

The strongest fix is structural, and this repo already has a proven instance of it. From the
2026-08-07 Touch ID setup — the one step the agent could not run itself *(session history)*:

```bash
cat <<'PASTE' | tee /dev/stderr | pbcopy
<the exact command text>
PASTE
```

`tee /dev/stderr` writes the **same bytes** to the terminal and to the clipboard in one
command, so divergence is impossible by construction rather than by discipline. That handoff
worked first try. The incident under review is exactly what happens when that property is
lost.

Keep using `pbcopy` — it is convenient and wanted. Just never let it be the *only* channel.

### 3. Long or nested-quoting command → stage a script, hand over a short invocation

When a command is long enough to tempt elision, or has quoting nested more than one level
(`ssh host 'sed -i "s|a|b|" file'`), stop composing a one-liner:

```bash
scp /tmp/patch-thing.sh root@host:/tmp/patch-thing.sh
ssh root@host 'bash /tmp/patch-thing.sh'
```

Strictly better on every axis: short enough to retype when the clipboard is gone, no quoting
for a second shell to re-parse, and the script can defend itself in ways a one-liner cannot —
be idempotent, refuse on unexpected input, back up before mutating, and verify (`bash -n`, a
re-`grep`) after. It is also reviewable: show the script's contents as a reference block and
still hand over a two-token command.

### 4. Order clauses so the cheap, reversible ones fail first

Put backups, existence checks, and dry-runs before anything destructive, so a
partially-pasted command dies before it can do damage. **Better still: make the script refuse
rather than rely on ordering** — ordering is a mitigation you get by luck, a guard clause is
one you get by design. Under `set -euo pipefail`, write guards as `if`-blocks;
`grep -q X && { …; exit 0; }` returns nonzero when the grep fails, which `set -e` turns into
an unintended exit.

### 5. Placeholders belong in reference snippets, and must look different

`<owner>`, `<N>`, `<pane-id>` are fine in a block the reader is meant to adapt. They are never
acceptable in a block the reader is asked to run *now*, and the two kinds must be
distinguishable at a glance. Label reference blocks ("template — substitute `<tab-id>`") and
keep run-now blocks free of anything angle-bracketed.

### 6. One payload at a time, named by its destination

The clipboard holds exactly one thing. When staging several handoffs, do them one at a time,
say which target the current contents belong to, and do not stage the next until the first is
consumed — a convention the user asked for directly on 2026-08-24 *(session history)*.

### 4. A verbatim command still lands in *this* machine's alias layer

Runnability is not a property of the command text alone — it is the text plus the shell it
arrives in, and this repo's shell is not a stock one. Three different `ls` resolve here:

```
ls is an alias for eza --group-directories-first     <- wins in command position
ls is /opt/homebrew/opt/coreutils/libexec/gnubin/ls  <- GNU ls, first on PATH
ls is /bin/ls                                        <- BSD ls
```

The alias wins, and **eza reads `-t` as `--time <FIELD>`, not "sort by mtime"**. So a line
that looks portable and correct everywhere:

```bash
ls -t ~/.claude/projects/<slug>/*.jsonl | head -3
```

dies with `error: invalid value '<first filename>' for '--time <FIELD>'`. Worse, a listing
that may legitimately be empty is usually written with `2>/dev/null` — which suppresses that
error and prints **nothing**, so the result reads as "this project has no transcripts"
rather than "wrong tool." Observed 2026-08-27 while documenting the `--continue` pane
template: an empty result was briefly taken as evidence that `orrery ☉` had no session
history, when it had three transcripts.

**Fix: name the binary, not the alias.** `/bin/ls -t …` in anything displayed — it is
unambiguous, and unlike `command ls` it does not silently depend on which `ls` PATH resolves
to first. `command ls` does bypass the alias and is fine interactively; it just lands on GNU
`ls` here rather than BSD `ls`, so it is the weaker guarantee for a written-down command.

This generalizes past `ls`: before displaying a command built from a bare tool name, ask
whether the name is aliased in `zsh/alias.sh`. Most aliases only change *defaults* and stay
compatible. `ls` bites because its alias changes flag **semantics**.

### The self-check before you display

> Could I paste this block into a shell right now, unmodified, and have it do the right thing?

If yes, it is a run-now block: no ellipses, no placeholders. If it requires substitution, it
is a reference block — say so in the sentence above it. There is no third category.

## Why This Matters

**The failure is silent on the agent's side.** The command runs in the user's terminal. You
do not see the error unless they paste it back, and the error names the wrong culprit — `sed`
in failure 2, not the elision that produced the bad argument.

**The clipboard's failure window is the conversational turn.** This is not a rare race.
Dictation replaces the clipboard whenever the user speaks, and the user speaks between your
message and their paste nearly every time. Three losses in seven days is the observed rate.

**Partial execution is worse than failure.** Shells run `&&` chains left to right, and a
literal `...` is an *argument* error in the clause containing it — not a parse error that
stops the line. Everything to the left already ran. An elided command is therefore not "a
command that fails," it is "a command that executes an arbitrary prefix of itself." Whether
that prefix is a backup or an `rm` is a property of how you happened to order the clauses.

**The blast radius is asymmetric.** Commands the agent runs itself pass through permission
gating and a sandbox. Commands handed to a human run in their shell, as whatever user they
are — `root` over ssh in one of these two cases — with none of that. The one path with no
guardrails is the one where text was being shortened for readability.

**The fix costs nothing.** Print the real string. When the real string is unwieldy, stage a
script — which you were arguably better off doing anyway.

## When to Apply

Every time the deliverable is *"run this"* — not only when the command looks dangerous. The
two failures here were a `python3` invocation and a backup-then-patch; neither looked
dangerous.

Highest value:

- **Scratchpad paths** — long, hashed, unmemorable, unguessable if truncated.
- **`ssh` one-liners**, especially with nested quotes, `sed -i`, or `sudo`.
- **Anything mutating remote state**, or running as root.
- **Multi-clause chains** where a prefix could execute alone.

Also applies to non-shell text destined to be pasted and executed elsewhere: NDJSON for the
herdr socket, a config blob, a SQL statement. Same contract.

Does **not** apply to prose discussion of a command's shape, diffs, code the user will edit
locally, or clearly-labeled reference/template blocks.

## Examples

### Failure 1 — the elided scratchpad path

Before, as displayed (rendered as `text`, not `bash` — this is a transcript of broken
output, and per rule 5 it must not look runnable):

```text
python3 /private/tmp/claude-505/.../scratchpad/fix-claude-settings.py
```

The `...` was pasted literally; Python looked for a directory named `...`.

After — shorten the *command*, not the text:

```bash
cp /private/tmp/claude-505/-Users-dvillavicencio-Projects-Personal-dotfiles/8202ed77-ce40-41ac-bf44-aaad2312ae16/scratchpad/fix-claude-settings.py /tmp/fix-claude-settings.py
python3 /tmp/fix-claude-settings.py
```

The long path still appears once, in full. The command that matters is short and retypable.

### Failure 2 — the elided remote patch

Before, as displayed:

```text
ssh root@openclaw-prod 'cp -n /usr/local/bin/axiom-claude-launch /usr/local/bin/axiom-claude-launch.bak && sed -i ... && bash -n ...'
```

Result: `sed: -e expression #1, char 1: unknown command: '.'` — **after** the `cp -n` had
already created the backup remotely. The same run also printed, from GNU coreutils:
`warning: behavior of -n is non-portable and may change in future; use --update=none instead`
(the Macs are BSD, the VPS is GNU — prefer a timestamped backup name over `-n`).

After — the shape that worked first try:

```bash
scp /tmp/patch-axiom-launcher.sh root@openclaw-prod:/tmp/patch-axiom-launcher.sh
ssh root@openclaw-prod 'bash /tmp/patch-axiom-launcher.sh'
```

Two short lines, no nested quoting, nothing to elide — and the script refuses on unexpected
input, backs up with a timestamp, and `bash -n`s itself afterwards.

## Related

- `docs/solutions/code-quality/claude-code-bash-tool-strips-pua-glyphs.md` — the adjacent
  family: what the agent emits is not what arrives, silently.
- `docs/solutions/runtime-errors/dot-doctor-heredoc-pipe-deadlock-2026-08-07.md` — the repo
  already decided that a payload belongs in a real file with a short invocation.
- `docs/solutions/best-practices/pr-check-pass-state-is-not-a-review-verdict.md` — sibling in
  genre only. Both are "an agent hands a human something that looks right and isn't," but that
  is a genre, not a cause: one is misreading an upstream signal, this one is emitting a
  defective artifact.
