"""What each chapter of a booklet prints, decided from the pack.

This is where the PO's rules are applied (Kalulu-Main
``docs/BOOKLETS-FROM-PACKS.md``, and ``SCHEMA.md`` "The reading booklets"):
the automatic syllables and words, the entries in capitals, the paragraphs and
their fonts, the silent letters to print in grey. Nothing here knows about
pages; ``layout`` places what comes out of it.
"""

from __future__ import annotations

import random
import re
from dataclasses import dataclass, field
from pathlib import Path

from kalulu_booklets import pack as packs
from kalulu_booklets.pack import Chapter, Item, Pack, Sentence
from kalulu_booklets.text import lower, upper, word_spans, words_of

SCRIPT, CURSIVE = "script", "cursive"


# What a multi-letter grapheme is coloured as (Styled.tints), in the versions
# that colour them (versions.py): one the chapter teaches, one an earlier lesson
# taught, or one whose colour changes because it touches another coloured one
# ("chou": ch then ou), so that each stays visible; "qu" always has that colour.
OWN, EARLIER, TOUCHING = "own", "earlier", "touching"


@dataclass(frozen=True)
class Styled:
    """Text to print, with what its letters are: the positions to print in grey
    where the chapter asks for it (``grey``), every silent letter whatever the
    chapter asks (``silent``), and its multi-letter graphemes, as (start, end,
    kind) spans (``tints``)."""

    text: str
    grey: frozenset[int] = frozenset()
    silent: frozenset[int] = frozenset()
    tints: tuple[tuple[int, int, str], ...] = ()

    def upper(self) -> Styled:
        return Styled(upper(self.text), self.grey, self.silent, self.tints)

    def slice(self, start: int, end: int) -> Styled:
        """The characters ``start`` to ``end``, with what is marked among them."""
        inside = lambda positions: frozenset(index - start for index in positions if start <= index < end)  # noqa: E731
        return Styled(self.text[start:end], inside(self.grey), inside(self.silent),
                      tuple((max(begin, start) - start, min(finish, end) - start, kind)
                            for begin, finish, kind in self.tints if begin < end and finish > start))

    @staticmethod
    def joined(pieces: list[Styled]) -> Styled:
        """Pieces one space apart, as sentences sharing a line."""
        text: list[str] = []
        grey: set[int] = set()
        silent: set[int] = set()
        tints: list[tuple[int, int, str]] = []
        offset = 0
        for piece in pieces:
            if text:
                text.append(" ")
                offset += 1
            text.append(piece.text)
            grey.update(offset + index for index in piece.grey)
            silent.update(offset + index for index in piece.silent)
            tints.extend((offset + begin, offset + end, kind) for begin, end, kind in piece.tints)
            offset += len(piece.text)
        return Styled("".join(text), frozenset(grey), frozenset(silent), tuple(tints))

    def lines(self) -> list[Styled]:
        """Split at the line breaks a sentence may hold (SCHEMA.md)."""
        pieces: list[Styled] = []
        start = 0
        for end in [index for index, character in enumerate(self.text) if character == "\n"] + [len(self.text)]:
            raw = self.text[start:end]
            first = start + len(raw) - len(raw.lstrip())
            pieces.append(self.slice(first, first + len(raw.strip())))
            start = end + 1
        return pieces


@dataclass
class Paragraph:
    font: str
    # Printed lines, each made of sentences that share it.
    lines: list[list[Styled]]


@dataclass
class TableRow:
    left: Styled
    right: Styled
    bold: bool


