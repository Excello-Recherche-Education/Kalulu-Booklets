from conftest import add_chapter, execute
from kalulu_booklets import content
from kalulu_booklets.content import CURSIVE, SCRIPT
from kalulu_booklets.pack import load


def chapter_content(pack_folder, **columns):
    add_chapter(pack_folder, 3, [3, 4, 5], **columns)
    booklet = content.booklet(load(pack_folder), 1)
    return booklet, booklet.chapters[0] if booklet.chapters else None


def texts(items):
    return [item.text for item in items]


def test_automatic_words_hold_a_chapter_gp_and_are_readable(pack_folder):
    _, chapter = chapter_content(pack_folder)
    # "la" holds no GP of the chapter, "lunule" is an exception, "l" has no
    # vowel; "Luna" is booklet-only, which the booklets print. Newest first,
    # then shortest.
    assert texts(chapter.words) == ["nu", "une", "lune", "Luna"]


def test_syllables_repeat_until_the_count(pack_folder):
    _, chapter = chapter_content(pack_folder, SyllableCount=5)
    assert texts(chapter.syllables) == ["nu", "lu", "un", "nu", "lu"]


def test_a_listed_part_replaces_the_automatic_choice(pack_folder):
    chapter_id = add_chapter(pack_folder, 3, [3], WordCount=1)
    execute(pack_folder, "INSERT INTO BookletEntries (ChapterID, Part, Position, Text) VALUES (?, 2, 0, 'la Lune')",
            chapter_id)
    execute(pack_folder, "INSERT INTO BookletEntries (ChapterID, Part, Position, Text) VALUES (?, 2, 1, 'une lune')",
            chapter_id)
    chapter = content.booklet(load(pack_folder), 1).chapters[0]
    assert texts(chapter.words) == ["la Lune", "une lune"]  # all of them, whatever WordCount


def test_silent_letters_come_from_the_decomposition(pack_folder):
    _, chapter = chapter_content(pack_folder, GreySilent=1)
    lune = chapter.words[texts(chapter.words).index("lune")]
    assert lune.grey == {3}


def test_no_grey_unless_the_chapter_asks(pack_folder):
    _, chapter = chapter_content(pack_folder)
    assert all(not item.grey for item in chapter.words)


def test_a_listed_entry_is_matched_word_by_word_case_ignored(pack_folder):
    pack = load(pack_folder)
    styled = content.styled(pack, "la Lune", grey=True)
    assert styled.grey == {6}


def test_a_word_in_no_list_is_printed_without_grey(pack_folder):
    assert content.styled(load(pack_folder), "Léo", grey=True).grey == frozenset()


def test_capitals_are_spread_evenly(pack_folder):
    _, chapter = chapter_content(pack_folder, SyllableCount=8, UppercaseProportion=0.25)
    assert [item.text.isupper() for item in chapter.syllables] == [False, False, False, True] * 2


def add_sentences(pack_folder, chapter_id, breaks):
    for position, brk in enumerate(breaks):
        execute(pack_folder, "INSERT INTO BookletSentences (ChapterID, SentenceID, Position, Break) VALUES (?, ?, ?, ?)",
                chapter_id, 1 + position % 2, position, brk)


def test_breaks_make_lines_and_paragraphs(pack_folder):
    chapter_id = add_chapter(pack_folder, 3, [3])
    add_sentences(pack_folder, chapter_id, [2, 0, 1, 2])
    chapter = content.booklet(load(pack_folder), 1).chapters[0]
    assert [[texts(line) for line in paragraph.lines] for paragraph in chapter.paragraphs] == [
        [["La lune.", "Une lune nue."], ["La lune."]],
        [["Une lune nue."]],
    ]
    assert [paragraph.font for paragraph in chapter.paragraphs] == [CURSIVE, SCRIPT]


def test_a_language_without_cursive_prints_sentences_in_script(pack_folder):
    execute(pack_folder, "UPDATE BookletSettings SET Cursive = 0")
    chapter_id = add_chapter(pack_folder, 3, [3], SentenceFont=2)
    add_sentences(pack_folder, chapter_id, [2, 2])
    chapter = content.booklet(load(pack_folder), 1).chapters[0]
    assert [paragraph.font for paragraph in chapter.paragraphs] == [SCRIPT, SCRIPT]
    assert chapter.writing_font == SCRIPT


def test_a_sentence_keeps_its_own_words_for_grey(pack_folder):
    chapter_id = add_chapter(pack_folder, 3, [3], GreySilent=1)
    add_sentences(pack_folder, chapter_id, [2, 0])
    chapter = content.booklet(load(pack_folder), 1).chapters[0]
    first, second = chapter.paragraphs[0].lines[0]
    assert first.grey == {6}  # "La lun|e|."
    assert second.grey == {2, 7}  # "Un|e| lun|e| nue." -- "nue" is in no list


def test_a_chapter_that_prints_nothing_is_left_out_and_said(pack_folder):
    booklet, chapter = chapter_content(pack_folder, SyllableCount=0, WordCount=0)
    assert chapter is None
    assert booklet.notes == ["Lesson 3, chapter 1: prints nothing, so it has no page"]


def test_a_sentence_read_only_later_is_said(pack_folder):
    chapter_id = add_chapter(pack_folder, 2, [2])
    add_sentences(pack_folder, chapter_id, [2])
    booklet = content.booklet(load(pack_folder), 1)
    assert 'Lesson 2, chapter 1: sentence "La lune." is readable from lesson 3' in booklet.notes
