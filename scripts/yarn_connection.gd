extends Node2D
class_name YarnConnection

enum WrapState { SEEKING_SUPPORT, WRAPPED, WOUND, TAUT, BOUND }

@export_category("Connection")
@export var slow_multiplier: float = 0.5
@export var slow_duration: float = 3.0
@export var bind_duration: float = 1.5
@export var maximum_duration: float = 10.0
@export var maximum_length: float = 0.0 # 0 = no connection-length limit
@export var cooldown_reduction_on_cut: float = 1.5

@export_category("Wrap Detection")
@export_range(180.0, 360.0) var required_wrap_angle_degrees: float = 270.0
@export var minimum_wrap_radius: float = 22.0
@export var minimum_pivot_contact_radius: float = 18.0
@export var minimum_player_step: float = 6.0
@export var maximum_player_sample_step: float = 64.0
@export var maximum_sample_angle_degrees: float = 100.0
@export var path_clearance: float = 1.0

@export_category("Tension — tune in playtests")
@export var required_tension_extension: float = 24.0
@export var required_pull_distance: float = 20.0

@export_category("Debug")
@export var show_debug_status: bool = true

var player: Node2D
var target: Node2D
var combat: Node
var lifetime_left: float = 0.0
var wrap_pivot: Node2D
var wrap_state: WrapState = WrapState.SEEKING_SUPPORT
var trail_points: Array[Vector2] = []
var path_points: Array[Vector2] = []
var wrap_contact_history: Array[Vector2] = []
var wrap_angle_history: Array[float] = []
var accumulated_wrap_angle: float = 0.0
var wrap_contact_radius: float = 0.0
var wrap_player_radius_at_contact: float = 0.0
var wrap_path_length_at_contact: float = 0.0
var routed_path_length_at_wound: float = 0.0
var player_radius_at_wound: float = 0.0
var player_position_at_wound: Vector2 = Vector2.ZERO
var pivot_position_at_wound: Vector2 = Vector2.ZERO
var tension_value: float = 0.0
var path_valid: bool = true
var is_wrapped: bool = false
var winding_complete: bool = false
var is_taut: bool = false
var loop_bound: bool = false
var valid_movement_this_frame: bool = false
var cut_reward_claimed: bool = false
var finished: bool = false
var owner_scene: Node
var last_bind_failure_reason: String = "寻找可缠绕支点"
var _last_observed_player_position: Vector2 = Vector2.ZERO
var _last_pivot_position: Vector2 = Vector2.ZERO
var _pending_wrap_angle_degrees: float = 0.0
var _pending_player_travel: float = 0.0
var _dynamic_pivot: bool = false
var _last_player_discontinuity_version: int = -1
var wrap_side_sign: float = 0.0
var _wrap_route_seeded: bool = false
var _wrap_seed_target_side: float = 1.0
var _wrap_seed_player_side: float = 1.0
var _wrap_seed_arc_direction: float = 1.0

@onready var tether_line: Line2D = $TetherLine
@onready var trail_line: Line2D = $TrailLine
@onready var debug_status: Label = $DebugStatus
@onready var pivot_marker: Polygon2D = $PivotMarker
@onready var anchor_knot: Polygon2D = $AnchorKnot


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
		_last_observed_player_position = player.global_position
		_last_player_discontinuity_version = _get_player_discontinuity_version()
		trail_points.append(player.global_position)
	if is_instance_valid(target) and target.has_method("apply_yarn_slow"):
		target.apply_yarn_slow(slow_duration, slow_multiplier)
	_update_visuals()


