extends SceneTree
## Replays a drawing recorded by ../record.py into a PDF of Godot's own making.
##
##     godot --headless --path prototype/godot --script res://replay.gd -- \
##         <drawing.json> <out.pdf> <glyphs.json> [shaping size]
##
## Text arrives unshaped: it is shaped here, by TextServer, and its glyphs are
## placed exactly as the generator's Face.draw places them. The glyphs used are
## written to glyphs.json, for comparing with what HarfBuzz gave the generator.

const PdfWriter := preload("res://pdf_writer.gd")
const Shaper := preload("res://shaper.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var started := Time.get_ticks_msec()
	var drawing: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	# 0: shape each font at its units per em, where TextServer's positions are
	# HarfBuzz's to the unit.
	var size: int = int(args[3]) if args.size() > 3 else 0
	var shaper := Shaper.new()
	var pdf := PdfWriter.new(Vector2(drawing["page_size"][0], drawing["page_size"][1]))
	pdf.info = drawing["info"]
	var folder: String = drawing["fonts_folder"]
	var shaped: Array = []
	var shaping_ms := 0
	for page: Array in drawing["pages"]:
		for op: Dictionary in page:
			match op["op"]:
				"save":
					pdf.save()
				"restore":
					pdf.restore()
				"transform":
					pdf.transform(op["matrix"])
				"fill_color":
					pdf.fill_color(op["rgb"])
				"stroke_color":
					pdf.stroke_color(op["rgb"])
				"line_width":
					pdf.line_width(op["width"])
				"fill_alpha":
					pdf.fill_alpha(op["alpha"])
				"path":
					pdf.path(op["code"], op["stroke"] != 0, op["fill"] != 0, op["even_odd"])
				"image":
					pdf.image(op["file"], op["x"], op["y"], op["width"], op["height"])
				"text":
					var before := Time.get_ticks_msec()
					var glyphs := shaper.shape(folder.path_join(op["font"]), op["text"], int(op["units"]),
							size if size > 0 else int(op["units"]))
					shaping_ms += Time.get_ticks_msec() - before
					shaped.append(glyphs)
					_draw_text(pdf, folder.path_join(op["font"]), op, glyphs)
				_:
					push_error("unknown operation %s" % op["op"])
		pdf.end_page()
	var bytes := pdf.finish()
	var out := FileAccess.open(args[1], FileAccess.WRITE)
	out.store_buffer(bytes)
	out.close()
	var glyph_file := FileAccess.open(args[2], FileAccess.WRITE)
	glyph_file.store_string(JSON.stringify(shaped))
	glyph_file.close()
	print("%d pages, %d texts shaped at %d px (0: units per em) in %d ms, %d ms in all, %d bytes" % [
			drawing["pages"].size(), shaped.size(), size, shaping_ms, Time.get_ticks_msec() - started, bytes.size()])
	quit()


## Face.draw, glyph for glyph: colours by cluster (grey first), letter and
## word spacing, the outline of a letter to trace over.
func _draw_text(pdf: PdfWriter, font: String, op: Dictionary, glyphs: Array) -> void:
	var text: String = op["text"]
	var size: float = op["size"]
	var units: float = op["units"]
	var x: float = op["x"]
	var y: float = op["y"]
	# JSON numbers arrive as floats, and 3.0 is not in an array of 3.
	var grey: Array = op["grey"].map(func(cluster: float) -> int: return int(cluster))
	var colors: Dictionary = op["colors"]
	var spacing: Variant = op["spacing"]
	var placed: Array = []
	var pen := 0.0  # font units, as HarfBuzz advances
	var extra := 0.0  # points the spacing has added so far
	var previous_cluster := -1
	for glyph: Array in glyphs:
		var cluster: int = glyph[1]
		var advance: float = glyph[2] / units
		var color: Variant = op["color"]
		if grey.has(cluster) and op["grey_color"] != null:
			color = op["grey_color"]
		elif colors.has(str(cluster)):
			color = colors[str(cluster)]
		var gx: float = x + (pen + float(glyph[3])) / units * size + extra
		var gy: float = y + float(glyph[4]) / units * size
		var letter := text[cluster] if cluster != previous_cluster else ""
		placed.append([glyph[0], gx, gy, color, letter])
		pdf.advance(font, glyph[0], glyph[2])
		pen += glyph[2]
		previous_cluster = cluster
		if spacing != null:
			var wanted := (advance + float(spacing[0])) * size
			if text[cluster] == " " and spacing[1] != null:
				wanted = float(spacing[1]) * size
			extra += wanted - advance * size
	pdf.glyphs(font, size, placed, op["outline"])
