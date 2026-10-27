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

from kalulu_booklets import pack as packs
from kalulu_booklets.pack import Chapter, Item, Pack
from kalulu_booklets.text import lower, upper, word_spans

SCRIPT, CURSIVE = "script", "cursive"


@dataclass(frozen=True)
class Styled:
    """Text to print, with the positions of its letters to print in grey."""

    text: str
    grey: frozenset[int] = frozenset()

    def upper(self) -> Styled:
        return Styled(upper(self.text), self.grey)

    def lines(self) -> list[Styled]:
        """Split at the line breaks a sentence may hold (SCHEMA.md)."""
        pieces: list[Styled] = []
        start = 0
        for end in [index for index, character in enumerate(self.text) if character == "\n"] + [len(self.text)]:
            raw = self.text[start:end]
            first = start + len(raw) - len(raw.lstrip())
            stripped = raw.strip()
            pieces.append(Styled(stripped, frozenset(index - first for index in self.grey
                                                     if first <= index < first + len(stripped))))
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
    # Pages the sentences may take at most; 0 for no limit.
    sentence_pages: int
    tables: list[list[TableRow]]
    writing: list[str]
    writing_font: str
    writing_models: int
    writing_tracings: int
    fluency: list[Styled]
    stories: list[tuple[str, list[Styled]]]

    def is_empty(self) -> bool:
        return not (self.title or self.syllables or self.words or self.paragraphs or self.tables
                    or self.writing or self.fluency or self.stories)


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

    syllables = _syllables(pack, chapter, int(setting("SyllableCount")), notes)
    words = _words(pack, chapter, int(setting("WordCount")), notes)

    return ChapterContent(
        chapter=chapter,
        title=[line.strip() for line in chapter.title.split("\n")] if chapter.title.strip() else [],
        syllables=_capitals(syllables, uppercase),
        syllable_columns=int(setting("SyllableColumns")),
        words=_capitals(words, uppercase),
        word_columns=int(setting("WordColumns")),
        paragraphs=_paragraphs(pack, chapter, grey, uppercase, notes),
        sentence_pages=int(setting("SentencePages")),
        tables=_tables(pack, chapter, grey),
        writing=[entry.text for entry in chapter.entries.get(packs.WRITING, [])],
        writing_font=CURSIVE if pack.cursive else SCRIPT,
        writing_models=int(setting("WritingModels")),
        writing_tracings=int(setting("WritingTracings")),
        fluency=[styled(pack, entry.text, grey) for entry in chapter.entries.get(packs.FLUENCY, [])],
        stories=[(story.title.strip(), [styled(pack, paragraph, grey) for paragraph in _story_paragraphs(story.text)])
                 for story in chapter.stories],
    )


# --- Syllables and words ---------------------------------------------------------

def _syllables(pack: Pack, chapter: Chapter, count: int, notes: list[str]) -> list[Styled]:
    """``count`` syllables, the listed ones or the automatic choice, repeated
    until the count is reached."""
    listed = chapter.entries.get(packs.SYLLABLES)
    if listed:
        chosen = [styled(pack, entry.text, chapter.grey_silent, syllables_too=True) for entry in listed]
        if len(chosen) > count:
            notes.append(f"{len(chosen)} syllables listed and SyllableCount is {count}: "
                         f"only the first {count} are printed")
    else:
        chosen = [_styled_item(pack, item, chapter.grey_silent)
                  for item in _automatic(pack, pack.syllables, chapter)]
        if count and not chosen:
            notes.append("no syllable readable at this lesson holds one of the chapter's GPs")
    if not chosen:
        return []
    return [chosen[index % len(chosen)] for index in range(count)]


def _words(pack: Pack, chapter: Chapter, count: int, notes: list[str]) -> list[Styled]:
    """The listed words, all of them; or ``count`` chosen automatically."""
    listed = chapter.entries.get(packs.WORDS)
    if listed:
        return [styled(pack, entry.text, chapter.grey_silent) for entry in listed]
    chosen = _automatic(pack, pack.words, chapter)
    if count and not chosen:
        notes.append("no word readable at this lesson holds one of the chapter's GPs")
    elif len(chosen) < count:
        notes.append(f"WordCount is {count}, and only {len(chosen)} words qualify")
    return [_styled_item(pack, item, chapter.grey_silent) for item in chosen[:count]]


