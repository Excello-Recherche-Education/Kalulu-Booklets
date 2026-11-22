extends GutTest
## The adapted versions (AdaptedLayout): dyslexia, dyspraxia and adhd. Ported
## from the Python generator's tests/test_adapted.py.

const Tiny := preload("res://tests/helpers/tiny_pack.gd")
const ADAPTED := ["dyslexia", "dyspraxia", "adhd"]


## An adapted layout that keeps every block line it draws, with its baseline.
class Watched:
	extends AdaptedLayout
	var drawn: Array = []

	func draw_block_line(surface: DrawingSurface, line: AdaptedLayout.Line, line_baseline: float,
			left: float = TEXT_LEFT, width: float = TEXT_WIDTH) -> void:
		drawn.append([line, line_baseline])
		super(surface, line, line_baseline, left, width)


var pack_folder := ""
var fonts: FontSet


func before_each() -> void:
	fonts = Tiny.fonts()
	pack_folder = Tiny.make() if fonts != null else ""
	if pack_folder.is_empty():
		pending("kalulu-languages/ has no schema or fonts/ at its pinned commit")


func after_all() -> void:
	Tiny.forget_all()


func _layout(version: String, folder: String = "") -> AdaptedLayout:
	var booklet := BookletContent.booklet(Tiny.read(folder if not folder.is_empty() else pack_folder), 1)
	return AdaptedLayout.new(booklet, fonts, BookletVersion.named(version))


## "ch" taught at lesson 2, "ou" at lesson 4; "chou" spells both.
func _two_letter_gps() -> void:
	Tiny.execute(pack_folder, "INSERT INTO GPs (ID, Grapheme, Phoneme, Type) VALUES (6, 'ch', 'S', 2)")
	Tiny.execute(pack_folder, "INSERT INTO GPs (ID, Grapheme, Phoneme, Type) VALUES (7, 'ou', 'u', 1)")
	Tiny.execute(pack_folder, "INSERT INTO GPsInLessons (GPID, LessonID) VALUES (6, 2)")
	Tiny.execute(pack_folder, "INSERT INTO Lessons (ID, LessonNb) VALUES (4, 4)")
	Tiny.execute(pack_folder, "INSERT INTO GPsInLessons (GPID, LessonID) VALUES (7, 4)")
	Tiny.execute(pack_folder, "INSERT INTO Words (ID, Word, Exception, BookletOnly) VALUES (8, 'chou', 0, 0)")
	for position in 2:
		Tiny.execute(pack_folder, "INSERT INTO GPsInWords (WordID, GPID, Position) VALUES (8, ?, ?)",
				[[6, 7][position], position])


static func _lesson(pack: BookletPack, number: int) -> BookletPack.Chapter:
	return pack.chapters.filter(func(chapter: BookletPack.Chapter) -> bool: return chapter.lesson == number)[0]


func test_a_chapter_colours_its_own_graphemes_and_earlier_ones() -> void:
	if pack_folder.is_empty():
		return
	_two_letter_gps()
	var pack := Tiny.read(pack_folder)
	# At lesson 4, "ch" is earlier and "ou" its own: they touch, and the
	# lesson's own keeps its colour, so "ch" changes.
	assert_eq(BookletContent.styled(pack, "chou", false, [], false, _lesson(pack, 4)).tints,
			[[0, 2, BookletContent.TOUCHING], [2, 4, BookletContent.OWN]])
	# Single letters are never coloured, nor a grapheme not taught yet.
	assert_eq(BookletContent.styled(pack, "la lune", false, [], false, _lesson(pack, 4)).tints, [])
	assert_eq(BookletContent.styled(pack, "chou", false, [], false, _lesson(pack, 2)).tints,
			[[0, 2, BookletContent.OWN]])


