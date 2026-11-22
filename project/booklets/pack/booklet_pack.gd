class_name BookletPack
extends RefCounted
## What the booklets read from a language pack: the lessons, the GPs they
## teach, the words, syllables and sentences with their decompositions and the
## flag printing them in capitals, and what the ``Booklet*`` tables say the
## booklets print and with which fonts (Kalulu-Languages ``SCHEMA.md``, schema
## version 7).
##
## A plain model that depends on nothing: BookletPackReader fills it from a
## ``language.db``, and the Prof Tool fills it from what it is editing.

const SCHEMA_VERSION := 7

## GPs.Type.
const SILENT := 0
const VOWEL := 1
const CONSONANT := 2

## BookletEntries.Part.
const SYLLABLES := 1
const WORDS := 2
const WRITING := 3
const TABLES := 4
const FLUENCY := 5

## BookletSentences.Break: what comes before a sentence.
const SAME_LINE := 0
const NEW_LINE := 1
const NEW_PARAGRAPH := 2

## BookletSettings.SentenceFont and SentenceFirstFont.
const ALTERNATE := 0
const SCRIPT := 1
const CURSIVE := 2

## What a language prints (version 7): its series, and the versions printed
## besides the base booklet, by BookletVersion's names. In this order.
const SERIES_COLUMNS := {"script": "ScriptSeries", "cursive": "CursiveSeries"}
const VERSION_COLUMNS := {"teacher": "TeacherVersion", "no-writing": "NoWritingVersion",
		"dyslexia": "DyslexiaVersion", "dyspraxia": "DyspraxiaVersion", "adhd": "AdhdVersion"}

## The columns a chapter can override, NULL meaning the BookletSettings value.
## UppercaseProportion is the language's alone (version 6).
const SETTINGS := ["SyllableCount", "SyllableColumns", "WordCount", "WordColumns", "SentenceFont",
		"SentenceFirstFont", "SentencePages", "WritingModels", "WritingTracings"]

## The fonts a language can replace (FontSet's roles) -> the BookletSettings
## column naming the BookletFonts row that replaces it; NULL keeps the default.
const FONT_COLUMNS := {"script": "ScriptFontID", "script_bold": "ScriptBoldFontID",
		"script_black": "ScriptBlackFontID", "cursive": "CursiveFontID"}

## How a GP's grapheme or phoneme is spelled in its asset file names, as the
## game spells them (Kalulu-Frontend Database._text_to_file_name()): a symbol
## as a word, a text with a capital as "cap." and its lowercase, so that "e-E"
## and "e-e" stay two files on a filesystem that folds case.
const _SYMBOL_NAMES := {"#": "sharp", "@": "at", "*": "star", "$": "usd", "%": "pcent", "§": "para"}
const LOOK_AND_LEARN_IMAGES := "look_and_learn/images"
## The pack's own pictures for the teacher's booklet (BookletImages).
const BOOKLET_IMAGES := "booklet_images"


class GP:
	var id: int
	var grapheme: String
	var phoneme: String
	var type: int
	var exception: bool
	## The first lesson teaching it, by LessonNb; null when no lesson does.
	var lesson: Variant

	func _init(gp_id: int, gp_grapheme: String, gp_phoneme: String, gp_type: int, gp_exception: bool,
			first_lesson: Variant) -> void:
		id = gp_id
		grapheme = gp_grapheme
		phoneme = gp_phoneme
		type = gp_type
		exception = gp_exception
		lesson = first_lesson

	func silent() -> bool:
		return type == SILENT


## A word or a syllable: its text and how it decomposes into GPs.
class Item:
	var id: int
	var text: String
	var exception: bool
	var reading: bool
	var booklet_only: bool
	var gp_ids: Array[int]
	## The lesson it becomes readable at: the last of its GPs' first lessons, as
	## the game and the Prof Tool work it out. null when never (no
	## decomposition, or a GP no lesson teaches).
	var lesson: Variant
	## Printed in capitals, while the language's UppercaseProportion is above 0.
	var uppercase: bool

	func _init(item_id: int, item_text: String, item_exception: bool, item_reading: bool, only_booklet: bool,
			item_gp_ids: Array[int], readable_at: Variant, item_uppercase: bool = false) -> void:
		id = item_id
		text = item_text
		exception = item_exception
		reading = item_reading
		booklet_only = only_booklet
		gp_ids = item_gp_ids
		lesson = readable_at
		uppercase = item_uppercase


