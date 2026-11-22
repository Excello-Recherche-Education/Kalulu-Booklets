class_name RecordingSurface
extends DrawingSurface
## Records every operation instead of drawing it, page by page, for the parity
## checks against the Python generator: the same drawing must come out of both,
## operation for operation (Kalulu-Main's docs/BOOKLETS-GODOT-PORT.md, section 5).
##
## ``pages`` is an array of pages, each an array of operations, each a
## dictionary with its "op" and its arguments. Colours are [r, g, b].

var pages: Array = [[]]


func save() -> void:
	_add({"op": "save"})


func restore() -> void:
	_add({"op": "restore"})


func transform(matrix: Array) -> void:
	_add({"op": "transform", "matrix": matrix.duplicate()})


func fill_color(color: Color) -> void:
	_add({"op": "fill_color", "rgb": _rgb(color)})


func stroke_color(color: Color) -> void:
	_add({"op": "stroke_color", "rgb": _rgb(color)})


func line_width(width: float) -> void:
	_add({"op": "line_width", "width": width})


func fill_alpha(alpha: float) -> void:
	_add({"op": "fill_alpha", "alpha": alpha})


func path(code: Array, stroke: bool, fill: bool, even_odd: bool = false) -> void:
	_add({"op": "path", "code": code.duplicate(true), "stroke": stroke, "fill": fill, "even_odd": even_odd})


func image(key: String, _picture: Image, x: float, y: float, width: float, height: float) -> void:
	_add({"op": "image", "key": key, "x": x, "y": y, "width": width, "height": height})


func glyphs(face: FontFace, size: float, placed: Array, outline: Variant = null) -> void:
	var recorded: Array = []
	for glyph: Array in placed:
		recorded.append([glyph[0], glyph[1], glyph[2], _rgb(glyph[3]), glyph[4]])
	_add({"op": "glyphs", "font": face.file, "size": size, "glyphs": recorded,
			"outline": null if outline == null else [_rgb(outline[0]), outline[1]]})


func end_page() -> void:
	pages.append([])


## The pages finished so far: the last, still empty, one is left out.
func finished_pages() -> Array:
	return pages.slice(0, pages.size() - 1) if pages.back().is_empty() else pages


func to_json() -> String:
	return JSON.stringify({"page_size": [page_size.x, page_size.y], "pages": finished_pages()})


func _add(operation: Dictionary) -> void:
	pages.back().append(operation)


static func _rgb(color: Color) -> Array:
	return [color.r, color.g, color.b]
