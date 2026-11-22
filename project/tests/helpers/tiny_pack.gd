extends RefCounted
## A tiny pack, made from the schema itself so the tests follow the contract
## (kalulu-languages/schema/v7.sql).
##
## Lessons: 1 teaches "a", 2 teaches "l", 3 teaches "u", "n" and the silent "e".

const GPS := {  # id: [grapheme, phoneme, type]
	1: ["a", "a", 1],
	2: ["l", "l", 2],
	3: ["u", "y", 1],
	4: ["n", "n", 2],
	5: ["e", "#", 0],
}
const LESSONS := {1: [1], 2: [2], 3: [3, 4, 5]}
const WORDS := {  # id: [word, GP ids, exception, booklet only]
	1: ["la", [2, 1], 0, 0],
	2: ["lune", [2, 3, 4, 5], 0, 0],
	3: ["l", [2], 0, 0],  # the elided "l'" sentences need
	4: ["une", [3, 4, 5], 0, 0],
	5: ["nu", [4, 3], 0, 0],
	6: ["lunule", [2, 3, 4, 3, 2, 5], 1, 0],  # an exception
	7: ["Luna", [2, 3, 4, 1], 0, 1],  # booklet only
}
const SYLLABLES := {1: ["la", [2, 1]], 2: ["nu", [4, 3]], 3: ["lu", [2, 3]], 4: ["un", [3, 4]]}
const SENTENCES := {1: ["La lune.", [1, 2]], 2: ["Une lune nue.", [4, 2]]}

## Where every test pack goes; emptied by forget_all().
const ROOT := "user://tiny_packs"

static var _made := 0


static func schema_path() -> String:
	return ProjectSettings.globalize_path("res://").path_join("../kalulu-languages/schema/v7.sql").simplify_path()


## A fresh pack in a folder of its own, ``<folder>/<locale>``; "" when the
## schema is not checked out.
static func make(version: int = 7, locale: String = "xx_XX") -> String:
	var schema := FileAccess.get_file_as_string(schema_path())
	if schema.is_empty():
		return ""
	_made += 1
	var folder := ProjectSettings.globalize_path(ROOT).path_join("%d-%d" % [Time.get_ticks_usec(), _made])
	var pack := folder.path_join(locale)
	DirAccess.make_dir_recursive_absolute(pack)
	var db := _open(pack)
	db.query(schema)
	db.query("PRAGMA user_version = %d" % version)
	for gp_id: int in GPS:
		db.query_with_bindings("INSERT INTO GPs (ID, Grapheme, Phoneme, Type) VALUES (?, ?, ?, ?)",
				[gp_id, GPS[gp_id][0], GPS[gp_id][1], GPS[gp_id][2]])
	for number: int in LESSONS:
		db.query_with_bindings("INSERT INTO Lessons (ID, LessonNb) VALUES (?, ?)", [number, number])
		for gp_id: int in LESSONS[number]:
			db.query_with_bindings("INSERT INTO GPsInLessons (GPID, LessonID) VALUES (?, ?)", [gp_id, number])
	for word_id: int in WORDS:
		var word: Array = WORDS[word_id]
		db.query_with_bindings("INSERT INTO Words (ID, Word, Exception, BookletOnly) VALUES (?, ?, ?, ?)",
				[word_id, word[0], word[2], word[3]])
		for position in word[1].size():
			db.query_with_bindings("INSERT INTO GPsInWords (WordID, GPID, Position) VALUES (?, ?, ?)",
					[word_id, word[1][position], position])
	for syllable_id: int in SYLLABLES:
		var syllable: Array = SYLLABLES[syllable_id]
		db.query_with_bindings("INSERT INTO Syllables (ID, Syllable) VALUES (?, ?)", [syllable_id, syllable[0]])
		for position in syllable[1].size():
			db.query_with_bindings("INSERT INTO GPsInSyllables (SyllableID, GPID, Position) VALUES (?, ?, ?)",
					[syllable_id, syllable[1][position], position])
	for sentence_id: int in SENTENCES:
		var sentence: Array = SENTENCES[sentence_id]
		db.query_with_bindings("INSERT INTO Sentences (ID, Sentence) VALUES (?, ?)", [sentence_id, sentence[0]])
		for position in sentence[1].size():
			db.query_with_bindings("INSERT INTO WordsInSentences (SentenceID, WordID, Position) VALUES (?, ?, ?)",
					[sentence_id, sentence[1][position], position])
	db.query("INSERT INTO BookletSettings (ID) VALUES (1)")
	db.close_db()
	return pack


## Adds a chapter to lesson ``lesson`` teaching ``gp_ids``; ``columns`` sets
## BookletChapters columns (Position 0 and Booklet 1 unless given). Returns
## its ID.
static func add_chapter(pack: String, lesson: int, gp_ids: Array = [], columns: Dictionary = {}) -> int:
	var values := {"LessonID": lesson, "Position": 0, "Booklet": 1}
	values.merge(columns, true)
	var db := _open(pack)
	var marks := ", ".join(values.keys().map(func(_key: Variant) -> String: return "?"))
	db.query_with_bindings("INSERT INTO BookletChapters (%s) VALUES (%s)" % [", ".join(values.keys()), marks],
			values.values())
	var chapter: int = db.last_insert_rowid
	for gp_id: int in gp_ids:
		db.query_with_bindings("INSERT INTO BookletChapterGPs (ChapterID, GPID) VALUES (?, ?)", [chapter, gp_id])
	db.close_db()
	return chapter


## Runs one statement on the pack.
static func execute(pack: String, sql: String, parameters: Array = []) -> void:
	var db := _open(pack)
	if not db.query_with_bindings(sql, parameters):
		push_error("tiny pack: %s failed: %s" % [sql, db.error_message])
	db.close_db()


static func read(pack: String) -> BookletPack:
	return BookletPackReader.new().read(pack)


## The chapters a test wrote, without the forced ones made for the lessons it
## left without (negative IDs): a pack's chapters or a booklet's.
static func own(chapters: Array) -> Array:
	return chapters.filter(func(chapter: Variant) -> bool:
		var item: BookletPack.Chapter = chapter.chapter if chapter is BookletContent.ChapterContent else chapter
		return item.id > 0)


## The pinned fonts, or null when kalulu-languages/ has none.
static func fonts() -> FontSet:
	if not FileAccess.file_exists(FontSet.pinned_folder().path_join(FontSet.CURSIVE)):
		return null
	return FontSet.from_folder(FontSet.pinned_folder())


## A PNG of ``width`` × ``height`` at ``path``, its folder made.
static func picture(path: String, width: int = 40, height: int = 30, color: Color = Color.ORANGE) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var image := Image.create(width, height, false, Image.FORMAT_RGB8)
	image.fill(color)
	image.save_png(path)


## Deletes every test pack made so far.
static func forget_all() -> void:
	_remove(ProjectSettings.globalize_path(ROOT))


static func _remove(folder: String) -> void:
	if not DirAccess.dir_exists_absolute(folder):
		return
	for sub in DirAccess.get_directories_at(folder):
		_remove(folder.path_join(sub))
	for file in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(file))
	DirAccess.remove_absolute(folder)


static func _open(pack: String) -> SQLite:
	var db := SQLite.new()
	db.path = pack.path_join("language.db")
	db.verbosity_level = SQLite.QUIET
	db.open_db()
	return db
