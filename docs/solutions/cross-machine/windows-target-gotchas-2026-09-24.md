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
  - github-actions
  - cross-machine
severity: Medium
component: "install.ps1, windows/tweaks.ps1, windows/gitconfig, windows/powershell/profile.ps1, windows/packages.json, windows/terminal/dotfiles.json"
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
again. The setting now lives in the stub, which is outside the repo. It also
stays in `windows/gitconfig`, because removing it from there would give a
machine whose stub predates #187 *neither* copy after a pull. Each copy covers
the case where the other is missing (CodeRabbit on #187). To repair a
tree that's already affected, force the value for that one command:
`git -c core.autocrlf=input checkout -- <files>`. The credential overrides
still live in `windows/gitconfig`, so on a branch from before #186 git falls
back to the Mac helper paths. That's acceptable, because nothing there
rewrites files.

**Build the stub with explicit `"`n"` line endings.** A PowerShell here-string
takes its line endings from the script file, so a CRLF copy of `install.ps1`
wrote a CRLF stub. The next LF run saw a "different" file and backed it up and
rewrote it for nothing.

**`gh`'s default token can't push workflow files.** `gh auth login` requests
`repo`, `read:org` and `gist`. With `gh` as the github.com credential helper,
the first push that touched `.github/workflows/` (the VIL-151 Windows CI leg)
was refused:

```text
! [remote rejected] … (refusing to allow an OAuth App to create or update
workflow `.github/workflows/install-matrix.yml` without `workflow` scope)
```

Everything else pushes fine, so this surfaces only on CI changes. Log in with
`gh auth login --scopes workflow`, or add it later with
`gh auth refresh -h github.com -s workflow`. Both open a browser device flow,
so an agent can't do it. There was no other stored GitHub credential to fall
back on: `cmdkey /list` showed only `gh`'s own entries.

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
`herdr-blank-state.sh`), so each event would error. Since VIL-150, `install.ps1`
seeds `windows/claude-settings.json` instead (only when `~/.claude/settings.json`
is absent): the Mac baseline minus the hooks, the iTerm2 notification channel and
the brew/tmux allow rules. `claude/CLAUDE.md` is safe to link, because its
Mac-only sections are already labeled as such.

**The status line works unchanged under Git Bash's `sh`**, including the Mac
`statusLine` command string (`$HOME` expands). Three Windows-only wrinkles, all
fixed in the script (VIL-150):

- Claude Code sends `cwd` as `C:\Users\Loft\...` while `$HOME` is
  `/c/Users/Loft`, so `~` shortening never matched. The script converts a
  drive-letter path with `cygpath -u` for the comparison only; `git -C` still
  gets the raw path, which it accepts.
