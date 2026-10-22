# 1Password for agents (`op-agent`)

How an agent gets a secret without the secret passing through David's hands or the agent's
transcript (VIL-399). The secret stays in 1Password, in a vault named **Agents**, and is read
at the moment it's needed through `op-agent`, a wrapper around the 1Password CLI (`op`) that
runs it as a read-only **service account**.

## Rules for agents

- **Never put a secret's value on stdout.** Whatever a command prints lands in the
  transcript. `op-agent` refuses the usual ways to do that: `read` or `inject` without
  `-o`, `--reveal`, `--no-masking`, and `item get`. Plain `op` has no such guard, so use
  `op-agent`.
- **Never read, print or copy the token file** (`~/.config/op-agent/token`). It is the key to
  every secret in the Agents vault.
- **Prefer references over values.** A repo's `.env` holds `op://` references, which are safe
  to commit, and the command runs under `op-agent run`:

  ```bash
  # .env (committed):  SANITY_API_READ_TOKEN=op://Agents/bryancola-sanity/read-token
  op-agent run --env-file .env -- npm run build
  ```

  `op run` resolves the references into the child's environment and masks the values if the
  child prints them: `<concealed by 1Password>`.
- **When a tool must read a file** (a `.env.local` that a framework loads by itself), write it
  with `op-agent inject -i .env.tpl -o .env.local` or `op-agent read -o <file> op://…`. Both
  write mode 0600. Keep the file gitignored, and delete it when it's no longer needed.
- **To check that a secret resolves without seeing it:**
  `op-agent read -o "$tmp" op://Agents/<item>/<field> && wc -c < "$tmp" && rm -f "$tmp"`.
- `op-agent whoami`, `op-agent vault list` and `op-agent item list` are safe to run; they
  print names and ids, not values.
- **Don't run it in a loop.** The limits are 1,000 reads per hour per token and **1,000
  requests a day across the whole 1Password account** on the Individual and Families plans.
  `op-agent service-account ratelimit` shows what's left.

`op-agent`'s guard is a seatbelt, not a boundary. Anything that runs as the same account can
read the token file directly.

## Who can read the Agents vault (decide before adding real secrets)

Each account that holds a token file can read **everything** in the vault. On hal, the
overnight pilot's worker runs as `david`, and the code it runs has `david`'s full access
(`pilot/README.md`, "Accepted risk"). A token file in `david`'s home therefore exposes the
whole vault to the worker. So either:

- install `david`'s token only once the pilot has its own account or a sandbox (the fix that
  README names), or
- keep the vault to secrets you would accept the worker seeing.

The `hal` account doesn't run the pilot, so its token file carries no such exposure.

## Setup (human steps)

**On 1Password.com (David):**
1. Create a vault named **Agents**. A service account can't be given the built-in Personal,
   Private or Employee vault, or the default Shared vault.
2. Create a service account (Developer → Service accounts, or `op service-account create`)
   with **read** access to Agents only. Vault access and permissions can't be changed after
   creation; to change them, create a new service account and revoke the old one.
3. Save the token the wizard shows **once**. Put it in your own 1Password, not in a chat or
   a note.
4. Add a test item to Agents, e.g. `op-agent-test` with a password field.

**On hal, as `hal`** (Homebrew at `/opt/homebrew` belongs to `hal`): in `hal`'s dotfiles
clone, `git pull && DOTFILES_PROFILE=server ./install`. That installs the cask and links
`~/.local/bin/op-agent`.

**On hal, as `david`:** `david` isn't set up by the Dotbot install; it has a clone and a
hand-made `~/.local/bin/dot` link. Do the same for this wrapper:
`git -C ~/Projects/Personal/dotfiles pull && ln -sfn ~/Projects/Personal/dotfiles/bin/op-agent ~/.local/bin/op-agent`.
`op` itself comes from `hal`'s Homebrew, which `david` can run.

**On hal, per account that should read the vault** (as that account; see the section above
before doing it for `david`):
```bash
umask 077; mkdir -p ~/.config/op-agent
pbpaste > ~/.config/op-agent/token  # or paste into: cat > ~/.config/op-agent/token, then Ctrl-D
chmod 600 ~/.config/op-agent/token
```
Over SSH there is no `pbpaste`, so use the `cat >` form, and check that the file isn't empty
(`test -s ~/.config/op-agent/token && echo ok`). A failed first attempt that leaves an empty
file is the exact problem this ticket started from.

**Verify** (as each account):
```bash
op-agent whoami                      # the service account, not a person
t=$(mktemp) && op-agent read -o "$t" op://Agents/op-agent-test/password && wc -c < "$t"; rm -f "$t"
```

**Personal Mac:** `op` comes from the same cask (`brew/Brewfile`). The desktop-app integration
works there for David. Agents on the Mac use `op-agent` the same way, with a token file of
their own.

## Sources

Read 2026-10-22 11:54 PDT:
- www.1password.dev/service-accounts/get-started/: CLI 2.18.0 or later; the token goes in
  `OP_SERVICE_ACCOUNT_TOKEN`; permissions are immutable; excluded vaults.
- www.1password.dev/service-accounts/rate-limits/: per-plan hourly and daily limits.
- www.1password.dev/cli/reference/commands/run/: values are masked by default.
- www.1password.dev/cli/reference/commands/inject/: `-o` writes with mode 0600 by default.
- Cask `1password-cli` 2.41.0 (`brew info --cask`): a single `op` binary in
  `/opt/homebrew/bin`, no pkg.
