extends GutTest
## Phase 3 of the port's check: every pack of kalulu-languages/ read by
## BookletPackReader as Python's pack.load() reads it, and every booklet of
## every series it prints holding, chapter for chapter, what Python's
## content.booklet() puts in it: the same syllables and words in the same grid
## order, the same sentences, silent letters, colours and notes.
##
## The expected values are written from the packs by tools/godot_content.py
## into tests/generated/content/, which is not committed (they follow the
## pinned packs): the Godot Tests workflow writes them before running GUT, and
## so must anyone running the tests by hand.

const ContentDump := preload("res://tests/helpers/content_dump.gd")
const GENERATED := "res://tests/generated/content"


func _locales() -> Array[String]:
	var out: Array[String] = []
	if DirAccess.dir_exists_absolute(GENERATED):
		for file in DirAccess.get_files_at(GENERATED):
			if file.ends_with(".json"):
				out.append(file.get_basename())
	out.sort()
	return out


func _packs_folder() -> String:
	return ProjectSettings.globalize_path("res://").path_join("../kalulu-languages").simplify_path()


func _expected(locale: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(GENERATED.path_join(locale + ".json")))


func test_every_pack_is_checked() -> void:
	if _locales().is_empty():
		pending("no expected content: run tools/godot_content.py first")
		return
	var packs: Array[String] = []
	for folder in DirAccess.get_directories_at(_packs_folder()):
		if FileAccess.file_exists(_packs_folder().path_join(folder).path_join("language.db")):
			packs.append(folder)
	packs.sort()
	assert_eq(_locales(), packs, "tools/godot_content.py wrote every pack of kalulu-languages/")


func test_packs_read_as_python_reads_them() -> void:
	if _locales().is_empty():
		pending("no expected content: run tools/godot_content.py first")
		return
	for locale in _locales():
		var reader := BookletPackReader.new()
		var pack := reader.read(_packs_folder().path_join(locale))
		assert_not_null(pack, "%s: %s" % [locale, reader.error])
		if pack == null:
			continue
		var found := ContentDump.difference(_expected(locale)["pack"], ContentDump.pack_dump(pack), locale)
		assert_eq(found, "", "%s reads as Python reads it" % locale)


func test_chapters_hold_what_python_puts_in_them() -> void:
	if _locales().is_empty():
		pending("no expected content: run tools/godot_content.py first")
		return
	for locale in _locales():
		var pack := BookletPackReader.new().read(_packs_folder().path_join(locale))
		if pack == null:
			fail_test("%s cannot be read" % locale)
			continue
		var booklets: Dictionary = _expected(locale)["booklets"]
		var made: Array[String] = []
		for series in pack.series():
			for number in pack.booklets():
				made.append("%s/%d" % [series, number])
		assert_eq(made, Array(booklets.keys(), TYPE_STRING, "", null), "%s prints the same booklets" % locale)
		for key: String in booklets:
			var parts := key.split("/")
			var booklet := BookletContent.booklet(pack, int(parts[1]), parts[0])
			var actual := ContentDump.booklet(booklet, pack)
			var expected: Dictionary = booklets[key]
			assert_eq(ContentDump.difference(expected["notes"], actual["notes"], "%s %s notes" % [locale, key]), "")
			assert_eq(actual["chapters"].size(), expected["chapters"].size(), "%s %s chapters" % [locale, key])
			for index in mini(actual["chapters"].size(), expected["chapters"].size()):
				var where := "%s %s chapter %d" % [locale, key, int(expected["chapters"][index]["chapter"])]
				assert_eq(ContentDump.difference(expected["chapters"][index], actual["chapters"][index], where), "")
