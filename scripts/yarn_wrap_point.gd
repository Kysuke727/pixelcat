extends Node2D
class_name YarnWrapPoint

## Explicit marker for scenery that can safely act as a yarn pivot.
@export_range(8.0, 48.0, 1.0) var yarn_wrap_radius: float = 11.0
@export_range(4.0, 32.0, 1.0) var entity_collision_radius: float = 10.0


func _ready() -> void:
	add_to_group("yarn_wrap_points")
	var collision_shape := get_node_or_null("StaticBody2D/CollisionShape2D") as CollisionShape2D
	if is_instance_valid(collision_shape) and collision_shape.shape is CircleShape2D:
		collision_shape.shape = collision_shape.shape.duplicate()
		(collision_shape.shape as CircleShape2D).radius = entity_collision_radius
