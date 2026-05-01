---
module: tmux
date: 2026-05-01
problem_type: best_practice
component: tooling
severity: low
applies_when:
  - "Installing CoreLocationCLI (Homebrew cask `corelocationcli`) on macOS"
  - "Wiring CoreLocationCLI into the tmux status bar (or any tmux-spawned context)"
  - "Debugging why the tmux location segment renders empty after install"
  - "Granting Location Services to a CLI binary the first time"
tags:
  - macos
  - tmux
  - corelocationcli
  - tcc
  - gatekeeper
  - location-services
  - permissions
related_components:
  - development_workflow
---

# macOS first-run on CoreLocationCLI: Gatekeeper, then Location Services TCC

## Context

The tmux status-bar location segment (`tmux/scripts/location.sh`) calls `CoreLocationCLI` (capitalized binary; the cask itself is named lowercase `corelocationcli`). On a brand-new Mac install, the first invocation surfaces **two distinct system gates** in sequence — and they are easy to confuse for "the cask is broken" if you don't know about them.

This doc captures the sequence so a future reinstall (or work-Mac onboarding) takes minutes instead of an afternoon.

## Guidance

After `brew bundle install` finishes, the user must clear two gates **before** `CoreLocationCLI` can return location data:

1. **Gatekeeper notarization gate.** The first time the binary runs (whether from the tmux status bar, a manual shell invocation, or a script), macOS Gatekeeper blocks it with "cannot verify the developer of `CoreLocationCLI`." Resolution:
   - Open **System Settings → Privacy & Security → Security**.
   - Find the "CoreLocationCLI was blocked..." entry near the bottom.
   - Click **Open Anyway**, then confirm in the dialog that follows.
   - This gate is one-time per binary version.
2. **Location Services TCC prompt.** With Gatekeeper cleared, the **second** invocation triggers the macOS TCC prompt asking which app should be granted Location Services. The prompt attributes to the GUI ancestor of the calling process — typically iTerm2, since that's the parent of the user's tmux server. Click **Allow**.
3. **Verify** in **System Settings → Privacy & Security → Location Services**: the granted app (iTerm2) should appear in the list with its toggle ON.

After both gates clear, subsequent invocations from any process spawned by iTerm2 — including the tmux status-bar refresh worker — return location data without further prompts.

### When the TCC prompt does not surface

If tmux is auto-attached at shell start (the dotfiles' `zshrc` session-restoration block), the prompt may not visibly surface — the parent-app attribution can land on a process that no longer has a foreground GUI window. Workaround:

- Open a **fresh iTerm2 window outside tmux** (or run `tmux kill-server` first).
- Manually run `CoreLocationCLI` once. The TCC prompt fires against iTerm2 directly.
- Click **Allow**.
- Reattach tmux. The status-bar refresh worker will now receive location data.

### TCC blast-radius note

Granting Location Services to iTerm2 authorizes **every process spawned under it** — any shell, any npm postinstall, any plugin — to read CoreLocation without a further prompt. This is broader than the script's actual need (it just wants city/region for the status pill). Worth keeping in mind when running untrusted code in that terminal; not a blocker for the location-pill feature, but a footgun if a malicious dependency were to read CoreLocation in the background.

## Why This Matters

Apple's TCC framework was designed for bundled `.app` applications, where the bundle's `Info.plist` declares `NSLocationUsageDescription` and the OS attributes the prompt to the bundle. CoreLocationCLI is a single Mach-O binary installed via Homebrew cask — it has no bundle, no Info.plist, no notarization signature the user explicitly trusted. Gatekeeper handles the "is this binary safe to run" question; TCC handles the "is this app allowed to read this data class" question. The two gates are orthogonal but both fire on first-use, and the user-visible UX makes them feel like a single ambiguous failure ("nothing happened, the pill is empty") unless you know to look in two different places.

The dotfiles' tmux location-pill feature explicitly accepts silent fall-through on missing Location Services — the pill simply renders empty. That design decision means a user on a fresh machine may not even notice the gates were never cleared. This doc is the recovery path.

## When to Apply

- Setting up a new Mac with the dotfiles for the first time.
- Onboarding the work Mac (when the user opts into the location feature there).
- Debugging an empty location segment in the tmux status bar — start by checking if Location Services is granted to iTerm2 in System Settings.
- Reinstalling `corelocationcli` after a Homebrew cleanup or major macOS upgrade (Gatekeeper sometimes re-blocks after OS updates).

## Related

- The location-pill plan: `docs/plans/2026-05-01-001-feat-tmux-location-pill-plan.md`
- The location resolver: `tmux/scripts/location.sh`
- The status-right pill that reads its output: `tmux/tmux.display.conf`
- Upstream CoreLocationCLI: https://github.com/fulldecent/corelocationcli (cask source: https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/c/corelocationcli.rb)
