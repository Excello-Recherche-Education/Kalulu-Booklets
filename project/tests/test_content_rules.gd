extends GutTest
## What a chapter prints (BookletContent), on the tiny pack of
## helpers/tiny_pack.gd. Ported from the Python generator's tests/test_content.py.

const Tiny := preload("res://tests/helpers/tiny_pack.gd")

var pack_folder := ""


func before_each() -> void:
	pack_folder = Tiny.make()
	if pack_folder.is_empty():
		pending("kalulu-languages/ is not checked out (git submodule update --init)")


func after_all() -> void:
	Tiny.forget_all()


## Lesson 3's chapter, made with ``columns``: [booklet, its content or null].
func _chapter_content(columns: Dictionary = {}) -> Array:
	Tiny.add_chapter(pack_folder, 3, [3, 4, 5], columns)
	var booklet := BookletContent.booklet(Tiny.read(pack_folder), 1)
	var chapters := Tiny.own(booklet.chapters)
	return [booklet, chapters[0] if not chapters.is_empty() else null]


func _first(folder: String) -> BookletContent.ChapterContent:
	return Tiny.own(BookletContent.booklet(Tiny.read(folder), 1).chapters)[0]


static func _texts(items: Array) -> Array:
	return items.map(func(item: BookletContent.Styled) -> String: return item.text)


static func _sorted(positions: Dictionary) -> Array:
	var keys := positions.keys()
	keys.sort()
	return keys


func _add_entries(chapter_id: int, part: int, entries: Array) -> void:
	for position in entries.size():
		Tiny.execute(pack_folder, "INSERT INTO BookletEntries (ChapterID, Part, Position, Text) VALUES (?, ?, ?, ?)",
				[chapter_id, part, position, entries[position]])


func _add_sentences(chapter_id: int, breaks: Array) -> void:
	for position in breaks.size():
		Tiny.execute(pack_folder,
				"INSERT INTO BookletSentences (ChapterID, SentenceID, Position, Break) VALUES (?, ?, ?, ?)",
				[chapter_id, 1 + position % 2, position, breaks[position]])


## Capitals print in the script series only.
func _capitals(share: float, words: Array = [], syllables: Array = [], sentences: Array = []) -> void:
	Tiny.execute(pack_folder,
			"UPDATE BookletSettings SET UppercaseProportion = ?, ScriptSeries = 1, CursiveSeries = 0", [share])
	for pair: Array in [["Words", words], ["Syllables", syllables], ["Sentences", sentences]]:
		for item_id: int in pair[1]:
			Tiny.execute(pack_folder, "UPDATE %s SET Uppercase = 1 WHERE ID = ?" % pair[0], [item_id])


func _lines_of(chapter: BookletContent.ChapterContent) -> Array:
	return chapter.paragraphs.map(func(paragraph: BookletContent.Paragraph) -> Array:
		return paragraph.lines.map(func(line: Array) -> Array: return _texts(line)))


func test_automatic_words_hold_a_chapter_gp_and_are_readable() -> void:
	if pack_folder.is_empty():
		return
	var chapter: BookletContent.ChapterContent = _chapter_content({"WordCount": 4})[1]
	# "la" holds no GP of the chapter, "lunule" is an exception, "l" has no
	# vowel. Booklet-only first ("Luna"), then in the pack's order.
	assert_eq(_texts(chapter.words), ["Luna", "lune", "une", "nu"])


func test_words_short_of_the_count_are_repeated_and_said() -> void:
	if pack_folder.is_empty():
		return
	var made := _chapter_content({"WordCount": 6, "WordColumns": 3})
	var words := _texts(made[1].words)
	# Once in order, then repeated in a shuffled round: none under itself.
	assert_eq(words.slice(0, 4), ["Luna", "lune", "une", "nu"])
	var rest := {}
	for word: String in words.slice(4):
		rest[word] = true
	assert_eq(rest.size(), 2)
	for index in range(3, 6):
		assert_ne(words[index], words[index - 3])
	assert_has(made[0].notes, "Lesson 3, chapter 1: WordCount is 6, and only 4 words qualify: they are repeated")


func test_a_grid_fills_every_row_it_starts() -> void:
	if pack_folder.is_empty():
		return
	var made := _chapter_content({"WordCount": 7, "WordColumns": 3, "SyllableCount": 8, "SyllableColumns": 6})
	# 7 words in 3 columns would leave one alone on the last row.
	assert_eq(made[1].words.size(), 6)
	assert_eq(made[1].syllables.size(), 6)
	assert_has(made[0].notes, "Lesson 3, chapter 1: WordCount is 7 in 3 columns: 6 are printed, so that every row is full")


