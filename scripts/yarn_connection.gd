extends Node2D
class_name YarnConnection

enum WrapState { SEEKING_SUPPORT, WRAPPED, WOUND, TAUT, BOUND }

const WRAP_ANGLE_EPSILON_DEGREES: float = 0.00001
const MAX_SUPPORT_SOLVE_ITERATIONS: int = 8
const LOOP_GEOMETRY_EPSILON: float = 0.05
static var _next_debug_connection_id: int = 1

@export_category("Connection")
@export var slow_multiplier: float = 0.5
@export var slow_duration: float = 3.0
@export var bind_duration: float = 1.5
@export var maximum_duration: float = 10.0
@export var maximum_length: float = 0.0 # 0 = no connection-length limit
@export var cooldown_reduction_on_cut: float = 1.5
@export_range(0.0, 240.0, 1.0) var initial_slack_length: float = 72.0
@export_range(1.0, 8.0, 0.5) var taut_rope_collision_radius: float = 2.5
@export_range(0.0, 24.0, 1.0) var rope_endpoint_collision_inset: float = 18.0
@export_range(0.0, 4.0, 0.1) var rope_taut_hysteresis: float = 0.5

@export_category("Wrap Detection")
@export_range(180.0, 360.0) var required_wrap_angle_degrees: float = 270.0
@export var minimum_wrap_radius: float = 22.0
@export var minimum_pivot_contact_radius: float = 18.0
@export var minimum_player_step: float = 6.0
@export var maximum_player_sample_step: float = 64.0
@export var maximum_sample_angle_degrees: float = 100.0
@export var path_clearance: float = 1.0
@export_range(0.0, 45.0, 1.0) var support_release_angle_degrees: float = 12.0

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
var wrap_supports: Array[Node2D] = []
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
var rope_physically_taut: bool = false
var loop_bound: bool = false
var valid_movement_this_frame: bool = false
var path_resolution_complete: bool = true
var effective_rope_length: float = 0.0
var actual_routed_length: float = 0.0
var remaining_slack: float = 0.0
var feeding_enabled: bool = true
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
var _secondary_support_arc_directions: Dictionary = {}
var _secondary_support_winding: Dictionary = {}
var _bound_target_ids: Dictionary = {}
var debug_connection_id: int = 0
var _last_tension_player_position: Vector2 = Vector2.ZERO
var _last_tension_pivot_position: Vector2 = Vector2.ZERO
var _last_tension_anchor_position: Vector2 = Vector2.ZERO
var _active_pull_distance: float = 0.0
var _wound_endpoint_segment_length: float = 0.0
var _player_requested_outward_pull: bool = false
var _player_slack_before_step: float = 0.0
var _feed_step_valid: bool = false
var _feed_step_route_length: float = 0.0
var _feed_step_support_ids: Array[int] = []
var _feed_step_support_centers: Dictionary = {}
var _feed_step_anchor_position: Vector2 = Vector2.ZERO
var _rope_barrier_shapes: Array[CollisionShape2D] = []
var _rope_barrier_body: StaticBody2D

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
	# Build/update the physical rope before enemy CharacterBody2D movement.
	process_physics_priority = -10
	set_process(false)
	set_physics_process(true)
	debug_connection_id = _next_debug_connection_id
	_next_debug_connection_id += 1
	add_to_group("yarn_connections")
	owner_scene = get_tree().current_scene
	lifetime_left = maximum_duration
	if is_instance_valid(player):
		_last_observed_player_position = player.global_position
		_last_tension_player_position = player.global_position
		_last_player_discontinuity_version = _get_player_discontinuity_version()
		trail_points.append(player.global_position)
	if is_instance_valid(target) and target.has_method("apply_yarn_slow"):
		target.apply_yarn_slow(slow_duration, slow_multiplier)
	# This is the one-time payout when the projectile sticks. It never grows to
	# follow either endpoint, so active movement can genuinely consume slack.
	effective_rope_length = player.global_position.distance_to(target.global_position) + initial_slack_length
	_rope_barrier_body = StaticBody2D.new()
	_rope_barrier_body.name = "TautRopeBarrier"
	_rope_barrier_body.collision_layer = 4
	_rope_barrier_body.collision_mask = 0
	_rope_barrier_body.set_meta("yarn_connection_id", debug_connection_id)
	_rope_barrier_body.add_to_group("yarn_barriers")
	add_child(_rope_barrier_body)
	print("[Yarn #%d] started anchor=%s" % [debug_connection_id, str(target.name) if is_instance_valid(target) else "<invalid>"])
	_update_visuals()


func _process(delta: float) -> void:
	# Kept as an explicit-call compatibility shim for legacy headless tests.
	# The node's process callback is disabled; live updates run in physics.
	_update_connection(delta, _legacy_test_pull_detected())


func _physics_process(delta: float) -> void:
	_update_connection(delta)


