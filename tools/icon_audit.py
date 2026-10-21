"""Audit icon source art, runtime routes, and changed definitions without editing art.

First dump current routes with tests/tools/icon_art_dump.gd, then run:
  python tools/icon_audit.py --data work/icons/dump/data.json --out work/icons/audit.json
Use --baseline older/data.json to flag definition changes for human semantic review.
Number-only changes are review candidates too; this tool never replaces artwork.
Only the Python standard library is required. Exit 1 means findings need review.
"""

import argparse
import json
from pathlib import Path
import re
import struct


ROOT = Path(__file__).resolve().parents[1]
GROUPS = ("skills", "items", "states")


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def gd_map(project, relative, name):
    """Read literal path dictionaries only; do not evaluate GDScript."""
    path = project / relative
    if not path.is_file():
        return {}
    text = path.read_text(encoding="utf-8-sig")
    match = re.search(r"\bconst\s+" + re.escape(name) + r"\s*:?=\s*\{(.*?)\}", text, re.S)
    return dict(re.findall(r'"([^"\n]+)"\s*:\s*"([^"\n]+)"', match.group(1))) if match else {}


def rows_of(data, project):
    rows = [(group, row) for group in GROUPS for row in data.get(group, [])]
    # Old dumps omitted sword buff states. Preserve that evidence, but discover
    # their live mapping rather than assuming an old dump proves full coverage.
    present = {row["id"] for group, row in rows if group == "states"}
    icons = gd_map(project, "src/ui/buff_bar.gd", "ICONS")
    names = gd_map(project, "src/ui/buff_bar.gd", "NAMES")
    for ident, path in icons.items():
        if ident.startswith("sword_") and ident not in present:
            rows.append(("states", {"id": ident, "path": path,
                                    "definition": {"name": names.get(ident, ident)},
                                    "discovered_from": "src/ui/buff_bar.gd:ICONS"}))
    return rows


def resource_file(project, resource):
    if not resource.startswith("res://"):
        return None
    path = (project / resource[6:]).resolve()
    return path if path.is_relative_to(project.resolve()) else None


def png_size(path):
    if path is None or not path.is_file():
        return None
    with path.open("rb") as stream:
        header = stream.read(24)
    if len(header) != 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        return None
    return list(struct.unpack(">II", header[16:24]))


def old_route(project, row):
    """Best-effort source inference for dumps made before resolved_path existed.

    This is labelled inferred, and cannot establish that Godot imported the PNG.
    Runtime proof always comes from a fresh dump's resolved_path and dimensions.
    """
    path = row.get("path", "")
    art = path
    fallback = path
    if path.startswith("art/"):
        pass
    elif path.startswith("items/gen/"):
        art = "art/items/" + path.rsplit("/", 1)[-1]
    elif path == "ui/teleport":
        art = "art/items/tp_scroll"
    elif path == "items/quest_letter":
        art = "art/items/recipe"
    else:
        for name in ("ABILITY_FALLBACKS", "NEUTRAL_SKILL_FALLBACKS"):
            for skill, value in gd_map(project, "src/ui/ui_kit.gd", name).items():
                if value == path:
                    art = "art/skills/" + skill
                    break
            if art != path:
                break
    resource = "res://assets/ui/" + art + ".png"
    file = resource_file(project, resource)
    if file and file.is_file():
        return resource
    resource = "res://assets/ui/" + fallback + ".svg"
    file = resource_file(project, resource)
    return resource if file and file.is_file() else None


def differences(before, after, path=""):
    if before == after:
        return []
    if isinstance(before, dict) and isinstance(after, dict):
        changes = []
        for key in sorted(before.keys() | after.keys()):
            changes.extend(differences(before.get(key), after.get(key), (path + "." + key).lstrip(".")))
        return changes
    if isinstance(before, list) and isinstance(after, list) and len(before) == len(after):
        return [change for index, (old, new) in enumerate(zip(before, after))
                for change in differences(old, new, path + "[" + str(index) + "]")]
    return [{"field": path, "before": before, "after": after}]