func test_a_count_below_one_row_is_kept() -> void:
	if pack_folder.is_empty():
		return
	var made := _chapter_content({"WordCount": 2, "WordColumns": 4})
	assert_eq(made[1].words.size(), 2)
	assert_false(made[0].notes.any(func(note: String) -> bool: return note.contains("every row is full")))


func test_syllables_repeat_until_the_count() -> void:
	if pack_folder.is_empty():
		return
	assert_eq(_texts(_chapter_content({"SyllableCount": 5})[1].syllables), ["nu", "lu", "un", "nu", "lu"])


func test_picks_past_the_count_lose_the_last_ones() -> void:
	if pack_folder.is_empty():
		return
	var chapter_id := Tiny.add_chapter(pack_folder, 3, [3], {"WordCount": 1})
	_add_entries(chapter_id, 2, ["la Lune", "une lune"])
	var booklet := BookletContent.booklet(Tiny.read(pack_folder), 1)
	assert_eq(_texts(Tiny.own(booklet.chapters)[0].words), ["la Lune"])
	assert_has(booklet.notes, "Lesson 3, chapter 1: 2 words picked and 1 printed: the last 1 are left out")


func test_picks_short_of_the_count_are_filled_from_the_pack() -> void:
	if pack_folder.is_empty():
		return
	var chapter_id := Tiny.add_chapter(pack_folder, 3, [3], {"WordCount": 3, "SyllableCount": 3})
	_add_entries(chapter_id, 2, ["la Lune"])
	_add_entries(chapter_id, 1, ["un"])
	var chapter := _first(pack_folder)
	# "lune" is already printed, as "la Lune": the fill skips it.
	assert_eq(_texts(chapter.words), ["la Lune", "Luna", "une"])
	assert_eq(_texts(chapter.syllables), ["un", "nu", "lu"])


func test_silent_letters_come_from_the_decomposition() -> void:
	if pack_folder.is_empty():
		return
	var chapter: BookletContent.ChapterContent = _chapter_content({"GreySilent": 1})[1]
	var lune: BookletContent.Styled = chapter.words[_texts(chapter.words).find("lune")]
	assert_eq(_sorted(lune.grey), [3])


func test_no_grey_unless_the_chapter_asks() -> void:
	if pack_folder.is_empty():
		return
	var chapter: BookletContent.ChapterContent = _chapter_content()[1]
	assert_true(chapter.words.all(func(item: BookletContent.Styled) -> bool: return item.grey.is_empty()))


func test_a_listed_entry_is_matched_word_by_word_case_ignored() -> void:
	if pack_folder.is_empty():
		return
	assert_eq(_sorted(BookletContent.styled(Tiny.read(pack_folder), "la Lune", true).grey), [6])


func test_a_word_in_no_list_is_printed_without_grey() -> void:
	if pack_folder.is_empty():
		return
	assert_true(BookletContent.styled(Tiny.read(pack_folder), "Léo", true).grey.is_empty())


func test_a_hyphenated_word_is_its_own_or_its_parts() -> void:
	if pack_folder.is_empty():
		return
	Tiny.execute(pack_folder, "INSERT INTO Words (ID, Word, BookletOnly) VALUES (8, 'la-lune', 1)")
	var gps := [2, 1, 2, 3, 4, 5]
	for position in gps.size():
		Tiny.execute(pack_folder, "INSERT INTO GPsInWords (WordID, GPID, Position) VALUES (8, ?, ?)",
				[gps[position], position])
	var pack := Tiny.read(pack_folder)
	# The word's GPs spell it once its hyphen is skipped: its silent e is grey.
	assert_eq(_sorted(BookletContent.styled(pack, "La-lune", true).grey), [6])
	# "une-lune" is no word, so it is "une" and "lune", each with its silent e.
	assert_eq(_sorted(BookletContent.styled(pack, "une-lune", true).grey), [2, 7])


