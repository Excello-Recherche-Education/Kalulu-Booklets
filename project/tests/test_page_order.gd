extends GutTest
## The order of a chapter's pages, the same in every version. Ported from the
## Python generator's tests/test_page_order.py.

const Tiny := preload("res://tests/helpers/tiny_pack.gd")


## The base layout, keeping the order its sections are laid out in.
class BaseWatched:
	extends BookletLayout
	var calls: Array = []

	func writing(content: BookletContent.ChapterContent) -> void:
		calls.append("writing")
		super(content)

	func lay_story(content: BookletContent.ChapterContent, story_title: String, paragraphs: Array) -> void:
		calls.append("story")
		super(content, story_title, paragraphs)

	func fluency(content: BookletContent.ChapterContent, items: Array[BookletContent.Styled]) -> void:
		calls.append("fluency")
		super(content, items)


## The same for an adapted version.
class AdaptedWatched:
	extends AdaptedLayout
	var calls: Array = []

	func writing(content: BookletContent.ChapterContent) -> void:
		calls.append("writing")
		super(content)

	func lay_story(content: BookletContent.ChapterContent, story_title: String, paragraphs: Array) -> void:
		calls.append("story")
		super(content, story_title, paragraphs)

	func fluency(content: BookletContent.ChapterContent, items: Array[BookletContent.Styled]) -> void:
		calls.append("fluency")
		super(content, items)


var pack_folder := ""
var fonts: FontSet


func before_each() -> void:
	fonts = Tiny.fonts()
	pack_folder = Tiny.make() if fonts != null else ""
	if pack_folder.is_empty():
		pending("kalulu-languages/ has no schema or fonts/ at its pinned commit")


func after_all() -> void:
	Tiny.forget_all()


func test_a_story_comes_after_the_writing_pages() -> void:
	if pack_folder.is_empty():
		return
	var chapter := Tiny.add_chapter(pack_folder, 2, [2], {"Title": "L l", "SentencePages": -1})
	for part in [3, 5]:
		Tiny.execute(pack_folder, "INSERT INTO BookletEntries (ChapterID, Part, Position, Text, Text2, Header) "
				+ "VALUES (?, ?, 0, 'la', '', 0)", [chapter, part])
	Tiny.execute(pack_folder,
			"INSERT INTO BookletStories (ChapterID, Position, Title, Text) VALUES (?, 0, 'Luna', 'La lune.')", [chapter])
	for version: BookletVersion in BookletVersion.all().values():
		if not version.writing:
			continue
		var booklet := BookletContent.booklet(Tiny.read(pack_folder), 1)
		var laid_out: BookletLayout = AdaptedWatched.new(booklet, fonts, version) if not version.adapted.is_empty() \
				else BaseWatched.new(booklet, fonts, version)
		laid_out.run()
		assert_eq(laid_out.calls, ["writing", "story", "fluency"], version.name)


func test_a_chapter_of_stories_only_starts_on_its_first_story() -> void:
	if pack_folder.is_empty():
		return
	var chapter := Tiny.add_chapter(pack_folder, 2, [2],
			{"Title": "", "SyllableCount": 0, "WordCount": 0, "SentencePages": -1})
	Tiny.execute(pack_folder,
			"INSERT INTO BookletStories (ChapterID, Position, Title, Text) VALUES (?, 0, 'Luna', 'La lune.')", [chapter])
	var booklet := BookletContent.booklet(Tiny.read(pack_folder), 1)
	var story: BookletContent.ChapterContent = booklet.chapters.filter(
			func(content: BookletContent.ChapterContent) -> bool: return content.chapter.id == chapter)[0]
	assert_false(story.has_chapter_page())
	var pages := BookletLayout.new(booklet, fonts).run()
	# No page is left blank between the chapters around it and the story.
	assert_true(pages.slice(1, pages.size() - 1).all(func(page: BookletLayout.Page) -> bool:
		return not page.numbered or not page.steps.is_empty()))
