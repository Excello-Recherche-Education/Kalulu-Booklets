"""Reading a language pack's ``language.db``.

The contract is Kalulu-Languages ``SCHEMA.md``, schema version 4: the lessons,
the GPs they teach, the words, syllables and sentences with their
decompositions, and the ``Booklet*`` tables that say what the booklets print and
with which fonts.
The pack is opened read-only; nothing here ever writes to it.
"""

from __future__ import annotations

import sqlite3
import unicodedata
from dataclasses import dataclass, field
from pathlib import Path

from kalulu_booklets.text import lower

SCHEMA_VERSION = 4

# GPs.Type: 0 silent, 1 vowel, 2 consonant.
SILENT, VOWEL, CONSONANT = 0, 1, 2

# BookletEntries.Part.
SYLLABLES, WORDS, WRITING, TABLES, FLUENCY = 1, 2, 3, 4, 5

# BookletSentences.Break: what comes before a sentence.
SAME_LINE, NEW_LINE, NEW_PARAGRAPH = 0, 1, 2

# BookletSettings.SentenceFont and SentenceFirstFont.
ALTERNATE, SCRIPT, CURSIVE = 0, 1, 2

# The columns a chapter can override, NULL meaning the BookletSettings value.
SETTINGS = (
    "SyllableCount", "SyllableColumns", "WordCount", "WordColumns",
    "UppercaseProportion", "SentenceFont", "SentenceFirstFont", "SentencePages",
    "WritingModels", "WritingTracings",
)


# How a GP's grapheme or phoneme is spelled in its asset file names, as the game
# spells them (Kalulu-Frontend Database._text_to_file_name()): a symbol as a
# word, a text with a capital as "cap." and its lowercase, so that "e-E" and
# "e-e" stay two files on a filesystem that folds case.
_SYMBOL_NAMES = {"#": "sharp", "@": "at", "*": "star", "$": "usd", "%": "pcent", "§": "para"}
LOOK_AND_LEARN_IMAGES = Path("look_and_learn") / "images"


def _is_png(path: Path) -> bool:
    """Not a Git LFS pointer left in its place: a checkout without the media has
    small text files under the images' names."""
    with path.open("rb") as file:
        return file.read(8) == b"\x89PNG\r\n\x1a\n"


def _file_name(text: str) -> str:
    if text in _SYMBOL_NAMES:
        return _SYMBOL_NAMES[text]
    return text if text == text.lower() else "cap." + text.lower()


# The fonts a language can replace (fonts.py's roles) -> the BookletSettings
# column naming the BookletFonts row that replaces it; NULL keeps the default.
FONT_COLUMNS = {
    "script": "ScriptFontID", "script_bold": "ScriptBoldFontID",
    "script_black": "ScriptBlackFontID", "cursive": "CursiveFontID",
}


class PackError(Exception):
    """The pack cannot be read: missing, or not the schema this code reads."""


@dataclass(frozen=True)
class GP:
    id: int
    grapheme: str
    phoneme: str
    type: int
    exception: bool
    # The first lesson teaching it, by LessonNb; None when no lesson does.
    lesson: int | None

    @property
    def silent(self) -> bool:
        return self.type == SILENT


@dataclass(frozen=True)
class Item:
    """A word or a syllable: its text and how it decomposes into GPs."""

    id: int
    text: str
    exception: bool
    reading: bool
    booklet_only: bool
    gp_ids: tuple[int, ...]
    # The lesson it becomes readable at: the last of its GPs' first lessons, as
    # the game and the Prof Tool work it out. None when never (no decomposition,
    # or a GP no lesson teaches).
    lesson: int | None


@dataclass(frozen=True)
class Sentence:
    id: int
    text: str
    word_ids: tuple[int, ...]
    exception: bool = False
    reading: bool = True
    booklet_only: bool = False


@dataclass(frozen=True)
class BookletFont:
    """A font replacing a default one: a file of Kalulu-Languages' fonts/."""

    name: str
    file: str  # its path inside fonts/, folders separated by "/"


