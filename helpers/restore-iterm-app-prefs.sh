#!/usr/bin/env bash
#
# restore-iterm-app-prefs.sh — restore the app-level iTerm2 key/pointer bindings
# a Dynamic Profile cannot carry (GlobalKeyMap, PointerActions), and complete the
# one-time migration OFF iTerm2's custom-preferences-folder mode.
#
# Background. These dotfiles used to point iTerm2 at the repo as its preferences
# folder (LoadPrefsFromCustomFolder=1, PrefsCustomFolder=<repo>/iterm). In that
# mode iTerm2 rewrites its ENTIRE prefs plist there on every quit — window
# arrangements, working directories, `/Users/<name>` paths, the machine hostname
# — which is how PII leaked into git. The fix is to migrate to a curated,
# PII-free Dynamic Profile (iterm/profile-dynamic.json, auto-linked by Dotbot)
# plus this app-level sidecar, and turn custom-folder mode OFF so iTerm2 goes
# back to its per-machine standard domain.
#
# While custom-folder mode is still ON, writing the standard `defaults` domain is
# pointless: iTerm2 reloads everything from the custom folder on relaunch and
# supersedes the write. So this script detects that state and refuses to report a
# false success — pass --migrate (with iTerm2 QUIT) to complete the migration.
#
# This is a MANUAL step, never wired into `./install`: it mutates another app's
# live preferences and requires iTerm2 to be quit first (iTerm2 overwrites its
# defaults on quit, so any write while it is running is lost).
#
# Usage:
#   helpers/restore-iterm-app-prefs.sh            # standard mode: restore keymaps
#   helpers/restore-iterm-app-prefs.sh --migrate  # one-time: leave custom-folder mode
#
# macOS only. Honors DOTFILES_DRY_RUN=1.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIDECAR="$REPO_ROOT/iterm/iterm2-app-keymap.json"
DOMAIN="com.googlecode.iterm2"
DRY="${DOTFILES_DRY_RUN:-0}"

MIGRATE=0
if [ "${1:-}" = "--migrate" ]; then
  MIGRATE=1
elif [ -n "${1:-}" ]; then
  echo "ERROR: unknown argument '$1' (expected --migrate or none)" >&2
  exit 64
fi

if [ "$(uname)" != "Darwin" ]; then
  echo "restore-iterm-app-prefs.sh: macOS only — nothing to do." >&2
  exit 0
fi
if [ ! -f "$SIDECAR" ]; then
  echo "ERROR: $SIDECAR not found" >&2
  exit 1
fi
if pgrep -xq iTerm2; then
  echo "ERROR: iTerm2 is running — it overwrites its prefs on quit, so any" >&2
  echo "       change here would be lost. Quit iTerm2, re-run, then relaunch." >&2
  exit 1
fi

# Write GlobalKeyMap + PointerActions from the sidecar into the standard domain.
# Each JSON dict becomes a real plist and is handed to `defaults write`, which
# accepts a plist-format value (verified round-trip: nested dicts survive).
apply_keymaps() {
  local key plist
  for key in GlobalKeyMap PointerActions; do
    plist="$(python3 - "$SIDECAR" "$key" <<'PY'
import json, plistlib, sys
d = json.load(open(sys.argv[1]))
sys.stdout.buffer.write(plistlib.dumps(d.get(sys.argv[2], {})))
PY
)"
    if [ "$DRY" = "1" ]; then
      echo "[dry-run] would: defaults write $DOMAIN $key <$key from sidecar>"
    else
      defaults write "$DOMAIN" "$key" "$plist"
      echo "wrote $DOMAIN $key"
    fi
  done
}

# Refuse if $1 is, or lives inside, the repo. Uses filesystem IDENTITY
# (device+inode via os.path.samefile), not string comparison: this checkout is on
# a case-insensitive macOS filesystem where `.../DOTFILES` and `.../dotfiles` are
# the same directory but differ as strings. Walks from the destination's realpath
# up to root and compares each existing ancestor to the repo by identity, so
# case aliases, symlinks, and `..` can't smuggle the backup into the checkout.
# Returns 0 = safe (outside), 3 = contained (equal to or inside repo).
assert_dir_outside_repo() {
  python3 - "$REPO_ROOT" "$1" <<'PY'
import os, sys
repo = os.path.realpath(sys.argv[1])
p = os.path.realpath(sys.argv[2])
while True:
    if os.path.exists(p):
        try:
            if os.path.samefile(p, repo):
                sys.exit(3)   # destination is, or is inside, the repo
        except OSError:
            pass
    parent = os.path.dirname(p)
    if parent == p:
        break
    p = parent
sys.exit(0)
PY
}

