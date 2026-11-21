"""Records everything the generator draws for one booklet, for the Godot replay.

    .venv/bin/python prototype/record.py <pack folder> <booklet> <version> <out dir>

Writes ``<out>/reference.pdf`` (the generator's own output, through ReportLab)
and ``<out>/drawing.json``: the same pages as a list of drawing operations, text
included as *unshaped* strings, so the Godot side has to shape and embed the
fonts itself. Each text operation also carries the glyphs HarfBuzz gave the
generator, in font units, for comparing the two shapers.

A prototype: nothing in the generator imports this.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import uharfbuzz as hb
from reportlab.pdfgen import canvas as rl_canvas

from kalulu_booklets import content, fonts, layout
from kalulu_booklets.pack import load
from kalulu_booklets.versions import VERSIONS

PAGES: list[list[dict]] = [[]]
INFO: dict[str, str] = {}
_IN_TEXT = [0]


def _rgb(color: object) -> list[float] | None:
    if color is None:
        return None
    return [round(value, 6) for value in color.rgb()]


def _record(op: dict) -> None:
    if not _IN_TEXT[0]:
        PAGES[-1].append(op)


_PATH = re.compile(r"[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?|[a-zA-Z]+")


def _path_ops(code: str) -> list[list]:
    ops, numbers = [], []
    for token in _PATH.findall(code):
        if token[0].isalpha():
            ops.append([token, *numbers])
            numbers = []
        else:
            numbers.append(float(token))
    return ops


class RecordingCanvas(rl_canvas.Canvas):
    def setTitle(self, title):
        INFO["Title"] = title
        super().setTitle(title)

    def setAuthor(self, author):
        INFO["Author"] = author
        super().setAuthor(author)

    def setSubject(self, subject):
        INFO["Subject"] = subject
        super().setSubject(subject)

    def setFillColor(self, color, alpha=None):
        _record({"op": "fill_color", "rgb": _rgb(color)})
        super().setFillColor(color, alpha)

    def setStrokeColor(self, color, alpha=None):
        _record({"op": "stroke_color", "rgb": _rgb(color)})
        super().setStrokeColor(color, alpha)

    def setLineWidth(self, width):
        _record({"op": "line_width", "width": width})
        super().setLineWidth(width)

    def setFillAlpha(self, alpha):
        _record({"op": "fill_alpha", "alpha": alpha})
        super().setFillAlpha(alpha)

    def saveState(self):
        _record({"op": "save"})
        super().saveState()

    def restoreState(self):
        _record({"op": "restore"})
        super().restoreState()

    def translate(self, dx, dy):
        _record({"op": "transform", "matrix": [1, 0, 0, 1, dx, dy]})
        super().translate(dx, dy)

    def scale(self, x, y):
        _record({"op": "transform", "matrix": [x, 0, 0, y, 0, 0]})
        super().scale(x, y)

    def line(self, x1, y1, x2, y2):
        _record({"op": "path", "code": [["m", x1, y1], ["l", x2, y2]], "stroke": 1, "fill": 0, "even_odd": False})
        super().line(x1, y1, x2, y2)

    def rect(self, x, y, width, height, stroke=1, fill=0):
        _record({"op": "path", "code": [["re", x, y, width, height]], "stroke": stroke, "fill": fill,
                 "even_odd": self._fillMode == rl_canvas.FILL_EVEN_ODD})
        super().rect(x, y, width, height, stroke, fill)

    # Both drawn as paths, so the reference and the replay share the curves.
    def roundRect(self, x, y, width, height, radius, stroke=1, fill=0):
        path = self.beginPath()
        path.roundRect(x, y, width, height, radius)
        self.drawPath(path, stroke, fill)

    def ellipse(self, x1, y1, x2, y2, stroke=1, fill=0):
        path = self.beginPath()
        path.ellipse(x1, y1, x2 - x1, y2 - y1)
        self.drawPath(path, stroke, fill)

    def drawPath(self, path, stroke=1, fill=0, fillMode=None):
        mode = fillMode if fillMode is not None else getattr(path, "_fillMode", self._fillMode)
        _record({"op": "path", "code": _path_ops(path.getCode()), "stroke": stroke, "fill": fill,
                 "even_odd": mode == rl_canvas.FILL_EVEN_ODD})
        super().drawPath(path, stroke, fill, fillMode)

    def drawImage(self, image, x, y, width=None, height=None, mask=None, **kwargs):
        _record({"op": "image", "file": str(Path(image.fileName).resolve()), "x": x, "y": y,
                 "width": width, "height": height, "mask": mask})
        return super().drawImage(image, x, y, width, height, mask, **kwargs)

    def showPage(self):
        PAGES.append([])
        super().showPage()


_original_draw = fonts.Face.draw


def _recording_draw(self, canvas, x, y, text, size, color, grey=frozenset(), grey_color=None,
                    colors=None, spacing=None, outline=None):
    buffer = hb.Buffer()
    buffer.add_codepoints([ord(character) for character in text])
    buffer.guess_segment_properties()
    hb.shape(self._hb, buffer)
    glyphs = [[info.codepoint, info.cluster, position.x_advance, position.x_offset, position.y_offset]
              for info, position in zip(buffer.glyph_infos or (), buffer.glyph_positions or ())] if text else []
    _record({
        "op": "text", "font": self.file, "x": x, "y": y, "text": text, "size": size,
        "color": _rgb(color), "grey": sorted(grey), "grey_color": _rgb(grey_color),
        "colors": {str(key): _rgb(value) for key, value in (colors or {}).items()},
        "spacing": None if spacing is None else [spacing.tracking, spacing.space],
        "outline": None if outline is None else [_rgb(outline[0]), outline[1]],
        "units": self.units, "harfbuzz": glyphs,
    })
    _IN_TEXT[0] += 1
    try:
        return _original_draw(self, canvas, x, y, text, size, color, grey, grey_color, colors, spacing, outline)
    finally:
        _IN_TEXT[0] -= 1


def main(pack_folder: str, number: str, version_name: str, out: str) -> None:
    out_dir = Path(out)
    out_dir.mkdir(parents=True, exist_ok=True)
    pack = load(Path(pack_folder))
    replaced = {role: font.file for role, font in pack.fonts.items()}
    folder = fonts.find(pack.path, replaced)
    faces = fonts.load(folder, tuple(sorted(replaced.items())))
    fonts.Face.draw = _recording_draw
    layout.Canvas = RecordingCanvas
    booklet = content.booklet(pack, int(number), pack.series[0])
    count = layout.write(booklet, faces, out_dir / "reference.pdf", VERSIONS[version_name])
    if not PAGES[-1]:
        PAGES.pop()
    drawing = {"page_size": list(layout.A5), "info": INFO, "fonts_folder": str(folder.resolve()),
               "series": pack.series[0], "pages": PAGES}
    (out_dir / "drawing.json").write_text(json.dumps(drawing, ensure_ascii=False))
    texts = sum(1 for page in PAGES for op in page if op["op"] == "text")
    print(f"{count} pages, {texts} text operations -> {out_dir}")


if __name__ == "__main__":
    main(*sys.argv[1:])