func _process(delta: float) -> void:
	if finished:
		return
	if not _connection_endpoints_are_valid():
		last_bind_failure_reason = "锚定目标或玩家已失效"
		_finish()
		return
	lifetime_left = maxf(lifetime_left - delta, 0.0)
	if lifetime_left <= 0.0:
		last_bind_failure_reason = "连接超时"
		_finish()
		return
	if maximum_length > 0.0 and player.global_position.distance_to(target.global_position) > maximum_length:
		last_bind_failure_reason = "超过连接最大距离"
		_finish()
		return
	if is_wrapped and not _is_valid_support(wrap_pivot):
		_reset_wrap_state("动态支点已死亡或静态支点已移除")
	if not is_wrapped:
		_try_acquire_support()
	_update_player_trail()
	var continuous_player_motion := _update_wrap_angle()
	if continuous_player_motion:
		_update_tension_and_bind()
	_update_visuals()


func _connection_endpoints_are_valid() -> bool:
	return (
		is_instance_valid(player)
		and is_instance_valid(target)
		and is_instance_valid(owner_scene)
		and get_tree().current_scene == owner_scene
		and (not player.has_method("is_alive") or player.is_alive())
		and (not target.has_method("is_alive") or target.is_alive())
	)


func _update_player_trail() -> void:
	var current := player.global_position
	if trail_points.is_empty() or trail_points.back().distance_to(current) >= minimum_player_step:
		trail_points.append(current)
		while trail_points.size() > 256:
			trail_points.remove_at(1)


func _try_acquire_support() -> void:
	var rope_start := player.global_position
	var rope_end := target.global_position
	var candidates: Array[Node2D] = []
	for candidate in get_tree().get_nodes_in_group("yarn_wrap_points"):
		if candidate is Node2D and _is_valid_support(candidate):
			candidates.append(candidate)
	for candidate in get_tree().get_nodes_in_group("enemies"):
		if candidate is Node2D and candidate != target and _is_valid_support(candidate):
			candidates.append(candidate)

	var nearest_support: Node2D
	var nearest_distance := INF
	for candidate in candidates:
		var radius := _get_support_radius(candidate)
		var distance := _distance_to_segment(_get_support_center(candidate), rope_start, rope_end)
		if distance <= radius and distance < nearest_distance:
			nearest_support = candidate
			nearest_distance = distance
	if is_instance_valid(nearest_support):
		wrap_pivot = nearest_support
		_dynamic_pivot = nearest_support.is_in_group("enemies")
		wrap_contact_radius = _get_support_radius(nearest_support)
		is_wrapped = true
		wrap_state = WrapState.WRAPPED
		_last_pivot_position = _get_support_center(wrap_pivot)
		_pending_wrap_angle_degrees = 0.0
		_pending_player_travel = 0.0
		wrap_side_sign = 0.0
		_wrap_route_seeded = false
		wrap_contact_history.clear()
		wrap_angle_history.clear()
		_wrap_route_seeded = false
		wrap_contact_history.append((player.global_position - _last_pivot_position).normalized())
		wrap_player_radius_at_contact = player.global_position.distance_to(_last_pivot_position)
		wrap_path_length_at_contact = _routed_path_length()
		last_bind_failure_reason = "已接触支点，继续绕支点移动"
		return

	var obstruction := _ray_hit(rope_start, rope_end, [player, target])
	if obstruction.is_empty():
		path_valid = true
		last_bind_failure_reason = "毛线尚未接触可缠绕支点"
	else:
		path_valid = false
		last_bind_failure_reason = "毛线被未配置为支点的障碍物挡住"


func _is_valid_support(candidate: Node2D) -> bool:
	if not is_instance_valid(candidate) or candidate == target:
		return false
	if candidate.is_in_group("enemies"):
		return not candidate.has_method("is_alive") or candidate.is_alive()
	return candidate.is_in_group("yarn_wrap_points")


func _get_support_radius(candidate: Node2D) -> float:
	var radius_variant: Variant = candidate.get("yarn_wrap_radius")
	var configured_radius := minimum_pivot_contact_radius
	if radius_variant != null and typeof(radius_variant) in [TYPE_FLOAT, TYPE_INT]:
		configured_radius = maxf(float(radius_variant), 1.0)
	for shape_node in candidate.find_children("*", "CollisionShape2D", true, false):
		var collision_shape := shape_node as CollisionShape2D
		if collision_shape == null or collision_shape.disabled or not collision_shape.get_parent() is PhysicsBody2D:
			continue
		if collision_shape.shape is CircleShape2D:
			var scale := collision_shape.global_scale.abs()
			var physical_radius := (collision_shape.shape as CircleShape2D).radius * maxf(scale.x, scale.y)
			configured_radius = maxf(configured_radius, physical_radius)
	return configured_radius


