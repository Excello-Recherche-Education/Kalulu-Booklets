from conftest import add_chapter, execute, own
from kalulu_booklets import content
from kalulu_booklets.content import CURSIVE, SCRIPT
from kalulu_booklets.pack import load


def chapter_content(pack_folder, **columns):
    add_chapter(pack_folder, 3, [3, 4, 5], **columns)
    booklet = content.booklet(load(pack_folder), 1)
    chapters = own(booklet.chapters)
    return booklet, chapters[0] if chapters else None


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
    assert texts(own(booklet.chapters)[0].words) == ["la Lune"]
    assert "Lesson 3, chapter 1: 2 words picked and WordCount is 1: the last 1 are left out" in booklet.notes


def test_picks_short_of_the_count_are_filled_from_the_pack(pack_folder):
    chapter_id = add_chapter(pack_folder, 3, [3], WordCount=3, SyllableCount=3)
    add_entries(pack_folder, chapter_id, 2, ["la Lune"])
    add_entries(pack_folder, chapter_id, 1, ["un"])
    chapter = own(content.booklet(load(pack_folder), 1).chapters)[0]
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


def test_a_hyphenated_word_is_its_own_or_its_parts(pack_folder):
    execute(pack_folder, "INSERT INTO Words (ID, Word, BookletOnly) VALUES (8, 'la-lune', 1)")
    for position, gp_id in enumerate([2, 1, 2, 3, 4, 5]):
        execute(pack_folder, "INSERT INTO GPsInWords (WordID, GPID, Position) VALUES (8, ?, ?)", gp_id, position)
    pack = load(pack_folder)
    # The word's GPs spell it once its hyphen is skipped: its silent e is grey.
    assert content.styled(pack, "La-lune", grey=True).grey == {6}
    # "une-lune" is no word, so it is "une" and "lune", each with its silent e.
    assert content.styled(pack, "une-lune", grey=True).grey == {2, 7}


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
    chapter = own(content.booklet(load(pack_folder), 1).chapters)[0]
    assert [[texts(line) for line in paragraph.lines] for paragraph in chapter.paragraphs] == [
        [["La lune.", "Une lune nue."], ["La lune."]],
        [["Une lune nue."]],
    ]
    assert [paragraph.font for paragraph in chapter.paragraphs] == [CURSIVE, SCRIPT]


def test_a_language_without_cursive_prints_sentences_in_script(pack_folder):
    execute(pack_folder, "UPDATE BookletSettings SET Cursive = 0")
    chapter_id = add_chapter(pack_folder, 3, [3], SentenceFont=2)
    add_sentences(pack_folder, chapter_id, [2, 2])
    chapter = own(content.booklet(load(pack_folder), 1).chapters)[0]
    assert [paragraph.font for paragraph in chapter.paragraphs] == [SCRIPT, SCRIPT]
    assert chapter.writing_font == SCRIPT


def test_a_sentence_keeps_its_own_words_for_grey(pack_folder):
    chapter_id = add_chapter(pack_folder, 3, [3], GreySilent=1)
    add_sentences(pack_folder, chapter_id, [2, 0])
    chapter = own(content.booklet(load(pack_folder), 1).chapters)[0]
    first, second = chapter.paragraphs[0].lines[0]
    assert first.grey == {6}  # "La lun|e|."
    assert second.grey == {2, 7}  # "Un|e| lun|e| nue." -- "nue" is in no list


def test_a_chapter_that_prints_nothing_is_left_out_and_said(pack_folder):
    booklet, chapter = chapter_content(pack_folder, SyllableCount=0, WordCount=0, SentencePages=-1)
    assert chapter is None
    # Lessons 1 and 2 have their forced chapters made, which print.
    assert [note for note in booklet.notes if note.startswith("Lesson 3")] == [
        "Lesson 3, chapter 1: prints nothing, so it has no page"]


def test_a_sentence_read_only_later_is_said(pack_folder):
    chapter_id = add_chapter(pack_folder, 2, [2])
    add_sentences(pack_folder, chapter_id, [2])
    booklet = content.booklet(load(pack_folder), 1)
    assert 'Lesson 2, chapter 1: sentence "La lune." is readable from lesson 3' in booklet.notes


def test_sentence_pages_minus_one_prints_no_sentence(pack_folder):
    chapter_id = add_chapter(pack_folder, 3, [3], SentencePages=-1)
    add_sentences(pack_folder, chapter_id, [2, 2])
    booklet = content.booklet(load(pack_folder), 1)
    assert own(booklet.chapters)[0].paragraphs == []
    assert "Lesson 3, chapter 1: SentencePages is -1, so its 2 sentence(s) are not printed" in booklet.notes


def test_a_chapter_picking_no_sentence_chooses_from_the_pack(pack_folder):
    execute(pack_folder, "INSERT INTO Sentences (ID, Sentence, BookletOnly) VALUES (3, 'Une lune.', 1)")
    for position, word_id in enumerate([4, 2]):
        execute(pack_folder, "INSERT INTO WordsInSentences (SentenceID, WordID, Position) VALUES (3, ?, ?)",
                word_id, position)
    _, chapter = chapter_content(pack_folder)
    assert chapter.paragraphs == []
    # Booklet-only first, then the pack's order.
    assert [(sentence_id, text.text) for sentence_id, text in chapter.sentence_pool] == [
        (3, "Une lune."), (1, "La lune."), (2, "Une lune nue.")]


def test_sentences_holding_the_chapter_gps_come_before_the_others(pack_folder):
    execute(pack_folder, "INSERT INTO Sentences (ID, Sentence) VALUES (3, 'La la.')")
    for position in range(2):
        execute(pack_folder, "INSERT INTO WordsInSentences (SentenceID, WordID, Position) VALUES (3, 1, ?)", position)
    add_chapter(pack_folder, 3, [3], SyllableCount=0, WordCount=0)  # teaches "u": "La la." has none
    chapter = own(content.booklet(load(pack_folder), 1).chapters)[0]
    assert [sentence_id for sentence_id, _ in chapter.sentence_pool] == [1, 2, 3]


def test_a_chapter_its_lesson_reads_no_sentence_of_says_so(pack_folder):
    add_chapter(pack_folder, 2, [2], Title="L l")  # "La lune." is only readable at lesson 3
    booklet = content.booklet(load(pack_folder), 1)
    assert own(booklet.chapters)[0].sentence_pool == []
    assert "Lesson 2, chapter 1: no sentence is readable at this lesson" in booklet.notes
