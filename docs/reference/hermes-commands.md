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
  - **Syd can also use hal's LM Studio** (2026-10-23). Its profile config has a `providers.hal`
    block: `api: http://hal:1234/v1`, `key_env: HAL_LMSTUDIO_API_KEY`, `default_model:
    qwen3.8-27b`, `context_length: 131072`, the same shape as Atlas's `hal` provider. The key is
    LM Studio's `david` token, in the profile's `.env`. Opus stays Syd's default, so pick hal per
    session: `hermes -p syd chat -q "…" --oneshot --provider hal -m qwen3.8-27b`. A one-line reply
    took about 1m40s, mostly prefill of Syd's system prompt.
  - **The 27B is shared** with the overnight pilot (01:30–06:00 PT) and with hal-bench, and LM
    Studio serves 2 requests at a time. A Syd call during a hal-bench speed run skews its numbers.
- **LM Studio API tokens are made only in the GUI.** `lms` has no token command, and LM Studio's
  docs describe only Developer → Server Settings → Manage Tokens. On hal, use the app
  (`/Applications/LM Studio.app`) over Screen Sharing as `hal`. The token store,
  `~/.lmstudio/.internal/permissions-store.json`, keeps SHA-512 hashes and labels (`atlas`,
  `axiom`, `david`, `hal-pilot-worker`); don't hand-edit it.
- **All three step aside for a Hermes wrapper of the same name.** `hermes profile alias <profile>
  [--name <name>]` writes `~/.local/bin/<name>`, which a function would shadow. Each file
  checks for that wrapper and drops its function (`unfunction`) when it exists. On hal as `hal`,
  `atlas` is that wrapper.
- **Each Orca project belongs to one machine.** The `hermes` and `axiom` projects are on hal
  (`hal-svc`), and `syd` is local, so Syd can't start from either of them. A plus-sign terminal is a plain
  shell. A setup script doesn't change that, because it only runs when Orca creates a worktree.
  Orca's built-in Hermes agent runs `hermes --tui`, the default profile, and adds `--yolo` when
  Orca's auto-approve option is on. So it can't start Syd, and it shouldn't be used for it.
