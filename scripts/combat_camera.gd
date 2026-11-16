extends Camera2D

## Two modes:
##  * fixed (default): a static camera whose view is identical to having no camera (fixed
##    to the top-left of the world) - used by the single-screen maps, only for shake.
##  * follow_player: follows the cat and never shows anything outside world_rect - used
##    by the bigger scrolling maps.
##
## Shake is "trauma"-based: effects add trauma (0..1) via add_trauma(); the offset
## scales with trauma squared and decays quickly. Offsets are whole pixels so the
## pixel art never shimmers.

@export var max_offset: float = 5.0
@export var decay: float = 2.4
@export var follow_player: bool = false
## With follow_player: the area the camera may show (world coordinates).
@export var world_rect: Rect2 = Rect2()

var trauma: float = 0.0
var _target: Node2D


func _ready() -> void:
	add_to_group("combat_camera")
	if follow_player:
		anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
		position_smoothing_enabled = false
		if world_rect.size != Vector2.ZERO:
			limit_left = int(world_rect.position.x)
			limit_top = int(world_rect.position.y)
			limit_right = int(world_rect.end.x)
			limit_bottom = int(world_rect.end.y)
		_follow()
	else:
		anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
		position = Vector2.ZERO
	make_current()


func add_trauma(amount: float) -> void:
	trauma = minf(trauma + maxf(amount, 0.0), 1.0)


func _process(delta: float) -> void:
	if follow_player:
		_follow()
	if trauma <= 0.0:
		if offset != Vector2.ZERO:
			offset = Vector2.ZERO
		return
	trauma = maxf(trauma - decay * delta, 0.0)
	var strength := trauma * trauma * max_offset
	offset = Vector2(roundf(randf_range(-1.0, 1.0) * strength), roundf(randf_range(-1.0, 1.0) * strength))


func _follow() -> void:
	if not is_instance_valid(_target):
		_target = get_tree().get_first_node_in_group("player") as Node2D
	if is_instance_valid(_target):
		global_position = _target.global_position.round()
