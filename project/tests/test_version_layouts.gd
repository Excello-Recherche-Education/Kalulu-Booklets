extends GutTest
## The versions of a booklet: the same content, laid out apart. Ported from the
## Python generator's tests/test_versions.py.

const Tiny := preload("res://tests/helpers/tiny_pack.gd")

var pack_folder := ""
var fonts: FontSet


func before_each() -> void:
	fonts = Tiny.fonts()
	pack_folder = Tiny.make() if fonts != null else ""
	if pack_folder.is_empty():
		pending("kalulu-languages/ has no schema or fonts/ at its pinned commit")


func after_all() -> void:
	Tiny.forget_all()


func _picture(name: String) -> void:
	Tiny.picture(pack_folder.path_join("look_and_learn/images").path_join(name))


func _pages(version: String) -> Array:
	var booklet := BookletContent.booklet(Tiny.read(pack_folder), 1)
	return BookletLayout.new(booklet, fonts, BookletVersion.named(version)).run()


func _build(numbers: Array[int] = [], versions: Array[String] = []) -> Dictionary:
	var said: Array[String] = []
	var errors: Array[String] = []
	var out := pack_folder.get_base_dir().path_join("out")
	var code := BookletBuild.new(func(line: String) -> void: said.append(line),
			func(line: String) -> void: errors.append(line)).build(pack_folder, numbers, versions, out)
	return {"code": code, "out": out, "said": "\n".join(said), "errors": "\n".join(errors)}


static func _used(pages: Array) -> int:
	return pages.filter(func(page: BookletLayout.Page) -> bool: return not page.steps.is_empty()).size()


static func _page_count(path: String) -> int:
	return FileAccess.get_file_as_bytes(path).get_string_from_ascii().count("/Type /Page ")


static func _pdf_text(path: String) -> String:
	var bytes := FileAccess.get_file_as_bytes(path)
	for index in bytes.size():
		if bytes[index] == 0 or bytes[index] > 126:
			bytes[index] = 32
	return bytes.get_string_from_ascii()


func test_saddle_stitch_order() -> void:
	# Folded and stapled, the sheets read 1, 2, ... 8 (0-based here).
	assert_eq(BookletWriter.imposition(8), [[7, 0], [1, 6], [5, 2], [3, 4]])


func test_a_teacher_page_carries_the_next_page_number() -> void:
	var pages := [BookletLayout.Page.new(false), BookletLayout.Page.new(true, true), BookletLayout.Page.new(),
			BookletLayout.Page.new()]
	assert_eq(Array(BookletWriter.folios(pages)), [1, 2, 2, 3])


func test_a_gp_image_is_found_by_its_encoded_name() -> void:
	if pack_folder.is_empty():
		return
	Tiny.execute(pack_folder, "INSERT INTO GPs (ID, Grapheme, Phoneme, Type) VALUES (9, 'e', 'E', 1)")
	_picture("e-cap.e.png")
	assert_eq(Tiny.read(pack_folder).picture(9).get_file(), "e-cap.e.png")


func test_a_git_lfs_pointer_is_not_a_picture() -> void:
	if pack_folder.is_empty():
		return
	var folder := pack_folder.path_join("look_and_learn/images")
	DirAccess.make_dir_recursive_absolute(folder)
	var file := FileAccess.open(folder.path_join("a-a.png"), FileAccess.WRITE)
	file.store_string("version https://git-lfs.github.com/spec/v1\n")
	file.close()
	assert_eq(Tiny.read(pack_folder).picture(1), "")


func test_the_teacher_version_adds_a_page_before_a_chapter_with_a_picture() -> void:
	if pack_folder.is_empty():
		return
	_picture("l-l.png")
	Tiny.add_chapter(pack_folder, 2, [2], {"Title": "L l", "ImageGPID": 2})
	# Lesson 2's chapter has a picture; lessons 1 and 3 get forced chapters with
	# none, and no teacher page.
	assert_eq(_pages("teacher").filter(func(page: BookletLayout.Page) -> bool: return page.shares_next_number).size(), 1)
	assert_false(_pages("base").any(func(page: BookletLayout.Page) -> bool: return page.shares_next_number))


