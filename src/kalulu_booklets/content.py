"""What each chapter of a booklet prints, decided from the pack.

This is where the PO's rules are applied (Kalulu-Main
``docs/BOOKLETS-FROM-PACKS.md``, and ``SCHEMA.md`` "The reading booklets"):
the automatic syllables and words, the share in capitals, the paragraphs and
their fonts, the silent letters to print in grey. Nothing here knows about
pages; ``layout`` places what comes out of it.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

from kalulu_booklets import pack as packs
from kalulu_booklets.pack import Chapter, Item, Pack
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
    # in order, as many as fit (each a paragraph of its own). The fonts
    # paragraphs alternate between, and the share printed in capitals.
    sentence_pool: list[tuple[int, Styled]]
    sentence_fonts: tuple[str, str]
    sentence_uppercase: float
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
    # The Look & Learn image of the chapter's ImageGPID, for the teacher's page;
    # None when it has none, or the pack's images are not checked out.
    picture: Path | None = None

    def is_empty(self) -> bool:
        return not (self.title or self.syllables or self.words or self.paragraphs or self.sentence_pool
                    or self.tables or self.writing or self.fluency or self.stories)


@dataclass
class Booklet:
    locale: str
    number: int
    cursive: bool
    chapters: list[ChapterContent]
    # What a person should look at: content that cannot be printed as asked.
    notes: list[str] = field(default_factory=list)


def booklet(pack: Pack, number: int) -> Booklet:
    result = Booklet(pack.locale, number, pack.cursive, [])
    for chapter in pack.chapters:
        if chapter.booklet != number:
            continue
        notes: list[str] = []
        content = _chapter(pack, chapter, notes)
        result.notes.extend(f"{chapter.name}: {note}" for note in notes)
        if content.is_empty():
            result.notes.append(f"{chapter.name}: prints nothing, so it has no page")
            continue
        result.chapters.append(content)
    return result


def _chapter(pack: Pack, chapter: Chapter, notes: list[str]) -> ChapterContent:
    setting = lambda column: pack.setting(chapter, column)  # noqa: E731
    grey = chapter.grey_silent
    uppercase = float(setting("UppercaseProportion"))

    syllables = _picked(pack, chapter, packs.SYLLABLES, int(setting("SyllableCount")), notes)
    words = _picked(pack, chapter, packs.WORDS, int(setting("WordCount")), notes)
    # -1 prints no sentence at all.
    sentence_pages = int(setting("SentencePages"))
    if sentence_pages < 0 and chapter.sentences:
        notes.append(f"SentencePages is -1, so its {len(chapter.sentences)} sentence(s) are not printed")
    pool, teaching = _sentence_pool(pack, chapter, grey) if sentence_pages >= 0 and not chapter.sentences else ([], set())
    if sentence_pages >= 0 and not chapter.sentences and not pool:
        notes.append("no sentence is readable at this lesson")

    return ChapterContent(
        chapter=chapter,
        title=[line.strip() for line in chapter.title.split("\n")] if chapter.title.strip() else [],
        syllables=_capitals(syllables, uppercase),
        syllable_columns=int(setting("SyllableColumns")),
        words=_capitals(words, uppercase),
        word_columns=int(setting("WordColumns")),
        paragraphs=_paragraphs(pack, chapter, grey, uppercase, notes) if sentence_pages >= 0 else [],
        sentence_pool=pool,
        sentence_fonts=(_paragraph_font(pack, chapter, 0), _paragraph_font(pack, chapter, 1)),
        sentence_uppercase=uppercase,
        sentence_pages=max(sentence_pages, 0),
        tables=_tables(pack, chapter, grey),
        writing=[entry.text for entry in chapter.entries.get(packs.WRITING, [])],
        writing_font=CURSIVE if pack.cursive else SCRIPT,
        writing_models=int(setting("WritingModels")),
        writing_tracings=int(setting("WritingTracings")),
        fluency=[styled(pack, entry.text, grey, chapter=chapter) for entry in chapter.entries.get(packs.FLUENCY, [])],
        stories=[(story.title.strip(), [styled(pack, paragraph, grey, chapter=chapter)
                                        for paragraph in _story_paragraphs(story.text)])
                 for story in chapter.stories],
        sentences_teaching=frozenset(teaching),
        picture=pack.picture(chapter.image_gp_id),
    )


# --- Syllables and words ---------------------------------------------------------

def _picked(pack: Pack, chapter: Chapter, part: int, count: int, notes: list[str]) -> list[Styled]:
    """``count`` syllables or words (SCHEMA.md): the chapter's picks first, in
    their order, the last ones left out past the count. Short of it, the rest is
    filled from the pack (``_automatic``), and when that runs out too, what was
    chosen is repeated until the count is reached."""
    kind, column = ("syllable", "SyllableCount") if part == packs.SYLLABLES else ("word", "WordCount")
    entries = chapter.entries.get(part, [])
    # Syllables are never coloured: only words get their graphemes' colours.
    tinted = chapter if part == packs.WORDS else None
    listed = [styled(pack, entry.text, chapter.grey_silent, syllables_too=part == packs.SYLLABLES, chapter=tinted)
              for entry in entries]
    if len(listed) > count:
        notes.append(f"{len(listed)} {kind}s picked and {column} is {count}: "
                     f"the last {len(listed) - count} are left out")
        return listed[:count]
    # A pick printed "la Lune" is the pack's "lune": it is not filled in twice.
    picked = {word for entry in entries for word in words_of(entry.text, pack.words_by_text)}
    items = pack.syllables if part == packs.SYLLABLES else pack.words
    filling = [_styled_item(pack, item, chapter.grey_silent, tinted)
               for item in _automatic(pack, items, chapter) if lower(item.text) not in picked]
    chosen = listed + filling[:count - len(listed)]
    if count and not chosen:
        notes.append(f"no {kind} readable at this lesson holds one of the chapter's GPs")
        return []
    # A syllable grid repeats its syllables by design; words only for want of more.
    if part == packs.WORDS and len(chosen) < count:
        notes.append(f"{column} is {count}, and only {len(chosen)} words qualify: they are repeated")
    return [chosen[index % len(chosen)] for index in range(count)]


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


def _capitals(items: list[Styled], proportion: float) -> list[Styled]:
    """Prints a share of the items in capitals, spread evenly: at 0.25, every
    fourth."""
    return [item.upper() if int((index + 1) * proportion) > int(index * proportion) else item
            for index, item in enumerate(items)]


# --- Sentences ---------------------------------------------------------------------

def _paragraphs(pack: Pack, chapter: Chapter, grey: bool, uppercase: float,
                notes: list[str]) -> list[Paragraph]:
    paragraphs: list[Paragraph] = []
    found = [(item, pack.sentences.get(item.sentence_id)) for item in chapter.sentences]
    for item, sentence in found:
        if sentence is None:
            notes.append(f"sentence {item.sentence_id} is not in the Sentence List")
    found = [(item, sentence) for item, sentence in found if sentence is not None]
    for index, (item, sentence) in enumerate(found):
        lesson = _sentence_lesson(pack, sentence)
        if lesson is None:
            notes.append(f"sentence \"{sentence.text}\" is never readable")
        elif lesson > chapter.lesson:
            notes.append(f"sentence \"{sentence.text}\" is readable from lesson {lesson}")
        text = styled(pack, sentence.text, grey, linked=sentence.word_ids, chapter=chapter)
        if int((index + 1) * uppercase) > int(index * uppercase):
            text = text.upper()
        pieces = text.lines()
        if not paragraphs or item.brk == packs.NEW_PARAGRAPH:
            paragraphs.append(Paragraph(_paragraph_font(pack, chapter, len(paragraphs)), [[]]))
        elif item.brk == packs.NEW_LINE:
            paragraphs[-1].lines.append([])
        paragraphs[-1].lines[-1].append(pieces[0])
        paragraphs[-1].lines.extend([piece] for piece in pieces[1:])
    return paragraphs


def _sentence_pool(pack: Pack, chapter: Chapter, grey: bool) -> tuple[list[tuple[int, Styled]], set[int]]:
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
    return [(sentence.id, styled(pack, sentence.text, grey, linked=sentence.word_ids, chapter=chapter))
            for _, sentence in ranked], teaching


def _paragraph_font(pack: Pack, chapter: Chapter, index: int) -> str:
    """Script and cursive alternate by paragraph, unless the chapter asks for
    one only; a language written without cursive prints everything in script."""
    if not pack.cursive:
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


def _silent_offsets(pack: Pack, item: Item, spelling: str) -> list[int]:
    """Positions in ``spelling`` of the letters ``item``'s silent GPs spell."""
    return _silent_of(pack, _gp_spans(pack, item, spelling))


