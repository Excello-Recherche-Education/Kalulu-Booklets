class_name CanvasSurface
extends DrawingSurface
## Draws the pages into a canvas item, for the Prof Tool's live preview: the
## same layout code as the PDF, so the preview is the booklet.
##
## A page is drawn ``scale`` pixels per point, its top left at ``origin``, the
## next one ``gap`` pixels below it. Glyphs are drawn by TextServer at a whole
## pixel size near their size on screen, then scaled to the exact size, so
## they stay sharp at any zoom. Paths are flattened to polygons: the layout
## draws rectangles, rounded rectangles, ellipses and lines, none with holes.
## Vector art is rasterised from its SVG source by Godot's own SVG loader, once
## per size, since its even-odd holes are beyond a canvas polygon.

## Segments a curve is flattened into, per 10 pixels of its control polygon.
const _CURVE_DETAIL := 1.0

var canvas_item: RID
var scale: float
var origin: Vector2
var gap: float

var _page := 0
var _matrix := Transform2D.IDENTITY  # user space -> page points (PDF, y up)
var _fill := Color.BLACK
var _stroke := Color.BLACK
var _width := 1.0
var _alpha := 1.0
var _stack: Array = []
var _textures: Dictionary = {}  # key -> ImageTexture


func _init(size: Vector2, item: RID, pixels_per_point: float = 1.0, at: Vector2 = Vector2.ZERO,
		page_gap: float = 16.0) -> void:
	super(size)
	canvas_item = item
	scale = pixels_per_point
	origin = at
	gap = page_gap


func save() -> void:
	_stack.append([_matrix, _fill, _stroke, _width, _alpha])


func restore() -> void:
	var state: Array = _stack.pop_back()
	_matrix = state[0]
	_fill = state[1]
	_stroke = state[2]
	_width = state[3]
	_alpha = state[4]


func transform(matrix: Array) -> void:
	_matrix = _matrix * Transform2D(Vector2(matrix[0], matrix[1]), Vector2(matrix[2], matrix[3]),
			Vector2(matrix[4], matrix[5]))


func fill_color(color: Color) -> void:
	_fill = color


func stroke_color(color: Color) -> void:
	_stroke = color


func line_width(width: float) -> void:
	_width = width


func fill_alpha(alpha: float) -> void:
	_alpha = alpha


func path(code: Array, stroke: bool, fill: bool, _even_odd: bool = false) -> void:
	var to_canvas := _page_to_canvas() * _matrix
	var outlines := _flatten(code, to_canvas)
	if fill:
		var color := Color(_fill, _fill.a * _alpha)
		for outline: Dictionary in outlines:
			var points: PackedVector2Array = outline["points"]
			if points.size() < 3:
				continue
			var triangles := Geometry2D.triangulate_polygon(points)
			if triangles.is_empty():
				continue
			var colors := PackedColorArray()
			colors.resize(points.size())
			colors.fill(color)
			RenderingServer.canvas_item_add_triangle_array(canvas_item, triangles, points, colors)
	if stroke:
		var width := _width * _scale_of(to_canvas)
		for outline: Dictionary in outlines:
			var points: PackedVector2Array = outline["points"]
			if outline["closed"] and points.size() > 2:
				points.append(points[0])
			if points.size() >= 2:
				RenderingServer.canvas_item_add_polyline(canvas_item, points, PackedColorArray([_stroke]), width, true)


func image(key: String, picture: Image, x: float, y: float, width: float, height: float) -> void:
	if not _textures.has(key):
		_textures[key] = ImageTexture.create_from_image(picture)
	_draw_texture(_textures[key], x, y, width, height)


func glyphs(face: FontFace, size: float, placed: Array, outline: Variant = null) -> void:
	var server := TextServerManager.get_primary_interface()
	var font: RID = face.font.get_rids()[0]
	var to_canvas := _page_to_canvas() * _matrix
	for glyph: Array in placed:
		# Glyph space: pixels at ``pixels``, y down from the baseline.
		var local := to_canvas * Transform2D(0.0, Vector2(1.0, -1.0), 0.0, Vector2(glyph[1], glyph[2]))
		var on_screen := size * _scale_of(local)
		var pixels := maxi(1, roundi(on_screen))
		var drawn := local.scaled_local(Vector2.ONE * (size / pixels))
		RenderingServer.canvas_item_add_set_transform(canvas_item, drawn)
		var color: Color = glyph[3]
		color.a *= _alpha
		if outline != null:
			var outline_pixels := maxi(1, roundi(float(outline[1]) * _scale_of(to_canvas) * pixels / maxf(on_screen, 0.001)))
			server.font_draw_glyph_outline(font, canvas_item, pixels, outline_pixels, Vector2.ZERO, glyph[0], outline[0])
		server.font_draw_glyph(font, canvas_item, pixels, Vector2.ZERO, glyph[0], color)
	RenderingServer.canvas_item_add_set_transform(canvas_item, Transform2D.IDENTITY)


