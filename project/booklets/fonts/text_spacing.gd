class_name TextSpacing
extends RefCounted
## Letter and word spacing, in em: ``tracking`` added after every glyph,
## ``space`` the whole advance of a space (null keeps the font's).

var tracking: float
var space: Variant


func _init(added: float = 0.0, space_advance: Variant = null) -> void:
	tracking = added
	space = space_advance
