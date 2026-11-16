extends Camera2D

## A static camera whose view is identical to having no camera at all (fixed to the
## top-left of the world), used only for screen shake. Later phases can turn this into
## a follow camera for larger maps.
##
## Shake is "trauma"-based: effects add trauma (0..1) via add_trauma(); the offset
## scales with trauma squared and decays quickly. Offsets are whole pixels so the
## pixel art never shimmers.

@export var max_offset: float = 5.0
@export var decay: float = 2.4

var trauma: float = 0.0


func _ready() -> void:
	add_to_group("combat_camera")
	anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	position = Vector2.ZERO
	make_current()


func add_trauma(amount: float) -> void:
	trauma = minf(trauma + maxf(amount, 0.0), 1.0)


func _process(delta: float) -> void:
	if trauma <= 0.0:
		if offset != Vector2.ZERO:
			offset = Vector2.ZERO
		return
	trauma = maxf(trauma - decay * delta, 0.0)
	var strength := trauma * trauma * max_offset
	offset = Vector2(roundf(randf_range(-1.0, 1.0) * strength), roundf(randf_range(-1.0, 1.0) * strength))
