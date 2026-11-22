extends GutTest
## VectorArt against the Python generator's vector.py, on the art it draws
## (tests/fixtures/vector_art.json, written by tools/godot_fixtures.py at 338cae2, the last commit with the Python generator), and what it
## refuses.


func _art_folder() -> String:
	return BookletArt.FOLDER


func test_reads_the_art_as_python_does() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/vector_art.json"))
	for file: String in fixture:
		var art := VectorArt.read(_art_folder().path_join(file))
		var expected: Dictionary = fixture[file]
		assert_eq(art.error, "", file)
		assert_eq(art.width, float(expected["width"]), "%s: width" % file)
		assert_eq(art.height, float(expected["height"]), "%s: height" % file)
		assert_eq(art.shapes.size(), expected["shapes"].size(), "%s: shapes" % file)
		var wrong := 0
		for index in mini(art.shapes.size(), expected["shapes"].size()):
			var got: Dictionary = art.shapes[index]
			var want: Dictionary = expected["shapes"][index]
			var color: Color = got["color"]
			if not (is_equal_approx(color.r, want["color"][0]) and is_equal_approx(color.g, want["color"][1])
					and is_equal_approx(color.b, want["color"][2])
					and is_equal_approx(got["opacity"], want["opacity"]) and got["even_odd"] == want["even_odd"]):
				wrong += 1
				continue
			var commands: Array = got["commands"]
			if commands.size() != want["commands"].size():
				wrong += 1
				continue
			for at in commands.size():
				var step: Array = commands[at]
				var other: Array = want["commands"][at]
				if step[0] != other[0] or step.size() != other.size():
					wrong += 1
					break
				for number in range(1, step.size()):
					if absf(step[number] - other[number]) > 1e-9 * maxf(1.0, absf(other[number])):
						wrong += 1
						break
		assert_eq(wrong, 0, "%s: shapes read differently" % file)


func test_draws_as_python_does() -> void:
	var art := VectorArt.read(_art_folder().path_join("cover-star.svg"))
	var surface := RecordingSurface.new(Vector2(420, 595))
	art.draw(surface, 10.0, 500.0, 100.0)
	var operations: Array = surface.pages[0]
	assert_eq(operations[0]["op"], "save")
	assert_eq(operations[1], {"op": "transform", "matrix": [1.0, 0.0, 0.0, 1.0, 10.0, 500.0]})
	var scale := 100.0 / art.width
	assert_eq(operations[2], {"op": "transform", "matrix": [scale, 0.0, 0.0, -scale, 0.0, 0.0]})
	assert_eq(operations[3]["op"], "fill_color")
	assert_eq(operations[4]["op"], "fill_alpha")
	assert_eq(operations[5]["op"], "path")
	assert_eq(operations[5]["code"][0][0], "m")
	assert_eq(operations.back()["op"], "restore")


func _refused(svg: String) -> String:
	var path := "user://refused.svg"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(svg)
	file.close()
	return VectorArt.read(path).error


func test_refuses_what_it_does_not_read() -> void:
	var head := "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 10 10\">"
	assert_string_contains(_refused(head + "<circle r=\"3\"/></svg>"), "<circle> is not read")
	assert_string_contains(_refused(head + "<path d=\"M 0 0 Q 1 1 2 2\"/></svg>"), "does not read")
	assert_string_contains(_refused(head + "<path fill=\"#000000\" d=\"M0 0 l5 5 Z\"/></svg>"), "does not read")
	assert_string_contains(_refused(head + "<path d=\"M 0 0 L 1\"/></svg>"), "L needs 2 numbers")
	assert_string_contains(_refused("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"1 0 10 10\"></svg>"),
			"not starting at 0 0")
	assert_eq(_refused(head + "<path d=\"M 0 0 L 1 1 C 1 2 3 4 5 6 Z\" fill=\"#ff0000\"/></svg>"), "")
