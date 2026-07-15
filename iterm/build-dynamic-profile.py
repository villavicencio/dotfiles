#!/usr/bin/env python3
"""Extract the intentional iTerm2 profile prefs into a Dynamic Profile JSON,
stripping PII / machine / session-specific keys."""
import getpass
import json
import math
import os
import plistlib
import socket
import sys

PLIST = os.environ.get("ITERM_PLIST", "iterm/com.googlecode.iterm2.plist")
OUT = "iterm/profile-dynamic.json"
# App-level (not profile-scoped) settings a Dynamic Profile cannot carry. Kept
# here PII-free so a fresh machine can restore them manually via
# helpers/restore-iterm-app-prefs.sh (see iterm/README.md); they are key codes
# and action numbers only.
OUT_APP = "iterm/iterm2-app-keymap.json"
APP_KEYS = ("GlobalKeyMap", "PointerActions")

# A stable Guid for the dynamic profile (dynamic profiles need a unique, stable
# Guid; a fixed one keeps iTerm tracking the same profile across regenerations).
DYNAMIC_GUID = "DFA17E00-D07F-11E5-DF17-DF17DF17DF17"
PROFILE_NAME = "Dotfiles"

# Keys carrying identity / PII / machine / session state — never record these.
DROP_KEYS = {
    "Working Directory",        # was the owner's live home path
    "Custom Directory",
    "Custom Command",
    "Command",                  # session command
    "Initial Text",
    "Custom Window Title",
    "Use Custom Window Title",
    "Shortcut",
    "Tags",
    "Default Bookmark",
    "Description",
    "Name",                     # set explicitly below
    "Guid",                     # set explicitly below
    # Advanced Working Directory Settings — can carry paths
    "AWDS Pane Directory", "AWDS Pane Option",
    "AWDS Tab Directory", "AWDS Tab Option",
    "AWDS Window Directory", "AWDS Window Option",
}


def sanitize(v):
    """Recursively make v strict-JSON-safe. iTerm stores unbounded values as
    `Infinity` (e.g. status-bar `maxwidth`), which Python's json writes as the
    bare `Infinity` token — invalid JSON that iTerm's parser rejects. Convert
    non-finite floats to large finite values; drop <data> (bytes) blobs."""
    if isinstance(v, bool):
        return v
    if isinstance(v, float):
        if math.isnan(v):
            return 0.0
        if math.isinf(v):
            return 1e9 if v > 0 else -1e9
        return v
    if isinstance(v, dict):
        return {k: sanitize(x) for k, x in v.items()}
    if isinstance(v, (list, tuple)):
        return [sanitize(x) for x in v]
    if isinstance(v, (bytes, bytearray)):
        return None   # signal: drop this key
    return v


def jsonable(v):
    """Sanitize v and return it if it round-trips through STRICT JSON; else None."""
    s = sanitize(v)
    try:
        json.dumps(s, allow_nan=False)   # allow_nan=False => reject inf/nan
        return s
    except (TypeError, ValueError):
        return None


def main():
    with open(PLIST, "rb") as f:
        d = plistlib.load(f)
    src = d["New Bookmarks"][0]  # the Default profile
    prof = {"Name": PROFILE_NAME, "Guid": DYNAMIC_GUID}
    for k in sorted(src):
        if k in DROP_KEYS:
            continue
        val = jsonable(src[k])
        if val is None:
            print(f"  dropped non-JSON key: {k}", file=sys.stderr)
            continue
        prof[k] = val
    doc = {"Profiles": [prof]}
    with open(OUT, "w") as f:
        json.dump(doc, f, indent=2, sort_keys=True, allow_nan=False)
        f.write("\n")
    print(f"wrote {OUT}: {len(prof)} profile keys")

    # Strict JSON validation: reject the Infinity/NaN extension that iTerm's
    # parser would choke on (parse_constant fires on those tokens).
    def _reject(tok):
        raise ValueError("non-strict JSON constant: " + tok)
    with open(OUT) as f:
        json.load(f, parse_constant=_reject)
    print("strict JSON: valid")

    # App-level keymap / pointer-action sidecar (Dynamic Profiles can't hold
    # these). Sanitized + strict JSON, same as the profile.
    app = {}
    for k in APP_KEYS:
        v = jsonable(d.get(k, {}))
        app[k] = v if v is not None else {}
    with open(OUT_APP, "w") as f:
        json.dump(app, f, indent=2, sort_keys=True, allow_nan=False)
        f.write("\n")
    with open(OUT_APP) as f:
        json.load(f, parse_constant=_reject)
    print(f"wrote {OUT_APP}: {sum(len(v) for v in app.values())} app-level entries")

    # PII assertion on BOTH written files. The machine-specific tokens are
    # derived at runtime (never hardcoded) so this file carries no PII of its
    # own: the current login name, the short + FQDN hostname, and the owner's
    # home directory. Plus the generic "/Users/" home-path prefix.
    user = getpass.getuser()
    host = socket.gethostname()
    tokens = {"/Users/", user, host, host.split(".")[0], os.path.expanduser("~")}
    tokens = {t for t in tokens if t}  # drop any empty
    for path in (OUT, OUT_APP):
        text = open(path).read()
        bad = sorted(t for t in tokens if t in text)
        if bad:
            print(f"PII LEAK: found {bad} in {path}", file=sys.stderr)
            sys.exit(1)
    print(f"PII check: clean ({len(tokens)} tokens checked) in both files")


if __name__ == "__main__":
    main()
