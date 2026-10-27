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
    _, chapter = chapter_content(pack_folder, WordCount=4)
    # "la" holds no GP of the chapter, "lunule" is an exception, "l" has no
    # vowel. Booklet-only first ("Luna"), then in the pack's order.
    assert texts(chapter.words) == ["Luna", "lune", "une", "nu"]


def test_words_short_of_the_count_are_repeated_and_said(pack_folder):
    booklet, chapter = chapter_content(pack_folder, WordCount=6)
    assert texts(chapter.words) == ["Luna", "lune", "une", "nu", "Luna", "lune"]
    assert "Lesson 3, chapter 1: WordCount is 6, and only 4 words qualify: they are repeated" in booklet.notes


def test_syllables_repeat_until_the_count(pack_folder):
    _, chapter = chapter_content(pack_folder, SyllableCount=5)
    assert texts(chapter.syllables) == ["nu", "lu", "un", "nu", "lu"]


def add_entries(pack_folder, chapter_id, part, entries):
    for position, text in enumerate(entries):
        execute(pack_folder, "INSERT INTO BookletEntries (ChapterID, Part, Position, Text) VALUES (?, ?, ?, ?)",
                chapter_id, part, position, text)


def test_picks_past_the_count_lose_the_last_ones(pack_folder):
    chapter_id = add_chapter(pack_folder, 3, [3], WordCount=1)
    add_entries(pack_folder, chapter_id, 2, ["la Lune", "une lune"])
    booklet = content.booklet(load(pack_folder), 1)
    assert texts(booklet.chapters[0].words) == ["la Lune"]
    assert "Lesson 3, chapter 1: 2 words picked and WordCount is 1: the last 1 are left out" in booklet.notes


def test_picks_short_of_the_count_are_filled_from_the_pack(pack_folder):
    chapter_id = add_chapter(pack_folder, 3, [3], WordCount=3, SyllableCount=3)
    add_entries(pack_folder, chapter_id, 2, ["la Lune"])
    add_entries(pack_folder, chapter_id, 1, ["un"])
    chapter = content.booklet(load(pack_folder), 1).chapters[0]
    # "lune" is already printed, as "la Lune": the fill skips it.
    assert texts(chapter.words) == ["la Lune", "Luna", "une"]
    assert texts(chapter.syllables) == ["un", "nu", "lu"]


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


def test_sentence_pages_minus_one_prints_no_sentence(pack_folder):
    chapter_id = add_chapter(pack_folder, 3, [3], SentencePages=-1)
    add_sentences(pack_folder, chapter_id, [2, 2])
    booklet = content.booklet(load(pack_folder), 1)
    assert booklet.chapters[0].paragraphs == []
    assert "Lesson 3, chapter 1: SentencePages is -1, so its 2 sentence(s) are not printed" in booklet.notes