@dataclass(frozen=True)
class Entry:
    """A line of a chapter's hand-written lists (BookletEntries)."""

    text: str
    text2: str
    header: bool


@dataclass(frozen=True)
class Story:
    title: str
    text: str


@dataclass(frozen=True)
class BookletSentence:
    sentence_id: int
    brk: int


@dataclass
class Chapter:
    id: int
    lesson: int  # LessonNb
    position: int
    booklet: int
    title: str
    image_gp_id: int | None
    grey_silent: bool
    # Column -> value, for the columns the chapter sets itself.
    overrides: dict[str, float]
    gp_ids: list[int] = field(default_factory=list)
    sentences: list[BookletSentence] = field(default_factory=list)
    # Part -> entries, in order. A part listed here replaces the automatic choice.
    entries: dict[int, list[Entry]] = field(default_factory=dict)
    stories: list[Story] = field(default_factory=list)

    @property
    def name(self) -> str:
        """How the Prof Tool names a chapter."""
        return f"Lesson {self.lesson}, chapter {self.position + 1}"


@dataclass
class Pack:
    locale: str
    path: Path
    gps: dict[int, GP]
    words: dict[int, Item]
    syllables: dict[int, Item]
    sentences: dict[int, Sentence]
    settings: dict[str, float]
    chapters: list[Chapter]
    # Lowercased text -> the IDs of every word or syllable spelled that way.
    words_by_text: dict[str, list[int]]
    syllables_by_text: dict[str, list[int]]
    # Role (FONT_COLUMNS) -> the font replacing its default, for those replaced.
    fonts: dict[str, BookletFont] = field(default_factory=dict)
    # The lessons that had no chapter, whose forced chapter is made here
    # (default_chapters()): every one of them for a pack with no chapter.
    made_chapters_for: list[int] = field(default_factory=list)

    @property
    def cursive(self) -> bool:
        return self.settings["Cursive"] != 0

    def setting(self, chapter: Chapter, column: str) -> float:
        """The value a chapter prints with: its own, or the language's."""
        return chapter.overrides.get(column, self.settings[column])

    def picture(self, gp_id: int | None) -> Path | None:
        """A GP's Look & Learn image, as the game finds it: by its encoded name,
        else by its raw one, composed or decomposed (packs store "ç" either way).
        None when the GP or its image is missing, or the image is a Git LFS
        pointer."""
        gp = self.gps.get(gp_id) if gp_id is not None else None
        if gp is None:
            return None
        folder = self.path.parent / LOOK_AND_LEARN_IMAGES
        for name in (f"{_file_name(gp.grapheme)}-{_file_name(gp.phoneme)}", f"{gp.grapheme}-{gp.phoneme}"):
            for form in ("NFC", "NFD"):
                path = folder / f"{unicodedata.normalize(form, name)}.png"
                if path.is_file() and _is_png(path):
                    return path
        return None

    def booklets(self) -> list[int]:
        return sorted({chapter.booklet for chapter in self.chapters})


def resolve(pack: str | Path) -> Path:
    """The ``language.db`` a pack argument names: the file, or its folder."""
    path = Path(pack).expanduser()
    if path.is_dir():
        path = path / "language.db"
    if not path.is_file():
        raise PackError(f"no language.db at {path}")
    return path


