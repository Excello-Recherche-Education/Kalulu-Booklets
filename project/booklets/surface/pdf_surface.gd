class_name PdfSurface
extends DrawingSurface
## Draws the pages into a PDF: what a booklet is written with.

var writer: PdfWriter


func _init(size: Vector2, info: Dictionary = {}) -> void:
	super(size)
	writer = PdfWriter.new(size)
	writer.info = info


func save() -> void:
	writer.save()


func restore() -> void:
	writer.restore()


func transform(matrix: Array) -> void:
	writer.transform(matrix)


func fill_color(color: Color) -> void:
	writer.fill_color(_rgb(color))


func stroke_color(color: Color) -> void:
	writer.stroke_color(_rgb(color))


func line_width(width: float) -> void:
	writer.line_width(width)


func fill_alpha(alpha: float) -> void:
	writer.fill_alpha(alpha)


func path(code: Array, stroke: bool, fill: bool, even_odd: bool = false) -> void:
	writer.path(code, stroke, fill, even_odd)


func image(key: String, picture: Image, x: float, y: float, width: float, height: float) -> void:
	writer.image(key, picture, x, y, width, height)


func glyphs(face: FontFace, size: float, placed: Array, outline: Variant = null) -> void:
	writer.add_font(face.name, face.data)
	var converted: Array = []
	for glyph: Array in placed:
		converted.append([glyph[0], glyph[1], glyph[2], _rgb(glyph[3]), glyph[4], glyph[5]])
	writer.glyphs(face.name, size, converted, null if outline == null else [_rgb(outline[0]), outline[1]])


func end_page() -> void:
	writer.end_page()


## The finished file.
func finish() -> PackedByteArray:
	return writer.finish()


static func _rgb(color: Color) -> Array:
	return [color.r, color.g, color.b]
