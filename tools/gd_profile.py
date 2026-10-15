"""Function-level profile of the simulation (GDScript has no sampling profiler outside the editor).

Copies the simulation scripts (src/sim, src/core, src/hero) and a tool script into a scratch Godot project, wraps every
named function with a scope object that records its time (self time: minus the functions it called), runs the tool
headless and prints the functions that took the most self time, with call counts.

    python tools/gd_profile.py [--out DIR] [--top 40] [--game] -- <tool args>
    python tools/gd_profile.py -- --fight=600 --min=11 --window=1 --a=ezee,azrin,froster,sludge,tock \
        --b=blood_ranger,caziel,kragg,azrin,froster

With --game the whole game runs in a window (src/game, src/ui and src/sim wrapped) with the main scene's arguments,
for example the teamfight benchmark: --game -- --bench=20 --t=600 --fight --autoplay --lineup=...

The tool is tests/tools/sim_profile.gd; it prints "PF <name> <self_ms> <calls>" lines at the end (the scope class adds
them). The wrapping itself costs about a microsecond per call, so tiny functions called very often look slower than
they are: read the call counts. Static functions can show inflated times (their scope object is not always freed at
the return), so time a suspicious static function directly before acting on it.
"""
import os
import re
import shutil
import subprocess
import sys

GODOT = "/a/Installer/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe"
if os.name == "nt":
    GODOT = r"A:\Installer\Godot_v4.7.2-stable_win64\Godot_v4.7.2-stable_win64_console.exe"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SCOPE = '''class_name PfScope
extends RefCounted
## Profiling scope (tools/gd_profile.py): created at a function's start, freed when the function returns.
static var self_us := {}
static var calls := {}
static var _stack: Array[int] = []           # child time of the open scopes
var key := ""
var t0 := 0

func _init(k: String) -> void:
	key = k
	t0 = Time.get_ticks_usec()
	_stack.append(0)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		var el := Time.get_ticks_usec() - t0
		var child: int = _stack.pop_back()
		self_us[key] = int(self_us.get(key, 0)) + el - child
		calls[key] = int(calls.get(key, 0)) + 1
		if not _stack.is_empty():
			_stack[-1] += el

static func dump() -> void:
	for k in self_us:
		print("PF %s %.3f %d" % [k, self_us[k] / 1000.0, calls[k]])
'''

FUNC = re.compile(r"^(\s*)(static\s+)?func\s+(\w+)\s*\(")


def instrument(src: str, fname: str) -> str:
    lines = src.split("\n")
    out = []
    i = 0
    while i < len(lines):
        ln = lines[i]
        m = FUNC.match(ln)
        if not m:
            out.append(ln)
            i += 1
            continue
        indent = m.group(1)
        name = m.group(3)
        # the signature may span lines: up to the line ending with ':' once parentheses close
        sig = [ln]
        depth = ln.count("(") - ln.count(")")
        while depth > 0 or not sig[-1].rstrip().endswith(":"):
            i += 1
            sig.append(lines[i])
            depth += lines[i].count("(") - lines[i].count(")")
        out.extend(sig)
        i += 1
        # the body's indentation: the next non-empty line
        j = i
        while j < len(lines) and lines[j].strip() == "":
            j += 1
        body_indent = re.match(r"^(\s*)", lines[j]).group(1) if j < len(lines) else indent + "\t"
        if len(body_indent) <= len(indent):
            body_indent = indent + "\t"
        out.append('%svar __pf := PfScope.new("%s:%s")' % (body_indent, fname, name))
    return "\n".join(out)