func test_flagged_entries_print_in_capitals() -> void:
	if pack_folder.is_empty():
		return
	# "lune" (word 2), "nu" (syllable 2) and "Une lune nue." (sentence 2).
	_capitals(1.0 / 3.0, [2], [2], [2])
	var chapter: BookletContent.ChapterContent = _chapter_content(
			{"WordCount": 4, "SyllableCount": 3, "SentencePages": 0})[1]
	assert_eq(_texts(chapter.words), ["Luna", "LUNE", "une", "nu"])
	assert_eq(_texts(chapter.syllables), ["NU", "lu", "un"])
	var pool := {}
	for pair: Array in chapter.sentence_pool:
		pool[pair[0]] = pair[1].text
	assert_eq(pool[2], "UNE LUNE NUE.")
	assert_eq(pool[1], "La lune.")


func test_flags_are_ignored_while_the_share_is_zero() -> void:
	if pack_folder.is_empty():
		return
	_capitals(0.0, [2], [2], [2])
	var chapter: BookletContent.ChapterContent = _chapter_content({"WordCount": 4, "SyllableCount": 3})[1]
	assert_false((_texts(chapter.words) + _texts(chapter.syllables)).any(func(text: String) -> bool:
		return text == text.to_upper() and text != text.to_lower()))


func test_a_pick_prints_in_capitals_when_all_its_words_are_flagged() -> void:
	if pack_folder.is_empty():
		return
	_capitals(0.5, [1, 2, 4])
	var chapter_id := Tiny.add_chapter(pack_folder, 3, [3], {"WordCount": 3})
	_add_entries(chapter_id, 2, ["la Lune", "une lune", "lune nue"])
	# "nu" is not flagged.
	assert_eq(_texts(_first(pack_folder).words), ["LA LUNE", "UNE LUNE", "lune nue"])


func test_a_chapters_sentences_print_in_capitals_by_their_flag() -> void:
	if pack_folder.is_empty():
		return
	_capitals(1.0 / 3.0, [], [], [1])
	var chapter_id := Tiny.add_chapter(pack_folder, 3, [3])
	_add_sentences(chapter_id, [2, 0])
	assert_eq(_lines_of(_first(pack_folder)), [[["LA LUNE.", "Une lune nue."]]])


func test_breaks_make_lines_and_paragraphs() -> void:
	if pack_folder.is_empty():
		return
	var chapter_id := Tiny.add_chapter(pack_folder, 3, [3])
	_add_sentences(chapter_id, [2, 0, 1, 2])
	var chapter := _first(pack_folder)
	assert_eq(_lines_of(chapter), [[["La lune.", "Une lune nue."], ["La lune."]], [["Une lune nue."]]])
	assert_eq(chapter.paragraphs.map(func(paragraph: BookletContent.Paragraph) -> String: return paragraph.font),
			[BookletContent.CURSIVE, BookletContent.SCRIPT])


func test_the_script_series_prints_sentences_in_script() -> void:
	if pack_folder.is_empty():
		return
	Tiny.execute(pack_folder, "UPDATE BookletSettings SET ScriptSeries = 1, CursiveSeries = 0")
	var chapter_id := Tiny.add_chapter(pack_folder, 3, [3], {"SentenceFont": 2})
	_add_sentences(chapter_id, [2, 2])
	var chapter := _first(pack_folder)
	assert_eq(chapter.paragraphs.map(func(paragraph: BookletContent.Paragraph) -> String: return paragraph.font),
			[BookletContent.SCRIPT, BookletContent.SCRIPT])
	assert_eq(chapter.writing_font, BookletContent.SCRIPT)


func test_a_sentence_keeps_its_own_words_for_grey() -> void:
	if pack_folder.is_empty():
		return
	var chapter_id := Tiny.add_chapter(pack_folder, 3, [3], {"GreySilent": 1})
	_add_sentences(chapter_id, [2, 0])
	var line: Array = _first(pack_folder).paragraphs[0].lines[0]
	assert_eq(_sorted(line[0].grey), [6], "La lun|e|.")
	assert_eq(_sorted(line[1].grey), [2, 7], "Un|e| lun|e| nue. -- \"nue\" is in no list")


func test_a_chapter_that_prints_nothing_is_left_out_and_said() -> void:
	if pack_folder.is_empty():
		return
	var made := _chapter_content({"SyllableCount": 0, "WordCount": 0, "SentencePages": -1})
	assert_null(made[1])
	# Lessons 1 and 2 have their forced chapters made, which print.
	assert_eq(made[0].notes.filter(func(note: String) -> bool: return note.begins_with("Lesson 3")),
			["Lesson 3, chapter 1: prints nothing, so it has no page"])