func _get_support_center(candidate: Node2D) -> Vector2:
	# Collision shapes can be offset from their owning node. Use the physical
	# obstacle center consistently for routing, winding, and tension geometry.
	if not is_instance_valid(candidate):
		return Vector2.ZERO
	for shape_node in candidate.find_children("*", "CollisionShape2D", true, false):
		var shape := shape_node as CollisionShape2D
		if shape != null and not shape.disabled and shape.shape is CircleShape2D and shape.get_parent() is PhysicsBody2D:
			return shape.global_position
	return candidate.global_position


func _distance_to_segment(point: Vector2, start: Vector2, end: Vector2) -> float:
	var segment := end - start
	var length_squared := segment.length_squared()
	if length_squared <= 0.001:
		return point.distance_to(start)
	var along := clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * along)


func _directed_arc_delta(start_angle: float, end_angle: float, direction: float) -> float:
	if direction > 0.0:
		return fposmod(end_angle - start_angle, TAU)
	if direction < 0.0:
		return -fposmod(start_angle - end_angle, TAU)
	return wrapf(end_angle - start_angle, -PI, PI)


func _history_wrap_angle_degrees() -> float:
	var total := 0.0
	for delta_degrees in wrap_angle_history:
		total += delta_degrees
	return total


func _update_wrap_angle() -> bool:
	valid_movement_this_frame = false
	if not is_wrapped or not _is_valid_support(wrap_pivot):
		return true
	var discontinuity_version := _get_player_discontinuity_version()
	if discontinuity_version != _last_player_discontinuity_version:
		_last_player_discontinuity_version = discontinuity_version
		_reset_wrap_state("检测到复活或位置跳转，绕行与张力基准已重置")
		return false
	if not _validate_current_path():
		accumulated_wrap_angle = 0.0
		_pending_wrap_angle_degrees = 0.0
		_pending_player_travel = 0.0
		wrap_contact_history.clear()
		wrap_angle_history.clear()
		winding_complete = false
		is_taut = false
		wrap_state = WrapState.WRAPPED
		tension_value = 0.0
		last_bind_failure_reason = "毛线路径无效，绕行进度已清除"
		_last_observed_player_position = player.global_position
		return true
	var current_pivot_position := _get_support_center(wrap_pivot)
	var current_relative := player.global_position - current_pivot_position
	var player_step := player.global_position.distance_to(_last_observed_player_position)
	if player_step > maximum_player_sample_step:
		# A discontinuous move invalidates the winding and its tension baseline;
		# merely skipping this angle sample would leave a stale pull threshold.
		_reset_wrap_state("检测到非连续位移，绕行与张力基准已重置")
		_last_pivot_position = current_pivot_position
		_last_observed_player_position = player.global_position
		_last_player_discontinuity_version = discontinuity_version
		return false
	# Compare both positions against the pivot's current transform. This filters
	# pivot-only motion while preserving genuine player movement at any frame rate.
	var previous_relative := _last_observed_player_position - current_pivot_position
	if player_step > 0.001 and previous_relative.length() >= maxf(minimum_wrap_radius, wrap_contact_radius) and current_relative.length() >= maxf(minimum_wrap_radius, wrap_contact_radius):
		var angular_step := rad_to_deg(previous_relative.angle_to(current_relative))
		if absf(angular_step) <= maximum_sample_angle_degrees:
			_pending_player_travel += player_step
			_pending_wrap_angle_degrees += angular_step
		else:
			_pending_player_travel = 0.0
			_pending_wrap_angle_degrees = 0.0
	if _pending_player_travel >= minimum_player_step:
		var committed_angle := _pending_wrap_angle_degrees
		accumulated_wrap_angle += committed_angle
		if absf(_pending_wrap_angle_degrees) > 0.1:
			valid_movement_this_frame = true
			wrap_side_sign = signf(accumulated_wrap_angle) if absf(accumulated_wrap_angle) > 0.1 else signf(_pending_wrap_angle_degrees)
			wrap_contact_history.append(current_relative.normalized())
			wrap_angle_history.append(committed_angle)
			while wrap_contact_history.size() > 1024:
				wrap_contact_history.remove_at(0)
			while wrap_angle_history.size() > 1024:
				wrap_angle_history.remove_at(0)
		_pending_player_travel = 0.0
		_pending_wrap_angle_degrees = 0.0
	if player_step >= minimum_player_step:
		trail_points.append(player.global_position)
		while trail_points.size() > 256:
			trail_points.remove_at(1)
	_last_pivot_position = current_pivot_position
	_last_observed_player_position = player.global_position
	var effective_wrap_angle := _history_wrap_angle_degrees() + _pending_wrap_angle_degrees
	if absf(effective_wrap_angle) > 0.1:
		wrap_side_sign = signf(effective_wrap_angle)
	if absf(effective_wrap_angle) >= required_wrap_angle_degrees:
		if absf(_pending_wrap_angle_degrees) > 0.001:
			wrap_angle_history.append(_pending_wrap_angle_degrees)
		accumulated_wrap_angle = effective_wrap_angle
		wrap_contact_history.append(current_relative.normalized())
		_pending_wrap_angle_degrees = 0.0
		_pending_player_travel = 0.0
		wrap_side_sign = signf(accumulated_wrap_angle)
	if winding_complete and absf(effective_wrap_angle) < required_wrap_angle_degrees:
		winding_complete = false
		is_taut = false
		tension_value = 0.0
		wrap_state = WrapState.WRAPPED
		last_bind_failure_reason = "反向移动已解除部分缠绕进度"
	if not winding_complete and absf(effective_wrap_angle) >= required_wrap_angle_degrees:
		winding_complete = true
		wrap_state = WrapState.WOUND
		player_position_at_wound = player.global_position
		pivot_position_at_wound = _get_support_center(wrap_pivot)
		player_radius_at_wound = player.global_position.distance_to(pivot_position_at_wound)
		routed_path_length_at_wound = _routed_path_length()
		last_bind_failure_reason = "缠绕完成，继续拉紧毛线"
	return true


