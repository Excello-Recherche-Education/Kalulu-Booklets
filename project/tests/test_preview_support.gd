extends GutTest
## What the Prof Tool's live preview needs from the generator: chapter content
## kept between layouts (BookletContent.booklet()'s cache), and each page
## saying which chapters are laid out on it (Page.chapter_ids).

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


func _two_chapters() -> BookletPack:
	Tiny.add_chapter(pack_folder, 2, [2], {"Title": "L l"})
	Tiny.add_chapter(pack_folder, 3, [3, 4, 5], {"Title": "u n"})
	return Tiny.read(pack_folder)


static func _shape_of(booklet: BookletContent.Booklet) -> Array:
	return [booklet.notes, booklet.chapters.map(func(content: BookletContent.ChapterContent) -> Array:
		return [content.chapter.id, content.syllables.map(func(item: BookletContent.Styled) -> String:
			return item.text), content.words.map(func(item: BookletContent.Styled) -> String: return item.text)])]


func test_a_cached_booklet_is_the_booklet() -> void:
	if pack_folder.is_empty():
		return
	var pack := _two_chapters()
	var cache := {}
	var first := BookletContent.booklet(pack, 1, "", cache)
	assert_eq(_shape_of(first), _shape_of(BookletContent.booklet(pack, 1)))
	var ids: Array = first.chapters.map(func(content: BookletContent.ChapterContent) -> int: return content.chapter.id)
	assert_eq(cache.keys().size(), pack.chapters.size(), "every chapter's content is kept")
	# Laid out again, each chapter's content is the one kept...
	var second := BookletContent.booklet(pack, 1, "", cache)
	assert_eq(_shape_of(second), _shape_of(first))
	for index in second.chapters.size():
		assert_same(second.chapters[index], first.chapters[index])
	# ...except a chapter whose ID was erased, worked out again from the pack.
	cache.erase(ids[0])
	var third := BookletContent.booklet(pack, 1, "", cache)
	assert_not_same(third.chapters[0], first.chapters[0])
	assert_same(third.chapters[1], first.chapters[1])
	assert_eq(_shape_of(third), _shape_of(first))


func test_each_page_names_the_chapters_on_it() -> void:
	if pack_folder.is_empty():
		return
	var pack := _two_chapters()
	for version: BookletVersion in BookletVersion.all().values():
		var booklet := BookletContent.booklet(pack, 1)
		var laid_out := BookletWriter.layout_for(booklet, fonts, version)
		var pages := laid_out.run()
		# The cover, the blank pages and the back cover belong to no chapter.
		assert_true(pages[0].chapter_ids.is_empty(), version.name)
		assert_true(pages[-1].chapter_ids.is_empty(), version.name)
		var seen := {}
		for page in pages:
			if page.chapter_ids.is_empty():
				continue
			assert_false(page.steps.is_empty(), "%s: a chapter's page has something on it" % version.name)
			seen.merge(page.chapter_ids)
		var expected: Array = booklet.chapters.map(func(content: BookletContent.ChapterContent) -> int:
			return content.chapter.id)
		var found := seen.keys()
		found.sort()
		expected.sort()
		assert_eq(found, expected, version.name)
		laid_out.release()


## The Prof Tool exports the generator: what it reads byte for byte must be in
## an exported project as it is. Its fonts come as Godot imports them
## (FontSet.font_bytes()), its pictures are kept as they are.
func test_the_pictures_are_exported_as_they_are() -> void:
	for file in DirAccess.get_files_at(BookletArt.FOLDER):
		if file.ends_with(".import"):
			var config := ConfigFile.new()
			config.load(BookletArt.FOLDER.path_join(file))
			assert_eq(config.get_value("remap", "importer", ""), "keep", file)


func test_a_font_s_bytes_are_its_file_s() -> void:
	if pack_folder.is_empty():
		return
	var path := FontSet.pinned_folder().path_join(FontSet.SCRIPT)
	assert_true(FontSet.has_font(path))
	assert_eq(FontSet.font_bytes(path), FileAccess.get_file_as_bytes(path))
	assert_false(FontSet.has_font("res://nowhere/Nothing.otf"))
	assert_eq(FontSet.font_bytes("res://nowhere/Nothing.otf").size(), 0)
