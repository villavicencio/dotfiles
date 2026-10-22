# Hermes commands: atlas, axiom and syd

Moved out of the always-loaded `CLAUDE.md` on 2026-10-22 (VIL-402), word for word except
for heading levels. `CLAUDE.md` keeps the one-line rules and points here.

## Hermes commands — `atlas`, `axiom` and `syd`
`zsh/functions/atlas.sh`, `axiom.sh` and `syd.sh` are loaded on every machine by the glob in
`zsh/functions.sh`. Each one decides when it is sourced whether to define its function. The
user-facing table is in `README.md` ("Hermes agents").

- **`atlas` and `axiom`** open the two agents that run as hal's `hal` account: Atlas, Hermes's
  `default` profile, and Axiom, the `axiom` profile. Each has its own
  tmux socket and session, and its own Orca project on hal: a placeholder git repo at
  `~/Projects/hermes` or `~/Projects/axiom` in `david`'s home, holding only a README. The
  consoles are:
  - `sudo -u hal -i tmux -L atlas new -A -s atlas 'atlas; exec zsh -il'`
  - `sudo -u hal -i tmux -L axiom new -A -s axiom 'hermes -p axiom --tui; exec zsh -il'`

  Both call `_hal_console` (`zsh/functions/hal_console.sh`), so a fix to how the tab is opened
  is made once:
  - On a desk Mac, it opens the console in an Orca tab. The tab is in the workspace on the
    `hal-svc` environment whose path ends in `/Projects/hermes` (or `/Projects/axiom`);
    `ATLAS_ORCA_ENV` / `AXIOM_ORCA_ENV` override the environment. It needs `orca` and `jq`.
    The lookup is by path, so a project's display name is free to change: the `hermes`
    project shows as `Atlas` since 2026-10-21. Renaming the folder on hal breaks it until
    the suffix in `atlas.sh`/`axiom.sh` follows. The Orca CLI can't set a project's name or
    icon (`orca repo set` only takes worktree visibility); use the project settings in the
    app. An uploaded icon must be a PNG of at most 256 KB; `pngquant` gets a 512×512 there.
  - On hal as `david`, it runs the console in place. The test is whether a local `hal` account
    exists, not whether `orca` is on PATH. Orca's tabs on hal put an `orca` CLI there too, and
    that one talks to hal's own Orca server, which has no `hal-svc` environment (#229).
- **`syd`** is `hermes -p syd --tui "$@"`. It's defined only where `~/.hermes/profiles/syd`
  exists, so hal and the work Mac don't get it. Hermes ignores `--tui` for subcommands, so
  `syd sessions list` works.
- **All three step aside for a Hermes wrapper of the same name.** `hermes profile alias <profile>
  [--name <name>]` writes `~/.local/bin/<name>`, which a function would shadow. Each file
  checks for that wrapper and drops its function (`unfunction`) when it exists. On hal as `hal`,
  `atlas` is that wrapper.
- **Each Orca project belongs to one machine.** The `hermes` and `axiom` projects are on hal
  (`hal-svc`), and `syd` is local, so Syd can't start from either of them. A plus-sign terminal is a plain
  shell. A setup script doesn't change that, because it only runs when Orca creates a worktree.
  Orca's built-in Hermes agent runs `hermes --tui`, the default profile, and adds `--yolo` when
  Orca's auto-approve option is on. So it can't start Syd, and it shouldn't be used for it.