func _get_player_discontinuity_version() -> int:
	if not is_instance_valid(player):
		return -1
	var value: Variant = player.get("position_discontinuity_version")
	return int(value) if value != null else 0


func _update_tension_and_bind() -> void:
	path_valid = _validate_current_path()
	if not path_valid:
		is_taut = false
		last_bind_failure_reason = "毛线路径被未配置支点的障碍物阻断"
		return
	if not winding_complete or not is_wrapped:
		return
	var route_extension := _routed_path_length() - routed_path_length_at_wound
	var radial_pull := player.global_position.distance_to(_get_support_center(wrap_pivot)) - player_radius_at_wound
	var pull_vector := player.global_position - player_position_at_wound
	var away_from_pivot := (player_position_at_wound - pivot_position_at_wound).normalized()
	var effective_pull := pull_vector.dot(away_from_pivot)
	tension_value = maxf(maxf(route_extension, radial_pull), 0.0)
	is_taut = tension_value >= required_tension_extension and radial_pull >= required_pull_distance and effective_pull >= required_pull_distance
	if not is_taut:
		wrap_state = WrapState.WOUND
		last_bind_failure_reason = "已缠绕，等待拉紧（张力 %.1f/%.1f px）" % [tension_value, required_tension_extension]
		return
	wrap_state = WrapState.TAUT
	_bind_wrapped_targets()


