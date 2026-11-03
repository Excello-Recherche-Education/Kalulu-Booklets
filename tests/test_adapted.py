"""The adapted versions (adapted.py): Dyslexie, Dyspraxie and TDAH."""

import io

import pytest
from reportlab.pdfgen.canvas import Canvas

from conftest import add_chapter, execute
from kalulu_booklets import adapted, content, fonts, layout
from kalulu_booklets.adapted import AdaptedLayout
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
    # At lesson 4, "ch" is earlier and "ou" its own: they touch, and the
    # lesson's own keeps its colour, so "ch" changes.
    assert content.styled(pack, "chou", False, chapter=lesson_4).tints == ((0, 2, TOUCHING), (2, 4, OWN))
    # Single letters are never coloured, nor a grapheme not taught yet.
    assert content.styled(pack, "la lune", False, chapter=lesson_4).tints == ()
    assert content.styled(pack, "chou", False, chapter=lesson_2).tints == ((0, 2, OWN),)


def test_of_two_earlier_graphemes_that_touch_the_second_changes(pack_folder):
    _two_letter_gps(pack_folder)
    execute(pack_folder, "INSERT INTO Lessons (ID, LessonNb) VALUES (5, 5)")
    execute(pack_folder, "INSERT INTO GPs (ID, Grapheme, Phoneme, Type) VALUES (9, 'an', 'an', 1)")
    execute(pack_folder, "INSERT INTO GPsInLessons (GPID, LessonID) VALUES (9, 5)")
    pack = load(pack_folder)
    lesson_5 = next(chapter for chapter in pack.chapters if chapter.lesson == 5)
    assert content.styled(pack, "chou", False, chapter=lesson_5).tints == ((0, 2, EARLIER), (2, 4, TOUCHING))


def test_a_grapheme_of_the_chapter_lesson_is_its_own_even_when_the_chapter_does_not_list_it(pack_folder):
    _two_letter_gps(pack_folder)
    add_chapter(pack_folder, 4, [], Title="où")
    pack = load(pack_folder)
    lesson_4 = next(chapter for chapter in pack.chapters if chapter.lesson == 4)
    assert 7 not in lesson_4.gp_ids
    assert content.styled(pack, "chou", False, chapter=lesson_4).tints == ((0, 2, TOUCHING), (2, 4, OWN))


def test_a_story_title_heads_its_page_and_wraps(pack_folder, monkeypatch):
    title = "Comment le lapin Kalulu a appris à lire tout seul"
    chapter = add_chapter(pack_folder, 2, [2], Title="L l")
    execute(pack_folder, "INSERT INTO BookletStories (ChapterID, Position, Title, Text) VALUES (?, 0, ?, ?)",
            chapter, title, "La lune.\n\nUne lune nue.")
    laid_out = _layout(pack_folder, ADHD)
    drawn = []
    monkeypatch.setattr(laid_out, "draw_line", lambda canvas, line, baseline, *rest: drawn.append((line, baseline)))
    canvas = Canvas(io.BytesIO())
    for page in laid_out.run():
        for step in page.steps:
            step(canvas)
    lines = [(" ".join(word.text for word in line.words), baseline) for line, baseline in drawn
             if line.face is laid_out.fonts.script_bold]
    assert " ".join(text for text, _ in lines) == title and len(lines) > 1
    story = [baseline for line, baseline in drawn if line.face is laid_out.fonts.script and
             line.words[0].text in ("La", "Une")]
    assert min(baseline for _, baseline in lines) > max(story)
    for line, _ in drawn:
        if line.face is laid_out.fonts.script_bold:
            assert sum(laid_out.width(line.face, word.text, line.size) for word in line.words) <= adapted.TEXT_WIDTH


def test_a_fluency_item_wider_than_its_column_is_said(pack_folder):
    laid_out = _layout(pack_folder, ADHD)
    chapter = laid_out.booklet.chapters[0]
    laid_out.fluency(chapter, [Styled("lalalalalalalala"), Styled("la")])
    assert any("lalalalalalalala" in note and "wider than its cell" in note for note in laid_out.booklet.notes)


@pytest.mark.parametrize("version", [DYSLEXIA, DYSPRAXIA, ADHD])
def test_the_fluency_test_keeps_every_item_on_pages_of_3_by_4(pack_folder, version):
    laid_out = _layout(pack_folder, version)
    items = [Styled(str(index)) for index in range(50)]
    before = len(laid_out.pages)
    laid_out.fluency(None, items)
    # 50 items, 12 a page: 5 pages, the last holding 2.
    assert len(laid_out.pages) - before == 5


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


def _pictures_drawn(laid_out, monkeypatch):
    drawn = []
    monkeypatch.setattr(adapted, "_picture", lambda canvas, name, *rest, **options: drawn.append(name))
    canvas = Canvas(io.BytesIO())
    for page in laid_out.run():
        for step in page.steps:
            step(canvas)
    return drawn


def _writing_and_table(pack_folder):
    chapter = add_chapter(pack_folder, 2, [2], Title="L l", SyllableCount=0, WordCount=0, SentencePages=-1)
    execute(pack_folder, "INSERT INTO BookletEntries (ChapterID, Part, Position, Text, Text2, Header) "
                         "VALUES (?, 3, 0, 'la', '', 0)", chapter)
    for position, (left, right, header) in enumerate((("a", "b", 1), ("la", "le", 0))):
        execute(pack_folder, "INSERT INTO BookletEntries (ChapterID, Part, Position, Text, Text2, Header) "
                             "VALUES (?, 4, ?, ?, ?, ?)", chapter, position, left, right, header)


def test_dyspraxia_keeps_the_writing_pages(pack_folder):
    _writing_and_table(pack_folder)
    used = lambda version: sum(1 for page in _layout(pack_folder, version).run() if page.steps)  # noqa: E731
    assert used(DYSPRAXIA) == used(ADHD)


def test_adhd_draws_no_animal(pack_folder, monkeypatch):
    _writing_and_table(pack_folder)
    assert set(_pictures_drawn(_layout(pack_folder, DYSPRAXIA), monkeypatch)) == {"penguin", "caterpillar"}
    assert _pictures_drawn(_layout(pack_folder, ADHD), monkeypatch) == []
