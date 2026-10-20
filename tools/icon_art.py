"""Package generated icon sheets, retaining exact source cells and provenance.

python tools/icon_art.py [--check]
Artwork is made by the built-in image generation tool. This only extracts its
fixed-grid cells and resizes them for the engine; it does not draw new artwork.
"""
import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "work/lemondev/2026-10-20-icons"


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    plan = json.loads((RUN / "plan.json").read_text(encoding="utf-8"))
    records = []
    missing = []
    for sheet in plan:
        source = RUN / "sheets" / (sheet["key"] + ".png")
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
            for index, name in enumerate(sheet["ids"]):
                if name is None:
                    continue
                x, y = index % grid, index // grid
                # Round every boundary independently for odd generated dimensions.
                box = (round(x*w/grid), round(y*h/grid), round((x+1)*w/grid), round((y+1)*h/grid))
                target = ROOT / "assets/ui/art" / sheet["kind"] / (name + ".png")
                if name == "death_order" and sheet["kind"] == "skills":
                    # Owner retained the original SVG; preserve rejected art outside the game pack.
                    target = RUN / "quarantine" / "death_order.png"
                previous = [r for r in records if r["kind"] == sheet["kind"] and r["id"] == name]
                if previous:
                    if not sheet.get("replace", False):
                        raise ValueError(f"Unexpected duplicate icon: {name}")
                    records = [r for r in records if r not in previous]
                if not args.check:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    image.crop(box).resize((256, 256), Image.Resampling.LANCZOS).save(target)
                if not target.exists():
                    raise ValueError(f"Missing packaged icon: {target}")
                with Image.open(target) as icon:
                    if icon.size != (256, 256):
                        raise ValueError(f"Invalid icon dimensions: {target}")
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
    (RUN / "manifest.json").write_text(json.dumps(manifest, indent=2)+"\n", encoding="utf-8")
    print(f"Packaged {len(records)} unique icons; missing sheets: {', '.join(missing) or 'none'}")
    if args.check and missing:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