func _update_connection(delta: float, compatibility_active_pull: bool = false) -> void:
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
	if is_wrapped and (not is_instance_valid(wrap_pivot) or not _is_valid_support(wrap_pivot)):
		_log_connection_state("primary pivot %s became invalid; winding reset" % (str(wrap_pivot.name) if is_instance_valid(wrap_pivot) else "<removed>"))
		_reset_wrap_state("动态支点已死亡或静态支点已移除")
	if not is_wrapped:
		_try_acquire_support()
	if is_wrapped:
		path_resolution_complete = _add_contacted_supports()
		if path_resolution_complete:
			_remove_released_secondary_supports()
		else:
			last_bind_failure_reason = "支点路径求解达到迭代上限，本帧暂停判定"
	_update_player_trail()
	var continuous_player_motion := path_resolution_complete and _update_wrap_angle(compatibility_active_pull)
	if continuous_player_motion and path_resolution_complete:
		_update_tension_and_bind(compatibility_active_pull)
	_update_rope_lengths_and_barrier()
	_update_visuals()


func _legacy_test_pull_detected() -> bool:
	if not winding_complete or not is_wrapped or not is_instance_valid(player):
		return false
	var motion := player.global_position - _last_observed_player_position
	if motion.length() <= 0.1 or motion.length() > maximum_player_sample_step:
		return false
	var route := _build_routed_path()
	if route.size() < 2:
		return false
	var outward := (route[0] - route[1]).normalized()
	var projected := motion.dot(outward)
	return projected > 0.1 and projected / maxf(motion.length(), 0.001) >= 0.7


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
		if is_instance_valid(candidate) and candidate is Node2D and _is_valid_support(candidate):
			candidates.append(candidate)
	for candidate in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(candidate) and candidate is Node2D and candidate != target and _is_valid_support(candidate):
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
		wrap_supports.clear()
		wrap_supports.append(nearest_support)
		_secondary_support_arc_directions.clear()
		_secondary_support_winding.clear()
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
		wrap_contact_history.append((player.global_position - _last_pivot_position).normalized())
		wrap_player_radius_at_contact = player.global_position.distance_to(_last_pivot_position)
		wrap_path_length_at_contact = _routed_path_length()
		last_bind_failure_reason = "已接触支点，继续绕支点移动"
		_log_connection_state("acquired primary pivot %s" % str(nearest_support.name))
		return

	var obstruction := _ray_hit(rope_start, rope_end, [player, target])
	if obstruction.is_empty():
		path_valid = true
		last_bind_failure_reason = "毛线尚未接触可缠绕支点"
	else:
		path_valid = false
		last_bind_failure_reason = "毛线被未配置为支点的障碍物挡住"


func _get_support_candidates() -> Array[Node2D]:
	var candidates: Array[Node2D] = []
	for candidate in get_tree().get_nodes_in_group("yarn_wrap_points"):
		if is_instance_valid(candidate) and candidate is Node2D and _is_valid_support(candidate):
			candidates.append(candidate)
	for candidate in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(candidate) and candidate is Node2D and _is_valid_support(candidate):
			candidates.append(candidate)
	return candidates


func _add_contacted_supports() -> bool:
	for iteration in range(MAX_SUPPORT_SOLVE_ITERATIONS):
		var contact := _find_next_contacted_support(_build_routed_path())
		var candidate: Node2D = contact.get("support")
		if not is_instance_valid(candidate):
			path_resolution_complete = true
			path_valid = _validate_current_path()
			return true
		wrap_supports.append(candidate)
		var support_id := candidate.get_instance_id()
		_secondary_support_arc_directions[support_id] = 0.0
		_secondary_support_winding[support_id] = {
			"angle": 0.0,
			"last_player_position": player.global_position,
			"last_support_center": _get_support_center(candidate),
		}
		_rebase_tension_after_topology_change()
		_log_connection_state("added contacted support %s at path segment %d (solve %d)" % [str(candidate.name), int(contact.get("segment", -1)), iteration + 1])
	var remaining_contact := _find_next_contacted_support(_build_routed_path())
	if is_instance_valid(remaining_contact.get("support")):
		path_resolution_complete = false
		path_valid = false
		last_bind_failure_reason = "支点求解达到 %d 次上限，未验证路径" % MAX_SUPPORT_SOLVE_ITERATIONS
		_log_connection_state(last_bind_failure_reason)
		return false
	path_resolution_complete = true
	path_valid = _validate_current_path()
	return true


func _find_next_contacted_support(path: PackedVector2Array) -> Dictionary:
	if path.size() < 2:
		return {}
	var best_support: Node2D
	var best_segment := INF
	var best_along := INF
	for candidate in _get_support_candidates():
		if wrap_supports.has(candidate):
			continue
		var center := _get_support_center(candidate)
		var radius := _get_support_radius(candidate)
		for segment_index in range(path.size() - 1):
			var start := path[segment_index]
			var segment := path[segment_index + 1] - start
			if _distance_to_segment(center, start, start + segment) > radius:
				continue
			var along := 0.0
			if segment.length_squared() > 0.001:
				along = clampf((center - start).dot(segment) / segment.length_squared(), 0.0, 1.0)
			if float(segment_index) < best_segment or (is_equal_approx(float(segment_index), best_segment) and along < best_along):
				best_support = candidate
				best_segment = float(segment_index)
				best_along = along
			break
	if not is_instance_valid(best_support):
		return {}
	return {"support": best_support, "segment": int(best_segment), "along": best_along}


