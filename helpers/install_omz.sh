#!/usr/bin/env bash
set -euo pipefail

if [ "${DOTFILES_DRY_RUN:-0}" = "1" ]; then
  echo "[dry-run] would install Oh My Zsh + plugins"
  exit 0
fi

# Define the Oh My Zsh installation directory
OMZ_DIR="$HOME/.oh-my-zsh"

# Pin the Oh My Zsh installer to a specific commit for reproducible installs.
# This pins the installer LOGIC only — it still clones ohmyzsh HEAD. Bump when
# intentionally refreshing installer behavior.
OMZ_INSTALL_REF="677a4592b18c08ddea737f8aca70bac0e9fc9313"

# Returns 0 iff $1 is a complete git checkout: a .git dir, a resolvable HEAD,
# and no tracked file missing from the worktree. `git clone` writes .git/HEAD
# *before* checking out the payload, so a hard-interrupted clone (SIGKILL,
# power loss) or a manually-created dir can look "present" while the payload is
# absent or partial — treating that as installed prints success over a broken
# shell. Optional $2 is a required top-level file (e.g. oh-my-zsh.sh) that must
# also be present. `--diff-filter=D` targets only *missing* tracked files, so a
# user's local edits to a checked-out file never trigger a needless re-clone.
checkout_complete() {
  local dir="$1" required="${2:-}"
  [ -d "$dir/.git" ] || return 1
  [ -z "$required" ] || [ -e "$dir/$required" ] || return 1
  git -C "$dir" rev-parse --verify --quiet HEAD >/dev/null 2>&1 || return 1
  local missing
  missing="$(git -C "$dir" diff --name-only --diff-filter=D HEAD 2>/dev/null)" || return 1
  [ -z "$missing" ]
}

# Echo a quarantine path for $1 that does not already exist. Quarantine dirs are
# kept across runs and $$ (PID) is reusable, so "${base}.broken.$$" alone can
# collide with a leftover dir — then `mv "$base" "$dest"` would *nest* the
# checkout inside it and a later restore would rebuild it at the wrong depth.
# Returning a fresh path guarantees `mv` renames rather than nests.
make_quarantine() {
  local base="$1" n=0 candidate="${1}.broken.$$"
  # -e misses dangling symlinks; -L catches them, so a candidate occupied by a
  # broken symlink is skipped too.
  while [ -e "$candidate" ] || [ -L "$candidate" ]; do
    n=$((n + 1))
    candidate="${base}.broken.$$.$n"
  done
  printf '%s' "$candidate"
}

# Crash/interruption safety for the quarantine window. Moving an occupant aside
# and reinstalling is not atomic: an interruption (INT/TERM) or an `rm -rf`
# failure that aborts under `set -e` could exit after the occupant is
# quarantined but before it is restored, leaving the path missing. Track the
# in-flight move and restore it on ANY exit. SIGKILL and power loss are
# uncatchable; those self-heal on the next ./install (a missing path is simply
# reinstalled) with the occupant preserved under its .broken.* name.
_inflight_src=""
_inflight_dst=""
restore_inflight() {
  [ -n "$_inflight_dst" ] || return 0
  # Nothing to restore unless the quarantine still holds the occupant...
  { [ -e "$_inflight_dst" ] || [ -L "$_inflight_dst" ]; } || return 0
  # ...and the original path is genuinely missing. After a successful reinstall
  # or an explicit rollback the path exists (and the quarantine is intentionally
  # kept as a backup), so this is a no-op.
  { [ -e "$_inflight_src" ] || [ -L "$_inflight_src" ]; } && return 0
  mv "$_inflight_dst" "$_inflight_src" 2>/dev/null || true
}
# EXIT catches normal/`set -e`/explicit-exit paths; INT/TERM convert the signal
# to an exit so the single EXIT handler does the restore (idempotent).
trap restore_inflight EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Install Oh My Zsh into $OMZ_DIR. Returns 0 only when the resulting checkout is
# complete. ZSH="$OMZ_DIR" forces the install target so it can never diverge to
# a $ZDOTDIR-derived path (the installer defaults to $ZDOTDIR/ohmyzsh when
# ZDOTDIR is set and != HOME); this keeps the core and the plugins that live
# beneath it in the same place.
install_omz_core() {
  echo "Installing Oh My Zsh..."
  local omz_installer
  # Download the installer to a variable first so a curl failure is caught
  # (a failed `$(curl …)` piped straight into `sh -c` would silently no-op).
  omz_installer="$(curl -fsSL "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/${OMZ_INSTALL_REF}/tools/install.sh")" || {
    echo "Failed to download the Oh My Zsh installer"
    return 1
  }
  # RUNZSH=no    — don't drop into a zsh subshell after install
  # CHSH=no      — don't change the login shell (Dotbot/install pipeline owns that)
  # KEEP_ZSHRC=yes — never touch our managed ~/.zshrc
  ZSH="$OMZ_DIR" RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$omz_installer" || {
    echo "Oh My Zsh installation failed"
    return 1
  }
  checkout_complete "$OMZ_DIR" "oh-my-zsh.sh"
}

