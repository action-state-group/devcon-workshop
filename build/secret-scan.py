#!/usr/bin/env python3
"""secret-scan.py IMAGE_TAR: fail if any layer of a `docker save` archive, or its config, carries a secret.

Every layer is read, not only the final filesystem: a file copied in one layer and deleted in a later
one still ships. Checked: forbidden file names, private-key blocks in files under 1 MiB, and the
config's env, labels and history.
"""
import io, json, re, sys, tarfile

NAMES = {"join.txt", "seedphrase.txt", ".credentials.json", "auth.json"}
KEY = re.compile(rb"-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----")
CFG = re.compile(r"(?i)(join[_-]?token|seed ?phrase|api[_-]?key|secret|password|MESH_LLM_POSTHOG_KEY|PRIVATE KEY)")
# Third-party toolchains fetched by sha256 (versions.lock) carry public test keys (Go's crypto/tls
# testdata, for one). Their key blocks are not ours; their file names are still checked.
VENDORED = ("opt/devcon8/go/", "opt/devcon8/node/", "opt/devcon8/npm/node_modules/")
# Known public files that merely mention these words.
ALLOW_CFG = re.compile(r"(?i)DO_NOT_TRACK")

def scan(path):
    bad = []
    with tarfile.open(path) as outer:
        names = outer.getnames()
        manifest = json.load(outer.extractfile("manifest.json"))[0]
        cfg = json.load(outer.extractfile(manifest["Config"]))
        text = json.dumps({"env": cfg.get("config", {}).get("Env"), "labels": cfg.get("config", {}).get("Labels"),
                           "history": cfg.get("history")})
        for m in CFG.finditer(text):
            ctx = text[max(0, m.start() - 40): m.end() + 40]
            if not ALLOW_CFG.search(ctx):
                bad.append(f"config: {ctx!r}")
        for layer in manifest["Layers"]:
            with tarfile.open(fileobj=outer.extractfile(layer)) as lt:
                for ti in lt:
                    base = ti.name.rsplit("/", 1)[-1]
                    if base.startswith(".wh."):
                        base = base[4:]
                    if base in NAMES:
                        bad.append(f"{layer}: {ti.name}")
                    if ti.isfile() and 0 < ti.size < (1 << 20) and not ti.name.startswith(VENDORED):
                        if KEY.search(lt.extractfile(ti).read()):
                            bad.append(f"{layer}: {ti.name} holds a private key")
    return bad

if __name__ == "__main__":
    found = scan(sys.argv[1])
    for f in found:
        print("secret-scan:", f)
    print(f"secret-scan: {'FAIL' if found else 'clean'}")
    sys.exit(1 if found else 0)