func test_the_no_writing_version_has_no_writing_page() -> void:
	if pack_folder.is_empty():
		return
	var chapter := Tiny.add_chapter(pack_folder, 2, [2],
			{"Title": "L l", "SyllableCount": 0, "WordCount": 0, "SentencePages": -1})
	Tiny.execute(pack_folder, "INSERT INTO BookletEntries (ChapterID, Part, Position, Text, Text2, Header) "
			+ "VALUES (?, 3, 0, 'la', '', 0)", [chapter])
	assert_eq(_used(_pages("no-writing")), _used(_pages("base")) - 1)


func test_every_version_gets_a_folder_and_the_printed_ones_an_a4_copy() -> void:
	if pack_folder.is_empty():
		return
	Tiny.add_chapter(pack_folder, 2, [2], {"Title": "L l"})
	var built := _build()
	assert_eq(built["code"], 0)
	for version: BookletVersion in BookletVersion.all().values():
		var folder: String = built["out"].path_join("xx_XX").path_join(version.name)
		var a5 := folder.path_join(version.file_name("xx_XX", 1))
		assert_eq(FileAccess.get_file_as_bytes(a5).slice(0, 4).get_string_from_ascii(), "%PDF", version.name)
		var imposed := folder.path_join(version.file_name("xx_XX", 1, true))
		assert_eq(FileAccess.file_exists(imposed), version.printed, version.name)
		if version.printed:
			assert_eq(_page_count(imposed) * 2, _page_count(a5), version.name)
			# A4 landscape.
			var box := RegEx.create_from_string("/MediaBox \\[0 0 ([0-9.]+) ([0-9.]+)\\]").search(_pdf_text(imposed))
			assert_not_null(box, "a MediaBox")
			if box != null:
				assert_almost_eq(float(box.get_string(1)), 841.8898, 0.001)
				assert_almost_eq(float(box.get_string(2)), 595.2756, 0.001)


func test_one_version_only() -> void:
	if pack_folder.is_empty():
		return
	var built := _build([], ["teacher"] as Array[String])
	assert_eq(built["code"], 0)
	assert_eq(Array(DirAccess.get_directories_at(built["out"].path_join("xx_XX"))), ["teacher"])


func test_a_made_chapter_takes_its_first_gp_with_a_picture() -> void:
	if pack_folder.is_empty():
		return
	# Lesson 3 teaches u, n and the silent e: only n has an image.
	_picture("n-n.png")
	var made := {}
	for chapter in Tiny.read(pack_folder).chapters:
		made[chapter.lesson] = chapter
	assert_eq(made[3].image_gp_id, 4)
	assert_null(made[1].image_gp_id)


func test_the_a4_sheet_centres_its_two_pages() -> void:
	# Two A5 pages (296 mm) on an A4 sheet (297 mm): half a millimetre each side.
	var margin := (BookletWriter.A4_LANDSCAPE.x - 2.0 * BookletLayout.PAGE_WIDTH) / 2.0
	assert_almost_eq(margin, 0.5 * BookletLayout.MM, 0.01)
	assert_eq(BookletWriter.sheet_sides(4), [[[3, margin], [0, margin + BookletLayout.PAGE_WIDTH]],
			[[1, margin], [2, margin + BookletLayout.PAGE_WIDTH]]])


func test_a_picture_name_matches_its_letter_case() -> void:
	if pack_folder.is_empty():
		return
	# Open o: only the closed o's picture is there, and a disk that ignores case
	# must not hand it over.
	Tiny.execute(pack_folder, "INSERT INTO GPs (ID, Grapheme, Phoneme, Type) VALUES (9, 'o', 'O', 1)")
	_picture("o-o.png")
	assert_eq(Tiny.read(pack_folder).picture(9), "")


