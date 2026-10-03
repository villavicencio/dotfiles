#!/usr/bin/env bash
# Assertions for the `server` install profile (DOTFILES_PROFILE=server, the
# headless Mac mini `hal`). Called by the macos-server job in
# .github/workflows/install-matrix.yml; `static` also runs anywhere, so it can
# be run locally before pushing.
#
#   ci/server-profile-checks.sh static          Brewfile.server contents + the
#                                               wrapper's profile validation
#   ci/server-profile-checks.sh seed            build a simulated hal $HOME
#   ci/server-profile-checks.sh post            after `./install`: rc chain,
#                                               preserved files, skips (git
#                                               is post-apply R8's)
#   ci/server-profile-checks.sh launchagents    no LaunchAgent added (tmux-continuum
#                                               boot), with a positive control
#   ci/server-profile-checks.sh snapshot FILE   record $HOME + brew state, for
#                                               the second-run idempotency diff
#
# seed/post/snapshot work on $HOME, so run them with HOME pointing at the
# simulated home. SEED_STATE (a dir OUTSIDE $HOME) carries the seed's hashes
# and the pre-install cask list across steps.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BREWFILE="$REPO/brew/Brewfile.server"
fail=0

err() { echo "::error::$*"; fail=1; }
ok()  { echo "ok: $*"; }
expect() {  # expect <label> <want> <got>
  if [ "$2" != "$3" ]; then
    err "$1: want [$(printf '%s' "$2" | tr '\n' '|')] got [$(printf '%s' "$3" | tr '\n' '|')]"
  else
    ok "$1 = [$(printf '%s' "$3" | tr '\n' '|')]"
  fi
}

# Brewfile entries of one kind ("brew", "cask", …), first quoted arg only.
entries() {
  sed -nE "s/^[[:space:]]*$1[[:space:]]+\"([^\"]+)\".*/\1/p" "$BREWFILE"
}

# Formulae the shared shell and git config invoke, plus the server set from
# the work order. Every one must be in Brewfile.server.
REQUIRED="starship zoxide atuin fzf eza bat git-delta neovim
coreutils gnu-sed grep findutils gawk jq ripgrep fd tmux git gh gitleaks
node uv syncthing util-linux tree wget curl pre-commit"

# Must never appear: the container runtime is installed out of band, and the
# rest is desk-only.
EXCLUDED="docker-desktop colima docker mosh herdr irssi handbrake yt-dlp aria2
mac-cleanup-py pam-reattach terminal-notifier corelocationcli lolcat
screenfetch jrnl pyenv pyenv-virtualenv go yarn perl cpanminus"

cmd_static() {
  if [ ! -f "$BREWFILE" ]; then
    err "brew/Brewfile.server is missing"
    BREWFILE=/dev/null
  fi
  # Formulae only: no casks, Mac App Store apps, VS Code extensions, taps.
  local other
  other="$(grep -nE '^[[:space:]]*(cask|mas|vscode|whalebrew|tap|go|cargo|uv)[[:space:]]' "$BREWFILE" || true)"
  if [ -z "$other" ]; then ok "Brewfile.server has formulae only"; else err "non-formula entries in Brewfile.server: $other"; fi
  # Any entry kind, not just brew: comments may mention it, entries may not.
  sed -nE 's/^[[:space:]]*[a-z]+[[:space:]]+"([^"]+)".*/\1/p' "$BREWFILE" | grep -qxF docker-desktop \
    && err "docker-desktop is an entry in Brewfile.server"
  local have f
  have="$(entries brew)"
  for f in $REQUIRED; do
    printf '%s\n' "$have" | grep -qxF "$f" || err "Brewfile.server lacks required formula: $f"
  done
  for f in $EXCLUDED; do
    printf '%s\n' "$have" | grep -qxF "$f" && err "Brewfile.server names excluded formula: $f"
  done
  ok "Brewfile.server: $(printf '%s\n' "$have" | grep -c .) formulae checked"

  # The wrapper must reject an unknown profile before it runs anything. A
  # throwaway HOME, so a wrapper that wrongly proceeds can't touch the real one
  # (it would only dry-run, but there is no reason to point it at real files).
  local out rc fake_home
  fake_home="$(mktemp -d)"
  out="$(cd "$REPO" && HOME="$fake_home" DOTFILES_PROFILE=bogus ./install --dry-run 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "DOTFILES_PROFILE"; then
    ok "unknown DOTFILES_PROFILE rejected (exit $rc)"
  else
    err "DOTFILES_PROFILE=bogus was not rejected (exit $rc): $out"
  fi
  if printf '%s' "$out" | grep -q 'Would '; then
    err "DOTFILES_PROFILE=bogus reached Dotbot before failing"
  fi
  # server is a macOS profile; elsewhere it must fail just as fast.
  if [ "$(uname)" != "Darwin" ]; then
    out="$(cd "$REPO" && HOME="$fake_home" DOTFILES_PROFILE=server ./install --dry-run 2>&1)"; rc=$?
    if [ "$rc" -ne 0 ] && ! printf '%s' "$out" | grep -q 'Would '; then
      ok "DOTFILES_PROFILE=server rejected on $(uname) (exit $rc)"
    else
      err "DOTFILES_PROFILE=server ran on $(uname) (exit $rc)"
    fi
  fi
  rm -rf "$fake_home"
}

