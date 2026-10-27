import pytest

from conftest import add_chapter, make_pack
from kalulu_booklets.pack import PackError, load


def test_refuses_another_schema_version(tmp_path):
    with pytest.raises(PackError, match="schema version 1"):
        load(make_pack(tmp_path, version=1))


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
    assert [chapter.id for chapter in load(pack_folder).chapters] == [first, second, later]


def test_a_chapter_setting_overrides_the_language(pack_folder):
    add_chapter(pack_folder, 3, [3], WordCount=2)
    pack = load(pack_folder)
    chapter = pack.chapters[0]
    assert pack.setting(chapter, "WordCount") == 2
    assert pack.setting(chapter, "SyllableCount") == 12


def test_the_pack_is_opened_read_only(pack_folder):
    before = (pack_folder / "language.db").read_bytes()
    load(pack_folder)
    assert (pack_folder / "language.db").read_bytes() == before
