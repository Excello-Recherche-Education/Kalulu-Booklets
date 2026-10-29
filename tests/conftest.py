"""A tiny pack, made from the schema itself so the tests follow the contract.

Lessons: 1 teaches "a", 2 teaches "l", 3 teaches "u", "n" and the silent "e".
"""

from __future__ import annotations

import sqlite3
from pathlib import Path

import pytest

SCHEMA = Path(__file__).resolve().parents[1] / "kalulu-languages" / "schema" / "v4.sql"

GPS = {  # id: (grapheme, phoneme, type)
    1: ("a", "a", 1),
    2: ("l", "l", 2),
    3: ("u", "y", 1),
    4: ("n", "n", 2),
    5: ("e", "#", 0),
}
LESSONS = {1: [1], 2: [2], 3: [3, 4, 5]}
WORDS = {  # id: (word, GP ids, exception, booklet only)
    1: ("la", [2, 1], 0, 0),
    2: ("lune", [2, 3, 4, 5], 0, 0),
    3: ("l", [2], 0, 0),  # the elided "l'" sentences need
    4: ("une", [3, 4, 5], 0, 0),
    5: ("nu", [4, 3], 0, 0),
    6: ("lunule", [2, 3, 4, 3, 2, 5], 1, 0),  # an exception
    7: ("Luna", [2, 3, 4, 1], 0, 1),  # booklet only
}
SYLLABLES = {1: ("la", [2, 1]), 2: ("nu", [4, 3]), 3: ("lu", [2, 3]), 4: ("un", [3, 4])}
SENTENCES = {1: ("La lune.", [1, 2]), 2: ("Une lune nue.", [4, 2])}


def make_pack(folder: Path, version: int = 4) -> Path:
    if not SCHEMA.is_file():
        pytest.skip("kalulu-languages/ is not checked out (git submodule update --init)")
    pack = folder / "xx_XX"
    pack.mkdir(parents=True)
    db = sqlite3.connect(pack / "language.db")
    db.executescript(SCHEMA.read_text(encoding="utf-8"))
    db.execute(f"PRAGMA user_version = {version}")
    for gp_id, (grapheme, phoneme, kind) in GPS.items():
        db.execute("INSERT INTO GPs (ID, Grapheme, Phoneme, Type) VALUES (?, ?, ?, ?)", (gp_id, grapheme, phoneme, kind))
    for number, gp_ids in LESSONS.items():
        db.execute("INSERT INTO Lessons (ID, LessonNb) VALUES (?, ?)", (number, number))
        for gp_id in gp_ids:
            db.execute("INSERT INTO GPsInLessons (GPID, LessonID) VALUES (?, ?)", (gp_id, number))
    for word_id, (word, gp_ids, exception, booklet_only) in WORDS.items():
        db.execute("INSERT INTO Words (ID, Word, Exception, BookletOnly) VALUES (?, ?, ?, ?)",
                   (word_id, word, exception, booklet_only))
        for position, gp_id in enumerate(gp_ids):
            db.execute("INSERT INTO GPsInWords (WordID, GPID, Position) VALUES (?, ?, ?)", (word_id, gp_id, position))
    for syllable_id, (syllable, gp_ids) in SYLLABLES.items():
        db.execute("INSERT INTO Syllables (ID, Syllable) VALUES (?, ?)", (syllable_id, syllable))
        for position, gp_id in enumerate(gp_ids):
            db.execute("INSERT INTO GPsInSyllables (SyllableID, GPID, Position) VALUES (?, ?, ?)",
                       (syllable_id, gp_id, position))
    for sentence_id, (sentence, word_ids) in SENTENCES.items():
        db.execute("INSERT INTO Sentences (ID, Sentence) VALUES (?, ?)", (sentence_id, sentence))
        for position, word_id in enumerate(word_ids):
            db.execute("INSERT INTO WordsInSentences (SentenceID, WordID, Position) VALUES (?, ?, ?)",
                       (sentence_id, word_id, position))
    db.execute("INSERT INTO BookletSettings (ID) VALUES (1)")
    db.commit()
    db.close()
    return pack


def add_chapter(pack: Path, lesson: int, gp_ids: list[int], **columns: object) -> int:
    db = sqlite3.connect(pack / "language.db")
    values = {"LessonID": lesson, "Position": 0, "Booklet": 1, **columns}
    cursor = db.execute(f"INSERT INTO BookletChapters ({', '.join(values)}) VALUES ({', '.join('?' * len(values))})",
                        list(values.values()))
    chapter = cursor.lastrowid
    for gp_id in gp_ids:
        db.execute("INSERT INTO BookletChapterGPs (ChapterID, GPID) VALUES (?, ?)", (chapter, gp_id))
    db.commit()
    db.close()
    return chapter


def execute(pack: Path, sql: str, *parameters: object) -> None:
    db = sqlite3.connect(pack / "language.db")
    db.execute(sql, parameters)
    db.commit()
    db.close()


@pytest.fixture
def pack_folder(tmp_path: Path) -> Path:
    return make_pack(tmp_path)


def own(chapters):
    """The chapters a test wrote, without the forced ones made for the lessons
    it left without (negative IDs): ``pack.chapters`` or a booklet's chapters."""
    return [chapter for chapter in chapters if getattr(chapter, "chapter", chapter).id > 0]
