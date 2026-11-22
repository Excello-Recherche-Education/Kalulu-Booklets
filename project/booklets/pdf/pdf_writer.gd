class_name PdfWriter
extends RefCounted
## A small PDF 1.7 writer: vector paths, colours and fill opacity, PNG images
## with their transparency, and text drawn glyph by glyph in embedded fonts.
##
## Fonts are embedded whole (Godot cannot subset a font): a CFF-flavoured
## OpenType file as FontFile3 /OpenType, a TrueType one as FontFile2, both as
## Identity-H composite fonts, so text is written as glyph indices -- exactly
## what shaping returns -- and a ToUnicode map keeps it copyable.
##
## Coordinates are PDF points, origin at the bottom left, as ReportLab's.
## Fonts and images are named by a key the caller chooses: a font file's bytes
## or a picture are embedded once, however often they are drawn.

## What the file's /Producer says.
const PRODUCER := "Kalulu-Booklets"

var page_size: Vector2
var info: Dictionary = {}

var _objects: Array[PackedByteArray] = []  # object n is _objects[n - 1]
var _page_ids: Array[int] = []
var _pages_id: int
var _resources_id: int
var _ops := PackedStringArray()
var _fonts: Dictionary = {}  # key -> font entry
var _images: Dictionary = {}  # key -> [object id, name]
var _alphas: Dictionary = {}  # alpha -> [object id, name]


func _init(size: Vector2) -> void:
	page_size = size
	_pages_id = _reserve()
	_resources_id = _reserve()


# --- Drawing ---------------------------------------------------------------------

func save() -> void:
	_ops.append("q")


func restore() -> void:
	_ops.append("Q")


func transform(m: Array) -> void:
	_ops.append("%s %s %s %s %s %s cm" % m.map(num))


func fill_color(rgb: Array) -> void:
	_ops.append("%s %s %s rg" % rgb.map(num))


func stroke_color(rgb: Array) -> void:
	_ops.append("%s %s %s RG" % rgb.map(num))


func line_width(width: float) -> void:
	_ops.append("%s w" % num(width))


func fill_alpha(alpha: float) -> void:
	var key := num(alpha)
	if not _alphas.has(key):
		var id := _reserve()
		_put(id, "<< /Type /ExtGState /ca %s >>" % key)
		_alphas[key] = [id, "GS%d" % _alphas.size()]
	_ops.append("/%s gs" % _alphas[key][1])


## ``code``: [operator, numbers...] with PDF's path operators (m l c v y h re).
func path(code: Array, stroke: bool, fill: bool, even_odd: bool) -> void:
	for step: Array in code:
		var numbers := step.slice(1).map(num)
		numbers.append(step[0])
		_ops.append(" ".join(numbers))
	if stroke and fill:
		_ops.append("B*" if even_odd else "B")
	elif fill:
		_ops.append("f*" if even_odd else "f")
	elif stroke:
		_ops.append("S")
	else:
		_ops.append("n")


func image(key: String, picture: Image, x: float, y: float, width: float, height: float) -> void:
	_ops.append("q %s 0 0 %s %s %s cm /%s Do Q" % [num(width), num(height), num(x), num(y), _image(key, picture)[1]])


## Makes a font file known under ``key``, before its glyphs are drawn.
func add_font(key: String, bytes: PackedByteArray) -> void:
	if not _fonts.has(key):
		_fonts[key] = {"id": _reserve(), "name": "F%d" % (_fonts.size() + 1), "bytes": bytes,
				"info": OpenTypeInfo.new(bytes), "widths": {}, "unicode": {}}


## ``placed``: [glyph index, x, y, rgb, text, advance] each, positioned on the
## page; ``text`` is what the glyph stands for, for copying, and ``advance`` its
## advance in font units, for the width table. ``rgb``: [r, g, b], 0 to 1.
## ``outline``: [rgb, width] strokes each glyph around its fill.
func glyphs(key: String, size: float, placed: Array, outline: Variant = null) -> void:
	var font: Dictionary = _fonts[key]
	if outline != null:
		line_width(outline[1])
	_ops.append("BT")
	_ops.append("/%s %s Tf" % [font["name"], num(size)])
	if outline != null:
		_ops.append("2 Tr")
		stroke_color(outline[0])
	var current: Variant = null
	for glyph: Array in placed:
		var index: int = glyph[0]
		if glyph[3] != current:
			fill_color(glyph[3])
			current = glyph[3]
		_ops.append("1 0 0 1 %s %s Tm <%04X> Tj" % [num(glyph[1]), num(glyph[2]), index])
		if not font["unicode"].has(index):
			font["unicode"][index] = glyph[4]
		if not font["widths"].has(index):
			font["widths"][index] = float(glyph[5]) * 1000.0 / font["info"].units_per_em
	_ops.append("ET")