func vector(art: VectorArt, left: float, top: float, width: float) -> void:
	var height := width * art.height / art.width
	var on_screen := width * _scale_of(_page_to_canvas() * _matrix)
	# Rasterised a little larger than shown, in steps, so a zoom reuses it.
	var raster_scale := snappedf(maxf(on_screen / art.width, 0.05) * 1.25, 0.05)
	var key := "%s@%s" % [art.key, raster_scale]
	if not _textures.has(key):
		var picture := Image.new()
		picture.load_svg_from_buffer(art.source, raster_scale)
		_textures[key] = ImageTexture.create_from_image(picture)
	_draw_texture(_textures[key], left, top - height, width, height)


func end_page() -> void:
	_page += 1
	_matrix = Transform2D.IDENTITY
	_stack.clear()


## How far below ``origin`` page ``index`` starts, in pixels.
func page_offset(index: int) -> float:
	return index * (page_size.y * scale + gap)


func _page_to_canvas() -> Transform2D:
	return Transform2D(Vector2(scale, 0.0), Vector2(0.0, -scale),
			origin + Vector2(0.0, page_offset(_page) + page_size.y * scale))


func _draw_texture(texture: Texture2D, x: float, y: float, width: float, height: float) -> void:
	# The unit square, y down, onto the picture's place: its top left is (x, y + height).
	var placed := _page_to_canvas() * _matrix * Transform2D(Vector2(width, 0.0), Vector2(0.0, -height),
			Vector2(x, y + height))
	RenderingServer.canvas_item_add_set_transform(canvas_item, placed)
	RenderingServer.canvas_item_add_texture_rect(canvas_item, Rect2(0.0, 0.0, 1.0, 1.0), texture.get_rid(), false,
			Color(1.0, 1.0, 1.0, _alpha))
	RenderingServer.canvas_item_add_set_transform(canvas_item, Transform2D.IDENTITY)


## The subpaths of ``code``, in canvas pixels: {"points", "closed"} each.
func _flatten(code: Array, to_canvas: Transform2D) -> Array:
	var outlines: Array = []
	var points := PackedVector2Array()
	var closed := false
	var current := Vector2.ZERO
	var start := Vector2.ZERO
	for step: Array in code:
		match step[0]:
			"m":
				if points.size() > 0:
					outlines.append({"points": points, "closed": closed})
				current = Vector2(step[1], step[2])
				start = current
				points = PackedVector2Array([to_canvas * current])
				closed = false
			"l":
				current = Vector2(step[1], step[2])
				points.append(to_canvas * current)
			"c":
				var control1 := to_canvas * Vector2(step[1], step[2])
				var control2 := to_canvas * Vector2(step[3], step[4])
				var end := to_canvas * Vector2(step[5], step[6])
				var begin := to_canvas * current
				var length := begin.distance_to(control1) + control1.distance_to(control2) + control2.distance_to(end)
				var segments := clampi(ceili(length / 10.0 * _CURVE_DETAIL), 2, 64)
				for index in range(1, segments + 1):
					var t := float(index) / segments
					points.append(begin.bezier_interpolate(control1, control2, end, t))
				current = Vector2(step[5], step[6])
			"h":
				closed = true
				current = start
			"re":
				if points.size() > 0:
					outlines.append({"points": points, "closed": closed})
				var corner := Vector2(step[1], step[2])
				var size := Vector2(step[3], step[4])
				points = PackedVector2Array([to_canvas * corner, to_canvas * (corner + Vector2(size.x, 0.0)),
						to_canvas * (corner + size), to_canvas * (corner + Vector2(0.0, size.y))])
				outlines.append({"points": points, "closed": true})
				points = PackedVector2Array()
				current = corner
				start = corner
	if points.size() > 0:
		outlines.append({"points": points, "closed": closed})
	return outlines


static func _scale_of(matrix: Transform2D) -> float:
	return sqrt(absf(matrix.determinant()))
