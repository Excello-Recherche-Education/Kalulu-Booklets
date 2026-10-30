"""The versions of a booklet: the same content, printed for different readers.

Every version is derived from the base booklet's chapters; none needs content of
its own (Kalulu-Main's docs/BOOKLETS-FROM-PACKS.md, "The versions"). What they
change is how the pages are made:

- **base** — the booklet itself;
- **teacher** — before each chapter, a page with its title and its picture (the
  Look & Learn image of the chapter's ``ImageGPID``), carrying the same page
  number as the chapter page, so a teacher's copy and a pupil's agree;
- **no-writing** — without its writing pages;
- **dyslexia**, **dyspraxia**, **adhd** — the "versions différenciées" of the
  examples, for pupils with those difficulties: bigger and airier text, a
  chapter over several pages, a shorter fluency test, an "adaptations" page
  saying what was changed; dyspraxia also prints everything in script with no
  writing pages, and dyspraxia and adhd colour the multi-letter graphemes
  (adapted.py, and Kalulu-Main's docs/booklet-versions/ for the measurements).

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
    # Made up to a multiple of four pages with blank ones, for folded sheets.
    folded: bool = True
    # Also written as A4 sheets, imposed for a folded booklet.
    printed: bool = False
    # An adapted version's style (adapted.py's STYLES); "" for the base layout.
    adapted: str = ""
    # The adaptations page's rows ticked (adapted.ADAPTATIONS), and who the
    # version is advised for, by language.
    adaptations: tuple[str, ...] = ()
    readers: tuple[tuple[str, str], ...] = ()

    def label(self, locale: str) -> str:
        labels = dict(self.labels)
        return labels.get(locale.split("_")[0], labels.get("fr", ""))

    def file_name(self, locale: str, number: int, imposed: bool = False) -> str:
        suffix = "" if self.name == "base" else f"-{self.name}"
        return f"{locale}-booklet-{number}{suffix}{'-print' if imposed else ''}.pdf"


BASE = Version("base", printed=True)
TEACHER = Version("teacher", labels=(("fr", "Version enseignant"), ("es", "Versión docente"),
                                     ("pt", "Versão do professor")),
                  label_color=HexColor("#29367e"), teacher=True, folded=False)
NO_WRITING = Version("no-writing", writing=False, printed=True)

# The examples' "Version différenciée", each in its colour.
ADAPTED = (("fr", "Version différenciée"), ("es", "Versión diferenciada"), ("pt", "Versão diferenciada"))
# Every adapted version makes the text bigger and airier.
_AIRIER = ("font", "word spacing", "letter spacing", "line spacing")
DYSLEXIA = Version("dyslexia", labels=ADAPTED, label_color=HexColor("#f7931d"), adapted="dyslexia",
                   adaptations=_AIRIER, readers=(("fr", "aux élèves dyslexiques"),))
DYSPRAXIA = Version("dyspraxia", labels=ADAPTED, label_color=HexColor("#24aae1"), adapted="dyspraxia",
                    writing=False,
                    adaptations=_AIRIER + ("fewer items", "graphemes coloured", "silent letters coloured",
                                           "script only"),
                    readers=(("fr", "aux élèves dyspraxiques"),))
ADHD = Version("adhd", labels=ADAPTED, label_color=HexColor("#dc96c2"), adapted="adhd",
               adaptations=_AIRIER + ("fewer items", "graphemes coloured", "silent letters coloured"),
               readers=(("fr", "aux élèves avec des troubles de l’attention"),))

VERSIONS: dict[str, Version] = {version.name: version
                                for version in (BASE, TEACHER, NO_WRITING, DYSLEXIA, DYSPRAXIA, ADHD)}