func test_of_two_earlier_graphemes_that_touch_the_second_changes() -> void:
	if pack_folder.is_empty():
		return
	_two_letter_gps()
	Tiny.execute(pack_folder, "INSERT INTO Lessons (ID, LessonNb) VALUES (5, 5)")
	Tiny.execute(pack_folder, "INSERT INTO GPs (ID, Grapheme, Phoneme, Type) VALUES (9, 'an', 'an', 1)")
	Tiny.execute(pack_folder, "INSERT INTO GPsInLessons (GPID, LessonID) VALUES (9, 5)")
	var pack := Tiny.read(pack_folder)
	assert_eq(BookletContent.styled(pack, "chou", false, [], false, _lesson(pack, 5)).tints,
			[[0, 2, BookletContent.EARLIER], [2, 4, BookletContent.TOUCHING]])


func test_a_grapheme_of_the_chapter_lesson_is_its_own_even_when_the_chapter_does_not_list_it() -> void:
	if pack_folder.is_empty():
		return
	_two_letter_gps()
	Tiny.add_chapter(pack_folder, 4, [], {"Title": "où"})
	var pack := Tiny.read(pack_folder)
	assert_false(_lesson(pack, 4).gp_ids.has(7))
	assert_eq(BookletContent.styled(pack, "chou", false, [], false, _lesson(pack, 4)).tints,
			[[0, 2, BookletContent.TOUCHING], [2, 4, BookletContent.OWN]])


func test_a_story_title_heads_its_page_and_wraps() -> void:
	if pack_folder.is_empty():
		return
	var title := "Comment le lapin Kalulu a appris à lire tout seul"
	var chapter := Tiny.add_chapter(pack_folder, 2, [2], {"Title": "L l"})
	Tiny.execute(pack_folder, "INSERT INTO BookletStories (ChapterID, Position, Title, Text) VALUES (?, 0, ?, ?)",
			[chapter, title, "La lune.\n\nUne lune nue."])
	var laid_out := Watched.new(BookletContent.booklet(Tiny.read(pack_folder), 1), fonts,
			BookletVersion.named("adhd"))
	var surface := RecordingSurface.new(BookletWriter.A5)
	for page in laid_out.run():
		for step in page.steps:
			step.call(surface)
	var words_of := func(line: AdaptedLayout.Line) -> String:
		return " ".join(line.words.map(func(word: BookletContent.Styled) -> String: return word.text))
	var title_lines := laid_out.drawn.filter(func(pair: Array) -> bool: return pair[0].face == fonts.script_bold)
	assert_eq(" ".join(title_lines.map(func(pair: Array) -> String: return words_of.call(pair[0]))), title)
	assert_gt(title_lines.size(), 1)
	var story := laid_out.drawn.filter(func(pair: Array) -> bool:
		return pair[0].face == fonts.script_regular and pair[0].words[0].text in ["La", "Une"])
	assert_gt(title_lines.map(func(pair: Array) -> float: return pair[1]).min(),
			story.map(func(pair: Array) -> float: return pair[1]).max())
	for pair: Array in title_lines:
		var line: AdaptedLayout.Line = pair[0]
		var width := 0.0
		for word: BookletContent.Styled in line.words:
			width += laid_out.spaced_width(line.face, word.text, line.size)
		assert_lte(width, AdaptedLayout.TEXT_WIDTH)


func test_a_fluency_item_wider_than_its_column_is_said() -> void:
	if pack_folder.is_empty():
		return
	var laid_out := _layout("adhd")
	var items: Array[BookletContent.Styled] = [BookletContent.Styled.new("lalalalalalalala"),
			BookletContent.Styled.new("la")]
	laid_out.fluency(laid_out.booklet.chapters[0], items)
	assert_true(laid_out.booklet.notes.any(func(note: String) -> bool:
		return note.contains("lalalalalalalala") and note.contains("wider than its cell")))


func test_the_fluency_test_keeps_every_item_on_pages_of_3_by_4() -> void:
	if pack_folder.is_empty():
		return
	for version: String in ADAPTED:
		var laid_out := _layout(version)
		var items: Array[BookletContent.Styled] = []
		for index in 50:
			items.append(BookletContent.Styled.new(str(index)))
		var before := laid_out.pages.size()
		laid_out.fluency(null, items)
		# 50 items, 12 a page: 5 pages, the last holding 2.
		assert_eq(laid_out.pages.size() - before, 5, version)