@dataclass
class ChapterContent:
    chapter: Chapter
    title: list[str]
    syllables: list[Styled]
    syllable_columns: int
    words: list[Styled]
    word_columns: int
    paragraphs: list[Paragraph]
    # When the chapter picks no sentence: the ones the layout may choose from,
    # in order, as many as fit (each a paragraph of its own), those flagged
    # Uppercase already in capitals. The fonts paragraphs alternate between.
    sentence_pool: list[tuple[int, Styled]]
    sentence_fonts: tuple[str, str]
    # Pages the sentences may take after the one they start on; 0 for none.
    sentence_pages: int
    tables: list[list[TableRow]]
    writing: list[str]
    writing_font: str
    writing_models: int
    writing_tracings: int
    fluency: list[Styled]
    stories: list[tuple[str, list[Styled]]]
    # The pool's sentences that hold one of the chapter's GPs: the others are
    # earlier lessons' content, taken only to fill the pages.
    sentences_teaching: frozenset[int] = frozenset()
    # The chapter's picture for the teacher's page: its own booklet image, else
    # the Look & Learn image of its ImageGPID; None when it has none, or the
    # pack's images are not checked out.
    picture: Path | None = None
    # The syllables and words chosen, each once: what ``syllables`` and
    # ``words`` repeat when there are too few (see arranged()).
    syllable_choice: list[Styled] = field(default_factory=list)
    word_choice: list[Styled] = field(default_factory=list)

    def is_empty(self) -> bool:
        return not (self.title or self.syllables or self.words or self.paragraphs or self.sentence_pool
                    or self.tables or self.writing or self.fluency or self.stories)

    def syllables_in(self, columns: int) -> list[Styled]:
        """The syllables for a grid of ``columns``: an adapted version prints
        them in fewer, and a repeat must not land in the column it held above."""
        if columns == self.syllable_columns:
            return self.syllables
        return arranged(self.syllable_choice, len(self.syllables), columns, _seed(self.chapter, packs.SYLLABLES))

    def words_in(self, columns: int) -> list[Styled]:
        if columns == self.word_columns:
            return self.words
        return arranged(self.word_choice, len(self.words), columns, _seed(self.chapter, packs.WORDS))


@dataclass
class Booklet:
    locale: str
    number: int
    cursive: bool
    chapters: list[ChapterContent]
    # What a person should look at: content that cannot be printed as asked.
    notes: list[str] = field(default_factory=list)


def booklet(pack: Pack, number: int, series: str | None = None) -> Booklet:
    """Booklet ``number`` of the ``series`` given, "script" or "cursive" (by
    default the first the language prints, SCHEMA.md ``ScriptSeries`` /
    ``CursiveSeries``). The cursive series also prints its titles, sentences and
    writing pages in cursive; capitals are printed in the script series only, as
    the printed Brazilian booklets have them."""
    series = series or pack.series[0]
    cursive = series == CURSIVE
    capitals = pack.capitals and not cursive
    result = Booklet(pack.locale, number, cursive, [])
    for chapter in pack.chapters:
        if chapter.booklet != number:
            continue
        notes: list[str] = []
        content = _chapter(pack, chapter, notes, cursive, capitals)
        result.notes.extend(f"{chapter.name}: {note}" for note in notes)
        if content.is_empty():
            result.notes.append(f"{chapter.name}: prints nothing, so it has no page")
            continue
        result.chapters.append(content)
    return result


