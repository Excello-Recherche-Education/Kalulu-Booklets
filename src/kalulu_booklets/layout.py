"""Placing a booklet's content on A5 pages, and writing the PDF.

Every measurement is here, in millimetres or points, so that the look of the
booklets can be tuned in one place. They are first values, to be adjusted
against the printed booklets.

A booklet is laid out in two passes: ``Layout`` decides what goes on which
page, as a list of drawing steps per page, and ``write()`` draws them, so that
blank pages can be added before the back cover to reach a multiple of four
(a booklet is printed on folded sheets).
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

from reportlab.lib.colors import HexColor, black, white
from reportlab.lib.pagesizes import A5
from reportlab.lib.units import mm
from reportlab.lib.utils import ImageReader
from reportlab.pdfgen.canvas import Canvas

from kalulu_booklets.content import CURSIVE, Booklet, ChapterContent, Paragraph, Styled, TableRow
from kalulu_booklets.fonts import Face, Fonts

PAGE_WIDTH, PAGE_HEIGHT = A5
MARGIN_SIDE = 14 * mm
MARGIN_TOP = 14 * mm
MARGIN_BOTTOM = 18 * mm
LEFT = MARGIN_SIDE
RIGHT = PAGE_WIDTH - MARGIN_SIDE
TOP = PAGE_HEIGHT - MARGIN_TOP
BOTTOM = MARGIN_BOTTOM
WIDTH = RIGHT - LEFT

INK = black
SILENT = HexColor("#9b9b9b")  # silent letters
TRACE = HexColor("#c9c9c9")  # writing copies to trace over
FOLIO = HexColor("#7a7a7a")  # page numbers
TABLE_RULE = HexColor("#8a8a8a")
BUBBLE = white  # the fluency bubble, white and outlined in black as in the printed booklets
BUBBLE_EDGE = black
STAR = HexColor("#f6c12e")
SEYES_MAIN = HexColor("#9488d4")
SEYES_FINE = HexColor("#d3cdef")
SEYES_MARGIN = HexColor("#e2827f")

GAP = 7 * mm  # between the blocks of a page

# Sizes measured on the printed booklets (2026-10-29): the width of the same
# text, in the same fonts, against ours. Text is never made smaller than these
# to fit: what is too wide spills over and is said (_wider_than()).
TITLE_SIZES = {1: 36, 2: 30, 3: 26}  # by the number of lines
TITLE_LEADING = 1.25
TITLE_LINE_GAP = 0.4  # the least room between two title lines' ink, in em
CURSIVE_TITLE_SCALE = 0.52  # of the script size: the printed titles' two columns stand as tall

SYLLABLE_SIZE = 16
SYLLABLE_ROW = 9.5 * mm  # 26.8 pt in the printed booklets
WORD_SIZE = 16
WORD_ROW = 8.8 * mm  # 25 pt in the printed booklets
CELL_PADDING = 2 * mm

SENTENCE_SIZE = 16
CURSIVE_SENTENCE_SIZE = 14.6  # Marelle stands taller: the printed booklets set it smaller
# Measured on the printed booklets: script lines 23.2 pt apart at 16 pt, cursive
# ones about 27 pt, and 40.6 pt from a cursive line to the next paragraph's
# first script line.
SCRIPT_LEADING = 1.45
CURSIVE_LEADING = 1.85  # of CURSIVE_SENTENCE_SIZE: 27 pt
PARAGRAPH_GAP = 0.67  # of the next paragraph's line

TABLE_SIZE = 16
TABLE_LEADING = 1.3  # a cell's wrapped lines
TABLE_ROW = 9 * mm
TABLE_WIDTH = 0.8 * WIDTH

STORY_TITLE_SIZE = 16
STORY_SIZE = 13
STORY_LEADING = 1.5

FLUENCY_SIZE = 14
FLUENCY_COLUMNS = 5
FLUENCY_ROW = 9 * mm  # at least; rows stretch to fill the page, up to FLUENCY_ROW_MOST
FLUENCY_ROW_MOST = 12 * mm
FLUENCY_PADDING = 5 * mm

# Seyès ruling: a thick line every four fine intervals. Lowercase letters are
# one interval high, as on a French school notebook.
SEYES_INTERVAL = 3 * mm
SEYES_LINES = 12  # writing lines per page
SEYES_MARGIN_LINE = LEFT + 12 * mm
COPY_GAP = 8 * mm

FOLIO_SIZE = 9
FOLIO_Y = 9 * mm

# The game's characters (art/LICENSE.md): the parakeet under the fluency test's
# bubble, the penguin above the tables, the caterpillar on the writing pages.
ART = Path(__file__).parent / "art"
PARAKEET_HEIGHT = 24 * mm
PENGUIN_HEIGHT = 12 * mm
CATERPILLAR_HEIGHT = 9 * mm
BUBBLE_TAIL = 8 * mm  # how far the fluency bubble's tail reaches down
STOPWATCH = 5 * mm

Draw = Callable[[Canvas], None]


@dataclass
class Page:
    steps: list[Draw] = field(default_factory=list)
    numbered: bool = True


class Layout:
    """Decides what goes on each page of one booklet."""

    def __init__(self, booklet: Booklet, fonts: Fonts):
        self.booklet = booklet
        self.fonts = fonts
        self.pages: list[Page] = []
        self.y = TOP
        # Sentences this booklet has printed, so a chosen one is not repeated
        # while others are left.
        self.printed_sentences: set[int] = set()

    # --- Pages ---------------------------------------------------------------------

    def new_page(self, numbered: bool = True) -> Page:
        self.pages.append(Page(numbered=numbered))
        self.y = TOP
        return self.pages[-1]

    @property
    def page(self) -> Page:
        return self.pages[-1]

    def room(self) -> float:
        return self.y - BOTTOM

    def add(self, step: Draw) -> None:
        self.page.steps.append(step)

    def note(self, chapter: ChapterContent, text: str) -> None:
        self.booklet.notes.append(f"{chapter.chapter.name}: {text}")

    def _wider_than(self, chapter: ChapterContent, face: Face, texts: list[str], size: float, width: float) -> None:
        """Text is never made smaller to fit a cell: one wider than its whole
        cell is printed at its size all the same, reaching into the next one,
        and said, so that the pack can be changed if it runs into its
        neighbour."""
        for text in texts:
            if text and face.width(text, size) > width:
                self.note(chapter, f"\"{text}\" is wider than its cell: check it does not run into its neighbour")

    # --- The booklet ---------------------------------------------------------------

    def run(self) -> list[Page]:
        self.cover()
        for chapter in self.booklet.chapters:
            self.chapter(chapter)
        # Blank pages before the back cover, to fill the last folded sheet.
        while (len(self.pages) + 1) % 4:
            self.new_page(numbered=False)
        self.back_cover()
        return self.pages

    def cover(self) -> None:
        self.new_page(numbered=False)
        number = str(self.booklet.number)
        black_face = self.fonts.script_black

        def draw(canvas: Canvas) -> None:
            _centered(canvas, black_face, "Kalulu", PAGE_HEIGHT * 0.72, 54, INK)
            _star(canvas, PAGE_WIDTH / 2, PAGE_HEIGHT * 0.42, 40 * mm, 17 * mm, STAR)
            size = 64
            _centered(canvas, black_face, number,
                      PAGE_HEIGHT * 0.42 - black_face.cap_height * size / 2, size, INK)

        self.add(draw)

    def back_cover(self) -> None:
        self.new_page(numbered=False)
        face = self.fonts.script_black
        self.add(lambda canvas: _centered(canvas, face, "Kalulu", 24 * mm, 20, FOLIO))

    # --- A chapter -----------------------------------------------------------------

    def chapter(self, content: ChapterContent) -> None:
        self.new_page()
        if content.title:
            self.title(content.title)
        if content.syllables:
            self.grid(content, content.syllables, content.syllable_columns, SYLLABLE_SIZE, SYLLABLE_ROW)
        if content.words:
            self.grid(content, content.words, content.word_columns, WORD_SIZE, WORD_ROW)
        if content.paragraphs:
            self.sentences(content)
        elif content.sentence_pool:
            self.chosen_sentences(content)
        for index, table in enumerate(content.tables):
            self.table(content, table, with_penguin=index == 0)
        for title, paragraphs in content.stories:
            self.story(content, title, paragraphs)
        if content.writing and content.writing_models + content.writing_tracings > 0:
            self.writing(content)
        if content.fluency:
            self.fluency(content, content.fluency)

    def title(self, lines: list[str]) -> None:
        """Script on the left; cursive, when the language has it, on the right."""
        script, cursive = self.fonts.script, self.fonts.cursive
        with_cursive = self.booklet.cursive
        half = WIDTH / 2 - 3 * mm if with_cursive else WIDTH
        size = TITLE_SIZES.get(len(lines), 22)
        for line in lines:
            size = min(size, _fit(script, line, half),
                       _fit(cursive, line, half) / CURSIVE_TITLE_SCALE if with_cursive else size)
        cursive_size = size * CURSIVE_TITLE_SCALE
        # Each line is placed by the ink of both columns, accents and loops
        # included, so that no line runs into the one above.
        inks = [[(face.ink(line)[0] * at, face.ink(line)[1] * at)
                 for face, at in ([(script, size), (cursive, cursive_size)] if with_cursive else [(script, size)])]
                for line in lines]
        tops = [max(top for top, _ in ink) for ink in inks]
        bottoms = [min(bottom for _, bottom in ink) for ink in inks]
        baselines = [self.y - tops[0]] if lines else []
        for index in range(1, len(lines)):
            step = max(size * TITLE_LEADING, -bottoms[index - 1] + tops[index] + TITLE_LINE_GAP * size)
            baselines.append(baselines[-1] - step)

        def draw(canvas: Canvas) -> None:
            # Each column centred in its half of the page, as printed; a line
            # starts where the column's widest one does, so lines align.
            script_left = (LEFT + WIDTH / 4 if with_cursive else PAGE_WIDTH / 2) \
                - max(script.width(line, size) for line in lines) / 2
            cursive_left = LEFT + 3 * WIDTH / 4 - max(cursive.width(line, cursive_size) for line in lines) / 2
            for line, baseline in zip(lines, baselines):
                script.draw(canvas, script_left, baseline, line, size, INK)
                if with_cursive:
                    cursive.draw(canvas, cursive_left, baseline, line, cursive_size, INK)

        self.add(draw)
        if lines:
            self.y = baselines[-1] + bottoms[-1] - GAP
        else:
            self.y -= GAP

    def grid(self, content: ChapterContent, items: list[Styled], columns: int, size: float, row: float) -> None:
        columns = max(1, min(columns, len(items)))
        rows = math.ceil(len(items) / columns)
        if rows * row > self.room():
            self.new_page()
        face = self.fonts.script
        cell = WIDTH / columns
        top = self.y
        self._wider_than(content, face, [item.text for item in items], size, cell)

        # Every item at the same size, a long one spilling out of its cell:
        # a smaller one among the others reads as different.
        def draw(canvas: Canvas) -> None:
            for index, item in enumerate(items):
                center_x = LEFT + (index % columns + 0.5) * cell
                center_y = top - (index // columns + 0.5) * row
                face.draw(canvas, center_x - face.width(item.text, size) / 2,
                          center_y - face.x_height * size / 2, item.text, size, INK, item.grey, SILENT)

        self.add(draw)
        self.y -= rows * row + GAP

    def sentences(self, content: ChapterContent) -> None:
        """On the page they start on, then on at most ``sentence_pages`` more;
        lines past that are left out and said."""
        limit = content.sentence_pages
        extra = 0
        dropped = 0
        self.printed_sentences.update(item.sentence_id for item in content.chapter.sentences)
        for index, paragraph in enumerate(content.paragraphs):
            face = self.fonts.cursive if paragraph.font == CURSIVE else self.fonts.script
            size = CURSIVE_SENTENCE_SIZE if paragraph.font == CURSIVE else SENTENCE_SIZE
            leading = size * (CURSIVE_LEADING if paragraph.font == CURSIVE else SCRIPT_LEADING)
            if index:
                self.y -= leading * PARAGRAPH_GAP
            for line in _wrap(face, paragraph, size, WIDTH):
                if dropped or leading > self.room():
                    if dropped or extra >= limit:
                        dropped += 1
                        continue
                    self.new_page()
                    extra += 1
                baseline = self.y - leading + (leading - face.x_height * size) / 2
                self.add(_line_step(face, line, baseline, size))
                self.y -= leading
        if dropped:
            room = "the page they start on" if not limit else f"that page and {limit} more"
            self.note(content, f"the sentences do not fit on {room} (SentencePages is {limit}): "
                               f"{dropped} line(s) are not printed")
        self.y -= GAP

    def chosen_sentences(self, content: ChapterContent) -> None:
        """A chapter that picks no sentence: as many of its pool as fit on the
        page they start on and on ``sentence_pages`` more, each whole. One that
        would run onto the next page is passed over for a later one that fits;
        one already printed in this booklet comes after the others. When too few
        of the pool hold one of the chapter's GPs to fill its pages, the others,
        earlier lessons' content, are printed too, and the build says so."""
        pool = sorted(content.sentence_pool, key=lambda candidate: candidate[0] in self.printed_sentences)
        printed: list[int] = []
        extra = 0
        placed = 0
        top_of_page = False
        while pool:
            fitting = None
            for index, (sentence_id, text) in enumerate(pool):
                font = content.sentence_fonts[placed % 2]
                face = self.fonts.cursive if font == CURSIVE else self.fonts.script
                size = CURSIVE_SENTENCE_SIZE if font == CURSIVE else SENTENCE_SIZE
                leading = size * (CURSIVE_LEADING if font == CURSIVE else SCRIPT_LEADING)
                if int((placed + 1) * content.sentence_uppercase) > int(placed * content.sentence_uppercase):
                    text = text.upper()
                lines = _wrap(face, Paragraph(font, [[piece] for piece in text.lines()]), size, WIDTH)
                gap = leading * PARAGRAPH_GAP if placed and not top_of_page else 0
                if gap + len(lines) * leading <= self.room():
                    fitting = (index, sentence_id, face, leading, lines, gap)
                    break
            if fitting is None:
                # Nothing left fits here: another page, if one is allowed and
                # this is not already a fresh one.
                if top_of_page or extra >= content.sentence_pages:
                    break
                self.new_page()
                extra += 1
                top_of_page = True
                continue
            index, sentence_id, face, leading, lines, gap = fitting
            self.y -= gap
            for line in lines:
                baseline = self.y - leading + (leading - face.x_height * size) / 2
                self.add(_line_step(face, line, baseline, size))
                self.y -= leading
            self.printed_sentences.add(sentence_id)
            printed.append(sentence_id)
            pool.pop(index)
            placed += 1
            top_of_page = False
        earlier = [sentence_id for sentence_id in printed if sentence_id not in content.sentences_teaching]
        if earlier:
            own = len(content.sentences_teaching)
            readable = ("no readable sentence holds one" if not own else
                        "only 1 readable sentence holds one" if own == 1 else
                        f"only {own} readable sentences hold one")
            self.note(content, f"not enough content of its own: {len(earlier)} of its {len(printed)} sentences "
                               f"{'holds' if len(earlier) == 1 else 'hold'} none of its GPs, taken from earlier "
                               f"lessons to fill its pages ({readable})")
        self.y -= GAP

    def table(self, content: ChapterContent, rows: list[TableRow], with_penguin: bool = False) -> None:
        penguin = PENGUIN_HEIGHT + GAP / 2 if with_penguin else 0
        if len(rows) * TABLE_ROW + penguin > self.room():
            self.new_page()
        if with_penguin:
            top_of_art = self.y
            self.add(lambda canvas: _picture(canvas, "penguin", PAGE_WIDTH / 2, top_of_art, PENGUIN_HEIGHT, centered=True))
            self.y -= penguin
        regular, bold = self.fonts.script, self.fonts.script_bold
        left = LEFT + (WIDTH - TABLE_WIDTH) / 2
        column = TABLE_WIDTH / 2
        inside = column - 2 * CELL_PADDING
        leading = TABLE_SIZE * TABLE_LEADING
        # A cell holding a sentence wraps onto more lines, as in the printed
        # booklets, and its row grows; a word too wide for the cell spills over.
        cells: list[tuple[list[list[Styled]], list[list[Styled]]]] = []
        heights: list[float] = []
        for row in rows:
            face = bold if row.bold else regular
            wrapped = tuple(_wrap(face, Paragraph("script", [[cell]]), TABLE_SIZE, inside) if cell.text else []
                            for cell in (row.left, row.right))
            for lines in wrapped:
                self._wider_than(content, face, [word.text for line in lines for word in line], TABLE_SIZE, column)
            cells.append(wrapped)
            tallest = max([len(lines) for lines in wrapped] + [1])
            heights.append(max(TABLE_ROW, tallest * leading + 2 * CELL_PADDING))
        height = sum(heights)
        if height > self.room():
            self.new_page()
        top = self.y

        def draw(canvas: Canvas) -> None:
            canvas.setStrokeColor(TABLE_RULE)
            canvas.setLineWidth(0.75)
            canvas.rect(left, top - height, TABLE_WIDTH, height)
            canvas.line(left + column, top, left + column, top - height)
            row_top = top
            for index, (row, wrapped, row_height) in enumerate(zip(rows, cells, heights)):
                if index:
                    canvas.line(left, row_top, left + TABLE_WIDTH, row_top)
                face = bold if row.bold else regular
                space = face.width(" ", TABLE_SIZE)
                for lines, x in zip(wrapped, (left, left + column)):
                    first = row_top - (row_height - len(lines) * leading) / 2 - leading / 2
                    for number, line in enumerate(lines):
                        width = sum(face.width(word.text, TABLE_SIZE) for word in line) + space * (len(line) - 1)
                        cursor = x + (column - width) / 2
                        baseline = first - number * leading - face.x_height * TABLE_SIZE / 2
                        for word in line:
                            cursor += face.draw(canvas, cursor, baseline, word.text, TABLE_SIZE, INK, word.grey, SILENT) + space
                row_top -= row_height

        self.add(draw)
        self.y -= height + GAP

    def story(self, content: ChapterContent, title: str, paragraphs: list[Styled]) -> None:
        self.new_page()
        if title:
            bold = self.fonts.script_bold
            top = self.y
            self.add(lambda canvas: _centered(canvas, bold, title, top - bold.cap_height * STORY_TITLE_SIZE,
                                              STORY_TITLE_SIZE, INK))
            self.y -= bold.cap_height * STORY_TITLE_SIZE + GAP
        face = self.fonts.script
        leading = STORY_SIZE * STORY_LEADING
        for index, text in enumerate(paragraphs):
            if index:
                self.y -= leading * PARAGRAPH_GAP
            for line in _wrap(face, Paragraph("script", [[piece] for piece in text.lines()]), STORY_SIZE, WIDTH):
                if leading > self.room():
                    self.new_page()
                baseline = self.y - leading + (leading - face.x_height * STORY_SIZE) / 2
                self.add(_line_step(face, line, baseline, STORY_SIZE))
                self.y -= leading
        self.y -= GAP

    def writing(self, content: ChapterContent) -> None:
        """Each item on its own ruled line, in black then in grey to trace over,
        and the line after it left empty to write on."""
        face = self.fonts.cursive if content.writing_font == CURSIVE else self.fonts.script
        size = SEYES_INTERVAL / face.x_height
        copies = [INK] * content.writing_models + [TRACE] * content.writing_tracings
        lines: list[list[tuple[float, str, object]]] = []
        for item in content.writing:
            width = face.width(item, size)
            current: list[tuple[float, str, object]] = []
            x = SEYES_MARGIN_LINE + 3 * mm
            for color in copies:
                if current and x + width > RIGHT:
                    lines.append(current)
                    current, x = [], SEYES_MARGIN_LINE + 3 * mm
                current.append((x, item, color))
                x += width + COPY_GAP
            lines.append(current)
            lines.append([])
        if lines and not lines[-1]:
            lines.pop()
        for start in range(0, len(lines), SEYES_LINES):
            self.new_page()
            page_lines = lines[start:start + SEYES_LINES]
            self.add(lambda canvas, page_lines=page_lines: _seyes(canvas, face, size, page_lines))

    def fluency(self, content: ChapterContent, items: list[Styled]) -> None:
        """A speech bubble the parakeet says, with two stopwatches beside it:
        the child reads the bubble aloud against the clock."""
        face = self.fonts.script
        below = BUBBLE_TAIL + PARAKEET_HEIGHT
        per_page = int((TOP - BOTTOM - below - 2 * FLUENCY_PADDING) // FLUENCY_ROW) * FLUENCY_COLUMNS
        cell = (WIDTH - 2 * FLUENCY_PADDING) / FLUENCY_COLUMNS
        self._wider_than(content, face, [item.text for item in items], FLUENCY_SIZE, cell)
        for start in range(0, len(items), per_page):
            self.new_page()
            chunk = items[start:start + per_page]
            rows = math.ceil(len(chunk) / FLUENCY_COLUMNS)
            # The bubble takes the page down to the parakeet, as the printed
            # booklets have it, its rows no further apart than FLUENCY_ROW_MOST.
            row_height = min(FLUENCY_ROW_MOST, (self.room() - below - 2 * FLUENCY_PADDING) / rows)
            height = rows * row_height + 2 * FLUENCY_PADDING
            top = self.y

            def draw(canvas: Canvas, chunk: list[Styled] = chunk, height: float = height, top: float = top,
                     row_height: float = row_height) -> None:
                bottom = top - height
                _bubble(canvas, LEFT, bottom, WIDTH, height, 6 * mm, PAGE_WIDTH / 2, BUBBLE_TAIL)
                _picture(canvas, "parakeet", PAGE_WIDTH / 2, bottom - BUBBLE_TAIL - 1 * mm, PARAKEET_HEIGHT, centered=True)
                for row in range(2):
                    _stopwatch(canvas, RIGHT - 18 * mm, bottom - BUBBLE_TAIL - 6 * mm - row * (STOPWATCH + 2 * mm), STOPWATCH)
                cell = (WIDTH - 2 * FLUENCY_PADDING) / FLUENCY_COLUMNS
                # One size for all: a test read against the clock must not
                # have a word printed smaller than the others.
                for index, item in enumerate(chunk):
                    center_x = LEFT + FLUENCY_PADDING + (index % FLUENCY_COLUMNS + 0.5) * cell
                    center_y = top - FLUENCY_PADDING - (index // FLUENCY_COLUMNS + 0.5) * row_height
                    face.draw(canvas, center_x - face.width(item.text, FLUENCY_SIZE) / 2,
                              center_y - face.x_height * FLUENCY_SIZE / 2, item.text, FLUENCY_SIZE, INK, item.grey, SILENT)

            self.add(draw)
            self.y -= height + below + GAP


# --- Writing the PDF ---------------------------------------------------------------

def write(booklet: Booklet, fonts: Fonts, path: Path) -> int:
    """Lays out and writes one booklet; returns its number of pages."""
    pages = Layout(booklet, fonts).run()
    path.parent.mkdir(parents=True, exist_ok=True)
    canvas = Canvas(str(path), pagesize=A5)
    canvas.setTitle(f"Kalulu - {booklet.locale} - {booklet.number}")
    canvas.setAuthor("Excello Recherche & Education")
    canvas.setSubject("Kalulu reading booklet")
    script = fonts.script
    for number, page in enumerate(pages, start=1):
        for step in page.steps:
            canvas.saveState()
            step(canvas)
            canvas.restoreState()
        if page.numbered:
            _centered(canvas, script, str(number), FOLIO_Y, FOLIO_SIZE, FOLIO)
        canvas.showPage()
    canvas.save()
    return len(pages)


# --- Drawing helpers ---------------------------------------------------------------

def _picture(canvas: Canvas, name: str, x: float, top: float, height: float, centered: bool = False) -> None:
    """One of the game's characters, ``height`` high, its top at ``top``; ``x``
    is its left edge, or its middle when ``centered``."""
    image = _image(name)
    width = height * image.getSize()[0] / image.getSize()[1]
    left = x - width / 2 if centered else x
    canvas.drawImage(image, left, top - height, width, height, mask="auto")


_IMAGES: dict[str, ImageReader] = {}


def _image(name: str) -> ImageReader:
    if name not in _IMAGES:
        _IMAGES[name] = ImageReader(str(ART / f"{name}.png"))
    return _IMAGES[name]


def _bubble(canvas: Canvas, x: float, y: float, width: float, height: float, radius: float,
            tail_x: float, tail: float) -> None:
    """A rounded speech bubble whose tail points down at ``tail_x``."""
    path = canvas.beginPath()
    half = tail * 0.75
    path.moveTo(x + radius, y)
    path.lineTo(tail_x - half, y)
    path.lineTo(tail_x, y - tail)
    path.lineTo(tail_x + half, y)
    path.lineTo(x + width - radius, y)
    path.arcTo(x + width - 2 * radius, y, x + width, y + 2 * radius, startAng=-90, extent=90)
    path.lineTo(x + width, y + height - radius)
    path.arcTo(x + width - 2 * radius, y + height - 2 * radius, x + width, y + height, startAng=0, extent=90)
    path.lineTo(x + radius, y + height)
    path.arcTo(x, y + height - 2 * radius, x + 2 * radius, y + height, startAng=90, extent=90)
    path.lineTo(x, y + radius)
    path.arcTo(x, y, x + 2 * radius, y + 2 * radius, startAng=180, extent=90)
    path.close()
    canvas.setFillColor(BUBBLE)
    canvas.setStrokeColor(BUBBLE_EDGE)
    canvas.setLineWidth(1)
    canvas.drawPath(path, stroke=1, fill=1)


def _stopwatch(canvas: Canvas, x: float, y: float, size: float) -> None:
    """A stopwatch ``size`` across, its dial centred at (x, y): a ring, the
    crown on top, the side button and one hand."""
    radius = size / 2
    stroke = size * 0.1
    canvas.setStrokeColor(INK)
    canvas.setFillColor(INK)
    canvas.setLineWidth(stroke)
    canvas.circle(x, y, radius - stroke / 2, stroke=1, fill=0)
    canvas.rect(x - size * 0.12, y + radius, size * 0.24, size * 0.1, stroke=0, fill=1)
    canvas.rect(x - size * 0.2, y + radius + size * 0.1, size * 0.4, size * 0.08, stroke=0, fill=1)
    side = math.radians(45)
    canvas.line(x + radius * math.cos(side), y + radius * math.sin(side),
                x + (radius + size * 0.12) * math.cos(side), y + (radius + size * 0.12) * math.sin(side))
    canvas.setLineWidth(stroke * 0.8)
    canvas.line(x, y, x + radius * 0.45, y + radius * 0.45)
    canvas.circle(x, y, stroke * 0.6, stroke=0, fill=1)


def _fit(face: Face, text: str, width: float) -> float:
    """The largest size at which ``text`` fits in ``width``."""
    at_one = face.width(text, 1)
    return width / at_one if at_one else 1000.0


def _centered(canvas: Canvas, face: Face, text: str, baseline: float, size: float, color: object) -> None:
    face.draw(canvas, (PAGE_WIDTH - face.width(text, size)) / 2, baseline, text, size, color)


def _star(canvas: Canvas, x: float, y: float, outer: float, inner: float, color: object) -> None:
    path = canvas.beginPath()
    for point in range(10):
        radius = outer if point % 2 == 0 else inner
        angle = math.pi / 2 + point * math.pi / 5
        px, py = x + radius * math.cos(angle), y + radius * math.sin(angle)
        path.moveTo(px, py) if point == 0 else path.lineTo(px, py)
    path.close()
    canvas.setFillColor(color)
    canvas.setStrokeColor(white)
    canvas.drawPath(path, stroke=0, fill=1)


def _slice(text: Styled, start: int, end: int) -> Styled:
    return Styled(text.text[start:end], frozenset(index - start for index in text.grey if start <= index < end))


def _joined(pieces: list[Styled]) -> Styled:
    """Sentences sharing a line, one space apart."""
    text, grey, offset = [], set(), 0
    for piece in pieces:
        if text:
            text.append(" ")
            offset += 1
        text.append(piece.text)
        grey.update(offset + index for index in piece.grey)
        offset += len(piece.text)
    return Styled("".join(text), frozenset(grey))


def _wrap(face: Face, paragraph: Paragraph, size: float, width: float) -> list[list[Styled]]:
    """A paragraph's printed lines, cut between words, as lists of words."""
    space = face.width(" ", size)
    printed: list[list[Styled]] = []
    for pieces in paragraph.lines:
        line = _joined(pieces)
        current: list[Styled] = []
        used = 0.0
        start = None
        bounds: list[tuple[int, int]] = []
        for index, character in enumerate(line.text + " "):
            if character == " ":
                if start is not None:
                    bounds.append((start, index))
                    start = None
            elif start is None:
                start = index
        for start, end in bounds:
            word = _slice(line, start, end)
            word_width = face.width(word.text, size)
            if current and used + space + word_width > width:
                printed.append(current)
                current, used = [], 0.0
            used += (space if current else 0) + word_width
            current.append(word)
        if current:
            printed.append(current)
    return printed


def _line_step(face: Face, words: list[Styled], baseline: float, size: float) -> Draw:
    def draw(canvas: Canvas) -> None:
        x = LEFT
        space = face.width(" ", size)
        for word in words:
            x += face.draw(canvas, x, baseline, word.text, size, INK, word.grey, SILENT) + space
    return draw


def _seyes(canvas: Canvas, face: Face, size: float, lines: list[list[tuple[float, str, object]]]) -> None:
    """A page of Seyès ruling, with the writing models on its lines."""
    step = 4 * SEYES_INTERVAL
    top = TOP - step  # room above the first writing line for tall letters
    canvas.setLineWidth(0.35)
    for line in range(SEYES_LINES + 1):
        main = top - line * step
        canvas.setStrokeColor(SEYES_MAIN)
        canvas.line(LEFT, main, RIGHT, main)
        if line < SEYES_LINES:
            canvas.setStrokeColor(SEYES_FINE)
            for fine in range(1, 4):
                canvas.line(LEFT, main - fine * SEYES_INTERVAL, RIGHT, main - fine * SEYES_INTERVAL)
    canvas.setStrokeColor(SEYES_MARGIN)
    canvas.setLineWidth(0.6)
    canvas.line(SEYES_MARGIN_LINE, top + step / 2, SEYES_MARGIN_LINE, top - SEYES_LINES * step)
    # The caterpillar, top left, in the room above the ruling.
    _picture(canvas, "caterpillar", LEFT, top + step / 2 + CATERPILLAR_HEIGHT + 1 * mm, CATERPILLAR_HEIGHT)
    for index, copies in enumerate(lines):
        baseline = top - (index + 1) * step
        for x, text, color in copies:
            face.draw(canvas, x, baseline, text, size, color)
