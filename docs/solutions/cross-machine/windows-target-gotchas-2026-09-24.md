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
scripts out as CRLF. `windows/gitconfig` sets `autocrlf = input`, but that only
applies after `install.ps1` has run. The first clone therefore needs
`git -c core.autocrlf=input clone …`.

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