func _advance_secondary_support_winding() -> void:
	for index in range(1, wrap_supports.size()):
		var support := wrap_supports[index]
		if not is_instance_valid(support) or not _is_valid_support(support):
			continue
		var support_id := support.get_instance_id()
		if not _secondary_support_winding.has(support_id):
			_secondary_support_winding[support_id] = {
				"angle": 0.0,
				"last_player_position": player.global_position,
				"last_support_center": _get_support_center(support),
			}
			continue
		var state: Dictionary = _secondary_support_winding[support_id]
		var previous_player: Vector2 = state.get("last_player_position", player.global_position)
		var previous_center: Vector2 = state.get("last_support_center", _get_support_center(support))
		var player_delta := player.global_position - previous_player
		var previous_relative := previous_player - previous_center
		var current_relative_from_player_motion := previous_relative + player_delta
		if player_delta.length() <= maximum_player_sample_step and previous_relative.length() > 0.001 and current_relative_from_player_motion.length() > 0.001:
			var delta_degrees := rad_to_deg(previous_relative.angle_to(current_relative_from_player_motion))
			if absf(delta_degrees) <= maximum_sample_angle_degrees:
				state["angle"] = float(state.get("angle", 0.0)) + delta_degrees
		state["last_player_position"] = player.global_position
		state["last_support_center"] = _get_support_center(support)
		_secondary_support_winding[support_id] = state


func _remove_released_secondary_supports() -> void:
	_advance_secondary_support_winding()
	for index in range(wrap_supports.size() - 1, 0, -1):
		var support := wrap_supports[index]
		if not is_instance_valid(support) or not _is_valid_support(support):
			var invalid_id := support.get_instance_id() if is_instance_valid(support) else 0
			wrap_supports.remove_at(index)
			_secondary_support_arc_directions.erase(invalid_id)
			_secondary_support_winding.erase(invalid_id)
			_rebase_tension_after_topology_change()
			_log_connection_state("removed invalid secondary support; retained primary winding")
			continue
		var support_id := support.get_instance_id()
		var state: Dictionary = _secondary_support_winding.get(support_id, {})
		if absf(float(state.get("angle", 0.0))) > support_release_angle_degrees:
			continue
		var path_without_support := _build_routed_path(support_id)
		if _path_touches_support(path_without_support, support, _get_support_radius(support)):
			continue
		wrap_supports.remove_at(index)
		_secondary_support_arc_directions.erase(support_id)
		_secondary_support_winding.erase(support_id)
		_rebase_tension_after_topology_change()
		_log_connection_state("removed released secondary support %s after direct path became clear" % str(support.name))


func _path_touches_support(path: PackedVector2Array, support: Node2D, radius: float) -> bool:
	if path.size() < 2 or not is_instance_valid(support):
		return false
	var center := _get_support_center(support)
	for segment_index in range(path.size() - 1):
		if _distance_to_segment(center, path[segment_index], path[segment_index + 1]) <= radius:
			return true
	return false


func _rebase_tension_after_topology_change() -> void:
	if not is_instance_valid(player):
		return
	_last_tension_player_position = player.global_position
	_last_tension_pivot_position = _get_support_center(wrap_pivot) if is_instance_valid(wrap_pivot) else Vector2.ZERO
	_last_tension_anchor_position = target.global_position if is_instance_valid(target) else Vector2.ZERO
	_active_pull_distance = 0.0
	if winding_complete:
		routed_path_length_at_wound = _routed_path_length()
		_wound_endpoint_segment_length = _get_endpoint_segment_length(_build_routed_path())


func _log_connection_state(reason: String) -> void:
	var pivot_name := str(wrap_pivot.name) if is_instance_valid(wrap_pivot) else "none"
	print("[Yarn #%d] %s | anchor=%s primary=%s state=%s angle=%.2f winding=%s taut=%s supports=%d" % [
		debug_connection_id,
		reason,
		str(target.name) if is_instance_valid(target) else "<invalid>",
		pivot_name,
		str(WrapState.keys()[wrap_state]),
		accumulated_wrap_angle,
		str(winding_complete),
		str(is_taut),
		wrap_supports.size()
	])


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


func _wrap_angle_reaches_threshold(angle_degrees: float) -> bool:
	return absf(angle_degrees) + WRAP_ANGLE_EPSILON_DEGREES >= required_wrap_angle_degrees


