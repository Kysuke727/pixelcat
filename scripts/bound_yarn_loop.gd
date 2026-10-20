extends StaticBody2D
class_name BoundYarnLoop

@export var collision_radius: float = 2.5
@export var lifetime: float = 1.5

var loop_paths: Array[PackedVector2Array] = []
var remaining_time: float = 0.0
var _shapes: Array[CollisionShape2D] = []
var _lines: Array[Line2D] = []


func setup(paths: Array[PackedVector2Array], duration: float, radius: float) -> void:
	loop_paths.clear()
	for path in paths:
		if path.size() >= 4:
			loop_paths.append(path.duplicate())
	lifetime = maxf(duration, 0.0)
	collision_radius = maxf(radius, 0.5)
	remaining_time = lifetime


func _ready() -> void:
	top_level = true
	global_position = Vector2.ZERO
	collision_layer = 8
	collision_mask = 0
	add_to_group("yarn_barriers")
	add_to_group("persistent_yarn_loops")
	process_physics_priority = -15
	for loop_path in loop_paths:
		var closed_path := loop_path.duplicate()
		if closed_path[0].distance_to(closed_path[closed_path.size() - 1]) > 0.05:
			closed_path.append(closed_path[0])
		var line := Line2D.new()
		line.name = "PersistentLoopVisual%d" % _lines.size()
		line.width = collision_radius * 2.0
		line.default_color = Color(1.0, 0.45, 0.72, 0.9)
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.z_index = 8
		add_child(line)
		_lines.append(line)
		for index in range(closed_path.size() - 1):
			var start := closed_path[index]
			var end := closed_path[index + 1]
			var segment := end - start
			if segment.length_squared() <= 0.001:
				continue
			line.add_point(start)
			var shape_node := CollisionShape2D.new()
			shape_node.name = "LoopEdge%d" % _shapes.size()
			var capsule := CapsuleShape2D.new()
			capsule.radius = collision_radius
			capsule.height = segment.length() + collision_radius * 2.0
			shape_node.shape = capsule
			shape_node.position = (start + end) * 0.5
			shape_node.rotation = segment.angle() - PI * 0.5
			add_child(shape_node)
			_shapes.append(shape_node)
		if not closed_path.is_empty():
			line.add_point(closed_path[closed_path.size() - 1])
	if loop_paths.is_empty() or lifetime <= 0.0:
		queue_free()


func _physics_process(delta: float) -> void:
	remaining_time = maxf(remaining_time - delta, 0.0)
	if remaining_time <= 0.0:
		queue_free()
