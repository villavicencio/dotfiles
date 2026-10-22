# Work Mac

Moved out of the always-loaded `CLAUDE.md` on 2026-10-22 (VIL-402), word for word except
for heading levels. `CLAUDE.md` keeps the one-line rules and points here.

## Setting up the work Mac

1. Clone this repo (recommended: `~/Projects/Personal/dotfiles`)
2. Verify architecture: `uname -m` must print `arm64` (check iTerm2 is not set to "Open using Rosetta")
3. Run `./install`
4. Clear stale completions: `rm ~/.zcompdump && exec zsh`
5. Create `~/.gitconfig.local`:
   ```ini
   [user]
       email = <your-work-email>
   ```
6. Create `~/env.sh` with required corporate Vertex AI overrides:
   ```bash
   export CLOUDSDK_PYTHON=/usr/bin/python3
   export GOOGLE_APPLICATION_CREDENTIALS=~/Downloads/<service-account-key>.json
   export ANTHROPIC_VERTEX_PROJECT_ID=<corp-gcp-project>
   export CLAUDE_CODE_USE_VERTEX=1
   export CLOUD_ML_REGION=us-east5
   ```
   Note: `CLOUDSDK_PYTHON` is required because the corporate proxy's SSL interception
   breaks Homebrew Python. System Python (`/usr/bin/python3`) trusts corporate CA certs via Keychain.
7. Switch the git remote to use the `github-work` SSH alias:
   ```bash
   git remote set-url origin git@github-work:villavicencio/dotfiles.git
   ```
   This avoids Tailscale MagicDNS routing GitHub SSH through the home Mac.
8. Add GitHub domains to `/etc/hosts` (Tailscale MagicDNS intercepts DNS):
   ```
   140.82.114.4    github.com
   140.82.114.10   codeload.github.com
   185.199.108.133 objects.githubusercontent.com
   185.199.108.133 raw.githubusercontent.com
   ```
