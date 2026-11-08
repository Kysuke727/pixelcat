extends Node2D
## Crisp flat-color shadow (not a gradient or blur). Drawn behind the slime body.
@export var width: float = 18.0
@export var height: float = 4.0
var airborne: float = 0.0


func set_airborne(value: float) -> void:
	airborne = clampf(value, 0.0, 1.0)
	scale = Vector2(1.0 - 0.24 * airborne, 1.0 - 0.13 * airborne)
	modulate.a = 0.32 - 0.14 * airborne


func _draw() -> void:
	var vertices := PackedVector2Array()
	for i in range(16):
		var angle := TAU * float(i) / 16.0
		vertices.append(Vector2(cos(angle) * width, sin(angle) * height))
	draw_colored_polygon(vertices, Color(0.13, 0.24, 0.18, 1.0))
