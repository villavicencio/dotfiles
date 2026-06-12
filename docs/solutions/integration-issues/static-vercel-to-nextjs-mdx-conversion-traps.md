---
title: "Static-to-Next.js Vercel conversion — three config traps (NODE_ENV, framework preset, MDX GFM)"
date: 2026-06-12
category: integration-issues
module: davidv.sh
problem_type: integration_issue
component: tooling
symptoms:
  - "`next build` compiles, then crashes prerendering `/_global-error` with `TypeError: Cannot read properties of null (reading 'useContext')` plus a React key-prop warning flood"
  - "Build log warnings: non-standard NODE_ENV value, and Next.js inferred workspace root as $HOME (stray ~/yarn.lock)"
  - "Deployment READY but production serves platform errors: `x-vercel-error: NOT_FOUND` on /, MIDDLEWARE_INVOCATION_FAILED (500) on middleware routes"
  - "MDX pages render GFM pipe tables as literal `| Frequency | Tasks |` paragraph text instead of <table> elements"
  - "MDX build fails with 'Expected the closing tag `</code>`' — two single `~` path references in one paragraph parsed as strikethrough across JSX boundaries"
root_cause: config_error
resolution_type: config_change
severity: high
related_components:
  - development_workflow
  - documentation
tags:
  - nextjs
  - vercel
  - mdx
  - remark-gfm
  - turbopack
  - node-env
  - framework-preset
  - x-vercel-error
---

# Static-to-Next.js Vercel conversion — three config traps (NODE_ENV, framework preset, MDX GFM)

## Problem

Converting an existing static Vercel project (plain `index.html` + `vercel.json`) to Next.js 16 + @next/mdx hit three independent, silently-failing traps: the machine's shell environment poisoned the build, the Vercel project's stale framework metadata broke serving, and MDX's CommonMark-only defaults broke both tables and tilde-heavy unix paths. None of the failures pointed at their actual cause, and none were in application code. (Context: the davidv.sh repo's `/ops` living-docs build, 2026-06-11/12.)

## Symptoms

**Trap 1 — local build crash during prerender.** `next build` compiles successfully, then dies prerendering `/_global-error`:

```
TypeError: Cannot read properties of null (reading 'useContext')
```

accompanied by a flood of React "unique key prop" warnings. Two tell-tale warnings appear earlier in the output and are the real clues:

```
⚠ You are using a non-standard "NODE_ENV" value
⚠ Next.js inferred your workspace root... selected /Users/<user>
  Detected additional lockfiles
```

(The second is caused by a stray `~/yarn.lock` at `$HOME`.)

**Trap 2 — deployed site 404s despite READY deployment.** After pushing the Next.js conversion, the Vercel deployment shows READY, but:

- `/` → 404 with header `x-vercel-error: NOT_FOUND` and body "The page could not be found NOT_FOUND" — a **platform** error page, not the Next.js 404
- the middleware-gated route → 500 with `x-vercel-error: MIDDLEWARE_INVOCATION_FAILED`
- `vercel.json` redirects (platform-level) still work — that contrast localizes the failure to "platform isn't serving the framework output," not DNS or routing

**Trap 3 — MDX content breakage, in two phases.**

- Phase A: GFM pipe tables (`| a | b |` with `| --- |` separator rows) render as literal paragraph text in MDX pages.
- Phase B (after enabling remark-gfm with defaults): a *different* MDX page fails the build:

```
Expected the closing tag `</code>` either after the end of `strikethrough`...
```

Triggered by two single `~` characters in one paragraph (`~/.npm-global` … `~/.local/bin`) — common in ops docs.

## What Didn't Work

- **Hunting for duplicate React.** The `useContext`-on-null crash is the classic two-Reacts signature, so the first move was `npm ls react react-dom next` — everything deduped (next@16.2.9, react@19.2.7). Dead end; the dev/prod React mixing came from `NODE_ENV`, not from duplicate packages.
- **Trusting "deployment READY."** The dashboard reported a successful deployment, which steered debugging toward app code and middleware. READY only means the build artifact deployed — it says nothing about whether the platform knows how to *serve* it. The `x-vercel-error` headers were the actual signal.
- **Treating the table breakage as an MDX syntax problem.** The tables were valid GFM; the pipeline simply doesn't speak GFM by default.

## Solution

Check these in order when a static-to-Next.js conversion misbehaves:

**1. Make the build immune to machine environment.** Root cause: this dotfiles repo's `zsh/zshenv` exports `NODE_ENV=development` globally. `next build` under `NODE_ENV=development` mixes dev and prod React during prerender, producing the `useContext` null crash. Separately, a stray `~/yarn.lock` wins Next's workspace-root inference and pulls the root up to `$HOME`.

```jsonc
// package.json
"scripts": {
  "build": "NODE_ENV=production next build"
}
```

```ts
// next.config.ts
const nextConfig = {
  turbopack: { root: __dirname }, // stray ~/yarn.lock otherwise wins workspace-root inference
};
```

