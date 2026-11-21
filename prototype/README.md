# Godot prototype (2026-11-21)

This prototype checks that Godot can reproduce the generator's PDFs:

- the same shaping, including Marelle's cursive joins and composed accents;
- vector PDF output with the fonts embedded.

It is a reference for the port planned in Kalulu-Main's
`docs/BOOKLETS-GODOT-PORT.md`, and is not meant to be merged.

1. `record.py` runs the real generator and records every drawing operation, with
   text left unshaped. It writes `reference.pdf` and `drawing.json`.
2. `godot/replay.gd` shapes the text with Godot's TextServer, places the glyphs as
   `Face.draw` does, and writes its own PDF (`pdf_writer.gd`, `open_type.gd`,
   `shaper.gd`).
3. `compare.py` diffs the glyphs, then renders both PDFs with pdfium and compares
   them pixel by pixel. It needs pypdfium2 and Pillow.

From the repository root, with the generator's venv and `$GODOT` set (Kalulu-Main's
`scripts/kalulu-env.sh`):

```bash
.venv/bin/python prototype/record.py kalulu-languages/fr_FR 1 base prototype/out/fr_FR-1-base
"$GODOT" --headless --path prototype/godot --import
"$GODOT" --headless --path prototype/godot --script res://replay.gd -- \
    "$PWD/prototype/out/fr_FR-1-base/drawing.json" "$PWD/prototype/out/fr_FR-1-base/godot.pdf" \
    "$PWD/prototype/out/fr_FR-1-base/godot-glyphs.json"
.venv/bin/python prototype/compare.py prototype/out/fr_FR-1-base 600
```

Results on fr_FR 1 base, es_UY 1 base and pt_BR 1 dyslexia:

- **Glyphs:** every glyph and cluster is the same.
- **Positions:** exact to the font unit when shaped at units per em.
- **Pages:** they match apart from antialiasing, in pdfium and in PDFKit.
