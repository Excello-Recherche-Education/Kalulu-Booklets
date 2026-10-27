"""The booklets' fonts, shaped with HarfBuzz and drawn glyph by glyph.

The fonts are not kept here: they live in Kalulu-Languages, in ``fonts/`` beside
the packs (its ``LICENSE.md`` says what each file is). Mulish prints script,
in the version modified for Kalulu, and Marelle prints cursive.

Marelle joins its letters through OpenType rules (contextual alternates,
chained substitutions), so text is shaped with HarfBuzz before it is drawn:
drawn letter by letter, the joins come out wrong. Each glyph is then drawn on
its own, which is what lets a silent letter be grey in the middle of a joined
cursive word: HarfBuzz says which letter every glyph comes from (its cluster).

ReportLab only embeds TrueType outlines, and Kalulu's Mulish is CFF-flavoured
OpenType, so a CFF font is converted to TrueType in memory before ReportLab
gets it. HarfBuzz shapes from the file itself; the conversion keeps every glyph
at its index, so the glyphs it returns are the ones ReportLab embeds.
"""

from __future__ import annotations

import hashlib
import io
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

import uharfbuzz as hb
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont as FontFile
from fontTools.ttLib import newTable
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen.canvas import Canvas

# In the fonts folder of Kalulu-Languages.
SCRIPT = "mulish/kalulu_mulish_regular.otf"
SCRIPT_BOLD = "mulish/kalulu_mulish_bold.otf"
SCRIPT_BLACK = "mulish/kalulu_mulish_black.otf"
CURSIVE = "marelle/Marelle-Regular.ttf"

# Kalulu-Booklets' own checkout of the packs.
PINNED = Path(__file__).resolve().parents[2] / "kalulu-languages" / "fonts"


class FontError(Exception):
    """No fonts folder holding the files the booklets print with."""


def find(pack_file: Path) -> Path:
    """The fonts of the Kalulu-Languages checkout a pack is in; failing that,
    those of the packs pinned in kalulu-languages/."""
    candidates = [pack_file.resolve().parent.parent / "fonts", PINNED]
    for folder in candidates:
        if all((folder / name).is_file() for name in (SCRIPT, SCRIPT_BOLD, SCRIPT_BLACK, CURSIVE)):
            return folder
    raise FontError("no fonts folder with Mulish and Marelle in "
                    + " or ".join(str(folder) for folder in candidates)
                    + " -- Kalulu-Languages keeps them in fonts/")


@dataclass(frozen=True)
class Glyph:
    char: str  # the character ReportLab draws this glyph with
    cluster: int  # index in the shaped text of the letter it comes from
    x: float  # in em, from the start of the text
    y: float
    advance: float


class Face:
    """A font file, registered with ReportLab and shaped with HarfBuzz."""

    def __init__(self, path: Path):
        data = path.read_bytes()
        info = FontFile(io.BytesIO(data))
        # One name per file content: two fonts folders never share a name.
        self.name = f"{path.stem}-{hashlib.sha1(data).hexdigest()[:8]}"
        self.units = info["head"].unitsPerEm
        self.x_height = info["OS/2"].sxHeight / self.units
        self.cap_height = info["OS/2"].sCapHeight / self.units
        # shapable=False: shaping happens here, once, and ReportLab must not
        # shape the result a second time.
        self._ttf = TTFont(self.name, _truetype(info) if "CFF " in info else io.BytesIO(data), shapable=False)
        pdfmetrics.registerFont(self._ttf)
        # Lets ReportLab embed glyphs that no character maps to (the
        # alternates shaping substitutes), under private-use characters.
        self._ttf.hbFont()
        self._hb = hb.Font(hb.Face(hb.Blob(data)))

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


def _truetype(font: FontFile) -> io.BytesIO:
    """``font``'s CFF outlines as TrueType ones, every glyph at its index."""
    order = font.getGlyphOrder()
    glyph_set = font.getGlyphSet()
    glyphs = {}
    for name in order:
        pen = TTGlyphPen(glyph_set)
        glyph_set[name].draw(Cu2QuPen(pen, 1.0, reverse_direction=True))
        glyphs[name] = pen.glyph()
    glyf = newTable("glyf")
    glyf.glyphOrder = order
    glyf.glyphs = glyphs
    font["glyf"] = glyf
    font["loca"] = newTable("loca")
    del font["CFF "]
    maxp = font["maxp"]
    maxp.tableVersion = 0x00010000
    maxp.maxZones = 1
    for field in ("maxTwilightPoints", "maxStorage", "maxFunctionDefs", "maxInstructionDefs",
                  "maxStackElements", "maxSizeOfInstructions", "maxComponentElements"):
        setattr(maxp, field, 0)
    font["head"].glyphDataFormat = 0
    font["head"].indexToLocFormat = 0
    font.sfntVersion = "\x00\x01\x00\x00"
    converted = io.BytesIO()
    font.save(converted)
    converted.seek(0)
    return converted


@dataclass(frozen=True)
class Fonts:
    script: Face
    script_bold: Face
    script_black: Face
    cursive: Face


@lru_cache(maxsize=None)
def load(folder: Path) -> Fonts:
    return Fonts(
        script=Face(folder / SCRIPT),
        script_bold=Face(folder / SCRIPT_BOLD),
        script_black=Face(folder / SCRIPT_BLACK),
        cursive=Face(folder / CURSIVE),
    )