# --- Pages and file ----------------------------------------------------------------

func end_page() -> void:
	var content := _reserve()
	_stream(content, "", "\n".join(_ops).to_utf8_buffer())
	_ops = PackedStringArray()
	var page := _reserve()
	_put(page, "<< /Type /Page /Parent %d 0 R /MediaBox [0 0 %s %s] /Resources %d 0 R /Contents %d 0 R >>"
			% [_pages_id, num(page_size.x), num(page_size.y), _resources_id, content])
	_page_ids.append(page)


func finish() -> PackedByteArray:
	var fonts := PackedStringArray()
	for key: String in _fonts:
		_write_font(_fonts[key])
		fonts.append("/%s %d 0 R" % [_fonts[key]["name"], _fonts[key]["id"]])
	var images := PackedStringArray()
	for key: String in _images:
		images.append("/%s %d 0 R" % [_images[key][1], _images[key][0]])
	var states := PackedStringArray()
	for key: String in _alphas:
		states.append("/%s %d 0 R" % [_alphas[key][1], _alphas[key][0]])
	_put(_resources_id, "<< /ProcSet [/PDF /Text /ImageB /ImageC] /Font << %s >> /XObject << %s >> /ExtGState << %s >> >>"
			% [" ".join(fonts), " ".join(images), " ".join(states)])
	_put(_pages_id, "<< /Type /Pages /Count %d /Kids [%s] >>"
			% [_page_ids.size(), " ".join(_page_ids.map(func(id: int) -> String: return "%d 0 R" % id))])
	var catalog := _reserve()
	_put(catalog, "<< /Type /Catalog /Pages %d 0 R >>" % _pages_id)
	var entries := PackedStringArray()
	for key: String in info:
		entries.append("/%s %s" % [key, _string(info[key])])
	entries.append("/Producer %s" % _string(PRODUCER))
	var info_id := _reserve()
	_put(info_id, "<< %s >>" % " ".join(entries))

	var out := PackedByteArray()
	out.append_array("%PDF-1.7\n%".to_utf8_buffer())
	out.append_array(PackedByteArray([0xE2, 0xE3, 0xCF, 0xD3, 0x0A]))
	var offsets: Array[int] = []
	for index in _objects.size():
		offsets.append(out.size())
		out.append_array(("%d 0 obj\n" % (index + 1)).to_utf8_buffer())
		out.append_array(_objects[index])
		out.append_array("\nendobj\n".to_utf8_buffer())
	var xref := out.size()
	var table := "xref\n0 %d\n0000000000 65535 f \n" % (_objects.size() + 1)
	for offset in offsets:
		table += "%010d 00000 n \n" % offset
	table += "trailer\n<< /Size %d /Root %d 0 R /Info %d 0 R >>\nstartxref\n%d\n%%%%EOF\n" % [
			_objects.size() + 1, catalog, info_id, xref]
	out.append_array(table.to_utf8_buffer())
	return out


# --- Fonts -------------------------------------------------------------------------

func _write_font(font: Dictionary) -> void:
	var font_info: OpenTypeInfo = font["info"]
	var scale := 1000.0 / font_info.units_per_em
	var base := font_info.postscript_name.validate_node_name().replace(" ", "")
	if base.is_empty():
		base = font["name"]
	var file := _reserve()
	if font_info.is_cff:
		_stream(file, "/Subtype /OpenType", font["bytes"])
	else:
		_stream(file, "/Length1 %d" % font["bytes"].size(), font["bytes"])
	var descriptor := _reserve()
	_put(descriptor, ("<< /Type /FontDescriptor /FontName /%s /Flags 32 /FontBBox [%s] /ItalicAngle %s"
			+ " /Ascent %s /Descent %s /CapHeight %s /XHeight %s /StemV 80 /%s %d 0 R >>") % [
			base, " ".join(font_info.bbox.map(func(v: int) -> String: return num(v * scale))),
			num(font_info.italic_angle), num(font_info.ascent * scale), num(font_info.descent * scale),
			num((font_info.cap_height if font_info.cap_height != 0 else font_info.ascent) * scale), num(font_info.x_height * scale),
			"FontFile3" if font_info.is_cff else "FontFile2", file])
	var widths := PackedStringArray()
	var indices: Array = font["widths"].keys()
	indices.sort()
	for index: int in indices:
		widths.append("%d [%s]" % [index, num(font["widths"][index])])
	var descendant := _reserve()
	_put(descendant, ("<< /Type /Font /Subtype /%s /BaseFont /%s /CIDSystemInfo << /Registry (Adobe)"
			+ " /Ordering (Identity) /Supplement 0 >> /FontDescriptor %d 0 R /DW 0 /W [%s]%s >>") % [
			"CIDFontType0" if font_info.is_cff else "CIDFontType2", base, descriptor, " ".join(widths),
			"" if font_info.is_cff else " /CIDToGIDMap /Identity"])
	var to_unicode := _reserve()
	_stream(to_unicode, "", _cmap(font["unicode"]).to_utf8_buffer())
	_put(font["id"], "<< /Type /Font /Subtype /Type0 /BaseFont /%s /Encoding /Identity-H /DescendantFonts [%d 0 R] /ToUnicode %d 0 R >>"
			% [base, descendant, to_unicode])


