extends GutTest
## The three surfaces: what a PDF holds, what a recording holds, and that the
## canvas draws without errors.

const A5 := Vector2(419.527559, 595.275591)


func _face(file: String) -> FontFace:
	var bytes := FileAccess.get_file_as_bytes(FontSet.pinned_folder().path_join(file))
	if bytes.is_empty():
		pending("%s is not checked out" % file)
		return null
	return FontFace.new(bytes, file)


func _picture() -> Image:
	var picture := Image.create(4, 3, false, Image.FORMAT_RGBA8)
	picture.fill(Color(0.2, 0.4, 0.6, 0.5))
	return picture


## One page using every operation.
func _draw_page(surface: DrawingSurface, script: FontFace, cursive: FontFace) -> void:
	surface.save()
	surface.fill_color(Color(0.5, 0.2, 0.1))
	surface.stroke_color(Color(0.1, 0.2, 0.3))
	surface.line_width(0.8)
	surface.fill_alpha(0.4)
	surface.path([["m", 10.0, 10.0], ["l", 100.0, 10.0], ["c", 120.0, 10.0, 120.0, 40.0, 100.0, 40.0], ["h"]],
			true, true, false)
	surface.path([["re", 20.0, 60.0, 50.0, 30.0]], false, true, true)
	surface.restore()
	surface.image("picture", _picture(), 200.0, 300.0, 40.0, 30.0)
	script.draw(surface, 50.0, 500.0, "la Lune", 16.0, Color.BLACK)
	cursive.draw(surface, 50.0, 450.0, "toujours", 14.6, Color(0.2, 0.2, 0.6), [1], Color(0.6, 0.6, 0.6),
			{}, null, [Color(0.3, 0.3, 0.3), 0.5])
	surface.transform([1.0, 0.0, 0.0, 1.0, 5.0, 5.0])
	surface.end_page()


func test_pdf_is_well_formed() -> void:
	var script := _face(FontSet.SCRIPT)
	var cursive := _face(FontSet.CURSIVE)
	if script == null or cursive == null:
		return
	var surface := PdfSurface.new(A5, {"Title": "Test – élève"})
	_draw_page(surface, script, cursive)
	_draw_page(surface, script, cursive)
	var bytes := surface.finish()
	# Compressed streams hold NUL bytes, which would end the string early.
	var readable := bytes.duplicate()
	for at in readable.size():
		if readable[at] == 0 or readable[at] > 126:
			readable[at] = 32
	var text := readable.get_string_from_ascii()
	assert_true(text.begins_with("%PDF-1.7"), "a PDF 1.7 header")
	assert_true(text.strip_edges().ends_with("%%EOF"), "an end of file")
	# Every cross-reference entry points at its object.
	var xref := text.rfind("\nxref\n") + 1
	var lines := text.substr(xref).split("\n")
	var count := int(lines[1].split(" ")[1])
	for number in range(1, count):
		var offset := int(lines[2 + number].split(" ")[0])
		assert_eq(bytes.slice(offset, offset + str(number).length() + 6).get_string_from_ascii(), "%d 0 obj" % number,
				"object %d where the cross-reference says" % number)
	assert_eq(text.count("/Type /Page "), 2, "two pages")
	assert_eq(text.count("/Subtype /Type0"), 2, "two fonts, each embedded once")
	assert_eq(text.count("/FontFile3"), 1, "Mulish embedded as CFF")
	assert_eq(text.count("/FontFile2"), 1, "Marelle embedded as TrueType")
	assert_eq(text.count("/Subtype /Image"), 2, "the picture once, and its transparency")
	var file := FileAccess.open("user://surfaces.pdf", FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


func test_recording_holds_every_operation_in_order() -> void:
	var script := _face(FontSet.SCRIPT)
	var cursive := _face(FontSet.CURSIVE)
	if script == null or cursive == null:
		return
	var surface := RecordingSurface.new(A5)
	_draw_page(surface, script, cursive)
	var operations: Array = surface.finished_pages()[0]
	assert_eq(operations.map(func(operation: Dictionary) -> String: return operation["op"]),
			["save", "fill_color", "stroke_color", "line_width", "fill_alpha", "path", "path", "restore", "image",
			"glyphs", "glyphs", "transform"])
	assert_eq(operations[9]["font"], FontSet.SCRIPT)
	var outline := Color(0.3, 0.3, 0.3)
	assert_eq(operations[10]["outline"], [[outline.r, outline.g, outline.b], 0.5])
	assert_eq(surface.finished_pages().size(), 1)
	var parsed: Dictionary = JSON.parse_string(surface.to_json())
	assert_eq(parsed["pages"].size(), 1, "the JSON holds the finished page")


func test_canvas_draws_every_operation() -> void:
	var script := _face(FontSet.SCRIPT)
	var cursive := _face(FontSet.CURSIVE)
	if script == null or cursive == null:
		return
	var item := RenderingServer.canvas_item_create()
	var surface := CanvasSurface.new(A5, item, 2.0, Vector2(10, 10))
	_draw_page(surface, script, cursive)
	_draw_page(surface, script, cursive)
	var art := BookletArt.vector("kalulu-logo")
	assert_eq(art.error, "")
	surface.vector(art, 10.0, 580.0, 120.0)
	assert_almost_eq(surface.page_offset(1), A5.y * 2.0 + 16.0, 1e-6, "the second page below the first")
	RenderingServer.free_rid(item)
