extends Node2D
class_name YarnWrapPoint

## Explicit marker for scenery that can safely act as a yarn pivot.
@export_range(8.0, 48.0, 1.0) var yarn_wrap_radius: float = 20.0


func _ready() -> void:
	add_to_group("yarn_wrap_points")