func _bind_wrapped_targets() -> void:
	if loop_bound:
		return
	var targets: Array[Node2D] = [target]
	if _dynamic_pivot and wrap_pivot != target:
		targets.append(wrap_pivot)
	var bound_count := 0
	for enemy in targets:
		if not is_instance_valid(enemy) or not enemy.has_method("apply_yarn_bind"):
			continue
		if bool(enemy.apply_yarn_bind(bind_duration)):
			bound_count += 1
	loop_bound = bound_count > 0
	if loop_bound:
		wrap_state = WrapState.BOUND
		last_bind_failure_reason = "束缚已触发" if bound_count == targets.size() else "部分目标处于束缚免疫期"
	else:
		last_bind_failure_reason = "目标处于束缚免疫期或已被束缚"


func _validate_current_path() -> bool:
	if not is_wrapped:
		var direct_obstruction := _ray_hit(player.global_position, target.global_position, [player, target])
		if direct_obstruction.is_empty():
			return true
		return false
	var excluded: Array[Node] = [player, target]
	var support_center := _get_support_center(wrap_pivot)
	if player.global_position.distance_to(support_center) <= wrap_contact_radius:
		return false
	if target.global_position.distance_to(support_center) <= wrap_contact_radius:
		return false
	var path := _build_routed_path()
	if path.size() < 2:
		return false
	for index in range(path.size() - 1):
		if not _ray_hit(path[index], path[index + 1], excluded).is_empty():
			return false
	return true


func _ray_hit(start: Vector2, end: Vector2, exclude_nodes: Array[Node]) -> Dictionary:
	if start.distance_squared_to(end) <= 0.001:
		return {}
	var query := PhysicsRayQueryParameters2D.create(start, end)
	# Check both world geometry (layer 1) and enemy bodies (layer 2); keep the
	# support collider in the query so a bad routed segment cannot pass through it.
	query.collision_mask = 3
	var exclusions: Array[RID] = []
	for node in exclude_nodes:
		if node is CollisionObject2D and is_instance_valid(node):
			exclusions.append((node as CollisionObject2D).get_rid())
	query.exclude = exclusions
	return get_world_2d().direct_space_state.intersect_ray(query)


func _routed_path_length() -> float:
	var points := _build_routed_path()
	var length := 0.0
	for index in range(points.size() - 1):
		length += points[index].distance_to(points[index + 1])
	return length


