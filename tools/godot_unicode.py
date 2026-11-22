"""Writes the Unicode tables the Godot port needs to treat text as Python does,
and the fixture its tests check them with.

    python3 tools/godot_unicode.py

- ``project/booklets/util/python_unicode_tables.gd``: what ``str.isspace()``
  calls whitespace; the characters whose ``str.lower()`` / ``str.upper()`` is
  more than one character (``text.lower()`` / ``upper()`` keep those as they
  are, and ``pack.title_for()`` prints the full form: "SS" for "ß"); and the
  canonical decompositions, compositions and combining classes of the Latin
  letters, since Godot 4.7 has no normalisation and ``Pack.picture()`` looks
  files up in NFC and NFD.
- ``project/tests/fixtures/unicode.json``: Python's answers on the same ranges.

Both are committed: they depend on Python's Unicode version, not on the packs.
"""

from __future__ import annotations

import json
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TABLES = ROOT / "project" / "booklets" / "util" / "python_unicode_tables.gd"
FIXTURE = ROOT / "project" / "tests" / "fixtures" / "unicode.json"

# The letters a pack's graphemes and phonemes are written with: Latin-1, the
# Latin Extended A and B blocks, and Latin Extended Additional (Vietnamese and
# the like). Combining marks are the 0300 block.
LATIN = [*range(0x00C0, 0x0250), *range(0x1E00, 0x1F00)]
MARKS = range(0x0300, 0x0370)
# The case mappings compared with Godot's: Latin, IPA, Greek, Cyrillic,
# Armenian, and the Latin and Greek extended blocks.
CASES = [*range(0x0000, 0x0590), *range(0x1E00, 0x2000)]


def characters() -> list[int]:
    return [code for code in range(0x110000) if not 0xD800 <= code <= 0xDFFF]


def gd_string(text: str) -> str:
    return '"' + "".join(f"\\u{ord(c):04x}" if ord(c) < 0x10000 else f"\\U{ord(c):06x}" for c in text) + '"'


def tables() -> str:
    spaces = [code for code in characters() if chr(code).isspace()]
    multi_lower = {code: chr(code).lower() for code in characters() if len(chr(code).lower()) > 1}
    multi_upper = {code: chr(code).upper() for code in characters() if len(chr(code).upper()) > 1}
    decompositions = {code: unicodedata.normalize("NFD", chr(code)) for code in LATIN
                      if unicodedata.normalize("NFD", chr(code)) != chr(code)}
    compositions = {}
    for code in LATIN:
        parts = unicodedata.decomposition(chr(code)).split()
        if len(parts) == 2 and not parts[0].startswith("<"):
            pair = chr(int(parts[0], 16)) + chr(int(parts[1], 16))
            if unicodedata.normalize("NFC", pair) == chr(code):
                compositions[pair] = code
    classes = {code: unicodedata.combining(chr(code)) for code in MARKS if unicodedata.combining(chr(code))}
    alnum: list[int] = []
    start = None
    for code in [*characters(), 0x110000]:
        is_alnum = code < 0x110000 and chr(code).isalnum()
        if is_alnum and start is None:
            start = code
        elif not is_alnum and start is not None:
            alnum += [start, code - 1]
            start = None

    def mapping(name: str, table: dict, key, value) -> list[str]:
        lines = [f"const {name} := {{"]
        lines += [f"\t{key(k)}: {value(v)}," for k, v in table.items()]
        return lines + ["}", ""]

    out = [
        "class_name PythonUnicodeTables",
        "extends RefCounted",
        "## Written by tools/godot_unicode.py from Python "
        f"{sys.version_info.major}.{sys.version_info.minor}'s Unicode {unicodedata.unidata_version}: do not edit.",
        "## See PythonUnicode for what each table is for.",
        "",
        "## The characters str.isspace() is true of.",
        "const SPACES := {",
        *[f"\t0x{code:04X}: true," for code in spaces],
        "}",
        "",
        "## Characters whose str.lower() is more than one character.",
        *mapping("MULTI_LOWER", multi_lower, lambda k: f"0x{k:04X}", gd_string),
        "## Characters whose str.upper() is more than one character.",
        *mapping("MULTI_UPPER", multi_upper, lambda k: f"0x{k:04X}", gd_string),
        "## NFD of the precomposed Latin letters.",
        *mapping("DECOMPOSITIONS", decompositions, lambda k: f"0x{k:04X}", gd_string),
        "## Canonical pairs composing into one Latin letter: base + mark -> letter.",
        *mapping("COMPOSITIONS", compositions, gd_string, lambda v: f"0x{v:04X}"),
        "## Canonical combining classes of the combining marks (0300-036F).",
        *mapping("COMBINING_CLASSES", classes, lambda k: f"0x{k:04X}", str),
        "## The characters str.isalnum() is true of, as [first, last] ranges, in order.",
        "const ALNUM_RANGES: Array[int] = [",
        *[f"\t{', '.join(f'0x{code:04X}' for code in alnum[index:index + 8])}," for index in range(0, len(alnum), 8)],
        "]",
        "",
    ]
    return "\n".join(out)


def fixture() -> dict:
    samples = []
    for code in LATIN:
        letter = chr(code)
        samples += [letter, unicodedata.normalize("NFD", letter), f"{letter}-{letter}", f"x{letter}y"]
    # Several marks on one letter, in either order, and marks with no base.
    samples += ["ậ", "ậ", "é́", "́a", "ç-s", "ç-s", "ã-ɐ̃",
                "ǖ", "ǖ", "q̇", "ñ", "ñ", ""]
    return {
        "unicode": unicodedata.unidata_version,
        "cases": {str(code): [chr(code).lower(), chr(code).upper()] for code in CASES},
        "spaces": [code for code in range(0x3001) if chr(code).isspace()],
        "alnum_texts": [[text, any(character.isalnum() for character in text)]
                        for text in ["«", "»", "!?", "…", "—", "a", "é", "١", "²", "Ⅻ", "¿¡", "«Oh", "x»", "...",
                                     "-", "'", "’", "%", "€", "ß", "ǅ", "ᾳ", "中", "🙂", "", " "]],
        "normalized": [[sample, unicodedata.normalize("NFC", sample), unicodedata.normalize("NFD", sample)]
                       for sample in dict.fromkeys(samples)],
        "strip": [[text, text.strip(), text.lstrip(), text.rstrip()]
                  for text in [" a ", " a ", "\n\t a b 　", "", "   ", "a", "​a​"]],
    }


def main() -> int:
    TABLES.write_text(tables() + "\n", encoding="utf-8")
    print(f"wrote {TABLES.relative_to(ROOT)}")
    FIXTURE.write_text(json.dumps(fixture(), ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"wrote {FIXTURE.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
