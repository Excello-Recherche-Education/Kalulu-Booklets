extends GutTest
## Reading a pack (BookletPackReader, BookletPack), on the tiny pack of
## helpers/tiny_pack.gd. Ported from the Python generator's tests/test_pack.py.

const Tiny := preload("res://tests/helpers/tiny_pack.gd")

var pack_folder := ""


func before_each() -> void:
	pack_folder = Tiny.make()
	if pack_folder.is_empty():
		pending("kalulu-languages/ is not checked out (git submodule update --init)")


func after_all() -> void:
	Tiny.forget_all()


func _chapters(pack: BookletPack) -> Array:
	return pack.chapters.map(func(chapter: BookletPack.Chapter) -> Array:
		return [chapter.lesson, chapter.title, Array(chapter.gp_ids), chapter.booklet, chapter.position])


func test_refuses_another_schema_version() -> void:
	if pack_folder.is_empty():
		return
	var reader := BookletPackReader.new()
	assert_null(reader.read(Tiny.make(1)))
	assert_string_contains(reader.error, "schema version 1")


func test_refuses_version_6() -> void:
	if pack_folder.is_empty():
		return
	var reader := BookletPackReader.new()
	assert_null(reader.read(Tiny.make(6)))
	assert_string_contains(reader.error, "schema version 6; this generator reads version 7")


func test_reads_the_fonts_that_replace_the_defaults() -> void:
	if pack_folder.is_empty():
		return
	Tiny.execute(pack_folder, "INSERT INTO BookletFonts (ID, Name, File) VALUES (4, 'Loops', 'marelle/Marelle2-Regular.ttf')")
	Tiny.execute(pack_folder,
			"INSERT INTO BookletFonts (ID, Name, File) VALUES (5, 'Unused', 'marelle/MarelleBaton-Regular.ttf')")
	Tiny.execute(pack_folder, "UPDATE BookletSettings SET CursiveFontID = 4")
	var fonts := Tiny.read(pack_folder).fonts
	assert_eq(fonts.keys(), ["cursive"])
	assert_eq([fonts["cursive"].name, fonts["cursive"].file], ["Loops", "marelle/Marelle2-Regular.ttf"])


func test_a_pack_without_chapters_gets_one_per_lesson() -> void:
	if pack_folder.is_empty():
		return
	var pack := Tiny.read(pack_folder)
	assert_eq(Array(pack.made_chapters_for), [1, 2, 3])
	# One grapheme per line; the silent e is taught, not in the title.
	assert_eq(_chapters(pack), [[1, "A a", [1], 1, 0], [2, "L l", [2], 1, 0], [3, "U u\nN n", [3, 4, 5], 1, 0]])
	assert_true(pack.chapters.all(func(chapter: BookletPack.Chapter) -> bool:
		return chapter.id < 0 and chapter.overrides.is_empty()))


func test_every_lesson_without_a_chapter_gets_its_forced_one() -> void:
	if pack_folder.is_empty():
		return
	Tiny.add_chapter(pack_folder, 2, [2], {"Booklet": 1, "Title": "Lesson two"})
	Tiny.add_chapter(pack_folder, 2, [2], {"Position": 1, "Booklet": 2, "Title": "Optional"})
	var pack := Tiny.read(pack_folder)
	assert_eq(Array(pack.made_chapters_for), [1, 3])
	assert_eq(pack.chapters.map(func(chapter: BookletPack.Chapter) -> Array:
		return [chapter.lesson, chapter.position, chapter.booklet, chapter.title, chapter.id < 0]), [
		[1, 0, 1, "A a", true],
		[2, 0, 1, "Lesson two", false],
		[2, 1, 2, "Optional", false],
		# The booklet of the last chapter before it: the optional one's.
		[3, 0, 2, "U u\nN n", true],
	])


func test_a_lesson_with_chapters_gets_none_made() -> void:
	if pack_folder.is_empty():
		return
	for lesson in [1, 2, 3]:
		Tiny.add_chapter(pack_folder, lesson, [lesson])
	var pack := Tiny.read(pack_folder)
	assert_true(pack.made_chapters_for.is_empty())
	assert_true(pack.chapters.all(func(chapter: BookletPack.Chapter) -> bool: return chapter.id > 0))


func test_refuses_a_folder_without_language_db() -> void:
	var reader := BookletPackReader.new()
	assert_null(reader.read(ProjectSettings.globalize_path("user://")))
	assert_string_contains(reader.error, "no language.db")


func test_readable_at_the_last_first_lesson_of_its_gps() -> void:
	if pack_folder.is_empty():
		return
	var pack := Tiny.read(pack_folder)
	assert_eq(pack.words[1].lesson, 2, "\"la\": l is taught in lesson 2")
	assert_eq(pack.words[2].lesson, 3, "\"lune\"")


func test_chapters_follow_the_lessons_then_their_position() -> void:
	if pack_folder.is_empty():
		return
	var later := Tiny.add_chapter(pack_folder, 3, [3])
	var second := Tiny.add_chapter(pack_folder, 2, [2], {"Position": 1})
	var first := Tiny.add_chapter(pack_folder, 2, [2], {"Position": 0})
	assert_eq(Tiny.own(Tiny.read(pack_folder).chapters).map(func(chapter: BookletPack.Chapter) -> int:
		return chapter.id), [first, second, later])


func test_a_chapter_setting_overrides_the_language() -> void:
	if pack_folder.is_empty():
		return
	Tiny.add_chapter(pack_folder, 3, [3], {"WordCount": 2})
	var pack := Tiny.read(pack_folder)
	var chapter: BookletPack.Chapter = Tiny.own(pack.chapters)[0]
	assert_eq(pack.setting(chapter, "WordCount"), 2)
	assert_eq(pack.setting(chapter, "SyllableCount"), 12)


func test_the_pack_is_opened_read_only() -> void:
	if pack_folder.is_empty():
		return
	var before := FileAccess.get_file_as_bytes(pack_folder.path_join("language.db"))
	Tiny.read(pack_folder)
	assert_eq(FileAccess.get_file_as_bytes(pack_folder.path_join("language.db")), before)


func test_inverted_marks_cut_words() -> void:
	assert_eq(BookletText.words_of("¡Ese oso amasa! ¿Quién canta?"),
			["ese", "oso", "amasa", "quién", "canta"] as Array[String])