- `echo "$input"` under dash (and any `xpg_echo` sh) turns JSON's `\\` into
  `\`, so jq failed with "Invalid escape" and every field came back empty.
  `printf '%s\n'` passes the bytes through.
- A native `jq.exe` ends output with CRLF. Git Bash's `sh` drops the CR, but
  dash kept it in the last field and drew an empty worktree badge. `jq -j`
  writes no line ending at all.

CI gotcha: the install matrix's R3 PII scan greps every tracked file outside
`docs/**` for `/Users/<alnum>`, and a Git Bash path like `/c/Users/me` in a
code comment matches it. Write example paths with a placeholder
(`/c/Users/<you>`), as the Mac examples already do.

Testing gotcha: the Claude Code Bash tool collapses `\\` in inline command
text, so feed Windows-path JSON through a file written with the Write tool, not
an inline heredoc or `printf`. `dash` ships with Git for Windows, so the
dash-only failures reproduce on the PC.

**Windows Terminal rewrites its own `settings.json`**, the same trap as Claude
Code's settings and Otty's config. Tracked terminal config therefore goes in a
JSON fragment (`%LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\dotfiles\`),
which Terminal only reads. It is the counterpart of the iTerm dynamic profile.
The fragment targets the pwsh profile by its fixed GUID
`{574e775e-4f2a-5b96-ac1e-a2962a402336}` with `"updates"`. Terminal generates
that profile the next time it launches after pwsh is installed.

## System tweaks (`windows/tweaks.ps1`)

**A mouse setting written only to the registry doesn't apply until the next
sign-in.** `HKCU\Control Panel\Mouse` (`MouseSpeed`, `MouseThreshold1`,
`MouseThreshold2`) is what persists, but the running session keeps its own copy.
`SystemParametersInfo(SPI_SETMOUSE, 0, int[3]{threshold1, threshold2, speed},
SPIF_UPDATEINIFILE | SPIF_SENDCHANGE)` changes both: per the Win32 docs,
`SPIF_UPDATEINIFILE` "writes the new system-wide parameter setting to the user
profile" and `SPIF_SENDCHANGE` broadcasts `WM_SETTINGCHANGE`. "Enhance pointer
precision" off is `[0,0,0]`. The script's mouse entry reads both the registry
and `SPI_GETMOUSE`, so a registry-only change still shows up as drift.

**`w32tm /config` needs `/update` to reach the running service.** Microsoft's
W32Time reference says `/update` "notifies W32Time that the configuration is
changing, causing the changes to take effect". This PC's `NtpServer` and `Type`
were `time.windows.com,0x9` / `NTP`, but the clock had never synced. The
documented stand-alone default for `NtpServer` is `time.windows.com,0x1`, so on
a fresh install the entry would detect the difference and fix it. Correct
values don't prove the service uses them, though, so the entry also compares
`w32tm /query /source` with the configured peer and resyncs when it differs.
Right after boot the source reads "Local CMOS Clock" until the first poll, so a
run then may resync needlessly, which is harmless.

**Game Mode's registry value doesn't exist until something writes it.** Game
Mode is on by default, but `HKCU\Software\Microsoft\GameBar\AutoGameModeEnabled`
(DWORD, 1 on / 0 off) is only created when the Settings toggle is flipped. This
PC had never flipped it, so the key held no such value while Game Mode was on.
Recording it means a dry run reads `would set` (`<absent>` → `1`) until the
first real run writes it; that is the one expected non-`ok` line.

**Editing Terminal's `settings.json` safely needs three things a regex doesn't
give.** The first version matched a line-anchored `"defaultProfile"` regex and
rewrote the file with `WriteAllText`. Review (#192) found three holes:
- *Two installs.* The packaged build keeps its settings under
  `Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\`, an unpackaged
  (zip/Scoop) build under `%LOCALAPPDATA%\Microsoft\Windows Terminal\`. Taking
  whichever exists first can edit a file the Terminal in use never reads. The
  running `WindowsTerminal.exe` tells them apart: a packaged one runs from
  `WindowsApps\Microsoft.WindowsTerminal_*`. With no signal, fail and name both.
- *JSONC.* A regex anchored to line starts skips `// "defaultProfile"` but still
  matches a nested `"defaultProfile"` or one inside `/* */`. A small scan that
  tracks comments, strings and bracket depth finds the real top-level key, and
  only that value's characters are replaced.
- *Concurrent writes.* Terminal saves its own file whenever its settings UI
  changes. Hash the bytes when read, write a temp file beside the original,
  re-hash the original just before `File.Move(tmp, path, overwrite)` (a
  same-directory rename), and fail if it changed.

**A hashtable's own properties shadow missing keys.** `$Tweaks` entries are
hashtables. The first version named the registry list `Values`. On the Terminal
entry, which has no such key, `$t.Values` returned the hashtable's built-in
`.Values` collection instead of `$null`. The engine then treated it as a
registry entry, and the dry run failed with `Cannot bind argument to parameter
'LiteralPath' because it is null`. Keys that exist win over properties, so this
only fails on entries *without* the key. Avoid `Values`, `Keys` and `Count` as
key names.

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

## CI on a hosted Windows runner (VIL-151)

The `windows` job in `install-matrix.yml` runs on `windows-2025`. These points
come from its first runs on 2026-09-25 (PR #194):

- **winget works on the hosted image.** `winget v1.11.510` is on PATH, and both
  `winget show` and `winget install --silent --source winget` run
  non-interactively. That includes machine-scope MSIs (Starship, Neovim
  0.12.5), because the runner account is elevated. Resolving all 32 IDs in
  `packages.json` took about 13 seconds.
- **Symlinks need no Developer Mode there.** The runner is elevated, so
  `New-Item -ItemType SymbolicLink` just works. That means CI can't catch a
  machine where Developer Mode is off.
- **The image already has `core.autocrlf=true`** in Git for Windows' system
  config, matching the gaming PC. The job still sets it explicitly, so the #187
  check can't pass by accident on a future image.
- **winget PATH changes reach the registry, not the step's process.** The job
  deliberately doesn't add them to `GITHUB_PATH`, so `install.ps1`'s
  `Update-SessionPath` has to find gitleaks, uv and nvim. It does. A step that
  runs the tools itself, like the profile probe, merges the machine and user
  PATH from the registry first, the way a new terminal would.
- **zoxide's init wraps `prompt`.** The profile runs starship's init, then
  zoxide's. zoxide saves the current `prompt` and defines its own, which calls
  the saved one. So `function:prompt` never mentions starship, even when
  starship is working.
- **`Get-Module starship` is empty even when starship's init ran.** The init is
  a `New-Module` dynamic module, and `Get-Module` doesn't list dynamic modules.
  Check `$env:STARSHIP_SHELL` and the exported `Enable-TransientPrompt` instead.
- **A PowerShell function that returns a one-element array returns the element.**
  `$gh = Get-X` then gives a string, and `$gh[0]` is its first character. Wrap
  the call in `@(...)` when the caller indexes the result.