def load(pack: str | Path) -> Pack:
    path = resolve(pack)
    connection = sqlite3.connect(f"{path.resolve().as_uri()}?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    try:
        return _load(connection, path)
    finally:
        connection.close()


def _load(db: sqlite3.Connection, path: Path) -> Pack:
    version = db.execute("PRAGMA user_version").fetchone()[0]
    if version != SCHEMA_VERSION:
        raise PackError(
            f"{path} follows language-pack schema version {version}; "
            f"this generator reads version {SCHEMA_VERSION}")

    lesson_numbers = {row["ID"]: row["LessonNb"] for row in db.execute("SELECT ID, LessonNb FROM Lessons")}

    gps: dict[int, GP] = {}
    for row in db.execute(
            """SELECT GPs.*, (SELECT MIN(Lessons.LessonNb) FROM GPsInLessons
                   JOIN Lessons ON Lessons.ID = GPsInLessons.LessonID
                   WHERE GPsInLessons.GPID = GPs.ID) AS FirstLesson
               FROM GPs"""):
        gps[row["ID"]] = GP(row["ID"], row["Grapheme"], row["Phoneme"], int(row["Type"] or 0),
                            bool(row["Exception"]), row["FirstLesson"])

    words = _items(db, gps, "Words", "Word", "GPsInWords", "WordID")
    syllables = _items(db, gps, "Syllables", "Syllable", "GPsInSyllables", "SyllableID")

    linked: dict[int, list[int]] = {}
    for row in db.execute("SELECT SentenceID, WordID FROM WordsInSentences ORDER BY SentenceID, Position"):
        linked.setdefault(row["SentenceID"], []).append(row["WordID"])
    sentences = {row["ID"]: Sentence(row["ID"], row["Sentence"], tuple(linked.get(row["ID"], ())),
                                     bool(row["Exception"]), row["Reading"] is None or row["Reading"] != 0,
                                     bool(row["BookletOnly"]))
                 for row in db.execute("SELECT ID, Sentence, Exception, Reading, BookletOnly FROM Sentences")}

    row = db.execute("SELECT * FROM BookletSettings ORDER BY ID LIMIT 1").fetchone()
    if row is None:
        raise PackError(f"{path} has no BookletSettings row")
    settings = {column: row[column] for column in ("Cursive",) + SETTINGS}
    booklet_fonts = {font["ID"]: BookletFont(font["Name"], font["File"])
                     for font in db.execute("SELECT ID, Name, File FROM BookletFonts")}
    fonts = {role: booklet_fonts[row[column]] for role, column in FONT_COLUMNS.items()
             if row[column] is not None and row[column] in booklet_fonts}

    chapters: dict[int, Chapter] = {}
    for row in db.execute("SELECT * FROM BookletChapters"):
        chapters[row["ID"]] = Chapter(
            id=row["ID"], lesson=lesson_numbers.get(row["LessonID"], 0), position=row["Position"],
            booklet=row["Booklet"], title=row["Title"], image_gp_id=row["ImageGPID"],
            grey_silent=bool(row["GreySilent"]),
            overrides={column: row[column] for column in SETTINGS if row[column] is not None})
    for row in db.execute("SELECT ChapterID, GPID FROM BookletChapterGPs ORDER BY ID"):
        if row["ChapterID"] in chapters:
            chapters[row["ChapterID"]].gp_ids.append(row["GPID"])
    for row in db.execute("SELECT ChapterID, SentenceID, Break FROM BookletSentences ORDER BY ChapterID, Position, ID"):
        if row["ChapterID"] in chapters:
            chapters[row["ChapterID"]].sentences.append(BookletSentence(row["SentenceID"], row["Break"]))
    for row in db.execute("SELECT * FROM BookletEntries ORDER BY ChapterID, Part, Position, ID"):
        if row["ChapterID"] in chapters:
            chapters[row["ChapterID"]].entries.setdefault(row["Part"], []).append(
                Entry(row["Text"], row["Text2"], bool(row["Header"])))
    for row in db.execute("SELECT ChapterID, Title, Text FROM BookletStories ORDER BY ChapterID, Position, ID"):
        if row["ChapterID"] in chapters:
            chapters[row["ChapterID"]].stories.append(Story(row["Title"], row["Text"]))

    lesson_gps: dict[int, list[int]] = {}
    for row in db.execute("SELECT LessonID, GPID FROM GPsInLessons ORDER BY ID"):
        lesson_gps.setdefault(row["LessonID"], []).append(row["GPID"])
    made = default_chapters(lesson_numbers, lesson_gps, gps, list(chapters.values()))
    chapters.update({chapter.id: chapter for chapter in made})

    pack = Pack(
        locale=path.parent.name, path=path, gps=gps, words=words, syllables=syllables,
        sentences=sentences, settings=settings,
        chapters=sorted(chapters.values(), key=lambda chapter: (chapter.lesson, chapter.position, chapter.id)),
        words_by_text=_by_text(words), syllables_by_text=_by_text(syllables), fonts=fonts,
        made_chapters_for=[chapter.lesson for chapter in made])
    # A made chapter's teacher picture: the first of its GPs with a Look & Learn
    # image, as the Prof Tool's BookletData.first_gp_with_image() chooses it.
    for chapter in made:
        chapter.image_gp_id = next((gp_id for gp_id in chapter.gp_ids if pack.picture(gp_id)), None)
    return pack


def default_chapters(lesson_numbers: dict[int, int], lesson_gps: dict[int, list[int]],
                     gps: dict[int, GP], existing: list[Chapter] = ()) -> list[Chapter]:
    """The forced chapters of the lessons ``existing`` has none for: every lesson
    has one, its first chapter. Made as the Prof Tool's Booklets screen makes them
    (BookletData.add_missing_chapters()), in the lessons' order: the lesson's GPs,
    a title made of them, the language's settings, and the booklet of the last
    chapter at or before that lesson (1 when there is none). Their IDs are
    negative, which no row has. The teacher's picture is chosen once the pack is
    loaded (``_load()``), since it depends on the images on disk."""
    have = {chapter.lesson for chapter in existing}
    chapters: list[Chapter] = []
    for lesson_id, number in sorted(lesson_numbers.items(), key=lambda pair: pair[1]):
        if number in have:
            continue
        gp_ids = list(dict.fromkeys(lesson_gps.get(lesson_id, [])))
        booklet = max([chapter.booklet for chapter in list(existing) + chapters if chapter.lesson <= number], default=1)
        chapters.append(Chapter(id=-number, lesson=number, position=0, booklet=booklet, title=title_for(gp_ids, gps),
                                image_gp_id=None, grey_silent=False, overrides={}, gp_ids=gp_ids))
    return chapters


def title_for(gp_ids: list[int], gps: dict[int, GP]) -> str:
    """A title from GPs, as the Prof Tool's BookletData.title_for() makes it: each
    grapheme once, exceptions and silent letters left out unless nothing else is
    left, a single letter with its capital ("L l")."""
    kept = [gp_id for gp_id in gp_ids if gp_id in gps and not gps[gp_id].exception and not gps[gp_id].silent]
    parts: list[str] = []
    for gp_id in kept or gp_ids:
        if gp_id not in gps:
            continue
        grapheme = gps[gp_id].grapheme
        text = f"{grapheme.upper()} {grapheme}" if len(grapheme) == 1 and grapheme.upper() != grapheme else grapheme
        if text not in parts:
            parts.append(text)
    return " ".join(parts)


def _items(db: sqlite3.Connection, gps: dict[int, GP], table: str, column: str,
           relation: str, key: str) -> dict[int, Item]:
    decompositions: dict[int, list[int]] = {}
    for row in db.execute(f"SELECT {key} AS ItemID, GPID FROM {relation} ORDER BY {key}, Position"):
        decompositions.setdefault(row["ItemID"], []).append(row["GPID"])
    items: dict[int, Item] = {}
    for row in db.execute(f"SELECT ID, {column} AS Text, Exception, Reading, BookletOnly FROM {table}"):
        gp_ids = tuple(decompositions.get(row["ID"], ()))
        items[row["ID"]] = Item(row["ID"], row["Text"], bool(row["Exception"]),
                                row["Reading"] is None or row["Reading"] != 0, bool(row["BookletOnly"]),
                                gp_ids, _readable_at(gp_ids, gps))
    return items


def _readable_at(gp_ids: tuple[int, ...], gps: dict[int, GP]) -> int | None:
    if not gp_ids:
        return None
    lessons = [gps[gp_id].lesson if gp_id in gps else None for gp_id in gp_ids]
    if any(lesson is None for lesson in lessons):
        return None
    return max(lessons)


def _by_text(items: dict[int, Item]) -> dict[str, list[int]]:
    by_text: dict[str, list[int]] = {}
    for item in sorted(items.values(), key=lambda item: item.id):
        by_text.setdefault(lower(item.text), []).append(item.id)
    return by_text
