extends Sprite2D
class_name Signpost

## A wooden signpost on a night map with a short line of text above it (Simplified Chinese).
## The text is lifted so the night tint does not make it unreadable.

@export var text: String = ""

var label: Label


func _ready() -> void:
	label = Label.new()
	label.name = "Text"
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color("#fff2c8"))
	label.add_theme_color_override("font_outline_color", Color("#2a1c10"))
	label.add_theme_constant_override("outline_size", 5)
	label.light_mask = 0
	label.z_index = 5
	add_child(label)
	label.reset_size()
	label.position = Vector2(-label.size.x / 2.0 / scale.x, -42.0 / scale.y - 6.0)
	label.scale = Vector2.ONE / scale
	label.position = Vector2(-label.size.x / 2.0, -54.0) / scale
	_apply_lift.call_deferred()


func _apply_lift() -> void:
	for atmosphere in get_tree().get_nodes_in_group("night_atmosphere"):
		if atmosphere.has_method("lift_modulate"):
			label.modulate = atmosphere.lift_modulate()
