# 1Password for agents (`op-agent`)

How an agent uses a secret without the secret passing through David's hands or being printed
into the agent's transcript (VIL-399). The secret stays in 1Password, in a vault named
**Agents**, and is read at the moment it's needed through `op-agent`, a wrapper around the
1Password CLI (`op`) that runs it as a read-only **service account**. The command that uses a
secret does receive its value (that's the point); what `op-agent` keeps from it is the
service-account token, and what it keeps from stdout is the value.

## Rules for agents

- **Never put a secret's value on stdout.** Whatever a command prints lands in the
  transcript. `op-agent` refuses the usual ways to do that: `read` or `inject` without
  `-o`, an `-o` that points at stdout (`-`, `/dev/*`, `/proc/*`, a link, a non-regular
  file, in any of `-o F`, `-oF`, `-o=F`, `--out-file F`, `--out-file=F`), `--reveal` and `--no-masking` in any spelling, and `item get`. Plain `op` has no
  such guard, so use `op-agent`.
- **Never read, print or copy the token file** (`~/.config/op-agent/token`). It is the key to
  every secret in the Agents vault.
- **Prefer references over values.** A repo's `.env` holds `op://` references, which are safe
  to commit, and the command runs under `op-agent run`:

  ```bash
  # .env (committed):  SANITY_API_READ_TOKEN=op://Agents/bryancola-sanity/read-token
  op-agent run --env-file .env -- npm run build
  ```

  `op run` resolves the references into the child's environment and masks the values if the
  child prints them: `<concealed by 1Password>`. `op-agent` starts the child through
  `env -u OP_SERVICE_ACCOUNT_TOKEN`, because `op run` otherwise passes its own environment,
  token included, to the child. The child can still write a value to a file or the
  network, so run only commands you'd trust with that secret.
- **When a tool must read a file** (a `.env.local` that a framework loads by itself), write it
  with `op-agent inject -i .env.tpl -o .env.local` or `op-agent read -o <file> op://…`. Both
  write mode 0600. Keep the file gitignored, and delete it when it's no longer needed.
- **To check that a secret resolves without seeing it:**
  `t=$(mktemp); op-agent read -f -o "$t" op://Agents/<item>/<field> && wc -c < "$t"; rc=$?; rm -f "$t" || rc=1; (exit $rc)`.
- `op-agent whoami`, `op-agent vault list` and `op-agent item list` are safe to run; they
  print names and ids, not values.
- **Don't run it in a loop.** The limits are 1,000 reads per hour per token and **1,000
  requests a day across the whole 1Password account** on the Individual and Families plans.
  `op-agent service-account ratelimit` shows what's left.

`op-agent`'s guard is a seatbelt, not a boundary. Anything that runs as the same account can
read the token file directly.

## Who can read the Agents vault

Each account that holds a token file can read **everything** in the vault. On hal, the
overnight pilot's worker runs as `david`, and the code it runs has `david`'s full access
(`pilot/README.md`, "Accepted risk"). Since `david` holds a token, the worker can read the
whole vault too. **David accepted that on 2026-10-22** (VIL-399): both `hal` and `david` get
a token. So:

- put in the Agents vault only secrets you'd accept the pilot worker reading;
- revisit this when the pilot gets its own account or a sandbox (the fix that README names).
  At that point `david`'s token can stay and the exposure goes away.

## Setup (human steps)

**On 1Password.com (David):**

Steps 1, 2 and 4 can also be done with `op` on the personal Mac through the 1Password app's
CLI integration. Run `op signin` first in that terminal. Until then, `op whoami` reports
`account is not signed in` even with the integration on, and it never prompts for Touch ID
itself (seen 2026-10-22). The sign-in lasts for that terminal only, until about 10 idle minutes.

1. Create a vault named **Agents**. A service account can't be given the built-in Personal,
   Private or Employee vault, or the default Shared vault.
2. Create a service account (Developer → Service accounts, or `op service-account create`)
   with **read** access to Agents only. Vault access and permissions can't be changed after
   creation; to change them, create a new service account and revoke the old one.
3. Save the token the wizard shows **once**. Put it in your own 1Password, not in a chat or
   a note.
4. Add a test item to Agents, e.g. `op-agent-test` with a password field.

**On hal, as `hal`** (Homebrew at `$BREW_PREFIX` belongs to `hal`): in `hal`'s dotfiles
clone, `git pull && DOTFILES_PROFILE=server ./install`. That installs the cask and links
`~/.local/bin/op-agent`.

**On hal, as `david`:** `david` isn't set up by the Dotbot install; it has a clone and a
hand-made `~/.local/bin/dot` link. Do the same for this wrapper:
`git -C ~/Projects/Personal/dotfiles pull && ln -sfn ~/Projects/Personal/dotfiles/bin/op-agent ~/.local/bin/op-agent`.
`op` itself comes from `hal`'s Homebrew, which `david` can run.

After changing `bin/op-agent`, run `ci/op-agent-checks.sh` (a stub `op`; no account needed).

**The token file on hal, for `hal` and for `david`.** The section above explains what `david`'s
copy exposes. Run this from the personal Mac, in a terminal with `op signin` done. The token
goes from your 1Password straight into the file over SSH and is never shown. `hal-orca` logs
in as `hal`, and `hal` logs in as `david`; both use key auth.
```bash
rc=0
for host in hal-orca hal; do
  op item get "hal-agents service account" --fields label=credential --reveal |
    ssh "$host" 'umask 077; d=~/.config/op-agent; mkdir -p "$d" && cat > "$d/token.new" && [ "$(head -c 4 "$d/token.new")" = ops_ ] && mv -f "$d/token.new" "$d/token" && echo "written on hal as $(id -un), $(wc -c < "$d/token") bytes" || { rm -f "$d/token.new"; echo "nothing written on hal as $(id -un): input was not a service-account token; existing token kept" >&2; exit 1; }' || rc=1
done
if [ "$rc" = 0 ]; then echo "both accounts written"; else echo "FAILED for at least one account; see above" >&2; false; fi
```
Each line should report a non-zero byte count, and the two counts should match. The token
goes to `token.new` first and replaces `token` only when it starts with `ops_` (every
service-account token does). An empty or wrong value, from a failed `op item get` or a
placeholder in place of the field, leaves the existing token alone, and the loop reports
which account failed. An empty
file from a failed first attempt is exactly the problem this ticket started from. (Done on
2026-10-22: 820 bytes for each account, same SHA-256.)

**Verify** (as each account):
```bash
op-agent whoami                      # the service account, not a person
t=$(mktemp); op-agent read -f -o "$t" op://Agents/op-agent-test/password && wc -c < "$t"; rc=$?; rm -f "$t" || rc=1; (exit $rc)
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
  `$BREW_PREFIX/bin`, no pkg.
