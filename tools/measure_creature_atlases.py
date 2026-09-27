"""Measure atlas alpha and record UV rectangles/feet pivots; never edit pixels.
Run after replacing an atlas: python tools/measure_creature_atlases.py
Requires Pillow and numpy only for this authoring step, not game runtime.
"""
import json
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Gamematerials" / "Creatures"
OUT = ROOT / "Builds" / "creature-review"
OUT.mkdir(parents=True, exist_ok=True)


def cut(profile, expected, radius):
    lo, hi = max(1, expected - radius), min(len(profile) - 1, expected + radius)
    indexes = np.arange(lo, hi + 1)
    # Prefer completely empty separators; distance breaks equal-alpha ties.
    costs = profile[indexes].astype(float) + abs(indexes - expected) * 0.03
    return int(indexes[np.argmin(costs)])


layouts, report = {}, {}
for path in sorted(SOURCE.glob("*-actions-v1.png")):
    key = path.name.split("-actions")[0]
    image = Image.open(path).convert("RGBA")
    alpha = np.asarray(image)[:, :, 3]
    mask = alpha > 48
    h, w = mask.shape
    unit = w / 6.0
    ys = [0] + [cut(mask.sum(axis=1), round(h * i / 4), 38) for i in range(1, 4)] + [h]
    pivots, rects, checks = [], [], []
    for row in range(4):
        y0, y1 = ys[row], ys[row + 1]
        xs = [0] + [cut(mask[y0:y1].sum(axis=0), round(w * i / 6), 26) for i in range(1, 6)] + [w]
        for col in range(6):
            x0, x1 = xs[col], xs[col + 1]
            part = mask[y0:y1, x0:x1]
            occupied_y, occupied_x = np.where(part)
            assert len(occupied_x) > 1000, (key, row, col, "empty frame")
            # Ignore isolated one-pixel sparks in foot placement.
            foot_rows = np.where(part.sum(axis=1) >= 5)[0]
            baseline = int(foot_rows[-1]) + 1
            # A bat's flight keeps its authored height and wing arc. Its death
            # row lands on a common floor after the loss-of-lift poses.
            if key == "bat":
                baseline = round(h / 4 * (row + 1) - 14) - y0
            rects.append([x0, y0, x1 - x0, y1 - y0])
            pivots.append([round(((col + 0.5) * unit - x0) / unit, 6), round(baseline / unit, 6)])
            edges = int(part[:, :1].sum() + part[:, -1:].sum() + part[:1, :].sum() + part[-1:, :].sum())
            checks.append({"row": row, "frame": col, "visible_pixels": len(occupied_x), "edge_pixels": edges,
                           "bounds": [int(occupied_x.min()), int(occupied_y.min()), int(occupied_x.max()+1), int(occupied_y.max()+1)]})
    layouts[key] = {"source_size": [w, h], "unit": unit, "rects": rects, "pivots": pivots}
    report[key] = {"size": [w, h], "transparent_fraction": round(float((alpha == 0).mean()), 4),
                   "opaque_fraction": round(float((alpha > 240).mean()), 4), "row_cuts": ys,
                   "frames": checks}
    print(key, "alpha empty", report[key]["transparent_fraction"], "rows", ys,
          "edge crossings", sum(c["edge_pixels"] for c in checks))
(SOURCE / "animation-layouts.json").write_text(json.dumps(layouts, indent=2) + "\n", encoding="utf-8")
(OUT / "atlas-analysis.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
