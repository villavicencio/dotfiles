---
title: "Linux install-matrix slowness was IPv6 fallback, not warm-up dependency — root cause and bake-in fix"
date: 2026-05-05
category: cross-machine
tags:
  - github-actions
  - install-matrix
  - apt
  - ipv6
  - cloudflare
  - root-cause-misattribution
  - first-write-trap
severity: Medium
component: ".github/workflows/install-matrix.yml — Linux leg apt timing; ci/Dockerfile apt configuration"
symptoms:
  - "PR CI Linux leg ran 12+ minutes (vs ~54s baseline) for several hours on 2026-05-04"
  - "Removing the runtime apt-bootstrap step caused the Linux leg to hit the 20-min job timeout"
  - "Visible Get/Ign lines in apt-get install output were spaced 60-69 seconds apart"
  - "Empirically restoring the bootstrap step (renamed 'Warm up apt cache') brought runtime back to ~12 min"
  - "Subsequent investigation runs the next day on the same workflow showed the slowness gone with no code change"
problem_type: "Transient upstream network condition misattributed as a structural workflow dependency"
module: "install-matrix CI workflow + ci/Dockerfile"
related_solutions:
  - "docs/solutions/cross-machine/install-matrix-seeded-failure-evidence-2026-05-03.md — companion validation evidence for the same workflow"
  - "docs/solutions/cross-machine/actions-checkout-leaves-regular-gitconfig-2026-05-04.md — sibling install-matrix learning from the prior session"
---

## TL;DR

The "warm-up step is load-bearing" finding from #58 / PR #64 was a misattribution. The 60-69s gaps between apt `Get:` lines that made the Linux leg time out without the warm-up step are the classic IPv6-connect-timeout-then-IPv4-fallback signature, not a missing apt-state dependency. `archive.ubuntu.com` resolves to Cloudflare CDN IPv6 addresses (`2606:4700:10::*`); when GitHub Actions' Azure-eastus runner network can't reach those IPv6 endpoints, every fresh apt connection waits ~60s for the IPv6 SYN to time out before falling back to IPv4. The warm-up step happened to absorb that fallback budget once, leaving the rest of the pipeline talking to already-failed-over IPv4 paths.

