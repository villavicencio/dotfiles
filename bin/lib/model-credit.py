#!/usr/bin/env python3
"""model-credit VIL-N: which model gets a ticket's `model` label.

Run through bin/model-credit. The rule it applies is docs/agents/tickets.md, "Model credit".
It only reads: Linear (the ticket's creation time and its PR attachments), GitHub through
`gh api`, and the local clone (for a local merge's own changes). It changes nothing, so it has
no DOTFILES_DRY_RUN guard.

Where the work comes from, for each repo searched (the repos of the ticket's Linear PR
attachments, the current clone's origin, and each --repo):
  * merged PRs: the ones attached to the ticket in Linear, plus every merged PR whose title,
    body or head branch names the ticket id (an exact match: VIL-85 doesn't match VIL-852).
    Closed PRs are read newest-updated first, back to the ticket's creation.
  * no-PR work on the default branch (read from GitHub, not from what's checked out): commits
    whose message names the id and that no merged PR landed, and local merges whose message
    names the id. A local merge counts the commits it brought in (named or not) and its own
    changes (`git show --remerge-diff`, when the local clone has the commit).

Test hooks, for ci/model-credit-checks.sh only: MODEL_CREDIT_LINEAR_FIXTURE (a file holding
the Linear GraphQL response, read instead of calling Linear) and MODEL_CREDIT_PER_PAGE (the
GitHub page size). `gh` is found on PATH, so the checks put a fake one first.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta

LINEAR_URL = "https://api.linear.app/graphql"
LINEAR_KEY_REF = "op://Agents/linear-api/password"
LINEAR_QUERY = (
    "query($id: String!) { issue(id: $id) { identifier createdAt "
    "attachments(first: 250) { pageInfo { hasNextPage } nodes { url } } } }"
)
PER_PAGE = int(os.environ.get("MODEL_CREDIT_PER_PAGE", "100"))
MAX_PAGES = 500
# A commit's date can trail the ticket's creation (an amend keeps the author date), so the
# default-branch listing starts this long before the ticket was created.
SINCE_MARGIN = timedelta(days=30)
PR_URL = re.compile(r"^https://github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)/pull/(\d+)(?:[/?#].*)?$")
REPO_SLUG = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
TRAILER = re.compile(r"^(co-authored-by|worker-model)\s*:\s*(.*?)\s*$", re.I)


class Fail(Exception):
    pass


def parse_dt(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00"))


def iso(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def id_pattern(ticket):
    # Not preceded by a letter or digit, not followed by a digit: VIL-85 matches
    # `feat/vil-85-x` and `(VIL-85)`, not `VIL-852`.
    return re.compile(r"(?<![A-Za-z0-9])" + re.escape(ticket) + r"(?![0-9])", re.I)


def label_of(name):
    return re.sub(r"[ .]", "-", name.lower())


def models_of(message):
    """{label: name} from the Co-Authored-By / Worker-Model trailers in the message's last
    paragraph (where git puts trailers). The name drops a trailing <email>."""
    paras = [p for p in re.split(r"\n\s*\n", message.strip()) if p.strip()]
    found = {}
    if len(paras) < 2:
        return found
    for line in paras[-1].splitlines():
        m = TRAILER.match(line.strip())
        if not m:
            continue
        name = re.sub(r"\s*<[^>]*>\s*$", "", m.group(2)).strip()
        if name:
            found.setdefault(label_of(name), name)
    return found


# --- GitHub, through gh ------------------------------------------------------------------

def gh_api(path):
    try:
        p = subprocess.run(["gh", "api", path], capture_output=True, text=True)
    except FileNotFoundError:
        raise Fail("gh is not installed")
    if p.returncode != 0:
        err = next((l for l in p.stderr.splitlines() if l.strip()), "no message")
        raise Fail(f"gh api {path}: {err}")
    return json.loads(p.stdout)


def pages(path, key=None):
    """Every item of a paged GitHub list (or of data[key] for an object response)."""
    sep = "&" if "?" in path else "?"
    for page in range(1, MAX_PAGES + 1):
        data = gh_api(f"{path}{sep}per_page={PER_PAGE}&page={page}")
        items = (data.get(key) or []) if key else data
        yield from items
        if len(items) < PER_PAGE:
            return
    raise Fail(f"gh api {path}: more than {MAX_PAGES} pages")


_commit_cache = {}


def commit_detail(slug, sha):
    if (slug, sha) not in _commit_cache:
        _commit_cache[(slug, sha)] = gh_api(f"repos/{slug}/commits/{sha}")
    return _commit_cache[(slug, sha)]


# --- Linear -------------------------------------------------------------------------------

def read_linear_key():
    if not shutil.which("op-agent"):
        raise Fail("op-agent is not on PATH (docs/agents/1password.md); --no-linear skips Linear")
    d = tempfile.mkdtemp(prefix="model-credit.")
    try:
        f = os.path.join(d, "key")
        p = subprocess.run(["op-agent", "read", "-f", "-o", f, LINEAR_KEY_REF],
                           capture_output=True, text=True)
        if p.returncode != 0 or not os.path.isfile(f):
            err = next((l for l in p.stderr.splitlines() if l.strip()), "no message")
            raise Fail(f"op-agent couldn't read {LINEAR_KEY_REF}: {err}")
        with open(f) as fh:
            key = fh.read().strip()
    finally:
        shutil.rmtree(d, ignore_errors=True)
    if not key:
        raise Fail(f"{LINEAR_KEY_REF} is empty")
    return key


def linear_issue(ticket):
    fixture = os.environ.get("MODEL_CREDIT_LINEAR_FIXTURE")
    if fixture:
        with open(fixture) as fh:
            data = json.load(fh)
    else:
        body = json.dumps({"query": LINEAR_QUERY, "variables": {"id": ticket}}).encode()
        req = urllib.request.Request(LINEAR_URL, data=body, headers={
            "Authorization": read_linear_key(), "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                data = json.load(r)
        except urllib.error.HTTPError as e:
            raise Fail(f"Linear API: HTTP {e.code}")
        except urllib.error.URLError as e:
            raise Fail(f"Linear API: {e.reason}")
    if data.get("errors"):
        raise Fail("Linear API: " + "; ".join(e.get("message", "?") for e in data["errors"]))
    issue = (data.get("data") or {}).get("issue")
    if not issue:
        raise Fail(f"Linear has no issue {ticket}")
    return issue


# --- local git ----------------------------------------------------------------------------

def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True)


def current_repo():
    p = git("remote", "get-url", "origin")
    if p.returncode != 0:
        return None
    m = re.search(r"github\.com[:/]+([^/]+/[^/]+?)(?:\.git)?/?$", p.stdout.strip())
    return m.group(1) if m else None


def remerge_lines(sha):
    """Lines a merge changed beyond git's own merge of its parents, or None if the local
    clone doesn't have the commit."""
    if git("cat-file", "-e", sha + "^{commit}").returncode != 0:
        return None
    p = git("show", "--remerge-diff", "--format=", "--numstat", sha)
    if p.returncode != 0:
        return None
    total = 0
    for line in p.stdout.splitlines():
        parts = line.split("\t")
        if len(parts) >= 3:
            total += sum(int(x) for x in parts[:2] if x.isdigit())
    return total


