"""The booklets' fonts, shaped with HarfBuzz and drawn glyph by glyph.

The fonts are not kept here: they live in Kalulu-Languages, in ``fonts/`` beside
the packs (its ``LICENSE.md`` says what each file is). Mulish prints script,
in the version modified for Kalulu, and Marelle prints cursive.

Marelle joins its letters through OpenType rules (contextual alternates,
chained substitutions), so text is shaped with HarfBuzz before it is drawn:
drawn letter by letter, the joins come out wrong. Each glyph is then drawn on
its own, which is what lets a silent letter be grey in the middle of a joined
cursive word: HarfBuzz says which letter every glyph comes from (its cluster).

A language can replace any of the four with a font of the same folder
(``BookletFonts`` in the pack): ``load`` takes the replacements by role. A
letter a font cannot print, even from its parts as HarfBuzz composes them ("á"
as "a" and a combining accent, which is how Marelle prints Spanish), comes out
as the font's empty box; each face records the ones it met, for the build to
point out.

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

# What each role prints with unless the pack replaces it.
DEFAULTS = {"script": SCRIPT, "script_bold": SCRIPT_BOLD, "script_black": SCRIPT_BLACK, "cursive": CURSIVE}
DEFAULT_NAMES = {"script": "Mulish", "script_bold": "Mulish bold", "script_black": "Mulish black", "cursive": "Marelle"}
ROLE_NAMES = {"script": "script", "script_bold": "bold script", "script_black": "black script", "cursive": "cursive"}

# Kalulu-Booklets' own checkout of the packs.
PINNED = Path(__file__).resolve().parents[2] / "kalulu-languages" / "fonts"


class FontError(Exception):
    """No fonts folder holding the files the booklets print with."""


def find(pack_file: Path, replaced: dict[str, str] | None = None) -> Path:
    """The fonts of the Kalulu-Languages checkout a pack is in; failing that,
    those of the packs pinned in kalulu-languages/. The folder must hold every
    file the booklets print with: the defaults, and the files of ``replaced``
    (role -> path inside fonts/) instead of the defaults they replace."""
    files = {**DEFAULTS, **(replaced or {})}
    candidates = [pack_file.resolve().parent.parent / "fonts", PINNED]
    for folder in candidates:
        if all((folder / name).is_file() for name in files.values()):
            return folder
    looked_for = "Mulish and Marelle" if not replaced else ", ".join(sorted(set(files.values())))
    raise FontError(f"no fonts folder with {looked_for} in "
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

    def __init__(self, path: Path, file: str = ""):
        data = path.read_bytes()
        info = FontFile(io.BytesIO(data))
        # Its path inside fonts/, as the pack names it.
        self.file = file or path.name
        # The characters met that this font cannot print, even from their parts.
        self.missing: set[str] = set()
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
        # HarfBuzz gives no positions at all for an empty text: a table row's
        # empty right cell is one.
        if not text:
            return ()
        buffer = hb.Buffer()
        buffer.add_codepoints([ord(character) for character in text])
        buffer.guess_segment_properties()
        hb.shape(self._hb, buffer)
        glyphs: list[Glyph] = []
        x = 0.0
        for info, position in zip(buffer.glyph_infos, buffer.glyph_positions):
            if info.codepoint == 0:  # .notdef: the font has nothing for it
                self.missing.add(text[info.cluster])
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

    def roles(self) -> dict[str, Face]:
        return {role: getattr(self, role) for role in DEFAULTS}


@lru_cache(maxsize=None)
def load(folder: Path, replaced: tuple[tuple[str, str], ...] = ()) -> Fonts:
    """The four faces, from ``folder``; ``replaced`` gives (role, path inside
    fonts/) for those the pack replaces."""
    files = {**DEFAULTS, **dict(replaced)}
    return Fonts(**{role: Face(folder / file, file) for role, file in files.items()})


def missing_notes(faces: Fonts, names: dict[str, str]) -> list[str]:
    """What the build says about the characters a face met and cannot print.
    ``names`` gives the pack's name for a replaced role's font."""
    notes = []
    for role, face in faces.roles().items():
        if face.missing:
            listed = " ".join(sorted(face.missing))
            notes.append(f"the {ROLE_NAMES[role]} font, {names.get(role, DEFAULT_NAMES[role])} "
                         f"(fonts/{face.file}), has no {listed}: "
                         f"printed as an empty box")
    return notes
