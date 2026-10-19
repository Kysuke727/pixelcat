extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world: Node = load("res://scenes/worlds/night_world.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	await physics_frame
	var player := get_first_node_in_group("player") as Node2D
	var combat: Node = player.get_node("PlayerCombat")
	player.set_physics_process(false)
	player.set_process(false)
	combat.set_process(false)
	for enemy in get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
		enemy.global_position = Vector2(930.0, 650.0)
	var lamp_point := world.get_node("Decorations/LampWrapPoint1") as Node2D
	var lamp_collision := lamp_point.get_node("StaticBody2D/CollisionShape2D") as CollisionShape2D
	_check(lamp_point.get_node("StaticBody2D") is StaticBody2D, "street lamp has a physical blocker separate from its wrap marker")
	_check(is_equal_approx((lamp_collision.shape as CircleShape2D).radius, 10.0) and is_equal_approx(float(lamp_point.get("yarn_wrap_radius")), 11.0), "lamp body radius and yarn-routing radius remain distinct")
	player.global_position = Vector2(656.0, 210.0)
	_check(player.test_move(player.global_transform, Vector2(40.0, 0.0)), "player movement query collides with the physical lamp body")

	_check(is_equal_approx(combat.ranged_cooldown, 4.0), "central yarn cooldown defaults to four seconds")
	_check(is_equal_approx(combat.yarn_connection_duration, 10.0), "base connection duration remains ten seconds")
	_check(is_equal_approx(combat.yarn_cut_cooldown_reduction, 1.5), "Q refund remains 1.5 seconds")

	# Verify K hits an enemy, records A, and starts cooldown at launch.
	player.global_position = Vector2(200.0, 300.0)
	combat.facing = Vector2.RIGHT
	var projectile_target := _spawn_slime(world, Vector2(270.0, 300.0))
	combat._spawn_projectile()
	for _frame in range(30):
		await physics_frame
		if not combat.yarn_projectile_in_flight:
			break
	_check(combat.active_yarn_connections.size() == 1, "K hit creates a tracked connection")
	if combat.active_yarn_connections.size() == 1:
		var fired_connection := combat.active_yarn_connections[0] as YarnConnection
		_check(fired_connection.target == projectile_target, "K hit stores the anchor target A")
		_check(is_equal_approx(combat.ranged_cooldown_left, 4.0), "cooldown starts at launch rather than after connection ends")
		fired_connection.finish_naturally()

	# A full orbit around A without touching a separate support never winds.
	var anchor_only := _spawn_slime(world, Vector2(500.0, 350.0))
	player.global_position = anchor_only.global_position + Vector2(70.0, 0.0)
	var anchor_connection := _create_connection(combat, player, anchor_only)
	await process_frame
	for step in range(1, 61):
		player.global_position = anchor_only.global_position + Vector2.from_angle(deg_to_rad(-6.0 * step)) * 70.0
		anchor_connection._process(1.0 / 60.0)
	_check(not anchor_connection.is_wrapped, "orbiting anchor A alone does not acquire a pivot")
	_check(not anchor_connection.winding_complete and not anchor_connection.loop_bound, "orbiting anchor A alone cannot wind or bind")
	anchor_connection.finish_naturally()
	anchor_only.queue_free()
	await process_frame

	# Rotation alone is not enough: the rope must contact a declared static pivot.
	var no_contact_target := _spawn_slime(world, Vector2(560.0, 350.0))
	var off_path_pivot := _add_wrap_point(world, Vector2(500.0, 450.0), 12.0)
	player.global_position = Vector2(500.0, 420.0)
	var no_contact_connection := _create_connection(combat, player, no_contact_target)
	await process_frame
	for step in range(1, 61):
		player.global_position = Vector2(500.0, 350.0) + Vector2.from_angle(deg_to_rad(-6.0 * step)) * 70.0
		no_contact_connection._process(1.0 / 60.0)
	_check(not no_contact_connection.is_wrapped, "nearby but untouched static pivot is rejected")
	_check(not no_contact_connection.loop_bound, "angle without real rope-to-pivot contact cannot bind")
	no_contact_connection.finish_naturally()
	off_path_pivot.queue_free()

	# Static support: 270 degrees only enters wound state; pulling tight binds A.
	var static_pivot_position := Vector2(500.0, 350.0)
	var static_target := _spawn_slime(world, Vector2(700.0, 350.0))
	var static_pivot := _add_wrap_point(world, static_pivot_position, 20.0)
	player.global_position = Vector2(430.0, 350.0)
	var static_connection := _create_connection(combat, player, static_target)
	await process_frame
	static_connection._process(1.0 / 60.0)
	var previous_route_length: float = static_connection._routed_path_length()
	var initial_route_length: float = previous_route_length
	var maximum_route_length_step := 0.0
	_check(static_connection.is_wrapped and static_connection.wrap_pivot == static_pivot, "rope contact selects the declared static support")
	for step in range(1, 46):
		player.global_position = static_pivot_position + Vector2.from_angle(PI - deg_to_rad(6.0 * step)) * 70.0
		static_connection._process(1.0 / 60.0)
		var route_length: float = static_connection._routed_path_length()
		maximum_route_length_step = maxf(maximum_route_length_step, absf(route_length - previous_route_length))
		previous_route_length = route_length
	_check(static_connection.winding_complete, "270 degrees around static pivot completes winding")
	_check(maximum_route_length_step < 40.0, "routed yarn topology changes continuously without a sudden wrap jump")
	_check(not static_connection.is_taut and static_target.bind_time_left <= 0.0, "winding without tension does not bind")
	_check(static_connection.path_points.size() >= 5, "visual yarn route bends around the support edge instead of through its center")
	_check(_path_clears_circle(static_connection.path_points, static_pivot_position, 20.0), "static yarn path stays outside the support surface")
	_check(absf(_path_oriented_arc_degrees(static_connection.path_points, static_pivot_position)) >= 180.0, "rendered yarn route preserves the major wrap topology")
	for step in range(46, 61):
		player.global_position = static_pivot_position + Vector2.from_angle(PI - deg_to_rad(6.0 * step)) * 70.0
		static_connection._process(1.0 / 60.0)
	_check(static_connection._routed_path_length() > initial_route_length + 100.0, "same endpoints after one full orbit retain a distinct rope coil")
	for step in range(59, 44, -1):
		player.global_position = static_pivot_position + Vector2.from_angle(PI - deg_to_rad(6.0 * step)) * 70.0
		static_connection._process(1.0 / 60.0)
	_check(static_connection.winding_complete, "reversing a full coil unwinds continuously back to the bind threshold")
	_check(static_connection.get_node("AnchorKnot").visible, "connected target displays the attached yarn knot")
	_check(static_connection.get_node("PivotMarker").visible, "active support has a visible debug marker")
	_check(static_connection.get_debug_status_text().contains("张力"), "debug display reports tension and wrap state")
	var final_radial := (player.global_position - static_pivot_position).normalized()
	player.global_position += final_radial * 30.0
	static_connection._process(1.0 / 60.0)
	_check(static_connection.is_taut, "pulling away after winding satisfies configurable tension")
	_check(static_connection.loop_bound, "taut static-pivot yarn binds anchor A")
	_check(static_target.bind_time_left >= 1.5, "static-pivot bind uses the 1.5-second base duration")
	_check(not static_pivot.is_in_group("enemies"), "static scenery pivot is never treated as an enemy target")
	static_connection.finish_naturally()
	static_target.bind_time_left = 0.0
	static_target.bind_resistance_left = 1.0
	_check(not static_target.apply_yarn_bind(1.5), "control immunity rejects a new yarn bind")
	static_pivot.queue_free()
	await process_frame

	var counterclockwise_pivot_position := Vector2(500.0, 350.0)
	var counterclockwise_target := _spawn_slime(world, Vector2(700.0, 350.0))
	var counterclockwise_pivot := _add_wrap_point(world, counterclockwise_pivot_position, 20.0)
	player.global_position = Vector2(430.0, 350.0)
	var counterclockwise_connection := _create_connection(combat, player, counterclockwise_target)
	await process_frame
	counterclockwise_connection._process(1.0 / 60.0)
	for step in range(1, 46):
		player.global_position = counterclockwise_pivot_position + Vector2.from_angle(PI + deg_to_rad(6.0 * step)) * 70.0
		counterclockwise_connection._process(1.0 / 60.0)
	_check(counterclockwise_connection.winding_complete, "counterclockwise pivot winding reaches 270 degrees")
	var counterclockwise_radial := (player.global_position - counterclockwise_pivot_position).normalized()
	player.global_position += counterclockwise_radial * 30.0
	counterclockwise_connection._process(1.0 / 60.0)
	_check(counterclockwise_connection.loop_bound, "counterclockwise winding can be pulled taut to bind")
	counterclockwise_connection.finish_naturally()
	counterclockwise_target.queue_free()
	counterclockwise_pivot.queue_free()

	# Reversal subtracts winding; tiny oscillations are below the valid step.
	var reverse_position := Vector2(400.0, 530.0)
	var reverse_target := _spawn_slime(world, Vector2(600.0, 530.0))
	var reverse_pivot := _add_wrap_point(world, reverse_position, 18.0)
	player.global_position = reverse_position + Vector2(-70.0, 0.0)
	var reverse_connection := _create_connection(combat, player, reverse_target)
	await process_frame
	reverse_connection._process(1.0 / 60.0)
	for angle_degrees in range(186, 331, 6):
		player.global_position = reverse_position + Vector2.from_angle(deg_to_rad(float(angle_degrees))) * 70.0
		reverse_connection._process(1.0 / 60.0)
	for angle_degrees in range(324, 239, -6):
		player.global_position = reverse_position + Vector2.from_angle(deg_to_rad(float(angle_degrees))) * 70.0
		reverse_connection._process(1.0 / 60.0)
	_check(absf(reverse_connection.accumulated_wrap_angle) < 100.0, "reverse movement subtracts pivot-relative winding")
	_check(not reverse_connection.winding_complete, "reversing prevents false completion")
	var jitter_angle := deg_to_rad(60.0)
	var jitter_center := reverse_position + Vector2.from_angle(jitter_angle) * 70.0
	for index in range(80):
		player.global_position = jitter_center + Vector2(1.0 if index % 2 == 0 else -1.0, 0.0)
		reverse_connection._process(1.0 / 60.0)
	_check(not reverse_connection.loop_bound, "micro jitter cannot trigger binding")
	reverse_connection.finish_naturally()
	reverse_pivot.queue_free()

	# Dynamic enemy B is an explicit pivot; a taut wrap binds both A and B.
	var dynamic_pivot_position := Vector2(400.0, 200.0)
	var anchor_bait := _spawn_slime(world, Vector2(600.0, 200.0))
	var dynamic_pivot := _spawn_slime(world, dynamic_pivot_position)
	player.global_position = Vector2(330.0, 200.0)
	var dynamic_connection := _create_connection(combat, player, anchor_bait)
	await process_frame
	dynamic_connection._process(1.0 / 60.0)
	_check(dynamic_connection.is_wrapped and dynamic_connection.wrap_pivot == dynamic_pivot, "enemy B is detected as a dynamic pivot, not anchor A")
	for step in range(1, 46):
		var orbit := Vector2.from_angle(PI - deg_to_rad(6.0 * step)) * 70.0
		dynamic_pivot.global_position = dynamic_pivot_position + Vector2(0.1 * step, 0.0)
		anchor_bait.global_position = Vector2(600.0, 200.0) + Vector2(0.0, 0.1 * step)
		player.global_position = dynamic_pivot.global_position + orbit
		dynamic_connection._process(1.0 / 60.0)
	_check(dynamic_connection.winding_complete, "dynamic pivot motion does not erase cat winding")
	_check(not dynamic_connection.loop_bound, "dynamic pivot winding still waits for tension")
	var dynamic_radial := (player.global_position - dynamic_pivot.global_position).normalized()
	player.global_position += dynamic_radial * 30.0
	dynamic_connection._process(1.0 / 60.0)
	_check(dynamic_connection.loop_bound, "tight dynamic-pivot yarn triggers binding")
	_check(anchor_bait.bind_time_left > 0.0 and dynamic_pivot.bind_time_left > 0.0, "enemy pivot wrap binds both A and B")
	dynamic_connection.finish_naturally()

	var motion_target := _spawn_slime(world, Vector2(700.0, 700.0))
	var motion_pivot := _add_wrap_point(world, Vector2(500.0, 700.0), 20.0)
	player.global_position = Vector2(430.0, 700.0)
	var motion_connection := _create_connection(combat, player, motion_target)
	await process_frame
	motion_connection._process(1.0 / 60.0)
	for _frame in range(49):
		motion_pivot.global_position += Vector2(0.0, 1.0)
		motion_connection._process(1.0 / 60.0)
	_check(absf(motion_connection.accumulated_wrap_angle) < 0.1, "moving support alone cannot count as player winding")
	player.global_position += Vector2(1000.0, 0.0)
	motion_connection._process(1.0 / 60.0)
	_check(absf(motion_connection.accumulated_wrap_angle) < 0.1, "teleport-sized movement is discarded as a winding sample")
	motion_connection.finish_naturally()
	motion_target.queue_free()
	motion_pivot.queue_free()

	for render_rate in [30, 60, 120, 144]:
		for physics_rate in [30, 60, 120, 240]:
			var rate_pivot_position := Vector2(500.0, 800.0 + float(render_rate + physics_rate))
			var rate_target := _spawn_slime(world, rate_pivot_position + Vector2(200.0, 0.0))
			var rate_pivot := _add_wrap_point(world, rate_pivot_position, 20.0)
			player.global_position = rate_pivot_position + Vector2(-70.0, 0.0)
			var rate_connection := _create_connection(combat, player, rate_target)
			await process_frame
			var elapsed := 0.0
			while elapsed < 1.8:
				elapsed = minf(elapsed + 1.0 / float(render_rate), 1.8)
				var physics_steps := int(floor(elapsed * float(physics_rate)))
				var simulated_physics_time := float(physics_steps) / float(physics_rate)
				var angle := PI - 200.0 * simulated_physics_time / 70.0
				player.global_position = rate_pivot_position + Vector2.from_angle(angle) * 70.0
				rate_connection._process(1.0 / float(render_rate))
			_check(rate_connection.winding_complete, "200 px/s winds at render %d / physics %d Hz" % [render_rate, physics_rate])
			rate_connection.finish_naturally()
			rate_target.queue_free()
			rate_pivot.queue_free()

	# Unsupported collision blocks the line; a marked wall may be routed around.
	var blocked_target := _spawn_slime(world, Vector2(600.0, 400.0))
	var wall := _create_wall(world, Vector2(510.0, 400.0), Vector2(20.0, 100.0))
	player.global_position = Vector2(430.0, 400.0)
	var blocked_connection := _create_connection(combat, player, blocked_target)
	await physics_frame
	blocked_connection._process(1.0 / 60.0)
	_check(not blocked_connection.path_valid, "unmarked wall invalidates and blocks the yarn path")
	blocked_connection.finish_naturally()
	var wall_pivot := _add_wrap_point(wall, Vector2(510.0, 400.0), 56.0)
	var routed_connection := _create_connection(combat, player, blocked_target)
	await physics_frame
	routed_connection._process(1.0 / 60.0)
	_check(routed_connection.is_wrapped and routed_connection.path_valid, "marked wall support routes yarn without drawing through it")
	_check(routed_connection.path_points.size() >= 5, "routed wall path bends around the configured wall envelope")
	_check(_path_clears_circle(routed_connection.path_points, Vector2(510.0, 400.0), 55.0), "routed path remains outside the marked wall envelope")
	routed_connection.finish_naturally()

	# Timeout, cut, target death, and dynamic pivot death invalidate their state.
	var timeout_target := _spawn_slime(world, Vector2(700.0, 600.0))
	player.global_position = Vector2(620.0, 600.0)
	var timeout_connection := _create_connection(combat, player, timeout_target)
	await process_frame
	timeout_connection.lifetime_left = 0.01
	timeout_connection._process(0.02)
	_check(timeout_connection.finished and timeout_connection.last_bind_failure_reason == "连接超时", "connection timeout prevents any later bind")
	var cut_connection := _create_connection(combat, player, timeout_target)
	await process_frame
	_check(cut_connection.cut_by_player(), "Q can cut the active connection")
	_check(cut_connection.finished, "cut connection is removed before later winding")
	var dead_target_connection := _create_connection(combat, player, timeout_target)
	await process_frame
	timeout_target.state = timeout_target.SlimeState.DEAD
	dead_target_connection._process(1.0 / 60.0)
	_check(dead_target_connection.finished, "anchor death cleans up its yarn connection")
	var dead_pivot_target := _spawn_slime(world, Vector2(700.0, 600.0))
	var dead_pivot := _spawn_slime(world, Vector2(660.0, 600.0))
	player.global_position = Vector2(620.0, 600.0)
	var dead_pivot_connection := _create_connection(combat, player, dead_pivot_target)
	await process_frame
	dead_pivot_connection._process(1.0 / 60.0)
	_check(dead_pivot_connection.wrap_pivot == dead_pivot, "dynamic pivot is tracked before death")
	dead_pivot.state = dead_pivot.SlimeState.DEAD
	dead_pivot_connection._process(1.0 / 60.0)
	_check(not dead_pivot_connection.is_wrapped and not dead_pivot_connection.loop_bound, "pivot death clears winding and tension state")
	dead_pivot_connection.finish_naturally()

	# Skill angle cap and connection duration remain unchanged.
	combat.yarn_skill_loop_angle_reduction = 30.0
	_check(combat.on_yarn_hit(_spawn_slime(world, Vector2(850.0, 350.0))), "skill-enabled yarn connection can be created")
	var skilled_connection := combat.active_yarn_connections.back() as YarnConnection
	_check(is_equal_approx(skilled_connection.required_wrap_angle_degrees, 240.0), "technique lowers required winding to the 240-degree cap")
	combat.yarn_skill_loop_angle_reduction = 0.0
	skilled_connection.finish_naturally()

	for enemy in get_nodes_in_group("enemies"):
		if is_instance_valid(enemy):
			enemy.queue_free()
	if is_instance_valid(world):
		for audio_player in world.find_children("*", "AudioStreamPlayer2D", true, false):
			audio_player.stop()
			audio_player.stream = null
		world.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.25).timeout
	if failures.is_empty():
		print("V3_1_1_YARN_PHYSICS_PASSED")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _spawn_slime(parent: Node, position: Vector2) -> CharacterBody2D:
	var slime: CharacterBody2D = load("res://scenes/enemies/slime.tscn").instantiate()
	parent.add_child(slime)
	slime.global_position = position
	slime.set_physics_process(false)
	return slime


