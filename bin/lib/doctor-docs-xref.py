import sys, os, re
try:
    repo = sys.argv[1]
    top_entries = set(os.listdir(repo))   # every real top-level name (dirs + files)
    bt = chr(96)                           # backtick, kept out of the source literally
    fence = re.compile(bt * 3 + r'.*?' + bt * 3, re.DOTALL)   # strip fenced blocks first
    pat = re.compile(bt + r'([^' + bt + r']+)' + bt)          # then inline path spans
    missing = set()
    for df in sys.argv[2:]:
        p = os.path.join(repo, df)
        if not os.path.exists(p):
            continue
        text = fence.sub('', open(p, encoding="utf-8", errors="replace").read())
        for tok in pat.findall(text):
            tok = tok.strip()
            if "/" not in tok:
                continue
            if any(c in tok for c in "<>*$~ ") or "…" in tok:
                continue
            explicit = tok.startswith("./")   # a ./-prefix is an unambiguous path ref
            rel = (tok[2:] if explicit else tok).rstrip("/")
            if not explicit and rel.split("/", 1)[0] not in top_entries:
                continue                       # first segment isn't a repo entry → prose
            if not os.path.exists(os.path.join(repo, rel)):
                missing.add(rel)
    for m in sorted(missing):
        print(m)
except Exception as e:
    sys.stderr.write("PARSER_ERROR %r\n" % (e,)); sys.exit(1)
