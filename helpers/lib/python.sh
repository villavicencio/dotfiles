# shellcheck shell=bash
# shellcheck disable=SC2034  # PYTHON is read by the scripts that source this file
#
# Sourced by helpers/install_claude_settings.sh and helpers/report_drift.sh:
# Windows detection and the Python they hand the Claude settings work to.

IS_WINDOWS=0
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) IS_WINDOWS=1 ;; esac

# A native Windows python can't open a Git Bash path (/c/Users/...); hand it
# the C:\... form. Everywhere else the path passes through unchanged.
native_path() {
  if [ "$IS_WINDOWS" -eq 1 ] && command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$1"
  else
    printf '%s\n' "$1"
  fi
}

# Sets PYTHON to a command that runs Python, or returns 1. Callers resolve it
# lazily, only once they need Python, so a run that needs none never probes and
# never lets uv download an interpreter. PYTHON is an array (the uv command is
# several words). The return status is the test, never ${#PYTHON[@]}: Bash 3.2
# under `set -u` treats an empty array as unbound. Expand PYTHON only after
# this succeeds.
PYTHON=()
resolve_python() {
  local _py
  # A python3 that actually runs. On Windows `python3` is often the Microsoft
  # Store placeholder: `command -v` finds it, but it exits non-zero with
  # "Python was not found". Probe by running it, and fall back to `python`
  # (what the python.org installer registers).
  for _py in python3 python; do
    if "$_py" -c 'import sys' >/dev/null 2>&1; then
      PYTHON=("$_py"); return 0
    fi
  done
  # No working Python on PATH — the state of a Windows PC set up only by
  # install.ps1, which installs uv but no Python. Run one through uv: it uses
  # an interpreter it can discover (managed, PATH, or the Windows registry; it
  # skips the Store placeholder) or, if there is none, downloads a managed one
  # into uv's own store. --no-project stops uv treating this repo as a
  # project to create and sync.
  if command -v uv >/dev/null 2>&1 \
     && uv run --no-project --quiet python -c 'import sys' >/dev/null 2>&1; then
    PYTHON=(uv run --no-project --quiet python); return 0
  fi
  return 1
}
