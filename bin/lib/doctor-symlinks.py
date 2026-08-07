import sys, os
cfgp, repo, mode = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    # System python3 has no PyYAML; use dotbot's vendored copy (same as the docs
    # index generator) so this check actually runs instead of silently passing.
    sys.path.insert(0, os.path.join(repo, "dotbot", "lib", "pyyaml", "lib"))
    import yaml
    doc = yaml.safe_load(open(cfgp))
    if not isinstance(doc, list):
        print("PARSER_ERROR", os.path.basename(cfgp), "top-level is not a list"); sys.exit(1)
    links = 0
    for block in doc:
        if not isinstance(block, dict) or "link" not in block: continue
        entries = block["link"] or {}
        if not isinstance(entries, dict):
            print("PARSER_ERROR", os.path.basename(cfgp), "link block is not a mapping"); sys.exit(1)
        for target, v in entries.items():
            links += 1
            src = v["path"] if isinstance(v, dict) else v
            srcabs = os.path.join(repo, src)
            if not os.path.exists(srcabs):
                print("MISSING_SOURCE", src); continue
            if mode != "full":
                continue                      # inactive config: source integrity only
            t = os.path.expanduser(target)
            if not os.path.lexists(t):
                continue                      # not installed yet — fine
            if os.path.islink(t) and not os.path.exists(t):
                print("DANGLING_SYMLINK", target); continue
            if not os.path.islink(t):
                print("CONFLICTING_FILE", target); continue   # regular file blocks relink
            if not os.path.samefile(t, srcabs):
                print("WRONG_TARGET", target)                 # symlink to a different source
    print("LINKS", links)
except SystemExit:
    raise
except Exception as e:
    print("PARSER_ERROR", os.path.basename(cfgp), repr(e)[:80]); sys.exit(1)