def _silent_of(pack: Pack, spans: list[tuple[int, int, int]]) -> list[int]:
    return [offset for start, end, gp_id in spans if pack.gps[gp_id].silent for offset in range(start, end)]


def _tints(pack: Pack, spans: list[tuple[int, int, int]], chapter: Chapter) -> list[tuple[int, int, str]]:
    """The multi-letter graphemes of a word to colour, as the examples colour
    them (Kalulu-Main's docs/booklet-versions/): the chapter's own, those an
    earlier lesson taught, and, when two coloured ones touch, the second in the
    third colour, as "qu" always is. A single letter, a doubled one ("ss") and a
    silent grapheme (grey instead) are not coloured."""
    tints: list[tuple[int, int, str]] = []
    for start, end, gp_id in spans:
        gp = pack.gps[gp_id]
        grapheme = lower(gp.grapheme)
        if gp.silent or len(grapheme) < 2 or len(set(grapheme)) < 2:
            continue
        if gp_id in chapter.gp_ids:
            kind = OWN
        elif gp.lesson is not None and gp.lesson <= chapter.lesson:
            kind = EARLIER
        else:
            continue
        if grapheme == "qu" or (tints and tints[-1][1] == start and tints[-1][2] != TOUCHING):
            kind = TOUCHING
        tints.append((start, end, kind))
    return tints
