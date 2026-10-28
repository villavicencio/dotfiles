import ast, sys

# argv: path to helpers/migrate_claude_settings.py, then STRIP_KEYS' words.
# Exit 1 when its MACHINE_LOCAL set differs from STRIP_KEYS.
try:
    tree = ast.parse(open(sys.argv[1], encoding="utf-8").read())
    found = None
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(
            isinstance(t, ast.Name) and t.id == "MACHINE_LOCAL" for t in node.targets
        ):
            found = set(ast.literal_eval(node.value))
    if found is None:
        print("no MACHINE_LOCAL assignment in %s" % sys.argv[1])
        sys.exit(1)
    strip = set(sys.argv[2:])
    if found != strip:
        print("MACHINE_LOCAL only: %s" % " ".join(sorted(found - strip)))
        print("STRIP_KEYS only: %s" % " ".join(sorted(strip - found)))
        sys.exit(1)
except (OSError, SyntaxError, ValueError) as e:
    print("PARSER_ERROR %r" % (e,))
    sys.exit(1)