The next day the slowness was gone — IPv6 reachability had recovered and both the warm-up-on and warm-up-off paths completed in ~52s. The fix is image-level: bake `Acquire::ForceIPv4 "true";` into `ci/Dockerfile` so apt skips the IPv6 attempt preemptively. With that in place the warm-up step can be deleted (truly closing #58) and the workflow becomes resilient to future IPv6-reachability transients.

## Symptom on 2026-05-04

After PR #62 baked `python3` and `sudo` into the image, PR #64's first attempt to delete the runtime `Install bootstrap deps` step from `install-matrix.yml` started timing out the Linux leg at 20 minutes. The visible apt log had this signature:

```
22:18:12  Get:1 liblocale-gettext-perl
22:19:15  Ign:2 libmpfr6     (+63s)
22:20:18  Ign:3 libsigsegv2   (+63s)
22:21:27  Ign:4 gawk          (+69s)
22:22:12  Get:5 adduser       (+45s)
```

Three different network-config approaches were tried during PR #64 and each failed:

- writing `Acquire::ForceIPv4 "true";` to `/etc/apt/apt.conf.d/99force-ipv4` *at the start of the locale shell block* — apt-get update fell to ~2 min but downstream apt connections still hit the 60s/conn delays
- inline `-o Acquire::ForceIPv4=true -o Acquire::http::Timeout=20` on every apt invocation — silent 20-min hang
- bringing back the bootstrap step (renamed "Warm up apt cache") with body reduced to `apt-get update -qq` — Linux leg back to ~12 min, green CI

The pivot landed PR #64 with the warm-up step kept and `#65` filed to investigate further. Issue #65's body listed four hypotheses:

1. IPv6 reachability transient
2. DNS resolver cache population
3. apt mirror selection / fallback
4. `/var/lib/apt/lists/` connection-metadata caching

## Investigation on 2026-05-05

PR #66 added diagnostic instrumentation to the workflow:

- A `skip_warmup` `workflow_dispatch` boolean input gating the warm-up step via `if:` (default false so PR runs were unaffected)
- The warm-up step rebuilt with `set -x`, `time getent hosts archive.ubuntu.com` x3 pre and post, dumps of `/etc/resolv.conf` / `/etc/apt/sources.list*` / `/etc/apt/apt.conf.d/` / `/var/lib/apt/lists/` pre and post, and `time apt-get update` with `-qq` dropped
- A new "Diagnostic — pre-install network state" step right before `Apply (./install)` repeating the DNS + lists snapshot regardless of `skip_warmup`, so warm-vs-cold deltas were captured at the same point in the job
- `install-linux.conf.yaml`'s locale block had `-qq` dropped temporarily so the slow-path apt activity was visible inside `./install`

Two paired runs were triggered against the same branch:

- **Warm path** (run 25387681948, `pull_request` event, `skip_warmup` defaults to false) — Linux leg **52s**
- **Cold path** (run 25387688848, `workflow_dispatch` with `skip_warmup=true`) — Linux leg **51s**

### Empirical findings

DNS resolution of `archive.ubuntu.com` was sub-millisecond in both pre-install snapshots — first call 27ms (cold cache), subsequent calls 1-2ms. Resolver state was identical: Docker's embedded `127.0.0.11` proxying to host `127.0.0.53`.

`archive.ubuntu.com` resolves to Cloudflare CDN IPv6:

```
2606:4700:10::6814:1cf6 archive.ubuntu.com.cdn.cloudflare.net archive.ubuntu.com
2606:4700:10::ac42:98b0 archive.ubuntu.com.cdn.cloudflare.net archive.ubuntu.com
```

Apt activity comparison inside the locale block / `install_packages.sh`:

| Metric | Warm path | Cold path |
|---|---|---|
| `apt-get update` (locale block) | 4 Hit lines, ~30ms (cached from warm-up) | 19 Get lines, 37.9 MB in 2s @ 22 MB/s |
| `apt-get install locales` fetch | 154ms | 165ms |
| 29 sequential `Get:` lines in `install_packages.sh` | ~510ms total (~15ms apart) | ~440ms total (~15ms apart) |

The 15ms inter-Get spacing in the cold path is what apt looks like with IPv6 working. The 60-69s spacing from 2026-05-04 is what apt looks like during IPv6 connect timeout fallback.

### Hypothesis verdicts

| # | Hypothesis | Verdict |
|---|---|---|
| 1 | IPv6 reachability transient | **Confirmed.** 60s gaps == IPv6 SYN timeout (default `tcp_syn_retries`/connect timeout). `archive.ubuntu.com` is on Cloudflare IPv6. |
| 2 | DNS cache population | Disproven. DNS sub-ms even cold. |
| 3 | Mirror selection | Disproven. Same mirrors, both fast. |
| 4 | `/var/lib/apt/lists/` connection caching | Disproven. Cold path with empty lists is just as fast as warm. |

The warm-up step was never structurally load-bearing. It happened to be the first apt invocation on 2026-05-04 and absorbed the IPv6-fallback timeout budget so that downstream apt invocations talked to already-failed-over IPv4 paths and didn't pay the timeout again.

## Fix

Bake the IPv4 force into the image so apt skips the IPv6 attempt preemptively:

```dockerfile
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl git python3 sudo zsh \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && printf 'Acquire::ForceIPv4 "true";\n' > /etc/apt/apt.conf.d/99-force-ipv4
```

Why image-level (not workflow runtime, not install-pipeline runtime):

- **Workflow-runtime injection was tried in PR #64** — the conf-d write at the top of the locale block didn't cover apt invocations earlier in the job, and inline `-o` flags interacted with `-qq` to produce silent hangs. Image-level state is universal across every apt call from second one onward.
- **Install-pipeline runtime would penalize the VPS too.** The VPS's apt sources resolve over IPv4 fine; forcing IPv4 there is wasted opinion. The image only ships in CI.
- **The image is the right ownership boundary** — it's the layer that owns "what apt configuration does CI use," and the workflow / install pipeline both should be able to assume apt is configured sanely.

With ForceIPv4 baked in, the warm-up step becomes redundant and can be deleted in step 2/2 (after the image republishes and the digest pin is bumped). That truly closes #58 and #65.

## Why this is a learning worth keeping

This is a **misattribution-of-cause postmortem**, not a fix-recipe postmortem. The original investigation in PR #64 had the right empirical observation ("removing the warm-up step times out the Linux leg") and the wrong causal model ("the warm-up step is structurally load-bearing for downstream apt"). The fix that landed (keep the warm-up step, rename it, document it as load-bearing) was correct *as a pivot* given the 4-attempt CI fight, but the comment block describing it as load-bearing was reinforcing the wrong model.

The diagnostic methodology that surfaced the truth is reusable:

- **Pair one fast-path run and one slow-path run with full visibility.** The original PR #64 attempts had `-qq` suppressing the apt output, so the actual signature (60s gaps) was invisible. Drop `-qq` and add `set -x` even when it makes logs noisy.
- **Use `workflow_dispatch` with a boolean input to gate the suspect step.** Lets you compare warm-vs-cold paths in the same PR/branch without needing two separate PRs.
- **Capture timing probes (`time getent`, `time apt-get update`) at the same point in two runs**, not just one. The delta is the empirical record.
- **Be willing for the fix to be in a different layer than the diagnostic.** The diagnostic instrumentation was in the workflow file; the actual fix is in the image. PR step 1/2 reverts the diagnostic and ships the image change; step 2/2 removes the warm-up.

If apt slowness ever resurfaces in CI with the same 60s-gap signature, jump straight to "is IPv6 reachability degraded?" — the answer is the conf-d file already winning that fight.

## What didn't work in the original 2026-05-04 investigation

(Recorded for the next maintainer who finds this issue and has the same temptations.)

- `Acquire::ForceIPv4 "true";` written to `/etc/apt/apt.conf.d/99force-ipv4` *at the start of the locale shell block, after the IPv6-fallback hits had already occurred* — too late; the warm-up's `apt-get update` had already paid the timeout
- Inline `-o Acquire::ForceIPv4=true -o Acquire::http::Timeout=20` on every apt invocation — the timeout=20 caused infinite-retry behavior under `-qq`, producing a silent 20-min hang
- `python3-minimal` instead of `python3` — strips the stdlib, dotbot's `import json` raises ModuleNotFoundError. Documented in `ci/Dockerfile`'s comment block; mentioned here only because it tempts every "minimize the image size" review

## Sites where this pattern lives

- `ci/Dockerfile` — the apt-conf-d write lands here in PR step 1/2
- `.github/workflows/install-matrix.yml` — the warm-up step gets removed in PR step 2/2 once the new image digest is pinned
- `install-linux.conf.yaml` — the locale block's `apt-get update -qq` is restored to `-qq` in step 1/2 (it was unsuppressed for the diagnostic only)