func test_the_no_writing_version_closes_on_folded_sheets() -> void:
	if pack_folder.is_empty():
		return
	var chapter := Tiny.add_chapter(pack_folder, 2, [2], {"Title": "L l"})
	Tiny.execute(pack_folder, "INSERT INTO BookletEntries (ChapterID, Part, Position, Text, Text2, Header) "
			+ "VALUES (?, 3, 0, 'la', '', 0)", [chapter])
	assert_eq(_pages("no-writing").size() % 4, 0)


func test_the_teacher_version_keeps_the_base_page_numbers() -> void:
	if pack_folder.is_empty():
		return
	_picture("l-l.png")
	Tiny.add_chapter(pack_folder, 2, [2], {"Title": "L l", "ImageGPID": 2})
	var numbers := func(pages: Array) -> Array:
		var folios := BookletWriter.folios(pages)
		var out: Array = []
		for index in pages.size():
			var page: BookletLayout.Page = pages[index]
			if not page.steps.is_empty() and page.numbered and not page.shares_next_number:
				out.append(folios[index])
		return out
	var base: Array = numbers.call(_pages("base"))
	var teacher: Array = numbers.call(_pages("teacher"))
	assert_eq(teacher, base.slice(0, teacher.size()))


func test_a_note_names_the_versions_that_gave_it_once_each() -> void:
	if pack_folder.is_empty():
		return
	# A word too wide for its cell, among the words and in the fluency test:
	# each version notes it twice.
	var chapter := Tiny.add_chapter(pack_folder, 2, [2], {"Title": "L l"})
	for part in [2, 5]:
		Tiny.execute(pack_folder, "INSERT INTO BookletEntries (ChapterID, Part, Position, Text, Text2, Header) "
				+ "VALUES (?, ?, 0, 'lalalalalalalalalalalala', '', 0)", [chapter, part])
	var built := _build([], ["base", "teacher", "base"] as Array[String])
	assert_eq(built["code"], 0)
	assert_false(built["said"].contains("base, base"))
	assert_eq(Array(built["said"].split("\n")).filter(func(line: String) -> bool:
		return line.contains("lalala") and line.contains("[")), [])


func _booklet_image(file: String = "puits.png", picture: bool = true) -> void:
	var folder := pack_folder.path_join("booklet_images")
	if picture:
		Tiny.picture(folder.path_join(file), 40, 30, Color.BROWN)
	else:
		DirAccess.make_dir_recursive_absolute(folder)
		var pointer := FileAccess.open(folder.path_join(file), FileAccess.WRITE)
		pointer.store_string("version https://git-lfs.github.com/spec/v1\n")
		pointer.close()
	Tiny.execute(pack_folder, "INSERT INTO BookletImages (ID, Name, File) VALUES (1, 'Puits', ?)", [file])


func test_a_chapter_shows_its_own_booklet_image_on_the_teacher_page() -> void:
	if pack_folder.is_empty():
		return
	# Lesson 2 teaches "l", which has no Look & Learn image here: the chapter
	# names a picture of the pack's own instead.
	_booklet_image()
	Tiny.add_chapter(pack_folder, 2, [2], {"Title": "L l", "ImageID": 1})
	var pack := Tiny.read(pack_folder)
	var chapter: BookletPack.Chapter = pack.chapters.filter(func(item: BookletPack.Chapter) -> bool:
		return item.lesson == 2)[0]
	assert_eq(pack.chapter_picture(chapter), pack_folder.path_join("booklet_images/puits.png"))
	assert_eq(_pages("teacher").filter(func(page: BookletLayout.Page) -> bool: return page.shares_next_number).size(), 1)