func _update_wrap_angle(player_is_actively_pulling: bool = false) -> bool:
	valid_movement_this_frame = false
	if not is_wrapped or not is_instance_valid(wrap_pivot) or not _is_valid_support(wrap_pivot):
		return true
	var discontinuity_version := _get_player_discontinuity_version()
	if discontinuity_version != _last_player_discontinuity_version:
		_last_player_discontinuity_version = discontinuity_version
		_reset_wrap_state("检测到复活或位置跳转，绕行与张力基准已重置")
		return false
	if not _validate_current_path():
		_pending_wrap_angle_degrees = 0.0
		_pending_player_travel = 0.0
		is_taut = false
		rope_physically_taut = false
		tension_value = 0.0
		_active_pull_distance = 0.0
		wrap_state = WrapState.WOUND if winding_complete else WrapState.WRAPPED
		last_bind_failure_reason = "毛线路径非法，暂停本帧绕行并保留已提交进度"
		_last_observed_player_position = player.global_position
		_last_tension_player_position = player.global_position
		return false
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
	if winding_complete and player_is_actively_pulling:
		# Radial pull is tension input, not reverse orbit. Do not let a tiny
		# endpoint-geometry angle change cancel a just-completed winding.
		_pending_wrap_angle_degrees = 0.0
		_pending_player_travel = 0.0
		_last_pivot_position = current_pivot_position
		_last_observed_player_position = player.global_position
		_last_tension_player_position = player.global_position
		return true
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
	if _wrap_angle_reaches_threshold(effective_wrap_angle):
		if absf(_pending_wrap_angle_degrees) > 0.001:
			wrap_angle_history.append(_pending_wrap_angle_degrees)
		accumulated_wrap_angle = effective_wrap_angle
		wrap_contact_history.append(current_relative.normalized())
		_pending_wrap_angle_degrees = 0.0
		_pending_player_travel = 0.0
		wrap_side_sign = signf(accumulated_wrap_angle)
	if winding_complete and not _wrap_angle_reaches_threshold(effective_wrap_angle):
		_log_connection_state("reverse movement unwound below the threshold")
		winding_complete = false
		is_taut = false
		tension_value = 0.0
		_active_pull_distance = 0.0
		wrap_state = WrapState.WRAPPED
		last_bind_failure_reason = "反向移动已解除部分缠绕进度"
	if not winding_complete and _wrap_angle_reaches_threshold(effective_wrap_angle):
		winding_complete = true
		wrap_state = WrapState.WOUND
		player_position_at_wound = player.global_position
		pivot_position_at_wound = _get_support_center(wrap_pivot)
		player_radius_at_wound = player.global_position.distance_to(pivot_position_at_wound)
		routed_path_length_at_wound = _routed_path_length()
		_wound_endpoint_segment_length = _get_endpoint_segment_length(_build_routed_path())
		_active_pull_distance = 0.0
		_last_tension_player_position = player.global_position
		_last_tension_pivot_position = pivot_position_at_wound
		_last_tension_anchor_position = target.global_position
		last_bind_failure_reason = "缠绕完成，继续拉紧毛线"
		_log_connection_state("winding threshold reached; waiting for active pull")
	return true


func _get_player_discontinuity_version() -> int:
	if not is_instance_valid(player):
		return -1
	var value: Variant = player.get("position_discontinuity_version")
	return int(value) if value != null else 0


func _update_tension_and_bind(allow_bind: bool = false) -> void:
	if not path_resolution_complete:
		path_valid = false
		is_taut = false
		last_bind_failure_reason = "支点路径求解未完成，暂停束缚结算"
		return
	path_valid = _validate_current_path()
	if not path_valid:
		is_taut = false
		rope_physically_taut = false
		last_bind_failure_reason = "毛线路径被未配置支点的障碍物阻断"
		_last_tension_player_position = player.global_position
		return
	_update_rope_lengths_and_barrier()
	is_taut = rope_physically_taut
	tension_value = maxf(actual_routed_length - (effective_rope_length - initial_slack_length), 0.0)
	if remaining_slack > LOOP_GEOMETRY_EPSILON:
		if winding_complete:
			wrap_state = WrapState.WOUND
		last_bind_failure_reason = "剩余松弛 %.1f px" % remaining_slack
		return
	if not winding_complete or not is_wrapped:
		last_bind_failure_reason = "绳长已受限，但尚无有效缠绕；只阻挡，不束缚"
		return
	if allow_bind and feeding_enabled:
		last_bind_failure_reason = "仍在放线；停止放线后再主动外拉才能束缚"
		return
	wrap_state = WrapState.BOUND if loop_bound else WrapState.TAUT
	last_bind_failure_reason = "毛线绷紧；等待玩家主动外拉" if not allow_bind else "玩家主动拉紧毛线"
	if allow_bind:
		_bind_wrapped_targets()


func _get_endpoint_segment_length(route: PackedVector2Array) -> float:
	if route.size() < 2:
		return 0.0
	return route[0].distance_to(route[1])


func constrain_player_velocity(requested_velocity: Vector2, delta: float) -> Vector2:
	_player_requested_outward_pull = false
	if finished or not is_instance_valid(player) or not is_instance_valid(target):
		return requested_velocity
	if not is_wrapped:
		_try_acquire_support()
	if is_wrapped:
		path_resolution_complete = _add_contacted_supports()
		if path_resolution_complete:
			_remove_released_secondary_supports()
		else:
			return requested_velocity
	var route := _build_routed_path()
	if route.size() < 2:
		return requested_velocity
	_update_rope_lengths_and_barrier()
	_capture_feed_step(route)
	_player_slack_before_step = remaining_slack
	var outward := (route[0] - route[1]).normalized()
	var outward_speed := requested_velocity.dot(outward)
	var alignment := outward_speed / maxf(requested_velocity.length(), 0.001)
	_player_requested_outward_pull = outward_speed > 0.5 and alignment >= 0.7
	if outward_speed <= 0.0:
		return requested_velocity
	var allowed_extension_speed := remaining_slack / maxf(delta, 0.001)
	if remaining_slack <= LOOP_GEOMETRY_EPSILON:
		allowed_extension_speed = 0.0
	return requested_velocity - outward * maxf(outward_speed - allowed_extension_speed, 0.0)