func test_a_sentence_read_only_later_is_said() -> void:
	if pack_folder.is_empty():
		return
	var chapter_id := Tiny.add_chapter(pack_folder, 2, [2])
	_add_sentences(chapter_id, [2])
	assert_has(BookletContent.booklet(Tiny.read(pack_folder), 1).notes,
			"Lesson 2, chapter 1: sentence \"La lune.\" is readable from lesson 3")


func test_sentence_pages_minus_one_prints_no_sentence() -> void:
	if pack_folder.is_empty():
		return
	var chapter_id := Tiny.add_chapter(pack_folder, 3, [3], {"SentencePages": -1})
	_add_sentences(chapter_id, [2, 2])
	var booklet := BookletContent.booklet(Tiny.read(pack_folder), 1)
	assert_true(Tiny.own(booklet.chapters)[0].paragraphs.is_empty())
	assert_has(booklet.notes, "Lesson 3, chapter 1: SentencePages is -1, so its 2 sentence(s) are not printed")


func test_a_chapter_picking_no_sentence_chooses_from_the_pack() -> void:
	if pack_folder.is_empty():
		return
	Tiny.execute(pack_folder, "INSERT INTO Sentences (ID, Sentence, BookletOnly) VALUES (3, 'Une lune.', 1)")
	for position in 2:
		Tiny.execute(pack_folder, "INSERT INTO WordsInSentences (SentenceID, WordID, Position) VALUES (3, ?, ?)",
				[[4, 2][position], position])
	var chapter: BookletContent.ChapterContent = _chapter_content()[1]
	assert_true(chapter.paragraphs.is_empty())
	# Booklet-only first, then the pack's order.
	assert_eq(chapter.sentence_pool.map(func(pair: Array) -> Array: return [pair[0], pair[1].text]),
			[[3, "Une lune."], [1, "La lune."], [2, "Une lune nue."]])


func test_sentences_holding_the_chapter_gps_come_before_the_others() -> void:
	if pack_folder.is_empty():
		return
	Tiny.execute(pack_folder, "INSERT INTO Sentences (ID, Sentence) VALUES (3, 'La la.')")
	for position in 2:
		Tiny.execute(pack_folder, "INSERT INTO WordsInSentences (SentenceID, WordID, Position) VALUES (3, 1, ?)",
				[position])
	# Teaches "u": "La la." has none.
	Tiny.add_chapter(pack_folder, 3, [3], {"SyllableCount": 0, "WordCount": 0})
	assert_eq(_first(pack_folder).sentence_pool.map(func(pair: Array) -> int: return pair[0]), [1, 2, 3])


func test_a_chapter_its_lesson_reads_no_sentence_of_says_so() -> void:
	if pack_folder.is_empty():
		return
	# "La lune." is only readable at lesson 3.
	Tiny.add_chapter(pack_folder, 2, [2], {"Title": "L l"})
	var booklet := BookletContent.booklet(Tiny.read(pack_folder), 1)
	assert_true(Tiny.own(booklet.chapters)[0].sentence_pool.is_empty())
	assert_has(booklet.notes, "Lesson 2, chapter 1: no sentence is readable at this lesson")


func test_a_language_with_both_series_prints_capitals_in_the_script_one_only() -> void:
	if pack_folder.is_empty():
		return
	_capitals(1.0 / 3.0, [2])
	Tiny.execute(pack_folder, "UPDATE BookletSettings SET CursiveSeries = 1")
	var chapter_id := Tiny.add_chapter(pack_folder, 3, [3, 4, 5], {"WordCount": 4, "SentenceFont": 2})
	_add_sentences(chapter_id, [2])
	var pack := Tiny.read(pack_folder)
	assert_eq(Array(pack.series()), ["script", "cursive"])
	var script: BookletContent.ChapterContent = Tiny.own(BookletContent.booklet(pack, 1, "script").chapters)[0]
	var cursive: BookletContent.ChapterContent = Tiny.own(BookletContent.booklet(pack, 1, "cursive").chapters)[0]
	assert_has(_texts(script.words), "LUNE")
	assert_does_not_have(_texts(cursive.words), "LUNE")
	assert_eq(script.paragraphs.map(func(paragraph: BookletContent.Paragraph) -> String: return paragraph.font),
			[BookletContent.SCRIPT])
	assert_eq(cursive.paragraphs.map(func(paragraph: BookletContent.Paragraph) -> String: return paragraph.font),
			[BookletContent.CURSIVE])
	assert_eq([script.writing_font, cursive.writing_font], [BookletContent.SCRIPT, BookletContent.CURSIVE])
