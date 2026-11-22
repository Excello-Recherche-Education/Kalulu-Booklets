extends GutTest
## The whole way, from a pack to its PDF files (BookletBuild, the command
## line's build). Ported from the Python generator's tests/test_build.py.

const Tiny := preload("res://tests/helpers/tiny_pack.gd")
const Command := preload("res://cli/build_command.gd")

var pack_folder := ""
var fonts: FontSet


func before_each() -> void:
	fonts = Tiny.fonts()
	pack_folder = Tiny.make() if fonts != null else ""
	if pack_folder.is_empty():
		pending("kalulu-languages/ has no schema or fonts/ at its pinned commit")


func after_all() -> void:
	Tiny.forget_all()


func _build(numbers: Array[int] = []) -> Dictionary:
	var said: Array[String] = []
	var errors: Array[String] = []
	var out := pack_folder.get_base_dir().path_join("out")
	var code := BookletBuild.new(func(line: String) -> void: said.append(line),
			func(line: String) -> void: errors.append(line)).build(pack_folder, numbers, [], out)
	return {"code": code, "out": out, "said": "\n".join(said), "errors": "\n".join(errors)}


static func _page_count(path: String) -> int:
	return FileAccess.get_file_as_bytes(path).get_string_from_ascii().count("/Type /Page ")


func test_builds_one_pdf_per_booklet() -> void:
	if pack_folder.is_empty():
		return
	var first := Tiny.add_chapter(pack_folder, 2, [2], {"Title": "L l"})
	Tiny.add_chapter(pack_folder, 3, [3, 4, 5], {"Booklet": 2, "Title": "u n", "GreySilent": 1})
	for entry: Array in [[3, "lune", "", 0], [4, "la", "une", 1], [5, "lune", "", 0]]:
		Tiny.execute(pack_folder, "INSERT INTO BookletEntries (ChapterID, Part, Position, Text, Text2, Header) "
				+ "VALUES (?, ?, 0, ?, ?, ?)", [first, entry[0], entry[1], entry[2], entry[3]])
	Tiny.execute(pack_folder,
			"INSERT INTO BookletStories (ChapterID, Position, Title, Text) VALUES (?, 0, 'Luna', ?)",
			[first, "La lune.\n\nUne lune nue."])
	var built := _build()
	assert_eq(built["code"], 0)
	for number in [1, 2]:
		var path: String = built["out"].path_join("xx_XX/base/xx_XX-booklet-%d.pdf" % number)
		assert_eq(FileAccess.get_file_as_bytes(path).slice(0, 4).get_string_from_ascii(), "%PDF")
		assert_eq(_page_count(path) % 4, 0, "printed on folded sheets")
	assert_string_contains(built["said"], "xx_XX-booklet-1.pdf")


func test_a_pack_in_memory_builds_what_its_folder_builds() -> void:
	if pack_folder.is_empty():
		return
	Tiny.add_chapter(pack_folder, 2, [2], {"Title": "L l"})
	var from_folder := _build()
	var pack := BookletPackReader.new().read(pack_folder)
	var out := pack_folder.get_base_dir().path_join("memory")
	var said: Array[String] = []
	var code := BookletBuild.new(func(line: String) -> void: said.append(line)).build_pack(pack, [], [], out)
	assert_eq(code, 0)
	var file := "xx_XX/base/xx_XX-booklet-1.pdf"
	assert_eq(FileAccess.get_file_as_bytes(out.path_join(file)),
			FileAccess.get_file_as_bytes(from_folder["out"].path_join(file)))
	assert_eq("\n".join(said).replace(out, "OUT"), from_folder["said"].replace(from_folder["out"], "OUT"))
	# What the pack holds in memory is what is printed: the Prof Tool's unsaved edits.
	pack.chapters.filter(func(chapter: BookletPack.Chapter) -> bool: return chapter.lesson == 2)[0].title = "Lu"
	BookletBuild.new(func(_line: String) -> void: pass).build_pack(pack, [], [], out)
	assert_ne(FileAccess.get_file_as_bytes(out.path_join(file)),
			FileAccess.get_file_as_bytes(from_folder["out"].path_join(file)))


