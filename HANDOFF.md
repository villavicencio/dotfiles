---
created_at: "2026-11-05T13:04:48-07:00"
branch: "master"
head: "fd512a1"
worktree: "/Users/dvillavicencio/Projects/Personal/dotfiles"
resume_focus: "hand mergewren pilot PRs #131-#134 to the MergeWren session with run evidence; reopen parent tickets (VIL-546/544/550/575) after merges"
---
# HANDOFF — 2026-11-05, midday (PT)

This session picked up the 11-03 handoff and checked the hal pilot runs. It then turned into a cleanup of this Mac, the personal one. A former employer's MDM and security-agent leftovers, carried over by Migration Assistant years ago, had been blocking macOS updates. The cleanup is done. The pilot PRs have not been handed to MergeWren yet.

## What We Built
- **Pilot run state (hal, as `david`, `~/runs/log/runner.log`):**
  - 11-03: `planner-error`.
  - 11-04: all three runs failed, but VIL-546's branch was pushed later as mergewren#131.
  - 11-05: all three runs passed and opened mergewren#132 (VIL-544), #133 (VIL-575) and #134 (VIL-550).
  - `~/runs/queue` was empty at about 11:30 PT.
- **Mac cleanup.** Every change is recorded in Claude memory `mac_hosts_apple_blocks.md`. Removed:
  - the `/etc/hosts` blocks on Apple's enrollment hosts and `gdmf`; Apple's answer afterwards was "Client is not DEP enabled"
  - JumpCloud's sudo rules, its admin service account and its `/opt/jc*` files
  - Jamf, Tanium and CrowdStrike leftovers
  - the old company's certificate authority
  - the Remote Management "all users, all privileges" preset
  - ghost names in the admin group
  - the `test` account and the orphan `/Users/z`
  - the crontab, whose two jobs both pulled from the deleted OpenClaw VPS (backup `~/crontab.bak-20261105`)
  - the Intel Homebrew in `/usr/local` (it had no packages, only the brew repo) and the dead `/usr/local/bin/kymsu` link

  The application firewall is now on.
- **`docs/reference/shell-and-path.md`** (`fd512a1`): GNU `rm` timed out on dead OneDrive placeholder folders, and `/bin/rm` removed them. Seen once; the cause isn't confirmed.

## Decisions Made
- **No backups for now.** There's no Time Machine and no backup app, and David chose to leave it.
- **FileVault is fine.** There's a personal recovery key and no institutional key. `FileVaultMaster.keychain` is an unused leftover. Earlier in the session it was called a risk; that was wrong.
- **Orrery and OpenClaw sync scripts and repos are kept**, only unscheduled. Orrery would need pointing at hal to be useful.

## What Didn't Work
- Removing `/usr/local/Homebrew` and the `_brew` completion links without sudo. `/usr/local` and `/usr/local/share/zsh/site-functions` are owned by root, so an empty `Homebrew` folder and two dangling links are left.
- GNU `rm -rf /Users/z` hit "Operation timed out" on File Provider placeholder folders; `sudo /bin/rm -rf` removed them.

## What's Next
1. **David, now: every new shell prints a `compinit` error about `_brew_services`** until the dangling links are removed. Run this on the Mac, as `dvillavicencio`, with your login password:
   `sudo rm /usr/local/share/zsh/site-functions/_brew /usr/local/share/zsh/site-functions/_brew_services && sudo rmdir /usr/local/Homebrew && zsh -i -c exit`
2. Hand mergewren#131–#134 to the MergeWren session (SendMessage) with the run evidence above. MergeWren fixes and merges them, and gets David's approval on each PR.
3. After each merge, reopen its parent ticket (VIL-546, VIL-544, VIL-550 or VIL-575); each brief covered only part of it (VIL-543).
4. **Tonight before 22:00 PT, David picks the next briefs.** The queue is empty, so VIL-570 alerts.
5. Optional work on this Mac:
   - install macOS 27.2 (27.0 now; restart needed)
   - `sudo rm /Library/Keychains/FileVaultMaster.keychain`
   - free disk space: 91% full, with `com.apple.wallpaper` 22 GB and `~/Downloads` 22 GB
6. Carried over: mergewren#105 (VIL-448) and #103 (VIL-345) in the MergeWren session. Friday after 16:00 PT, confirm the someday reminder (job `572d2f167b79`) posted.

## Gotchas & Watch-outs
- **The Mac's clock is set to MST** (`date` shows `-07:00`), not Pacific. Convert to PT before stating times.
- `/usr/local/bin` still holds app links (Docker, OrbStack, Orca, Cursor, Tailscale, 1password-mcp…), and `/usr/local/share/dotnet` and `/usr/local/mysql` are in use. Only Homebrew's own files were removed. Don't delete `/usr/local` wholesale.
- Old `.zcompdump-*` files have built up in `~/.config/zsh/`. They're harmless.
- **Carried over:**
  - Nothing else may use hal's local models from 01:30 to 05:00 PST.
  - Don't pass David's approvals along to MergeWren.
  - Never run `npx … remote` by hand while the Desktop Commander agent is loaded.