func _build_routed_path() -> PackedVector2Array:
	var points := PackedVector2Array()
	if not is_instance_valid(player) or not is_instance_valid(target):
		return points
	points.append(player.global_position)
	if not is_wrapped or not _is_valid_support(wrap_pivot):
		points.append(target.global_position)
		return points
	var center := _get_support_center(wrap_pivot)
	var radius := wrap_contact_radius + maxf(path_clearance, 0.0)
	var player_offset := player.global_position - center
	var target_offset := target.global_position - center
	if player_offset.length() <= radius or target_offset.length() <= radius:
		points.append(target.global_position)
		return points
	var player_phi := player_offset.angle()
	var target_phi := target_offset.angle()
	var player_alpha := acos(clampf(radius / player_offset.length(), -1.0, 1.0))
	var target_alpha := acos(clampf(radius / target_offset.length(), -1.0, 1.0))
	var effective_winding := _history_wrap_angle_degrees() + _pending_wrap_angle_degrees
	if _wrap_route_seeded and absf(effective_winding) > 0.1 and not wrap_contact_history.is_empty():
		var initial_player_angle := wrap_contact_history[0].angle()
		var seed_alpha := acos(clampf(radius / maxf(wrap_player_radius_at_contact, radius + 0.01), -1.0, 1.0))
		var seed_player_angle := initial_player_angle + _wrap_seed_player_side * seed_alpha
		# Unwrap the cat's current polar angle from the stored signed movement
		# history. Using a shortest-arc remainder here double-counted a full turn
		# whenever radial movement shifted the tangent angle across the modulo seam.
		var unwrapped_player_angle := initial_player_angle + deg_to_rad(effective_winding)
		var expected_polar_angle := wrapf(unwrapped_player_angle, -PI, PI)
		var geometry_correction := wrapf(player_phi - expected_polar_angle, -PI, PI)
		# Preserve complete active turns but align the tangent with the current
		# endpoint geometry after a dynamic support has moved.
		var current_start_angle := unwrapped_player_angle + geometry_correction + _wrap_seed_player_side * player_alpha
		points.append(center + Vector2.from_angle(current_start_angle) * radius)
		var history_delta := seed_player_angle - current_start_angle
		var history_subdivisions := maxi(1, ceili(absf(history_delta) / deg_to_rad(12.0)))
		for step in range(1, history_subdivisions + 1):
			points.append(center + Vector2.from_angle(current_start_angle + history_delta * float(step) / float(history_subdivisions)) * radius)
		var current_target_tangent_angle := target_phi + _wrap_seed_target_side * target_alpha
		var base_delta := _directed_arc_delta(seed_player_angle, current_target_tangent_angle, _wrap_seed_arc_direction)
		var base_subdivisions := maxi(1, ceili(absf(base_delta) / deg_to_rad(12.0)))
		for step in range(1, base_subdivisions + 1):
			points.append(center + Vector2.from_angle(seed_player_angle + base_delta * float(step) / float(base_subdivisions)) * radius)
		points.append(target.global_position)
		return points
	var best_start := Vector2.ZERO
	var best_end := Vector2.ZERO
	var best_side := 1.0
	var best_length := INF
	var directions: Array[float] = []
	if absf(wrap_side_sign) > 0.1:
		directions.append(wrap_side_sign)
	else:
		directions.append(1.0)
		directions.append(-1.0)
	for player_angle in [player_phi - player_alpha, player_phi + player_alpha]:
		for target_angle in [target_phi - target_alpha, target_phi + target_alpha]:
			var start_tangent := center + Vector2.from_angle(player_angle) * radius
			var end_tangent := center + Vector2.from_angle(target_angle) * radius
			for candidate_side in directions:
				var candidate_arc := _directed_arc_delta(player_angle, target_angle, candidate_side)
				var candidate_length := player.global_position.distance_to(start_tangent) + absf(candidate_arc) * radius + end_tangent.distance_to(target.global_position)
				if candidate_length < best_length:
					best_start = start_tangent
					best_end = end_tangent
					best_side = candidate_side
					best_length = candidate_length
	if best_length == INF:
		points.append(target.global_position)
		return points
	points.append(best_start)
	var start_angle := (best_start - center).angle()
	var end_angle := (best_end - center).angle()
	var arc_delta := _directed_arc_delta(start_angle, end_angle, best_side)
	if not _wrap_route_seeded:
		_wrap_route_seeded = true
		_wrap_seed_target_side = signf(wrapf(end_angle - target_phi, -PI, PI))
		_wrap_seed_player_side = signf(wrapf(start_angle - player_phi, -PI, PI))
		_wrap_seed_arc_direction = best_side
	if absf(arc_delta) < 0.001:
		arc_delta = best_side * TAU
	var arc_subdivisions := maxi(8, ceili(absf(arc_delta) / deg_to_rad(12.0)))
	for arc_step in range(1, arc_subdivisions):
		points.append(center + Vector2.from_angle(start_angle + arc_delta * float(arc_step) / float(arc_subdivisions)) * radius)
	points.append(best_end)
	points.append(target.global_position)
	return points


