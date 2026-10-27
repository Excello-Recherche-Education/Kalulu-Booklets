"""The booklets' fonts, shaped with HarfBuzz and drawn glyph by glyph.

Mulish prints script and Marelle cursive, both under the SIL Open Font License
(``fonts/OFL-*.txt``). Marelle joins its letters through OpenType rules
(contextual alternates, chained substitutions), so text is shaped with HarfBuzz
before it is drawn: drawn letter by letter, the joins come out wrong.

Each glyph is drawn on its own, which is what lets a silent letter be grey in
the middle of a joined cursive word: HarfBuzz says which letter every glyph
comes from (its cluster).
"""

from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

import uharfbuzz as hb
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen.canvas import Canvas

FONTS = Path(__file__).resolve().parent / "fonts"


@dataclass(frozen=True)
class Glyph:
    char: str  # the character ReportLab draws this glyph with
    cluster: int  # index in the shaped text of the letter it comes from
    x: float  # in em, from the start of the text
    y: float
    advance: float


class Face:
    """A font file, registered with ReportLab and shaped with HarfBuzz."""

    def __init__(self, name: str, file_name: str):
        self.name = name
        path = FONTS / file_name
        # shapable=False: shaping happens here, once, and ReportLab must not
        # shape the result a second time.
        self._ttf = TTFont(name, str(path), shapable=False)
        pdfmetrics.registerFont(self._ttf)
        # Lets ReportLab embed glyphs that no character maps to (the
        # alternates shaping substitutes), under private-use characters.
        self._ttf.hbFont()
        self._hb = hb.Font(hb.Face(hb.Blob.from_file_path(str(path))))
        self.units = self._hb.face.upem
        # x-height and cap height in em, from the OS/2 table.
        self.x_height, self.cap_height = _heights(path, self.units)

    @lru_cache(maxsize=None)
    def shape(self, text: str) -> tuple[Glyph, ...]:
        buffer = hb.Buffer()
        buffer.add_codepoints([ord(character) for character in text])
        buffer.guess_segment_properties()
        hb.shape(self._hb, buffer)
        glyphs: list[Glyph] = []
        x = 0.0
        for info, position in zip(buffer.glyph_infos, buffer.glyph_positions):
            glyphs.append(Glyph(self._char_for(info.codepoint, position.x_advance), info.cluster,
                                (x + position.x_offset) / self.units, position.y_offset / self.units,
                                position.x_advance / self.units))
            x += position.x_advance
        return tuple(glyphs)

    def width(self, text: str, size: float) -> float:
        return sum(glyph.advance for glyph in self.shape(text)) * size

    def draw(self, canvas: Canvas, x: float, y: float, text: str, size: float,
             color: object, grey: frozenset[int] = frozenset(), grey_color: object = None) -> float:
        """Draws ``text`` with its baseline at ``y``; returns its width. The
        glyphs of the letters in ``grey`` are drawn in ``grey_color``."""
        glyphs = self.shape(text)
        drawn = canvas.beginText()
        drawn.setFont(self.name, size)
        current = None
        for glyph in glyphs:
            wanted = grey_color if glyph.cluster in grey and grey_color is not None else color
            if wanted is not current:
                drawn.setFillColor(wanted)
                current = wanted
            drawn.setTextOrigin(x + glyph.x * size, y + glyph.y * size)
            drawn.textOut(glyph.char)
        canvas.drawText(drawn)
        return sum(glyph.advance for glyph in glyphs) * size

    def _char_for(self, gid: int, advance: int) -> str:
        face = self._ttf.face
        for code in face.glyphToChar.get(gid, ()):
            if face.charToGlyph.get(code) == gid:
                return chr(code)
        return chr(self._ttf.hbAddPrivate(f"gid{gid}", gid, self._ttf.pdfScale(advance)))


def _heights(path: Path, units: int) -> tuple[float, float]:
    """sxHeight and sCapHeight of the OS/2 table (version 2 and later), in em."""
    import struct

    data = path.read_bytes()
    tables = struct.unpack(">H", data[4:6])[0]
    for index in range(tables):
        tag, _checksum, offset, _length = struct.unpack(">4sIII", data[12 + 16 * index:28 + 16 * index])
        if tag == b"OS/2":
            x_height, cap_height = struct.unpack(">hh", data[offset + 86:offset + 90])
            return x_height / units, cap_height / units
    raise ValueError(f"{path.name} has no OS/2 table")


@dataclass(frozen=True)
class Fonts:
    script: Face
    script_bold: Face
    script_black: Face
    cursive: Face


@lru_cache(maxsize=1)
def fonts() -> Fonts:
    return Fonts(
        script=Face("Mulish", "Mulish-Regular.ttf"),
        script_bold=Face("Mulish-Bold", "Mulish-Bold.ttf"),
        script_black=Face("Mulish-Black", "Mulish-Black.ttf"),
        cursive=Face("Marelle", "Marelle-Regular.ttf"),
    )