func on_player_physics_moved(old_position: Vector2, new_position: Vector2) -> void:
	if finished:
		return
	var requested_pull := _player_requested_outward_pull
	_player_requested_outward_pull = false
	if not path_resolution_complete:
		return
	if not is_wrapped:
		_try_acquire_support()
	if is_wrapped:
		path_resolution_complete = _add_contacted_supports()
		if path_resolution_complete:
			_remove_released_secondary_supports()
	if not path_resolution_complete or not _validate_current_path():
		_feed_step_valid = false
		return
	var discontinuity_before := _get_player_discontinuity_version()
	var continuous_motion := _update_wrap_angle(requested_pull)
	if continuous_motion:
		_pay_out_for_player_route_growth(old_position, new_position)
	_update_rope_lengths_and_barrier()
	var movement := new_position - old_position
	var route := _build_routed_path()
	var outward := (route[0] - route[1]).normalized() if route.size() >= 2 else Vector2.ZERO
	var actively_pulled := requested_pull and (
		movement.dot(outward) > 0.1 or _player_slack_before_step <= LOOP_GEOMETRY_EPSILON
	)
	# At the leash, CharacterBody2D correctly clamps the cat's outward velocity
	# to zero. A real outward input at an already taut leash is still the final
	# active pull; do not require another physical pixel after the hard limit.
	# A teleport/respawn is excluded by the discontinuity version check.
	var requested_at_taut_leash := (
		requested_pull
		and _player_slack_before_step <= LOOP_GEOMETRY_EPSILON
		and old_position.distance_to(new_position) <= 0.1
		and discontinuity_before == _get_player_discontinuity_version()
	)
	if (continuous_motion or requested_at_taut_leash) and not feeding_enabled and remaining_slack <= LOOP_GEOMETRY_EPSILON and winding_complete and is_wrapped and actively_pulled:
		_update_tension_and_bind(true)
	elif requested_pull:
		last_bind_failure_reason = "玩家外拉正在消耗松弛（%.1f px）" % remaining_slack
	_feed_step_valid = false


func _capture_feed_step(route: PackedVector2Array) -> void:
	_feed_step_valid = route.size() >= 2 and is_instance_valid(player) and is_instance_valid(target)
	_feed_step_route_length = _path_length(route)
	_feed_step_support_ids.clear()
	_feed_step_support_centers.clear()
	_feed_step_anchor_position = target.global_position if is_instance_valid(target) else Vector2.ZERO
	for support in wrap_supports:
		if not is_instance_valid(support):
			continue
		var support_id := support.get_instance_id()
		_feed_step_support_ids.append(support_id)
		_feed_step_support_centers[support_id] = _get_support_center(support)


func _pay_out_for_player_route_growth(old_position: Vector2, new_position: Vector2) -> void:
	if not feeding_enabled or not _feed_step_valid or not is_instance_valid(target):
		return
	var player_step := old_position.distance_to(new_position)
	if player_step <= 0.1 or player_step > maximum_player_sample_step:
		return
	if target.global_position.distance_to(_feed_step_anchor_position) > 0.05:
		return
	if wrap_supports.size() != _feed_step_support_ids.size():
		return
	for index in range(wrap_supports.size()):
		var support := wrap_supports[index]
		if not is_instance_valid(support) or support.get_instance_id() != _feed_step_support_ids[index]:
			return
		var old_center: Vector2 = _feed_step_support_centers.get(support.get_instance_id(), _get_support_center(support))
		if _get_support_center(support).distance_to(old_center) > 0.05:
			return
	var current_route_length := _routed_path_length()
	var player_caused_growth := current_route_length - _feed_step_route_length
	if player_caused_growth <= 0.001:
		return
	effective_rope_length += player_caused_growth
	last_bind_failure_reason = "正在放线 +%.1f px（玩家造成的路径增长）" % player_caused_growth


func stop_feeding() -> bool:
	if finished or not feeding_enabled:
		return false
	_update_rope_lengths_and_barrier()
	feeding_enabled = false
	last_bind_failure_reason = "已停止放线，锁定有效绳长；剩余松弛 %.1f px" % remaining_slack
	_log_connection_state(last_bind_failure_reason)
	_update_visuals()
	return true


func _path_length(path: PackedVector2Array) -> float:
	var result := 0.0
	for index in range(path.size() - 1):
		result += path[index].distance_to(path[index + 1])
	return result


