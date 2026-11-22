class_name OpenTypeInfo
extends RefCounted
## Reads the few numbers a PDF needs out of an OpenType or TrueType file:
## its units per em, bounding box, ascent, descent, x-height, cap height and
## PostScript name, and whether its outlines are CFF or TrueType.
##
## Godot's Font answers some of these at a pixel size, rounded; the file
## answers them exactly, in font units, which is what the layout measures in.

var data: PackedByteArray
var tables: Dictionary = {}  # tag -> [offset, length]
var units_per_em: int
var bbox: Array[int] = [0, 0, 0, 0]  # xMin, yMin, xMax, yMax
var ascent: int
var descent: int
var x_height: int
var cap_height: int  # 0 when the font does not say
var italic_angle: float
var postscript_name: String
var is_cff: bool


func _init(bytes: PackedByteArray) -> void:
	data = bytes
	var count := _u16(4)
	for index in count:
		var record := 12 + 16 * index
		tables[data.slice(record, record + 4).get_string_from_ascii()] = [_u32(record + 8), _u32(record + 12)]
	is_cff = tables.has("CFF ") or tables.has("CFF2")
	var head: int = tables["head"][0]
	units_per_em = _u16(head + 18)
	bbox = [_i16(head + 36), _i16(head + 38), _i16(head + 40), _i16(head + 42)]
	var hhea: int = tables["hhea"][0]
	ascent = _i16(hhea + 4)
	descent = _i16(hhea + 6)
	if tables.has("OS/2"):
		var os2: int = tables["OS/2"][0]
		if _u16(os2) >= 2:
			x_height = _i16(os2 + 86)
			cap_height = _i16(os2 + 88)
	if tables.has("post"):
		var post: int = tables["post"][0]
		italic_angle = _i16(post + 4) + _u16(post + 6) / 65536.0
	postscript_name = _name(6)


## A name record: Windows Unicode first, then Macintosh Roman.
func _name(id: int) -> String:
	if not tables.has("name"):
		return ""
	var start: int = tables["name"][0]
	var count := _u16(start + 2)
	var strings := start + _u16(start + 4)
	var fallback := ""
	for index in count:
		var record := start + 6 + 12 * index
		if _u16(record + 6) != id:
			continue
		var length := _u16(record + 8)
		var offset := strings + _u16(record + 10)
		var platform := _u16(record)
		if platform == 3:
			var text := ""
			for at in range(offset, offset + length, 2):
				text += char(_u16(at))
			return text
		if platform == 1:
			fallback = data.slice(offset, offset + length).get_string_from_ascii()
	return fallback


func _u16(at: int) -> int:
	return (data[at] << 8) | data[at + 1]


func _i16(at: int) -> int:
	var value := _u16(at)
	return value - 65536 if value >= 32768 else value


func _u32(at: int) -> int:
	return (_u16(at) << 16) | _u16(at + 2)
