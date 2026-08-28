#!/usr/bin/env python3
"""Remove allow-rules that a broader rule for the same binary already grants.

A Claude Code `settings.local.json` accretes one allow-rule per prompt-time
approval and never garbage-collects. Once a broad `Bash(cmd:*)` exists, every
narrower rule for that same binary grants nothing — deleting them changes the
real permission surface by exactly zero while making the surface that IS granted
legible. Measured 2026-08-27 on `~/Projects/agents`: 77 of 221 rules were dead
this way, 36 of them one-off `scp` pushes.

Scope, deliberately narrow — this tool ONLY deletes subsumed rules:
  * It never rewrites, normalizes, reorders, or broadens a rule.
  * It never touches the broad grants themselves. Whether `Bash(ssh:*)` should
    exist is a judgement call for a human, and this tool does not make it.
  * It never touches a rule that is not subsumed — dead paths and malformed
    entries are left alone, since "unparseable" and "safe to delete" differ.

**Credential-bearing rules are skipped, by design.** A `curl` rule approved at
prompt time can carry the Authorization header it was approved with, so the
allowlist becomes a plaintext secret store. Deleting such a rule does not
un-disclose the secret — only rotation does — and deleting it quietly would
destroy the evidence of what needs rotating. They are reported and left in place.
This is also why the tool derives its removal set at runtime and hardcodes no
rule text: a pruner with rule literals in it would copy those secrets into a
tracked file.

Usage:
    prune-subsumed-perms.py <settings.json>            # report only (default)
    prune-subsumed-perms.py <settings.json> --apply    # rewrite, after a backup
"""
import json
import os
import re
import shutil
import sys
from collections import defaultdict

# Shapes that grant a family rather than one invocation.
BROAD = ("prefix", "space-star")

# Detectors for secrets that must never be silently deleted or reproduced.
# Deliberately broad: a false positive only means a rule is *kept*.
CREDENTIAL_PATTERNS = [
    ("anthropic-admin-key", re.compile(r"sk-ant-admin\d{2}-[A-Za-z0-9_\-]{20,}")),
    ("anthropic-api-key", re.compile(r"sk-ant-api\d{2}-[A-Za-z0-9_\-]{20,}")),
    ("discord-bot-token",
     re.compile(r"Bot\s+[A-Za-z0-9_\-]{20,}\.[A-Za-z0-9_\-]{5,}\.[A-Za-z0-9_\-]{20,}")),
    ("bearer-token", re.compile(r"Bearer\s+[A-Za-z0-9_\-.]{30,}")),
    ("github-token", re.compile(r"gh[pousr]_[A-Za-z0-9]{30,}")),
    ("aws-access-key", re.compile(r"AKIA[0-9A-Z]{16}")),
    ("generic-api-key",
     re.compile(r"(?i)\b(?:api[_-]?key|secret|password|token)\b\s*[:=]\s*['\"]?[A-Za-z0-9_\-]{24,}")),
]


def credentials_in(text):
    """Names of credential types present. Never returns the secret itself."""
    return sorted({name for name, pat in CREDENTIAL_PATTERNS if pat.search(text)})


def bash_inner(rule):
    m = re.match(r"^Bash\((.*)\)$", rule, re.S)
    return m.group(1) if m else None


def binary_of(inner):
    """The binary a rule governs. `sudo foo` keys as `sudo foo`, not `sudo`."""
    tokens = inner.split(":")[0].strip().split()
    if not tokens:
        return None
    head = os.path.basename(tokens[0].strip("'\""))
    if head in ("sudo", "doas") and len(tokens) > 1:
        return f"{head} {os.path.basename(tokens[1].strip(chr(39) + chr(34)))}"
    return head


def shape_of(inner):
    if inner.endswith(":*"):
        return "prefix"          # Bash(cmd:*) — the idiomatic prefix match
    if re.search(r"\s\*$", inner):
        return "space-star"      # Bash(cmd *) — broad, and NOT the prefix idiom
    return "narrow"


def classify(allow):
    """(index -> (binary, shape)) for parseable Bash rules only."""
    out = {}
    for i, rule in enumerate(allow):
        inner = bash_inner(rule)
        if inner is None:
            continue
        b = binary_of(inner)
        if b:
            out[i] = (b, shape_of(inner))
    return out


def subsumed_indices(allow):
    """Indices of narrow rules that a broad rule for the same binary covers."""
    info = classify(allow)
    broad_binaries = {b for _, (b, s) in info.items() if s in BROAD}
    return {i for i, (b, s) in info.items() if s == "narrow" and b in broad_binaries}


def detect_indent(raw):
    m = re.search(r"\n(\s+)\"", raw)
    return len(m.group(1)) if m else 2


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    apply_ = "--apply" in sys.argv
    if len(args) != 1:
        sys.exit(__doc__.strip().splitlines()[-3].strip())

    path = os.path.expanduser(args[0])
    raw = open(path, encoding="utf-8").read()
    data = json.loads(raw)
    allow = data.get("permissions", {}).get("allow")
    if allow is None:
        sys.exit(f"{path}: no permissions.allow array — nothing to do")

    doomed = subsumed_indices(allow)
    held = {i for i in doomed if credentials_in(allow[i])}
    doomed -= held

    # Order is preserved: the kept list is the original filtered in place.
    kept = [r for i, r in enumerate(allow) if i not in doomed]

    print(f"file    {path}")
    print(f"rules   {len(allow)}")
    print(f"subsumed{'':<1} {len(doomed) + len(held)} "
          f"(removable {len(doomed)}, held for credentials {len(held)})")
    print(f"result  {len(allow)} -> {len(kept)}")

    by_bin = defaultdict(int)
    for i in doomed:
        by_bin[binary_of(bash_inner(allow[i]))] += 1
    if by_bin:
        print("\nremovable, by binary:")
        for b, n in sorted(by_bin.items(), key=lambda x: (-x[1], x[0])):
            print(f"  {n:3}  {b}")

    if held:
        print(f"\nHELD ({len(held)}) — subsumed but carrying credentials. NOT removed.")
        print("  Deleting these does not un-disclose the secret; rotate first, then")
        print("  remove them by hand. Types present (values never printed):")
        types = defaultdict(int)
        for i in held:
            for t in credentials_in(allow[i]):
                types[t] += 1
        for t, n in sorted(types.items()):
            print(f"    {n:3}  {t}")

    if not apply_:
        print("\n(report only — pass --apply to rewrite, which backs up first)")
        return 0
    if not doomed:
        print("\nnothing removable")
        return 0

    backup = path + ".bak-prune-subsumed"
    shutil.copy2(path, backup)
    data["permissions"]["allow"] = kept
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=detect_indent(raw))
        if raw.endswith("\n"):
            f.write("\n")
    print(f"\nremoved {len(doomed)}; backup: {backup}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
