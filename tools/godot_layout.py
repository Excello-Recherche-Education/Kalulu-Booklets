"""Records what the Python generator draws for every booklet, for the Godot
port's tests to compare against (Kalulu-Main's docs/BOOKLETS-GODOT-PORT.md,
phase 4: operation streams and notes identical for every pack × booklet ×
series × version).

    .venv/bin/python tools/godot_layout.py [pack folder ...]

By default every ``xx_XX`` pack of ``kalulu-languages/``. One file per pack,
``project/tests/generated/layout/<locale>.json``: for each series, booklet and
version the pack prints, every page's drawing operations, the notes the layout
added, and the imposition of its printing copy.

The operations are those of the Godot port's ``DrawingSurface``, recorded from
ReportLab's canvas as the layout calls it: save / restore / transform, colours,
line width, fill opacity, paths (their numbers as the layout computed them, not
as ReportLab rounds them into the PDF), images, and text. Text is recorded as
the layout asked for it (``Face.draw()``'s arguments), not glyph by glyph: the
Godot test draws it again with its own FontFace, whose glyphs phase 2 checked
against HarfBuzz. Images are named ``art/<file>`` for the characters, else by
their path inside the pack.

Like ``godot_content.py``'s, these files follow the packs and are not
committed; the Godot Tests workflow writes them before running GUT.
"""

from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "project" / "tests" / "generated" / "layout"
sys.path.insert(0, str(ROOT / "src"))

from reportlab.pdfgen import canvas as rl_canvas  # noqa: E402
from reportlab.pdfgen import pathobject  # noqa: E402

from kalulu_booklets import content as contents  # noqa: E402
from kalulu_booklets import fonts as fontfaces  # noqa: E402
from kalulu_booklets import layout  # noqa: E402
from kalulu_booklets import pack as packs  # noqa: E402
from kalulu_booklets.versions import VERSIONS  # noqa: E402


class Recorder:
    def __init__(self) -> None:
        self.pages: list[list] = [[]]
        self.in_text = 0
        self.pack_folder: Path = Path()

    def add(self, operation: list) -> None:
        if not self.in_text:
            self.pages[-1].append(operation)


RECORD = Recorder()


def rgb(color: object) -> list[float] | None:
    return None if color is None else list(color.rgb())


# --- Paths: their operators with the numbers the layout gave -----------------------

def _recording(name: str, operator: str):
    original = getattr(pathobject.PDFPathObject, name)

    def method(self, *numbers):
        if not hasattr(self, "_steps"):
            self._steps = []
        self._steps.append([operator, *numbers])
        return original(self, *numbers)
    return method


for _name, _operator in (("moveTo", "m"), ("lineTo", "l"), ("curveTo", "c"), ("rect", "re"), ("close", "h")):
    setattr(pathobject.PDFPathObject, _name, _recording(_name, _operator))


def steps_of(path: pathobject.PDFPathObject) -> list:
    return list(getattr(path, "_steps", []))


