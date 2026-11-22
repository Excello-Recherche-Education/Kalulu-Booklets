extends GutTest
## BookletVersion against the Python generator's versions.py (the fixture was
## written by tools/godot_fixtures.py at 338cae2, the last commit with the Python generator), and BookletPackReader's refusals.


func test_versions_match_python() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/versions.json"))
	assert_eq(Array(BookletVersion.all().keys()), fixture["order"])
	for name: String in fixture["versions"]:
		var expected: Dictionary = fixture["versions"][name]
		var version := BookletVersion.named(name)
		for locale: String in expected["labels"]:
			assert_eq(version.label(locale), expected["labels"][locale], "%s label in %s" % [name, locale])
		if expected["label_color"] == null:
			assert_null(version.label_color, name)
		else:
			var color: Color = version.label_color
			for channel in 3:
				assert_almost_eq([color.r, color.g, color.b][channel], float(expected["label_color"][channel]), 1e-6,
						"%s label colour" % name)
		for property: String in ["label_bold", "writing", "teacher", "folded", "printed", "adapted", "adaptations",
				"readers"]:
			assert_eq(version.get(property), expected[property], "%s %s" % [name, property])
		assert_eq([version.file_name("fr_FR", 2), version.file_name("pt_BR", 1, true, "cursive"),
				version.file_name("es_AR", 3, false, "script")], expected["file_names"], "%s file names" % name)


func test_reader_refuses_a_folder_without_a_pack() -> void:
	var reader := BookletPackReader.new()
	assert_null(reader.read(ProjectSettings.globalize_path("user://no-pack-here")))
	assert_string_starts_with(reader.error, "no language.db at ")


func test_reader_refuses_another_schema_version() -> void:
	var folder := ProjectSettings.globalize_path("user://old_pack")
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join("language.db")
	DirAccess.remove_absolute(path)
	var db := SQLite.new()
	db.path = path
	db.verbosity_level = SQLite.QUIET
	db.open_db()
	db.query("PRAGMA user_version = 6")
	db.close_db()
	var reader := BookletPackReader.new()
	assert_null(reader.read(folder))
	assert_eq(reader.error, "%s follows language-pack schema version 6; this generator reads version 7" % path)
