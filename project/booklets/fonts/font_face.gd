class_name FontFace
extends RefCounted
## A font file, shaped with Godot's TextServer, which is HarfBuzz.
##
## Marelle joins its letters through OpenType rules (contextual alternates,
## chained substitutions), so text is shaped before it is drawn: drawn letter
## by letter, the joins come out wrong. Each glyph is then drawn on its own,
## which is what lets a silent letter be grey in the middle of a joined cursive
## word: shaping says which letter every glyph comes from (its cluster).
##
## Text is shaped at the font's units per em, with quarter-pixel positioning
## and no hinting: there TextServer's positions are HarfBuzz's to the font unit
## (measured on whole booklets, docs/BOOKLETS-GODOT-PORT.md section 2). A
## letter the font cannot print, even from its parts ("á" as "a" and a
## combining accent, as Marelle prints Spanish), comes out as the font's empty
## box, and the face records it in ``missing`` for the build to point out.

## The font file's bytes, embedded whole in a PDF.
var data: PackedByteArray
## Its path inside fonts/, as a pack names it.
var file: String
## One name per file content: two fonts folders never share one.
var name: String
var units: int
var x_height: float  # em
var cap_height: float  # em
## The characters met that this font cannot print, even from their parts.
var missing: Dictionary = {}
var font: FontFile
var info: OpenTypeInfo

var _server: TextServer = TextServerManager.get_primary_interface()
var _shaped: Dictionary = {}  # text -> glyphs
var _inks: Dictionary = {}  # text -> [top, bottom]
var _bounds: Dictionary = {}  # glyph index -> [y min, y max] in font units, or null


func _init(bytes: PackedByteArray, file_name: String) -> void:
	data = bytes
	file = file_name
	info = OpenTypeInfo.new(bytes)
	units = info.units_per_em
	x_height = float(info.x_height) / units
	cap_height = float(info.cap_height) / units
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA1)
	hashing.update(bytes)
	name = "%s-%s" % [file_name.get_file().get_basename(), hashing.finish().hex_encode().left(8)]
	font = FontFile.new()
	font.data = bytes
	font.hinting = TextServer.HINTING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_ONE_QUARTER
	font.allow_system_fallback = false
	font.generate_mipmaps = false


## The glyphs of ``text``: [glyph index, cluster, x, y, advance, advance in
## font units] each. x, y and advance are in em, x from the start of the text;
## the cluster is the index in ``text`` of the letter the glyph comes from.
func shape(text: String) -> Array:
	if _shaped.has(text):
		return _shaped[text]
	var glyphs: Array = []
	# Nothing to shape in an empty text: a table row's empty right cell is one.
	if not text.is_empty():
		var shaped := _server.create_shaped_text()
		_server.shaped_text_add_string(shaped, text, font.get_rids(), units)
		_server.shaped_text_shape(shaped)
		var x := 0.0
		for glyph: Dictionary in _server.shaped_text_get_glyphs(shaped):
			var index: int = glyph["index"]
			var offset: Vector2 = glyph["offset"]
			var advance: float = glyph["advance"]
			# A letter no font has is drawn by TextServer as a box of its own,
			# with the character code as its index and no font: here it is the
			# font's .notdef, with .notdef's advance, as HarfBuzz gives it.
			if not (glyph["font_rid"] as RID).is_valid():
				index = 0
				offset = Vector2.ZERO
				advance = _server.font_get_glyph_advance(font.get_rids()[0], units, 0).x
			if index == 0:
				missing[text[glyph["start"]]] = true
			glyphs.append([index, glyph["start"], (x + offset.x) / units, -offset.y / units, advance / units, advance])
			x += advance
		_server.free_rid(shaped)
	_shaped[text] = glyphs
	return glyphs


## How far the drawn letters of ``text`` reach above and below the baseline,
## in em, accents and loops included: [top, bottom], bottom negative below the
## baseline. Exact: curves are bounded by their extrema, not their control
## points, as fontTools' BoundsPen bounds them.
func ink(text: String) -> Array:
	if _inks.has(text):
		return _inks[text]
	var top := 0.0
	var bottom := 0.0
	for glyph: Array in shape(text):
		var bounds: Variant = glyph_bounds(glyph[0])
		if bounds == null:
			continue
		var offset: float = glyph[3] * units
		top = maxf(top, (bounds[3] + offset) / units)
		bottom = minf(bottom, (bounds[1] + offset) / units)
	_inks[text] = [top, bottom]
	return _inks[text]


## A glyph's ink: [x min, y min, x max, y max] in font units, y up, or null
## for a glyph with no outline (a space).
func glyph_bounds(index: int) -> Variant:
	if not _bounds.has(index):
		var contours := _server.font_get_glyph_contours(font.get_rids()[0], units, index)
		var box: Variant = OutlineBounds.of(contours) if not contours.is_empty() else null
		# TextServer's contours point y down, as the screen does.
		_bounds[index] = null if box == null else [box[0], -box[3], box[2], -box[1]]
	return _bounds[index]


func width(text: String, size: float, spacing: TextSpacing = null) -> float:
	var total := 0.0
	for glyph: Array in shape(text):
		total += glyph[4] * size if spacing == null else _advance(text, glyph, size, spacing)
	return total


## Draws ``text`` with its baseline at ``y``; returns its width. The glyphs of
## the letters in ``grey`` (text positions) are drawn in ``grey_color``, those
## in ``colors`` (text position -> colour) in theirs, grey first. ``spacing``
## sets the letter and word spacing; ``outline`` ([colour, width]) strokes each
## glyph around its fill, as a letter to trace over.
func draw(surface: DrawingSurface, x: float, y: float, text: String, size: float, color: Color,
		grey: Variant = [], grey_color: Variant = null, colors: Dictionary = {},
		spacing: TextSpacing = null, outline: Variant = null) -> float:
	var placed: Array = []
	var extra := 0.0  # what the spacing has added so far
	var advances := 0.0
	var previous_cluster := -1
	for glyph: Array in shape(text):
		var cluster: int = glyph[1]
		var wanted := color
		if grey.has(cluster) and grey_color != null:
			wanted = grey_color
		elif colors.has(cluster):
			wanted = colors[cluster]
		# The letter a glyph stands for, on its cluster's first glyph only.
		var letter := text[cluster] if cluster != previous_cluster else ""
		previous_cluster = cluster
		placed.append([glyph[0], x + glyph[2] * size + extra, y + glyph[3] * size, wanted, letter, glyph[5]])
		advances += glyph[4] * size
		if spacing != null:
			extra += _advance(text, glyph, size, spacing) - glyph[4] * size
	if not placed.is_empty():
		surface.glyphs(self, size, placed, outline)
	return advances + extra


## A glyph's advance with ``spacing``: a space as wide as asked, any other
## glyph followed by the extra letter spacing.
static func _advance(text: String, glyph: Array, size: float, spacing: TextSpacing) -> float:
	if text[glyph[1]] == " " and spacing.space != null:
		return float(spacing.space) * size
	return (glyph[4] + spacing.tracking) * size
