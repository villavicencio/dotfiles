# Install pipeline and the server profile

Moved out of the always-loaded `CLAUDE.md` on 2026-10-22 (VIL-402), word for word except
for heading levels. `CLAUDE.md` keeps the one-line rules and points here.

## Install pipeline

`./install` runs Dotbot with the layered configs — `dotbot-conf/base.yaml` (shared)
then the platform layer (`dotbot-conf/darwin.yaml` or `dotbot-conf/linux.yaml`) — which
together:

1. Creates required directories under `~/.config/`
2. Writes `~/.zshenv` to set `ZDOTDIR=$HOME/.config/zsh`
3. Installs Oh My Zsh and plugins
4. Symlinks config files into `~/.config/`
5. Runs helper scripts: omz, brew, Brewfile, tmux, nvim, nvm, node (fonts install via Brewfile casks)

Helper scripts are in `helpers/`. Each is independently runnable.

On Windows, `install.ps1` replaces all of the above — see `docs/reference/windows.md`.

## Server profile (`hal`)

`DOTFILES_PROFILE=server ./install` sets up `hal`, a headless Mac mini (macOS 27, Apple
Silicon) reached only over SSH. It runs as the standard account `hal`, which has no sudo and
owns Homebrew at `/opt/homebrew`. An unset profile or `desk` is the normal install. Any other
value fails before Dotbot runs, and so does `server` on anything but macOS.
`DOTFILES_PROFILE=server ./install --dry-run` previews it.

How it differs from a desk Mac:

- **Layers:** `base.yaml` runs with `--except clean`, then `dotbot-conf/server.yaml` runs in
  place of `darwin.yaml`. Dotbot's `clean` only removes dead links in `~` that resolve into
  this repo (`dotbot/src/dotbot/plugins/clean.py`, v1.24.1). hal also carries dangling links
  copied from the VPS, such as `~/personal`, and a first install has nothing to clean, so
  `clean` doesn't run there at all.
- **Packages:** `brew/Brewfile.server`, formulae only plus two CLI-only casks (`vercel`, which
  Homebrew moved out of core, and `1password-cli`; CI allows exactly those). An old `vercel`/`vercel-cli` formula
  blocks that cask, so `helpers/migrate_vercel_cask.sh` swaps it first, on both profiles.
  On the desk profile, `helpers/migrate_tldr_tlrc.sh` likewise runs first: it unlinks the
  disabled `tldr` formula, links or installs `tlrc`, and only then uninstalls `tldr`
  (if `tlrc` fails it relinks `tldr`, says so when even that fails, and stops the install).
  On a Mac without the old formula, a `bin/tldr` that isn't `tlrc`'s is left alone, with a
  message, and the install carries on.
  Installed by `brew bundle` with
  `HOMEBREW_BUNDLE_NO_UPGRADE=1` and `HOMEBREW_NO_INSTALL_UPGRADE=1`, so installed formulae
  aren't upgraded under running services. A new formula can still upgrade a shared
  dependency it needs. The Homebrew network installer never runs: if brew is missing at
  the `BREW_PREFIX` location (`/opt/homebrew` on Apple Silicon), the wrapper stops before
  Dotbot runs, with nothing changed. No font casks. The container runtime (OrbStack, and brew's `docker` and
  `colima`) is installed out of band and is in no Brewfile.