def audit(project, data, baseline=None):
    records = []
    findings = []
    previous = {(group, row["id"]): row for group in GROUPS for row in (baseline or {}).get(group, [])}
    seen = set()
    for group, row in rows_of(data, project):
        ident = row["id"]
        key = (group, ident)
        codes = []
        if key in seen:
            codes.append("duplicate_id")
        seen.add(key)
        category = "items" if group == "items" else "skills"
        source_id = "recipe" if group == "items" and (ident.startswith("recipe_") or ident == "recipe") else ident
        expected = "res://assets/ui/art/" + category + "/" + source_id + ".png"
        source = resource_file(project, expected)
        exists = bool(source and source.is_file())
        dimensions = png_size(source)
        if not exists:
            codes.append("missing_source_png")
        elif dimensions is None or min(dimensions) <= 0:
            codes.append("invalid_source_png")
        runtime = "resolved_path" in row
        resolved = row.get("resolved_path") if runtime else old_route(project, row)
        if exists and resolved != expected:
            codes.append("route_mismatch")
        if runtime and (not resolved or row.get("dimensions") == [0, 0]):
            codes.append("missing_runtime_texture")
        review = None
        if baseline is not None and key in previous:
            changes = differences(previous[key].get("definition", {}), row.get("definition", {}))
            if changes:
                numeric = lambda value: isinstance(value, (int, float)) and not isinstance(value, bool)
                review = {"changes": changes, "number_only": all(numeric(c["before"]) and numeric(c["after"]) for c in changes),
                          "action": "Review meaning and image together; do not replace art automatically."}
                codes.append("definition_review")
        elif baseline is not None and key not in previous:
            codes.append("new_entry_review")
        record = {"group": group, "id": ident, "name": row.get("definition", {}).get("name", ident),
                  "path": row.get("path"), "expected_source": expected, "source_exists": exists,
                  "source_dimensions": dimensions, "resolved_path": resolved,
                  "route_evidence": "runtime_dump" if runtime else "source_inference_only",
                  "runtime_dimensions": row.get("dimensions"), "findings": codes}
        if "discovered_from" in row:
            record["discovered_from"] = row["discovered_from"]
        if review:
            record["semantic_review"] = review
        for code in codes:
            findings.append({"group": group, "id": ident, "code": code})
        records.append(record)
    removed = [{"group": group, "id": ident} for group, ident in previous.keys() - seen]
    summary = {"rows": len(records), "groups": {g: sum(r["group"] == g for r in records) for g in GROUPS},
               "unique_expected_sources": len({r["expected_source"] for r in records}),
               "missing_source_png": sum(f["code"] == "missing_source_png" for f in findings),
               "route_mismatch": sum(f["code"] == "route_mismatch" for f in findings),
               "definition_review": sum(f["code"] == "definition_review" for f in findings),
               "new_entry_review": sum(f["code"] == "new_entry_review" for f in findings),
               "runtime_routes": sum(r["route_evidence"] == "runtime_dump" for r in records),
               "findings": len(findings), "removed_entries": len(removed)}
    return {"summary": summary, "records": records, "findings": findings, "removed_entries": removed,
            "notes": ["Recipes share art/items/recipe.png. Switch Boots attributes and Empty Flask are individual states.",
                      "Missing PNG means missing source art; inferred routes do not prove a Godot import.",
                      "Definition changes require semantic review, including number-only edits. No artwork was modified."]}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--project", type=Path, default=ROOT)
    parser.add_argument("--data", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--baseline", type=Path)
    args = parser.parse_args()
    report = audit(args.project.resolve(), read_json(args.data), read_json(args.baseline) if args.baseline else None)
    report["data"] = str(args.data.resolve())
    report["project"] = str(args.project.resolve())
    report["baseline"] = str(args.baseline.resolve()) if args.baseline else None
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps(report["summary"]))
    print("Audit: " + str(args.out.resolve()))
    return 1 if report["findings"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