func _update_rope_lengths_and_barrier() -> void:
	if not is_instance_valid(player) or not is_instance_valid(target):
		return
	var route := _build_routed_path()
	actual_routed_length = _path_length(route)
	remaining_slack = maxf(effective_rope_length - actual_routed_length, 0.0)
	if rope_physically_taut:
		rope_physically_taut = remaining_slack <= LOOP_GEOMETRY_EPSILON + rope_taut_hysteresis
	else:
		rope_physically_taut = remaining_slack <= LOOP_GEOMETRY_EPSILON
	var physically_taut := rope_physically_taut and path_resolution_complete and _validate_current_path()
	if is_instance_valid(_rope_barrier_body):
		_rope_barrier_body.collision_layer = 4 if physically_taut else 0
		_update_rope_barrier_shapes(route, physically_taut)


func _update_rope_barrier_shapes(route: PackedVector2Array, enabled: bool) -> void:
	if not is_instance_valid(_rope_barrier_body):
		return
	var usable_segments := maxi(route.size() - 1, 0)
	while _rope_barrier_shapes.size() < usable_segments:
		var shape_node := CollisionShape2D.new()
		shape_node.name = "RopeSegment%d" % _rope_barrier_shapes.size()
		var capsule := CapsuleShape2D.new()
		capsule.radius = taut_rope_collision_radius
		shape_node.shape = capsule
		_rope_barrier_body.add_child(shape_node)
		_rope_barrier_shapes.append(shape_node)
	while _rope_barrier_shapes.size() > usable_segments:
		var removed: CollisionShape2D = _rope_barrier_shapes.pop_back()
		removed.queue_free()
	for index in range(usable_segments):
		var shape_node := _rope_barrier_shapes[index]
		var start := route[index]
		var end := route[index + 1]
		var segment := end - start
		if segment.length_squared() <= 0.001:
			shape_node.disabled = true
			continue
		if index == 0:
			start += segment.normalized() * rope_endpoint_collision_inset
		if index == usable_segments - 1:
			end -= segment.normalized() * rope_endpoint_collision_inset
		segment = end - start
		shape_node.disabled = not enabled or segment.length() <= 0.5
		shape_node.position = to_local((start + end) * 0.5)
		shape_node.rotation = segment.angle() - PI * 0.5
		var capsule := shape_node.shape as CapsuleShape2D
		capsule.height = maxf(segment.length() + taut_rope_collision_radius * 2.0, taut_rope_collision_radius * 2.0)


func _bind_wrapped_targets() -> void:
	var targets := _collect_enclosed_targets()
	var actual_loops := _extract_actual_closed_loops(_build_routed_path())
	var bound_count := 0
	var eligible_count := 0
	for enemy in targets:
		if not is_instance_valid(enemy) or not enemy.has_method("apply_yarn_bind") or _bound_target_ids.has(enemy.get_instance_id()):
			continue
		eligible_count += 1
		if bool(enemy.apply_yarn_bind(bind_duration)):
			bound_count += 1
			_bound_target_ids[enemy.get_instance_id()] = true
			_log_connection_state("bound enclosed target %s" % str(enemy.name))
	loop_bound = loop_bound or bound_count > 0
	if loop_bound:
		wrap_state = WrapState.BOUND
		last_bind_failure_reason = "束缚已触发 %d/%d 个有效目标" % [_bound_target_ids.size(), targets.size()]
		_retain_bound_loops(actual_loops)
		# The caught targets retain their own bind timers. The cat-side tether is
		# removed immediately; only the closed loop, if any, survives independently.
		_finish()
	else:
		last_bind_failure_reason = "没有可结算目标（免疫或已被其他毛线束缚；候选 %d）" % eligible_count


func _retain_bound_loops(actual_loops: Array[PackedVector2Array]) -> void:
	if actual_loops.is_empty() or not is_instance_valid(owner_scene):
		return
	var retained_loop := BoundYarnLoop.new()
	retained_loop.setup(actual_loops, bind_duration, taut_rope_collision_radius)
	owner_scene.add_child(retained_loop)


func _collect_enclosed_targets() -> Array[Node2D]:
	var result: Array[Node2D] = []
	if is_instance_valid(target) and target.is_in_group("enemies"):
		result.append(target)
	var routed_path := _build_routed_path()
	if routed_path.size() < 2 or not path_resolution_complete or not _validate_current_path():
		return result
	for support_index in range(wrap_supports.size()):
		var support := wrap_supports[support_index]
		if not is_instance_valid(support) or not support.is_in_group("enemies") or result.has(support):
			continue
		if _path_touches_support(routed_path, support, _get_support_radius(support) + path_clearance):
			result.append(support)
	for candidate in _collect_targets_inside_actual_loops(routed_path):
		if not result.has(candidate):
			result.append(candidate)
	return result


func _collect_targets_inside_actual_loops(routed_path: PackedVector2Array) -> Array[Node2D]:
	var result: Array[Node2D] = []
	var closed_loops := _extract_actual_closed_loops(routed_path)
	if closed_loops.is_empty():
		return result
	for candidate in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(candidate) or not candidate is Node2D or not _is_valid_support(candidate):
			continue
		var candidate_position := (candidate as Node2D).global_position
		for loop_path in closed_loops:
			if _point_is_inside_polygon_nonzero(candidate_position, loop_path):
				result.append(candidate)
				break
	return result