**2. Fix the Vercel project's framework preset.** Root cause: the project was created in the static era (CLI deploy of plain files), leaving project `framework: null`. The platform deployed the repo but never served `.next` output as a Next.js app — hence platform-level `NOT_FOUND` for pages and `MIDDLEWARE_INVOCATION_FAILED` for the middleware-gated route, while `vercel.json` redirects (handled before framework serving) kept working.

```
PATCH https://api.vercel.com/v9/projects/{id}?teamId=...
Authorization: Bearer <token>

{"framework": "nextjs"}
```

Then trigger a redeploy (empty commit push) — the setting applies at build/serve time, not retroactively. Verified: GET on the project shows `framework: "nextjs"`; both domains 200.

**3. Enable GFM in MDX — with `singleTilde` off.** Root cause A: pipe tables are a GFM extension; @next/mdx enables only CommonMark. Root cause B: `remark-gfm` defaults `singleTilde: true`, so two lone `~` characters in one paragraph parse as a strikethrough span (which then crosses JSX boundaries and breaks the build).

```bash
npm i remark-gfm
```

```ts
// next.config.ts
import createMDX from "@next/mdx";

const withMDX = createMDX({
  options: {
    // string form keeps plugin options serializable for Turbopack;
    // singleTilde off so ~/paths don't parse as strikethrough
    remarkPlugins: [["remark-gfm", { singleTilde: false }]],
  },
});

export default withMDX(nextConfig);
```

The string/tuple plugin specifier (not an imported function) is load-bearing: Turbopack requires serializable loader options. With `singleTilde: false`, only `~~double~~` triggers strikethrough.

Verification on built HTML: 3 `<table>` elements, 0 raw `| --- |` leaks, 0 `<del>` elements, tilde paths intact.

**Known leftover (not fixed):** Next 16 deprecates the `middleware.ts` convention in favor of "proxy"; still functional, just a warning.

## Why This Works

All three failures live at toolchain seams, not in app code:

- **Trap 1** is the *machine environment* leaking into the build. Next.js treats `NODE_ENV` as authoritative; a global shell export silently overrides the build's intended mode for every Node tool on the machine. Pinning `NODE_ENV=production` in the build script (and `turbopack.root` in config) makes the build reproducible regardless of which shell launched it.
- **Trap 2** is *stale platform metadata*. Vercel's framework preset is project-level state set at creation time; converting the repo's stack doesn't update it. The deployment pipeline succeeded mechanically while the serving layer had no idea a framework existed.
- **Trap 3** is a *default-off extension*. MDX is CommonMark-first; GFM features (tables, strikethrough) are opt-in, and one of GFM's own defaults (`singleTilde`) is hostile to documentation full of unix home-directory paths.

The unifying lesson: a stack conversion changes the app, but the build host, the platform project record, and the markdown pipeline each carry independent configuration that must be converted too.

## Prevention

- **Force `NODE_ENV=production` in the build script** of every Next.js project on this machine. It costs nothing and makes builds immune to machine-global exports. Longer-term: reconsider whether `export NODE_ENV=development` belongs in `zsh/zshenv` at all — it silently affects every Node tool on the machine (flagged 2026-06-11; removal still pending). Note: CLAUDE.md's "Node version" convention block documents `NODE_VERSION` but not this `NODE_ENV` export — this doc is currently the only place the footgun is written down.
- **Pin `turbopack.root` (or clean up stray lockfiles in `$HOME`)** whenever Next warns about inferred workspace root. The "Detected additional lockfiles" warning is actionable, not noise.
- **When converting a project's stack on Vercel, explicitly set the framework preset** (dashboard or `PATCH /v9/projects/{id}` with `{"framework": "nextjs"}`) and redeploy. Don't assume the git integration infers it.
- **Read `x-vercel-error` response headers before debugging app code.** `NOT_FOUND` / `MIDDLEWARE_INVOCATION_FAILED` at the platform layer mean the platform isn't running your app at all. The contrast test (do `vercel.json` redirects still work?) cheaply separates platform routing from framework serving.
- **Don't trust "deployment READY" as "site works."** Curl the production domain and check status + headers as the actual acceptance test.
- **Grep built HTML as a render test for MDX:** expect `<table>` elements, zero raw `| --- |` leaks, zero unexpected `<del>` elements. Catches both missing-GFM and overeager-strikethrough regressions mechanically.
- **Always pass `{ singleTilde: false }` to remark-gfm** in any docs site whose content mentions unix paths (`~/...`). Two single tildes in one paragraph is all it takes, and the failure surfaces on whatever page happens to contain them — possibly long after GFM was enabled.

## Related Issues

- `docs/solutions/code-quality/brew-shellenv-clobbers-path-via-path-helper.md` — sibling instance of the same pattern class: a global export in this repo's shell init silently altering external tool behavior (PATH ordering there, NODE_ENV here). Shared prevention rule: when a tool misbehaves only on this machine, audit `zsh/zshenv` exports first.
- `docs/solutions/code-quality/zsh-configuration-audit-19-issues.md` — the prior systematic zshenv review; it predates this finding (the `NODE_ENV=development` export was not flagged there).
- No related GitHub issues (searched).
