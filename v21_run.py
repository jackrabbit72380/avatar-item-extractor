import base64, json, os, shutil, sys, zlib

MARK = "###PAYLOAD###"
CARRIER = "Extract-AvatarItem-v20.bat"
READERS = ("avatar_mesh.py", "lzx.py")
NO_ITEM = "Error: this container does not contain Avatar Item Content. Please try another."


def unpack(here, cache):
    p = os.path.join(here, CARRIER)
    if not os.path.exists(p):
        return None
    t = open(p, encoding="utf-8", errors="replace").read()
    b = "".join(t[t.rfind(MARK) + len(MARK):].split())
    for n, s in json.loads(zlib.decompress(base64.b85decode(b.encode())).decode()).items():
        open(os.path.join(cache, n), "w", encoding="utf-8", newline="\n").write(s)
    return os.path.join(cache, "extract_items.py")


def readers(here, cache):
    for n in READERS:
        if os.path.exists(os.path.join(cache, n)):
            continue
        for d in (here, os.getcwd()):
            if os.path.exists(os.path.join(d, n)):
                shutil.copyfile(os.path.join(d, n), os.path.join(cache, n))
    miss = [n for n in READERS if not os.path.exists(os.path.join(cache, n))]
    if miss:
        print("\n   The reader modules %s are missing." % " and ".join(miss))
        print("   Copy avatar_mesh.py and lzx.py beside this file and run again.\n")
        return 5
    return 0


def label(out):
    p = os.path.join(out, "catalogue.json")
    if not os.path.exists(p):
        return 0
    cat = json.load(open(p, encoding="utf-8"))
    ok = mp = 0
    for r in cat.get("items", []):
        ids = {b.get("id") for b in r.get("blocks") or []}
        good = bool((r.get("model") or {}).get("parses"))
        r["avatar_content"] = bool(r.get("blocks"))
        # Block 7 is the CustomColorTable: choosable colours, so a team colour.
        r["shading"] = ("mp" if 7 in ids else "sp") if good else None
        ok += good
        mp += good and 7 in ids
    json.dump(cat, open(p, "w", encoding="utf-8"), indent=1)
    if ok:
        print("  %d MP items (team colour), %d SP items (baked colours)" % (mp, ok - mp))
    elif cat.get("items"):
        print("\n" + NO_ITEM)
    return ok


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    cache, rest = sys.argv[1], sys.argv[2:]
    os.makedirs(cache, exist_ok=True)
    t = unpack(here, cache)
    if not t:
        print("   %s is not beside this script." % CARRIER)
        print("   Keep it next to Extract-AvatarItem-v21.bat and run again.")
        return 6
    s = readers(here, cache)
    if s:
        return s
    sys.path.insert(0, cache)
    code = compile(open(t, encoding="utf-8").read(), t, "exec")
    sys.argv = [t] + rest
    try:
        exec(code, {"__name__": "__main__", "__file__": t})
        rc = 0
    except SystemExit as e:
        rc = e.code if isinstance(e.code, int) else 0
    out = "extracted"
    for i, w in enumerate(rest):
        if w == "--out" and i + 1 < len(rest):
            out = rest[i + 1]
    parsed = label(out)
    if rc == 0 and not parsed:
        return 3
    return rc


if __name__ == "__main__":
    sys.exit(main())