# --- the count ----------------------------------------------------------------------------

class Credit:
    def __init__(self):
        self.counted = {}   # (slug, sha) -> record
        self.skipped = []   # (slug, sha, where, reason)
        self.notes = []

    def add(self, slug, sha, where, lines=None, message=None, date=None):
        key = (slug, sha if lines is None else sha + ":own")
        if key in self.counted:
            self.counted[key]["where"] += f"; also {where}"
            return
        if lines is None:
            d = commit_detail(slug, sha)
            lines = d["stats"]["total"]
            message = d["commit"]["message"]
            date = d["commit"]["committer"]["date"]
        self.counted[key] = {
            "slug": slug, "sha": sha, "where": where, "lines": lines, "date": date,
            "subject": message.splitlines()[0] if message else "",
            "models": models_of(message), "order": len(self.counted),
        }

    def skip(self, slug, sha, where, reason):
        self.skipped.append((slug, sha, where, reason))


def find_repos(args, issue):
    repos = {}

    def add(slug, why):
        repos.setdefault(slug, [])
        if why not in repos[slug]:
            repos[slug].append(why)

    attached, other = [], []
    if issue:
        for node in issue["attachments"]["nodes"]:
            m = PR_URL.match(node.get("url") or "")
            if m:
                attached.append((m.group(1), int(m.group(2))))
                add(m.group(1), "Linear attachment")
            else:
                other.append(node.get("url") or "?")
    cur = current_repo()
    if cur:
        add(cur, "current clone")
    for r in args.repo:
        add(r, "--repo")
    return repos, attached, other, cur