def _chapter(pack: Pack, chapter: Chapter, notes: list[str], cursive: bool, capitals: bool) -> ChapterContent:
    setting = lambda column: pack.setting(chapter, column)  # noqa: E731
    grey = chapter.grey_silent

    if chapter.image_id is not None and pack.chapter_picture(chapter) is None:
        image = pack.images.get(chapter.image_id)
        notes.append(f"its booklet image {f'booklet_images/{image.file}' if image else chapter.image_id} cannot be "
                     "printed: missing, not a PNG or JPEG, or not checked out (Git LFS); its teacher page is left out")
    syllable_columns, word_columns = int(setting("SyllableColumns")), int(setting("WordColumns"))
    syllable_count = _whole_rows(int(setting("SyllableCount")), syllable_columns, "Syllable", notes)
    word_count = _whole_rows(int(setting("WordCount")), word_columns, "Word", notes)
    syllable_choice = _picked(pack, chapter, packs.SYLLABLES, syllable_count, notes, capitals)
    word_choice = _picked(pack, chapter, packs.WORDS, word_count, notes, capitals)
    syllables = arranged(syllable_choice, syllable_count, syllable_columns, _seed(chapter, packs.SYLLABLES))
    words = arranged(word_choice, word_count, word_columns, _seed(chapter, packs.WORDS))
    # -1 prints no sentence at all.
    sentence_pages = int(setting("SentencePages"))
    if sentence_pages < 0 and chapter.sentences:
        notes.append(f"SentencePages is -1, so its {len(chapter.sentences)} sentence(s) are not printed")
    pool, teaching = _sentence_pool(pack, chapter, grey, capitals) if sentence_pages >= 0 and not chapter.sentences else ([], set())
    if sentence_pages >= 0 and not chapter.sentences and not pool:
        notes.append("no sentence is readable at this lesson")

    return ChapterContent(
        chapter=chapter,
        title=[line.strip() for line in chapter.title.split("\n")] if chapter.title.strip() else [],
        syllables=syllables,
        syllable_columns=syllable_columns,
        words=words,
        word_columns=word_columns,
        paragraphs=_paragraphs(pack, chapter, grey, notes, cursive, capitals) if sentence_pages >= 0 else [],
        sentence_pool=pool,
        sentence_fonts=(_paragraph_font(pack, chapter, 0, cursive), _paragraph_font(pack, chapter, 1, cursive)),
        sentence_pages=max(sentence_pages, 0),
        tables=_tables(pack, chapter, grey),
        writing=[entry.text for entry in chapter.entries.get(packs.WRITING, [])],
        writing_font=CURSIVE if cursive else SCRIPT,
        writing_models=int(setting("WritingModels")),
        writing_tracings=int(setting("WritingTracings")),
        fluency=[styled(pack, entry.text, grey, chapter=chapter) for entry in chapter.entries.get(packs.FLUENCY, [])],
        stories=[(story.title.strip(), [styled(pack, paragraph, grey, chapter=chapter)
                                        for paragraph in _story_paragraphs(story.text)])
                 for story in chapter.stories],
        sentences_teaching=frozenset(teaching),
        picture=pack.chapter_picture(chapter),
        syllable_choice=syllable_choice,
        word_choice=word_choice,
    )


# --- Syllables and words ---------------------------------------------------------

def _whole_rows(count: int, columns: int, kind: str, notes: list[str]) -> int:
    """A grid fills every row it starts (the PO's rule, 2026-11-09): 7 words in
    3 columns leave one alone on the last row, so 6 are printed. A count below
    one row is kept: it prints as one row of its own."""
    if columns < 1 or count <= columns or count % columns == 0:
        return count
    whole = count - count % columns
    notes.append(f"{kind}Count is {count} in {columns} columns: {whole} are printed, "
                 f"so that every row is full")
    return whole


def _picked(pack: Pack, chapter: Chapter, part: int, count: int, notes: list[str], capitals: bool) -> list[Styled]:
    """Up to ``count`` syllables or words, each once (SCHEMA.md): the chapter's
    picks first, in their order, the last ones left out past the count. Short of
    it, the rest is filled from the pack (``_automatic``); when that runs out
    too, arranged() repeats what was chosen until the count is reached."""
    kind, column = ("syllable", "SyllableCount") if part == packs.SYLLABLES else ("word", "WordCount")
    entries = chapter.entries.get(part, [])
    # Syllables are never coloured: only words get their graphemes' colours.
    tinted = chapter if part == packs.WORDS else None
    listed = [_in_capitals(styled(pack, entry.text, chapter.grey_silent, syllables_too=part == packs.SYLLABLES,
                                  chapter=tinted), capitals and _pick_flagged(pack, entry.text, part))
              for entry in entries]
    if len(listed) > count:
        notes.append(f"{len(listed)} {kind}s picked and {count} printed: "
                     f"the last {len(listed) - count} are left out")
        return listed[:count]
    # A pick printed "la Lune" is the pack's "lune": it is not filled in twice.
    picked = {word for entry in entries for word in words_of(entry.text, pack.words_by_text)}
    items = pack.syllables if part == packs.SYLLABLES else pack.words
    filling = [_in_capitals(_styled_item(pack, item, chapter.grey_silent, tinted), capitals and item.uppercase)
               for item in _automatic(pack, items, chapter) if lower(item.text) not in picked]
    chosen = listed + filling[:count - len(listed)]
    if count and not chosen:
        notes.append(f"no {kind} readable at this lesson holds one of the chapter's GPs")
        return []
    # A syllable grid repeats its syllables by design; words only for want of more.
    if part == packs.WORDS and len(chosen) < count:
        notes.append(f"{column} is {count}, and only {len(chosen)} words qualify: they are repeated")
    return chosen