class Sentence:
	var id: int
	var text: String
	var word_ids: Array[int]
	var exception: bool
	var reading: bool
	var booklet_only: bool
	var uppercase: bool

	func _init(sentence_id: int, sentence_text: String, sentence_word_ids: Array[int],
			sentence_exception: bool = false, sentence_reading: bool = true, only_booklet: bool = false,
			sentence_uppercase: bool = false) -> void:
		id = sentence_id
		text = sentence_text
		word_ids = sentence_word_ids
		exception = sentence_exception
		reading = sentence_reading
		booklet_only = only_booklet
		uppercase = sentence_uppercase


## A font replacing a default one: a file of Kalulu-Languages' fonts/.
class BookletFont:
	var name: String
	## Its path inside fonts/, folders separated by "/".
	var file: String

	func _init(font_name: String, font_file: String) -> void:
		name = font_name
		file = font_file


## A picture of the pack's own for the teacher's booklet: a file of the pack's
## booklet_images/, for a chapter whose sound has no Look & Learn image.
class BookletImage:
	var name: String
	## Its path inside booklet_images/, folders separated by "/".
	var file: String

	func _init(image_name: String, image_file: String) -> void:
		name = image_name
		file = image_file


## A line of a chapter's hand-written lists (BookletEntries).
class Entry:
	var text: String
	var text2: String
	var header: bool

	func _init(entry_text: String, entry_text2: String, entry_header: bool) -> void:
		text = entry_text
		text2 = entry_text2
		header = entry_header


class Story:
	var title: String
	var text: String

	func _init(story_title: String, story_text: String) -> void:
		title = story_title
		text = story_text


class ChapterSentence:
	var sentence_id: int
	## What comes before it: SAME_LINE, NEW_LINE or NEW_PARAGRAPH.
	var brk: int

	func _init(id: int, before: int) -> void:
		sentence_id = id
		brk = before


class Chapter:
	var id: int
	var lesson: int  # LessonNb
	var position: int
	var booklet: int
	var title: String
	var image_gp_id: Variant  # int or null
	var grey_silent: bool
	## Column -> value, for the columns the chapter sets itself.
	var overrides: Dictionary
	var gp_ids: Array[int] = []
	## The pack's own picture for the teacher's page (BookletImages), which
	## takes the place of the ImageGPID one; int or null.
	var image_id: Variant = null
	var sentences: Array[ChapterSentence] = []
	## Part -> Array of Entry, in order. A part listed here replaces the
	## automatic choice.
	var entries: Dictionary = {}
	var stories: Array[Story] = []

	func _init(chapter_id: int, lesson_number: int, chapter_position: int, booklet_number: int,
			chapter_title: String, image_gp: Variant, grey: bool, chapter_overrides: Dictionary) -> void:
		id = chapter_id
		lesson = lesson_number
		position = chapter_position
		booklet = booklet_number
		title = chapter_title
		image_gp_id = image_gp
		grey_silent = grey
		overrides = chapter_overrides

	## How the Prof Tool names a chapter.
	func name() -> String:
		return "Lesson %d, chapter %d" % [lesson, position + 1]


var locale: String
## The pack's folder, the one holding its language.db; "" when it has none on
## disk, and then no picture is found.
var folder: String
## ID -> GP, Item, Sentence, in the order the pack lists them.
var gps: Dictionary = {}
var words: Dictionary = {}
var syllables: Dictionary = {}
var sentences: Dictionary = {}
var settings: Dictionary = {}
## In the booklets' order: by lesson, position, then ID.
var chapters: Array[Chapter] = []
## Lowercased text -> the IDs of every word or syllable spelled that way.
var words_by_text: Dictionary = {}
var syllables_by_text: Dictionary = {}
## Role (FONT_COLUMNS) -> the BookletFont replacing its default, for those replaced.
var fonts: Dictionary = {}
## ID -> BookletImage.
var images: Dictionary = {}
## The lessons that had no chapter, whose forced chapter is made here
## (default_chapters()): every one of them for a pack with no chapter.
var made_chapters_for: Array[int] = []


