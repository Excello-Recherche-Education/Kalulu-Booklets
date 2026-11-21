"""Compares the Godot replay with the generator's own PDF.

    .venv/bin/python prototype/compare.py <out dir> [dpi]

1. Glyphs: what Godot's TextServer shaped against what HarfBuzz gave the
   generator -- same glyph indices, same clusters, advances and offsets within
   a hundredth of a font unit.
2. Pages: both PDFs rendered by pdfium at ``dpi``, pixel by pixel. Writes
   ``diff-<page>.png`` (reference | godot | difference) for the pages that differ.

Needs pypdfium2 and Pillow in the venv (not dependencies of the generator).
"""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path

import pypdfium2 as pdfium
from PIL import Image, ImageChops

TOLERANCE = 0.01  # font units


def glyphs(out: Path) -> None:
    drawing = json.loads((out / "drawing.json").read_text())
    texts = [op for page in drawing["pages"] for op in page if op["op"] == "text"]
    godot = json.loads((out / "godot-glyphs.json").read_text())
    assert len(texts) == len(godot)
    index_or_cluster, position, worst = [], [], 0.0
    for op, theirs in zip(texts, godot):
        ours = op["harfbuzz"]
        if [g[:2] for g in ours] != [[int(g[0]), int(g[1])] for g in theirs]:
            index_or_cluster.append(op)
            continue
        gap = max((abs(a - b) for g, h in zip(ours, theirs) for a, b in zip(g[2:], h[2:])), default=0.0)
        worst = max(worst, gap)
        if gap > TOLERANCE:
            position.append((op, gap))
    count = sum(len(op["harfbuzz"]) for op in texts)
    print(f"glyphs: {len(texts)} texts, {count} glyphs")
    print(f"  different glyph or cluster: {len(index_or_cluster)} texts")
    for op in index_or_cluster[:5]:
        print(f"    {op['font']} {op['text']!r}")
    print(f"  same glyphs, position off by more than {TOLERANCE} unit: {len(position)} texts; "
          f"largest gap {worst:.4f} units")
    for op, gap in position[:5]:
        print(f"    {op['font']} {op['text']!r}: {gap:.3f}")


def pages(out: Path, dpi: int) -> None:
    reference = pdfium.PdfDocument(out / "reference.pdf")
    godot = pdfium.PdfDocument(out / "godot.pdf")
    print(f"pages: {len(reference)} reference, {len(godot)} godot, rendered at {dpi} dpi")
    # A folder per run, so no diff of an earlier run is left looking current.
    out = out / time.strftime("diff-%Y%m%d-%H%M%S")
    out.mkdir()
    identical, rows = 0, []
    for number in range(len(reference)):
        a = reference[number].render(scale=dpi / 72).to_pil().convert("RGB")
        b = godot[number].render(scale=dpi / 72).to_pil().convert("RGB")
        difference = ImageChops.difference(a, b).convert("L")
        histogram = difference.histogram()
        changed = sum(histogram[1:])
        visible = sum(histogram[33:])  # more than an eighth of the range
        if changed == 0:
            identical += 1
            continue
        rows.append((number + 1, changed, visible, max(i for i, n in enumerate(histogram) if n)))
        if visible:
            strip = Image.new("RGB", (a.width * 3, a.height), "white")
            strip.paste(a, (0, 0))
            strip.paste(b, (a.width, 0))
            strip.paste(difference.point(lambda v: 255 - min(255, v * 4)).convert("RGB"), (a.width * 2, 0))
            strip.save(out / f"diff-{number + 1:03}.png")
    print(f"  identical to the pixel: {identical} of {len(reference)}")
    for page, changed, visible, largest in rows:
        print(f"  page {page}: {changed} pixels differ, {visible} by more than 32/255, largest {largest}")


if __name__ == "__main__":
    folder = Path(sys.argv[1])
    glyphs(folder)
    pages(folder, int(sys.argv[2]) if len(sys.argv) > 2 else 150)