# What a repeat costs where it lands, in arranged(): beside itself on its row, or
# under itself, is what the PO asked to avoid (2026-11-17); at the end of one row
# and the start of the next it is barely seen; two cells away on its row ("d e
# d") still reads as a repeat; in a column it held in an earlier row, only a
# little.
_BESIDE, _ABOVE, _ACROSS_ROWS, _NEAR, _SAME_COLUMN = 100, 100, 10, 5, 1
_ATTEMPTS = 200
_CHEAPEST = 0.7
_ROWS_LOOKED_AT = 5


def _seed(chapter: Chapter, part: int) -> str:
    # A fixed seed: the same pack prints the same booklet every time.
    return f"{chapter.id}:{part}"


def arranged(choice: list[Styled], count: int, columns: int, seed: str) -> list[Styled]:
    """``count`` items read row by row in ``columns``: ``choice`` once in its
    order, then, when there are too few, again in shuffled rounds (the PO's rule,
    2026-11-17), each using every item once so that none comes up more than
    another. No item sits beside itself or under itself where that can be
    helped, and as little as can be in a column it held before: of many random
    grids, the one that costs least (``_cost``)."""
    result = list(choice[:count])
    if not choice or len(result) == count:
        return result
    # A chapter may pick the same syllable twice: a round holds each spelling once.
    distinct = list({lower(item.text): item for item in choice}.values())
    if len(distinct) == 1:
        return [result[index % len(result)] for index in range(count)]
    rng = random.Random(seed)
    best: list[Styled] = []
    best_cost = -1
    # A round can corner the next one, so whole grids are compared, not rounds.
    # Fewer attempts for a long grid, which costs more to lay.
    for _ in range(min(_ATTEMPTS, max(20, 4800 // count))):
        laid, cost = list(result), 0
        while len(laid) < count:
            cost += _one_round(distinct, min(len(distinct), count - len(laid)), laid, columns, rng)
        if best_cost < 0 or cost < best_cost:
            best, best_cost = laid, cost
        if cost == 0:
            break
    return best


def _one_round(items: list[Styled], size: int, laid: list[Styled], columns: int, rng: random.Random) -> int:
    """Adds ``size`` of ``items`` to ``laid``, each among those not beside or
    under themselves there: mostly the cheapest, sometimes any of them, since
    taking the cheapest every time walks into the same dead end on every attempt.
    Returns what they cost."""
    left = list(items)
    total = 0
    for _ in range(size):
        costs = [_cost(item, laid, columns) for item in left]
        fitting = [index for index, cost in enumerate(costs) if cost < min(_BESIDE, _ABOVE)] or range(len(left))
        if rng.random() < _CHEAPEST:
            fitting = [index for index in fitting if costs[index] == min(costs[other] for other in fitting)]
        index = rng.choice(fitting)
        total += costs[index]
        laid.append(left.pop(index))
    return total


def _cost(item: Styled, sequence: list[Styled], columns: int) -> int:
    position = len(sequence)
    column = position % columns if columns > 0 else 0
    same = lambda other: lower(other.text) == lower(item.text)  # noqa: E731
    cost = 0
    if position and same(sequence[-1]):
        cost += _BESIDE if column or columns <= 1 else _ACROSS_ROWS
    if column >= 2 and same(sequence[-2]):
        cost += _NEAR
    if columns > 0 and position >= columns and same(sequence[position - columns]):
        cost += _ABOVE
    if columns > 0:
        # The rows just above: further up, nobody compares.
        earlier_rows = range(max(column, position - _ROWS_LOOKED_AT * columns), position - columns, columns)
        cost += _SAME_COLUMN * sum(1 for earlier in earlier_rows if same(sequence[earlier]))
    return cost


def _automatic(pack: Pack, items: dict[int, Item], chapter: Chapter) -> list[Item]:
    """What fills a chapter's syllables or words (SCHEMA.md): the entries
    readable at its lesson that hold at least one of its GPs. Exceptions are left
    out, as the game leaves them out, and so is an entry with no vowel: such a
    "word" is the elided form a sentence needs ("l" of "l'ours"), never read
    alone. Booklet-only entries first, then in the pack's order; one entry per
    spelling."""
    taught = set(chapter.gp_ids)
    vowels = {gp.id for gp in pack.gps.values() if gp.type == packs.VOWEL}
    candidates = [item for item in items.values()
                  if not item.exception and item.reading and item.lesson is not None
                  and item.lesson <= chapter.lesson and taught.intersection(item.gp_ids)
                  and vowels.intersection(item.gp_ids)]
    candidates.sort(key=lambda item: (not item.booklet_only, item.id))
    seen: set[str] = set()
    chosen: list[Item] = []
    for item in candidates:
        if lower(item.text) not in seen:
            seen.add(lower(item.text))
            chosen.append(item)
    return chosen


def _in_capitals(item: Styled, flagged: bool) -> Styled:
    return item.upper() if flagged else item


def _pick_flagged(pack: Pack, text: str, part: int) -> bool:
    """Whether a chapter's pick prints in capitals (SCHEMA.md, ``Uppercase``):
    when every syllable or word of the pack it is made of is flagged, "la Lune"
    only if both "la" and "lune" are. A word of no list leaves it as written."""
    if not pack.capitals:
        return False
    lists = ((pack.syllables_by_text, pack.syllables), (pack.words_by_text, pack.words))
    if part == packs.WORDS:
        lists = lists[::-1]
    spellings = words_of(text, pack.words_by_text)
    return bool(spellings) and all(
        any(items[item_id].uppercase for by_text, items in lists for item_id in by_text.get(spelling, []))
        for spelling in spellings)


def _sentence_text(pack: Pack, sentence: Sentence, grey: bool, chapter: Chapter, capitals: bool) -> Styled:
    return _in_capitals(styled(pack, sentence.text, grey, linked=sentence.word_ids, chapter=chapter),
                        capitals and sentence.uppercase)


# --- Sentences ---------------------------------------------------------------------

def _paragraphs(pack: Pack, chapter: Chapter, grey: bool, notes: list[str], cursive: bool,
                capitals: bool) -> list[Paragraph]:
    paragraphs: list[Paragraph] = []
    found = [(item, pack.sentences.get(item.sentence_id)) for item in chapter.sentences]
    for item, sentence in found:
        if sentence is None:
            notes.append(f"sentence {item.sentence_id} is not in the Sentence List")
    found = [(item, sentence) for item, sentence in found if sentence is not None]
    for item, sentence in found:
        lesson = _sentence_lesson(pack, sentence)
        if lesson is None:
            notes.append(f"sentence \"{sentence.text}\" is never readable")
        elif lesson > chapter.lesson:
            notes.append(f"sentence \"{sentence.text}\" is readable from lesson {lesson}")
        pieces = _sentence_text(pack, sentence, grey, chapter, capitals).lines()
        if not paragraphs or item.brk == packs.NEW_PARAGRAPH:
            paragraphs.append(Paragraph(_paragraph_font(pack, chapter, len(paragraphs), cursive), [[]]))
        elif item.brk == packs.NEW_LINE:
            paragraphs[-1].lines.append([])
        paragraphs[-1].lines[-1].append(pieces[0])
        paragraphs[-1].lines.extend([piece] for piece in pieces[1:])
    return paragraphs


def _sentence_pool(pack: Pack, chapter: Chapter, grey: bool, capitals: bool) -> tuple[list[tuple[int, Styled]], set[int]]:
    """What a chapter that picks no sentence chooses from: the sentences readable
    at its lesson, exceptions left out. Those with a word holding one of its GPs
    come first, then the others, since the point is to fill the pages; within
    each, booklet-only ones first, then in the pack's order. The layout takes as
    many as fit, whole. Also the IDs of those holding one of its GPs: the layout
    says when it had to print others."""
    taught = set(chapter.gp_ids)
    ranked = []
    for sentence in pack.sentences.values():
        lesson = _sentence_lesson(pack, sentence)
        if sentence.exception or not sentence.reading or lesson is None or lesson > chapter.lesson:
            continue
        teaches = any(taught.intersection(pack.words[word_id].gp_ids) for word_id in sentence.word_ids)
        ranked.append(((not teaches, not sentence.booklet_only, sentence.id), sentence))
    ranked.sort(key=lambda pair: pair[0])
    teaching = {sentence.id for key, sentence in ranked if not key[0]}
    return [(sentence.id, _sentence_text(pack, sentence, grey, chapter, capitals)) for _, sentence in ranked], teaching


def _paragraph_font(pack: Pack, chapter: Chapter, index: int, cursive: bool) -> str:
    """Script and cursive alternate by paragraph, unless the chapter asks for
    one only; the script series prints everything in script."""
    if not cursive:
        return SCRIPT
    font = int(pack.setting(chapter, "SentenceFont"))
    if font == packs.SCRIPT:
        return SCRIPT
    if font == packs.CURSIVE:
        return CURSIVE
    first = CURSIVE if int(pack.setting(chapter, "SentenceFirstFont")) == packs.CURSIVE else SCRIPT
    other = SCRIPT if first == CURSIVE else CURSIVE
    return first if index % 2 == 0 else other


def _sentence_lesson(pack: Pack, sentence: packs.Sentence) -> int | None:
    lessons = [pack.words[word_id].lesson if word_id in pack.words else None for word_id in sentence.word_ids]
    if not lessons or any(lesson is None for lesson in lessons):
        return None
    return max(lessons)


# --- Tables and stories -------------------------------------------------------------

def _tables(pack: Pack, chapter: Chapter, grey: bool) -> list[list[TableRow]]:
    """Two-column tables; a header row is bold and starts a new table."""
    tables: list[list[TableRow]] = []
    for entry in chapter.entries.get(packs.TABLES, []):
        if entry.header or not tables:
            tables.append([])
        tables[-1].append(TableRow(styled(pack, entry.text, grey, chapter=chapter),
                                   styled(pack, entry.text2, grey, chapter=chapter), entry.header))
    return tables


def _story_paragraphs(text: str) -> list[str]:
    """Paragraphs are separated by an empty line (SCHEMA.md); a single line
    break inside one is kept."""
    return [paragraph.strip() for paragraph in re.split(r"\n\s*\n", text.strip()) if paragraph.strip()]


# --- Silent letters -------------------------------------------------------------------

def styled(pack: Pack, text: str, grey: bool, linked: tuple[int, ...] = (),
           syllables_too: bool = False, chapter: Chapter | None = None) -> Styled:
    """``text`` with what its letters are: its silent letters, in ``grey`` too
    when ``grey`` is set, and, given the ``chapter`` it prints in, its
    multi-letter graphemes to colour.

    Each word is matched as the Prof Tool matches it: to the sentence's own
    words (``linked``, from WordsInSentences) when they follow in order, else to
    ``Words`` by its spelling, case ignored. A word's silent letters are its GPs
    of type 0; a word that is in no list, or whose GPs do not spell it, has none.
    """
    silent: set[int] = set()
    tints: list[tuple[int, int, str]] = []
    next_linked = 0
    for start, end in word_spans(text, pack.words_by_text):
        word = lower(text[start:end])
        item = None
        if next_linked < len(linked) and linked[next_linked] in pack.words \
                and lower(pack.words[linked[next_linked]].text) == word:
            item = pack.words[linked[next_linked]]
            next_linked += 1
        else:
            item = _by_spelling(pack, word, syllables_too)
        if item is not None:
            spans = _gp_spans(pack, item, text[start:end])
            silent.update(start + offset for offset in _silent_of(pack, spans))
            if chapter is not None:
                tints.extend((start + begin, start + end_, kind) for begin, end_, kind in _tints(pack, spans, chapter))
    return Styled(text, frozenset(silent) if grey else frozenset(), frozenset(silent), tuple(tints))


def _styled_item(pack: Pack, item: Item, grey: bool, chapter: Chapter | None = None) -> Styled:
    spans = _gp_spans(pack, item, item.text)
    silent = frozenset(_silent_of(pack, spans))
    return Styled(item.text, silent if grey else frozenset(), silent,
                  tuple(_tints(pack, spans, chapter)) if chapter is not None else ())


def _by_spelling(pack: Pack, word: str, syllables_too: bool) -> Item | None:
    """The word spelled ``word``; of several, the one readable first, which is the
    one a child is likeliest to have met."""
    candidates = [pack.words[item_id] for item_id in pack.words_by_text.get(word, [])]
    if not candidates and syllables_too:
        candidates = [pack.syllables[item_id] for item_id in pack.syllables_by_text.get(word, [])]
    if not candidates:
        return None
    return min(candidates, key=lambda item: (item.lesson is None, item.lesson or 0, item.exception, item.id))


def _gp_spans(pack: Pack, item: Item, spelling: str) -> list[tuple[int, int, int]]:
    """Where in ``spelling`` each of ``item``'s GPs is, as (start, end, GP ID),
    or nothing when its GPs do not spell it exactly. A hyphen between two of
    them is no GP: "tam-tam" is t-a-m-t-a-m."""
    spans: list[tuple[int, int, int]] = []
    position = 0
    for index, gp_id in enumerate(item.gp_ids):
        if index and spelling[position:position + 1] == "-":
            position += 1
        gp = pack.gps.get(gp_id)
        if gp is None:
            return []
        grapheme = lower(gp.grapheme)
        if lower(spelling[position:position + len(grapheme)]) != grapheme:
            return []
        spans.append((position, position + len(grapheme), gp_id))
        position += len(grapheme)
    return spans if position == len(spelling) else []


def _silent_of(pack: Pack, spans: list[tuple[int, int, int]]) -> list[int]:
    return [offset for start, end, gp_id in spans if pack.gps[gp_id].silent for offset in range(start, end)]


def _tints(pack: Pack, spans: list[tuple[int, int, int]], chapter: Chapter) -> list[tuple[int, int, str]]:
    """The multi-letter graphemes of a word to colour (Kalulu-Main's
    docs/BOOKLETS-FROM-PACKS.md, section 7): those this chapter's lesson
    teaches, those an earlier lesson taught, and, when two coloured ones touch,
    one of the two in the third colour so that each stays visible. That is the
    second, unless the second is the lesson's own: the lesson's own colour
    never changes, so the one before it does. "qu" always has the third
    colour. A single letter, a doubled one ("ss") and a silent grapheme (grey
    instead) are not coloured."""
    tints: list[tuple[int, int, str]] = []
    for start, end, gp_id in spans:
        gp = pack.gps[gp_id]
        grapheme = lower(gp.grapheme)
        if gp.silent or len(grapheme) < 2 or len(set(grapheme)) < 2:
            continue
        if gp_id in chapter.gp_ids or gp.lesson == chapter.lesson:
            kind = OWN
        elif gp.lesson is not None and gp.lesson < chapter.lesson:
            kind = EARLIER
        else:
            continue
        before = tints[-1] if tints and tints[-1][1] == start else None
        if grapheme == "qu":
            kind = TOUCHING
        elif before is not None and before[2] != TOUCHING:
            if kind != OWN:
                kind = TOUCHING
            elif before[2] != OWN:
                tints[-1] = (before[0], before[1], TOUCHING)
        tints.append((start, end, kind))
    return tints