func _add_wrap_point(parent: Node, position: Vector2, radius: float) -> Node2D:
	var point := load("res://scenes/combat/yarn_wrap_point.tscn").instantiate() as Node2D
	parent.add_child(point)
	point.global_position = position
	point.set("yarn_wrap_radius", radius)
	return point


func _create_connection(combat: Node, player: Node2D, target: Node2D) -> YarnConnection:
	var connection := load("res://scenes/combat/yarn_connection.tscn").instantiate() as YarnConnection
	connection.configure(player, target, combat)
	current_scene.add_child(connection)
	return connection


func _create_wall(parent: Node, position: Vector2, size: Vector2) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	shape.shape = rectangle
	wall.add_child(shape)
	parent.add_child(wall)
	wall.global_position = position
	return wall


func _path_clears_circle(points: Array[Vector2], center: Vector2, radius: float) -> bool:
	for index in range(points.size() - 1):
		if _distance_to_segment(center, points[index], points[index + 1]) < radius - 0.5:
			return false
	return true


func _path_oriented_arc_degrees(points: Array[Vector2], center: Vector2) -> float:
	var total := 0.0
	for index in range(points.size() - 1):
		var from_vector := points[index] - center
		var to_vector := points[index + 1] - center
		if from_vector.length() >= 18.0 and from_vector.length() <= 24.0 and to_vector.length() >= 18.0 and to_vector.length() <= 24.0:
			total += rad_to_deg(from_vector.angle_to(to_vector))
	return total


func _minimum_path_radius(points: Array[Vector2], center: Vector2) -> float:
	var minimum := INF
	for index in range(points.size() - 1):
		minimum = minf(minimum, _distance_to_segment(center, points[index], points[index + 1]))
	return minimum


func _distance_to_segment(point: Vector2, start: Vector2, end: Vector2) -> float:
	var segment := end - start
	if segment.length_squared() <= 0.001:
		return point.distance_to(start)
	var along := clampf((point - start).dot(segment) / segment.length_squared(), 0.0, 1.0)
	return point.distance_to(start + segment * along)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		failures.append(description)