func test_an_adapted_version_prints_the_sentences_the_base_chose() -> void:
	if pack_folder.is_empty():
		return
	Tiny.add_chapter(pack_folder, 3, [3, 4], {"Title": "u n"})
	var base := BookletLayout.new(BookletContent.booklet(Tiny.read(pack_folder), 1), fonts)
	base.run()
	var adapted := _layout("adhd")
	assert_eq(adapted.chosen, base.chosen)
	assert_true(adapted.chosen.values().any(func(chosen: Array) -> bool: return not chosen.is_empty()))


func test_the_base_notes_are_not_said_again() -> void:
	if pack_folder.is_empty():
		return
	var booklet := BookletContent.booklet(Tiny.read(pack_folder), 1)
	var before := booklet.notes.duplicate()
	AdaptedLayout.new(booklet, fonts, BookletVersion.named("dyslexia"))
	assert_eq(booklet.notes, before)


func test_an_adapted_booklet_closes_on_folded_sheets() -> void:
	if pack_folder.is_empty():
		return
	Tiny.add_chapter(pack_folder, 2, [2], {"Title": "L l"})
	for version: String in ADAPTED:
		assert_eq(_layout(version).run().size() % 4, 0, version)


func test_a_language_with_no_adaptations_text_has_no_such_page_and_says_so() -> void:
	if pack_folder.is_empty():
		return
	var laid_out := _layout("dyslexia")
	laid_out.run()
	assert_true(laid_out.booklet.notes.any(func(note: String) -> bool: return note.contains("no adaptations page")))


func test_french_has_the_adaptations_page() -> void:
	if pack_folder.is_empty():
		return
	var french := pack_folder.get_base_dir().path_join("fr_FR")
	DirAccess.rename_absolute(pack_folder, french)
	var booklet := BookletContent.booklet(Tiny.read(french), 1)
	var pages := AdaptedLayout.new(booklet, fonts, BookletVersion.named("dyspraxia")).run()
	assert_false(booklet.notes.any(func(note: String) -> bool: return note.contains("no adaptations page")))
	# The adaptations page, then the back cover; neither is numbered.
	assert_false(pages[-2].numbered)
	assert_false(pages[-2].steps.is_empty())


## The characters a layout draws, by name.
static func _pictures_drawn(laid_out: BookletLayout) -> Array:
	var surface := RecordingSurface.new(BookletWriter.A5)
	for page in laid_out.run():
		for step in page.steps:
			step.call(surface)
	var names: Array = []
	for page: Array in surface.pages:
		for operation: Dictionary in page:
			if operation["op"] == "image" and operation["key"].begins_with("art/"):
				names.append(operation["key"].get_file().get_basename())
	return names


func _writing_and_table() -> void:
	var chapter := Tiny.add_chapter(pack_folder, 2, [2],
			{"Title": "L l", "SyllableCount": 0, "WordCount": 0, "SentencePages": -1})
	Tiny.execute(pack_folder, "INSERT INTO BookletEntries (ChapterID, Part, Position, Text, Text2, Header) "
			+ "VALUES (?, 3, 0, 'la', '', 0)", [chapter])
	var rows := [["a", "b", 1], ["la", "le", 0]]
	for position in rows.size():
		Tiny.execute(pack_folder, "INSERT INTO BookletEntries (ChapterID, Part, Position, Text, Text2, Header) "
				+ "VALUES (?, 4, ?, ?, ?, ?)", [chapter, position, rows[position][0], rows[position][1],
				rows[position][2]])


func test_dyspraxia_keeps_the_writing_pages() -> void:
	if pack_folder.is_empty():
		return
	_writing_and_table()
	var used := func(version: String) -> int:
		return _layout(version).run().filter(func(page: BookletLayout.Page) -> bool:
			return not page.steps.is_empty()).size()
	assert_eq(used.call("dyspraxia"), used.call("adhd"))


func test_adhd_draws_no_animal() -> void:
	if pack_folder.is_empty():
		return
	_writing_and_table()
	var dyspraxia := {}
	for name: String in _pictures_drawn(_layout("dyspraxia")):
		dyspraxia[name] = true
	var names := dyspraxia.keys()
	names.sort()
	assert_eq(names, ["caterpillar", "penguin"])
	assert_eq(_pictures_drawn(_layout("adhd")), [])