# --- simulated hal home -------------------------------------------------------
# What is on hal before the first install (work order "Facts about the target"),
# reduced to what the install could plausibly touch. The OrbStack and LM Studio
# binaries are stubs; init.zsh does what OrbStack's does (puts ~/.orbstack/bin
# on PATH).
# ~/.zshenv is seeded too but left out here: the install replaces it on
# purpose, and `post` checks the backup instead.
SEEDED=".zprofile .zshrc .ssh/config Library/LaunchAgents/dev.hal.test.plist
bin/lms-up.sh bin/container-watchdog.sh .lmstudio/bin/lms .orbstack/shell/init.zsh
.orbstack/bin/docker"

# shellcheck disable=SC2016  # the seeded files are written with literal $VARS
cmd_seed() {
  : "${SEED_STATE:?set SEED_STATE to a directory outside \$HOME}"
  mkdir -p "$SEED_STATE" "$HOME"/{.ssh,Library/LaunchAgents,bin,.lmstudio/bin,.orbstack/shell,.orbstack/bin}
  # The two rc files hal has today. With ZDOTDIR set zsh stops reading them;
  # the install must neither edit nor delete them.
  printf '%s\n' 'eval "$(/opt/homebrew/bin/brew shellenv)"' \
    '' '# Added by OrbStack: command-line tools and integration' \
    'source ~/.orbstack/shell/init.zsh 2>/dev/null || :' > "$HOME/.zprofile"
  printf '%s\n' '' '# Added by LM Studio CLI (lms)' "export PATH=\"\$PATH:$HOME/.lmstudio/bin\"" \
    '# End of LM Studio CLI section' > "$HOME/.zshrc"
  # hal has no ~/.zshenv; seeding one exercises the server backup path.
  printf '%s\n' '# pre-existing zshenv (simulated)' > "$HOME/.zshenv"
  printf '%s\n' 'Include ~/.orbstack/ssh/config' > "$HOME/.ssh/config"
  printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' '<plist version="1.0"><dict/></plist>' \
    > "$HOME/Library/LaunchAgents/dev.hal.test.plist"
  printf '%s\n' '#!/bin/sh' 'exit 0' > "$HOME/bin/lms-up.sh"
  printf '%s\n' '#!/bin/sh' 'exit 0' > "$HOME/bin/container-watchdog.sh"
  printf '%s\n' '#!/bin/sh' 'echo lms-stub' > "$HOME/.lmstudio/bin/lms"
  printf '%s\n' '#!/bin/sh' 'echo docker-stub' > "$HOME/.orbstack/bin/docker"
  chmod +x "$HOME"/bin/*.sh "$HOME/.lmstudio/bin/lms" "$HOME/.orbstack/bin/docker"
  printf '%s\n' '# OrbStack shell integration (simulated)' \
    'export PATH="$HOME/.orbstack/bin:$PATH"' > "$HOME/.orbstack/shell/init.zsh"
  # Dangling symlinks that must survive: one pointing outside the repo (the
  # vault links copied from the VPS) and one pointing INTO the repo, which
  # Dotbot's clean would delete if it ran.
  ln -sfn /home/node/obsidian/hermes/personal "$HOME/personal"
  ln -sfn "$REPO/no-such-file-server-profile-check" "$HOME/stale-repo-link"

  # shellcheck disable=SC2086  # SEEDED is a word list on purpose
  ( cd "$HOME" && shasum -a 256 $SEEDED ) > "$SEED_STATE/seed.sha256"
  if command -v brew >/dev/null 2>&1; then
    brew list --cask -1 2>/dev/null | sort > "$SEED_STATE/casks.before"
  else
    : > "$SEED_STATE/casks.before"
  fi
  # chsh shim: records any call. The apply step puts SEED_STATE/shim first on
  # PATH with CI=false, so a chsh step gated only on CI would reach it.
  mkdir -p "$SEED_STATE/shim"
  printf '%s\n' '#!/bin/sh' "echo \"chsh \$*\" >> \"$SEED_STATE/chsh.called\"" 'exit 1' \
    > "$SEED_STATE/shim/chsh"
  chmod +x "$SEED_STATE/shim/chsh"
  ok "seeded simulated hal home at $HOME"
}

link_target() { readlink "$1" 2>/dev/null || echo "(not a symlink)"; }

cmd_post() {
  : "${SEED_STATE:?set SEED_STATE to the directory the seed step used}"
  local brew_prefix=/opt/homebrew

  # Preserved: every seeded file byte-identical, the dangling links untouched.
  if ( cd "$HOME" && shasum -a 256 -c "$SEED_STATE/seed.sha256" >/dev/null ); then
    ok "seeded files unchanged ($(wc -l < "$SEED_STATE/seed.sha256" | tr -d ' ') files)"
  else
    ( cd "$HOME" && shasum -a 256 -c "$SEED_STATE/seed.sha256" ) || true
    err "a pre-existing file was changed or removed"
  fi
  expect "dangling ~/personal kept" "/home/node/obsidian/hermes/personal" "$(link_target "$HOME/personal")"
  expect "dangling in-repo link kept (no clean on server)" \
    "$REPO/no-such-file-server-profile-check" "$(link_target "$HOME/stale-repo-link")"
  # ~/.zshenv is replaced (ZDOTDIR); the old one must be backed up verbatim.
  expect "zshenv backup" "# pre-existing zshenv (simulated)" "$(cat "$HOME/.zshenv.pre-dotfiles" 2>/dev/null)"
  expect "zshenv" "export ZDOTDIR=$HOME/.config/zsh" "$(head -1 "$HOME/.zshenv")"

  # Skipped steps left nothing behind.
  if [ -e "$SEED_STATE/chsh.called" ]; then err "chsh was called: $(cat "$SEED_STATE/chsh.called")"; else ok "chsh not called"; fi
  local p
  for p in .config/nvim .config/nvm .local/bin/uv .local/bin/uvx .local/bin/claude \
           .local/bin/claude-code .claude/settings.json .claude/CLAUDE.md \
           .claude/statusline-command.sh .claude/hooks \
           "Library/Application Support/iTerm2/DynamicProfiles/dotfiles.json"; do
    if [ -e "$HOME/$p" ] || [ -L "$HOME/$p" ]; then err "server install created ~/$p"; else ok "absent: ~/$p"; fi
  done
  if git -C "$REPO" diff --quiet -- nvim/lazy-lock.json; then ok "nvim/lazy-lock.json untouched"
  else err "nvim/lazy-lock.json was modified"; fi

  # Server links.
  expect "tmux local.conf link" "$REPO/tmux/local.server.conf" "$(link_target "$HOME/.config/tmux/local.conf")"
  expect "zprofile link" "$REPO/zsh/zprofile.server" "$(link_target "$HOME/.config/zsh/.zprofile")"
  # The OMZ installer targets zdot="${ZDOTDIR:-$HOME}" and writes its template
  # .zshrc into $ZDOTDIR when its step runs under zsh (VIL-280); the helper
  # removes a template it created, and the Dotbot link owns the path. A
  # regular file here means the link step failed or was skipped.
  expect "zshrc link" "$REPO/zsh/zshrc" "$(link_target "$HOME/.config/zsh/.zshrc")"
  expect "git platform overlay link" "$REPO/git/gitconfig.server" "$(link_target "$HOME/.config/git/gitconfig.platform")"
  expect "codex AGENTS.md link" "$REPO/codex/AGENTS.md" "$(link_target "$HOME/.codex/AGENTS.md")"

  # Packages: everything in Brewfile.server present, and no cask added.
  if brew bundle check --no-upgrade --file="$BREWFILE" >/dev/null 2>&1; then ok "brew bundle check: Brewfile.server satisfied"
  else brew bundle check --no-upgrade --verbose --file="$BREWFILE" || true; err "Brewfile.server not satisfied"; fi
  local added
  added="$(comm -13 "$SEED_STATE/casks.before" <(brew list --cask -1 2>/dev/null | sort))"
  if [ -z "$added" ]; then ok "no cask installed"; else err "casks installed by the server install: $added"; fi

  # Git (helpers git actually runs, pager) is asserted by post-apply R8.

  # rc chain: what ~/.zprofile and ~/.zshrc used to provide still resolves,
  # in an interactive login shell (ssh) and a non-interactive one (zsh -lc).
  local mode out
  for mode in -lic -lc; do
    out="$(zsh "$mode" 'for c in brew lms docker node gh; do print -r -- "$c=$(whence -p $c)"; done; print -r -- "PATH=$PATH"' 2>/dev/null)"
    echo "--- zsh $mode:"; printf '%s\n' "$out"
    expect "zsh $mode brew" "brew=$brew_prefix/bin/brew" "$(printf '%s\n' "$out" | grep '^brew=')"
    expect "zsh $mode lms" "lms=$HOME/.lmstudio/bin/lms" "$(printf '%s\n' "$out" | grep '^lms=')"
    expect "zsh $mode docker" "docker=$HOME/.orbstack/bin/docker" "$(printf '%s\n' "$out" | grep '^docker=')"
    expect "zsh $mode node" "node=$brew_prefix/bin/node" "$(printf '%s\n' "$out" | grep '^node=')"
    expect "zsh $mode gh" "gh=$brew_prefix/bin/gh" "$(printf '%s\n' "$out" | grep '^gh=')"
    # user scope still beats Homebrew (the order zsh/zshenv sets up).
    local path_line lb hb
    path_line="$(printf '%s\n' "$out" | sed -n 's/^PATH=//p')"
    lb="$(printf '%s\n' "$path_line" | tr ':' '\n' | grep -nxF "$HOME/.local/bin" | head -1 | cut -d: -f1)"
    hb="$(printf '%s\n' "$path_line" | tr ':' '\n' | grep -nxF "$brew_prefix/bin" | head -1 | cut -d: -f1)"
    if [ -n "$lb" ] && [ -n "$hb" ] && [ "$lb" -lt "$hb" ]; then ok "zsh $mode: ~/.local/bin before $brew_prefix/bin"
    else err "zsh $mode: ~/.local/bin (pos ${lb:-none}) not before $brew_prefix/bin (pos ${hb:-none})"; fi
  done
}

# ~/Library/LaunchAgents holds hal's live services. The install must add
# nothing there; the likely offender is tmux-continuum's boot option, which
# writes Tmux.Start.plist whenever a tmux server loads the plugin with
# @continuum-boot on (tmux/tmux.general.conf sets it; the server's
# local.conf turns it off).
# shellcheck disable=SC2030,SC2031  # each private tmux server lives in its own subshell on purpose
cmd_launchagents() {
  local la="$HOME/Library/LaunchAgents" plist cont d
  plist="$la/Tmux.Start.plist"
  cont="$HOME/.config/tmux/plugins/tmux-continuum/scripts/handle_tmux_automatic_start.sh"
  # First, the install's own result, before anything below can change it (the
  # control ends by running continuum's boot-off handler, which deletes the
  # plist).
  expect "LaunchAgents after install" "dev.hal.test.plist" "$(ls -1 "$la" 2>/dev/null)"
  if [ ! -x "$cont" ]; then
    err "tmux-continuum not installed at $cont; the boot check can't run"
    return
  fi
  # Control: prove this check can see the plist. A private server with no
  # config, boot forced on, continuum's own handler: the plist must appear,
  # then go again with boot off.
  d="$(mktemp -d /tmp/dotfiles-tmuxchk.XXXXXX)"  # short: 104-byte socket path cap on macOS
  if ! ( unset TMUX; export TMUX_TMPDIR="$d"; ctl=0
    tmux -f /dev/null new-session -d -s control
    tmux set -g @continuum-boot on; "$cont"
    if [ -f "$plist" ]; then echo "ok: control: boot on writes $plist"; else ctl=1; fi
    tmux set -g @continuum-boot off; "$cont"
    tmux kill-server
    exit "$ctl" ) 2>&1; then
    err "control: boot on wrote no $plist, so the check below proves nothing"
  fi
  rm -rf "$d"
  [ -e "$plist" ] && err "control: boot off left $plist behind"
  # Real: a private server with the installed config (local.conf, then TPM).
  d="$(mktemp -d /tmp/dotfiles-tmuxchk.XXXXXX)"  # short: 104-byte socket path cap on macOS
  # Absence of the plist only counts if that server really started with the
  # installed config (boot off, from local.conf) and TPM loaded the plugins
  # (tmux-resurrect's bindings exist; continuum loads in the same TPM pass).
  local real
  real="$( unset TMUX; export TMUX_TMPDIR="$d"
    if ! tmux new-session -d -s check; then echo "START_FAILED"; exit 0; fi
    sleep 3
    printf 'boot=%s plugins=%s\n' "$(tmux show -gqv @continuum-boot)" \
      "$(tmux list-keys 2>/dev/null | grep -q tmux-resurrect && echo loaded || echo missing)"
    tmux kill-server )"
  rm -rf "$d"
  echo "installed-config tmux server: $real"
  case "$real" in
    START_FAILED*) err "a tmux server with the installed config failed to start; the LaunchAgent check proves nothing" ;;
    "boot=off plugins=loaded") ok "installed config: plugins loaded with @continuum-boot off" ;;
    *) err "installed config: expected plugins loaded with boot off, got [$real]" ;;
  esac
  if [ -e "$plist" ]; then err "a tmux server with the installed config wrote $plist"; else ok "tmux with the installed config wrote no LaunchAgent"; fi
}

cmd_snapshot() {
  local out="${1:?usage: snapshot FILE}"
  {
    # Paths, types, link targets and content hashes. Library and .cache hold
    # brew/zsh/pre-commit logs and caches that every run appends to.
    ( cd "$HOME" && find . \( -path ./Library -o -path ./.cache \) -prune -o -print | LC_ALL=C sort \
      | while IFS= read -r f; do
          if [ -L "$f" ]; then echo "L $f -> $(readlink "$f")"
          elif [ -f "$f" ]; then echo "F $f $(shasum -a 256 < "$f" | cut -c1-16)"
          else echo "D $f"; fi
        done )
    echo "## brew formulae"; brew list --formula --versions 2>/dev/null | LC_ALL=C sort
    echo "## brew casks"; brew list --cask --versions 2>/dev/null | LC_ALL=C sort
  } > "$out"
  ok "snapshot: $(wc -l < "$out" | tr -d ' ') lines -> $out"
}

case "${1:-}" in
  static)   cmd_static ;;
  seed)     cmd_seed ;;
  post)     cmd_post; cmd_launchagents ;;
  launchagents) cmd_launchagents ;;
  snapshot) shift; cmd_snapshot "$@" ;;
  *) echo "usage: $0 static|seed|post|launchagents|snapshot FILE" >&2; exit 2 ;;
esac
exit "$fail"
