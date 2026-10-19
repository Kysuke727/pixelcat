extends Node2D
class_name YarnConnection

@export var slow_multiplier: float = 0.5
@export var slow_duration: float = 3.0
@export var bind_duration: float = 1.5
@export var maximum_duration: float = 10.0
@export var maximum_length: float = 0.0 # 0 = no connection-length limit
@export var sample_distance: float = 6.0
@export_range(180.0, 360.0) var required_loop_angle_degrees: float = 270.0
@export var minimum_loop_radius: float = 24.0
@export var minimum_loop_perimeter: float = 120.0
@export var minimum_loop_area: float = 450.0
@export var maximum_samples: int = 384
@export var cooldown_reduction_on_cut: float = 1.5

var player: Node2D
var target: Node2D
var combat: Node
var lifetime_left: float
var trail_points: Array[Vector2] = []
var trail_offsets: Array[Vector2] = []
var trail_length: float = 0.0
var accumulated_loop_angle: float = 0.0
var loop_bound: bool = false
var cut_reward_claimed: bool = false
var finished: bool = false
var owner_scene: Node
var last_bind_failure_reason: String = "等待有效移动轨迹"

@export var show_debug_status: bool = true

@onready var tether_line: Line2D = $TetherLine
@onready var trail_line: Line2D = $TrailLine
@onready var debug_status: Label = $DebugStatus


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
	if is_instance_valid(player) and is_instance_valid(target):
		trail_offsets.append(player.global_position - target.global_position)
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
	if lifetime_left <= 0.0 or (maximum_length > 0.0 and player.global_position.distance_to(target.global_position) > maximum_length):
		last_bind_failure_reason = "连接超时" if lifetime_left <= 0.0 else "超过连接最大距离"
		_finish()
		return
	if not _has_clear_line_of_sight():
		last_bind_failure_reason = "目标与玩家之间被障碍物遮挡"
		_finish()
		return
	_sample_player_path()
	_try_close_loop()
	_update_lines()


func _sample_player_path() -> void:
	if trail_offsets.is_empty():
		trail_points.append(player.global_position)
		trail_offsets.append(player.global_position - target.global_position)
		return
	var current := player.global_position
	var current_offset := current - target.global_position
	var previous_offset: Vector2 = trail_offsets.back()
	var segment_length := previous_offset.distance_to(current_offset)
	if segment_length < sample_distance:
		return
	trail_length += segment_length
	trail_points.append(current)
	trail_offsets.append(current_offset)
	if previous_offset.length() >= minimum_loop_radius and current_offset.length() >= minimum_loop_radius:
		accumulated_loop_angle += rad_to_deg(previous_offset.angle_to(current_offset))
	_simplify_last_points()
	while trail_offsets.size() > maxi(maximum_samples, 3):
		trail_points.remove_at(1)
		trail_offsets.remove_at(1)


func _simplify_last_points() -> void:
	while trail_offsets.size() >= 3:
		var count := trail_offsets.size()
		var first: Vector2 = trail_offsets[count - 3]
		var middle: Vector2 = trail_offsets[count - 2]
		var last: Vector2 = trail_offsets[count - 1]
		var first_leg := middle - first
		var second_leg := last - middle
		if first_leg.length_squared() == 0.0 or second_leg.length_squared() == 0.0:
			trail_points.remove_at(count - 2)
			trail_offsets.remove_at(count - 2)
			continue
		var normalized_cross := absf(first_leg.normalized().cross(second_leg.normalized()))
		if normalized_cross < 0.035 and first_leg.dot(second_leg) > 0.0:
			trail_points.remove_at(count - 2)
		else:
			break


func _try_close_loop() -> void:
	if loop_bound:
		return
	if trail_offsets.size() < 4:
		last_bind_failure_reason = "有效轨迹点不足（%d/4）" % trail_offsets.size()
		return
	if trail_length < minimum_loop_perimeter:
		last_bind_failure_reason = "有效轨迹周长不足（%.0f/%.0f px）" % [trail_length, minimum_loop_perimeter]
		return
	if absf(accumulated_loop_angle) < required_loop_angle_degrees:
		last_bind_failure_reason = "绕行角度不足（%.0f°/%.0f°）" % [absf(accumulated_loop_angle), required_loop_angle_degrees]
		return
	var polygon := PackedVector2Array()
	for offset in trail_offsets:
		polygon.append(target.global_position + offset)
	if absf(_signed_polygon_area(polygon)) < minimum_loop_area:
		last_bind_failure_reason = "闭合区域面积不足（%.0f/%.0f px²）" % [absf(_signed_polygon_area(polygon)), minimum_loop_area]
		return
	var bound_count := 0
	var attempted_bind_count := 0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or not enemy.has_method("apply_yarn_bind"):
			continue
		# The tethered target is always a valid bind candidate: at 270° the
		# auto-closing chord can leave the orbit center outside the polygon.
		if enemy == target or Geometry2D.is_point_in_polygon(enemy.global_position, polygon):
			attempted_bind_count += 1
			if bool(enemy.apply_yarn_bind(bind_duration)):
				bound_count += 1
	if bound_count == 0:
		last_bind_failure_reason = "闭合区域内没有可束缚敌人" if attempted_bind_count == 0 else "敌人处于束缚免疫期或已被束缚"
		return
	loop_bound = true
	last_bind_failure_reason = ""


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
	for offset in trail_offsets:
		local_trail.append(to_local(target.global_position + offset))
	trail_line.points = local_trail
	trail_line.visible = local_trail.size() > 1
	if is_instance_valid(debug_status):
		debug_status.visible = show_debug_status
		debug_status.position = to_local(player.global_position) + Vector2(-75.0, -50.0)
		var target_name: String = str(target.name) if is_instance_valid(target) else "无"
		var loop_ready := (
			trail_offsets.size() >= 4
			and trail_length >= minimum_loop_perimeter
			and absf(accumulated_loop_angle) >= required_loop_angle_degrees
			and absf(_signed_polygon_area(_current_polygon())) >= minimum_loop_area
		)
		var status_text := "连接：成功 | 目标：%s\n角度：%.0f° | 轨迹点：%d\n可触发：%s" % [target_name, absf(accumulated_loop_angle), trail_offsets.size(), "是" if loop_ready else "否"]
		if not loop_bound and not last_bind_failure_reason.is_empty():
			status_text += "\n原因：" + last_bind_failure_reason
		debug_status.text = status_text
		debug_status.add_theme_color_override("font_color", Color(1.0, 0.92, 0.65))
		debug_status.add_theme_font_size_override("font_size", 10)
		debug_status.z_index = 20


func _current_polygon() -> PackedVector2Array:
	var polygon := PackedVector2Array()
	for offset in trail_offsets:
		polygon.append(target.global_position + offset)
	return polygon


func get_debug_status_text() -> String:
	return debug_status.text if is_instance_valid(debug_status) else ""


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
