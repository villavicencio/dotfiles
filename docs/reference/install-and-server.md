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

`david` and `hal` each have a dotfiles clone at `~/Projects/Personal/dotfiles`, and the two
drift apart. VIL-700's second part moves `hal` onto `david`'s clone, so one pull as `david`
updates both accounts. The steps below make the move; nothing changes on hal until they are
run, in order. Step 5 (`verify`) exits 0 only when the move is complete and the installed
sync-check matches the shared clone's copy; it can only run once step 2 is done. To see which
clone `hal`'s zsh starts from at any time: `ssh hal-as-hal 'readlink ~/.config/zsh/.zshrc'`.

Until the move, pull both clones:
`ssh hal 'git -C ~/Projects/Personal/dotfiles pull --ff-only'` and
`ssh hal-as-hal 'git -C ~/Projects/Personal/dotfiles pull --ff-only'`.

After the move:

- `david` owns the one clone. `hal`'s 24 dotfiles links point into it (the list is `LINKS` in
  `helpers/hal_shared_clone.sh`; `~/.config/herdr/config.toml` is among them and stays dead,
  since `herdr/` is gone from the repo; any other missing target fails step 5), and so does
  `hal`'s `~/.claude/CLAUDE.md`. The file
  that link replaced is `~/.claude/CLAUDE.md.pre-vil700`.
- Pull as `david` only: `ssh hal 'git -C ~/Projects/Personal/dotfiles pull --ff-only'`. `hal`
  never runs git in that clone and never gets a `safe.directory` entry for it.
