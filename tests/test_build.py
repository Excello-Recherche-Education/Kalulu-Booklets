"""The whole way, from a pack to a PDF."""

import re

import pytest

from conftest import add_chapter, execute, own
from kalulu_booklets import content, fonts, layout
from kalulu_booklets.cli import main
from kalulu_booklets.pack import load

# The test pack has no Kalulu-Languages checkout around it, so its fonts are
# the pinned ones.
pytestmark = pytest.mark.skipif(not (fonts.PINNED / fonts.CURSIVE).is_file(),
                                reason="kalulu-languages/ has no fonts/ at its pinned commit")


def page_count(path):
    return len(re.findall(rb"/Type\s*/Page[^s]", path.read_bytes()))


def test_builds_one_pdf_per_booklet(pack_folder, tmp_path, capsys):
    first = add_chapter(pack_folder, 2, [2], Title="L l")
    add_chapter(pack_folder, 3, [3, 4, 5], Booklet=2, Title="u n", GreySilent=1)
    for part, text, text2, header in ((3, "lune", "", 0), (4, "la", "une", 1), (5, "lune", "", 0)):
        execute(pack_folder, "INSERT INTO BookletEntries (ChapterID, Part, Position, Text, Text2, Header) "
                             "VALUES (?, ?, 0, ?, ?, ?)", first, part, text, text2, header)
    execute(pack_folder, "INSERT INTO BookletStories (ChapterID, Position, Title, Text) VALUES (?, 0, 'Luna', ?)",
            first, "La lune.\n\nUne lune nue.")

    out = tmp_path / "out"
    assert main(["build", str(pack_folder), "--out", str(out)]) == 0

    for number in (1, 2):
        path = out / "xx_XX" / "base" / f"xx_XX-booklet-{number}.pdf"
        assert path.read_bytes().startswith(b"%PDF")
        assert page_count(path) % 4 == 0  # printed on folded sheets
    assert "xx_XX-booklet-1.pdf" in capsys.readouterr().out


def test_a_pack_without_chapters_prints_one_per_lesson(pack_folder, tmp_path, capsys):
    assert main(["build", str(pack_folder), "--out", str(tmp_path)]) == 0
    out = capsys.readouterr().out
    assert "has no booklet chapter: one per lesson" in out
    assert ", 3 chapter(s))" in out
    assert (tmp_path / "xx_XX" / "base" / "xx_XX-booklet-1.pdf").is_file()


def test_refuses_a_booklet_the_pack_does_not_have(pack_folder, tmp_path, capsys):
    add_chapter(pack_folder, 2, [2], Title="L l")
    assert main(["build", str(pack_folder), "--booklet", "3", "--out", str(tmp_path)]) == 2
    assert "has no booklet 3" in capsys.readouterr().err


@pytest.mark.parametrize("pages, room", [(0, "the page they start on"), (1, "that page and 1 more")])
def test_sentences_beyond_their_pages_are_said(pack_folder, tmp_path, capsys, pages, room):
    chapter = add_chapter(pack_folder, 3, [3], SentencePages=pages, SyllableCount=0, WordCount=0)
    for position in range(90):
        execute(pack_folder, "INSERT INTO BookletSentences (ChapterID, SentenceID, Position, Break) VALUES (?, 1, ?, 1)",
                chapter, position)
    assert main(["build", str(pack_folder), "--out", str(tmp_path)]) == 0
    assert f"do not fit on {room} (SentencePages is {pages})" in capsys.readouterr().out


def test_chosen_sentences_are_whole_and_one_that_overflows_is_passed_over(pack_folder):
    long_one = "Une lune nue. " * 12
    execute(pack_folder, "INSERT INTO Sentences (ID, Sentence) VALUES (3, ?)", long_one.strip())
    for position in range(24):
        execute(pack_folder, "INSERT INTO WordsInSentences (SentenceID, WordID, Position) VALUES (3, ?, ?)",
                [4, 2][position % 2], position)
    add_chapter(pack_folder, 3, [3], SentencePages=0)
    booklet = content.booklet(load(pack_folder), 1)
    chapter = own(booklet.chapters)[0]
    chapter.sentence_pool.sort(key=lambda candidate: candidate[0] != 3)  # the long one first
    pages = layout.Layout(booklet, fonts.load(fonts.PINNED))
    pages.new_page()
    pages.y = layout.BOTTOM + 3 * layout.SENTENCE_SIZE * layout.CURSIVE_LEADING  # room for three lines
    pages.chosen_sentences(chapter)
    assert pages.printed_sentences == {1, 2}  # the long one does not fit, the two short ones do
    assert len(pages.pages) == 1


def _built_notes(pack_folder):
    booklet = content.booklet(load(pack_folder), 1)
    pages = layout.Layout(booklet, fonts.load(fonts.PINNED))
    pages.run()
    return booklet.notes


def test_sentences_from_earlier_lessons_filling_a_chapter_are_said(pack_folder):
    # "La la." holds no "u": it is lesson 2's, printed only to fill the page.
    execute(pack_folder, "INSERT INTO Sentences (ID, Sentence) VALUES (3, 'La la.')")
    for position in range(2):
        execute(pack_folder, "INSERT INTO WordsInSentences (SentenceID, WordID, Position) VALUES (3, 1, ?)", position)
    add_chapter(pack_folder, 3, [3], SyllableCount=0, WordCount=0, SentencePages=0)
    notes = [note for note in _built_notes(pack_folder) if note.startswith("Lesson 3")]
    assert "Lesson 3, chapter 1: not enough content of its own: 1 of its 3 sentences holds none of its GPs, " \
           "taken from earlier lessons to fill its pages (only 2 readable sentences hold one)" in notes


def test_a_chapter_filled_with_its_own_sentences_says_nothing(pack_folder):
    add_chapter(pack_folder, 3, [3], SyllableCount=0, WordCount=0, SentencePages=0)
    assert not [note for note in _built_notes(pack_folder) if "not enough content" in note]