func _extract_actual_closed_loops(path: PackedVector2Array) -> Array[PackedVector2Array]:
	var loops: Array[PackedVector2Array] = []
	if path.size() < 3:
		return loops
	var endpoint_closed := path[0].distance_to(path[path.size() - 1]) <= LOOP_GEOMETRY_EPSILON
	if endpoint_closed:
		var closed_path := path.duplicate()
		if closed_path[0] != closed_path[closed_path.size() - 1]:
			closed_path.append(closed_path[0])
		if absf(_signed_polygon_area(closed_path)) > LOOP_GEOMETRY_EPSILON:
			loops.append(closed_path)
	for first_segment in range(path.size() - 1):
		for second_segment in range(first_segment + 2, path.size() - 1):
			if endpoint_closed and first_segment == 0 and second_segment == path.size() - 2:
				continue
			var intersection := _segment_intersection(
				path[first_segment], path[first_segment + 1],
				path[second_segment], path[second_segment + 1]
			)
			if intersection.is_empty():
				continue
			var loop_path := PackedVector2Array([intersection["point"]])
			for vertex_index in range(first_segment + 1, second_segment + 1):
				loop_path.append(path[vertex_index])
			loop_path.append(intersection["point"])
			if loop_path.size() >= 4 and absf(_signed_polygon_area(loop_path)) > LOOP_GEOMETRY_EPSILON:
				loops.append(loop_path)
	return loops


