class_name OutlineBounds
extends RefCounted
## The exact bounds of a glyph outline, as TextServer.font_get_glyph_contours()
## returns it: on-curve points, plus the extrema of every quadratic (TrueType)
## or cubic (CFF) segment, as fontTools' BoundsPen computes them. A curve's
## control points can lie outside its ink, so bounding them overestimates:
## Marelle's loops would push a line away from its neighbours for nothing.

const _ON := TextServer.CONTOUR_CURVE_TAG_ON
const _CONIC := TextServer.CONTOUR_CURVE_TAG_OFF_CONIC
const _CUBIC := TextServer.CONTOUR_CURVE_TAG_OFF_CUBIC


## [x min, y min, x max, y max] of ``contours`` ({"points", "contours"}), in
## its own units, or null when it has no points.
static func of(contours: Dictionary) -> Variant:
	var points: PackedVector3Array = contours.get("points", PackedVector3Array())
	var ends: PackedInt32Array = contours.get("contours", PackedInt32Array())
	if points.is_empty():
		return null
	var box := [INF, INF, -INF, -INF]
	var start := 0
	for end in ends:
		_contour(points.slice(start, end + 1), box)
		start = end + 1
	return box if box[0] <= box[2] else null


static func _contour(points: PackedVector3Array, box: Array) -> void:
	var count := points.size()
	if count == 0:
		return
	# Start on an on-curve point; a contour of conic points only starts on the
	# implied point between its last and first.
	var first := -1
	for index in count:
		if int(points[index].z) == _ON:
			first = index
			break
	var start: Vector2
	if first >= 0:
		start = _xy(points[first])
	else:
		first = count - 1
		start = (_xy(points[count - 1]) + _xy(points[0])) / 2.0
	_add(box, start)
	var current := start
	var offs: Array[Vector3] = []
	for step in range(1, count + 1):
		var point := points[(first + step) % count]
		var tag := int(point.z)
		if tag == _ON:
			current = _segment(box, current, offs, _xy(point))
			offs.clear()
		elif tag == _CONIC and not offs.is_empty() and int(offs[0].z) == _CONIC:
			# Two conic points in a row: an on-curve point is implied between them.
			var implied := (_xy(offs[0]) + _xy(point)) / 2.0
			current = _segment(box, current, offs, implied)
			offs = [point]
		else:
			offs.append(point)
	if not offs.is_empty():
		_segment(box, current, offs, start)


## Bounds the segment from ``from`` through the off-curve ``offs`` to ``to``;
## returns ``to``.
static func _segment(box: Array, from: Vector2, offs: Array[Vector3], to: Vector2) -> Vector2:
	_add(box, to)
	if offs.size() == 1:
		_quadratic(box, from, _xy(offs[0]), to)
	elif offs.size() == 2:
		_cubic(box, from, _xy(offs[0]), _xy(offs[1]), to)
	return to


static func _quadratic(box: Array, p0: Vector2, p1: Vector2, p2: Vector2) -> void:
	for axis in 2:
		var denominator := p0[axis] - 2.0 * p1[axis] + p2[axis]
		if denominator == 0.0:
			continue
		var t := (p0[axis] - p1[axis]) / denominator
		if t > 0.0 and t < 1.0:
			var u := 1.0 - t
			_add(box, p0 * u * u + p1 * 2.0 * u * t + p2 * t * t)


static func _cubic(box: Array, p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2) -> void:
	for axis in 2:
		# The derivative, divided by 3: a t² + b t + c.
		var a := -p0[axis] + 3.0 * p1[axis] - 3.0 * p2[axis] + p3[axis]
		var b := 2.0 * (p0[axis] - 2.0 * p1[axis] + p2[axis])
		var c := p1[axis] - p0[axis]
		var roots: Array[float] = []
		if absf(a) < 1e-12:
			if absf(b) > 1e-12:
				roots.append(-c / b)
		else:
			var discriminant := b * b - 4.0 * a * c
			if discriminant >= 0.0:
				var root := sqrt(discriminant)
				roots.append((-b + root) / (2.0 * a))
				roots.append((-b - root) / (2.0 * a))
		for t in roots:
			if t > 0.0 and t < 1.0:
				var u := 1.0 - t
				_add(box, p0 * u * u * u + p1 * 3.0 * u * u * t + p2 * 3.0 * u * t * t + p3 * t * t * t)


static func _add(box: Array, point: Vector2) -> void:
	box[0] = minf(box[0], point.x)
	box[1] = minf(box[1], point.y)
	box[2] = maxf(box[2], point.x)
	box[3] = maxf(box[3], point.y)


static func _xy(point: Vector3) -> Vector2:
	return Vector2(point.x, point.y)
