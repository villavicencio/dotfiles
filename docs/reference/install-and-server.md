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
    `hal`'s `~/.claude/statusline-command.sh` is a link into its clone, so a pull updates it.
    The July copy it replaced is `~/.claude/statusline-command.sh.pre-link-20261023`.
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

   The command sends only the key's type and base64 body, never the private key. It pins the
   new line to the Mac's tailnet IPv4 address, read from `tailscale ip -4` when it runs, with
   the same options as the `hal-orca` line. It refuses anything that isn't an ed25519 public
   key, adds nothing if the key is already there, backs the file up first, and replaces the
   key's comment with `mac-main-key hal-as-hal <date>`.

   ```bash
   a=$(tailscale ip -4 | head -n 1)
   if [ -z "$a" ]; then
     echo "no tailnet IPv4 from tailscale ip -4 (CLI missing or not connected); nothing sent" >&2; false
   else
     awk -v a="$a" 'NR==1{print a, $1, $2}' ~/.ssh/id_ed25519.pub | ssh hal-orca 'set -u; f=~/.ssh/authorized_keys; read -r a t k || exit 1; case "$a" in ""|*[!0-9.]*) echo "unexpected pin address; nothing changed" >&2; exit 1;; esac; case "$t" in ssh-ed25519) ;; *) echo "not an ed25519 public key; nothing changed" >&2; exit 1;; esac; case "$k" in ""|*[!A-Za-z0-9+/=]*) echo "unexpected key data; nothing changed" >&2; exit 1;; esac; if awk -v k="$k" "{for(i=1;i<=NF;i++) if(\$i==k) f=1} END{exit !f}" "$f"; then echo "key already present; nothing changed"; exit 0; fi; /bin/cp -p "$f" "$f.bak-$(/bin/date +%Y%m%d-%H%M%S)" && printf "from=\"%s\",no-agent-forwarding,no-X11-forwarding %s %s mac-main-key hal-as-hal %s\n" "$a" "$t" "$k" "$(/bin/date +%F)" >> "$f" && /bin/chmod 600 "$f" && echo "added; keys now on hal:" && ssh-keygen -lf "$f" | awk "{print \$2, \$3, \$4}"'
   fi
   ```

   It prints the fingerprints now on `hal`'s `authorized_keys`, or says it changed nothing.

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

Each account still has its own dotfiles clone at `~/Projects/Personal/dotfiles`. Pull both:
`ssh hal 'git -C ~/Projects/Personal/dotfiles pull --ff-only'` and
`ssh hal-as-hal 'git -C ~/Projects/Personal/dotfiles pull --ff-only'`. VIL-700's second part
plans to move `hal` onto `david`'s clone; until it lands, this paragraph is current.