def game_profile(out: str, tool_args: list, top: int) -> None:
    """--game: the whole game (src/game, src/ui, src/sim instrumented) in a window, with the main scene's benchmark."""
    if os.path.exists(out):
        shutil.rmtree(out)
    os.makedirs(out)
    shutil.copy(os.path.join(ROOT, "project.godot"), out)
    shutil.copytree(os.path.join(ROOT, ".godot"), os.path.join(out, ".godot"))
    # the assets are only read: link them instead of copying 600 MB
    subprocess.run(["cmd", "/c", "mklink", "/J", os.path.join(out, "assets"), os.path.join(ROOT, "assets")],
                   capture_output=True)
    for name in os.listdir(ROOT):
        if name.endswith(".svg") or name.endswith(".import") or name == "icon.svg":
            shutil.copy(os.path.join(ROOT, name), out)
    for d in ["src", "tests"]:
        for base, _dirs, files in os.walk(os.path.join(ROOT, d)):
            rel = os.path.relpath(base, ROOT).replace("\\", "/")
            os.makedirs(os.path.join(out, rel), exist_ok=True)
            for fn in files:
                src = os.path.join(base, fn)
                dst = os.path.join(out, rel, fn)
                if fn.endswith(".gd") and (rel.startswith("src/game") or rel.startswith("src/ui") or rel == "src/sim"):
                    with open(src, encoding="utf-8") as f:
                        txt = instrument(f.read(), fn[:-3])
                    if fn == "main.gd":
                        # report only the benchmark window: the counters restart when its warm-up ends
                        txt = txt.replace("\t\tget_tree().quit()", "\t\tPfScope.dump()\n\t\tget_tree().quit()")
                        txt = txt.replace("\t\tUiKit.draw_us.clear()\n",
                                          "\t\tUiKit.draw_us.clear()\n\t\tPfScope.self_us.clear()\n\t\tPfScope.calls.clear()\n")
                    with open(dst, "w", encoding="utf-8", newline="\n") as f:
                        f.write(txt)
                else:
                    shutil.copy(src, dst)
    with open(os.path.join(out, "src/sim/pf_scope.gd"), "w", encoding="utf-8", newline="\n") as f:
        f.write(SCOPE)
    os.makedirs(os.path.join(out, "work"), exist_ok=True)
    subprocess.run([GODOT, "--headless", "--path", out, "--import"], capture_output=True)
    r = subprocess.run([GODOT, "--path", out, "res://src/game/main.tscn", "--"] + tool_args,
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    report(r, top)


def report(r, top: int) -> None:
    rows = []
    for ln in r.stdout.splitlines():
        if ln.startswith("PF "):
            _, k, ms, n = ln.split(" ")
            rows.append((float(ms), int(n), k))
        elif "ALL mean" in ln or "SCRIPT ERROR" in ln or ln.startswith("BENCH"):
            print(ln)
    for ln in r.stderr.splitlines():
        if "SCRIPT ERROR" in ln or "Parse Error" in ln:
            print(ln)
    rows.sort(reverse=True)
    total = sum(x[0] for x in rows)
    print("self time total %.0f ms" % total)
    for ms, n, k in rows[:top]:
        print("%9.1f ms %5.1f%% %9d calls %7.2f us/call  %s" % (ms, 100.0 * ms / max(total, 1e-9), n, 1000.0 * ms / max(n, 1), k))


def main() -> None:
    args = sys.argv[1:]
    tool_args = []
    if "--" in args:
        k = args.index("--")
        tool_args = args[k + 1:]
        args = args[:k]
    out = os.path.join(os.environ.get("TEMP", "/tmp"), "woa_gdprof")
    top = 40
    if "--out" in args:
        out = args[args.index("--out") + 1]
    if "--top" in args:
        top = int(args[args.index("--top") + 1])
    if "--game" in args:
        game_profile(out, tool_args, top)
        return
    if os.path.exists(out):
        shutil.rmtree(out)
    os.makedirs(out)
    with open(os.path.join(ROOT, "project.godot"), encoding="utf-8") as f:
        proj = f.read()
    proj = re.sub(r"\[autoload\][^\[]*", "", proj)
    proj = proj.replace('run/main_scene="res://src/ui/splash.tscn"', "")
    with open(os.path.join(out, "project.godot"), "w", encoding="utf-8", newline="\n") as f:
        f.write(proj)
    for d in ["src/sim", "src/core", "src/hero"]:
        for base, _dirs, files in os.walk(os.path.join(ROOT, d)):
            rel = os.path.relpath(base, ROOT)
            os.makedirs(os.path.join(out, rel), exist_ok=True)
            for fn in files:
                if not fn.endswith(".gd") and not fn.endswith(".json"):
                    continue
                with open(os.path.join(base, fn), encoding="utf-8") as f:
                    txt = f.read()
                if fn.endswith(".gd") and rel.replace("\\", "/") == "src/sim":
                    txt = instrument(txt, fn[:-3])
                with open(os.path.join(out, rel, fn), "w", encoding="utf-8", newline="\n") as f:
                    f.write(txt)
    os.makedirs(os.path.join(out, "tests/tools"), exist_ok=True)
    with open(os.path.join(ROOT, "tests/tools/sim_profile.gd"), encoding="utf-8") as f:
        tool = f.read()
    tool = tool.replace("\tquit()", "\tPfScope.dump()\n\tquit()")
    # with --fight, count only the fights (not the fast-forward before them)
    tool = tool.replace("\tw.profiling = true\n", "\tw.profiling = true\n\tPfScope.self_us.clear()\n\tPfScope.calls.clear()\n")
    with open(os.path.join(out, "tests/tools/sim_profile.gd"), "w", encoding="utf-8", newline="\n") as f:
        f.write(tool)
    with open(os.path.join(out, "src/sim/pf_scope.gd"), "w", encoding="utf-8", newline="\n") as f:
        f.write(SCOPE)
    subprocess.run([GODOT, "--headless", "--path", out, "--import"], capture_output=True)
    r = subprocess.run([GODOT, "--headless", "--path", out, "-s", "tests/tools/sim_profile.gd", "--"] + tool_args,
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    report(r, top)


if __name__ == "__main__":
    main()
