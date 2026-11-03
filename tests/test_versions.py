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


def test_the_a4_sheet_centres_its_two_pages():
    # Two A5 pages (296 mm) on an A4 sheet (297 mm): half a millimetre each side.
    margin = (layout.landscape(layout.A4)[0] - 2 * layout.PAGE_WIDTH) / 2
    assert margin == pytest.approx(0.5 * layout.mm, abs=0.01)
    assert layout.sheet_sides(4) == [((3, margin), (0, margin + layout.PAGE_WIDTH)),
                                     ((1, margin), (2, margin + layout.PAGE_WIDTH))]


def test_a_picture_name_matches_its_letter_case(pack_folder):
    # Open o: only the closed o's picture is there, and a disk that ignores
    # case must not hand it over.
    execute(pack_folder, "INSERT INTO GPs (ID, Grapheme, Phoneme, Type) VALUES (9, 'o', 'O', 1)")
    _picture(pack_folder, "o-o.png")
    assert load(pack_folder).picture(9) is None


def test_the_no_writing_version_closes_on_folded_sheets(pack_folder):
    chapter = add_chapter(pack_folder, 2, [2], Title="L l")
    execute(pack_folder, "INSERT INTO BookletEntries (ChapterID, Part, Position, Text, Text2, Header) "
                         "VALUES (?, 3, 0, 'la', '', 0)", chapter)
    assert len(_pages(pack_folder, NO_WRITING)) % 4 == 0


def test_the_teacher_version_keeps_the_base_page_numbers(pack_folder):
    _picture(pack_folder, "l-l.png")
    add_chapter(pack_folder, 2, [2], Title="L l", ImageGPID=2)
    base, teacher = _pages(pack_folder, BASE), _pages(pack_folder, TEACHER)
    numbers = lambda pages: [folio for folio, page in zip(layout._folios(pages), pages)  # noqa: E731
                             if page.steps and page.numbered and not page.shares_next_number]
    assert numbers(teacher) == numbers(base)[:len(numbers(teacher))]


def test_a_note_names_the_versions_that_gave_it_once_each(pack_folder, tmp_path, capsys):
    # A word too wide for its cell, among the words and in the fluency test:
    # each version notes it twice.
    chapter = add_chapter(pack_folder, 2, [2], Title="L l")
    for part in (2, 5):
        execute(pack_folder, "INSERT INTO BookletEntries (ChapterID, Part, Position, Text, Text2, Header) "
                             "VALUES (?, ?, 0, 'lalalalalalalalalalalala', '', 0)", chapter, part)
    out = tmp_path / "out"
    assert main(["build", str(pack_folder), "--version", "base", "--version", "teacher", "--version", "base",
                 "--out", str(out)]) == 0
    said = capsys.readouterr().out
    assert "base, base" not in said
    assert [line for line in said.splitlines() if "lalala" in line and "[" in line] == []


def _booklet_image(pack_folder, file="puits.png", picture=True):
    folder = pack_folder / "booklet_images"
    folder.mkdir(exist_ok=True)
    if picture:
        Image.new("RGB", (40, 30), "brown").save(folder / file)
    else:
        (folder / file).write_text("version https://git-lfs.github.com/spec/v1\n")
    execute(pack_folder, "INSERT INTO BookletImages (ID, Name, File) VALUES (1, 'Puits', ?)", file)


def test_a_chapter_shows_its_own_booklet_image_on_the_teacher_page(pack_folder):
    # Lesson 2 teaches "l", which has no Look & Learn image here: the chapter
    # names a picture of the pack's own instead.
    _booklet_image(pack_folder)
    add_chapter(pack_folder, 2, [2], Title="L l", ImageID=1)
    pack = load(pack_folder)
    chapter = next(chapter for chapter in pack.chapters if chapter.lesson == 2)
    assert pack.chapter_picture(chapter) == pack_folder / "booklet_images" / "puits.png"
    assert sum(page.shares_next_number for page in _pages(pack_folder, TEACHER)) == 1


def test_a_booklet_image_not_checked_out_leaves_the_teacher_page_out_and_says_so(pack_folder):
    _booklet_image(pack_folder, picture=False)
    add_chapter(pack_folder, 2, [2], Title="L l", ImageID=1)
    booklet = content.booklet(load(pack_folder), 1)
    assert not any(page.shares_next_number for page in layout.Layout(booklet, fonts.load(fonts.PINNED), TEACHER).run())
    assert any("booklet_images/puits.png cannot be printed" in note for note in booklet.notes)


def test_a_chapter_without_a_booklet_image_keeps_its_gp_picture(pack_folder):
    _picture(pack_folder, "l-l.png")
    _booklet_image(pack_folder)
    add_chapter(pack_folder, 2, [2], Title="L l", ImageGPID=2)
    pack = load(pack_folder)
    chapter = next(chapter for chapter in pack.chapters if chapter.lesson == 2)
    assert pack.chapter_picture(chapter).name == "l-l.png"
