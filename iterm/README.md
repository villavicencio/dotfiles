# iTerm2 configuration

The dotfiles ship iTerm2 settings as a **Dynamic Profile** (not a full prefs
plist). A Dynamic Profile carries only the intentional *visual* profile and
holds no identity: no window arrangements, no working directory, no username or
hostname.

## Why the old approach leaked

iTerm2 was previously pointed at this repo as its **custom preferences folder**
(`LoadPrefsFromCustomFolder = 1`, `PrefsCustomFolder = <repo>/iterm`). In that
mode iTerm2 rewrites its *entire* `com.googlecode.iterm2.plist` into the folder
on every quit — including window arrangements, working directories, `/Users/<name>`
paths and the machine hostname. That plist was tracked, so PII flowed straight
into git history. The plist is now `.gitignore`d, but git-ignoring alone does
**not** stop the leak: while custom-folder mode is on, iTerm2 keeps recreating
the file on disk. Completing the fix requires turning custom-folder mode **off**
— see [Migrating](#migrating-off-custom-preferences-folder-mode) below.

## Files

| File | What it is | Install path |
|---|---|---|
| `profile-dynamic.json` | The visual profile (colors, fonts, Shift+Enter mapping). A Dynamic Profile. | Auto-linked by Dotbot to `~/Library/Application Support/iTerm2/DynamicProfiles/dotfiles.json` |
| `iterm2-app-keymap.json` | App-level bindings a Dynamic Profile **cannot** carry: `GlobalKeyMap` + `PointerActions`. Applied manually. | Not linked — see restore step below |
| `build-dynamic-profile.py` | One-shot generator that produced the two JSON files from a live plist, stripping PII/session keys. Kept for provenance/audit. | — |

The profile applies automatically on the next machine: Dotbot links it, iTerm2
reads the DynamicProfiles directory live, no restart needed.

## Migrating off custom-preferences-folder mode

**One-time, per machine.** If iTerm2 is still loading prefs from this repo
(`defaults read com.googlecode.iterm2 LoadPrefsFromCustomFolder` prints `1`),
finish the migration to the Dynamic Profile:

```sh
# QUIT iTerm2 first (it overwrites its prefs on quit).
helpers/restore-iterm-app-prefs.sh --migrate
# then relaunch iTerm2
```

`--migrate` backs up the old prefs **outside the repo** (mode `0600`, under
`${XDG_STATE_HOME:-~/.local/state}/dotfiles/`) — never inside `iterm/`, since that
plist is exactly the PII being removed. It then writes the app-level bindings into
iTerm2's standard per-machine domain and sets `LoadPrefsFromCustomFolder = false`
so iTerm2 stops reading/writing this repo.
After relaunch: **Preferences → Profiles**, select **Dotfiles**, mark it default.
iTerm2 will no longer recreate the plist here.

## Restoring app-level key/pointer bindings

`GlobalKeyMap` and `PointerActions` are **global** iTerm2 preferences, not
profile-scoped, so a Dynamic Profile can't restore them. They live in
`iterm2-app-keymap.json`. Once custom-folder mode is off (see above), apply them
on demand:

```sh
# Quit iTerm2 first — it overwrites its defaults on quit, so applying them
# while it's running has no effect.
helpers/restore-iterm-app-prefs.sh
# then relaunch iTerm2
```

The script is macOS-only, honors `DOTFILES_DRY_RUN=1`, and refuses to run while
iTerm2 is up. If custom-folder mode is still on it **refuses** to write (the
write would be silently superseded) and prints the `--migrate` instructions
instead — so it never reports a false success. It is **not** wired into
`./install`: writing another app's live defaults during an unattended install is
exactly the kind of side effect the install pipeline avoids. It's a deliberate
manual step.

## Regenerating

`build-dynamic-profile.py` reads a live `com.googlecode.iterm2.plist` (which is
`.gitignore`d and not tracked). To regenerate after changing the profile in the
iTerm2 UI:

```sh
# Point at the live prefs and re-extract.
ITERM_PLIST="$HOME/Library/Preferences/com.googlecode.iterm2.plist" \
  python3 iterm/build-dynamic-profile.py
```

It drops identity/session keys, converts iTerm's non-finite `Infinity` values to
finite numbers (strict-JSON compliance), and asserts both output files are free
of `/Users/`, the machine hostname, and the owner's name before writing.
