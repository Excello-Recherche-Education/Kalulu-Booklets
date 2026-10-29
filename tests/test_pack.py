import sqlite3

import pytest

from conftest import add_chapter, make_pack, own
from kalulu_booklets.pack import PackError, load


def test_refuses_another_schema_version(tmp_path):
    with pytest.raises(PackError, match="schema version 1"):
        load(make_pack(tmp_path, version=1))


def test_refuses_version_3(tmp_path):
    with pytest.raises(PackError, match="schema version 3; this generator reads version 4"):
        load(make_pack(tmp_path, version=3))


def test_reads_the_fonts_that_replace_the_defaults(pack_folder):
    db = sqlite3.connect(pack_folder / "language.db")
    db.execute("INSERT INTO BookletFonts (ID, Name, File) VALUES (4, 'Loops', 'marelle/Marelle2-Regular.ttf')")
    db.execute("INSERT INTO BookletFonts (ID, Name, File) VALUES (5, 'Unused', 'marelle/MarelleBaton-Regular.ttf')")
    db.execute("UPDATE BookletSettings SET CursiveFontID = 4")
    db.commit()
    db.close()
    fonts = load(pack_folder).fonts
    assert list(fonts) == ["cursive"]
    assert (fonts["cursive"].name, fonts["cursive"].file) == ("Loops", "marelle/Marelle2-Regular.ttf")


def test_a_pack_without_chapters_gets_one_per_lesson(pack_folder):
    pack = load(pack_folder)
    assert pack.made_chapters_for == [1, 2, 3]
    assert [(c.lesson, c.title, c.gp_ids, c.booklet, c.position) for c in pack.chapters] == [
        (1, "A a", [1], 1, 0),
        (2, "L l", [2], 1, 0),
        (3, "U u N n", [3, 4, 5], 1, 0),  # the silent e is taught, not in the title
    ]
    assert all(chapter.id < 0 and not chapter.overrides for chapter in pack.chapters)


def test_every_lesson_without_a_chapter_gets_its_forced_one(pack_folder):
    add_chapter(pack_folder, 2, [2], Booklet=1, Title="Lesson two")
    add_chapter(pack_folder, 2, [2], Position=1, Booklet=2, Title="Optional")
    pack = load(pack_folder)
    assert pack.made_chapters_for == [1, 3]
    assert [(c.lesson, c.position, c.booklet, c.title, c.id < 0) for c in pack.chapters] == [
        (1, 0, 1, "A a", True),
        (2, 0, 1, "Lesson two", False),
        (2, 1, 2, "Optional", False),
        # The booklet of the last chapter before it: the optional one's.
        (3, 0, 2, "U u N n", True),
    ]


def test_a_lesson_with_chapters_gets_none_made(pack_folder):
    for lesson in (1, 2, 3):
        add_chapter(pack_folder, lesson, [lesson])
    pack = load(pack_folder)
    assert pack.made_chapters_for == [] and all(chapter.id > 0 for chapter in pack.chapters)


def test_refuses_a_folder_without_language_db(tmp_path):
    with pytest.raises(PackError, match="no language.db"):
        load(tmp_path)


def test_readable_at_the_last_first_lesson_of_its_gps(pack_folder):
    pack = load(pack_folder)
    assert pack.words[1].lesson == 2  # "la": l is taught in lesson 2
    assert pack.words[2].lesson == 3  # "lune"


def test_chapters_follow_the_lessons_then_their_position(pack_folder):
    later = add_chapter(pack_folder, 3, [3])
    second = add_chapter(pack_folder, 2, [2], Position=1)
    first = add_chapter(pack_folder, 2, [2], Position=0)
    assert [chapter.id for chapter in own(load(pack_folder).chapters)] == [first, second, later]


def test_a_chapter_setting_overrides_the_language(pack_folder):
    add_chapter(pack_folder, 3, [3], WordCount=2)
    pack = load(pack_folder)
    chapter = own(pack.chapters)[0]
    assert pack.setting(chapter, "WordCount") == 2
    assert pack.setting(chapter, "SyllableCount") == 12


def test_the_pack_is_opened_read_only(pack_folder):
    before = (pack_folder / "language.db").read_bytes()
    load(pack_folder)
    assert (pack_folder / "language.db").read_bytes() == before
