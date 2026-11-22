class_name BookletPackReader
extends RefCounted
## Fills a BookletPack from a pack's ``language.db``, with godot-sqlite: the only
## file of the generator that needs it.
##
## The contract is Kalulu-Languages ``SCHEMA.md``, schema version 7. The pack is
## opened read-only; nothing here ever writes to it.
##
##     var reader := BookletPackReader.new()
##     var pack := reader.read("…/kalulu-languages/fr_FR")
##     if pack == null:
##         push_error(reader.error)

## Why the last read() returned null: no language.db, or another schema.
var error := ""

var _db: SQLite


## The ``language.db`` a pack argument names: the file, or its folder. "" with
## ``error`` set when there is none.
func resolve(pack: String) -> String:
	var path := pack
	if path.begins_with("~"):
		path = OS.get_environment("HOME") + path.substr(1)
	if DirAccess.dir_exists_absolute(path):
		path = path.path_join("language.db")
	if not FileAccess.file_exists(path):
		error = "no language.db at %s" % path
		return ""
	return path


## The pack at ``pack`` (its folder or its language.db), or null with ``error``
## set.
func read(pack: String) -> BookletPack:
	error = ""
	var path := resolve(pack)
	if path.is_empty():
		return null
	_db = SQLite.new()
	_db.path = path
	_db.read_only = true
	_db.verbosity_level = SQLite.QUIET
	if not _db.open_db():
		error = "cannot open %s: %s" % [path, _db.error_message]
		return null
	var result := _load(path)
	_db.close_db()
	_db = null
	return result


func _rows(sql: String) -> Array:
	if not _db.query(sql):
		push_error("BookletPackReader: %s failed: %s" % [sql, _db.error_message])
		return []
	return _db.query_result.duplicate()