func _update_visuals() -> void:
	path_points.clear()
	var full_path := _build_routed_path()
	if path_valid:
		for point in full_path:
			path_points.append(point)
	else:
		var excluded: Array[Node] = [player, target]
		for index in range(full_path.size() - 1):
			path_points.append(full_path[index])
			var obstruction := _ray_hit(full_path[index], full_path[index + 1], excluded)
			if not obstruction.is_empty():
				path_points.append(obstruction["position"])
				break
		if path_points.size() == full_path.size():
			path_points.append(full_path[full_path.size() - 1])
	var local_path := PackedVector2Array()
	for point in path_points:
		local_path.append(to_local(point))
	tether_line.points = local_path
	tether_line.default_color = Color(1.0, 0.25, 0.48, 1.0) if not path_valid else Color(1.0, 0.45, 0.72, 0.9)
	anchor_knot.position = to_local(target.global_position)
	var local_trail := PackedVector2Array()
	for point in trail_points:
		local_trail.append(to_local(point))
	trail_line.points = local_trail
	trail_line.visible = show_debug_status and is_wrapped and local_trail.size() > 1
	pivot_marker.visible = show_debug_status and is_wrapped and is_instance_valid(wrap_pivot)
	if pivot_marker.visible:
		pivot_marker.position = to_local(_get_support_center(wrap_pivot))
	if not is_instance_valid(debug_status) or not is_instance_valid(player):
		return
	debug_status.visible = show_debug_status
	debug_status.position = to_local(player.global_position) + Vector2(-85.0, -68.0)
	var target_name := str(target.name) if is_instance_valid(target) else "无"
	var pivot_name := str(wrap_pivot.name) if is_wrapped and is_instance_valid(wrap_pivot) else "未接触"
	var state_names: Array[String] = ["寻找支点", "已接触支点", "已缠绕·等待拉紧", "拉紧中", "束缚触发"]
	var status_name: String = state_names[wrap_state]
	var status_text := "锚定：%s | 支点：%s\n路径节点：%d | 角度：%.0f°/%.0f°\n有效移动：%s | 已缠绕：%s\n已拉紧：%s | 张力：%.1f/%.1f px\n状态：%s" % [
		target_name,
		pivot_name,
		path_points.size(),
		absf(accumulated_wrap_angle),
		required_wrap_angle_degrees,
		"是" if valid_movement_this_frame else "否",
		"是" if winding_complete else "否",
		"是" if is_taut else "否",
		tension_value,
		required_tension_extension,
		status_name
	]
	if not last_bind_failure_reason.is_empty() and not loop_bound:
		status_text += "\n原因：" + last_bind_failure_reason
	debug_status.text = status_text
	debug_status.add_theme_color_override("font_color", Color(1.0, 0.92, 0.65))
	debug_status.add_theme_font_size_override("font_size", 10)
	debug_status.z_index = 20


func get_debug_status_text() -> String:
	return debug_status.text if is_instance_valid(debug_status) else ""


func cut_by_player() -> bool:
	if finished or cut_reward_claimed:
		return false
	cut_reward_claimed = true
	if is_instance_valid(combat) and combat.has_method("on_yarn_cut_reward"):
		combat.on_yarn_cut_reward(cooldown_reduction_on_cut)
	last_bind_failure_reason = "玩家主动剪断毛线"
	_finish()
	return true


func finish_naturally() -> void:
	_finish()


func _reset_wrap_state(reason: String) -> void:
	wrap_pivot = null
	_dynamic_pivot = false
	is_wrapped = false
	wrap_state = WrapState.SEEKING_SUPPORT
	accumulated_wrap_angle = 0.0
	_pending_wrap_angle_degrees = 0.0
	_pending_player_travel = 0.0
	wrap_side_sign = 0.0
	_wrap_route_seeded = false
	wrap_contact_history.clear()
	wrap_angle_history.clear()
	wrap_contact_radius = 0.0
	wrap_player_radius_at_contact = 0.0
	wrap_path_length_at_contact = 0.0
	routed_path_length_at_wound = 0.0
	winding_complete = false
	is_taut = false
	loop_bound = false
	path_valid = true
	tension_value = 0.0
	trail_points.clear()
	trail_points.append(player.global_position)
	_last_observed_player_position = player.global_position
	last_bind_failure_reason = reason


func _finish() -> void:
	if finished:
		return
	finished = true
	if is_instance_valid(combat) and combat.has_method("on_yarn_connection_finished"):
		combat.on_yarn_connection_finished(self)
	queue_free()