## The series the language prints, "script" and / or "cursive", in that order
## (SCHEMA.md, ``ScriptSeries`` / ``CursiveSeries``).
func series() -> Array[String]:
	var out: Array[String] = []
	for name: String in SERIES_COLUMNS:
		if _truthy(settings[SERIES_COLUMNS[name]]):
			out.append(name)
	return out


## The versions the language prints: the base booklet always, then those its
## settings ask for.
func versions() -> Array[String]:
	var out: Array[String] = ["base"]
	for name: String in VERSION_COLUMNS:
		if _truthy(settings[VERSION_COLUMNS[name]]):
			out.append(name)
	return out


## Whether the Uppercase flags count: the Prof Tool draws them at the
## language's UppercaseProportion, and at 0 they are ignored (SCHEMA.md).
func capitals() -> bool:
	return settings["UppercaseProportion"] > 0


## The value a chapter prints with: its own, or the language's.
func setting(chapter: Chapter, column: String) -> Variant:
	return chapter.overrides.get(column, settings[column])


## A GP's Look & Learn image, as the game finds it: by its encoded name, else by
## its raw one, composed or decomposed (packs store "ç" either way). "" when
## the GP or its image is missing, or the image is a Git LFS pointer.
func picture(gp_id: Variant) -> String:
	var gp: GP = gps.get(gp_id) if gp_id != null else null
	if gp == null or folder.is_empty():
		return ""
	var images_folder := folder.path_join(LOOK_AND_LEARN_IMAGES)
	# Names are matched against the folder's listing, letter case included:
	# macOS's disks ignore case, so asking for "o-O.png" there would find
	# "o-o.png", another sound's picture, where Linux finds nothing.
	var files := {}
	if DirAccess.dir_exists_absolute(images_folder):
		for file in DirAccess.get_files_at(images_folder):
			files[file] = true
	for name in ["%s-%s" % [_file_name(gp.grapheme), _file_name(gp.phoneme)], "%s-%s" % [gp.grapheme, gp.phoneme]]:
		for form in [PythonUnicode.nfc(name), PythonUnicode.nfd(name)]:
			var file: String = form + ".png"
			if files.has(file) and _is_png(images_folder.path_join(file)):
				return images_folder.path_join(file)
	return ""


## A chapter's picture on the teacher's page: its own booklet image when it
## names one, else its ImageGPID's Look & Learn image. "" when it has neither,
## or the file is missing or a Git LFS pointer.
func chapter_picture(chapter: Chapter) -> String:
	if chapter.image_id == null:
		return picture(chapter.image_gp_id)
	var image: BookletImage = images.get(chapter.image_id)
	if image == null or folder.is_empty():
		return ""
	var path := folder.path_join(BOOKLET_IMAGES).path_join(image.file)
	return path if FileAccess.file_exists(path) and _is_picture(path) else ""


func booklets() -> Array[int]:
	var numbers := {}
	for chapter in chapters:
		numbers[chapter.booklet] = true
	var out: Array[int] = []
	out.assign(numbers.keys())
	out.sort()
	return out


## Fills ``words_by_text`` and ``syllables_by_text`` from the lists, and sorts
## the chapters into the booklets' order. A pack's filler calls it last.
func index() -> void:
	words_by_text = _by_text(words)
	syllables_by_text = _by_text(syllables)
	var sorted := StableSort.sorted(chapters, func(chapter: Chapter) -> Array:
		return [chapter.lesson, chapter.position, chapter.id])
	chapters.assign(sorted)


## The forced chapters of the lessons ``existing`` has none for: every lesson
## has one, its first chapter. Made as the Prof Tool's Booklets screen makes
## them (BookletData.add_missing_chapters()), in the lessons' order: the
## lesson's GPs, a title made of them, the language's settings, and the booklet
## of the last chapter at or before that lesson (1 when there is none). Their
## IDs are negative, which no row has. ``lesson_numbers`` is lesson ID ->
## LessonNb and ``lesson_gps`` lesson ID -> its GP IDs, both in the pack's
## order. Their teacher's picture is chosen by ``pick_made_pictures()`` once
## the pack can find its images.
static func default_chapters(lesson_numbers: Dictionary, lesson_gps: Dictionary, pack_gps: Dictionary,
		existing: Array = []) -> Array[Chapter]:
	var have := {}
	for chapter: Chapter in existing:
		have[chapter.lesson] = true
	var made: Array[Chapter] = []
	var lessons := StableSort.sorted(lesson_numbers.keys(), func(lesson_id: Variant) -> int:
		return lesson_numbers[lesson_id])
	for lesson_id: Variant in lessons:
		var number: int = lesson_numbers[lesson_id]
		if have.has(number):
			continue
		var gp_ids: Array[int] = []
		for gp_id: int in lesson_gps.get(lesson_id, []):
			if not gp_ids.has(gp_id):
				gp_ids.append(gp_id)
		var booklet := 1
		var any := false
		for chapter: Chapter in existing + made:
			if chapter.lesson <= number:
				booklet = chapter.booklet if not any else maxi(booklet, chapter.booklet)
				any = true
		var chapter := Chapter.new(-number, number, 0, booklet, title_for(gp_ids, pack_gps), null, false, {})
		chapter.gp_ids = gp_ids
		made.append(chapter)
	return made