func _cmap(unicode: Dictionary) -> String:
	var lines := PackedStringArray([
		"/CIDInit /ProcSet findresource begin", "12 dict begin", "begincmap",
		"/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def",
		"/CMapName /Adobe-Identity-UCS def", "/CMapType 2 def",
		"1 begincodespacerange", "<0000> <FFFF>", "endcodespacerange"])
	var entries: Array = unicode.keys().filter(func(index: int) -> bool: return not unicode[index].is_empty())
	entries.sort()
	for start in range(0, entries.size(), 100):
		var block := entries.slice(start, start + 100)
		lines.append("%d beginbfchar" % block.size())
		for index: int in block:
			lines.append("<%04X> <%s>" % [index, _utf16(unicode[index])])
		lines.append("endbfchar")
	lines.append_array(["endcmap", "CMapName currentdict /CMap defineresource pop", "end", "end"])
	return "\n".join(lines)


# --- Images ------------------------------------------------------------------------

func _image(key: String, source: Image) -> Array:
	if not _images.has(key):
		var picture := source.duplicate() as Image
		var transparent := picture.detect_alpha() != Image.ALPHA_NONE
		picture.convert(Image.FORMAT_RGBA8)
		var rgba := picture.get_data()
		var count := picture.get_width() * picture.get_height()
		var rgb := PackedByteArray()
		rgb.resize(count * 3)
		var alpha := PackedByteArray()
		alpha.resize(count)
		for pixel in count:
			rgb[pixel * 3] = rgba[pixel * 4]
			rgb[pixel * 3 + 1] = rgba[pixel * 4 + 1]
			rgb[pixel * 3 + 2] = rgba[pixel * 4 + 2]
			alpha[pixel] = rgba[pixel * 4 + 3]
		var size := "/Width %d /Height %d /BitsPerComponent 8" % [picture.get_width(), picture.get_height()]
		var mask := ""
		if transparent:
			var mask_id := _reserve()
			_stream(mask_id, "/Type /XObject /Subtype /Image %s /ColorSpace /DeviceGray" % size, alpha)
			mask = " /SMask %d 0 R" % mask_id
		var id := _reserve()
		_stream(id, "/Type /XObject /Subtype /Image %s /ColorSpace /DeviceRGB%s" % [size, mask], rgb)
		_images[key] = [id, "Im%d" % _images.size()]
	return _images[key]


# --- Objects -----------------------------------------------------------------------

func _reserve() -> int:
	_objects.append(PackedByteArray())
	return _objects.size()


func _put(id: int, body: String) -> void:
	_objects[id - 1] = body.to_utf8_buffer()


func _stream(id: int, entries: String, data: PackedByteArray) -> void:
	# Godot's DEFLATE mode writes a zlib stream, which is FlateDecode.
	var packed := data.compress(FileAccess.COMPRESSION_DEFLATE)
	var body := ("<< /Length %d /Filter /FlateDecode %s >>\nstream\n" % [packed.size(), entries]).to_utf8_buffer()
	body.append_array(packed)
	body.append_array("\nendstream".to_utf8_buffer())
	_objects[id - 1] = body


## Six decimals: a vector drawing's scale is ~0.08, and four left its far
## edges a tenth of a point off.
static func num(value: float) -> String:
	if absf(value) < 0.0000005:
		return "0"
	return String.num(value, 6)


static func _string(text: String) -> String:
	var plain := true
	for at in text.length():
		if text.unicode_at(at) > 126:
			plain = false
	if plain:
		return "(%s)" % text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
	return "<FEFF%s>" % _utf16(text)


static func _utf16(text: String) -> String:
	var hex := ""
	for at in text.length():
		var code := text.unicode_at(at)
		if code > 0xFFFF:
			code -= 0x10000
			hex += "%04X%04X" % [0xD800 + (code >> 10), 0xDC00 + (code & 0x3FF)]
		else:
			hex += "%04X" % code
	return hex