class RecordingCanvas(rl_canvas.Canvas):
    def setFillColor(self, color, alpha=None):
        RECORD.add(["fill_color", rgb(color)])
        # ReportLab sets the opacity a colour carries itself (1 for every
        # colour here): not something the layout asked for.
        RECORD.in_text += 1
        try:
            super().setFillColor(color, alpha)
        finally:
            RECORD.in_text -= 1

    def setStrokeColor(self, color, alpha=None):
        RECORD.add(["stroke_color", rgb(color)])
        super().setStrokeColor(color, alpha)

    def setLineWidth(self, width):
        RECORD.add(["line_width", width])
        super().setLineWidth(width)

    def setFillAlpha(self, alpha):
        RECORD.add(["fill_alpha", alpha])
        super().setFillAlpha(alpha)

    def saveState(self):
        RECORD.add(["save"])
        super().saveState()

    def restoreState(self):
        RECORD.add(["restore"])
        super().restoreState()

    def translate(self, dx, dy):
        RECORD.add(["transform", [1, 0, 0, 1, dx, dy]])
        super().translate(dx, dy)

    def scale(self, x, y):
        RECORD.add(["transform", [x, 0, 0, y, 0, 0]])
        super().scale(x, y)

    def line(self, x1, y1, x2, y2):
        RECORD.add(["path", [["m", x1, y1], ["l", x2, y2]], True, False, False])
        super().line(x1, y1, x2, y2)

    def rect(self, x, y, width, height, stroke=1, fill=0):
        RECORD.add(["path", [["re", x, y, width, height]], bool(stroke), bool(fill), False])
        super().rect(x, y, width, height, stroke, fill)

    # Shapes ReportLab writes straight into the page: drawn as paths here, so
    # their curves are recorded as the layout's numbers make them.
    def ellipse(self, x1, y1, x2, y2, stroke=1, fill=0):
        path = self.beginPath()
        path.ellipse(x1, y1, x2 - x1, y2 - y1)
        self.drawPath(path, stroke, fill)

    def roundRect(self, x, y, width, height, radius, stroke=1, fill=0):
        path = self.beginPath()
        path.roundRect(x, y, width, height, radius)
        self.drawPath(path, stroke, fill)

    def drawPath(self, path, stroke=1, fill=0, fillMode=None):
        # Even-odd only when the layout asks for it. Left unasked, ReportLab
        # fills with the last mode a drawing set, which restoreState() does
        # not undo: the cover's logo leaves it even-odd for the fluency bubble
        # after it, which fills the same either way, its outline crossing
        # nowhere.
        RECORD.add(["path", steps_of(path), bool(stroke), bool(fill), fillMode == rl_canvas.FILL_EVEN_ODD])
        super().drawPath(path, stroke, fill, fillMode)

    def drawImage(self, image, x, y, width=None, height=None, mask=None, **kwargs):
        file = Path(image.fileName).resolve()
        art = layout.ART.resolve()
        key = f"art/{file.name}" if file.parent == art else file.relative_to(RECORD.pack_folder).as_posix()
        RECORD.add(["image", key, x, y, width, height])
        # ReportLab places the image with a transform of its own, inside a
        # saved state: not something the layout asked for.
        RECORD.in_text += 1
        try:
            return super().drawImage(image, x, y, width, height, mask, **kwargs)
        finally:
            RECORD.in_text -= 1

    def showPage(self):
        RECORD.pages.append([])
        super().showPage()


_draw = fontfaces.Face.draw


def recording_draw(self, canvas, x, y, text, size, color, grey=frozenset(), grey_color=None,
                   colors=None, spacing=None, outline=None):
    RECORD.add(["text", self.file, x, y, text, size, rgb(color), sorted(grey), rgb(grey_color),
                {str(key): rgb(value) for key, value in (colors or {}).items()},
                None if spacing is None else [spacing.tracking, spacing.space],
                None if outline is None else [rgb(outline[0]), outline[1]]])
    RECORD.in_text += 1
    try:
        return _draw(self, canvas, x, y, text, size, color, grey, grey_color, colors, spacing, outline)
    finally:
        RECORD.in_text -= 1


fontfaces.Face.draw = recording_draw
layout.Canvas = RecordingCanvas


def run(pack: packs.Pack, faces: fontfaces.Fonts, series: str, number: int, version_name: str, out: Path) -> dict:
    version = VERSIONS[version_name]
    booklet = contents.booklet(pack, number, series)
    before = len(booklet.notes)
    RECORD.pages = [[]]
    count = layout.write(booklet, faces, out / "booklet.pdf", version)
    pages = RECORD.pages[:-1] if not RECORD.pages[-1] else RECORD.pages
    return {
        "pages": pages,
        "notes": booklet.notes[before:],
        "imposition": [[list(side) for side in sheet] for sheet in layout.sheet_sides(count)] if version.printed else None,
    }


def dump(folder: Path) -> dict:
    pack = packs.load(folder)
    RECORD.pack_folder = pack.path.parent.resolve()
    replaced = {role: font.file for role, font in pack.fonts.items()}
    faces = fontfaces.load(fontfaces.find(pack.path, replaced), tuple(sorted(replaced.items())))
    runs = {}
    with tempfile.TemporaryDirectory() as scratch:
        for series in pack.series:
            for number in pack.booklets():
                for version in pack.versions:
                    runs[f"{series}/{number}/{version}"] = run(pack, faces, series, number, version, Path(scratch))
    return {"locale": pack.locale, "runs": runs}


def main(arguments: list[str]) -> int:
    folders = [Path(argument) for argument in arguments] or sorted(
        path for path in (ROOT / "kalulu-languages").glob("??_??") if (path / "language.db").is_file())
    if not folders:
        print("no pack found: is kalulu-languages/ checked out?", file=sys.stderr)
        return 1
    OUT.mkdir(parents=True, exist_ok=True)
    for folder in folders:
        data = dump(folder)
        path = OUT / f"{data['locale']}.json"
        path.write_text(json.dumps(data, ensure_ascii=False) + "\n", encoding="utf-8")
        operations = sum(len(page) for run in data["runs"].values() for page in run["pages"])
        print(f"wrote {path.relative_to(ROOT)} ({len(data['runs'])} runs, {operations} operations, "
              f"{path.stat().st_size // 1024} KB)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
