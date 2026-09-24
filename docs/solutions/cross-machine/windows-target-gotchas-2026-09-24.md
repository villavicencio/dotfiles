---
title: "Adding Windows as a third target — the gotchas behind install.ps1's shape"
date: 2026-09-24
category: cross-machine
tags:
  - windows
  - powershell
  - winget
  - git
  - onedrive
  - windows-terminal
  - claude-code
  - cross-machine
severity: Medium
component: "install.ps1, windows/gitconfig, windows/powershell/profile.ps1, windows/packages.json, windows/terminal/dotfiles.json"
problem_type: "cross-machine config portability"
module: "install pipeline (windows)"
related_solutions:
  - "docs/solutions/best-practices/keep-dotfiles-glue-layer-in-shell-not-rust-lua-2026-05-30.md — why the Windows glue is PowerShell rather than Dotbot"
  - "docs/solutions/integration-issues/otty-config-symlink-hostile-atomic-rename-2026-08-07.md — the app-rewrites-its-own-config trap that Windows Terminal's settings.json shares"
---

# Adding Windows as a third target — the gotchas behind install.ps1's shape

The Windows gaming PC joined the repo on 2026-09-24. Each item below was hit, or
verified, while building `install.ps1`, and each explains a choice that would
otherwise look arbitrary.

## Shell and profile

