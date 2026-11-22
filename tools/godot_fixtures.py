"""Writes the reference values the Godot port's tests compare against.

While the generator is ported to Godot (Kalulu-Main's docs/BOOKLETS-GODOT-PORT.md),
the Python one is the oracle: these fixtures are what it, or the libraries it
uses, answer for the same inputs. They are committed, so the Godot tests run
without Python.

    .venv/bin/python tools/godot_fixtures.py

Fixtures that depend on a font name the font's SHA-256: a test whose font has
changed in Kalulu-Fonts since says so instead of comparing, and this script is
run again.
"""

from __future__ import annotations

import hashlib
import json
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "project" / "tests" / "fixtures"
sys.path.insert(0, str(ROOT / "src"))

# Seeds as content._seed() makes them, "<chapter id>:<part>", default chapters
# negative, plus a few that test the seeding itself.
SEEDS = ["1:1", "1:2", "42:2", "-7:1", "-123:2", "100000:1", "0:0", "", "é:1",
         "a long seed, longer than a SHA-512 block of one hundred and twenty-eight bytes, "
         "so that the digest's padding spans two blocks of the message"]
CHOICE_SIZES = [1, 2, 3, 4, 5, 7, 8, 9, 16, 17, 33, 100, 1000]


def write(name: str, data: object) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / name
    path.write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"wrote {path.relative_to(ROOT)}")


def random_fixture() -> dict:
    cases = []
    for seed in SEEDS:
        rng = random.Random(seed)
        # As exact 53-bit integers: Godot's JSON parser can miss a float's last bit.
        floats = [int(rng.random() * 2**53) for _ in range(8)]
        bits = [rng.getrandbits(k) for k in (1, 5, 31, 32, 0, 17)]
        below = [rng.choice(range(n)) for n in CHOICE_SIZES * 3]
        mixed = []
        for n in CHOICE_SIZES:
            mixed.append(rng.random() < 0.7)
            mixed.append(rng.choice(range(n)))
        cases.append({"seed": seed, "random": floats, "getrandbits": bits, "choice": below, "mixed": mixed})
    return {"choice_sizes": CHOICE_SIZES, "cases": cases}


def sha512_fixture() -> list:
    messages = ["", "abc", "1:1", "é:1", "x" * 111, "x" * 112, "x" * 127, "x" * 128, "x" * 129, "y" * 1000]
    return [{"message": message, "digest": hashlib.sha512(message.encode()).hexdigest()} for message in messages]


FONTS = ROOT / "kalulu-languages" / "fonts"
# What the booklets print, in their languages: accents, cursive joins, letters
# Marelle composes from a base and a combining accent, a hyphen, an apostrophe,
# capitals, and characters a font may lack.
TEXTS = ["la Lune", "Il a lu.", "toujours", "tou jours", "j'ai vu", "pique-nique", "¿Dónde está?",
         "¡Ñandú!", "Ação e coração", "á í ó ú ã ñ ü", "Él dijo «sí»", "ÉCOLE", "100 %", "", " ",
         "Kalulu", "ffi", "✓", "€", "Ŵ"]
SPACINGS = [(0.0, None), (0.05, None), (0.1, 0.5), (-0.02, 0.25)]


def fonts_fixture() -> dict:
    import uharfbuzz as hb
    from fontTools.pens.boundsPen import BoundsPen
    from fontTools.ttLib import TTFont as FontFile

    from kalulu_booklets import fonts

    out = {}
    for role, name in fonts.DEFAULTS.items():
        path = FONTS / name
        data = path.read_bytes()
        info = FontFile(str(path))
        face = fonts.Face(path, name)
        glyph_set = info.getGlyphSet()
        bounds = []
        for glyph_name in info.getGlyphOrder():
            pen = BoundsPen(glyph_set)
            glyph_set[glyph_name].draw(pen)
            bounds.append(list(pen.bounds) if pen.bounds else None)
        hb_font = hb.Font(hb.Face(hb.Blob(data)))
        shaped = {}
        for text in TEXTS:
            buffer = hb.Buffer()
            buffer.add_codepoints([ord(character) for character in text])
            buffer.guess_segment_properties()
            hb.shape(hb_font, buffer)
            pen = 0
            glyphs = []
            for glyph, position in zip(buffer.glyph_infos or (), buffer.glyph_positions or ()):
                glyphs.append([glyph.codepoint, glyph.cluster, pen + position.x_offset, position.y_offset,
                               position.x_advance])
                pen += position.x_advance
            shaped[text] = glyphs
        widths = {text: [face.width(text, 16.0, fonts.Spacing(tracking, space)) for tracking, space in SPACINGS]
                  for text in TEXTS}
        out[name] = {
            "role": role,
            "sha256": hashlib.sha256(data).hexdigest(),
            "units": face.units,
            "x_height": face.x_height,
            "cap_height": face.cap_height,
            "shaped": shaped,
            "ink": {text: list(face.ink(text)) for text in TEXTS},
            "widths": widths,
            "missing": sorted(face.missing),
            "bounds": bounds,
        }
    return {"texts": TEXTS, "spacings": [list(spacing) for spacing in SPACINGS], "fonts": out}


def vector_fixture() -> dict:
    from kalulu_booklets import vector

    out = {}
    for path in sorted((ROOT / "src" / "kalulu_booklets" / "art").glob("*.svg")):
        art = vector.read(path)
        out[path.name] = {
            "width": art.width,
            "height": art.height,
            "shapes": [{"color": [shape.color.red, shape.color.green, shape.color.blue], "opacity": shape.opacity,
                        "even_odd": shape.even_odd, "commands": [[command, *numbers] for command, numbers in shape.commands]}
                       for shape in art.shapes],
        }
    return out


def versions_fixture() -> dict:
    from kalulu_booklets.versions import VERSIONS

    out = {}
    for name, version in VERSIONS.items():
        color = version.label_color
        out[name] = {
            "labels": {locale: version.label(locale) for locale in ("fr_FR", "es_AR", "pt_BR", "it_IT")},
            "label_color": None if color is None else [color.red, color.green, color.blue],
            "label_bold": version.label_bold, "writing": version.writing, "teacher": version.teacher,
            "folded": version.folded, "printed": version.printed, "adapted": version.adapted,
            "adaptations": list(version.adaptations), "readers": dict(version.readers),
            "file_names": [version.file_name("fr_FR", 2), version.file_name("pt_BR", 1, True, "cursive"),
                           version.file_name("es_AR", 3, False, "script")],
        }
    return {"order": list(VERSIONS), "versions": out}


def main() -> int:
    write("python_random.json", random_fixture())
    write("sha512.json", sha512_fixture())
    write("fonts.json", fonts_fixture())
    write("vector_art.json", vector_fixture())
    write("versions.json", versions_fixture())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