- **Skipped:**
  - chsh.
  - The nvm, node, uv and Claude Code installers. node and uv come from the Brewfile, and
    Claude Code is installed separately on hal.
  - The Claude settings seed and the `~/.claude` links. `~/.claude` arrives from the VPS with
    regular files in those places. One exception, made by hand on 2026-10-23 (#244):
    `hal`'s `~/.claude/statusline-command.sh` is a link into the clone `hal` runs from, so a
    pull updates it. The July copy it replaced is
    `~/.claude/statusline-command.sh.pre-link-20261023`. VIL-700's move (below, "One dotfiles
    clone on hal") makes `hal`'s `~/.claude/CLAUDE.md` a link too.
    `hal` and `david` on hal also have `autoCompactWindow`, which places the statusline's
    compaction marker. The server profile skips the settings seed, and the migration leaves an
    existing value alone, so set it by hand to match `claude/settings.json` (600000 since
    2026-11-11; it was 400000).
  - The iTerm profile.
  - The `~/.config/nvim` link and the plugin bootstrap. Without the bootstrap, the first
    `nvim` would rewrite `nvim/lazy-lock.json`, so the server's nvim runs with no config. A
    link into this repo left by an earlier desk install is moved to `~/.config/nvim.pre-dotfiles`
    (`helpers/retire_desk_nvim_link.sh`); a real directory or a link elsewhere is left alone.
- **Kept:** Oh My Zsh, the shared zsh, git and tmux configs, the pre-commit hook, and the
  Codex `AGENTS.md` link. TPM installs the plugins against a private, throwaway tmux socket.
  Its `install_plugins` reads the plugin list from whatever tmux server is current, so a
  server hal already runs without this config would make it abort ("Tmux Plugin Manager not
  configured") and fail the install.
- **Overlays**, linked only under this profile (the tmux one by `base.yaml`, ahead of TPM;
  the others by `server.yaml`):

  | Link | Source | Effect |
  |---|---|---|
  | `~/.config/zsh/.zprofile` | `zsh/zprofile.server` | With `ZDOTDIR` set, zsh no longer reads `~/.zprofile` or `~/.zshrc`. This file carries what hal's own versions did: brew shellenv, OrbStack's `init.zsh`, and `~/.lmstudio/bin`, each only if present. hal's `~/.zprofile` and `~/.zshrc` are left untouched. After shellenv it re-applies `zsh/zshenv`'s PATH order, which shellenv's prepend and macOS's `/etc/zprofile` (`path_helper`) undo in every login shell. |
  | `~/.config/git/gitconfig.platform` | `git/gitconfig.server` | Resets the credential helpers (osxkeychain and GCM can't work over SSH) to `/opt/homebrew/bin/gh` for github.com and gist.github.com, and sets `core.pager = less -FRX`. |
  | `~/.config/tmux/local.conf` | `tmux/local.server.conf` | Sets `@continuum-boot off`. It is linked before the TPM step starts a tmux server, so tmux-continuum never loads with boot on and never writes `~/Library/LaunchAgents/Tmux.Start.plist`, which opens iTerm at login. A regular `local.conf` already there is renamed to `local.conf.dotbot-backup.<timestamp>` first (Dotbot's `backup`). If the link still isn't in place, `install_tmux.sh` fails without starting tmux. |

- **`~/.zshenv`:** a `~/.zshenv` this install didn't write is kept as
  `~/.zshenv.pre-dotfiles` before being replaced. A regular file is copied there, and a
  symlink is moved there as a link.
- **GitHub over HTTPS only:** neither `hal` nor `david` on hal has github.com in
  `~/.ssh/known_hosts` (checked 2026-10-23), so `git clone git@github.com:…` fails with
  "Host key verification failed". Clone with `gh repo clone <owner>/<repo>` or an
  `https://github.com/…` URL. Every clone there already uses HTTPS: both dotfiles clones,
  `david`'s `~/Projects/hal-bench`, and the skills clone. The pilot's git calls also
  authenticate over HTTPS with its own token. Keep HTTPS as the convention rather than adding
  GitHub's host key.

Verify with `ci/server-profile-checks.sh static` locally. CI's `macos-server` job runs the
profile in a simulated hal home and checks the pre-existing files, the shell chain, git, and
that no LaunchAgent was added. It also checks that a second run changes nothing.

### Reaching hal as `hal` (VIL-700)

`hal` is the service account Atlas, Axiom, LM Studio and MergeWren run in. Treat it as
production. These SSH aliases in the personal Mac's `~/.ssh/config` (machine-local, not
tracked; `docs/reference/shell-and-path.md`) reach hal as `david` or `hal`:

| Alias | Logs in as | Key | Use |
|---|---|---|---|
| `hal` | `david` | the Mac's main key, `~/.ssh/id_ed25519` | Anything done as `david`, including `david`'s dotfiles clone |
| `hal-as-hal` (after the setup below) | `hal` | the Mac's main key | Claude and Codex sessions that run their own SSH commands as `hal`; David too |
| `hal-orca` | `hal` | `~/.ssh/hal-orca` | Orca's `hal-orca` environment only (its server on hal runs as `hal`) |
| `hal-svc` | `david`, then `sudo -u hal -i` | the main key, then David's password | David by hand |

`hal-as-hal` exists only on a Mac where the setup below has been done. Until then the alias
is missing, and the main key is not on `hal`'s `authorized_keys`.

`hal-svc` is also the name of an Orca environment, which is a different thing: the one the
`atlas` and `axiom` launchers open their tabs on (`docs/reference/hermes-commands.md`). Those
tabs log in as `david` and run `sudo -u hal -i` (`zsh/functions/atlas.sh`).

Rules:

- A Claude or Codex session that runs its own SSH commands as `hal` uses `hal-as-hal`. Never
  `hal-orca`, which is Orca's key, and never `hal-svc`, which needs David's password.
- David's `atlas` and `axiom` launchers keep their path: an Orca tab on the `hal-svc`
  environment, which logs in as `david`, then `sudo -u hal -i` (`zsh/functions/atlas.sh`,
  `zsh/functions/axiom.sh`, `docs/reference/hermes-commands.md`). VIL-700 doesn't change them.
- A Claude Code session also needs a permission rule for the alias (setup step 4).
- `hal-as-hal` is a full shell as `hal`. Read before you write, and avoid installs and
  service restarts while the overnight pilot uses the local models (the window is in
  `docs/reference/hermes-commands.md`, "The 27B is shared").

Setup, on the personal Mac only (the key is pinned to its tailnet address). Do the steps in
order; nothing here exists until you do it. Before step 1, check on the Mac that
`ssh -o BatchMode=yes hal-orca 'id -un'` prints `hal`, that `tailscale ip -4` prints an
address, and that `~/.ssh/id_ed25519.pub` exists.

1. **Add the Mac's main public key to `hal`'s `~/.ssh/authorized_keys`.** David runs this by
   hand on the personal Mac, in a terminal, as his own account; an agent session doesn't. It
   reaches hal as `hal` over `hal-orca`, because until this key is in, that is the only login
   as `hal` that needs no password. This is the one use of `hal-orca` outside Orca. No
   password is expected. If the ssh agent has dropped Orca's key, ssh asks for the `hal-orca`
   key's passphrase, not a hal account password.

   From the dotfiles checkout on the Mac, run `bash helpers/add_hal_as_hal_key.sh`. It sends
   only the key's type and base64 body, never the private key, and pins the new line to the
   Mac's tailnet IPv4 address, read from `tailscale ip -4` when it runs, with the same options
   as the `hal-orca` line. It refuses anything that isn't an ed25519 public key or a
   dotted-quad address. Only on a run that is about to append, it first makes a new backup
   (never overwriting an older one) and makes sure the file ends in a newline.
   After writing, it checks that the new line is the last line and that `ssh-keygen` reads it
   as one more key, then prints the options it wrote and the fingerprints now on hal. The key's
   comment becomes `mac-main-key hal-as-hal <date>`.

   If the key is already on hal, the script changes nothing. With exactly the intended
   options it exits 0. With any other options, or none, it prints that line's options next
   to the intended ones and exits 3; changing or removing that line is David's decision.
   Exit 1 means it refused, or a check failed before `authorized_keys` was changed. Exit 4
   means the write or a check after it failed; it names the backup to restore.

   Any other exit code means ssh or the shell on hal failed. The code doesn't tell you the
   state of the file, and neither does whether a backup exists. Look at the file instead.
   This lists its fingerprints and the options of any `mac-main-key hal-as-hal` line, without
   the key itself:

   ```bash
   ssh hal-orca 'ssh-keygen -lf ~/.ssh/authorized_keys; awk "/mac-main-key hal-as-hal/ { i = index(\$0, \"ssh-ed25519 \"); print (i > 1 ? substr(\$0, 1, i - 2) : \"(no options)\") }" ~/.ssh/authorized_keys'
   ```

   If the run made a backup, compare the file with the newest
   `~/.ssh/authorized_keys.bak-*`. Running the script again is safe: it adds the key only
   when it's missing, and it refuses a line with other options. `DOTFILES_DRY_RUN=1` prints
   what it would do and sends nothing. After changing the script, run
   `ci/hal-as-hal-key-checks.sh`.

2. **Add the alias to the Mac's `~/.ssh/config`**, above `Host *`. Edit the file on the Mac as
   your own account; no password. Host aliases are machine-local in this repo, so the block
   is not tracked:

   ```
   Host hal-as-hal
       HostName <hal's tailnet name: the HostName of the Host hal block>
       User hal
       IdentityFile ~/.ssh/id_ed25519
       IdentitiesOnly yes
       ServerAliveInterval 30
       ServerAliveCountMax 3
   ```

3. **Check it** on the Mac: `ssh -o BatchMode=yes hal-as-hal 'id -un'` prints `hal`. It logs
   in as `hal` with the main key and never asks for a password; BatchMode makes it fail
   instead. An authentication failure means step 1 is missing, or the connection didn't come
   from the pinned tailnet IPv4 address (see below). "Could not resolve hostname hal-as-hal"
   means step 2 is missing.

4. **Claude Code only:** add `Bash(ssh hal-as-hal:*)` to `~/.claude/settings.json` on the Mac.
   Agents can't write that file; David adds the rule. The file and the rule are Claude
   Code's; a Codex session follows its own approval settings.

What hal looks like after step 1:

- sshd lets `hal` in by public key only (`Match User hal` → `AuthenticationMethods publickey`
  in `/etc/ssh/sshd_config.d/200-hal.conf`). There is no `AllowUsers` line. This is already
  so; step 1 doesn't change it.
- `hal`'s `~/.ssh/authorized_keys` has one line per key, each pinned to the Mac's tailnet
  IPv4 address with `from="<that address>",no-agent-forwarding,no-X11-forwarding`. The
  `hal-orca` line is there already; step 1 adds the main key's line with the same options.
- The pin is IPv4 only. If ssh ever reaches hal over the tailnet's IPv6 address, hal refuses
  both keys.

### One dotfiles clone on hal (VIL-700)

`david` and `hal` each have a dotfiles clone at `~/Projects/Personal/dotfiles`. VIL-700's
second part moves `hal` onto `david`'s clone, so one pull as `david` updates both accounts.
Nothing changes on hal until the steps below are run. Until then, pull both clones:
`ssh hal 'git -C ~/Projects/Personal/dotfiles pull --ff-only'` and
`ssh hal-as-hal 'git -C ~/Projects/Personal/dotfiles pull --ff-only'`.

After the move:

- `david` owns the one clone. `hal`'s 24 dotfiles links (`LINKS` in
  `helpers/hal_shared_clone.sh`) and `hal`'s `~/.claude/CLAUDE.md` point into it; the file
  CLAUDE.md replaced is `~/.claude/CLAUDE.md.pre-vil700`. One link,
  `~/.config/herdr/config.toml`, stays dead: `herdr/` is gone from the repo.
- Pull as `david` only: `ssh hal 'git -C ~/Projects/Personal/dotfiles pull --ff-only'`. Don't
  run git in that clone as `hal`, and don't give `hal` a `safe.directory` entry for it.
- `hal` gets into `david`'s home through one ACL entry on that folder, `user:hal allow search`,
  and reads the clone through its group and other permissions (`hal` is in `david`'s group,
  `staff`). It can also read whatever else in `david`'s home is open to that group or to all
  accounts. Before adding the entry, step 2 closes four paths
  David chose (2026-11-16): `~/.claude/file-history`, `~/.claude/shell-snapshots` and
  `~/scratch` to mode 700, `~/env.sh` to 600. The mode each had before step 2 first changed
  it goes to `~/.vil-700-modes-before-acl`. Nothing else is closed (`~/.cache`, `~/.local` and
  `~/.agents` stay as they are, by David's choice); step 2 prints the top level of what stays
  open to `hal`, judged by group and other mode bits alone.
- `hal` can search `david`'s home but not list it. Under `NO_CASE_GLOB` (set in `zsh/zshrc`)
  zsh lists every directory on a pattern's path, so an absolute glob through `david`'s home
  finds nothing for `hal` ("no matches found"). `zsh/functions.sh` turns `CASE_GLOB` back on
  while it lists its files, and step 5 runs `zsh/functions.sh` as `hal` with `zshrc`'s glob options and checks that it
  defines functions from that folder.
- Anything that runs as `david`, the overnight pilot included, can change files `hal` runs.
  David chose this layout knowing that; Atlas's hourly check is the alarm for it.
- Don't run `DOTFILES_PROFILE=server ./install` as `hal` from `david`'s clone until VIL-736:
  it writes into the repo.
- `hal`'s old clone moves to `~/Projects/Personal/dotfiles.pre-vil700` after one night
  (step 7). Nothing deletes it.

**Atlas's hourly check.** Hermes cron job `637debb93470` runs
`~/.hermes/scripts/dotfiles-sync-check.sh` as `hal` and sends what it prints to David's Slack
DM; empty output sends nothing, and a non-zero exit sends an error alert. Step 3 makes that
file a copy of `helpers/hal_dotfiles_sync_check.sh` (Hermes refuses a script that resolves
outside `~/.hermes/scripts`) and keeps the original beside it as
`dotfiles-sync-check.sh.pre-vil700`; the job itself doesn't change. The check watches the
clone `hal`'s `~/.config/zsh/.zshrc` link points into, without running git in it, and reports
when:

- the clone is behind GitHub's master, or on a commit that isn't on master;
- a tracked file outside submodules differs from the repo at the commit the clone is on (at
  master, if that commit isn't on master), in content or executable bit, or is missing, unreadable, or a link where the repo has a file.
  This is the tamper alarm: `hal` runs these files, and anything running as `david` can change
  them;
- the clone has files, outside `.git` and submodules, that commit doesn't;
- the installed check isn't master's copy; the report gives the command (step 3 again, once
  `david`'s clone is on master).

It doesn't print a report identical to the last one it recorded. It exits 1 when it can't
check or can't write its state file; its last line says why. `DOTFILES_DRY_RUN=1` fetches
nothing and writes no state.

**The move.** Run the steps in order, from the dotfiles checkout on the personal Mac. Avoid
the overnight pilot's window for steps 1 to 4 (`docs/reference/hermes-commands.md`, "The 27B
is shared").

| # | Runs as | Command | Exit 0 means |
|---|---|---|---|
| 1 | David, on the Mac | `bash helpers/hal_shared_clone_sync.sh` | both clones are on the commit GitHub's master had when it started |
| 2 | `david` | `ssh hal 'bash ~/Projects/Personal/dotfiles/helpers/hal_shared_clone.sh acl'` | each of the four paths is missing or closed (its mode 700 or 600, and no ACL entry on it that allows anything), and `user:hal allow search` is the only entry for `hal` on `david`'s home |
| 3 | `hal` | `ssh hal-as-hal 'bash ~david/Projects/Personal/dotfiles/helpers/hal_shared_clone.sh sync-check'` | the installed check is an executable copy of the shared clone's, and the original is kept as `dotfiles-sync-check.sh.pre-vil700` |
| 4 | `hal` | the same, with `relink` | the 24 links and `~/.claude/CLAUDE.md` point into `david`'s clone, and `CLAUDE.md.pre-vil700` is a file |
| 5 | `hal` | the same, with `verify` | step 4's state; step 3's, for the clone as it is now; each linked file is readable (the herdr link aside); the scan of `hal`'s home finds no other symlink to the old clone or a path inside it; and `zsh/functions.sh`, run as `hal` with `zshrc`'s glob options, defines a function from `zsh/functions` |
| 6 | | one night of Atlas's check | |
| 7 | `hal` | the same, with `retire-old-clone` | `hal`'s clone is at `~/Projects/Personal/dotfiles.pre-vil700` |

Step 2 refuses, changing nothing, if one of the four paths is a link or has an ACL entry that
allows access: it doesn't remove entries it didn't add. The scan in step 5 (and in step 7,
which runs step 5's checks before moving anything) skips `Library`, `Desktop`, `Documents`,
`Downloads`, `Movies`, `Music` and `Pictures`, which macOS closes to ssh sessions, and
`.Trash`. It stays on the home's own disk, matches a symlink only when its target, as written, is
the old clone's full path or a path inside it (a relative link isn't caught), and doesn't look inside files.

Exit codes, for every step: 0 as in the table (each step of `helpers/hal_shared_clone.sh`
but `verify` says `done already` when it was in that state before the run). 1: not in that
state; the step either refused, changing nothing, or failed partway, and its messages say what it changed. Running it again is safe, or undo it as below.
2: a step name the script doesn't know. Any other code means ssh or the shell failed; to see
where things stand, run `verify` or the step with `DOTFILES_DRY_RUN=1`. That runs a step's
checks, changes nothing, and exits 0 when the step is done or its checks pass, 1 when they
don't (a real run can still fail where the checks don't look: a write, or for step 1 a clone that
can't be fast-forwarded). For step 1 it goes in front of the command; for the others, inside the quotes:
`ssh hal-as-hal 'DOTFILES_DRY_RUN=1 bash ~david/Projects/Personal/dotfiles/helpers/hal_shared_clone.sh relink'`.

Undoing, newest step first. Each is a step of `helpers/hal_shared_clone.sh`, run as `hal` like
step 3 unless it says `david`. None compares the two clones, so a pull as `david` since the
move doesn't stop one.

- Step 7: `restore-old-clone`. Exit 0: `hal`'s clone is back at `~/Projects/Personal/dotfiles`.
- Step 4: `relink-rollback` (after `restore-old-clone`, if step 7 ran) points the links back
  and puts `CLAUDE.md.pre-vil700` back. Exit 0: the 24 links point into `hal`'s clone, and
  `~/.claude/CLAUDE.md` is a file.
- Step 3: `sync-check-rollback`, optional, since the new check works with either clone. It
  refuses while `hal`'s `.zshrc` link points anywhere but `hal`'s own clone, because the
  original check runs git in the clone the links point into. Exit 0: the installed check is
  the original.
- Step 2: `acl-rollback`, as `david`
  (`ssh hal 'bash ~/Projects/Personal/dotfiles/helpers/hal_shared_clone.sh acl-rollback'`),
  only after `relink-rollback`: removing the entry while `hal`'s links point into `david`'s
  clone breaks `hal`'s shell and git, and as `david` the step can't see those links. Exit 0:
  `david`'s home has no entry for `hal`, and each path step 2 changed that was still at its
  closed mode is back at its recorded mode (a path without a record, such as one step 2
  found already closed, stays as it is).
- Step 1: nothing to undo.

After changing any of the three scripts, run `ci/hal-shared-clone-checks.sh`.
