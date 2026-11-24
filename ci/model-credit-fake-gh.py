#!/usr/bin/env python3
"""A fake `gh api` for ci/model-credit-checks.sh: answers the GitHub REST calls that
bin/lib/model-credit.py makes, from local git repos instead of the network.

$FAKE_GH_ROOT/<owner>/<name>/ is a git repo standing in for github.com/<owner>/<name>.
Next to it:
  <name>.default    the default branch (one line)
  <name>.prs.json   the repo's closed PRs: [{number, title, body, head_ref, head, merge,
                    merged (default true), updated_at (default: the merge's date)}]
                    `head` and `merge` are revisions in the repo: the PR's last commit and
                    the commit that landed it (a squash commit, say). A PR's commits are
                    `head` minus the merge's first parent, as GitHub lists them.
Every call is appended to $FAKE_GH_ROOT/calls. An unknown call fails like a 404.
"""
import json
import os
import re
import subprocess
import sys
import urllib.parse

ROOT = os.environ["FAKE_GH_ROOT"]


def die(msg):
    print(f"gh: {msg}", file=sys.stderr)
    sys.exit(1)


def git(repo, *args):
    p = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True,
                       env={**os.environ, "TZ": "UTC"})
    if p.returncode != 0:
        die(f"Not Found (HTTP 404) [{' '.join(args)}: {p.stderr.strip()}]")
    return p.stdout


def rev(repo, r):
    return git(repo, "rev-parse", "--verify", r + "^{commit}").strip()


def commit_obj(repo, sha, stats=False):
    out = git(repo, "show", "-s", "--date=format-local:%Y-%m-%dT%H:%M:%SZ",
              "--format=%H%n%P%n%cd%n%B", sha)
    h, parents, date, msg = out.split("\n", 3)
    o = {"sha": h, "parents": [{"sha": p} for p in parents.split()],
         "commit": {"message": msg.rstrip("\n"), "committer": {"date": date}}}
    if stats:
        if parents:
            ns = git(repo, "diff", "--numstat", parents.split()[0], h)
        else:
            ns = git(repo, "show", "--numstat", "--format=", h)
        total = sum(int(x) for line in ns.splitlines() for x in line.split("\t")[:2] if x.isdigit())
        o["stats"] = {"total": total}
    return o


def prs(repo, owner_name):
    path = os.path.join(ROOT, owner_name + ".prs.json")
    if not os.path.exists(path):
        return []
    with open(path) as fh:
        raw = json.load(fh)
    out = []
    for p in raw:
        merged = p.get("merged", True)
        merge_sha = rev(repo, p["merge"]) if p.get("merge") else None
        date = commit_obj(repo, merge_sha)["commit"]["committer"]["date"] if merge_sha else None
        base = git(repo, "rev-parse", merge_sha + "^1").strip() if merge_sha else None
        shas = git(repo, "rev-list", "--reverse", "--topo-order", p["head"],
                   *(["^" + base] if base else [])).split()
        out.append({
            "number": p["number"], "title": p.get("title", ""), "body": p.get("body"),
            "head": {"ref": p["head_ref"]}, "base": {"ref": "main"},
            "merged_at": date if merged else None,
            "updated_at": p.get("updated_at") or date or "2026-01-01T00:00:00Z",
            "_merge": merge_sha if merged else None, "_commits": shas,
        })
    return out


def public(p):
    return {k: v for k, v in p.items() if not k.startswith("_")}


def paged(items, q):
    per = int(q.get("per_page", ["30"])[0])
    page = int(q.get("page", ["1"])[0])
    return items[(page - 1) * per: page * per]


def main(argv):
    if len(argv) != 2 or argv[0] != "api":
        die(f"fake gh only answers `gh api <path>`, not: {' '.join(argv)}")
    with open(os.path.join(ROOT, "calls"), "a") as fh:
        fh.write(argv[1] + "\n")
    u = urllib.parse.urlsplit(argv[1])
    q = urllib.parse.parse_qs(u.query)
    m = re.match(r"^repos/([^/]+/[^/]+)(/.*)?$", u.path)
    if not m:
        die("Not Found (HTTP 404)")
    owner_name, rest = m.group(1), m.group(2) or ""
    repo = os.path.join(ROOT, owner_name)
    if not os.path.isdir(repo):
        die("Not Found (HTTP 404)")
    default = open(os.path.join(ROOT, owner_name + ".default")).read().strip()

    if rest == "":
        return {"default_branch": default}
    if rest == "/pulls":
        items = sorted(prs(repo, owner_name), key=lambda p: p["updated_at"], reverse=True)
        return [public(p) for p in paged(items, q)]
    m = re.match(r"^/pulls/(\d+)(/commits)?$", rest)
    if m:
        p = next((p for p in prs(repo, owner_name) if p["number"] == int(m.group(1))), None)
        if not p:
            die("Not Found (HTTP 404)")
        if m.group(2):
            return [commit_obj(repo, s) for s in paged(p["_commits"], q)]
        return public(p)
    if rest == "/commits":
        args = ["rev-list", "--date-order", urllib.parse.unquote(q["sha"][0])]
        if "since" in q:
            args.append("--since=" + q["since"][0])
        return [commit_obj(repo, s) for s in paged(git(repo, *args).split(), q)]
    m = re.match(r"^/commits/([^/]+)/pulls$", rest)
    if m:
        sha = rev(repo, m.group(1))
        return [public(p) for p in prs(repo, owner_name)
                if p["_merge"] == sha or sha in p["_commits"]]
    m = re.match(r"^/commits/([^/]+)$", rest)
    if m:
        return commit_obj(repo, rev(repo, urllib.parse.unquote(m.group(1))), stats=True)
    m = re.match(r"^/compare/([0-9a-f]+)\.\.\.([0-9a-f]+)$", rest)
    if m:
        shas = git(repo, "rev-list", "--reverse", "--topo-order", m.group(2), "^" + m.group(1)).split()
        return {"total_commits": len(shas), "commits": [commit_obj(repo, s) for s in paged(shas, q)]}
    die("Not Found (HTTP 404)")


if __name__ == "__main__":
    print(json.dumps(main(sys.argv[1:])))
