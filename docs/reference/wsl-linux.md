# WSL and Linux

Moved out of the always-loaded `CLAUDE.md` on 2026-10-22 (VIL-402), word for word except
for heading levels. `CLAUDE.md` keeps the one-line rules and points here.

## Setting up WSL on the Windows PC

The Linux layer runs unchanged inside WSL — `./install` with `base.yaml` + `linux.yaml`. It
is a **second, independent clone** in the Linux filesystem, not the Windows checkout through
`/mnt/c` (that path is slow, and Windows-side line-ending/permission semantics leak in).

1. From Windows: `wsl --install -d Ubuntu-26.04 --no-launch`: the same release CI's
   `ci/Dockerfile` tests (both moved from 24.04 in VIL-154, 2026-09-25). When CI moves to
   a new release, reinstall WSL to match; the 24.04 distro held nothing unique and was
   simply unregistered.
2. `wsl -d Ubuntu-26.04` and create the Linux user interactively — use `dvillavicencio` so
   `/home/…` paths line up with `/Users/…` on the Macs. To redo a fresh distro (wrong
   username), `wsl --unregister Ubuntu-26.04` wipes it; reinstall with step 1.
3. Inside WSL: `git clone https://github.com/villavicencio/dotfiles.git ~/Projects/Personal/dotfiles`,
   `cd` into it, `./install --dry-run`, then **`./install` run by the user in a WSL window** —
   `sudo` and `chsh` both prompt for the Linux password, which an agent shell cannot type.
   An agent can do everything else (clone, dry-run, verify) via
   `wsl -d Ubuntu-26.04 -u <user> -- sh <script>` (use `zsh -i <script>` to check anything
   `.zshrc` sets up). On 26.04 `sudo` is **sudo-rs** (its prompt reads `[sudo: authenticate]
   Password:`). CI runs as root and never exercises it, but the 2026-09-25 install ran
   cleanly under sudo-rs 0.2.13.
4. Verify in zsh: `getent passwd $USER` shows `/usr/bin/zsh`, `dot doctor` exits 0,
   `dot bench` median under budget (184 ms measured on 26.04, 2026-09-25; the first run
   after install is a slow cold start). The pin check takes its arguments:
   `nvim --headless -l helpers/nvim_verify_lock.lua nvim/lazy-lock.json ~/.local/share/nvim/lazy`
   (27/27 at their locked commits).

Expected on a fresh install, not failures:

- `install_nvim.sh` installs Neovim itself: the pinned official release tarball
  (sha256-checked) into `~/.local/opt/nvim-v<ver>`, with `~/.local/bin/nvim` linked to it.
  It needs no sudo, and apt's 0.9.5 `neovim` is no longer installed. A WSL distro set up
  before VIL-152 still has apt's copy at `/usr/bin/nvim`. `~/.local/bin` comes first on
  PATH, so it is shadowed and harmless; `sudo apt remove neovim` removes it.