func test_a_pack_without_chapters_prints_one_per_lesson() -> void:
	if pack_folder.is_empty():
		return
	var built := _build()
	assert_eq(built["code"], 0)
	assert_string_contains(built["said"], "has no booklet chapter: one per lesson")
	assert_string_contains(built["said"], ", 3 chapter(s))")
	assert_true(FileAccess.file_exists(built["out"].path_join("xx_XX/base/xx_XX-booklet-1.pdf")))


func test_refuses_a_booklet_the_pack_does_not_have() -> void:
	if pack_folder.is_empty():
		return
	Tiny.add_chapter(pack_folder, 2, [2], {"Title": "L l"})
	var built := _build([3] as Array[int])
	assert_eq(built["code"], 2)
	assert_string_contains(built["errors"], "has no booklet 3")


func test_sentences_beyond_their_pages_are_said() -> void:
	if pack_folder.is_empty():
		return
	for case: Array in [[0, "the page they start on"], [1, "that page and 1 more"]]:
		pack_folder = Tiny.make()
		var chapter := Tiny.add_chapter(pack_folder, 3, [3],
				{"SentencePages": case[0], "SyllableCount": 0, "WordCount": 0})
		for position in 90:
			Tiny.execute(pack_folder, "INSERT INTO BookletSentences (ChapterID, SentenceID, Position, Break) "
					+ "VALUES (?, 1, ?, 1)", [chapter, position])
		var built := _build()
		assert_eq(built["code"], 0)
		assert_string_contains(built["said"], "do not fit on %s (SentencePages is %d)" % [case[1], case[0]])


func test_chosen_sentences_are_whole_and_one_that_overflows_is_passed_over() -> void:
	if pack_folder.is_empty():
		return
	var long_one := PythonUnicode.strip("Une lune nue. ".repeat(12))
	Tiny.execute(pack_folder, "INSERT INTO Sentences (ID, Sentence) VALUES (3, ?)", [long_one])
	for position in 24:
		Tiny.execute(pack_folder, "INSERT INTO WordsInSentences (SentenceID, WordID, Position) VALUES (3, ?, ?)",
				[[4, 2][position % 2], position])
	Tiny.add_chapter(pack_folder, 3, [3], {"SentencePages": 0})
	var booklet := BookletContent.booklet(Tiny.read(pack_folder), 1)
	var chapter: BookletContent.ChapterContent = Tiny.own(booklet.chapters)[0]
	# The long one first.
	chapter.sentence_pool = StableSort.sorted(chapter.sentence_pool, func(candidate: Array) -> bool:
		return candidate[0] != 3)
	var pages := BookletLayout.new(booklet, fonts)
	pages.new_page()
	# Room for three lines.
	pages.y = BookletLayout.BOTTOM + 3 * BookletLayout.SENTENCE_SIZE * BookletLayout.CURSIVE_LEADING
	pages.chosen_sentences(chapter)
	# The long one does not fit, the two short ones do.
	var printed := pages.printed_sentences.keys()
	printed.sort()
	assert_eq(printed, [1, 2])
	assert_eq(pages.pages.size(), 1)


func _built_notes() -> Array[String]:
	var booklet := BookletContent.booklet(Tiny.read(pack_folder), 1)
	BookletLayout.new(booklet, fonts).run()
	return booklet.notes


func test_sentences_from_earlier_lessons_filling_a_chapter_are_said() -> void:
	if pack_folder.is_empty():
		return
	# "La la." holds no "u": it is lesson 2's, printed only to fill the page.
	Tiny.execute(pack_folder, "INSERT INTO Sentences (ID, Sentence) VALUES (3, 'La la.')")
	for position in 2:
		Tiny.execute(pack_folder, "INSERT INTO WordsInSentences (SentenceID, WordID, Position) VALUES (3, 1, ?)",
				[position])
	Tiny.add_chapter(pack_folder, 3, [3], {"SyllableCount": 0, "WordCount": 0, "SentencePages": 0})
	assert_has(_built_notes(), "Lesson 3, chapter 1: not enough content of its own: 1 of its 3 sentences holds "
			+ "none of its GPs, taken from earlier lessons to fill its pages (only 2 readable sentences hold one)")


