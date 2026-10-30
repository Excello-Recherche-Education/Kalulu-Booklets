"""The versions of a booklet: the same content, printed for different readers.

Every version is derived from the base booklet's chapters; none needs content of
its own (Kalulu-Main's docs/BOOKLETS-FROM-PACKS.md, "The versions"). What they
change is how the pages are made:

- **base** — the booklet itself;
- **teacher** — before each chapter, a page with its title and its picture (the
  Look & Learn image of the chapter's ``ImageGPID``), carrying the same page
  number as the chapter page, so a teacher's copy and a pupil's agree;
- **no-writing** — without its writing pages.

The base and no-writing versions are also written for printing: A4 landscape,
two A5 pages a sheet, in the order a folded and stapled booklet reads them.
"""

from __future__ import annotations

from dataclasses import dataclass

from reportlab.lib.colors import Color, HexColor


@dataclass(frozen=True)
class Version:
    name: str
    # A line under the cover's star, in its colour, by the pack's language (the
    # locale's first part); none for the base booklet. French is the examples';
    # the others are translations to have checked, and a language missing here
    # gets the French.
    labels: tuple[tuple[str, str], ...] = ()
    label_color: Color | None = None
    writing: bool = True
    teacher: bool = False
    # Also written as A4 sheets, imposed for a folded booklet.
    printed: bool = False

    def label(self, locale: str) -> str:
        labels = dict(self.labels)
        return labels.get(locale.split("_")[0], labels.get("fr", ""))

    def file_name(self, locale: str, number: int, imposed: bool = False) -> str:
        suffix = "" if self.name == "base" else f"-{self.name}"
        return f"{locale}-booklet-{number}{suffix}{'-print' if imposed else ''}.pdf"


BASE = Version("base", printed=True)
TEACHER = Version("teacher", labels=(("fr", "Version enseignant"), ("es", "Versión docente"),
                                     ("pt", "Versão do professor")),
                  label_color=HexColor("#29367e"), teacher=True)
NO_WRITING = Version("no-writing", writing=False, printed=True)

VERSIONS: dict[str, Version] = {version.name: version for version in (BASE, TEACHER, NO_WRITING)}