- `dot doctor` warns: no Homebrew; macOS-only aliases (`show`/`hide`/`flush`/`localip`,
  `update`→topgrade) point at missing binaries; `.claude/settings.local.json` absent;
  `python3` "shadowed" by `/bin` → `/usr/bin` (Ubuntu's merged-usr symlink, same file).
- `eza`, `zoxide`, `lazygit` are absent — the apt list in `helpers/install_packages.sh` is
  a curated subset of the Brewfile.
- **No Node (nvm) and no uv on Linux.** `install_nvm.sh`, `install_node.sh` and
  `install_uv.sh` run only from `darwin.yaml`, so `node`/`npm`/`uv` are missing in WSL even
  in an interactive zsh. This is intended (VIL-157, canceled 2026-10-12): nothing in WSL needs
  them yet, and Claude Code's native installer doesn't need Node. Wire them into `linux.yaml` if that
  changes.

Why the Linux layer needed changes for this (both invisible in CI):

- **zsh is installed in `base.yaml`'s Linux-only locale step**, before `install_omz.sh`:
  the pinned Oh My Zsh installer exits 1 ("Zsh is not installed") on a bare Ubuntu, and
  `ci/Dockerfile` pre-installs zsh, so CI never saw it.
- **`linux.yaml`'s `chsh` step sets `stdin: true`.** Dotbot wires a shell step's stdin to
  `/dev/null` by default; Linux `chsh` reads its password through PAM on stdin, so without
  it `chsh` printed `Password:` and failed instantly with `PAM: Authentication failure`.
  (`sudo` is unaffected — it opens `/dev/tty` itself.) Any future Dotbot step that prompts
  needs the same flag.

## Git on Linux — an overlay via include (VIL-146)

`~/.gitconfig` is the same symlink to `git/gitconfig` on every Dotbot host. On Linux,
`linux.yaml` also links `~/.config/git/gitconfig.platform` → `git/gitconfig.linux`, which
`git/gitconfig` `[include]`s after its `[credential]` sections and before
`~/.gitconfig.local`. macOS links nothing there, and git silently skips a missing include,
so the Macs resolve exactly the config they did before (the only new key is
`include.path` itself). The overlay:

- **resets the multi-valued `credential.helper` lists** with an empty value, dropping
  `osxkeychain`, the `/usr/local` GCM path and `/opt/homebrew/bin/gh`, then adds
  `!/usr/bin/gh auth git-credential` for github.com and gist.github.com only. Other hosts
  get no helper, so git prompts. `/usr/bin/gh` is where `install_packages.sh`'s
  cli.github.com apt repo puts it, and it's also what `gh auth setup-git` writes, so
  running that later adds nothing.
- **sets `core.pager = less -FRX`**. `vim -` stays the Mac preference (see `CLAUDE.md`, "Things
  intentionally left as-is"). Git only pages on a tty, so scripts never hit it, but on
  openclaw-prod it turned git output in agent sessions into vim buffers.

`git config --get-all credential.helper` **still prints the macOS values on Linux**. The
reset works by appending an empty entry, not by deleting lines from another file. To see
what git actually runs:

```bash
printf 'protocol=https\nhost=github.com\n\n' | GIT_TRACE=1 GIT_TERMINAL_PROMPT=0 git credential fill 2>&1 >/dev/null | grep run_command
```

CI's R8 assertion (`.github/actions/install-matrix-post-apply`) runs that on the `linux`
leg and checks the macOS values are unchanged on `macos`.

Why not the alternatives: **`includeIf "gitdir:/home/"`** (the ticket's first idea)
conditions on the repository, not the OS, so `git clone` into `/tmp`, a repo under `/mnt/c`,
or `git config --global` outside any repo would still see the macOS helpers. **A
Windows-style stub** would mean a Dotbot shell step writing `~/.gitconfig`, which is a
symlink into the repo on existing hosts: a plain `>` follows the link and overwrites
`git/gitconfig` itself (the same trap as "A hook symlinked into the repo…"). The overlay has
no checkout-governing setting like Windows' `autocrlf`, so it doesn't need to live outside
the worktree.

The Linux apt list also installs `git-delta`, `vim` and `less`: `git/gitconfig` names delta
(the diff/show pager and `interactive.diffFilter`) and vim (`core.editor`), and the overlay
names less. The bare ubuntu base image (24.04 or 26.04) has none of them.

**Picking it up on an existing WSL install:** `git pull && ./install` in the WSL clone (the
new link is a plain Dotbot `link:`, and apt adds the three packages), then `gh auth login`
if gh isn't authenticated yet.

Gotchas behind these rules: `docs/solutions/cross-machine/wsl-ubuntu-target-2026-09-24.md`.

## CI image (`ci/Dockerfile`)
The install matrix's Linux leg runs in a minimal Ubuntu 26.04 image. Why it's built the way it is:

- **Bare server, as root.** The install runbook and `dotbot-conf/linux.yaml` assume root. The image
  carries only the bootstrap deps `helpers/install_packages.sh` doesn't install itself; later apt
  installs are the pipeline's own job. 26.04 since VIL-154, so CI tests the same release as WSL.
- **Published, pinned, not baked.** `publish-ci-image.yml` publishes it to
  `ghcr.io/<owner>/dotfiles-ci-ubuntu` on master pushes that touch the Dockerfile; consumers pin
  the SHA digest, not the `:26.04` tag (`:24.04` is left as it was). The repo is mounted at
  runtime, so repo changes need no rebuild. The base image is digest-pinned too (multi-arch
  manifest list), matching the consumer-side pin; bump it with
  `docker buildx imagetools inspect ubuntu:26.04` when Canonical ships patches.
- **sudo, even as root.** `install_packages.sh` runs `sudo apt-get install …`. As root sudo is a
  no-op, but without the binary the helper aborts and later helpers cascade-fail ("tmux: command
  not found"). An earlier image left it out and the workflow had to apt-install it at runtime
  (#58). On 26.04 the package is classic sudo (`sudo.ws`); a stock install, like the WSL distro,
  defaults to sudo-rs. As root neither authenticates, so CI never exercises sudo-rs; the first
  real run is `./install` on the distro.
- **python3, not python3-minimal.** Dotbot imports `json` and `yaml` at startup, and
  python3-minimal strips the stdlib (`ModuleNotFoundError`). The full metapackage adds
  libpython3-stdlib (~45 MB) and matches stock Ubuntu Server.
- **`Acquire::ForceIPv4`, first in the chain.** archive.ubuntu.com resolves to Cloudflare IPv6,
  which the Actions runners sometimes can't reach, so every fresh apt connection waited ~60 s
  before falling back (the 60–69 s gaps of 2026-05-04, #65). It's set in the image, not at
  runtime, so earlier apt calls get it, and not in the install pipeline, where real hosts don't
  need it. It comes before `apt-get update` so the image build itself is protected too. Full
  investigation: `docs/solutions/cross-machine/install-matrix-ipv6-fallback-misattribution-2026-05-05.md`.