func _segment_intersection(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> Dictionary:
	var first := b - a
	var second := d - c
	var denominator := first.cross(second)
	if absf(denominator) <= LOOP_GEOMETRY_EPSILON:
		return {}
	var offset := c - a
	var t := offset.cross(second) / denominator
	var u := offset.cross(first) / denominator
	if t < -LOOP_GEOMETRY_EPSILON or t > 1.0 + LOOP_GEOMETRY_EPSILON or u < -LOOP_GEOMETRY_EPSILON or u > 1.0 + LOOP_GEOMETRY_EPSILON:
		return {}
	return {"point": a + first * clampf(t, 0.0, 1.0)}


func _signed_polygon_area(path: PackedVector2Array) -> float:
	var twice_area := 0.0
	for index in range(path.size() - 1):
		twice_area += path[index].cross(path[index + 1])
	if path[0] != path[path.size() - 1]:
		twice_area += path[path.size() - 1].cross(path[0])
	return twice_area * 0.5


func _point_is_inside_polygon_nonzero(point: Vector2, polygon: PackedVector2Array) -> bool:
	var winding_number := 0
	for index in range(polygon.size() - 1):
		var a := polygon[index]
		var b := polygon[index + 1]
		if _distance_to_segment(point, a, b) <= LOOP_GEOMETRY_EPSILON:
			return true
		var side := (b - a).cross(point - a)
		if a.y <= point.y:
			if b.y > point.y and side > LOOP_GEOMETRY_EPSILON:
				winding_number += 1
		elif b.y <= point.y and side < -LOOP_GEOMETRY_EPSILON:
			winding_number -= 1
	return winding_number != 0


func _point_is_inside_routed_loop(point: Vector2, open_path: PackedVector2Array) -> bool:
	# Only endpoint-closed routes and cycles traced by actual self-intersections
	# create regions. No synthetic endpoint chord or player-history polygon is used.
	for loop_path in _extract_actual_closed_loops(open_path):
		if _point_is_inside_polygon_nonzero(point, loop_path):
			return true
	return false


func _validate_current_path() -> bool:
	if not is_instance_valid(player) or not is_instance_valid(target):
		return false
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
	for point in path:
		if not is_finite(point.x) or not is_finite(point.y):
			return false
	for index in range(path.size() - 1):
		if not _ray_hit(path[index], path[index + 1], excluded).is_empty():
			return false
	return true


func _ray_hit(start: Vector2, end: Vector2, exclude_nodes: Array[Node]) -> Dictionary:
	if not is_finite(start.x) or not is_finite(start.y) or not is_finite(end.x) or not is_finite(end.y):
		return {"position": start, "collider": self}
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


func _build_routed_path(excluded_support_id: int = 0) -> PackedVector2Array:
	var points := PackedVector2Array()
	if not is_instance_valid(player) or not is_instance_valid(target):
		return points
	points.append(player.global_position)
	if not is_wrapped or not is_instance_valid(wrap_pivot) or not _is_valid_support(wrap_pivot):
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
		return _route_through_secondary_supports(points, excluded_support_id)
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
	return _route_through_secondary_supports(points, excluded_support_id)


func _route_through_secondary_supports(base_path: PackedVector2Array, excluded_support_id: int = 0) -> PackedVector2Array:
	var routed := base_path
	for solve_iteration in range(MAX_SUPPORT_SOLVE_ITERATIONS):
		var changed := false
		for support_index in range(1, wrap_supports.size()):
			var support := wrap_supports[support_index]
			if not is_instance_valid(support) or not _is_valid_support(support):
				continue
			if support.get_instance_id() == excluded_support_id:
				continue
			var center := _get_support_center(support)
			var radius := _get_support_radius(support) + maxf(path_clearance, 0.0)
			for segment_index in range(routed.size() - 1):
				if _distance_to_segment(center, routed[segment_index], routed[segment_index + 1]) >= radius - 0.5:
					continue
				var key := support.get_instance_id()
				var preferred_direction := float(_secondary_support_arc_directions.get(key, 0.0))
				var route_result := _route_segment_around_circle(
					routed[segment_index], routed[segment_index + 1], center, radius, preferred_direction
				)
				var detour: PackedVector2Array = route_result.get("points", PackedVector2Array())
				if detour.size() < 3:
					continue
				var replacement := PackedVector2Array()
				for prefix_index in range(segment_index + 1):
					replacement.append(routed[prefix_index])
				for detour_index in range(1, detour.size() - 1):
					replacement.append(detour[detour_index])
				for suffix_index in range(segment_index + 1, routed.size()):
					replacement.append(routed[suffix_index])
				routed = replacement
				if preferred_direction == 0.0:
					_secondary_support_arc_directions[key] = float(route_result.get("direction", 0.0))
				changed = true
				break
		if not changed:
			break
	return routed


func _route_segment_around_circle(
	start: Vector2,
	end: Vector2,
	center: Vector2,
	radius: float,
	preferred_direction: float
) -> Dictionary:
	var start_offset := start - center
	var end_offset := end - center
	if start_offset.length() <= radius or end_offset.length() <= radius:
		return {}
	var start_alpha := acos(clampf(radius / start_offset.length(), -1.0, 1.0))
	var end_alpha := acos(clampf(radius / end_offset.length(), -1.0, 1.0))
	var directions: Array[float] = []
	if absf(preferred_direction) > 0.1:
		directions.append(preferred_direction)
	else:
		directions.append(-1.0)
		directions.append(1.0)
	var best_path := PackedVector2Array()
	var best_length := INF
	var best_direction := 0.0
	for start_side in [-1.0, 1.0]:
		var start_angle: float = start_offset.angle() + float(start_side) * start_alpha
		var start_tangent := center + Vector2.from_angle(start_angle) * radius
		for end_side in [-1.0, 1.0]:
			var end_angle: float = end_offset.angle() + float(end_side) * end_alpha
			var end_tangent := center + Vector2.from_angle(end_angle) * radius
			for direction in directions:
				var arc := _directed_arc_delta(start_angle, end_angle, float(direction))
				var candidate_length := start.distance_to(start_tangent) + absf(arc) * radius + end_tangent.distance_to(end)
				if candidate_length >= best_length:
					continue
				best_length = candidate_length
				best_direction = float(direction)
				best_path.clear()
				best_path.append(start)
				best_path.append(start_tangent)
				var subdivisions := maxi(1, ceili(absf(arc) / deg_to_rad(10.0)))
				for subdivision in range(1, subdivisions + 1):
					best_path.append(center + Vector2.from_angle(start_angle + arc * float(subdivision) / float(subdivisions)) * radius)
				best_path.append(end)
	return {"points": best_path, "direction": best_direction}


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
		if not full_path.is_empty() and path_points.size() == full_path.size():
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
	var debug_row := 0
	for connection in get_tree().get_nodes_in_group("yarn_connections"):
		if connection == self:
			continue
		if connection is YarnConnection and (connection as YarnConnection).debug_connection_id < debug_connection_id:
			debug_row += 1
	debug_status.position = to_local(player.global_position) + Vector2(-85.0, -68.0 - float(debug_row) * 42.0)
	var target_name := str(target.name) if is_instance_valid(target) else "无"
	var pivot_name := str(wrap_pivot.name) if is_wrapped and is_instance_valid(wrap_pivot) else "未接触"
	var support_names := PackedStringArray()
	for support in wrap_supports:
		if is_instance_valid(support):
			support_names.append(str(support.name))
	var support_summary := ", ".join(support_names) if not support_names.is_empty() else "无"
	var state_names: Array[String] = ["寻找支点", "已接触支点", "已缠绕·等待拉紧", "拉紧中", "束缚触发"]
	var status_name: String = state_names[wrap_state]
	var status_text := "#%d 锚定：%s | 主支点：%s\n路径支点：%s\n路径节点：%d | 角度：%.0f°/%.0f°\n有效移动：%s | 已缠绕：%s\n已拉紧：%s | 张力：%.1f/%.1f px\n状态：%s" % [
		debug_connection_id,
		target_name,
		pivot_name,
		support_summary,
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
	status_text += "\n绳路 %.1f / 有效 %.1f px | 松弛 %.1f px" % [actual_routed_length, effective_rope_length, remaining_slack]
	status_text += " | 放线：%s" % ("开" if feeding_enabled else "已锁定")
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
	_log_connection_state("wrap state reset: %s" % reason)
	wrap_pivot = null
	wrap_supports.clear()
	_secondary_support_arc_directions.clear()
	_secondary_support_winding.clear()
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
	rope_physically_taut = false
	loop_bound = false
	path_resolution_complete = true
	path_valid = true
	tension_value = 0.0
	_active_pull_distance = 0.0
	_player_requested_outward_pull = false
	_feed_step_valid = false
	_last_tension_player_position = player.global_position
	_last_tension_pivot_position = Vector2.ZERO
	_last_tension_anchor_position = target.global_position if is_instance_valid(target) else Vector2.ZERO
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
