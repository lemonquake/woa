"""Package generated icon sheets, retaining exact source cells and provenance.

python tools/icon_art.py --run work/lemondev/<run-folder> [--check]
Artwork is made by the built-in image generation tool. This only extracts its
fixed-grid cells and resizes them for the engine; it does not draw new artwork.
"""
import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--run", required=True, type=Path,
                        help="Run directory with plan.json and sheets; absolute or project-relative")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    run = args.run if args.run.is_absolute() else ROOT / args.run
    plan = json.loads((run / "plan.json").read_text(encoding="utf-8-sig"))
    chosen = {}
    for sheet_index, sheet in enumerate(plan):
        if sheet["kind"] not in ("skills", "items"):
            raise ValueError("Unknown icon kind")
        for cell, name in enumerate(sheet["ids"]):
            if name is None:
                continue
            if not name.replace("_", "").isalnum() or Path(name).name != name:
                raise ValueError(f"Invalid icon ID: {name}")
            key = (sheet["kind"], name)
            if key in chosen and not sheet.get("replace", False):
                raise ValueError(f"Unexpected duplicate icon: {name}")
            chosen[key] = (sheet_index, cell)
    records = []
    missing = []
    for sheet_index, sheet in enumerate(plan):
        source = run / "sheets" / (sheet["key"] + ".png")
        if not source.exists():
            missing.append(sheet["key"])
            continue
        with Image.open(source) as image:
            image = image.convert("RGB")
            w, h = image.size
            if w != h or w < 1024:
                raise ValueError(f"Invalid square sheet: {source}, {image.size}")
            source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
            grid = sheet.get("grid", 4)
            if not isinstance(grid, int) or grid < 1 or len(sheet["ids"]) > grid * grid:
                raise ValueError(f"Invalid grid/cell count: {source}")
            for index, name in enumerate(sheet["ids"]):
                if name is None:
                    continue
                if chosen[(sheet["kind"], name)] != (sheet_index, index):
                    continue
                x, y = index % grid, index // grid
                # Round every boundary independently for odd generated dimensions.
                box = (round(x*w/grid), round(y*h/grid), round((x+1)*w/grid), round((y+1)*h/grid))
                target = ROOT / "assets/ui/art" / sheet["kind"] / (name + ".png")
                previous = [r for r in records if r["kind"] == sheet["kind"] and r["id"] == name]
                if previous:
                    if not sheet.get("replace", False):
                        raise ValueError(f"Unexpected duplicate icon: {name}")
                    records = [r for r in records if r not in previous]
                expected = image.crop(box).resize((256, 256), Image.Resampling.LANCZOS)
                if not args.check:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    expected.save(target)
                if not target.exists():
                    raise ValueError(f"Missing packaged icon: {target}")
                with Image.open(target) as icon:
                    if icon.size != (256, 256):
                        raise ValueError(f"Invalid icon dimensions: {target}")
                    if icon.convert("RGB").tobytes() != expected.tobytes():
                        raise ValueError(f"Packaged pixels do not match their source cell: {target}")
                records.append(dict(id=name, kind=sheet["kind"], sheet=sheet["key"], cell=index+1,
                                    crop=list(box), source_sha256=source_hash,
                                    path=target.relative_to(ROOT).as_posix(),
                                    sha256=hashlib.sha256(target.read_bytes()).hexdigest()))
    keys = [(r["kind"], r["id"]) for r in records]
    if len(keys) != len(set(keys)):
        raise ValueError("Duplicate icon identities in plan")
    hashes = [r["sha256"] for r in records]
    if len(hashes) != len(set(hashes)):
        raise ValueError("Duplicate icon images: check grid extraction")
    manifest = dict(generator="Built-in image generation", size=256, icons=records,
                    missing_sheets=missing)
    if not args.check:
        (run / "manifest.json").write_text(json.dumps(manifest, indent=2)+"\n", encoding="utf-8")
    print(f"Packaged {len(records)} unique icons; missing sheets: {', '.join(missing) or 'none'}")
    if args.check and missing:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
