# HANDOFF — 2026-05-05 (PDT)

Same-calendar-day continuation of the earlier session that landed yesterday's HANDOFF (no overnight gap). Started with `/pickup` against the apt-warmth investigation queued in #65; closed it end-to-end. **Net: 2 PRs merged (#66 + #67), 2 issues closed (#58 + #65), 2 direct-to-master postmortem commits, 1 misattribution corrected.**

The 12-minute Linux CI slowness from 2026-05-04 was finally diagnosed as IPv6 SYN-timeout fallback (`archive.ubuntu.com` → Cloudflare IPv6). Yesterday's "warm-up step is load-bearing" framing was a misattribution; today both warm-path and cold-path runs completed in ~52s, confirming nothing was structurally dependent on the warm-up. Fix landed at the image level (bake `Acquire::ForceIPv4 "true";` into `ci/Dockerfile`), warm-up step removed in step 2/2.

## What We Built

### docs(solutions) — IPv6 fallback misattribution postmortem (commits `f6fb1c2` + `babdfa6`, master)

`docs/solutions/cross-machine/install-matrix-ipv6-fallback-misattribution-2026-05-05.md` (~155 lines). Documents:
- The misattribution: yesterday's "warm-up is load-bearing" was wrong; the warm-up coincidentally absorbed the IPv6-fallback timeout budget once
- The signature: 60-69s gaps between apt `Get:`/`Ign:` lines == IPv6 SYN timeout (default `tcp_syn_retries`)
- The root cause: `archive.ubuntu.com` resolves to Cloudflare CDN IPv6 (`2606:4700:10::6814:1cf6` and `2606:4700:10::ac42:98b0`); the Azure-eastus runner network can't reliably reach those endpoints
- The diagnostic methodology: paired `pull_request` (warm-path, default `skip_warmup=false`) + `workflow_dispatch -f skip_warmup=true` (cold-path) runs against the same branch, with `time getent hosts`, `time apt-get update` (without `-qq`), and full `set -x` visibility
- The four hypothesis verdicts (only #1 confirmed)
- Why image-level beats workflow-runtime injection (PR #64 tried that and it didn't catch earlier apt invocations)

Initial commit `f6fb1c2` had the fix snippet showing the printf at the END of the RUN chain. PR #66 review (P2 finding) caught that this would leave `publish-ci-image.yml`'s own image build exposed to the same IPv6 fallback. Commit `babdfa6` fixed the snippet + added a callout against re-reordering. Both committed direct to master per docs carve-out.

### PR #66 — bake Acquire::ForceIPv4 into ci/Dockerfile (squash-merged 2026-05-05T18:38:05Z as `6d988c3`)

#65 step 1/2. 1 file changed (`ci/Dockerfile`), 20 insertions / 1 deletion.

- Writes `Acquire::ForceIPv4 "true";` to `/etc/apt/apt.conf.d/99-force-ipv4` as the **first** link in the existing RUN chain. Order matters: at the end of the chain the conf only protects runtime consumers, leaving `publish-ci-image.yml`'s own build exposed.
- 13-line comment block above the RUN explaining the IPv6→Cloudflare cause, why image-level (not runtime), and a separate 4-line callout about why the printf must be first in the chain.
- Branch was history-cleaned via `--force-with-lease`: the original diagnostic instrumentation commit (`aa6e1d3`) and a follow-up reorder commit (`befdd8c`) were collapsed into a single clean commit (`4344e55`). Diagnostic methodology preserved in the postmortem instead.
- 6 always-on persona ce-code-review wasn't run today — the diff was small and the user reviewed manually. P2 finding (printf placement) caught and fixed before merge.

### PR #67 — remove warm-up step + bump digest (squash-merged 2026-05-05T18:52:41Z as `987ff6d`, closes #58 #65)

#65 step 2/2. 1 file changed (`.github/workflows/install-matrix.yml`), 6 insertions / 23 deletions.

- Bumped pin from `sha256:758af964…a6d6` → `sha256:8f6ad527bb8ee8d729f94c2e3c6f18f872a54b7a0f698d670ac4a8adc6a3f20e`. Captured from `publish-ci-image.yml` run [25395181070](https://github.com/villavicencio/dotfiles/actions/runs/25395181070)'s `containerimage.digest` output (Docker daemon not running locally; the canonical `docker buildx imagetools inspect ghcr.io/villavicencio/dotfiles-ci-ubuntu:24.04` later returned the same digest, confirming the workflow-log capture was correct).
- Deleted the entire "Warm up apt cache" step + its 17-line comment block.
- Updated the `image:` block comment to mention #65's ForceIPv4 bake alongside #58's python3+sudo bake.
- CI on PR #67: Linux **63s**, macOS **9m40s**. Both green. Linux was ~10s slower than the prior 52s baseline because the locale block now does cold `apt-get update` of 19 sources (~37.9 MB in 2s @ 22 MB/s) without the warm-up's pre-population.

### Issues #58 + #65 closed with retrospective comments

- **#58** was actually auto-closed by PR #62's body yesterday (the 2026-05-04 HANDOFF was incorrect that #58 stayed open). Comment added today recording the genuine close (warm-up step finally removed in PR #67).
- **#65** auto-closed by PR #67's `closes #65` body. Comment added pointing at the postmortem and naming both PRs.

## Decisions Made

- **Option 1 chosen for the fix.** Image-level ForceIPv4 + remove warm-up. Considered and rejected: (option 2) belt-and-braces with both ForceIPv4 + warm-up, (option 3) just bake ForceIPv4 and leave warm-up. Option 1 truly closes #58, removes ~7s overhead per run, and ForceIPv4 alone is bulletproof against the IPv6-fallback class of failure.
- **ForceIPv4 lives at the image level, not workflow runtime, not install-pipeline runtime.** PR #64 tried both runtime approaches and they failed (conf-d write at start of locale block was too late; inline `-o` flags interacted with `-qq` to produce silent hangs). Image-level state is universal across every apt invocation from second one onward and doesn't penalize the VPS (which doesn't pull this image).
- **Two-PR sequence required by chicken-and-egg.** Same as PR #62 + #64 yesterday: ci/Dockerfile changes need to merge to master before publish-ci-image.yml republishes and the new digest is available; install-matrix.yml needs the new digest. Single PR can't satisfy both.
- **`printf` MUST be first in the RUN chain.** P2 review finding caught this — at the end of the chain the conf only takes effect for runtime consumers, leaving the image build itself exposed. Comment in Dockerfile explicitly warns against re-reordering.
- **Force-push to drop the diagnostic commit on PR #66.** The branch was mine, the PR was draft, the diagnostic instrumentation served its purpose (gathered the warm/cold timing data) but had no value to preserve in history once the methodology was captured in the postmortem. `--force-with-lease` used for safety.
- **Postmortem committed direct to master per docs carve-out.** Matches yesterday's pattern (`actions-checkout-leaves-regular-gitconfig-2026-05-04.md` and `python-bytecode-cache-falsely-fails-r2-on-macos-runners-2026-05-04.md`). Per `feedback_commit_approval.md`: "commit directly for new docs and pure additive content."
- **Diagnostic methodology preserved as a reusable pattern.** `workflow_dispatch` boolean input gating a suspect step + paired warm/cold runs against the same branch (different concurrency groups via different `github.ref`) is documented in the postmortem's "Why this is a learning worth keeping" section.

## What Didn't Work

- **Yesterday's "warm-up is load-bearing" framing.** Empirical observation was right (removing the warm-up timed out the Linux leg), but the causal model was wrong. The warm-up just absorbed the IPv6-fallback budget once; nothing was structurally dependent on it.
- **`printf` at the end of the RUN chain** (initial commit on PR #66). Reviewer caught it before merge — would have left the image-build's own apt operations exposed to the same IPv6 fallback.
- **`docker buildx imagetools inspect` for digest capture.** Docker daemon wasn't running locally. Pulled the digest from the publish workflow's logs instead (the `containerimage.digest` line written by `actions/build-push-action`). Confirmed correct after the fact when the docker command finally returned (it had been hanging in the background).
- **Initial concurrency-group conflict on the dispatch runs.** Two back-to-back `workflow_dispatch` calls on the same ref shared the `install-matrix-${{ github.ref }}` concurrency group; the second cancelled the first. Solved by triggering one as `pull_request` (PR ref) and the other as `workflow_dispatch` (branch ref), giving them separate groups.

## What's Next

1. **#63 — publish-ci-image.yml smoke test.** Most adjacent to the work just shipped. Would catch image-content regressions before they reach `install-matrix.yml`. A future "someone strips ForceIPv4 from the Dockerfile as cleanup" or "apt configuration bug" would be invisible until install-matrix runs against the new digest. A smoke test (e.g., spawn the image and run `apt-config dump | grep ForceIPv4`) catches it at the right layer.
2. **#59 / #60 / #61** — composite-action extraction, R3 assertion 2 seeded validation, Dotbot output-format pin. Each is a small follow-up; pick up independently.
3. **PR #1c — third leg of CE trifecta.** `docs/solutions/_index.md` + `critical-patterns.md` regen on `/handoff`. Plan exists at `docs/plans/2026-05-03-001-feat-ci-install-matrix-plan.md` (Deferred to Follow-Up Work section). New feature work, better as fresh session.
4. **`actions/checkout` Node 20 deprecation warning** still showing on every CI run. Action can bump to a Node 24 version when one is available; currently informational only (deadline June 2nd, 2026 per GH's own message).

## Gotchas & Watch-outs

- **Linux CI is 63s today** (was 52s baseline pre-#67). The 10s increase is from the locale block doing a cold `apt-get update` of 19 sources without the warm-up's pre-population. Not a regression worth blocking on. If it grows, future option: don't strip `/var/lib/apt/lists/*` in `ci/Dockerfile` so the lists ship populated.
- **The 60-69s gap signature in apt logs == IPv6 SYN-timeout fallback.** If it ever resurfaces, jump straight to "is `/etc/apt/apt.conf.d/99-force-ipv4` present in the image?" — don't relitigate the 4-attempt CI fight from 2026-05-04. The postmortem documents this explicitly.
- **`Acquire::ForceIPv4` MUST stay first in the `RUN` chain in `ci/Dockerfile`.** The comment block warns against moving it to "logical" cleanup-block placement at the end. If it gets moved, `publish-ci-image.yml`'s own image build loses the protection (only runtime consumers benefit).
- **Yesterday's HANDOFF claimed #58 stayed open** until #65 landed. That was incorrect — #58 was auto-closed by PR #62's body on 2026-05-04T20:50:09Z. We didn't notice yesterday because the workflow / acceptance criterion still expected the warm-up step to be removed, which only happened today via PR #67. Just a minor documentation mismatch; both issues are now genuinely closed.
- **`claude/CLAUDE.md`, `claude/commands/*.md`, `claude/settings.json`** are symlinked into `~/.claude/` — edits via the live Claude UI write back through to the repo. No `claude/*` edits this session, but the rule still applies; treat any `M` on those files as real intentional content (per `feedback_claude_symlink_writeback.md`).
- **Force-push on draft PRs is OK** when the branch is yours, the PR has no review history yet, and the dropped commits have no preserved value (the diagnostic methodology is in the postmortem, not the dropped commit). Used `--force-with-lease` for safety.
- **Digest capture from publish workflow logs** is a good fallback when Docker daemon isn't running locally. Look for `containerimage.digest` in the `actions/build-push-action` job output. The canonical method is `docker buildx imagetools inspect ghcr.io/<owner>/dotfiles-ci-ubuntu:24.04` but it requires the daemon.
- **Inbox-archive cycle on `/pickup`** worked cleanly today: 4 openclaw infra signals (Browserbase down, Discord react missing for Atlas, 2 MCP-reaper high-kill alerts) were surfaced and archived to `shared/inbox/forge/archive/`. None affected dotfiles work.