- `hal` gets into `david`'s home through one ACL entry on that folder alone,
  `user:hal allow search`. It reads the clone through the clone's own "other" permissions, and
  can read anything else in `david`'s home that other accounts can read. Before setting the
  entry, step 2 closes four paths David chose (2026-11-16): `~/.claude/file-history`,
  `~/.claude/shell-snapshots` and `~/scratch` to 700, `~/env.sh` to 600. For each path it
  changes, it first records the earlier mode in `~/.vil-700-modes-before-acl`, a file it
  creates with mode 600. Everything else stays as it is
  (`~/.cache`, `~/.local`, `~/.agents` included, by David's choice), and step 2 lists the top
  level of what other accounts can still read.
- Anything that runs as `david`, the overnight pilot included, can change files `hal` runs.
  David chose this layout knowing that. Atlas's hourly check (below) is the alarm for it.
- `DOTFILES_PROFILE=server ./install` as `hal` from a clone `david` owns is expected to fail
  at the steps that write into the repo. Fixing that is VIL-736; until it lands, don't run it
  there.
- `hal`'s old clone is moved to `~/Projects/Personal/dotfiles.pre-vil700` after one night
  (step 7). Nothing deletes it.

**Atlas's hourly check.** Hermes cron job `637debb93470` runs
`~/.hermes/scripts/dotfiles-sync-check.sh` as `hal` and sends what it prints to David's Slack
DM; empty output sends nothing, and a non-zero exit sends an error alert. From step 3 on, that
file is a copy of `helpers/hal_dotfiles_sync_check.sh`. It's a copy because Hermes refuses a
script that resolves outside `~/.hermes/scripts`, and a link would point into the clone it
watches. The original is kept beside it as `dotfiles-sync-check.sh.pre-vil700`. The job's
schedule and prompt don't change.

The check watches the clone `hal`'s `~/.config/zsh/.zshrc` link points into. It never runs git
in it: it reads the clone's `.git/HEAD` and refs as files, and keeps its own copy of GitHub's
master in `~/.cache/dotfiles-sync-check/master.git` in `hal`'s home. Git runs only there, with
no global or system config, because `hal`'s `~/.gitconfig` is one of the watched files. It
remembers the last report it sent in `~/.hermes/scripts/.dotfiles-sync-check.state` and
doesn't send that report again while nothing changes. It reports when:

- the clone is behind master, or on a commit that isn't on master;
- a tracked file in the clone differs from GitHub's copy at the commit the clone is on (at
  master, if that commit isn't on it), or is missing, unreadable, a link where the repo has a
  file, or a link that points somewhere other than the repo's link does, or has an executable
  bit that differs from the repo's mode. This is the tamper alarm. It looks at every tracked
  file outside submodules (the `dotbot` submodule, which `hal` doesn't run, is skipped), because `hal` runs more than its links point at: `zsh/zshrc` sources `zsh/functions/*.sh`, `bin/dot` runs `bin/lib/`
  and `helpers/`, and the starship and topgrade configs can run commands;
- the clone has files that commit doesn't (`.git` and submodules aside);
- the installed copy isn't master's `helpers/hal_dotfiles_sync_check.sh`. After a change to it
  merges, pull as `david`, then run step 3 again.

It exits 1 with a one-line reason, which Hermes sends as an error alert, when it can't check
(the clone or a folder in it is unreadable, GitHub can't be reached, git fails in its copy)
or can't write its state file. `DOTFILES_DRY_RUN=1` fetches nothing and writes no state.

**The move.** Each step names the account it runs as, checks the state it expects, and stops
with nothing changed when the state is anything else. Running a step again is safe: a step
whose work is complete says `done already` and exits 0. `DOTFILES_DRY_RUN=1` runs a step's
checks, prints what it would change, changes nothing, and exits 1 when the checks would stop
the real run, 0 otherwise. For step
1 it goes in front of the command; for the others it goes inside the quotes, so it reaches hal:
`ssh hal-as-hal 'DOTFILES_DRY_RUN=1 bash ~david/Projects/Personal/dotfiles/helpers/hal_shared_clone.sh relink'`. Avoid the overnight pilot's window for steps 1 to 4 (`docs/reference/hermes-commands.md`,
"The 27B is shared").

| # | Runs as | Command, from the dotfiles checkout on the personal Mac | Changes |
|---|---|---|---|
| 1 | David, on the Mac | `bash helpers/hal_shared_clone_sync.sh` | fast-forwards both clones to GitHub's master and checks they're on one commit |
| 2 | `david` | `ssh hal 'bash ~/Projects/Personal/dotfiles/helpers/hal_shared_clone.sh acl'` | closes the four paths, then adds `user:hal allow search` to `david`'s home |
| 3 | `hal` | `ssh hal-as-hal 'bash ~david/Projects/Personal/dotfiles/helpers/hal_shared_clone.sh sync-check'` | installs the new check; the old one stays as `.pre-vil700` |
| 4 | `hal` | the same, with `relink` | points the 24 links into `david`'s clone and links `~/.claude/CLAUDE.md` |
| 5 | `hal` | the same, with `verify` | nothing |
| 6 | | one night of Atlas's check running | |
| 7 | `hal` | the same, with `retire-old-clone` | moves `hal`'s clone to `~/Projects/Personal/dotfiles.pre-vil700` |

What each step checks:

- Step 1 refuses unless, in both clones, `git status` runs and shows no edits to tracked
  files, the branch is `master`, and `origin` is GitHub's URL.
- Step 2 refuses if other accounts can't search `~/Projects` and `~/Projects/Personal`, or
  can't read something in the clone (outside `.git/objects`); if `david`'s home has any other
  ACL entry for `hal`; or if one of the four paths is a link. A path that doesn't exist is
  skipped. If one of the others can't be closed, the entry isn't set; the exit is then 4 when
  that run closed or recorded something, and `acl-rollback` reopens what it closed. It says
  `done already` only when each of the four paths that exists has its closed mode and the
  entry is in place.
- Step 3 installs the shared clone's `helpers/hal_dotfiles_sync_check.sh`. It refuses if the
  installed check is none of: the original (by sha256), an earlier copy of this repo's check,
  or the original that `sync-check-rollback` put back. It says `done already` only when the
  installed check is an executable copy of the shared clone's and
  `dotfiles-sync-check.sh.pre-vil700` is the original.
- Step 4 says `done already` when every link and `~/.claude/CLAUDE.md` already point into
  `david`'s clone, before its other checks, so a pull since doesn't make it refuse. Otherwise
  it refuses unless the clones are on one commit; the installed check is step 3's (an
  executable copy of the shared clone's, with the original kept); each of the 24 links points
  into `hal`'s clone or, from an earlier run, already into `david`'s; and each linked file
  exists in both clones and is the same in both, the links already moved included.
- Step 5 fails unless every link and `~/.claude/CLAUDE.md` point into `david`'s clone, the file
  CLAUDE.md replaced is kept, the installed check is step 3's for the shared clone as it is
  now, and no other link points into the old clone.
- Step 7 says `done already` when the old clone is at `dotfiles.pre-vil700`, every link and
  `~/.claude/CLAUDE.md` point into `david`'s clone, and no other link points into the old one.
  A check that a pull has since made stale is step 5's to report. Otherwise it refuses unless
  step 5's checks pass. Before moving, it reads the old clone's edits, commits on no
  remote-tracking branch, and stashes with git, prints them, and refuses if any of those reads
  fails. Moving the clone keeps all of them.
- The scan in steps 4, 5 and 7 looks in `hal`'s home for links whose target starts with the
  old clone's path. It skips `Library`, `Desktop`, `Documents`, `Downloads`, `Movies`, `Music`
  and `Pictures`, which macOS closes to ssh sessions; if it can't read the rest, steps 5 and 7
  fail.

Exit codes, for every step: 0 done, already done, or a dry run that found nothing in the way.
1 refused, with nothing changed (for `verify`: something isn't as expected). 2 a step name
`helpers/hal_shared_clone.sh` doesn't know. 4 something was changed and then a later part
failed; the message says what changed and which step to run next. Any other code means ssh
or the shell on hal failed partway; the code says nothing about the state, so run `verify`, or
the step again with `DOTFILES_DRY_RUN=1`, to see it. Step 1 is the exception: it reports an
ssh failure itself, as 1 when it happens during the checks (nothing changed yet) and as 4 when
it happens after, and its last lines show where each clone is.

Undoing, newest step first. Each is a step of `helpers/hal_shared_clone.sh` with the same exit
codes, run as `hal` like step 3 unless it says `david`. None of them compares the two clones,
so a pull as `david` since the move doesn't stop one. Each accepts what a full or a stopped
run of its forward step leaves; what else it needs is in its bullet:

- Step 7: `restore-old-clone` moves the old clone back.
- Step 4: `relink-rollback` points each link that's in `david`'s clone back into `hal`'s, and
  puts `CLAUDE.md.pre-vil700` back as `~/.claude/CLAUDE.md`. It needs `hal`'s clone in place,
  so after step 7, run `restore-old-clone` first.
- Step 3: `sync-check-rollback` puts the original check back (and keeps the `.pre-vil700`
  copy). It refuses while `hal`'s `.zshrc` link points anywhere but `hal`'s own clone, because
  the original runs git in the clone the links point into. The new check works either way, so
  this is optional.
- Step 2: `acl-rollback`, as `david` (`ssh hal 'bash ~/Projects/Personal/dotfiles/helpers/hal_shared_clone.sh acl-rollback'`),
  takes the entry off `david`'s home, then puts each path whose mode is still the closed one
  back to its recorded mode. Run it only after `relink-rollback`: with `hal`'s links still in
  `david`'s clone, removing the entry breaks `hal`'s shell and git, and as `david` the step
  can't see `hal`'s links to check.
- Step 1: nothing to undo; it's an ordinary fast-forward of both clones.

After changing any of the three scripts, run `ci/hal-shared-clone-checks.sh`.
