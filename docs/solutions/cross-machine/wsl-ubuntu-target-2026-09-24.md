---
title: "WSL Ubuntu as a Linux target — what a bare distro exposes that the CI image hides"
date: 2026-09-24
category: cross-machine
tags:
  - wsl
  - linux
  - dotbot
  - zsh
  - chsh
  - ci-parity
  - windows
  - cross-machine
severity: Medium
component: "dotbot-conf/base.yaml, dotbot-conf/linux.yaml, helpers/install_omz.sh"
problem_type: "cross-machine install failure on a fresh host"
module: "install pipeline (dotbot)"
related_solutions:
  - "docs/solutions/cross-machine/windows-target-gotchas-2026-09-24.md: the Windows side of the same PC"
  - "docs/solutions/cross-machine/vps-dotfiles-target.md: the previous (retired) Linux target"
  - "docs/solutions/best-practices/verify-the-instrument-before-trusting-a-negative.md: the same lesson as the stale-clone re-run below"
---

# WSL Ubuntu as a Linux target — what a bare distro exposes that the CI image hides

On 2026-09-24 the Linux layer was brought up in WSL 2 (Ubuntu 24.04.5) on the
gaming PC (VIL-148). CI runs that layer on every PR, in a container built from
`ci/Dockerfile`. That image pre-installs `zsh`, `sudo`, `python3`, `git` and
`curl`, and runs non-interactively as root. A real distro differs on both
counts, and both differences broke the first install.

## 1. Oh My Zsh needs zsh, and it runs before the package install

`base.yaml` runs `install_omz.sh` before `install_packages.sh`, and
`install_packages.sh` is what installs zsh on Linux. The pinned Oh My Zsh
installer (`OMZ_INSTALL_REF`) checks for zsh first:

```text
Zsh is not installed. Please install zsh first.
```

and exits 1. On a bare Ubuntu the first `./install` therefore failed the OMZ
step, and only a second run completed it. CI never showed this because its
image already has zsh.

**Fix:** the Linux-only locale step in `base.yaml`, which already
`apt-get install`s before OMZ runs, now installs `locales zsh`.

## 2. Dotbot gives shell steps `/dev/null` as stdin, so `chsh` can't prompt

The new `chsh` step in `linux.yaml` (modeled on `darwin.yaml`'s) failed
instantly:

```text
Password: chsh: PAM: Authentication failure
```

The user never got to type anything. Tell-tale sign: `Password:` and the
failure are on the **same line**. A mistyped password would show the user's
Enter first.

Dotbot v1.24.1's `util/common.py` sets `stdin = None if enable_stdin else
devnull_r`, and `enable_stdin` defaults to false for every shell step. Linux
`chsh` (util-linux, via PAM) reads the password from stdin, so it read EOF.
`sudo` in the same run prompted normally, because it opens `/dev/tty` itself.

**Fix:** set `stdin: true` on that step. Any future Dotbot step that prompts
needs the same flag.

## 3. Re-running a fix: check the clone is actually on it first

The second attempt failed identically, and it wasn't the fix's fault. The WSL
clone was still on the pre-fix commit (`stdin: true` absent, and `git status`
reporting "up to date" against a remote-tracking ref that was never fetched).
One `git pull` from the agent side brought in the fix, and the third run
succeeded. Before judging a fix by a re-run, confirm `git log --oneline -1`
shows the fix commit.

## 4. Smaller findings

- **A Windows Terminal "Ubuntu" profile doesn't mean a distro exists.** The
  PC's Terminal defaulted to an "Ubuntu" profile while `wsl -l -v` showed *no
  installed distributions*, with no Ubuntu app package, no `Lxss` registry
  entry and no `ext4.vhdx`. Terminal keeps profiles for distros that have been
  removed. Check `wsl -l -v`.
- **Use a separate clone inside the WSL filesystem.** Don't use the Windows
  checkout through `/mnt/c`: it's slow, and Windows line-ending and permission
  behavior leaks in. The two clones share nothing but the remote.
- **Picked the wrong username?** On a fresh distro,
  `wsl --unregister Ubuntu-24.04` plus a reinstall is simpler than renaming the
  user (home directory, groups, and the `[user] default=` line in
  `/etc/wsl.conf`). Check `/home/*` is empty first.
- **Driving WSL from an agent on Windows:**
  - Windows PowerShell 5.1 strips inner double quotes from arguments to
    `wsl.exe`, so write the commands to a bash script (with LF endings) under
    the scratchpad and run `wsl -d <distro> -u <user> -- bash /mnt/c/…/script.sh`.
    From Git Bash, set `MSYS_NO_PATHCONV=1` so the `/mnt/c/...` path isn't
    rewritten.
  - `wsl.exe`'s own output is UTF-16; pipe it through `tr -d '\000'`.
  - `-u root` works before the user account exists (it skips first-launch
    setup), which makes it useful for read-only inspection.
- **Expected `dot doctor` warnings on WSL:** no Homebrew; macOS-only aliases
  pointing at missing binaries; no `.claude/settings.local.json`; and `python3`
  "shadowed" by Ubuntu's merged-usr `/bin` → `/usr/bin` link, which is the same
  file. Result on 2026-09-24: 0 failures, 4 warnings, `dot bench` median 186 ms.
- **Neovim:** apt ships 0.9.5, and `install_nvim.sh` skips cleanly because the
  config needs 0.11+ (VIL-152).
- **git credential helpers:** WSL inherits `git/gitconfig`'s macOS helpers.
  Public clones and pulls work; pushing from WSL needs VIL-146.