func test_a_chapter_filled_with_its_own_sentences_says_nothing() -> void:
	if pack_folder.is_empty():
		return
	Tiny.add_chapter(pack_folder, 3, [3], {"SyllableCount": 0, "WordCount": 0, "SentencePages": 0})
	assert_false(_built_notes().any(func(note: String) -> bool: return note.contains("not enough content")))


func test_a_paragraph_is_never_cut_across_two_pages() -> void:
	if pack_folder.is_empty():
		return
	var chapter_id := Tiny.add_chapter(pack_folder, 3, [3], {"SyllableCount": 0, "WordCount": 0, "SentencePages": 1})
	# Two paragraphs, each sentence on its own line: the second has three.
	var breaks := [2, 2, 1, 1]
	for position in breaks.size():
		Tiny.execute(pack_folder, "INSERT INTO BookletSentences (ChapterID, SentenceID, Position, Break) "
				+ "VALUES (?, 2, ?, ?)", [chapter_id, position, breaks[position]])
	var booklet := BookletContent.booklet(Tiny.read(pack_folder), 1)
	var chapter: BookletContent.ChapterContent = Tiny.own(booklet.chapters)[0]
	var pages := BookletLayout.new(booklet, fonts)
	pages.new_page()
	# Room for the first paragraph and two lines of the second, whatever its font.
	pages.y = BookletLayout.BOTTOM + 3.5 * BookletLayout.SENTENCE_SIZE * BookletLayout.CURSIVE_LEADING
	pages.sentences(chapter)
	assert_eq(pages.pages.size(), 2)
	assert_eq([pages.pages[0].steps.size(), pages.pages[1].steps.size()], [1, 3])


func test_punctuation_never_starts_a_line() -> void:
	var text := "Ni vu ni connu ! « Oui » dit-il…"
	var words: Array = []
	for found in RegEx.create_from_string("\\S+").search_all(text):
		words.append([found.get_start(), found.get_end()])
	assert_eq(BookletLayout.unbreakable(text, words).map(func(span: Array) -> String:
		return text.substr(span[0], span[1] - span[0])), ["Ni", "vu", "ni", "connu !", "« Oui »", "dit-il…"])


func test_the_command_line_reads_its_arguments() -> void:
	if pack_folder.is_empty():
		return
	var command := Command.new()
	assert_eq(command.run(PackedStringArray(["print", "fr_FR"])), 2, "an unknown command")
	assert_eq(command.run(PackedStringArray(["build"])), 2, "no pack")
	assert_eq(command.run(PackedStringArray(["build", pack_folder, "--version", "large"])), 2, "an unknown version")
	assert_eq(command.run(PackedStringArray(["build", pack_folder, "--booklet", "one"])), 2, "a booklet not a number")
	var out := pack_folder.get_base_dir().path_join("cli")
	assert_eq(command.run(PackedStringArray(["build", pack_folder, "--version", "base", "--out", out])), 0)
	assert_true(FileAccess.file_exists(out.path_join("xx_XX/base/xx_XX-booklet-1.pdf")))
	command.free()


func test_a_bare_locale_is_a_pinned_pack() -> void:
	var pinned := ProjectSettings.globalize_path("res://").path_join("../kalulu-languages/fr_FR").simplify_path()
	if not DirAccess.dir_exists_absolute(pinned):
		pending("kalulu-languages/ is not checked out")
		return
	assert_eq(Command.pack_path("fr_FR"), pinned)
	assert_eq(Command.absolute("/tmp/x/../y"), "/tmp/y")