def _automatic(pack: Pack, items: dict[int, Item], chapter: Chapter) -> list[Item]:
    """What a chapter prints when nothing is listed (SCHEMA.md): the entries
    readable at its lesson that hold at least one of its GPs. Exceptions are left
    out, as the game leaves them out, and so is an entry with no vowel: such a
    "word" is the elided form a sentence needs ("l" of "l'ours"), never read
    alone. New at this lesson first, then the shortest, then in the pack's order;
    one entry per spelling."""
    taught = set(chapter.gp_ids)
    vowels = {gp.id for gp in pack.gps.values() if gp.type == packs.VOWEL}
    candidates = [item for item in items.values()
                  if not item.exception and item.reading and item.lesson is not None
                  and item.lesson <= chapter.lesson and taught.intersection(item.gp_ids)
                  and vowels.intersection(item.gp_ids)]
    candidates.sort(key=lambda item: (item.lesson != chapter.lesson, len(item.gp_ids), item.id))
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
        text = styled(pack, sentence.text, grey, linked=sentence.word_ids)
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
        tables[-1].append(TableRow(styled(pack, entry.text, grey), styled(pack, entry.text2, grey), entry.header))
    return tables


def _story_paragraphs(text: str) -> list[str]:
    """Paragraphs are separated by an empty line (SCHEMA.md); a single line
    break inside one is kept."""
    return [paragraph.strip() for paragraph in re.split(r"\n\s*\n", text.strip()) if paragraph.strip()]


# --- Silent letters -------------------------------------------------------------------

def styled(pack: Pack, text: str, grey: bool, linked: tuple[int, ...] = (),
           syllables_too: bool = False) -> Styled:
    """``text`` with its silent letters marked, when ``grey`` is set.

    Each word is matched as the Prof Tool matches it: to the sentence's own
    words (``linked``, from WordsInSentences) when they follow in order, else to
    ``Words`` by its spelling, case ignored. A word's silent letters are its GPs
    of type 0; a word that is in no list, or whose GPs do not spell it, is
    printed without grey.
    """
    if not grey:
        return Styled(text)
    silent: set[int] = set()
    next_linked = 0
    for start, end in word_spans(text):
        word = lower(text[start:end])
        item = None
        if next_linked < len(linked) and linked[next_linked] in pack.words \
                and lower(pack.words[linked[next_linked]].text) == word:
            item = pack.words[linked[next_linked]]
            next_linked += 1
        else:
            item = _by_spelling(pack, word, syllables_too)
        if item is not None:
            silent.update(start + offset for offset in _silent_offsets(pack, item, text[start:end]))
    return Styled(text, frozenset(silent))


def _styled_item(pack: Pack, item: Item, grey: bool) -> Styled:
    if not grey:
        return Styled(item.text)
    return Styled(item.text, frozenset(_silent_offsets(pack, item, item.text)))


def _by_spelling(pack: Pack, word: str, syllables_too: bool) -> Item | None:
    """The word spelled ``word``; of several, the one readable first, which is the
    one a child is likeliest to have met."""
    candidates = [pack.words[item_id] for item_id in pack.words_by_text.get(word, [])]
    if not candidates and syllables_too:
        candidates = [pack.syllables[item_id] for item_id in pack.syllables_by_text.get(word, [])]
    if not candidates:
        return None
    return min(candidates, key=lambda item: (item.lesson is None, item.lesson or 0, item.exception, item.id))


def _silent_offsets(pack: Pack, item: Item, spelling: str) -> list[int]:
    """Positions in ``spelling`` of the letters ``item``'s silent GPs spell, or
    none when its GPs do not spell it exactly."""
    offsets: list[int] = []
    position = 0
    for gp_id in item.gp_ids:
        gp = pack.gps.get(gp_id)
        if gp is None:
            return []
        grapheme = lower(gp.grapheme)
        if lower(spelling[position:position + len(grapheme)]) != grapheme:
            return []
        if gp.silent:
            offsets.extend(range(position, position + len(grapheme)))
        position += len(grapheme)
    return offsets if position == len(spelling) else []
