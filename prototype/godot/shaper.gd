extends RefCounted
## Shapes text with Godot's own TextServer, which is HarfBuzz, and gives the
## glyphs back in font units, as the generator's fonts.py does with uharfbuzz.
##
## Sub-pixel positioning is on so that Godot does not round advances to whole
## pixels. Shaped at its units per em, a font's positions are HarfBuzz's to the
## unit (measured on fr_FR booklet 1: no difference at all); at 64 px they are
## off by up to 0.44 unit, at 256 px by 0.1. A whole booklet shapes in under a
## second at full size.

const SIZE := 64

var _server: TextServer = TextServerManager.get_primary_interface()
var _fonts: Dictionary = {}  # path -> FontFile


func font(path: String) -> FontFile:
	if not _fonts.has(path):
		var file := FontFile.new()
		file.data = FileAccess.get_file_as_bytes(path)
		file.hinting = TextServer.HINTING_NONE
		file.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_ONE_QUARTER
		file.allow_system_fallback = false
		file.generate_mipmaps = false
		_fonts[path] = file
	return _fonts[path]


## [glyph index, cluster, x advance, x offset, y offset] per glyph, in font
## units, y up. The cluster is the index in ``text`` of the letter the glyph
## comes from.
func shape(path: String, text: String, units: int, size: int = SIZE) -> Array:
	if text.is_empty():
		return []
	var shaped := _server.create_shaped_text()
	_server.shaped_text_add_string(shaped, text, font(path).get_rids(), size)
	_server.shaped_text_shape(shaped)
	var scale := float(units) / size
	var glyphs: Array = []
	for glyph: Dictionary in _server.shaped_text_get_glyphs(shaped):
		var offset: Vector2 = glyph["offset"]
		var index: int = glyph["index"]
		# A letter no font has is drawn by TextServer as a box of its own, with
		# the character code as its index and no font: that is .notdef here.
		if not (glyph["font_rid"] as RID).is_valid():
			index = 0
		glyphs.append([index, glyph["start"], glyph["advance"] * scale, offset.x * scale, -offset.y * scale])
	_server.free_rid(shaped)
	return glyphs
