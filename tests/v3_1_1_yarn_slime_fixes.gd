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
	var angle_probe := load("res://scenes/combat/yarn_connection.tscn").instantiate() as YarnConnection
	_check(angle_probe._wrap_angle_reaches_threshold(270.0), "positive winding reaches the exact 270-degree threshold")
	_check(angle_probe._wrap_angle_reaches_threshold(-270.0), "negative winding reaches the exact 270-degree threshold")
	_check(angle_probe._wrap_angle_reaches_threshold(269.9999994), "sub-microdegree floating error still reaches the threshold")
	_check(angle_probe._wrap_angle_reaches_threshold(-269.9999994), "negative winding tolerates the same floating error")
	_check(not angle_probe._wrap_angle_reaches_threshold(269.99), "meaningfully sub-threshold winding remains incomplete")
	angle_probe.required_wrap_angle_degrees = 240.0
	_check(angle_probe._wrap_angle_reaches_threshold(240.0), "skill-adjusted positive 240-degree threshold is accepted")
	_check(angle_probe._wrap_angle_reaches_threshold(-239.9999994), "skill-adjusted negative threshold tolerates floating error")
	_check(not angle_probe._wrap_angle_reaches_threshold(239.99), "skill-adjusted winding remains incomplete below tolerance")
	angle_probe.free()
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

	# Reproduce the reviewed 360-degree radial seam case using the routed path
	# builder itself: one pixel of radius change must not add another whole coil.
	var seam_pivot_position := Vector2(400.0, 900.0)
	var seam_target := _spawn_slime(world, seam_pivot_position + Vector2(-200.0, 0.0))
	var seam_pivot := _add_wrap_point(world, seam_pivot_position, 20.0)
	player.global_position = seam_pivot_position + Vector2(70.0, 0.0)
	var seam_connection := _create_connection(combat, player, seam_target)
	await process_frame
	seam_connection._process(1.0 / 60.0)
	seam_connection.wrap_contact_history.clear()
	seam_connection.wrap_contact_history.append(Vector2.RIGHT)
	seam_connection.wrap_player_radius_at_contact = 70.0
	seam_connection.wrap_angle_history.clear()
	seam_connection.wrap_angle_history.append(360.0)
	seam_connection.accumulated_wrap_angle = 360.0
	seam_connection.wrap_side_sign = 1.0
	seam_connection._wrap_route_seeded = true
	seam_connection._wrap_seed_player_side = -1.0
	seam_connection._wrap_seed_target_side = 1.0
	seam_connection._wrap_seed_arc_direction = -1.0
	var seam_radius := seam_connection.wrap_contact_radius + seam_connection.path_clearance
	var legacy_alpha_70 := acos(seam_radius / 70.0)
	var legacy_alpha_71 := acos(seam_radius / 71.0)
	var legacy_seed_angle := -legacy_alpha_70
	var legacy_arc_70 := -fposmod((-legacy_alpha_70) - legacy_seed_angle, TAU) - TAU
	var legacy_arc_71 := -fposmod((-legacy_alpha_71) - legacy_seed_angle, TAU) - TAU
	var legacy_formula_jump_degrees := absf(rad_to_deg(legacy_arc_71 - legacy_arc_70))
	_check(legacy_formula_jump_degrees > 350.0, "reviewed modulo-plus-turn formula reproduces its extra revolution (%.2f degrees)" % legacy_formula_jump_degrees)
	var seam_length_at_70 := seam_connection._routed_path_length()
	player.global_position = seam_pivot_position + Vector2(71.0, 0.0)
	var seam_length_at_71 := seam_connection._routed_path_length()
	var radial_seam_jump := absf(seam_length_at_71 - seam_length_at_70)
	_check(radial_seam_jump < 5.0, "360-degree route remains continuous after a 1px radial pull (observed jump %.2f px)" % radial_seam_jump)
	for seed_side in [-1.0, 1.0]:
		for winding_sign in [-1.0, 1.0]:
			var initial_angle := 0.37
			seam_connection.wrap_contact_history[0] = Vector2.from_angle(initial_angle)
			seam_connection._wrap_seed_player_side = seed_side
			seam_connection._wrap_seed_target_side = -seed_side
			seam_connection._wrap_seed_arc_direction = winding_sign
			seam_target.global_position = seam_pivot_position + Vector2.from_angle(initial_angle + PI + winding_sign * 0.2) * 210.0
			var boundary_lengths: Array[float] = []
			for turn_degrees in [359.0, 360.0, 361.0]:
				seam_connection.wrap_angle_history.clear()
				seam_connection.wrap_angle_history.append(winding_sign * turn_degrees)
				var radius_lengths: Array[float] = []
				for player_radius in [69.0, 70.0, 71.0]:
					player.global_position = seam_pivot_position + Vector2.from_angle(initial_angle + deg_to_rad(winding_sign * turn_degrees)) * player_radius
					radius_lengths.append(seam_connection._routed_path_length())
				boundary_lengths.append(radius_lengths[1])
				_check(absf(radius_lengths[1] - radius_lengths[0]) < 5.0 and absf(radius_lengths[2] - radius_lengths[1]) < 5.0, "inward/outward path length stays continuous at %d degrees for seed %s direction %s" % [int(turn_degrees), seed_side, winding_sign])
			_check(not seam_connection.loop_bound, "geometry-only route changes never bind without an active player pull")
			_check(absf(boundary_lengths[1] - boundary_lengths[0]) < 5.0 and absf(boundary_lengths[2] - boundary_lengths[1]) < 5.0, "route length is continuous through 359/360/361 degrees for seed %s direction %s" % [seed_side, winding_sign])
			var unwind_lengths: Array[float] = []
			for turn_degrees in [361.0, 360.0, 359.0]:
				seam_connection.wrap_angle_history.clear()
				seam_connection.wrap_angle_history.append(winding_sign * turn_degrees)
				player.global_position = seam_pivot_position + Vector2.from_angle(initial_angle + deg_to_rad(winding_sign * turn_degrees)) * 70.0
				unwind_lengths.append(seam_connection._routed_path_length())
			_check(absf(unwind_lengths[1] - unwind_lengths[0]) < 5.0 and absf(unwind_lengths[2] - unwind_lengths[1]) < 5.0, "reverse unwrapping remains continuous across a full-turn boundary")
	seam_connection.winding_complete = true
	seam_connection.wrap_state = YarnConnection.WrapState.WOUND
	seam_connection.player_position_at_wound = player.global_position
	seam_connection.pivot_position_at_wound = seam_pivot_position
	seam_connection.player_radius_at_wound = player.global_position.distance_to(seam_pivot_position)
	seam_connection.routed_path_length_at_wound = seam_connection._routed_path_length()
	seam_connection.effective_rope_length = seam_connection._routed_path_length() + 20.0
	player.global_position += (player.global_position - seam_pivot_position).normalized()
	seam_connection._update_tension_and_bind()
	_check(seam_connection.remaining_slack > 0.0 and not seam_connection.loop_bound, "one-pixel radial change at a full-turn seam cannot consume reserved slack or bind")
	seam_connection.finish_naturally()
	seam_target.queue_free()
	seam_pivot.queue_free()
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
	no_contact_target.queue_free()
	await process_frame

	# Static support: 270 degrees only enters wound state; pulling tight binds A.
	var static_pivot_position := Vector2(500.0, 350.0)
	var static_target := _spawn_slime(world, Vector2(700.0, 350.0))
	var static_pivot := _add_wrap_point(world, static_pivot_position, 20.0)
	player.global_position = Vector2(430.0, 350.0)
	var static_connection := _create_connection(combat, player, static_target, 0.0)
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
	_check(static_target.bind_time_left <= 0.0, "winding without active player pull does not bind even if rope length is exhausted")
	var actual_wrap_history := static_connection.wrap_angle_history.duplicate()
	static_connection.wrap_angle_history.clear()
	static_connection.wrap_angle_history.append(269.999999402585)
	static_connection.winding_complete = false
	static_connection._update_wrap_angle()
	_check(static_connection.winding_complete, "Godot-reproduced 269.9999994-degree result reaches threshold")
	_check(not static_connection.loop_bound, "floating tolerance does not bypass the required active pull")
	static_connection.wrap_angle_history.clear()
	static_connection.wrap_angle_history.append(270.0 - YarnConnection.WRAP_ANGLE_EPSILON_DEGREES * 0.5)
	static_connection.winding_complete = true
	static_connection._update_wrap_angle()
	_check(static_connection.winding_complete, "sub-tolerance edge noise does not flicker winding completion")
	_check(not static_connection.loop_bound, "threshold tolerance alone cannot bind before active tension")
	static_connection.wrap_angle_history[0] = 270.0 - YarnConnection.WRAP_ANGLE_EPSILON_DEGREES * 2.0
	static_connection._update_wrap_angle()
	_check(not static_connection.winding_complete, "deliberate reverse unwrapping beyond tolerance clears completion")
	static_connection.wrap_angle_history = actual_wrap_history
	static_connection.accumulated_wrap_angle = static_connection._history_wrap_angle_degrees()
	static_connection.winding_complete = true
	static_connection.wrap_state = YarnConnection.WrapState.WOUND
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
	static_connection.stop_feeding()
	var final_radial := (player.global_position - static_pivot_position).normalized()
	player.global_position += final_radial * 30.0
	static_connection._process(1.0 / 60.0)
	_check(static_connection.is_taut, "pulling away after winding satisfies configurable tension")
	_check(static_connection.loop_bound, "taut static-pivot yarn binds anchor A")
	_check(static_target.bind_time_left >= 1.5, "static-pivot bind uses the 1.5-second base duration")
	_check(not static_pivot.is_in_group("enemies"), "static scenery pivot is never treated as an enemy target")
	static_connection.finish_naturally()

	var teleport_pivot_position := Vector2(780.0, 500.0)
	var teleport_target := _spawn_slime(world, teleport_pivot_position + Vector2(200.0, 0.0))
	var teleport_pivot := _add_wrap_point(world, teleport_pivot_position, 20.0)
	player.global_position = teleport_pivot_position + Vector2(-70.0, 0.0)
	var teleport_connection := _create_connection(combat, player, teleport_target)
	await process_frame
	teleport_connection._process(1.0 / 60.0)
	for step in range(1, 46):
		player.global_position = teleport_pivot_position + Vector2.from_angle(PI - deg_to_rad(6.0 * step)) * 70.0
		teleport_connection._process(1.0 / 60.0)
	_check(teleport_connection.winding_complete and not teleport_connection.loop_bound, "teleport fixture reaches wound state without tension")
	var winding_before_teleport := teleport_connection.accumulated_wrap_angle
	var teleport_radial := (player.global_position - teleport_pivot_position).normalized()
	player.global_position += teleport_radial * 100.0
	teleport_connection._process(1.0 / 60.0)
	_check(not teleport_connection.winding_complete and not teleport_connection.loop_bound and absf(teleport_connection.accumulated_wrap_angle) < absf(winding_before_teleport), "large teleport invalidates completed winding and tension baseline")
	for _idle_frame in range(5):
		teleport_connection._process(1.0 / 60.0)
	_check(not teleport_connection.loop_bound and not teleport_connection.is_taut, "standing still after teleport cannot trigger delayed binding")
	teleport_connection.finish_naturally()
	teleport_target.queue_free()
	teleport_pivot.queue_free()
	await process_frame
	var revive_pivot_position := Vector2(500.0, 680.0)
	var revive_target := _spawn_slime(world, revive_pivot_position + Vector2(200.0, 0.0))
	var revive_pivot := _add_wrap_point(world, revive_pivot_position, 20.0)
	player.global_position = revive_pivot_position + Vector2(-70.0, 0.0)
	var revive_connection := _create_connection(combat, player, revive_target)
	await process_frame
	revive_connection._process(1.0 / 60.0)
	_check(revive_connection.is_wrapped, "short-respawn fixture attaches to a valid support")
	revive_connection.wrap_angle_history.clear()
	revive_connection.wrap_angle_history.append(270.0)
	revive_connection.accumulated_wrap_angle = 270.0
	revive_connection.winding_complete = true
	revive_connection.wrap_state = YarnConnection.WrapState.WOUND
	revive_connection.player_position_at_wound = player.global_position
	revive_connection.pivot_position_at_wound = revive_pivot.global_position
	revive_connection.player_radius_at_wound = player.global_position.distance_to(revive_pivot.global_position)
	revive_connection.routed_path_length_at_wound = revive_connection._routed_path_length()
	_check(revive_connection.winding_complete, "short-respawn fixture starts in the wound-but-not-taut state")
	player.revive_from_expedition(player.global_position + Vector2(12.0, 0.0))
	revive_connection._process(1.0 / 60.0)
	_check(not revive_connection.winding_complete and not revive_connection.loop_bound, "short respawn teleport invalidates yarn despite being below the distance threshold")
	for _idle_frame in range(5):
		revive_connection._process(1.0 / 60.0)
	_check(not revive_connection.loop_bound, "short respawn followed by stillness cannot reuse the old tension baseline")
	revive_connection.finish_naturally()
	revive_target.queue_free()
	revive_pivot.queue_free()
	await process_frame
	static_target.bind_time_left = 0.0
	static_target.bind_resistance_left = 1.0
	_check(not static_target.apply_yarn_bind(1.5), "control immunity rejects a new yarn bind")
	static_pivot.queue_free()
	static_target.queue_free()
	await process_frame

	var counterclockwise_pivot_position := Vector2(500.0, 350.0)
	var counterclockwise_target := _spawn_slime(world, Vector2(700.0, 350.0))
	var counterclockwise_pivot := _add_wrap_point(world, counterclockwise_pivot_position, 20.0)
	player.global_position = Vector2(430.0, 350.0)
	var counterclockwise_connection := _create_connection(combat, player, counterclockwise_target, 0.0)
	await process_frame
	counterclockwise_connection._process(1.0 / 60.0)
	for step in range(1, 46):
		player.global_position = counterclockwise_pivot_position + Vector2.from_angle(PI + deg_to_rad(6.0 * step)) * 70.0
		counterclockwise_connection._process(1.0 / 60.0)
	_check(counterclockwise_connection.winding_complete, "counterclockwise pivot winding reaches 270 degrees")
	counterclockwise_connection.stop_feeding()
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
	reverse_target.queue_free()

	# Dynamic enemy B is an explicit pivot; a taut wrap binds both A and B.
	var dynamic_pivot_position := Vector2(400.0, 200.0)
	var anchor_bait := _spawn_slime(world, Vector2(600.0, 200.0))
	var dynamic_pivot := _spawn_slime(world, dynamic_pivot_position)
	player.global_position = Vector2(330.0, 200.0)
	var dynamic_connection := _create_connection(combat, player, anchor_bait, 0.0)
	await process_frame
	dynamic_connection._process(1.0 / 60.0)
	_check(dynamic_connection.is_wrapped and dynamic_connection.wrap_pivot == dynamic_pivot, "enemy B is detected as a dynamic pivot, not anchor A")
	dynamic_connection.set_process(false)
	for step in range(1, 46):
		var orbit := Vector2.from_angle(PI - deg_to_rad(6.0 * step)) * 70.0
		dynamic_pivot.global_position = dynamic_pivot_position + Vector2(0.1 * step, 0.0)
		anchor_bait.global_position = Vector2(600.0, 200.0) + Vector2(0.0, 0.1 * step)
		player.global_position = dynamic_pivot.global_position + orbit
		await physics_frame
		dynamic_connection._process(1.0 / 60.0)
	_check(dynamic_connection.winding_complete, "dynamic pivot motion does not erase cat winding")
	_check(not dynamic_connection.loop_bound, "dynamic pivot winding still waits for tension")
	dynamic_connection.stop_feeding()
	var dynamic_radial := (player.global_position - dynamic_pivot.global_position).normalized()
	player.global_position += dynamic_radial * 30.0
	dynamic_connection._process(1.0 / 60.0)
	_check(dynamic_connection.loop_bound, "tight dynamic-pivot yarn triggers binding")
	_check(anchor_bait.bind_time_left > 0.0 and dynamic_pivot.bind_time_left > 0.0, "enemy pivot wrap binds both A and B")
	dynamic_connection.finish_naturally()
	anchor_bait.queue_free()
	dynamic_pivot.queue_free()
	await process_frame

	# Moving enemy B must change the current tangent geometry without counting
	# B's movement as cat winding. The slime's collision circle is offset from
	# its CharacterBody2D origin, so validate against the actual shape center.
	var moving_support := _spawn_slime(world, Vector2(700.0, 300.0))
	var moving_anchor := _spawn_slime(world, Vector2(900.0, 300.0))
	var support_shape := moving_support.get_node("CollisionShape2D") as CollisionShape2D
	# Re-run the reviewed pre-fix endpoint-angle formula with its supplied
	# geometry. Its tangent matches the review's point, but is not tangent to the
	# player's current direction after B moves; this is the reproducible defect.
	var legacy_player := Vector2(-40.0, 70.0)
	var legacy_radius := 15.0
	var legacy_current_relative := legacy_player
	var legacy_alpha := acos(legacy_radius / legacy_current_relative.length())
	var legacy_tangent_angle := PI + deg_to_rad(270.0) - legacy_alpha
	var legacy_tangent := Vector2.from_angle(legacy_tangent_angle) * legacy_radius
	var legacy_collision_center := Vector2(0.0, 7.0)
	var legacy_clearance := _distance_to_segment(legacy_collision_center, legacy_player, legacy_tangent)
	var current_phi := legacy_current_relative.angle()
	var current_alpha := acos(legacy_radius / legacy_current_relative.length())
	var current_tangent_angle := current_phi - current_alpha
	var stale_tangent_error := absf(rad_to_deg(wrapf(legacy_tangent_angle - current_tangent_angle, -PI, PI)))
	_check(legacy_tangent.distance_to(Vector2(14.7381, 2.7908)) < 0.01, "reviewed old formula reproduces its stale endpoint tangent")
	_check(stale_tangent_error > 20.0, "old formula's endpoint tangent is not tangent to the current player position (%.2f degrees; finite segment clearance %.2fpx)" % [stale_tangent_error, legacy_clearance])
	var physical_support_center := support_shape.global_position
	player.global_position = physical_support_center + Vector2(-70.0, 0.0)
	var moving_connection := _create_connection(combat, player, moving_anchor)
	await physics_frame
	moving_connection.set_process(false)
	moving_connection.wrap_pivot = moving_support
	moving_connection._dynamic_pivot = true
	moving_connection.is_wrapped = true
	moving_connection.wrap_state = YarnConnection.WrapState.WOUND
	moving_connection.wrap_contact_radius = 14.0
	moving_connection.wrap_player_radius_at_contact = 70.0
	moving_connection.wrap_contact_history = [Vector2.LEFT]
	moving_connection.wrap_angle_history = [270.0]
	moving_connection.accumulated_wrap_angle = 270.0
	moving_connection.winding_complete = true
	moving_connection.wrap_side_sign = 1.0
	moving_connection._wrap_route_seeded = true
	moving_connection._wrap_seed_player_side = -1.0
	moving_connection._wrap_seed_target_side = 1.0
	moving_connection._wrap_seed_arc_direction = 1.0
	player.global_position = physical_support_center + Vector2(0.0, 70.0)
	moving_connection._last_observed_player_position = player.global_position
	moving_connection._last_pivot_position = physical_support_center
	moving_connection.player_position_at_wound = player.global_position
	moving_connection.pivot_position_at_wound = physical_support_center
	moving_connection.player_radius_at_wound = player.global_position.distance_to(physical_support_center)
	moving_connection.routed_path_length_at_wound = moving_connection._routed_path_length()
	var winding_before_pivot_motion := moving_connection.accumulated_wrap_angle
	moving_support.global_position += Vector2(40.0, 0.0)
	await physics_frame
	var moving_path := moving_connection._build_routed_path()
	var current_shape_center := support_shape.global_position
	var minimum_actual_clearance := INF
	for segment_index in range(moving_path.size() - 1):
		minimum_actual_clearance = minf(minimum_actual_clearance, _distance_to_segment(current_shape_center, moving_path[segment_index], moving_path[segment_index + 1]))
	_check(is_equal_approx(moving_connection._get_support_center(moving_support).y, current_shape_center.y), "dynamic support routing uses the offset physical collision center")
	_check(minimum_actual_clearance >= 12.0, "moving enemy pivot route stays outside its actual 12px collision circle (%.2fpx)" % minimum_actual_clearance)
	_check(moving_connection._validate_current_path(), "dynamic pivot collision layer participates in routed-path validation")
	for seed_side in [-1.0, 1.0]:
		for winding_sign in [-1.0, 1.0]:
			moving_connection.wrap_angle_history.clear()
			moving_connection.wrap_angle_history.append(winding_sign * 270.0)
			moving_connection._wrap_seed_player_side = seed_side
			moving_connection._wrap_seed_target_side = -seed_side
			moving_connection._wrap_seed_arc_direction = winding_sign
			var variant_path := moving_connection._build_routed_path()
			var variant_clearance := INF
			for segment_index in range(variant_path.size() - 1):
				variant_clearance = minf(variant_clearance, _distance_to_segment(current_shape_center, variant_path[segment_index], variant_path[segment_index + 1]))
			_check(variant_clearance >= 12.0, "dynamic route for seed side %s and winding %s clears the physical slime collider" % [seed_side, winding_sign])
			_check(moving_connection._validate_current_path(), "dynamic route remains collision-valid for both winding directions and seed sides")
	moving_connection.wrap_angle_history.clear()
	moving_connection.wrap_angle_history.append(270.0)
	moving_connection._wrap_seed_player_side = -1.0
	moving_connection._wrap_seed_target_side = 1.0
	moving_connection._wrap_seed_arc_direction = 1.0
	moving_connection._process(1.0 / 60.0)
	_check(is_equal_approx(moving_connection.accumulated_wrap_angle, winding_before_pivot_motion), "stationary cat gains no active winding when enemy B moves")
	_check(not moving_connection.loop_bound, "stationary cat cannot trigger active tension from enemy B movement")
	moving_support.global_position += Vector2(0.0, 30.0)
	await physics_frame
	moving_connection._process(1.0 / 60.0)
	_check(is_equal_approx(moving_connection.accumulated_wrap_angle, winding_before_pivot_motion) and not moving_connection.loop_bound, "radial movement of B alone cannot add winding or trigger tension")
	moving_connection.finish_naturally()
	moving_support.queue_free()
	moving_anchor.queue_free()
	await process_frame

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


func _create_connection(combat: Node, player: Node2D, target: Node2D, initial_slack: float = 72.0) -> YarnConnection:
	var connection := load("res://scenes/combat/yarn_connection.tscn").instantiate() as YarnConnection
	connection.configure(player, target, combat)
	connection.initial_slack_length = initial_slack
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
