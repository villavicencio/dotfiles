# Windows PC

Moved out of the always-loaded `CLAUDE.md` on 2026-10-22 (VIL-402), word for word except
for heading levels. `CLAUDE.md` keeps the one-line rules and points here.

## Setting up the Windows PC

The Windows layer is **PowerShell, not Dotbot**: Dotbot's `shell` directives assume a
POSIX shell, and nothing in `base.yaml` (zsh, Oh My Zsh, tmux, Homebrew) applies. The glue
stays in the platform's native shell, per
`docs/solutions/best-practices/keep-dotfiles-glue-layer-in-shell-not-rust-lua-2026-05-30.md`.

1. Turn on Developer Mode (Settings → System → For developers) so symlinks work unelevated.
2. Install PowerShell 7 and git: `winget install Microsoft.PowerShell Git.Git`
3. Clone with LF line endings — Git for Windows' system config sets `core.autocrlf=true`,
   which would check the shell scripts out as CRLF before the `~/.gitconfig` stub that
   `install.ps1` writes can override it:
   ```powershell
   git -c core.autocrlf=input clone https://github.com/villavicencio/dotfiles.git $HOME\Projects\Personal\dotfiles
   ```
4. `cd $HOME\Projects\Personal\dotfiles`, then `pwsh -File install.ps1 -DryRun` to preview
   and `pwsh -File install.ps1` to apply. A failed step does not stop the others; the
   script exits 1 and lists what failed.