def find_prs(repos, attached, idre, created, credit):
    prs = {}
    for slug in repos:
        for pr in pages(f"repos/{slug}/pulls?state=closed&sort=updated&direction=desc"):
            if created and parse_dt(pr["updated_at"]) < created:
                break
            if not pr.get("merged_at"):
                continue
            how = [k for k, v in (("title", pr.get("title")), ("body", pr.get("body")),
                                  ("branch", pr["head"]["ref"])) if v and idre.search(v)]
            if how:
                prs[(slug, pr["number"])] = {"pr": pr, "found": how}
    for slug, n in attached:
        if (slug, n) not in prs:
            prs[(slug, n)] = {"pr": gh_api(f"repos/{slug}/pulls/{n}"), "found": []}
        prs[(slug, n)]["found"].insert(0, "Linear attachment")
    return prs


def count_prs(prs, credit):
    for (slug, n), rec in sorted(prs.items()):
        where = f"{slug}#{n}"
        if not rec["pr"].get("merged_at"):
            credit.skip(slug, "", where, "PR not merged")
            continue
        commits = list(pages(f"repos/{slug}/pulls/{n}/commits"))
        if len(commits) >= 250:
            credit.notes.append(f"{where} has 250 or more commits; GitHub lists only the first "
                                "250, so this count can be short")
        in_pr = {c["sha"] for c in commits}
        for c in commits:
            if len(c["parents"]) > 1:
                outside = [p["sha"] for p in c["parents"][1:] if p["sha"] not in in_pr]
                credit.skip(slug, c["sha"], where, "merge of the base branch into the PR" if outside
                            else "merge inside the PR (the commits it merges are counted)")
                continue
            credit.add(slug, c["sha"], where)


