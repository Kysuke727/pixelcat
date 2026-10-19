extends Node2D
class_name YarnConnection

@export var slow_multiplier: float = 0.5
@export var slow_duration: float = 3.0
@export var bind_duration: float = 2.0
@export var maximum_duration: float = 10.0
@export var maximum_length: float = 500.0
@export var sample_distance: float = 6.0
@export var closure_distance: float = 18.0
@export var minimum_loop_perimeter: float = 120.0
@export var minimum_loop_area: float = 450.0
@export var maximum_samples: int = 384
@export var cooldown_reduction_on_cut: float = 1.5

var player: Node2D
var target: Node2D
var combat: Node
var lifetime_left: float
var trail_points: Array[Vector2] = []
var trail_length: float = 0.0
var loop_bound: bool = false
var cut_reward_claimed: bool = false
var finished: bool = false
var owner_scene: Node

@onready var tether_line: Line2D = $TetherLine
@onready var trail_line: Line2D = $TrailLine


func configure(new_player: Node2D, new_target: Node2D, new_combat: Node, settings: Dictionary = {}) -> void:
	player = new_player
	target = new_target
	combat = new_combat
	for property_name in settings:
		set(property_name, settings[property_name])


func _ready() -> void:
	add_to_group("yarn_connections")
	owner_scene = get_tree().current_scene
	lifetime_left = maximum_duration
	if is_instance_valid(player):
		trail_points.append(player.global_position)
	if is_instance_valid(target) and target.has_method("apply_yarn_slow"):
		target.apply_yarn_slow(slow_duration, slow_multiplier)
	_update_lines()


func _process(delta: float) -> void:
	if finished:
		return
	if (
		not is_instance_valid(player)
		or not is_instance_valid(target)
		or not is_instance_valid(owner_scene)
		or get_tree().current_scene != owner_scene
		or (player.has_method("is_alive") and not player.is_alive())
		or (target.has_method("is_alive") and not target.is_alive())
	):
		_finish()
		return
	lifetime_left = maxf(lifetime_left - delta, 0.0)
	if lifetime_left <= 0.0 or player.global_position.distance_to(target.global_position) > maximum_length:
		_finish()
		return
	if not _has_clear_line_of_sight():
		_finish()
		return
	_sample_player_path()
	_update_lines()
	_try_close_loop()


func _sample_player_path() -> void:
	if trail_points.is_empty():
		trail_points.append(player.global_position)
		return
	var current := player.global_position
	var previous: Vector2 = trail_points.back()
	var segment_length := previous.distance_to(current)
	if segment_length < sample_distance:
		return
	trail_length += segment_length
	trail_points.append(current)
	_simplify_last_points()
	while trail_points.size() > maxi(maximum_samples, 3):
		trail_points.remove_at(1)


func _simplify_last_points() -> void:
	while trail_points.size() >= 3:
		var count := trail_points.size()
		var first: Vector2 = trail_points[count - 3]
		var middle: Vector2 = trail_points[count - 2]
		var last: Vector2 = trail_points[count - 1]
		var first_leg := middle - first
		var second_leg := last - middle
		if first_leg.length_squared() == 0.0 or second_leg.length_squared() == 0.0:
			trail_points.remove_at(count - 2)
			continue
		var normalized_cross := absf(first_leg.normalized().cross(second_leg.normalized()))
		if normalized_cross < 0.035 and first_leg.dot(second_leg) > 0.0:
			trail_points.remove_at(count - 2)
		else:
			break


func _try_close_loop() -> void:
	if loop_bound or trail_points.size() < 4 or trail_length < minimum_loop_perimeter:
		return
	var current := player.global_position
	if current.distance_to(trail_points.front()) > closure_distance:
		return
	var polygon := PackedVector2Array(trail_points)
	if absf(_signed_polygon_area(polygon)) < minimum_loop_area:
		return
	if not Geometry2D.is_point_in_polygon(target.global_position, polygon):
		return
	loop_bound = true
	if target.has_method("apply_yarn_bind"):
		target.apply_yarn_bind(bind_duration)


func _signed_polygon_area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	for index in range(polygon.size()):
		var next_index := (index + 1) % polygon.size()
		area += polygon[index].cross(polygon[next_index])
	return area * 0.5


func _update_lines() -> void:
	if not is_instance_valid(player) or not is_instance_valid(target):
		return
	tether_line.points = PackedVector2Array([
			to_local(player.global_position),
			to_local(target.global_position)
	])
	var local_trail := PackedVector2Array()
	for point in trail_points:
		local_trail.append(to_local(point))
	trail_line.points = local_trail
	trail_line.visible = local_trail.size() > 1


func _has_clear_line_of_sight() -> bool:
	var query := PhysicsRayQueryParameters2D.create(player.global_position, target.global_position)
	query.collision_mask = 1
	var exclusions: Array[RID] = []
	if player is CollisionObject2D:
		exclusions.append((player as CollisionObject2D).get_rid())
	if target is CollisionObject2D:
		exclusions.append((target as CollisionObject2D).get_rid())
	query.exclude = exclusions
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func cut_by_player() -> bool:
	if finished or cut_reward_claimed:
		return false
	cut_reward_claimed = true
	if is_instance_valid(combat) and combat.has_method("on_yarn_cut_reward"):
		combat.on_yarn_cut_reward(cooldown_reduction_on_cut)
	_finish()
	return true


func finish_naturally() -> void:
	_finish()


func _finish() -> void:
	if finished:
		return
	finished = true
	if is_instance_valid(combat) and combat.has_method("on_yarn_connection_finished"):
		combat.on_yarn_connection_finished(self)
	queue_free()