# Reinstall Oh My Zsh unless it's already a complete checkout. Anything else
# occupying the path — a broken/partial dir, a stray regular file, a dangling
# symlink — is *moved aside*, never deleted: plugins live beneath it and a
# misjudgment must not destroy user data. Clearing the path first also means the
# failure-cleanup below can only ever remove what the install itself created.
quarantine=""
if ! checkout_complete "$OMZ_DIR" "oh-my-zsh.sh"; then
  if [ -e "$OMZ_DIR" ] || [ -L "$OMZ_DIR" ]; then
    quarantine="$(make_quarantine "$OMZ_DIR")"
    echo "Existing $OMZ_DIR is not a usable Oh My Zsh checkout; moving it aside to $quarantine and reinstalling..."
    _inflight_src="$OMZ_DIR"; _inflight_dst="$quarantine"
    mv "$OMZ_DIR" "$quarantine"
  fi
  if ! install_omz_core; then
    echo "Oh My Zsh install did not produce a complete checkout at $OMZ_DIR"
    # The path was cleared above, so anything at $OMZ_DIR now was created by the
    # install we just ran — removing it can't touch user data, and clearing it
    # unblocks the rollback below.
    rm -rf "$OMZ_DIR"
    # Roll back: a failed repair must not strand the machine without its
    # previous core. Restore whatever we quarantined — dir, file, or symlink
    # (hence -e || -L, not -d).
    if [ -n "$quarantine" ] && { [ -e "$quarantine" ] || [ -L "$quarantine" ]; }; then
      echo "Restoring the previous checkout from $quarantine"
      mv "$quarantine" "$OMZ_DIR"
    fi
    exit 1
  fi
fi

# Plugins to install, as "name|url" entries. Bash 3.2 (macOS /bin/bash) has no
# associative arrays, so a plain indexed array of delimited strings is used —
# the previous `declare -A` silently failed under bash 3.2 and installed 0 plugins.
PLUGINS=(
  "zsh-256color|https://github.com/chrissicool/zsh-256color"
  "zsh-autosuggestions|https://github.com/zsh-users/zsh-autosuggestions"
  "zsh-history-substring-search|https://github.com/zsh-users/zsh-history-substring-search"
  "zsh-syntax-highlighting|https://github.com/zsh-users/zsh-syntax-highlighting"
)

for entry in "${PLUGINS[@]}"; do
  plugin="${entry%%|*}"
  url="${entry#*|}"
  PLUGIN_DIR="$OMZ_DIR/custom/plugins/$plugin"
  pq=""   # exact quarantine path for THIS plugin, if we move one aside
  if checkout_complete "$PLUGIN_DIR"; then
    echo "$plugin already installed, skipping."
    continue
  fi
  # Anything occupying the path that is NOT a complete checkout — a partial dir,
  # a stray regular file, a dangling symlink, or a checkout with local edits —
  # is moved aside, never deleted (data safety). Clearing the path first also
  # guarantees the failure-cleanup below can only ever remove the clone WE make.
  if [ -e "$PLUGIN_DIR" ] || [ -L "$PLUGIN_DIR" ]; then
    pq="$(make_quarantine "$PLUGIN_DIR")"
    echo "$plugin path is not a complete checkout; moving it aside to $pq and recloning..."
    _inflight_src="$PLUGIN_DIR"; _inflight_dst="$pq"
    mv "$PLUGIN_DIR" "$pq"
  fi
  echo "Installing $plugin..."
  # Fail if the clone errors OR exits 0 with an incomplete checkout.
  if ! git clone "$url" "$PLUGIN_DIR" || ! checkout_complete "$PLUGIN_DIR"; then
    echo "$plugin installation did not produce a complete checkout"
    # The path was cleared above, so this only removes the clone we just made.
    rm -rf "$PLUGIN_DIR"
    # Roll back: if we quarantined a previous occupant (dir, file, or symlink),
    # restore it so a transient failure doesn't leave the path missing when we
    # hold an exact backup.
    if [ -n "$pq" ] && { [ -e "$pq" ] || [ -L "$pq" ]; }; then
      echo "Restoring the previous $plugin checkout from $pq"
      mv "$pq" "$PLUGIN_DIR"
    fi
    exit 1
  fi
done

echo "All installations completed successfully."