func _load(path: String) -> BookletPack:
	var version: int = _rows("PRAGMA user_version")[0]["user_version"]
	if version != BookletPack.SCHEMA_VERSION:
		error = "%s follows language-pack schema version %d; this generator reads version %d" \
				% [path, version, BookletPack.SCHEMA_VERSION]
		return null

	var pack := BookletPack.new()
	pack.folder = path.get_base_dir()
	pack.locale = pack.folder.get_file()

	var lesson_numbers := {}
	for row: Dictionary in _rows("SELECT ID, LessonNb FROM Lessons"):
		lesson_numbers[row["ID"]] = row["LessonNb"]

	for row: Dictionary in _rows(
			"""SELECT GPs.*, (SELECT MIN(Lessons.LessonNb) FROM GPsInLessons
				JOIN Lessons ON Lessons.ID = GPsInLessons.LessonID
				WHERE GPsInLessons.GPID = GPs.ID) AS FirstLesson
			FROM GPs"""):
		pack.gps[row["ID"]] = BookletPack.GP.new(row["ID"], row["Grapheme"], row["Phoneme"],
				int(row["Type"]) if row["Type"] != null else 0, _bool(row["Exception"]), row["FirstLesson"])

	pack.words = _items(pack.gps, "Words", "Word", "GPsInWords", "WordID")
	pack.syllables = _items(pack.gps, "Syllables", "Syllable", "GPsInSyllables", "SyllableID")

	var linked := {}
	for row: Dictionary in _rows("SELECT SentenceID, WordID FROM WordsInSentences ORDER BY SentenceID, Position"):
		if not linked.has(row["SentenceID"]):
			linked[row["SentenceID"]] = [] as Array[int]
		linked[row["SentenceID"]].append(row["WordID"])
	for row: Dictionary in _rows("SELECT ID, Sentence, Exception, Reading, BookletOnly, Uppercase FROM Sentences"):
		var word_ids: Array[int] = linked.get(row["ID"], [] as Array[int])
		pack.sentences[row["ID"]] = BookletPack.Sentence.new(row["ID"], row["Sentence"], word_ids,
				_bool(row["Exception"]), _reading(row["Reading"]), _bool(row["BookletOnly"]), _bool(row["Uppercase"]))

	var settings_rows := _rows("SELECT * FROM BookletSettings ORDER BY ID LIMIT 1")
	if settings_rows.is_empty():
		error = "%s has no BookletSettings row" % path
		return null
	var settings: Dictionary = settings_rows[0]
	for column: String in ["UppercaseProportion"] + BookletPack.SERIES_COLUMNS.values() \
			+ BookletPack.VERSION_COLUMNS.values() + BookletPack.SETTINGS:
		pack.settings[column] = settings[column]
	var booklet_fonts := {}
	for row: Dictionary in _rows("SELECT ID, Name, File FROM BookletFonts"):
		booklet_fonts[row["ID"]] = BookletPack.BookletFont.new(row["Name"], row["File"])
	for role: String in BookletPack.FONT_COLUMNS:
		var font_id: Variant = settings[BookletPack.FONT_COLUMNS[role]]
		if font_id != null and booklet_fonts.has(font_id):
			pack.fonts[role] = booklet_fonts[font_id]
	for row: Dictionary in _rows("SELECT ID, Name, File FROM BookletImages"):
		pack.images[row["ID"]] = BookletPack.BookletImage.new(row["Name"], row["File"])

	var chapters := {}
	for row: Dictionary in _rows("SELECT * FROM BookletChapters"):
		var overrides := {}
		for column: String in BookletPack.SETTINGS:
			if row[column] != null:
				overrides[column] = row[column]
		var chapter := BookletPack.Chapter.new(row["ID"], lesson_numbers.get(row["LessonID"], 0), row["Position"],
				row["Booklet"], row["Title"], row["ImageGPID"], _bool(row["GreySilent"]), overrides)
		chapter.image_id = row["ImageID"]
		chapters[row["ID"]] = chapter
	for row: Dictionary in _rows("SELECT ChapterID, GPID FROM BookletChapterGPs ORDER BY ID"):
		if chapters.has(row["ChapterID"]):
			chapters[row["ChapterID"]].gp_ids.append(row["GPID"])
	for row: Dictionary in _rows(
			"SELECT ChapterID, SentenceID, Break FROM BookletSentences ORDER BY ChapterID, Position, ID"):
		if chapters.has(row["ChapterID"]):
			chapters[row["ChapterID"]].sentences.append(BookletPack.ChapterSentence.new(row["SentenceID"], row["Break"]))
	for row: Dictionary in _rows("SELECT * FROM BookletEntries ORDER BY ChapterID, Part, Position, ID"):
		if chapters.has(row["ChapterID"]):
			var entries: Dictionary = chapters[row["ChapterID"]].entries
			if not entries.has(row["Part"]):
				entries[row["Part"]] = []
			entries[row["Part"]].append(BookletPack.Entry.new(row["Text"], row["Text2"], _bool(row["Header"])))
	for row: Dictionary in _rows("SELECT ChapterID, Title, Text FROM BookletStories ORDER BY ChapterID, Position, ID"):
		if chapters.has(row["ChapterID"]):
			chapters[row["ChapterID"]].stories.append(BookletPack.Story.new(row["Title"], row["Text"]))

	var lesson_gps := {}
	for row: Dictionary in _rows("SELECT LessonID, GPID FROM GPsInLessons ORDER BY ID"):
		if not lesson_gps.has(row["LessonID"]):
			lesson_gps[row["LessonID"]] = []
		lesson_gps[row["LessonID"]].append(row["GPID"])
	var made := BookletPack.default_chapters(lesson_numbers, lesson_gps, pack.gps, chapters.values())
	for chapter in made:
		chapters[chapter.id] = chapter
		pack.made_chapters_for.append(chapter.lesson)
	pack.chapters.assign(chapters.values())
	pack.index()
	pack.pick_made_pictures(made)
	return pack


func _items(gps: Dictionary, table: String, column: String, relation: String, key: String) -> Dictionary:
	var decompositions := {}
	for row: Dictionary in _rows("SELECT %s AS ItemID, GPID FROM %s ORDER BY %s, Position" % [key, relation, key]):
		if not decompositions.has(row["ItemID"]):
			decompositions[row["ItemID"]] = [] as Array[int]
		decompositions[row["ItemID"]].append(row["GPID"])
	var items := {}
	for row: Dictionary in _rows("SELECT ID, %s AS Text, Exception, Reading, BookletOnly, Uppercase FROM %s"
			% [column, table]):
		var gp_ids: Array[int] = decompositions.get(row["ID"], [] as Array[int])
		items[row["ID"]] = BookletPack.Item.new(row["ID"], row["Text"], _bool(row["Exception"]),
				_reading(row["Reading"]), _bool(row["BookletOnly"]), gp_ids,
				BookletPack.readable_at(gp_ids, gps), _bool(row["Uppercase"]))
	return items


## Python's ``bool()`` of a column: NULL and 0 are false.
static func _bool(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL:
			return false
		TYPE_INT, TYPE_FLOAT:
			return value != 0
		TYPE_STRING:
			return not (value as String).is_empty()
	return bool(value)


## Reading is NULL or non-zero for an entry the game reads.
static func _reading(value: Variant) -> bool:
	return value == null or value != 0
