"""The adapted versions' layout: Dyslexie, Dyspraxie and TDAH ("versions
différenciées", versions.py).

They print the base booklet's content (a chapter that picks no sentence prints
the ones the base booklet chose for it) bigger and airier, measured on the
printed examples (Kalulu-Main's docs/booklet-versions/):

- script text 20 or 24 pt, with letter and word spacing; cursive is never
  spaced out, its letters are joined;
- a chapter over several pages: the title, the syllables and as many words as
  fit, then the words left, then the sentences on pages of their own, a
  sentence block never split across two pages;
- words in two columns or one per line, centred;
- the multi-letter graphemes coloured, and every silent letter grey (dyspraxia,
  adhd);
- 24 of the fluency test's items, on two pages of 3 × 4;
- a sentence table one column per page;
- writing pages on a wider ruling, the copies drawn as outlines to trace over;
- the page number bottom right, and an "adaptations" page before the back
  cover saying what this version changes.

Every measurement is a baseline-to-baseline distance or a position from the
page's top or left edge, in millimetres, as the reports give them.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from reportlab.lib.colors import HexColor, black, white
from reportlab.lib.units import mm
from reportlab.pdfgen.canvas import Canvas

from kalulu_booklets.content import (CURSIVE, EARLIER, OWN, SCRIPT, TOUCHING, Booklet, ChapterContent, Paragraph,
                                     Styled, TableRow)
from kalulu_booklets.fonts import Face, Fonts, Spacing
from kalulu_booklets.layout import (CURSIVE_SENTENCE_SIZE, INK, PAGE_HEIGHT, PAGE_WIDTH, PENGUIN_HEIGHT, SENTENCE_SIZE,
                                    Layout, Page, _picture, _stopwatch, _wrap)
from kalulu_booklets.versions import BASE, Version

SILENT = HexColor("#7f7f7f")
TINTS = {OWN: HexColor("#f3b267"), EARLIER: HexColor("#3d329f"), TOUCHING: HexColor("#9c484c")}
# The writing pages' ruling: fine blue lines, main grey ones, grey verticals.
RULE_FINE = HexColor("#b2d1ed")
RULE_MAIN = HexColor("#7f7f7f")
COPY_FILL = HexColor("#bfbfbf")
COPY_EDGE = HexColor("#a4a3a4")
TABLE_RULE = HexColor("#8a8a8a")

# Script only: +0.12 em after every letter, and a space of 0.52 em in all.
SPACING = Spacing(tracking=0.12, space=0.52)

TEXT_LEFT = 12.7 * mm
TEXT_RIGHT = 135.5 * mm
TEXT_WIDTH = TEXT_RIGHT - TEXT_LEFT
# The grids' columns: equal cells across 127 mm, each item centred in its own.
GRID_LEFT = 10.5 * mm
GRID_WIDTH = 127 * mm


def _top(millimetres: float) -> float:
    """A height ``millimetres`` from the top of the page."""
    return PAGE_HEIGHT - millimetres * mm


@dataclass(frozen=True)
class Style:
    size: float  # script text: syllables, words, sentences, tables, fluency
    cursive_size: float
    cursive: bool  # cursive in the chapters (titles and sentences)
    tinted: bool  # the multi-letter graphemes coloured
    all_silent: bool  # every silent letter grey, not only where the chapter asks
    one_sentence_a_line: bool  # each sentence starts a line of its own
    title_sizes: dict[int, float]
    first: float  # the first baseline of a page without a title, from the top
    last: float  # the lowest baseline, from the top
    line: float  # script lines in a block
    cursive_line: float
    block: float  # from a block's last line to the next one's first
    after_title: float
    syllable_row: float
    after_syllables: float
    word_row: float
    word_centres: tuple[float, ...]  # of the page's width
    table_row: float
    table_cells: float  # between two sentences of a sentence table
    story_size: float
    story_title_size: float
    story_line: float
    story_paragraph: float  # from a paragraph's last line to the next one's first
    fluency_size: float = 24


STYLES = {
    "dyslexia": Style(
        size=20, cursive_size=20 * CURSIVE_SENTENCE_SIZE / SENTENCE_SIZE, cursive=True, tinted=False,
        all_silent=False, one_sentence_a_line=False, title_sizes={1: 36, 2: 30, 3: 26},
        first=20.8, last=194, line=9.9, cursive_line=11.6, block=25, after_title=20.4,
        syllable_row=12, after_syllables=20.8, word_row=10.9, word_centres=(2 / 7, 5 / 7),
        table_row=15.4, table_cells=19.3, story_size=18, story_title_size=20, story_line=8.8, story_paragraph=17.6),
    "dyspraxia": Style(
        size=24, cursive_size=24, cursive=False, tinted=True, all_silent=True, one_sentence_a_line=True,
        title_sizes={1: 40, 2: 36, 3: 30}, first=22, last=186, line=17.6, cursive_line=17.6, block=42.3,
        after_title=27.5, syllable_row=19.8, after_syllables=32.1, word_row=19.8, word_centres=(1 / 2,),
        table_row=25, table_cells=42.3, story_size=24, story_title_size=24, story_line=17.6, story_paragraph=35.3),
    "adhd": Style(
        size=24, cursive_size=24 * CURSIVE_SENTENCE_SIZE / SENTENCE_SIZE, cursive=True, tinted=True,
        all_silent=True, one_sentence_a_line=False, title_sizes={1: 40, 2: 36, 3: 30},
        first=22, last=186, line=17.6, cursive_line=17.6, block=42.3, after_title=27,
        syllable_row=19.75, after_syllables=32, word_row=19.75, word_centres=(1 / 2,),
        table_row=25, table_cells=42.3, story_size=24, story_title_size=24, story_line=17.6, story_paragraph=35.3),
}

# The most columns for which the widest syllable fits its cell with 0.3 em to
# spare: the printed booklets keep "coi cou" in 6 and put "vou mou" in 4.
SYLLABLE_COLUMNS = (6, 4, 3)
SYLLABLE_SPARE = 0.3

# The fluency test: 3 columns of 4 rows a page, in a rounded box.
FLUENCY_COLUMNS = (29.5, 74.0, 118.6)  # centres, from the left
FLUENCY_ROWS = (63.1, 93.0, 123.0, 153.0)  # baselines, from the top
FLUENCY_BOX = (4.2, 35.8, 143.8, 174.2)  # left, top, right, bottom
FLUENCY_KEPT = 3  # of each row of 5
STOPWATCH = 9.5
STOPWATCH_TOP = 184  # the first one's centre, below the box

# The writing pages: main lines every 15.93 mm, four fine intervals between
# them; a model row on every other main line; verticals every 15.95 mm.
RULE_INTERVAL = 15.93 / 4
RULE_MAIN_TOP = 31.9
RULE_MAINS = 11
RULE_LEFT, RULE_RIGHT = 4.5, 142.4
VERTICAL_FIRST, VERTICAL_STEP = 20.6, 15.95
MODEL_LEFT = 21.3
COPY_ROOM = 6  # the least room before the next copy
CATERPILLAR_HEIGHT = 9

FOLIO_SIZE = 14
FOLIO_RIGHT = 138.5
FOLIO_BASELINE = 200.5

# The adaptations page (the examples' text), by language. A language missing
# here has no such page, and the build says so.
ADAPTATIONS = ("font", "word spacing", "letter spacing", "line spacing", "fewer items", "graphemes coloured",
               "silent letters coloured", "script only")
ADAPTATIONS_TEXT = {
    "fr": {
        "intro": "Ce livret différencié est conçu pour répondre à certains symptômes fréquents des troubles de "
                 "l’apprentissage. Il existe plusieurs versions des livrets différenciés, chaque version répond à "
                 "des symptômes différents. Ce livret suit les adaptations suivantes :",
        "heading": "Adaptation :",
        "rows": {
            "font": "Augmentation de la police",
            "word spacing": "Augmentation de l’espacement entre les mots",
            "letter spacing": "Augmentation de l’espacement entre les lettres",
            "line spacing": "Augmentation de l’interligne",
            "fewer items": "Réduction du nombre d’items par page",
            "graphemes coloured": "Coloration des digrammes et trigrammes",
            "silent letters coloured": "Coloration des graphèmes silencieux",
            "script only": "Utiliser uniquement une police script",
        },
        "no writing": "De plus, il n’y a pas de lignes d’écriture dans ces livrets car l’écriture n’est pas un moyen "
                      "d’apprentissage chez la plupart des élèves dyspraxiques. Si vous voulez en ajouter, nous vous "
                      "conseillons de suivre les conseils de l’association Le Cartable Fantastique.",
        "closing": ("Si on suit les données scientifiques sur le sujet, nous conseillons ces adaptations {readers}.",
                    "N’hésitez pas à nous envoyer vos commentaires à contact@excellolab.org."),
    },
}
ADAPTATIONS_SIZE = 11
ADAPTATIONS_LINE = 6.2
ADAPTATIONS_ROW = 8.5


def fluency_items(items: list[Styled]) -> list[Styled]:
    """The 24 items of a fluency test: the base's are rows of 5, and the first
    3 of rows 1-4 and of rows 7-10 are kept, its easier and its harder half. A
    shorter test keeps the first 3 of each of its rows, at most 24."""
    rows = [items[start:start + 5] for start in range(0, len(items), 5)]
    if len(rows) >= 10:
        rows = rows[0:4] + rows[6:10]
    return [item for row in rows for item in row[:FLUENCY_KEPT]][:24]


@dataclass
class _Line:
    face: Face
    size: float
    words: list[Styled]
    spacing: Spacing | None
    pitch: float  # from the line above, in a block
    centred: bool = False


@dataclass
class _Block:
    lines: list[_Line] = field(default_factory=list)


class AdaptedLayout(Layout):
    """Lays out a booklet in an adapted version."""

    def __init__(self, booklet: Booklet, fonts: Fonts, version: Version = BASE,
                 chosen: dict[int, list[int]] | None = None):
        super().__init__(booklet, fonts, version, chosen)
        self.style = STYLES[version.adapted]
        if chosen is None:
            # The sentences the base booklet chose, laid out apart so its notes
            # are not said twice.
            notes = list(booklet.notes)
            base = Layout(booklet, fonts, BASE)
            base.run()
            booklet.notes[:] = notes
            self.chosen = base.chosen
        self.baseline: float | None = None  # the last one placed on this page

    # --- Pages ---------------------------------------------------------------------

    def new_page(self, numbered: bool = True, shares_next_number: bool = False) -> Page:
        page = super().new_page(numbered, shares_next_number)
        self.baseline = None
        return page

    def place(self, gap: float, below: float = 0.0) -> float:
        """The baseline of something ``gap`` below the last one placed (the
        page's first baseline on a fresh page), reaching ``below`` further down
        with its other lines; on a new page when it does not fit here."""
        last = _top(self.style.last)
        if self.baseline is not None:
            first = self.baseline - gap
            if first - below >= last:
                self.baseline = first - below
                return first
            self.new_page()
        first = _top(self.style.first)
        self.baseline = first - below
        return first

    def draw_folio(self, canvas: Canvas, number: int) -> None:
        text = str(number)
        face = self.fonts.script
        face.draw(canvas, FOLIO_RIGHT * mm - face.width(text, FOLIO_SIZE), _top(FOLIO_BASELINE), text, FOLIO_SIZE, INK)

    def run(self) -> list[Page]:
        self.cover()
        for chapter in self.booklet.chapters:
            self.chapter(chapter)
        text = ADAPTATIONS_TEXT.get(self.booklet.locale.split("_")[0])
        if text is None:
            self.booklet.notes.append(f"the {self.version.name} version has no adaptations page in this language: "
                                      "its text is to be written (adapted.ADAPTATIONS_TEXT)")
        # The adaptations page and the back cover close the last folded sheet.
        while (len(self.pages) + (2 if text else 1)) % 4:
            self.new_page(numbered=False)
        if text:
            self.adaptations(text)
        self.back_cover()
        return self.pages

    # --- Text ------------------------------------------------------------------------

    def face(self, font: str) -> Face:
        return self.fonts.cursive if font == CURSIVE and self.style.cursive else self.fonts.script

    def font_of(self, font: str) -> str:
        return CURSIVE if font == CURSIVE and self.style.cursive else SCRIPT

    def spacing(self, face: Face) -> Spacing | None:
        return None if face is self.fonts.cursive else SPACING

    def marks(self, item: Styled) -> tuple[frozenset[int], dict[int, object]]:
        """The letters printed grey, and the colours of the others."""
        grey = item.silent if self.style.all_silent else item.grey
        colors: dict[int, object] = {}
        if self.style.tinted:
            for start, end, kind in item.tints:
                for index in range(start, end):
                    colors[index] = TINTS[kind]
        return grey, colors

    def draw_text(self, canvas: Canvas, face: Face, x: float, y: float, item: Styled, size: float,
                  tinted: bool = True) -> float:
        grey, colors = self.marks(item)
        return face.draw(canvas, x, y, item.text, size, INK, grey, SILENT, colors if tinted else None,
                         self.spacing(face))

    def width(self, face: Face, text: str, size: float) -> float:
        return face.width(text, size, self.spacing(face))

    def draw_line(self, canvas: Canvas, line: _Line, baseline: float, left: float = TEXT_LEFT,
                  width: float = TEXT_WIDTH) -> None:
        space = line.face.width(" ", line.size, line.spacing)
        total = sum(self.width(line.face, word.text, line.size) for word in line.words) + space * (len(line.words) - 1)
        x = left + (width - total) / 2 if line.centred else left
        for word in line.words:
            x += self.draw_text(canvas, line.face, x, baseline, word, line.size) + space

    def lines_of(self, font: str, pieces: list[list[Styled]], size: float | None = None, centred: bool = False,
                 width: float = TEXT_WIDTH, pitch: float | None = None) -> list[_Line]:
        """``pieces`` (lines of sentences sharing them) wrapped at ``width``."""
        font = self.font_of(font)
        face = self.face(font)
        size = size or (self.style.cursive_size if font == CURSIVE else self.style.size)
        pitch = pitch or (self.style.cursive_line if font == CURSIVE else self.style.line) * mm
        spacing = self.spacing(face)
        return [_Line(face, size, words, spacing, pitch, centred)
                for words in _wrap(face, Paragraph(font, pieces), size, width, spacing)]

    def put_block(self, content: ChapterContent, lines: list[_Line], gap: float, left: float = TEXT_LEFT,
                  width: float = TEXT_WIDTH) -> None:
        """A block of lines on one page, never split; one taller than a page
        runs over, as in the printed booklets."""
        if not lines:
            return
        below = sum(line.pitch for line in lines[1:])
        if below > _top(self.style.first) - _top(self.style.last):
            for index, line in enumerate(lines):
                baseline = self.place(gap if index == 0 else line.pitch)
                self.add(lambda canvas, line=line, baseline=baseline: self.draw_line(canvas, line, baseline, left, width))
            return
        first = self.place(gap, below)
        baselines = [first]
        for line in lines[1:]:
            baselines.append(baselines[-1] - line.pitch)

        def draw(canvas: Canvas) -> None:
            for line, baseline in zip(lines, baselines):
                self.draw_line(canvas, line, baseline, left, width)

        self.add(draw)

    # --- A chapter -----------------------------------------------------------------

    def chapter(self, content: ChapterContent) -> None:
        style = self.style
        self.new_page()
        if content.title:
            self.y = _top(17)
            self.baseline = self.title(content.title, style.title_sizes, cursive_too=style.cursive)
        gap = style.after_title * mm
        if content.syllables:
            self.grid(content, content.syllables, self.syllable_columns(content.syllables), style.syllable_row,
                      gap, tinted=False)
            gap = style.after_syllables * mm
        if content.words:
            self.words(content, gap)
        self.chapter_sentences(content)
        for index, table in enumerate(content.tables):
            self.table(content, table, with_penguin=index == 0)
        for title, paragraphs in content.stories:
            self.story(content, title, paragraphs)
        if self.version.writing and content.writing and content.writing_models + content.writing_tracings > 0:
            self.writing(content)
        if content.fluency:
            self.fluency(content, content.fluency)

    def syllable_columns(self, items: list[Styled]) -> int:
        face, size = self.fonts.script, self.style.size
        widest = max(self.width(face, item.text, size) for item in items)
        for columns in SYLLABLE_COLUMNS:
            if widest + SYLLABLE_SPARE * size <= GRID_WIDTH / columns:
                return columns
        return SYLLABLE_COLUMNS[-1]

    def grid(self, content: ChapterContent, items: list[Styled], columns: int, row: float, gap: float,
             tinted: bool = True, centres: list[float] | None = None) -> None:
        """Rows of ``columns`` items, each centred in its cell, ``row`` mm
        apart; rows that do not fit go on the next page."""
        face, size = self.fonts.script, self.style.size
        centres = centres or [GRID_LEFT + (column + 0.5) * GRID_WIDTH / columns for column in range(columns)]
        cell = GRID_WIDTH / len(centres)
        for item in items:
            if self.width(face, item.text, size) > cell:
                self.note(content, f"\"{item.text}\" is wider than its cell: check it does not run into its neighbour")
        for start in range(0, len(items), len(centres)):
            baseline = self.place(gap if start == 0 else row * mm)
            chunk = items[start:start + len(centres)]

            def draw(canvas: Canvas, chunk: list[Styled] = chunk, baseline: float = baseline) -> None:
                for item, centre in zip(chunk, centres):
                    self.draw_text(canvas, face, centre - self.width(face, item.text, size) / 2, baseline, item, size,
                                   tinted)

            self.add(draw)

    def words(self, content: ChapterContent, gap: float) -> None:
        self.grid(content, content.words, 0, self.style.word_row, gap,
                  centres=[PAGE_WIDTH * centre for centre in self.style.word_centres])

    def chapter_sentences(self, content: ChapterContent) -> None:
        """On pages of their own, block after block: the chapter's paragraphs,
        or each sentence the base booklet chose for it."""
        blocks: list[tuple[str, list[list[Styled]]]] = []
        if content.paragraphs:
            for paragraph in content.paragraphs:
                lines = paragraph.lines
                if self.style.one_sentence_a_line:
                    lines = [[piece] for line in lines for piece in line]
                blocks.append((paragraph.font, lines))
        elif content.sentence_pool:
            pool = dict(content.sentence_pool)
            chosen = [sentence_id for sentence_id in self.chosen.get(content.chapter.id, []) if sentence_id in pool]
            for placed, sentence_id in enumerate(chosen):
                text = pool[sentence_id]
                if int((placed + 1) * content.sentence_uppercase) > int(placed * content.sentence_uppercase):
                    text = text.upper()
                blocks.append((content.sentence_fonts[placed % 2], [[piece] for piece in text.lines()]))
        if not blocks:
            return
        self.new_page()
        for font, pieces in blocks:
            self.put_block(content, self.lines_of(font, pieces), self.style.block * mm)

    def table(self, content: ChapterContent, rows: list[TableRow], with_penguin: bool = False) -> None:
        if any(_is_sentence(cell.text) for row in rows if not row.bold for cell in (row.left, row.right)):
            self.sentence_table(content, rows)
            return
        self.new_page()
        style, size = self.style, self.style.size
        if with_penguin:
            self.add(lambda canvas: _picture(canvas, "penguin", PAGE_WIDTH / 2, _top(8), PENGUIN_HEIGHT * 1.25,
                                             centered=True))
            # The first row's baseline 0.6 of a row under the penguin.
            self.baseline = _top(8) - PENGUIN_HEIGHT * 1.25 + 0.4 * style.table_row * mm
        centres = [PAGE_WIDTH * 2 / 7, PAGE_WIDTH * 5 / 7]
        for row in rows:
            baseline = self.place(style.table_row * mm)
            face = self.fonts.script_bold if row.bold else self.fonts.script

            def draw(canvas: Canvas, row: TableRow = row, baseline: float = baseline, face: Face = face) -> None:
                for cell, centre in zip((row.left, row.right), centres):
                    if cell.text:
                        self.draw_text(canvas, face, centre - self.width(face, cell.text, size) / 2, baseline, cell,
                                       size)
                if row.bold:
                    canvas.setStrokeColor(TABLE_RULE)
                    canvas.setLineWidth(0.75)
                    rule = baseline - 0.35 * style.table_row * mm
                    canvas.line(GRID_LEFT, rule, GRID_LEFT + GRID_WIDTH, rule)

            self.add(draw)

    def sentence_table(self, content: ChapterContent, rows: list[TableRow]) -> None:
        """Each column on pages of its own: its header, then its sentences,
        centred and wrapped."""
        for side in ("left", "right"):
            cells = [(row.bold, getattr(row, side)) for row in rows if getattr(row, side).text]
            if not cells:
                continue
            self.new_page()
            for bold, cell in cells:
                if bold:
                    face = self.fonts.script_bold
                    lines = [_Line(face, self.style.size, words, SPACING, self.style.line * mm, centred=True)
                             for words in _wrap(face, Paragraph(SCRIPT, [[cell]]), self.style.size, TEXT_WIDTH,
                                                SPACING)]
                else:
                    lines = self.lines_of(SCRIPT, [[cell]], centred=True)
                self.put_block(content, lines, self.style.table_cells * mm)

    def story(self, content: ChapterContent, title: str, paragraphs: list[Styled]) -> None:
        """Paragraphs flowing from page to page, left aligned."""
        style = self.style
        self.new_page()
        if title:
            bold = self.fonts.script_bold
            baseline = self.place(0)
            title_line = _Line(bold, style.story_title_size, [Styled(title)], SPACING, 0)
            self.add(lambda canvas: self.draw_line(canvas, title_line, baseline))
        face = self.fonts.script
        for index, text in enumerate(paragraphs):
            lines = _wrap(face, Paragraph(SCRIPT, [[piece] for piece in text.lines()]), style.story_size, TEXT_WIDTH,
                          SPACING)
            for number, words in enumerate(lines):
                gap = (style.story_paragraph if number == 0 and index else style.story_line) * mm
                if number == 0 and index == 0:
                    gap = 2 * style.story_line * mm
                baseline = self.place(gap)
                line = _Line(face, style.story_size, words, SPACING, 0)
                self.add(lambda canvas, line=line, baseline=baseline: self.draw_line(canvas, line, baseline))

    def writing(self, content: ChapterContent) -> None:
        """A model in black then its copies to trace over, outlined, on every
        other main line; the main line between is left to write on."""
        face = self.fonts.cursive if content.writing_font == CURSIVE else self.fonts.script
        size = RULE_INTERVAL * mm / face.x_height
        model_lines = [_top(RULE_MAIN_TOP + line * 4 * RULE_INTERVAL) for line in range(1, RULE_MAINS, 2)]
        verticals = [VERTICAL_FIRST + index * VERTICAL_STEP for index in range(20)
                     if VERTICAL_FIRST + index * VERTICAL_STEP < RULE_RIGHT]
        copies = [False] * content.writing_models + [True] * content.writing_tracings
        rows: list[list[tuple[float, str, bool]]] = []
        for item in content.writing:
            width = face.width(item, size)
            current: list[tuple[float, str, bool]] = []
            x = MODEL_LEFT
            for traced in copies:
                if current and x + width / mm > RULE_RIGHT:
                    rows.append(current)
                    current, x = [], MODEL_LEFT
                current.append((x, item, traced))
                # The next copy starts at a vertical line, a little room after.
                end = x + width / mm + COPY_ROOM
                x = next((vertical for vertical in verticals if vertical >= end), end)
            rows.append(current)
        for start in range(0, len(rows), len(model_lines)):
            self.new_page()
            page_rows = rows[start:start + len(model_lines)]

            def draw(canvas: Canvas, page_rows=page_rows) -> None:
                _ruling(canvas, verticals)
                _picture(canvas, "caterpillar", 6 * mm, _top(4), CATERPILLAR_HEIGHT * mm)
                for baseline, row in zip(model_lines, page_rows):
                    for x, text, traced in row:
                        if traced:
                            face.draw(canvas, x * mm, baseline, text, size, COPY_FILL, outline=(COPY_EDGE, 0.5))
                        else:
                            face.draw(canvas, x * mm, baseline, text, size, black)

            self.add(draw)

    def fluency(self, content: ChapterContent, items: list[Styled]) -> None:
        kept = fluency_items(items)
        face, size = self.fonts.script, self.style.fluency_size
        per_page = len(FLUENCY_COLUMNS) * len(FLUENCY_ROWS)
        for start in range(0, len(kept), per_page):
            self.new_page()
            chunk = kept[start:start + per_page]

            def draw(canvas: Canvas, chunk: list[Styled] = chunk) -> None:
                left, top, right, bottom = FLUENCY_BOX
                canvas.setFillColor(white)
                canvas.setStrokeColor(black)
                canvas.setLineWidth(1)
                canvas.roundRect(left * mm, _top(bottom), (right - left) * mm, (bottom - top) * mm, 6 * mm,
                                 stroke=1, fill=1)
                for index in range(2):
                    _stopwatch(canvas, 17 * mm, _top(STOPWATCH_TOP + index * 12), STOPWATCH * mm)
                for index, item in enumerate(chunk):
                    centre = FLUENCY_COLUMNS[index % len(FLUENCY_COLUMNS)] * mm
                    baseline = _top(FLUENCY_ROWS[index // len(FLUENCY_COLUMNS)])
                    self.draw_text(canvas, face, centre - self.width(face, item.text, size) / 2, baseline, item, size)

            self.add(draw)

    # --- The adaptations page ------------------------------------------------------

    def adaptations(self, text: dict) -> None:
        """What this version changes, as the examples' table, and who it is
        advised for."""
        self.new_page(numbered=False)
        face, bold = self.fonts.script, self.fonts.script_bold
        size, line = ADAPTATIONS_SIZE, ADAPTATIONS_LINE * mm
        language = self.booklet.locale.split("_")[0]
        readers = dict(self.version.readers).get(language, "")

        def paragraph(words_of: str, at: float) -> tuple[list[tuple[list[Styled], float]], float]:
            placed = []
            for words in _wrap(face, Paragraph(SCRIPT, [[Styled(words_of)]]), size, TEXT_WIDTH):
                placed.append((words, at))
                at -= line
            return placed, at

        lines, y = paragraph(text["intro"], _top(30))
        table_top = y - line / 2
        rows = [(text["rows"][key], key in self.version.adaptations) for key in ADAPTATIONS]
        after = table_top - (len(rows) + 1) * ADAPTATIONS_ROW * mm - line
        tail = [text["no writing"]] if not self.version.writing and "no writing" in text else []
        tail.extend(piece.format(readers=readers).replace(" .", ".") for piece in text["closing"])
        for piece in tail:
            more, after = paragraph(piece, after)
            lines.extend(more)
            after -= line / 2
        mark_x = TEXT_RIGHT - 12 * mm

        def draw(canvas: Canvas) -> None:
            space = face.width(" ", size)
            for words, baseline in lines:
                x = TEXT_LEFT
                for word in words:
                    x += face.draw(canvas, x, baseline, word.text, size, INK) + space
            canvas.setStrokeColor(TABLE_RULE)
            canvas.setLineWidth(0.6)
            row = ADAPTATIONS_ROW * mm
            bottom = table_top - (len(rows) + 1) * row
            canvas.rect(TEXT_LEFT, bottom, TEXT_WIDTH, table_top - bottom)
            canvas.line(mark_x - 12 * mm, table_top, mark_x - 12 * mm, bottom)
            for index, (label, ticked) in enumerate([(text["heading"], False)] + rows):
                top = table_top - index * row
                if index:
                    canvas.line(TEXT_LEFT, top, TEXT_LEFT + TEXT_WIDTH, top)
                baseline = top - row / 2 - face.x_height * size / 2
                (bold if index == 0 else face).draw(canvas, TEXT_LEFT + 2 * mm, baseline, label, size, INK)
                if ticked:
                    face.draw(canvas, mark_x - face.width("x", size) / 2, baseline, "x", size, INK)

        self.add(draw)


def _is_sentence(text: str) -> bool:
    return text.rstrip().endswith((".", "!", "?", "…"))


def _ruling(canvas: Canvas, verticals: list[float]) -> None:
    """The writing page's ruling: four fine blue intervals between grey main
    lines, and grey verticals the whole height of the page."""
    left, right = RULE_LEFT * mm, RULE_RIGHT * mm
    canvas.setLineWidth(0.35)
    canvas.setStrokeColor(RULE_FINE)
    for main in range(RULE_MAINS - 1):
        for fine in range(1, 4):
            y = _top(RULE_MAIN_TOP + (main * 4 + fine) * RULE_INTERVAL)
            canvas.line(left, y, right, y)
    canvas.setStrokeColor(RULE_MAIN)
    canvas.setLineWidth(0.5)
    for main in range(RULE_MAINS):
        y = _top(RULE_MAIN_TOP + main * 4 * RULE_INTERVAL)
        canvas.line(left, y, right, y)
    for vertical in verticals:
        canvas.line(vertical * mm, 0, vertical * mm, PAGE_HEIGHT)