## A made chapter's teacher picture: the first of its GPs with a Look & Learn
## image, as the Prof Tool's BookletData.first_gp_with_image() chooses it.
func pick_made_pictures(made: Array[Chapter]) -> void:
	for chapter in made:
		chapter.image_gp_id = null
		for gp_id in chapter.gp_ids:
			if not picture(gp_id).is_empty():
				chapter.image_gp_id = gp_id
				break


## A title from GPs, as the Prof Tool's BookletData.title_for() makes it: each
## grapheme once, exceptions and silent letters left out unless nothing else is
## left, a single letter with its capital ("L l"), one grapheme per line, so
## that a title of several prints as a column ("U u" above "N n"), as the
## hand-written titles do.
static func title_for(gp_ids: Array[int], pack_gps: Dictionary) -> String:
	var kept: Array[int] = []
	for gp_id in gp_ids:
		if pack_gps.has(gp_id) and not pack_gps[gp_id].exception and not pack_gps[gp_id].silent():
			kept.append(gp_id)
	var parts: Array[String] = []
	for gp_id in (kept if not kept.is_empty() else gp_ids):
		if not pack_gps.has(gp_id):
			continue
		var grapheme: String = pack_gps[gp_id].grapheme
		var raised := PythonUnicode.upper_full(grapheme)
		var text := "%s %s" % [raised, grapheme] if grapheme.length() == 1 and raised != grapheme else grapheme
		if not parts.has(text):
			parts.append(text)
	return "\n".join(parts)


## The lesson an item made of ``gp_ids`` becomes readable at (see Item.lesson).
static func readable_at(gp_ids: Array[int], pack_gps: Dictionary) -> Variant:
	if gp_ids.is_empty():
		return null
	var last := 0
	for gp_id in gp_ids:
		var lesson: Variant = pack_gps[gp_id].lesson if pack_gps.has(gp_id) else null
		if lesson == null:
			return null
		last = maxi(last, lesson)
	return last


static func _by_text(items: Dictionary) -> Dictionary:
	var by_text := {}
	var ids := items.keys()
	ids.sort()
	for item_id: int in ids:
		var key := BookletText.lower(items[item_id].text)
		if not by_text.has(key):
			by_text[key] = []
		by_text[key].append(item_id)
	return by_text


static func _file_name(text: String) -> String:
	if _SYMBOL_NAMES.has(text):
		return _SYMBOL_NAMES[text]
	var lowered := _python_lower(text)
	return text if text == lowered else "cap." + lowered


## Python's own ``str.lower()``, which may lengthen the text ("İ").
static func _python_lower(text: String) -> String:
	var out := PackedStringArray()
	for index in text.length():
		var code := text.unicode_at(index)
		out.append(PythonUnicodeTables.MULTI_LOWER[code] if PythonUnicodeTables.MULTI_LOWER.has(code)
				else text[index].to_lower())
	return "".join(out)


## Not a Git LFS pointer left in its place: a checkout without the media has
## small text files under the images' names.
static func _is_png(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	return file != null and file.get_buffer(8) == PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])


## A PNG or a JPEG, not a Git LFS pointer left in its place.
static func _is_picture(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var start := file.get_buffer(8)
	return start == PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) \
			or (start.size() >= 3 and start[0] == 0xFF and start[1] == 0xD8 and start[2] == 0xFF)


static func _truthy(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL:
			return false
		TYPE_BOOL:
			return value
		TYPE_INT, TYPE_FLOAT:
			return value != 0
	return true