def count_default_branch(slug, idre, created, prs, cur, credit):
    branch = gh_api(f"repos/{slug}")["default_branch"]
    q = urllib.parse.quote(branch, safe="")
    tip = commit_detail(slug, q)["sha"]
    path = f"repos/{slug}/commits?sha={q}"
    if created:
        path += f"&since={iso(created - SINCE_MARGIN)}"
    listing = list(pages(path))
    by_sha = {c["sha"]: c for c in listing}
    first_parent, s = set(), tip
    while s in by_sha and s not in first_parent:
        first_parent.add(s)
        ps = by_sha[s]["parents"]
        s = ps[0]["sha"] if ps else None
    named = [c for c in listing if idre.search(c["commit"]["message"])]
    named.sort(key=lambda c: parse_dt(c["commit"]["committer"]["date"]))
    counted_prs = {n for (sl, n), rec in prs.items() if sl == slug and rec["pr"].get("merged_at")}

    def landed_by(sha):
        return sorted(p["number"] for p in gh_api(f"repos/{slug}/commits/{sha}/pulls")
                      if p.get("merged_at"))

    def pr_skip(sha, where, nums):
        for n in nums:
            tail = "counted above" if n in counted_prs else "that PR isn't linked to the ticket"
            credit.skip(slug, sha, where, f"lands PR #{n}; {tail}")

    # Local merges first, so a named commit they bring in is counted once, as theirs.
    for c in [c for c in named if len(c["parents"]) > 1]:
        sha, where = c["sha"], f"{slug} {branch}"
        if sha not in first_parent:
            credit.skip(slug, sha, where, f"merge into a branch, not into {branch}")
            continue
        nums = landed_by(sha)
        if nums:
            pr_skip(sha, where, nums)
            continue
        mwhere = f"{slug} local merge {sha[:7]} into {branch}"
        p1, p2 = c["parents"][0]["sha"], c["parents"][1]["sha"]
        if len(c["parents"]) > 2:
            credit.notes.append(f"{sha[:7]} is an octopus merge; only its second parent's "
                                "commits are counted")
        cmp_path = f"repos/{slug}/compare/{p1}...{p2}"
        total = gh_api(f"{cmp_path}?per_page=1&page=1").get("total_commits", 0)
        brought = list(pages(cmp_path, key="commits"))
        if len(brought) < total:
            credit.notes.append(f"{mwhere}: GitHub listed {len(brought)} of {total} commits")
        for b in brought:
            if len(b["parents"]) > 1:
                credit.skip(slug, b["sha"], mwhere, "merge inside the merged branch")
            else:
                credit.add(slug, b["sha"], mwhere)
        own = remerge_lines(sha) if slug == cur else None
        if own is None:
            why = "no local clone of this repo" if slug != cur else \
                "the local clone lacks the commit (git fetch origin)"
            credit.skip(slug, sha, mwhere, f"the merge's own changes not measured: {why}")
        elif own == 0:
            credit.skip(slug, sha, mwhere, "the merge itself changed nothing beyond git's merge")
        else:
            credit.add(slug, sha, f"{mwhere} (its own changes, remerge-diff)", lines=own,
                       message=c["commit"]["message"], date=c["commit"]["committer"]["date"])
    for c in [c for c in named if len(c["parents"]) <= 1]:
        sha, where = c["sha"], f"{slug} {branch}"
        if (slug, sha) in credit.counted:
            continue
        nums = landed_by(sha)
        if nums:
            pr_skip(sha, where, nums)
        else:
            credit.add(slug, sha, f"{slug} no-PR commit on {branch}")


def decide(credit):
    rows = sorted(credit.counted.values(), key=lambda r: (parse_dt(r["date"]), r["order"]))
    per, newest, names = {}, {}, {}
    nobody = {"no model trailer": 0, "two or more models": 0}
    for i, r in enumerate(rows):
        if len(r["models"]) == 1:
            (lab, name), = r["models"].items()
            per[lab] = per.get(lab, 0) + r["lines"]
            newest[lab] = i
            names.setdefault(lab, name)
        else:
            nobody["no model trailer" if not r["models"] else "two or more models"] += r["lines"]
    nobody_total = sum(nobody.values())
    if not per:
        return rows, per, newest, names, nobody, None, "no counted commit names a model"
    top = max(per, key=lambda lab: (per[lab], newest[lab]))
    if per[top] == 0:
        return rows, per, newest, names, nobody, None, "no model has any lines"
    if nobody_total > per[top]:
        return rows, per, newest, names, nobody, None, (
            f"lines in commits that name no model ({nobody_total}) are more than "
            f"{top}'s ({per[top]})")
    return rows, per, newest, names, nobody, top, None