func test_a_booklet_image_not_checked_out_leaves_the_teacher_page_out_and_says_so() -> void:
	if pack_folder.is_empty():
		return
	_booklet_image("puits.png", false)
	Tiny.add_chapter(pack_folder, 2, [2], {"Title": "L l", "ImageID": 1})
	var booklet := BookletContent.booklet(Tiny.read(pack_folder), 1)
	var pages := BookletLayout.new(booklet, fonts, BookletVersion.named("teacher")).run()
	assert_false(pages.any(func(page: BookletLayout.Page) -> bool: return page.shares_next_number))
	assert_true(booklet.notes.any(func(note: String) -> bool:
		return note.contains("booklet_images/puits.png cannot be printed")))


func test_a_chapter_without_a_booklet_image_keeps_its_gp_picture() -> void:
	if pack_folder.is_empty():
		return
	_picture("l-l.png")
	_booklet_image()
	Tiny.add_chapter(pack_folder, 2, [2], {"Title": "L l", "ImageGPID": 2})
	var pack := Tiny.read(pack_folder)
	var chapter: BookletPack.Chapter = pack.chapters.filter(func(item: BookletPack.Chapter) -> bool:
		return item.lesson == 2)[0]
	assert_eq(pack.chapter_picture(chapter).get_file(), "l-l.png")


func test_a_title_of_up_to_five_lines_keeps_the_three_line_size() -> void:
	# A title of several graphemes is a column, one per line: four or five
	# lines must not fall back to the small default size.
	var all_sizes := [BookletLayout.TITLE_SIZES]
	for style: Dictionary in AdaptedLayout.STYLES.values():
		all_sizes.append(style["title_sizes"])
	for sizes: Dictionary in all_sizes:
		assert_eq([sizes[4], sizes[5]], [sizes[3], sizes[3]])


func test_a_language_prints_its_series_and_versions_only() -> void:
	if pack_folder.is_empty():
		return
	Tiny.add_chapter(pack_folder, 2, [2], {"Title": "L l"})
	Tiny.execute(pack_folder, "UPDATE BookletSettings SET ScriptSeries = 1, CursiveSeries = 1, TeacherVersion = 0, "
			+ "NoWritingVersion = 0, DyslexiaVersion = 0, DyspraxiaVersion = 0, AdhdVersion = 0")
	assert_eq(Array(Tiny.read(pack_folder).versions()), ["base"])
	var built := _build([], ["base", "adhd"] as Array[String])
	assert_eq(built["code"], 0)
	assert_string_contains(built["said"], "xx_XX prints no adhd version")
	assert_eq(Array(DirAccess.get_directories_at(built["out"].path_join("xx_XX"))), ["base"])
	var files := Array(DirAccess.get_files_at(built["out"].path_join("xx_XX/base")))
	files.sort()
	assert_eq(files, ["xx_XX-booklet-1-cursive-print.pdf", "xx_XX-booklet-1-cursive.pdf",
			"xx_XX-booklet-1-script-print.pdf", "xx_XX-booklet-1-script.pdf"])


func test_a_language_of_one_series_keeps_its_file_names() -> void:
	if pack_folder.is_empty():
		return
	var built := _build([], ["base"] as Array[String])
	assert_eq(built["code"], 0)
	assert_true(FileAccess.file_exists(built["out"].path_join("xx_XX/base/xx_XX-booklet-1.pdf")))


func test_a_short_fluency_test_keeps_a_full_bubble() -> void:
	if pack_folder.is_empty():
		return
	# The printed Brazilian booklet's 25-item test has the 50-item one's bubble.
	var heights: Array[float] = []
	for count in [25, 50]:
		var pages := BookletLayout.new(BookletContent.booklet(Tiny.read(pack_folder), 1), fonts)
		pages.new_page()
		var top := pages.y
		var items: Array[BookletContent.Styled] = []
		for _index in count:
			items.append(BookletContent.Styled.new("la"))
		pages.fluency(null, items)
		heights.append(top - pages.y)
	assert_almost_eq(heights[0], heights[1], 1e-6)
