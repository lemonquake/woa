"""Convert text sources to LF line endings (Python on Windows writes CRLF in text mode)."""
import os

ROOTS = ["src", "tests", "tools", "docs"]
EXTS = (".gd", ".gdshader", ".py", ".md", ".sh", ".tscn", ".json", ".cfg", ".txt")

n = 0
for root in ROOTS:
    for dp, _, files in os.walk(root):
        for f in files:
            if not f.endswith(EXTS):
                continue
            p = os.path.join(dp, f)
            b = open(p, "rb").read()
            if b"\r\n" in b:
                open(p, "wb").write(b.replace(b"\r\n", b"\n"))
                n += 1
for f in ["project.godot", ".gitignore", ".gitattributes"]:
    if os.path.exists(f):
        b = open(f, "rb").read()
        if b"\r\n" in b:
            open(f, "wb").write(b.replace(b"\r\n", b"\n"))
            n += 1
print("normalized", n, "files")