def main(argv):
    ap = argparse.ArgumentParser(prog="model-credit", description=(
        "Print the lines each model changed in a ticket's merged work, and the `model` label "
        "the rule in docs/agents/tickets.md (\"Model credit\") gives it."))
    ap.add_argument("ticket", help="Linear ticket id, e.g. VIL-852")
    ap.add_argument("--repo", action="append", default=[], metavar="OWNER/NAME",
                    help="also search this GitHub repo (repeatable)")
    ap.add_argument("--no-linear", action="store_true",
                    help="don't read Linear: no PR attachments, and no start date for the search")
    args = ap.parse_args(argv)
    if not re.match(r"^[A-Za-z]+-[0-9]+$", args.ticket):
        ap.error(f"not a ticket id: {args.ticket}")
    for r in args.repo:
        if not REPO_SLUG.match(r):
            ap.error(f"--repo wants owner/name, not {r}")
    ticket = args.ticket.upper()
    idre = id_pattern(ticket)

    issue = None if args.no_linear else linear_issue(ticket)
    created = parse_dt(issue["createdAt"]) if issue else None
    repos, attached, other, cur = find_repos(args, issue)
    if not repos:
        raise Fail("no repo to search: no Linear PR attachment, no GitHub origin here, no --repo")

    credit = Credit()
    prs = find_prs(repos, attached, idre, created, credit)
    count_prs(prs, credit)
    for slug in repos:
        count_default_branch(slug, idre, created, prs, cur, credit)
    rows, per, newest, names, nobody, label, why = decide(credit)

    out = [f"model-credit {ticket}"]
    if issue:
        pr_list = ", ".join(f"{s}#{n}" for s, n in attached) or "none"
        out.append(f"Linear: created {issue['createdAt']}; PR attachments: {pr_list}")
        if issue["attachments"].get("pageInfo", {}).get("hasNextPage"):
            out.append("  ! Linear has more than 250 attachments; only the first 250 were read")
        for u in other:
            out.append(f"  other attachment, not a GitHub PR (ignored): {u}")
    else:
        out.append("Linear: not read (--no-linear): no PR attachments, and the search has no "
                   "start date")
    out.append("Repos searched (merged PRs, and no-PR work on the default branch):")
    for slug, why_list in repos.items():
        out.append(f"  {slug}  ({', '.join(why_list)})")
    out.append("")
    out.append("PRs counted:" if prs else "PRs counted: none")
    for (slug, n), rec in sorted(prs.items()):
        state = "merged" if rec["pr"].get("merged_at") else "NOT merged, skipped"
        out.append(f"  {slug}#{n}  {state}  found by: {', '.join(rec['found'])}  "
                   f"\"{rec['pr'].get('title', '')}\"")
    out.append("")
    out.append("Commits counted (oldest first, by committer date):" if rows else
               "Commits counted: none")
    for r in rows:
        who = ", ".join(r["models"].values()) or "no model"
        if len(r["models"]) > 1:
            who += " (two or more models: credited to nobody)"
        out.append(f"  {r['date']}  {r['sha'][:7]}  {r['lines']:>6} lines  {who}")
        out.append(f"      from {r['where']}: {r['subject']}")
    if credit.skipped:
        out.append("")
        out.append("Skipped:")
        for slug, sha, where, reason in credit.skipped:
            out.append(f"  {sha[:7] or '-':7}  {where}: {reason}")
    if credit.notes:
        out.append("")
        for n in credit.notes:
            out.append(f"  ! {n}")
    out.append("")
    out.append("Lines per model:")
    order = sorted(per, key=lambda lab: (-per[lab], -newest[lab]))
    for lab in order:
        out.append(f"  {lab:<30} {per[lab]:>6} lines  (as \"{names[lab]}\"; newest commit "
                   f"{rows[newest[lab]]['date']})")
    for k, v in nobody.items():
        out.append(f"  {'(nobody: ' + k + ')':<30} {v:>6} lines")
    out.append("")
    out.append(f"Label: {label}" if label else f"Label: no label: {why}")
    print("\n".join(out))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Fail as e:
        print(f"model-credit: {e}", file=sys.stderr)
        sys.exit(1)
