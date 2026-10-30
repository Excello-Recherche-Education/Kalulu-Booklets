"""The adapted versions (adapted.py): Dyslexie, Dyspraxie and TDAH."""

import pytest

from conftest import add_chapter, execute
from kalulu_booklets import content, fonts, layout
from kalulu_booklets.adapted import AdaptedLayout, fluency_items
from kalulu_booklets.content import EARLIER, OWN, TOUCHING, Styled
from kalulu_booklets.pack import load
from kalulu_booklets.versions import ADHD, BASE, DYSLEXIA, DYSPRAXIA

pytestmark = pytest.mark.skipif(not (fonts.PINNED / fonts.CURSIVE).is_file(),
                                reason="kalulu-languages/ has no fonts/ at its pinned commit")


def _layout(pack_folder, version):
    booklet = content.booklet(load(pack_folder), 1)
    return AdaptedLayout(booklet, fonts.load(fonts.PINNED), version)


def _two_letter_gps(pack_folder):
    # "ch" taught at lesson 2, "ou" at lesson 4; "chou" spells both.
    execute(pack_folder, "INSERT INTO GPs (ID, Grapheme, Phoneme, Type) VALUES (6, 'ch', 'S', 2)")
    execute(pack_folder, "INSERT INTO GPs (ID, Grapheme, Phoneme, Type) VALUES (7, 'ou', 'u', 1)")
    execute(pack_folder, "INSERT INTO GPsInLessons (GPID, LessonID) VALUES (6, 2)")
    execute(pack_folder, "INSERT INTO Lessons (ID, LessonNb) VALUES (4, 4)")
    execute(pack_folder, "INSERT INTO GPsInLessons (GPID, LessonID) VALUES (7, 4)")
    execute(pack_folder, "INSERT INTO Words (ID, Word, Exception, BookletOnly) VALUES (8, 'chou', 0, 0)")
    for position, gp_id in enumerate((6, 7)):
        execute(pack_folder, "INSERT INTO GPsInWords (WordID, GPID, Position) VALUES (8, ?, ?)", gp_id, position)


def test_a_chapter_colours_its_own_graphemes_and_earlier_ones(pack_folder):
    _two_letter_gps(pack_folder)
    pack = load(pack_folder)
    lesson_4 = next(chapter for chapter in pack.chapters if chapter.lesson == 4)
    lesson_2 = next(chapter for chapter in pack.chapters if chapter.lesson == 2)
    # At lesson 4, "ch" is earlier and "ou" its own, but it touches "ch".
    assert content.styled(pack, "chou", False, chapter=lesson_4).tints == ((0, 2, EARLIER), (2, 4, TOUCHING))
    # Single letters are never coloured, nor a grapheme not taught yet.
    assert content.styled(pack, "la lune", False, chapter=lesson_4).tints == ()
    assert content.styled(pack, "chou", False, chapter=lesson_2).tints == ((0, 2, OWN),)


def test_the_fluency_test_keeps_its_easier_and_harder_halves():
    items = [Styled(str(index)) for index in range(50)]
    kept = [int(item.text) for item in fluency_items(items)]
    assert kept == [0, 1, 2, 5, 6, 7, 10, 11, 12, 15, 16, 17, 30, 31, 32, 35, 36, 37, 40, 41, 42, 45, 46, 47]
    assert len(fluency_items(items[:20])) == 12


def test_an_adapted_version_prints_the_sentences_the_base_chose(pack_folder):
    add_chapter(pack_folder, 3, [3, 4], Title="u n")
    booklet = content.booklet(load(pack_folder), 1)
    base = layout.Layout(booklet, fonts.load(fonts.PINNED), BASE)
    base.run()
    adapted = _layout(pack_folder, ADHD)
    assert adapted.chosen == base.chosen and any(adapted.chosen.values())


def test_the_base_notes_are_not_said_again(pack_folder):
    booklet = content.booklet(load(pack_folder), 1)
    before = list(booklet.notes)
    AdaptedLayout(booklet, fonts.load(fonts.PINNED), DYSLEXIA)
    assert booklet.notes == before


@pytest.mark.parametrize("version", [DYSLEXIA, DYSPRAXIA, ADHD])
def test_an_adapted_booklet_closes_on_folded_sheets(pack_folder, version):
    add_chapter(pack_folder, 2, [2], Title="L l")
    pages = _layout(pack_folder, version).run()
    assert len(pages) % 4 == 0


def test_a_language_with_no_adaptations_text_has_no_such_page_and_says_so(pack_folder):
    laid_out = _layout(pack_folder, DYSLEXIA)
    laid_out.run()
    assert any("no adaptations page" in note for note in laid_out.booklet.notes)


def test_french_has_the_adaptations_page(pack_folder):
    folder = pack_folder.rename(pack_folder.with_name("fr_FR"))
    booklet = content.booklet(load(folder), 1)
    laid_out = AdaptedLayout(booklet, fonts.load(fonts.PINNED), DYSPRAXIA)
    pages = laid_out.run()
    assert not any("no adaptations page" in note for note in booklet.notes)
    # The adaptations page, then the back cover; neither is numbered.
    assert not pages[-2].numbered and pages[-2].steps


def test_dyspraxia_has_no_writing_page(pack_folder):
    chapter = add_chapter(pack_folder, 2, [2], Title="L l", SyllableCount=0, WordCount=0, SentencePages=-1)
    execute(pack_folder, "INSERT INTO BookletEntries (ChapterID, Part, Position, Text, Text2, Header) "
                         "VALUES (?, 3, 0, 'la', '', 0)", chapter)
    used = lambda version: sum(1 for page in _layout(pack_folder, version).run() if page.steps)  # noqa: E731
    assert used(DYSPRAXIA) == used(ADHD) - 1