5. `gh auth login --scopes workflow` (the github.com credential helper in `windows/gitconfig`
   is `gh`). gh is the only GitHub credential on the PC, and its default scopes (`repo`,
   `read:org`, `gist`) make GitHub **reject any push that touches `.github/workflows/`**:
   `refusing to allow an OAuth App to create or update workflow … without workflow scope`.
   An existing login adds it with `gh auth refresh -h github.com -s workflow` (it opens a
   browser, so an agent can't do it). This blocked VIL-151 and the CI half of VIL-154 on
   2026-09-24. A composite action under `.github/actions/` is *not* a workflow file and
   pushes fine without the scope.
6. System settings, from an **elevated** `pwsh`: `pwsh -File windows/tweaks.ps1 -DryRun`,
   then without `-DryRun`. See "System tweaks" below.

What `install.ps1` does, in order — each step idempotent, `-DryRun` mutates nothing:

1. `winget import windows/packages.json --no-upgrade` — installs what is missing and never
   upgrades what is present (without `--no-upgrade` it upgrades every outdated package,
   running apps included). Upgrades are topgrade's job (`update`).
2. Symlinks the configs shared with macOS — `git/gitignore`, `git/gitattributes`,
   `starship/starship.toml`, `lazygit/config.yml` (into `%APPDATA%`), `claude/CLAUDE.md`,
   `claude/statusline-command.sh`, and the whole `nvim/` directory as `%LOCALAPPDATA%\nvim`
   (where Windows Neovim reads its config) — plus the Windows Terminal fragment. A real
   file or directory in the way is moved to `<name>.pre-dotfiles`, never deleted.
3. Writes two **stubs** rather than links:
   - `~/.gitconfig` `[include]`s `git/gitconfig` then `windows/gitconfig`. Git has no
     OS-conditional include, so the shared file cannot pull in the Windows overrides itself.
     The overrides reset the multi-valued `credential.helper` lists with an empty value
     (dropping `osxkeychain` and the `/opt/homebrew/bin/gh` path) before adding
     `manager` / the Windows `gh.exe`. The stub itself sets `core.autocrlf = input`:
     **anything that governs checkout must live outside the worktree.** A setting in
     `windows/gitconfig` vanishes whenever a checkout removes that file (any commit
     before #186), and git then rewrites files with CRLF under the system `autocrlf=true`.
     `windows/gitconfig` keeps a second copy on purpose: a machine whose stub predates #187
     still gets `input` from it after a pull, until `install.ps1` is re-run. Don't remove
     either copy.
   - `$PROFILE` dot-sources `windows/powershell/profile.ps1`. `$PROFILE` lives under
     Documents, which OneDrive commonly redirects and syncs, and OneDrive handles symlinks
     badly. Resolve Documents with `[Environment]::GetFolderPath('MyDocuments')`, never
     hardcode it.
4. Seeds `~/.claude/settings.json` from `windows/claude-settings.json` **only when absent**
   — the same contract as `helpers/install_claude_settings.sh` on the Macs. A live file is
   never touched, and the seed is a copy, never a link (Claude Code rewrites the file).
5. `pre-commit install` (pre-commit via `uv tool`; gitleaks via winget, **pinned in
   `windows/packages.json` too** — that is a third place the gitleaks version must match).
6. `windows/install_nvim.ps1`: the Windows twin of `helpers/install_nvim.sh`. It restores
   the plugins pinned in `nvim/lazy-lock.json` into `%LOCALAPPDATA%\nvim-data` and runs
   `helpers/nvim_verify_lock.lua`, the verifier the two share. A missing nvim is a failure
   (step 1 imports with `--ignore-unavailable`, so a Neovim that didn't install would
   otherwise pass silently), except under `-SkipPackages`, which passes `-AllowMissing`
   and `-NoUpgrade`. With `-NoUpgrade`, an nvim older than 0.12 fails with an "upgrade
   Neovim.Neovim" message. Otherwise, when nvim is older than 0.12, it runs `winget upgrade --id Neovim.Neovim -e`
   (step 1's `--no-upgrade` leaves an old copy in place), then fails with exit 1 if the
   version is still too old. It can also be run on its own.

Windows-specific rules:

- **Windows seeds `windows/claude-settings.json`, never `claude/settings.json`.** Every hook
  in the Mac file calls a tmux bash script, which would error on every event here.
  The Windows file is the Mac baseline with three things removed, and nothing added:

  | Removed | Why |
  |---|---|
  | `hooks` (all of them) | `tmux-attention.sh` — no tmux on Windows |
  | `preferredNotifChannel: "iterm2"` | iTerm2 is macOS-only; Claude Code picks a default |
  | `Bash(brew …)`, `Bash(tmux -V*)` allow rules | no Homebrew or tmux; dead rules |

  Everything else is identical: `permissions` (the remaining allow rules + `defaultMode`),
  `enabledPlugins`, `extraKnownMarketplaces`, and the UI/notification prefs. **The
  `statusLine` block is byte-identical** — `sh "$HOME/.claude/statusline-command.sh"` runs
  under Git Bash's `sh` with `$HOME` expanded (verified live 2026-09-24), and `install.ps1`
  links the script. Its deps are `jq` (winget `jqlang.jq`), `git`, `awk`, and the Nerd Font
  from the Terminal fragment.
  **Nothing keeps the two files in step but you**: change a shared key in one, change it in
  the other. Under Git Bash, `install_claude_settings.sh` (seed and `--capture`) and
  `report_drift.sh` target the Windows file, so a capture on the PC cannot overwrite the Mac
  baseline with a hook-free copy. On Windows `report_drift.sh` reports **only** the Claude
  settings comparison — its Homebrew and npm-globals sections are Mac/Linux inventories and
  are skipped, not failed. Both helpers probe for a Python that actually runs (`python3`
  under Git Bash is usually the Microsoft Store placeholder, which `command -v` finds but
  which exits non-zero), fall back to `python`, and hand it `cygpath -w` paths. **With no
  working Python they run one through uv** — `uv run --no-project --quiet python` — so a PC
  set up only by `install.ps1` (which installs uv, `astral-sh.uv`, but no Python) still gets
  a real comparison and capture. uv uses an interpreter it can discover (its own, `PATH`, or
  the Windows registry; it skips the Store placeholder) or downloads a managed one on first
  use; `--no-project` stops it treating the repo as a project. Python is resolved **lazily**,
  only on the path that actually normalizes or captures settings, so a run that compares
  nothing (settings not seeded yet, a dry run, the seed path) never probes and never lets uv
  download. Test the found state with a flag or the resolver's exit status, never
  `${#PYTHON[@]}`: Bash 3.2 under `set -u` treats an empty array as unbound. Don't add a Python to
  `windows/packages.json` for this. With neither a Python nor a working uv, both helpers fail
  loudly; a failed normalization is an error, never a silent "(in sync)". The fallback is
  not Windows-gated, but the Macs and Linux normally find `python3` first and never reach it.
  The seed only lands on a machine with no settings file. A PC that already has one keeps
  it; adopting the baseline there is a human step (the auto-mode classifier blocks agents
  from writing it): move the live file aside, re-run `install.ps1`, then re-add any
  machine-local keys (`modelSettings`, `theme`, …).
- **The status line normalizes Windows paths for display only.** Claude Code sends `cwd` as
  `C:\Users\…` while Git Bash's `$HOME` is `/c/Users/…`; the script converts a drive-letter
  path with `cygpath -u` before the `~` comparison (paths outside `$HOME` keep their native
  form) and passes the raw path to `git -C`. It also feeds jq with `printf '%s\n'` (dash's
  `echo` expands the `\\` in JSON-escaped Windows paths into an invalid escape) and reads
  with `jq -j` (a native `jq.exe` ends its line with CRLF, and dash keeps the CR).
- **`claude/CLAUDE.md` IS linked on Windows** — its Mac-only rules sit under "Mac setup
  (personal Mac)", and the Obscura rule says it exists only on the personal Mac and gives the
  `WebFetch` fallback everywhere else (the Windows installer doesn't provision `browse-gateway`).
- **`topgrade/topgrade.toml` is NOT linked on Windows** — its `[commands]` entry is POSIX
  shell. Topgrade runs on defaults there.
- **Machine-local overrides:** `~/env.ps1` (sourced last by the profile) is the `~/env.sh`
  counterpart; `~/.gitconfig.local` works unchanged.
- **Windows Terminal's `settings.json` is app-rewritten** — same trap as Claude's. Tracked
  terminal config goes in the fragment (`windows/terminal/dotfiles.json`), which Terminal
  only reads. The one exception is `defaultProfile`, which a fragment cannot set:
  `windows/tweaks.ps1` edits that single value in place (see "System tweaks").
- **Neovim on Windows:** `Neovim.Neovim` is a machine-scope MSI, so `winget import` raises a
  UAC prompt. It adds `C:\Program Files\Neovim\bin` to the machine PATH, which
  `Update-SessionPath` picks up in the same run. `LuaLS.lua-language-server` is the Brewfile's
  `lua-language-server` (NvChad enables `lua_ls`). The config needs nothing else to start:
  git, curl, tar, and ripgrep are already there. Optional extras are in `nvim/README.md`:
  stylua and the html/css servers through `:Mason` (the latter need Node), and the
  tree-sitter CLI plus a C compiler for parsers Neovim does not bundle.
- **Don't run `python3` from a Windows install step.** It is often the Microsoft Store
  stub under `WindowsApps`, which is why the nvim pin verifier is Lua run by `nvim -l`.
- **CI covers the Windows layer.** The `windows` job in `install-matrix.yml` runs on a
  hosted `windows-2025` runner. It does a dry run, a `-SkipPackages` apply, a second run
  that must change nothing, and the #187 commit-switch check. It does **not** run the full
  `winget import`: that is a gaming PC's app list, which is slow, and some installers want
  a GUI or a reboot. It checks that every `packages.json` ID and pinned version resolves in
  winget instead, because `install.ps1`'s `--ignore-unavailable` would skip a dead ID
  without saying so. **winget is a hard prerequisite of the job:** if a runner image ever
  lacks it, the job fails. There is deliberately no fallback, because the ID check, the
  real nvim bootstrap and the profile's starship/zoxide checks all depend on
  winget-installed tools, and a fallback would let the job go green with them skipped. The
  LF checks (W1, W9) reject `w/crlf` and `w/mixed`. **Adding or removing a link in
  `install.ps1` means updating the job's `EXPECTED_LINKS` too.**

## System tweaks (`windows/tweaks.ps1`)

The counterpart of macOS `defaults write`: a data-driven list (`$Tweaks`) of Windows settings,
each compared by its configured value (registry or `settings.json`; the mouse and time entries
also check the live session) and reported `ok`, `would set` (`-DryRun`) or `set`. Before a change it saves
the prior values under `%LOCALAPPDATA%\dotfiles\tweaks-backups\<timestamp>-<pid>\`. A failing entry
doesn't stop the others; the script exits 1 and lists them.

- **Separate from `install.ps1` on purpose.** Some entries write HKLM or run `w32tm` and need
  elevation, and `install.ps1` stays unelevated. An unelevated run still *reads* the admin
  entries (reported `ok` when correct); it records a failure only when one would have to
  change. It also changes the live session (mouse), which a routine re-install shouldn't do.
- **Record only what this PC already has.** An entry lands after the setting was changed by
  hand and verified, and `-DryRun` must then read `ok` on every line. The script is a record,
  not a place to try new settings. Current entries: mouse acceleration off, Game Bar
  background recording off, Game Mode on, hardware-accelerated GPU scheduling on (admin,
  needs a restart), Windows Time syncing from `time.windows.com,0x9` (admin), and Terminal's
  default profile = PowerShell 7.
- **Game Mode is the one expected `would set`.** Windows defaults it on but doesn't write
  `HKCU\Software\Microsoft\GameBar\AutoGameModeEnabled` (DWORD, 1 on / 0 off) until the
  Settings toggle does, so a PC that was never toggled reads `AutoGameModeEnabled=<absent>`.
  The first real run writes the `1` Windows was already assuming; after that it reads `ok`.
  (`AllowAutoGameMode`, which some PCs also have in that key, isn't recorded: the Windows 11
  references — ElevenForum's Game Mode tutorial, Microsoft Q&A — use `AutoGameModeEnabled`.)
- **Only the mouse and time entries apply live.** Game Bar, Game Mode and GPU scheduling are
  plain registry writes: Game Bar may need a sign-out, and GPU scheduling needs a restart. Mouse: `SystemParametersInfo(SPI_SETMOUSE, [0,0,0], SPIF_UPDATEINIFILE|SPIF_SENDCHANGE)`
  writes the same three `HKCU\Control Panel\Mouse` values *and* changes the running session.
  A registry-only write waits for the next sign-in, so the mouse entry also compares
  `SPI_GETMOUSE` with the registry. Time: `w32tm /config … /update` makes the running service
  re-read its settings, then `/resync` syncs now. Correct registry values don't prove the
  service uses them (this PC had them and had never synced), so the time entry also compares
  `w32tm /query /source` with the configured peer, and runs the set when either differs. The
  source reads "Local CMOS Clock" until the first poll after boot, so a run just after boot
  may resync, which is harmless.
- **The Terminal entry edits one value, carefully**, because Terminal rewrites the rest of its
  `settings.json` itself:
  - *Which file:* the packaged build's `…\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json`
    or the unpackaged (zip/Scoop) build's `%LOCALAPPDATA%\Microsoft\Windows Terminal\settings.json`.
    When both exist, the running `WindowsTerminal.exe` decides (a packaged one runs from
    `WindowsApps\Microsoft.WindowsTerminal_*`; Preview/Canary are other packages and don't
    count). If neither kind is running, both are, or a process path can't be read, the entry
    fails naming both files rather than guess.
  - *Which key:* a comment-aware scan of the JSONC finds the **top-level** `defaultProfile`,
    skipping `//` and `/* */` comments, strings, and nested objects/arrays. Key names are
    compared after decoding JSON escapes, so `"defaultProfile"` counts. A duplicate
    top-level key, a non-string value, or text it can't scan is an error, as is invalid UTF-8
    (decoded strictly, so it never round-trips as U+FFFD). Only that value's characters are
    spliced; BOM and line endings are kept.
  - *How it writes:* the bytes it read are backed up first, and the new text goes to a temp
    file beside the original and is read back. Terminal saves by writing `settings.json.tmp`
    and renaming it over `settings.json`, so "check the hash, then rename ours over it" would
    still lose a save that landed between the two. Instead the original is opened sharing only
    read (read + DELETE access, via P/Invoke `CreateFileW`): from then on nothing else can write
    it or rename over it, and a file some program already has open for writing makes the entry
    fail with nothing changed. Through that handle it re-checks the hash, renames the original
    aside (`SetFileInformationByHandle`, never replacing), then renames the temp file into
    place without replacing. Terminal's own reads share everything and still work. The only
    gap left is the instant between those two renames, when the path is empty: a save landing
    there wins, and the original is put back if it can be (else the error names the `.old`
    file). A symlinked `settings.json` is edited at its target, leaving the link.
  - Dot-sourcing the script (`. windows/tweaks.ps1`) defines its functions and `$Tweaks` and
    stops before the engine runs, which is how these are tested against scratch files. The
    real `set` path of the script as a whole has still only run against scratch copies.
- **Never name a `$Tweaks` key `Values`, `Keys` or `Count`.** On an entry without that key,
  `$t.Values` returns the hashtable's own `.Values` collection instead of `$null`, so the
  entry gets treated as a registry entry. That's why the registry list is called `Registry`.

Gotchas behind these rules: `docs/solutions/cross-machine/windows-target-gotchas-2026-09-24.md`.
