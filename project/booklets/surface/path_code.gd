class_name PathCode
extends RefCounted
## A path's steps for DrawingSurface.path(), built as ReportLab's
## PDFPathObject builds them: the same calls make the same curves, number for
## number, so the booklets' bubbles, stopwatches and rounded boxes stayed the
## ones the Python generator drew.

## The steps so far: [operator, numbers...] each.
var code: Array = []


func move_to(x: float, y: float) -> PathCode:
	code.append(["m", x, y])
	return self


func line_to(x: float, y: float) -> PathCode:
	code.append(["l", x, y])
	return self


func curve_to(x1: float, y1: float, x2: float, y2: float, x3: float, y3: float) -> PathCode:
	code.append(["c", x1, y1, x2, y2, x3, y3])
	return self


func rect(x: float, y: float, width: float, height: float) -> PathCode:
	code.append(["re", x, y, width, height])
	return self


func close() -> PathCode:
	code.append(["h"])
	return self


## ReportLab's ``arcTo``: a line to the arc's start, then the arc of the
## ellipse inscribed in (x1, y1)-(x2, y2), from ``start`` degrees over
## ``extent``, counter-clockwise.
func arc_to(x1: float, y1: float, x2: float, y2: float, start: float = 0.0, extent: float = 90.0) -> PathCode:
	_curves(bezier_arc(x1, y1, x2, y2, start, extent), true)
	return self


## ReportLab's ``ellipse(x, y, width, height)``.
func ellipse(x: float, y: float, width: float, height: float) -> PathCode:
	_curves(bezier_arc(x, y, x + width, y + height, 0.0, 360.0), false)
	return self


## ReportLab's ``circle``.
func circle(x: float, y: float, radius: float) -> PathCode:
	return ellipse(x - radius, y - radius, 2.0 * radius, 2.0 * radius)


## ReportLab's ``roundRect`` with one radius: corners approximately quadrants
## of a circle, from a precomputed multiplier.
func round_rect(x: float, y: float, width: float, height: float, radius: float) -> PathCode:
	var m := 0.4472
	var xlo := minf(x, x + width)
	var xhi := maxf(x, x + width)
	var ylo := minf(y, y + height)
	var yhi := maxf(y, y + height)
	var t := m * radius
	move_to(xlo + radius, ylo)
	line_to(xhi - radius, ylo)
	curve_to(xhi - t, ylo, xhi, ylo + t, xhi, ylo + radius)
	line_to(xhi, yhi - radius)
	curve_to(xhi, yhi - t, xhi - t, yhi, xhi - radius, yhi)
	line_to(xlo + radius, yhi)
	curve_to(xlo + t, yhi, xlo, yhi - t, xlo, yhi - radius)
	line_to(xlo, ylo + radius)
	curve_to(xlo, ylo + t, xlo + t, ylo, xlo + radius, ylo)
	return close()


func _curves(curves: Array, line_first: bool) -> void:
	var first: Array = curves[0]
	if line_first:
		line_to(first[0], first[1])
	else:
		move_to(first[0], first[1])
	for curve: Array in curves:
		curve_to(curve[2], curve[3], curve[4], curve[5], curve[6], curve[7])


## ReportLab's ``pdfgeom.bezierArc``: the Bézier curves of an elliptical arc,
## [x1, y1, x2, y2, x3, y3, x4, y4] each, in its own order of operations.
static func bezier_arc(x1: float, y1: float, x2: float, y2: float, start: float = 0.0,
		extent: float = 90.0) -> Array:
	var left := minf(x1, x2)
	var high := maxf(y1, y2)
	var right := maxf(x1, x2)
	var low := minf(y1, y2)
	var arcs := 1
	var fragment := extent
	if absf(extent) > 90.0:
		arcs = int(ceil(absf(extent) / 90.0))
		fragment = extent / arcs
	var x_cen := (left + right) / 2.0
	var y_cen := (high + low) / 2.0
	var rx := (right - left) / 2.0
	var ry := (low - high) / 2.0
	var half := fragment * PI / 360.0
	var kappa := absf(4.0 / 3.0 * (1.0 - cos(half)) / sin(half))
	var points: Array = []
	for index in arcs:
		var theta0 := (start + index * fragment) * PI / 180.0
		var theta1 := (start + (index + 1) * fragment) * PI / 180.0
		if fragment > 0.0:
			points.append([x_cen + rx * cos(theta0), y_cen - ry * sin(theta0),
					x_cen + rx * (cos(theta0) - kappa * sin(theta0)), y_cen - ry * (sin(theta0) + kappa * cos(theta0)),
					x_cen + rx * (cos(theta1) + kappa * sin(theta1)), y_cen - ry * (sin(theta1) - kappa * cos(theta1)),
					x_cen + rx * cos(theta1), y_cen - ry * sin(theta1)])
		else:
			points.append([x_cen + rx * cos(theta0), y_cen - ry * sin(theta0),
					x_cen + rx * (cos(theta0) + kappa * sin(theta0)), y_cen - ry * (sin(theta0) - kappa * cos(theta0)),
					x_cen + rx * (cos(theta1) - kappa * sin(theta1)), y_cen - ry * (sin(theta1) + kappa * cos(theta1)),
					x_cen + rx * cos(theta1), y_cen - ry * sin(theta1)])
	return points