# Back up $src into directory $bak_dir under basename $name, writing through the
# validated directory FILE DESCRIPTOR (openat semantics) so neither the final
# component nor any parent can be swapped for a symlink-into-the-repo between
# validation and creation. `cp(1)` would follow such a symlink; this won't:
#   - open $bak_dir with O_DIRECTORY|O_NOFOLLOW (refuses a symlinked bak_dir),
#   - re-derive the fd's real path (F_GETPATH) and assert by identity it is not
#     inside the repo — binds the earlier path check to the actual open dir,
#   - lstat the basename RELATIVE to that fd; an existing dest is kept only if it
#     is a regular, non-symlink file that parses as a COMPLETE plist,
#   - otherwise write to a temp file (0600), fsync, and publish atomically via
#     link() (no overwrite); a partial/interrupted copy is never seen as valid.
# Args: $1 src  $2 bak_dir  $3 basename  $4 repo_root. Returns 0 ok/keep, 1 unsafe.
safe_backup() {
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import errno, fcntl, os, plistlib, shutil, stat, sys
src, bak_dir, name, repo = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
F_GETPATH = 50  # <sys/fcntl.h> on macOS

def inside_repo(path):
    repo_real = os.path.realpath(repo)
    p = os.path.realpath(path)
    while True:
        if os.path.exists(p):
            try:
                if os.path.samefile(p, repo_real):
                    return True
            except OSError:
                pass
        parent = os.path.dirname(p)
        if parent == p:
            return False
        p = parent

try:
    dir_fd = os.open(bak_dir, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
except OSError as e:
    if e.errno in (errno.ELOOP, errno.ENOTDIR):
        sys.stderr.write("ERROR: backup dir is a symlink or not a directory — refusing: %s\n" % bak_dir)
        sys.exit(1)
    raise
try:
    real = fcntl.fcntl(dir_fd, F_GETPATH, b"\x00" * 1024).split(b"\x00", 1)[0].decode()
    if inside_repo(real):
        sys.stderr.write("ERROR: backup dir resolves inside the repo — refusing: %s\n" % real)
        sys.exit(1)
    try:
        st = os.lstat(name, dir_fd=dir_fd)
        if stat.S_ISLNK(st.st_mode):
            sys.stderr.write("ERROR: backup path is a symlink — refusing: %s/%s\n" % (real, name))
            sys.exit(1)
        if stat.S_ISREG(st.st_mode):
            # An existing backup is trusted only if it is a COMPLETE plist. A
            # truncated/empty file from an interrupted prior run must not be
            # silently accepted (the user could later delete the real prefs,
            # left with an unusable backup).
            efd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=dir_fd)
            try:
                with os.fdopen(efd, "rb") as ef:
                    plistlib.load(ef)
            except Exception:
                sys.stderr.write("ERROR: existing backup is not a complete plist "
                                 "(truncated/corrupt?) — remove it and re-run: %s/%s\n" % (real, name))
                sys.exit(1)
            print("backup already exists and is a valid plist, keeping it: %s/%s" % (real, name))
            sys.exit(0)
        sys.stderr.write("ERROR: backup path exists and is not a regular file — refusing: %s/%s\n" % (real, name))
        sys.exit(1)
    except FileNotFoundError:
        pass
    # Write to a temp file (relative to the validated dir fd), fsync it, then
    # publish atomically via link() — which fails rather than overwrites if the
    # final name appeared concurrently. On any failure the temp is removed, so a
    # partial file is never observable as "the backup".
    tmp = ".%s.tmp.%d" % (name, os.getpid())
    try:
        os.unlink(tmp, dir_fd=dir_fd)   # clear a stale temp from a crashed run
    except FileNotFoundError:
        pass
    try:
        wfd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=dir_fd)
    except OSError as e:
        if e.errno in (errno.ELOOP, errno.EEXIST):
            sys.stderr.write("ERROR: refusing symlinked/pre-existing temp path (%s): %s/%s\n"
                             % (e.strerror, real, tmp))
            sys.exit(1)
        raise
    try:
        with os.fdopen(wfd, "wb") as out, open(src, "rb") as inp:
            shutil.copyfileobj(inp, out)
            out.flush()
            os.fsync(out.fileno())
        # Validate the COMPLETED copy parses as a plist BEFORE publishing it — a
        # source that was already truncated/corrupt, or mutated mid-copy, must not
        # become the permanent backup. On failure the finally-block removes the
        # temp, so nothing is published and safe_backup returns non-zero (the
        # migration then aborts without disabling custom-folder mode).
        vfd = os.open(tmp, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=dir_fd)
        try:
            with os.fdopen(vfd, "rb") as vf:
                plistlib.load(vf)
        except Exception:
            sys.stderr.write("ERROR: copied backup did not parse as a complete plist "
                             "(corrupt/mutated source?) — not publishing: %s/%s\n" % (real, name))
            sys.exit(1)
        try:
            os.link(tmp, name, src_dir_fd=dir_fd, dst_dir_fd=dir_fd)
        except OSError as e:
            if e.errno == errno.EEXIST:
                sys.stderr.write("ERROR: backup appeared concurrently — not overwriting: %s/%s\n" % (real, name))
                sys.exit(1)
            raise
        os.fsync(dir_fd)   # persist the new directory entry
    finally:
        try:
            os.unlink(tmp, dir_fd=dir_fd)
        except FileNotFoundError:
            pass
    print("backed up custom-folder plist -> %s/%s (0600, openat+O_NOFOLLOW, atomic, outside the repo)" % (real, name))
