"""The versions of a booklet (versions.py): the same content, laid out apart."""

import re

import pytest
from PIL import Image

from conftest import add_chapter, execute
from kalulu_booklets import content, fonts, layout
from kalulu_booklets.cli import main
from kalulu_booklets.pack import load
from kalulu_booklets.versions import BASE, NO_WRITING, TEACHER, VERSIONS

pytestmark = pytest.mark.skipif(not (fonts.PINNED / fonts.CURSIVE).is_file(),
                                reason="kalulu-languages/ has no fonts/ at its pinned commit")


def _picture(pack_folder, name):
    folder = pack_folder / "look_and_learn" / "images"
    folder.mkdir(parents=True, exist_ok=True)
    Image.new("RGB", (40, 30), "orange").save(folder / name)


def _pages(pack_folder, version):
    booklet = content.booklet(load(pack_folder), 1)
    return layout.Layout(booklet, fonts.load(fonts.PINNED), version).run()


def test_saddle_stitch_order():
    # Folded and stapled, the sheets read 1, 2, ... 8 (0-based here).
    assert layout.imposition(8) == [(7, 0), (1, 6), (5, 2), (3, 4)]


def test_a_teacher_page_carries_the_next_page_number():
    pages = [layout.Page(numbered=False), layout.Page(shares_next_number=True), layout.Page(), layout.Page()]
    assert layout._folios(pages) == [1, 2, 2, 3]


def test_a_gp_image_is_found_by_its_encoded_name(pack_folder):
    execute(pack_folder, "INSERT INTO GPs (ID, Grapheme, Phoneme, Type) VALUES (9, 'e', 'E', 1)")
    _picture(pack_folder, "e-cap.e.png")
    assert load(pack_folder).picture(9).name == "e-cap.e.png"


def test_a_git_lfs_pointer_is_not_a_picture(pack_folder):
    folder = pack_folder / "look_and_learn" / "images"
    folder.mkdir(parents=True)
    (folder / "a-a.png").write_text("version https://git-lfs.github.com/spec/v1\n")
    assert load(pack_folder).picture(1) is None


def test_the_teacher_version_adds_a_page_before_a_chapter_with_a_picture(pack_folder):
    _picture(pack_folder, "l-l.png")
    add_chapter(pack_folder, 2, [2], Title="L l", ImageGPID=2)
    teacher = _pages(pack_folder, TEACHER)
    # Lesson 2's chapter has a picture; lessons 1 and 3 get forced chapters
    # with none, and no teacher page.
    assert sum(page.shares_next_number for page in teacher) == 1
    assert not any(page.shares_next_number for page in _pages(pack_folder, BASE))


def test_the_no_writing_version_has_no_writing_page(pack_folder):
    chapter = add_chapter(pack_folder, 2, [2], Title="L l", SyllableCount=0, WordCount=0, SentencePages=-1)
    execute(pack_folder, "INSERT INTO BookletEntries (ChapterID, Part, Position, Text, Text2, Header) "
                         "VALUES (?, 3, 0, 'la', '', 0)", chapter)
    used = lambda pages: sum(1 for page in pages if page.steps)  # noqa: E731
    assert used(_pages(pack_folder, NO_WRITING)) == used(_pages(pack_folder, BASE)) - 1


def test_every_version_gets_a_folder_and_the_printed_ones_an_a4_copy(pack_folder, tmp_path):
    add_chapter(pack_folder, 2, [2], Title="L l")
    out = tmp_path / "out"
    assert main(["build", str(pack_folder), "--out", str(out)]) == 0
    for version in VERSIONS.values():
        a5 = out / "xx_XX" / version.name / version.file_name("xx_XX", 1)
        assert a5.read_bytes().startswith(b"%PDF")
        imposed = a5.with_name(version.file_name("xx_XX", 1, imposed=True))
        assert imposed.is_file() == version.printed
        if version.printed:
            a5_pages = len(re.findall(rb"/Type\s*/Page[^s]", a5.read_bytes()))
            data = imposed.read_bytes()
            assert len(re.findall(rb"/Type\s*/Page[^s]", data)) * 2 == a5_pages
            assert re.search(rb"/MediaBox \[ 0 0 841\.8898 595\.2756 \]", data)  # A4 landscape


def test_one_version_only(pack_folder, tmp_path):
    out = tmp_path / "out"
    assert main(["build", str(pack_folder), "--version", "teacher", "--out", str(out)]) == 0
    assert [folder.name for folder in (out / "xx_XX").iterdir()] == ["teacher"]


def test_a_made_chapter_takes_its_first_gp_with_a_picture(pack_folder):
    # Lesson 3 teaches u, n and the silent e: only n has an image.
    _picture(pack_folder, "n-n.png")
    made = {chapter.lesson: chapter for chapter in load(pack_folder).chapters}
    assert made[3].image_gp_id == 4 and made[1].image_gp_id is None