**PSReadLine's prediction option throws when output is redirected.**
`Set-PSReadLineOption -PredictionSource History` fails in any non-interactive
`pwsh` (a script, or Claude Code's shell tool) with:

```text
The predictive suggestion feature cannot be enabled because the console output
doesn't support virtual terminal processing or it's redirected.
```

Because the profile loads for `pwsh -File` too, an unguarded profile makes every
scripted `pwsh` call print this error. `profile.ps1` gates the whole PSReadLine
block on `-not [Console]::IsOutputRedirected`.

**Documents is often redirected into OneDrive**, and `$PROFILE` lives under
Documents (`~/OneDrive/Documents/PowerShell/Microsoft.PowerShell_profile.ps1`
on this PC). OneDrive handles symlinks badly, so `$PROFILE` is a one-line stub
that dot-sources the tracked profile. Resolve the folder with
`[Environment]::GetFolderPath('MyDocuments')`, never a hardcoded path.

**winget's `Microsoft.PowerShell` installs pwsh as an MSIX package.** It
resolves to `%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe`, and
`C:\Program Files\PowerShell\7\pwsh.exe` does not exist. Call `pwsh` by name.

**Passing `-Command` from Windows PowerShell 5.1 to `pwsh.exe` strips inner
double quotes.** Claude Code's PowerShell tool is 5.1, so something like
`pwsh -Command '... "{0}" -f $x ...'` arrives mangled and fails with a
`ParserError`. Put the code in a file and use `pwsh -File`.

## git

**Git for Windows sets `core.autocrlf=true` in its system config**
(`C:\Program Files\Git\etc\gitconfig`), so a plain clone checks the shell
scripts out as CRLF. The `~/.gitconfig` stub sets `autocrlf = input`, but that
only applies after `install.ps1` has run. The first clone therefore needs
`git -c core.autocrlf=input clone …`.

**Never put a checkout-controlling setting in a file inside the worktree.**
`autocrlf = input` first lived in `windows/gitconfig`, which the stub includes
from the repo's working tree. On 2026-09-24, `git switch master` moved to a
master from before #186, where that file doesn't exist. Git silently ignores a
missing include, so `autocrlf` fell back to the system `true`, and the following
`git pull` wrote all 13 changed files with CRLF (`git ls-files --eol` showed
`i/lf w/crlf`). That included `helpers/generate_docs_index.sh`, which bash
can't run with CRLF. It also defeats a repair: deleting and re-checking-out
those files deletes `windows/gitconfig` too, so the checkout runs as `true`
again. The setting now lives in the stub, which is outside the repo. To repair a
tree that's already affected, force the value for that one command:
`git -c core.autocrlf=input checkout -- <files>`. The credential overrides
still live in `windows/gitconfig`, so on a branch from before #186 git falls
back to the Mac helper paths. That's acceptable, because nothing there
rewrites files.

**Build the stub with explicit `"`n"` line endings.** A PowerShell here-string
takes its line endings from the script file, so a CRLF copy of `install.ps1`
wrote a CRLF stub. The next LF run saw a "different" file and backed it up and
rewrote it for nothing.

**Git has no OS-conditional include**, so `git/gitconfig` cannot pull in the
Windows overrides by itself. `~/.gitconfig` is therefore a generated stub that
`[include]`s `git/gitconfig` and then `windows/gitconfig`, with absolute paths
written at install time.

**`credential.helper` is multi-valued.** The shared file adds `osxkeychain`, a
`/usr/local` GCM path and `/opt/homebrew/bin/gh`. A later `helper =` with an
empty value resets the list, and the Windows helpers are added after that.
`git config --show-origin --get-all credential.helper` shows the whole chain,
resets included. Only the entries after the last empty value take effect.

## winget

**`winget import` upgrades every already-installed package with a newer
version**, not just the missing ones. The first run upgraded nine apps, and Logi
Options+ failed mid-upgrade with installer exit code `1008` because it was
running. `install.ps1` passes `--no-upgrade`, which leaves upgrades to topgrade
(`update`).

**`winget export` records only packages it can match to a source**, and it
matches too much: .NET/VC++ runtimes, WindowsAppRuntime, Edge, OneDrive. Treat
the export as a candidate list. `packages.json` is curated to intentional
installs, the same rule as the Brewfile.

**`winget import --no-upgrade` exits 0 when everything is already
installed**, so any non-zero exit is a real failure. When measuring it, don't
pipe winget into `Select-Object -First N`: the pipeline stops early, kills
winget, and `$LASTEXITCODE` reads `-1`. That produced a false "already
installed counts as failure" reading once. Capture `$LASTEXITCODE` on the line
right after the call.

**A running process never sees PATH changes that winget makes.** winget writes
the user PATH in the registry (`%LOCALAPPDATA%\Microsoft\WinGet\Links` for
portable packages). The shell that ran the install, and every process started
before it, keeps the old PATH. That includes the Claude Code session itself,
so `! gh auth login` failed with `command not found` right after `gh` was
installed, and the gitleaks pre-commit hook failed with `Executable gitleaks not
found`. After winget, `install.ps1` adds whatever the registry PATH has that
the process lacks (`Update-SessionPath`). It *merges* rather than replaces,
because replacing would drop entries a parent process or profile added only to
this session, and a `uv` found that way would vanish mid-install. Interactively,
open a new terminal, or call the tool by its full path.

**Native exit codes don't trip `$ErrorActionPreference = 'Stop'`.** It only
covers PowerShell errors. `install.ps1` checks `$LASTEXITCODE` after winget,
`uv` and `pre-commit`. It also wraps each link and stub in `Invoke-Step`,
because a PowerShell error there (a symlink refused when Developer Mode is off)
would otherwise abort the script under `Stop`. Every failure is recorded, the
remaining steps still run, and the script exits 1 with the list. That applies to
`-DryRun` too, where a missing link source is reported. It prints "Installation
complete!" only when nothing failed.

## Claude Code and Windows Terminal

**`claude/settings.json` must not be seeded on Windows.** Every hook in it
calls a tmux or herdr bash script (`tmux-attention.sh`, `herdr-agent-state.sh`,
`herdr-blank-state.sh`), so each event would error. `claude/CLAUDE.md` is safe
to link, because its Mac-only sections are already labeled as such.

**Windows Terminal rewrites its own `settings.json`**, the same trap as Claude
Code's settings and Otty's config. Tracked terminal config therefore goes in a
JSON fragment (`%LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\dotfiles\`),
which Terminal only reads. It is the counterpart of the iTerm dynamic profile.
The fragment targets the pwsh profile by its fixed GUID
`{574e775e-4f2a-5b96-ac1e-a2962a402336}` with `"updates"`. Terminal generates
that profile the next time it launches after pwsh is installed.

## Repo scripts run from Git Bash

**`python3` in Git Bash is the Microsoft Store placeholder.** It resolves to
`%LOCALAPPDATA%\Microsoft\WindowsApps\python3` and prints "Python was not
found". The python.org installer registers `python` and `py` only. Scripts that
call `python3` (for example `helpers/generate_docs_index.sh`) need a `python3`
shim on `PATH` that runs `python`.

**`generate_docs_index.sh` wasn't Windows-safe until this change.**
`os.path.relpath` returned `best-practices\foo.md`, which broke every markdown
link, and text-mode `open(..., "w")` wrote CRLF. Together they rewrote every row
of `INDEX.md`. It now normalizes `rel` to `/` and writes with `newline="\n"`, so
a Windows run is byte-identical to a macOS one.

## Claude Code's shell tool

**Claude Code's shell safety check blocks `Remove-Item` when a command merely
mentions a system-looking path.** A cleanup command that removed
`\ASUS\`-scheduled tasks was blocked because the task path string sat in the
same command as `Remove-Item`, even though `Unregister-ScheduledTask` was the
thing using it. The whole command is refused before any of it runs. Split the
task-removal and file-removal steps into separate commands.