finally:
    os.close(dir_fd)
PY
}

# Confirm the writes actually landed in the standard domain (best-effort; the
# authoritative check is after an iTerm2 relaunch, which a script can't do).
verify_keymaps() {
  [ "$DRY" = "1" ] && return 0
  local key
  for key in GlobalKeyMap PointerActions; do
    if [ "$(defaults read-type "$DOMAIN" "$key" 2>/dev/null)" != "Type is dictionary" ]; then
      echo "WARN: $DOMAIN $key did not read back as a dictionary" >&2
    fi
  done
}

lpcf="$(defaults read "$DOMAIN" LoadPrefsFromCustomFolder 2>/dev/null || echo 0)"
pcf="$(defaults read "$DOMAIN" PrefsCustomFolder 2>/dev/null || echo '')"

if [ "$lpcf" = "1" ]; then
  if [ "$MIGRATE" != "1" ]; then
    {
      echo "iTerm2 is in custom-preferences-folder mode:"
      echo "  LoadPrefsFromCustomFolder = 1"
      echo "  PrefsCustomFolder         = $pcf"
      echo
      echo "In this mode iTerm2 loads/saves ALL prefs from that folder, so writing"
      echo "the standard defaults domain now would be silently overwritten on the"
      echo "next relaunch. Complete the one-time migration instead (iTerm2 QUIT):"
      echo
      echo "  helpers/restore-iterm-app-prefs.sh --migrate"
      echo
      echo "See iterm/README.md."
    } >&2
    exit 2
  fi

  echo "Migrating off iTerm2 custom-preferences-folder mode…"
  cf_plist="$pcf/com.googlecode.iterm2.plist"
  # Back up the old prefs OUTSIDE the repo. That plist is exactly the PII this
  # migration removes (identity, paths, hostname, session state); a backup inside
  # the repo could be `git add`ed on a machine without a global *.bak ignore. Use
  # a user-owned state dir with restrictive permissions instead.
  #
  # The destination is validated UP FRONT (before any copy): XDG_STATE_HOME must
  # be absolute, and the resolved backup dir must NOT be the repo or live inside
  # it — otherwise a misconfigured XDG_STATE_HOME (e.g. set to the repo root, or a
  # relative/symlinked path) would drop the PII plist back into the checkout.
  state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
  case "$state_home" in
    /*) : ;;
    *) echo "ERROR: XDG_STATE_HOME must be an absolute path (got '$state_home')" >&2; exit 1 ;;
  esac
  bak_dir="$state_home/dotfiles"
  if ! assert_dir_outside_repo "$bak_dir"; then
    echo "ERROR: backup dir '$bak_dir' is, or lives inside, the repo." >&2
    echo "       Refusing — that would risk committing the PII prefs plist." >&2
    echo "       Point XDG_STATE_HOME at an absolute path outside the repo." >&2
    exit 1
  fi
  bak_name="iterm2-prefs.pre-dynamic-profile.plist"
  bak="$bak_dir/$bak_name"
  if [ -f "$cf_plist" ]; then
    if [ "$DRY" = "1" ]; then
      echo "[dry-run] would back up '$cf_plist' -> '$bak' (0600, openat+O_NOFOLLOW, outside the repo)"
    else
      mkdir -p "$bak_dir"
      chmod 700 "$bak_dir" 2>/dev/null || true
      # safe_backup does the authoritative work: it opens $bak_dir with
      # O_DIRECTORY|O_NOFOLLOW, re-asserts by identity that the opened dir is
      # outside the repo, and creates the basename relative to that fd — so no
      # symlink swap of the dir or the file can redirect the PII copy into the repo.
      if ! safe_backup "$cf_plist" "$bak_dir" "$bak_name" "$REPO_ROOT"; then
        exit 1
      fi
    fi
  fi
  apply_keymaps
  if [ "$DRY" = "1" ]; then
    echo "[dry-run] would: defaults write $DOMAIN LoadPrefsFromCustomFolder -bool false"
  else
    defaults write "$DOMAIN" LoadPrefsFromCustomFolder -bool false
    echo "set $DOMAIN LoadPrefsFromCustomFolder = false"
  fi
  verify_keymaps
  echo
  echo "Migration written. Next:"
  echo "  1. Relaunch iTerm2 — it now uses its standard per-machine prefs."
  echo "  2. Preferences > Profiles: select 'Dotfiles' and mark it the default."
  echo "  3. iTerm2 no longer rewrites $pcf — the leftover plist there (if any,"
  echo "     git-ignored) can be deleted manually once you've confirmed the profile."
  [ -f "$bak" ] && echo "  Backup of the old prefs: $bak"
  exit 0
fi

# Standard mode: iTerm2 uses its per-machine domain; restoring keymaps is safe.
apply_keymaps
verify_keymaps
echo "Done. Relaunch iTerm2 to apply."
