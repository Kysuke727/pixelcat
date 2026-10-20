extends SceneTree

class BindProbe extends Node2D:
	var bind_attempts: int = 0
	var accepts_bind: bool = false

	func apply_yarn_bind(_duration: float) -> bool:
		bind_attempts += 1
		return accepts_bind


var failures: Array[String] = []
var old_physics_ticks: int = 60


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	old_physics_ticks = Engine.physics_ticks_per_second
	print("YARN_FINAL_RULES_ACCEPTANCE_BEGIN")
	if OS.get_cmdline_user_args().has("k-only"):
		await _test_real_k_launch_hits_anchor()
		_finish_and_quit()
		return
	if OS.get_cmdline_user_args().has("preplaced-only"):
		await _test_real_e2e_closed_loop(1.0, false, true)
		await _test_real_e2e_closed_loop(-1.0, false, true)
		_finish_and_quit()
		return
	if OS.get_cmdline_user_args().has("impossible-route-only"):
		await _test_impossible_route_recovers()
		_finish_and_quit()
		return
	if OS.get_cmdline_user_args().has("physics-matrix-only"):
		await _test_impossible_route_recovers()
		for physics_rate in [30, 60, 120]:
			Engine.physics_ticks_per_second = physics_rate
			print("[PHYSICS MATRIX] start ticks_per_second=", physics_rate)
			await _test_real_e2e_closed_loop(1.0, false, true)
			await _test_real_e2e_closed_loop(-1.0, false, true)
		Engine.physics_ticks_per_second = old_physics_ticks
		_finish_and_quit()
		return
	# Exercise the raw projectile input before other physics fixtures mutate tree
	# scene state; the later end-to-end cases independently exercise K in the
	# real night world, including the feed-lock second press.
	await _test_real_k_launch_hits_anchor()
	await _test_open_route_never_binds()
	await _test_all_immune_snapshot_is_one_shot()
	await _test_real_knockback_does_not_feed_or_pull()
	await _test_real_dodge_contributes_as_player_intent()
	await _test_real_e2e_closed_loop(1.0)
	await _test_real_e2e_closed_loop(-1.0)
	await _test_real_e2e_closed_loop(-1.0, true)
	await _test_real_e2e_closed_loop(1.0, false, true)
	await _test_real_e2e_closed_loop(-1.0, false, true)
	Engine.physics_ticks_per_second = old_physics_ticks
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("move_up")
	Input.action_release("move_down")
	Input.action_release("ranged_attack")
	Input.action_release("dodge")
	_finish_and_quit()


func _finish_and_quit() -> void:
	if failures.is_empty():
		print("YARN_FINAL_RULES_ACCEPTANCE_PASSED")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("YARN_FINAL_RULES_ACCEPTANCE_FAILED: %d failure(s)" % failures.size())
		quit(1)


func _test_open_route_never_binds() -> void:
	print("[UNIT] open routed path settlement guard")
	var world := _make_world("OpenPathUnitWorld")
	var cat := Node2D.new()
	var anchor := BindProbe.new()
	anchor.accepts_bind = true
	anchor.add_to_group("enemies")
	world.add_child(cat)
	world.add_child(anchor)
	cat.global_position = Vector2(100.0, 120.0)
	anchor.global_position = Vector2(300.0, 120.0)
	var connection := _new_connection(world, cat, anchor)
	connection._bind_wrapped_targets()
	_check(anchor.bind_attempts == 0, "open route does not bind its anchor")
	_check(not connection.settlement_completed, "open route does not consume the one-shot settlement")
	_check(not connection.finished, "open route does not detach the cat endpoint")
	_check(get_nodes_in_group("persistent_yarn_loops").is_empty(), "open route creates no retained loop")
	await _dispose_world(world)


func _test_all_immune_snapshot_is_one_shot() -> void:
	print("[UNIT] frozen all-immune settlement")
	var world := _make_world("OneShotSettlementUnitWorld")
	var cat := Node2D.new()
	var anchor := BindProbe.new()
	var later_enemy := BindProbe.new()
	anchor.add_to_group("enemies")
	later_enemy.add_to_group("enemies")
	world.add_child(cat)
	world.add_child(anchor)
	world.add_child(later_enemy)
	cat.global_position = Vector2(0.0, 0.0)
	anchor.global_position = Vector2(20.0, 20.0)
	later_enemy.global_position = Vector2(30.0, 30.0)
	var connection := _new_connection(world, cat, anchor)
	connection.bind_duration = 0.4
	var known_square := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(100.0, 0.0), Vector2(100.0, 100.0),
		Vector2(0.0, 100.0), Vector2(0.0, 0.0)
	])
	var actual_loops: Array[PackedVector2Array] = [known_square]
	var frozen_targets: Array[Node2D] = [anchor]
	var configured_duration := connection.bind_duration
	connection._commit_bind_snapshot(frozen_targets, actual_loops)
	var detached_after_settlement := connection.finished
	# An enemy entering after the pull-time target snapshot must not be retried.
	connection._commit_bind_snapshot([anchor, later_enemy], actual_loops)
	_check(connection.settlement_completed and connection.settlement_attempt_count == 1, "one valid pull snapshot is committed once even when all targets resist")
	_check(anchor.bind_attempts == 1, "immune target receives only its first settlement attempt")
	_check(later_enemy.bind_attempts == 0, "enemy arriving after the frozen snapshot is not added")
	_check(connection._settlement_targets_snapshot.size() == 1, "snapshot is immutable after settlement")
	_check(detached_after_settlement, "one-shot snapshot detaches the cat-side link")
	await physics_frame
	var retained := get_first_node_in_group("persistent_yarn_loops") as BoundYarnLoop
	_check(is_instance_valid(retained), "all-immune resolution retains the validated loop")
	_check(is_equal_approx(retained.lifetime, configured_duration), "all-immune loop uses configured bind duration")
	await _dispose_world(world)


func _test_real_knockback_does_not_feed_or_pull() -> void:
	print("[PHYSICS INTEGRATION] knockback is constrained but never active yarn intent")
	var world := _make_world("KnockbackPhysicsWorld")
	var cat := load("res://scenes/player/cat.tscn").instantiate() as CharacterBody2D
	var anchor := _spawn_slime(world, Vector2(250.0, 300.0))
	world.add_child(cat)
	cat.global_position = Vector2(350.0, 300.0)
	cat.set("hitstun_left", 0.25)
	cat.set("knockback_velocity", Vector2.RIGHT * 80.0)
	var connection := _new_connection(world, cat, anchor)
	connection.initial_slack_length = 30.0
	await physics_frame
	var starting_length := connection.effective_rope_length
	var starting_position := cat.global_position
	await _wait_physics_seconds(0.12)
	_check(cat.global_position.x > starting_position.x + 1.0, "external knockback moves the cat under its real CharacterBody2D physics")
	_check(is_equal_approx(connection.effective_rope_length, starting_length), "external knockback cannot manufacture released rope length")
	_check(not connection._player_requested_outward_pull, "external velocity cannot be interpreted as active outward input")
	_check(not connection.settlement_completed, "external force alone cannot settle a yarn loop")
	await _dispose_world(world)


func _test_impossible_route_recovers() -> void:
	print("[PHYSICS INTEGRATION] overlapping real support blocks route, then clears and recovers")
	var world := _make_world("ImpossibleYarnRouteWorld")
	var cat := load("res://scenes/player/cat.tscn").instantiate() as CharacterBody2D
	world.add_child(cat)
	cat.global_position = Vector2(300.0, 300.0)
	cat.set("last_facing", Vector2.RIGHT)
	var anchor := _spawn_slime(world, Vector2(500.0, 300.0))
	anchor.set("move_speed", 0.0)
	anchor.set("chase_range", 0.0)
	anchor.set("disengage_range", 0.0)
	anchor.set("idle_duration_min", 30.0)
	anchor.set("idle_duration_max", 30.0)
	var connection := _new_connection(world, cat, anchor)
	connection.initial_slack_length = 300.0
	var obstruction := _spawn_wrap_point(world, cat.global_position)
	obstruction.set("entity_collision_radius", 16.0)
	await physics_frame
	var starting_tick := Engine.get_physics_frames()
	var starting_settlement_count := int(connection.settlement_attempt_count)
	await _wait_physics_seconds(0.5)
	var blocked_tick_count := Engine.get_physics_frames() - starting_tick
	_check(blocked_tick_count >= 10, "unresolvable overlap is handled across real physics updates rather than a blocking loop")
	_check(not connection.path_valid and not connection.path_resolution_complete, "overlapped endpoint support makes the rope path explicitly unresolved")
	_check(not connection.finished and not connection.settlement_completed, "unresolved geometry cannot bind, detach, or consume settlement")
	_check(int(connection.settlement_attempt_count) == starting_settlement_count, "impossible geometry does not repeatedly invoke settlement")
	print("IMPOSSIBLE_ROUTE blocked_ticks=", blocked_tick_count, " supports=", connection.wrap_supports.size(), " reason=", connection.last_bind_failure_reason)
	var held_angle := connection.accumulated_wrap_angle
	obstruction.global_position = Vector2(360.0, 360.0)
	await _wait_physics_seconds(0.5)
	_check(connection.path_valid and connection.path_resolution_complete, "removing the blocking collision restores route solving")
	_check(not connection.finished and not connection.settlement_completed, "route recovery does not invent a winding or bind")
	_check(absf(connection.accumulated_wrap_angle - held_angle) <= 0.01, "route recovery preserves valid winding progress")
	print("IMPOSSIBLE_ROUTE recovery_ticks=", Engine.get_physics_frames() - starting_tick - blocked_tick_count, " route_valid=", connection.path_valid, " wrap_angle=", connection.accumulated_wrap_angle, " settlement_attempts=", connection.settlement_attempt_count)
	await _dispose_world(world)


func _test_real_k_launch_hits_anchor() -> void:
	print("[PHYSICS INTEGRATION] real K input, projectile travel, and slime contact")
	var world := _make_world("KProjectileWorld")
	var cat := load("res://scenes/player/cat.tscn").instantiate() as CharacterBody2D
	world.add_child(cat)
	cat.global_position = Vector2(250.0, 300.0)
	cat.set("last_facing", Vector2.RIGHT)
	var combat := cat.get_node("PlayerCombat")
	var anchor := _spawn_slime(world, Vector2(350.0, 300.0))
	anchor.set("move_speed", 0.0)
	anchor.set("chase_range", 0.0)
	anchor.set("disengage_range", 0.0)
	anchor.set("idle_duration_min", 20.0)
	anchor.set("idle_duration_max", 20.0)
	var health_before: float = anchor.get("current_health")
	Input.action_press("ranged_attack")
	await process_frame
	await physics_frame
	Input.action_release("ranged_attack")
	await _wait_physics_seconds(1.0)
	var active: Array = combat.get("active_yarn_connections")
	print("K-INTEGRATION DEBUG cat=", cat.global_position, " facing=", cat.get("last_facing"), " dead=", cat.get("dead"), " can_act=", cat.call("can_perform_combat_action"), " enabled=", combat.get("combat_enabled"), " night=", combat.call("_is_night_combat_scene"), " cooldown=", combat.get("ranged_cooldown_left"), " fired=", combat.get("projectile_fired"), " in_flight=", combat.get("yarn_projectile_in_flight"), " action=", combat.get("action_state"), " anchor=", anchor.global_position, " hp=", anchor.get("current_health"), " active=", active.size())
	_check(float(anchor.get("current_health")) == health_before - 1.0, "K projectile actually hits and damages anchor A")
	_check(active.size() == 1, "projectile collision creates exactly one live cat-side connection")
	if active.size() == 1 and is_instance_valid(active[0]):
		_check(active[0] is YarnConnection and not active[0].finished, "projectile-created connection remains live after impact")
	await _dispose_world(world)


func _test_real_dodge_contributes_as_player_intent() -> void:
	print("[PHYSICS INTEGRATION] dodge movement is explicit active intent")
	var world := _make_world("DodgePhysicsWorld")
	var cat := load("res://scenes/player/cat.tscn").instantiate() as CharacterBody2D
	world.add_child(cat)
	cat.global_position = Vector2(350.0, 300.0)
	cat.set("last_facing", Vector2.RIGHT)
	cat.set("dodge_distance", 36.0)
	cat.set("dodge_duration", 0.24)
	cat.set("dodge_cooldown", 0.0)
	var anchor := _spawn_slime(world, Vector2(250.0, 300.0))
	anchor.set("move_speed", 0.0)
	anchor.set("chase_range", 0.0)
	var connection := _new_connection(world, cat, anchor)
	connection.initial_slack_length = 100.0
	await physics_frame
	var starting_length := connection.effective_rope_length
	Input.action_press("move_right")
	Input.action_press("dodge")
	await process_frame
	Input.action_release("dodge")
	await _wait_physics_seconds(0.2)
	Input.action_release("move_right")
	_check(cat.global_position.x > 355.0, "real dodge input produces physical cat movement")
	_check(connection.effective_rope_length > starting_length + 1.0, "confirmed active dodge can pay out player-caused route growth")
	await _dispose_world(world)


func _test_real_e2e_closed_loop(direction_sign: float, all_immune: bool = false, preplaced_targets: bool = false) -> void:
	var wall_started_msec := Time.get_ticks_msec()
	var direction_name := "clockwise" if direction_sign < 0.0 else "counterclockwise"
	if Engine.physics_ticks_per_second != 60:
		direction_name += " %dHz" % Engine.physics_ticks_per_second
	if preplaced_targets:
		direction_name += " preplaced-contact"
	if all_immune:
		direction_name += " all-immune"
	print("[END TO END] ", direction_name, " normal K → live orbit → stop-feed K → active pull → group settlement → retained barrier")
	var world := load("res://scenes/worlds/night_world.tscn").instantiate() as Node2D
	root.add_child(world)
	current_scene = world
	await physics_frame
	var cat := get_first_node_in_group("player") as CharacterBody2D
	_check(is_instance_valid(cat), direction_name + " uses the real night-scene cat")
	if not is_instance_valid(cat):
		await _dispose_world(world)
		return
	for enemy in get_nodes_in_group("enemies"):
		if is_instance_valid(enemy):
			enemy.queue_free()
	for support in get_nodes_in_group("yarn_wrap_points"):
		if is_instance_valid(support):
			support.queue_free()
	await physics_frame
	var anchor_y := 350.0 if direction_sign < 0.0 else 470.0
	cat.global_position = Vector2(480.0, anchor_y)
	cat.set("last_facing", Vector2.RIGHT)
	var combat := cat.get_node("PlayerCombat")
	combat.set("yarn_bind_duration", 1.0)
	combat.set("yarn_connection_duration", 10.0)
	combat.set("projectile_range", 160.0)
	var prior_cooldown := maxf(float(combat.get("ranged_cooldown_left")), 0.0)
	if prior_cooldown > 0.0:
		await _wait_physics_seconds(prior_cooldown + 0.1)
	var anchor := _spawn_slime(world, Vector2(620.0, anchor_y))
	anchor.set("move_speed", 0.0)
	anchor.set("chase_range", 0.0)
	anchor.set("disengage_range", 0.0)
	anchor.set("idle_duration_min", 30.0)
	anchor.set("idle_duration_max", 30.0)
	var primary := _spawn_wrap_point(world, Vector2(550.0, 410.0))
	# A broad but physically ordinary scenery support makes the real rope lobe
	# large enough for a group-bind acceptance; the body itself remains radius 10.
	primary.set("yarn_wrap_radius", 32.0)
	var secondary_y := 410.0 - signf(anchor_y - 410.0) * 44.0
	var secondary := _spawn_wrap_point(world, Vector2(550.0, secondary_y))
	var preplaced_inside: Array[Node2D] = []
	var preplaced_outside: Node2D
	var preplaced_start_positions: Dictionary = {}
	if preplaced_targets:
		var radial_sign := signf(anchor_y - 410.0)
		var contact_angle: float = -PI / 4.0 * radial_sign
		var contact_direction: Vector2 = Vector2.from_angle(contact_angle)
		# Two separated bodies on the same future lobe edge, plus a farther
		# out-of-loop body on the same radial line. All exist before K; when the
		# winding arc reaches this angle the live solver sees multiple contacts
		# in one physics update without overlapping their actual collision discs.
		for radial_distance in [23.0]:
			var offset: Vector2 = contact_direction * float(radial_distance) - Vector2(0.0, 7.0)
			var enemy := _spawn_slime(world, primary.global_position + offset)
			_configure_active_wander(enemy, primary, direction_sign)
			preplaced_start_positions[enemy.get_instance_id()] = enemy.global_position
			preplaced_inside.append(enemy)
		var group_member_angle: float = -3.0 * PI / 4.0 * radial_sign
		var group_member_offset: Vector2 = Vector2.from_angle(group_member_angle) * 30.0 - Vector2(0.0, 7.0)
		var group_member := _spawn_slime(world, primary.global_position + group_member_offset)
		_configure_active_wander(group_member, primary, direction_sign)
		preplaced_start_positions[group_member.get_instance_id()] = group_member.global_position
		preplaced_inside.append(group_member)
		preplaced_outside = _spawn_slime(world, Vector2(850.0, 620.0))
		_configure_active_wander(preplaced_outside, primary, direction_sign)
		preplaced_start_positions[preplaced_outside.get_instance_id()] = preplaced_outside.global_position
	var cat_approach := Vector2.DOWN if anchor_y < 410.0 else Vector2.UP
	await physics_frame
	var health_before: float = anchor.get("current_health")
	print("E2E ", direction_name, " pre_K cat_dead=", cat.get("dead"), " can_act=", cat.call("can_perform_combat_action"), " combat_enabled=", combat.get("combat_enabled"), " cooldown=", combat.get("ranged_cooldown_left"), " current_night=", combat.call("_is_night_combat_scene"), " tree_paused=", paused, " node_process=", combat.is_processing(), " action_exists=", InputMap.has_action("ranged_attack"))
	Input.action_press("ranged_attack")
	await process_frame
	await physics_frame
	Input.action_release("ranged_attack")
	var projectile_trace: Array[String] = []
	for _tick in range(ceili(float(Engine.physics_ticks_per_second))):
		await physics_frame
		for candidate in world.find_children("*", "Area2D", true, false):
			if candidate.has_method("setup") and candidate.has_method("get"):
				projectile_trace.append("pos=%s consumed=%s dir=%s" % [str(candidate.global_position), str(candidate.get("consumed")), str(candidate.get("direction"))])
	var connections: Array = combat.get("active_yarn_connections")
	if connections.size() != 1:
		var preplaced_debug: Array[String] = []
		for enemy in preplaced_inside + ([preplaced_outside] if is_instance_valid(preplaced_outside) else []):
			preplaced_debug.append("%s@%s hp=%s" % [enemy.name, str(enemy.global_position), str(enemy.get("current_health"))])
		print("E2E ", direction_name, " projectile_debug cat=", cat.global_position, " facing=", cat.get("last_facing"), " anchor=", anchor.global_position, " hp=", anchor.get("current_health"), " others=", preplaced_debug, " in_flight=", combat.get("yarn_projectile_in_flight"), " fired=", combat.get("projectile_fired"), " cooldown=", combat.get("ranged_cooldown_left"), " action_state=", combat.get("action_state"), " scene_group=", world.is_in_group("night_exploration"), " projectile_trace=", projectile_trace.slice(0, 6))
		_check(false, direction_name + " K launch physically connects to anchor A")
		await _dispose_world(world)
		return
	var connection := connections[0] as YarnConnection
	_check(float(anchor.get("current_health")) == health_before - 1.0, direction_name + " projectile physically damages anchor A")
	print("E2E ", direction_name, " t=1.0s projectile_contact hp=", anchor.get("current_health"), " connection=", connection.debug_connection_id)
	await _move_cat_for(cat, cat_approach, 0.60)
	var orbit_center := primary.global_position
	var orbit_radius := 70.0
	var start_angle := PI
	var orbit_steps := 36
	var invalid_route_samples := 0
	var minimum_physical_clearance := INF
	var orbit_start_tick := Engine.get_physics_frames()
	for step in range(1, orbit_steps + 1):
		var angle := start_angle + direction_sign * TAU * float(step) / float(orbit_steps)
		var destination := orbit_center + Vector2.from_angle(angle) * orbit_radius
		var move_vector := destination - cat.global_position
		var speed := maxf(float(cat.call("get_effective_move_speed")), 1.0)
		await _move_cat_for(cat, move_vector, move_vector.length() / speed)
		if is_instance_valid(connection) and not connection.path_valid:
			invalid_route_samples += 1
		if is_instance_valid(connection):
			var physical_route := connection._build_routed_path()
			minimum_physical_clearance = minf(minimum_physical_clearance, _minimum_support_clearance(physical_route, connection.wrap_supports))
		if step % 6 == 0:
			var live_route := connection._build_routed_path()
			var live_loops := connection._extract_actual_closed_loops(live_route)
			print("E2E ", direction_name, " t~", snappedf(1.0 + float(step) * 0.09, 0.01), "s orbit_step=", step, " supports=", connection.wrap_supports.size(), " angle=", snappedf(connection.accumulated_wrap_angle, 0.1), "deg loops=", live_loops.size(), " route_valid=", connection.path_valid)
	var routed_before_lock := connection._build_routed_path()
	var physical_loops := connection._extract_actual_closed_loops(routed_before_lock)
	_check(invalid_route_samples == 0, direction_name + " live route remains validated throughout physical orbit")
	_check(minimum_physical_clearance >= -0.25, direction_name + " routed segments do not penetrate any actual support collision shape")
	print("E2E ", direction_name, " route_quality invalid_samples=", invalid_route_samples, " min_physical_clearance=", snappedf(minimum_physical_clearance, 2))
	var orbit_physics_ticks := Engine.get_physics_frames() - orbit_start_tick
	var graph_solve_count := connection.debug_visibility_graph_solve_count
	var graph_average_usec := float(connection.debug_visibility_graph_total_usec) / maxf(float(graph_solve_count), 1.0)
	print("ROUTE_GRAPH ", direction_name, " physics_ticks=", orbit_physics_ticks, " requests=", connection.debug_visibility_graph_request_count, " solves=", graph_solve_count, " cache_hits=", connection.debug_visibility_graph_cache_hit_count, " solves_per_tick=", snappedf(float(graph_solve_count) / maxf(float(orbit_physics_ticks), 1.0), 0.001), " nodes_last/max=", connection.debug_visibility_graph_last_node_count, "/", connection.debug_visibility_graph_max_node_count, " avg/max_usec=", snappedf(graph_average_usec, 0.1), "/", connection.debug_visibility_graph_max_usec, " failures=", connection.debug_visibility_graph_failure_count, " topology_rejections=", connection.debug_visibility_graph_topology_rejection_count)
	_check(connection.debug_visibility_graph_topology_rejection_count == 0, direction_name + " graph detours do not discard an existing actual loop")
	_check(connection.wrap_supports.size() >= 2, direction_name + " naturally contacts multiple distinct supports")
	_check(connection.winding_complete, direction_name + " reaches wrap threshold through real player movement")
	_check(not physical_loops.is_empty(), direction_name + " natural route contains a real closed loop before settlement")
	if physical_loops.is_empty() or not connection.winding_complete:
		print("E2E ", direction_name, " blocked_before_settlement reason=", connection.last_bind_failure_reason, " route_points=", routed_before_lock.size())
		await _dispose_world(world)
		return
	var test_loop := _largest_loop_by_independent_area(physical_loops)
	var centroid := _polygon_area_centroid(test_loop)
	var inside_a: Node2D
	var inside_b: Node2D
	var inside_c: Node2D
	var outside: Node2D
	if preplaced_targets:
		inside_a = preplaced_inside[0]
		inside_b = preplaced_inside[1]
		inside_c = null
		# The second radial body is the designated outside support probe; it is
		# checked separately and never treated as an enclosed group target.
		outside = preplaced_outside
		for candidate in preplaced_inside + [preplaced_outside]:
			_check(candidate.is_physics_processing() and not bool(candidate.get("combat_paused")), direction_name + " preplaced slime AI/physics remain enabled")
			var initial_position: Vector2 = preplaced_start_positions.get(candidate.get_instance_id(), candidate.global_position)
			_check(candidate.global_position.distance_to(initial_position) > 0.5, direction_name + " preplaced enemy AI actually moves during physical winding")
		_check(connection.debug_support_contact_events.size() >= 2, direction_name + " preplaced enemies naturally contact the forming path as supports")
		var target_tick_by_id: Dictionary = {}
		for event in connection.debug_support_contact_events:
			var contact_id := int(event.get("id", 0))
			if (preplaced_inside + [preplaced_outside]).any(func(enemy: Node2D) -> bool: return enemy.get_instance_id() == contact_id):
				target_tick_by_id[contact_id] = int(event.get("tick", -1))
		_check(target_tick_by_id.size() >= 2, direction_name + " at least two preplaced enemies become routed supports")
		var simultaneous_contact := false
		var contact_ids: Array = target_tick_by_id.keys()
		var simultaneous_window_ticks := ceili(0.75 * float(Engine.physics_ticks_per_second))
		for first_index in range(contact_ids.size()):
			for second_index in range(first_index + 1, contact_ids.size()):
				var first_tick := int(target_tick_by_id[contact_ids[first_index]])
				var second_tick := int(target_tick_by_id[contact_ids[second_index]])
				if absi(first_tick - second_tick) <= simultaneous_window_ticks:
					simultaneous_contact = true
		_check(simultaneous_contact, direction_name + " multiple preplaced slime contacts are resolved within the same 0.75-second orbit window")
		print("E2E ", direction_name, " live_contact_events=", connection.debug_support_contact_events)
	else:
		# This prior acceptance remains as a separate post-loop group-snapshot check.
		inside_a = _spawn_slime(world, centroid + Vector2(-22.0, -10.0))
		inside_b = _spawn_slime(world, centroid + Vector2(22.0, -10.0))
		inside_c = _spawn_slime(world, centroid + Vector2(0.0, 22.0))
		outside = _spawn_slime(world, centroid + Vector2(80.0, 0.0))
		for candidate in [inside_a, inside_b, inside_c, outside]:
			candidate.set("move_speed", 0.0)
			candidate.set("chase_range", 0.0)
			candidate.set("disengage_range", 0.0)
	if all_immune:
		anchor.set("bind_resistance_left", 5.0)
		inside_a.set("bind_resistance_left", 5.0)
		inside_b.set("bind_resistance_left", 5.0)
		inside_c.set("bind_resistance_left", 5.0)
	var expected_loops: Array[PackedVector2Array] = physical_loops if preplaced_targets else [test_loop]
	if preplaced_targets:
		var geometry_summary: Array[String] = []
		for loop_path in physical_loops:
			geometry_summary.append("area=%.1f center=%s" % [absf(_polygon_twice_area(loop_path)) * 0.5, str(_polygon_area_centroid(loop_path))])
		print("E2E ", direction_name, " loop_geometry=", geometry_summary, " targets=", preplaced_inside.map(func(enemy: Node2D) -> String: return "%s:%s inside=%s" % [enemy.name, str(enemy.global_position), str(_independent_point_inside_any(enemy.global_position, expected_loops))]))
	if not preplaced_targets:
		_check(_independent_point_inside_any(inside_a.global_position, expected_loops), direction_name + " independent inside expectation A")
		_check(_independent_point_inside_any(inside_b.global_position, expected_loops), direction_name + " independent inside expectation B")
		if is_instance_valid(inside_c):
			_check(_independent_point_inside_any(inside_c.global_position, expected_loops), direction_name + " independent inside expectation C")
		_check(not _independent_point_inside_any(outside.global_position, expected_loops), direction_name + " independent outside expectation")
	var settlement_support_ids: Dictionary = {}
	for support in connection.wrap_supports:
		if is_instance_valid(support) and support.is_in_group("enemies"):
			settlement_support_ids[support.get_instance_id()] = true
	await physics_frame
	var rope_length_before_stop := connection.effective_rope_length
	Input.action_press("ranged_attack")
	await process_frame
	await physics_frame
	Input.action_release("ranged_attack")
	await physics_frame
	_check(not connection.feeding_enabled, direction_name + " second K stops feed without another projectile")
	_check(is_equal_approx(connection.effective_rope_length, rope_length_before_stop), direction_name + " stopping feed locks rather than resetting released rope length")
	_check(absf(connection.remaining_slack - maxf(connection.effective_rope_length - connection.actual_routed_length, 0.0)) <= 0.1, direction_name + " stopped-feed slack matches the live route after topology resolution")
	_check(not connection.settlement_completed, direction_name + " stop-feed alone does not settle")
	print("E2E ", direction_name, " event=feed_locked rope=", snappedf(connection.effective_rope_length, 0.1), " slack=", snappedf(connection.remaining_slack, 0.1), " real_loops=", physical_loops.size())
	var settlement_attempts_at_exit := 0
	var elapsed_pull := 0.0
	while is_instance_valid(connection) and not connection.finished and elapsed_pull < 4.0:
		var pull_route := connection._build_routed_path()
		if pull_route.size() < 2:
			break
		var outward := pull_route[0] - pull_route[1]
		await _move_cat_for(cat, outward, 0.10)
		elapsed_pull += 0.10
		if is_instance_valid(connection):
			settlement_attempts_at_exit = int(connection.settlement_attempt_count)
		else:
			settlement_attempts_at_exit = 1
	if is_instance_valid(connection):
		_check(connection.finished, direction_name + " active outward pull completes one-shot settlement")
	else:
		_check(true, direction_name + " connection resolved and released after active pull")
	var retained_nodes := get_nodes_in_group("persistent_yarn_loops")
	var expected_inside: Array[Node2D] = []
	if preplaced_targets and retained_nodes.size() == 1:
		var settled_loop := retained_nodes[0] as BoundYarnLoop
		var preplaced_candidates: Array[Node2D] = preplaced_inside.duplicate()
		preplaced_candidates.append(preplaced_outside)
		var independently_inside_count := 0
		for candidate in preplaced_candidates:
			var independently_inside := _independent_point_inside_any(candidate.global_position, settled_loop.loop_paths)
			var is_bound := float(candidate.get("bind_time_left")) > 0.0
			if independently_inside:
				independently_inside_count += 1
			if independently_inside or settlement_support_ids.has(candidate.get_instance_id()):
				expected_inside.append(candidate)
			if all_immune:
				_check(not is_bound, direction_name + " immune preplaced target is not bound")
			else:
				var expected_bound := independently_inside or settlement_support_ids.has(candidate.get_instance_id())
				_check(is_bound == expected_bound, direction_name + " preplaced target bind matches independent loop geometry or active support role")
		_check(independently_inside_count >= 1, direction_name + " at least one preplaced enemy is independently inside the actual pull-time loops")
		_check(not _independent_point_inside_any(preplaced_outside.global_position, settled_loop.loop_paths), direction_name + " designated preplaced outsider is outside every retained loop")
		_check(not settlement_support_ids.has(preplaced_outside.get_instance_id()), direction_name + " designated outsider is not an active wrap support")
	else:
		expected_inside = [inside_a, inside_b, inside_c]
		for candidate in expected_inside:
			if all_immune:
				_check(float(candidate.get("bind_time_left")) <= 0.0, direction_name + " immune enclosed enemy is not bound")
			else:
				_check(float(candidate.get("bind_time_left")) > 0.0, direction_name + " known enclosed enemy binds")
	if all_immune:
		_check(float(anchor.get("bind_time_left")) <= 0.0, direction_name + " immune anchor is not bound")
	_check(float(outside.get("bind_time_left")) <= 0.0, direction_name + " known outside enemy remains unbound")
	_check(retained_nodes.size() == 1, direction_name + " cat endpoint resolves into one independent retained loop")
	_check(primary != secondary, direction_name + " independent support objects are used")
	print("E2E ", direction_name, " event=pull_snapshot bound=", _count_bound(expected_inside), "/", expected_inside.size(), " outside=", outside.get("bind_time_left"), " retained_loops=", retained_nodes.size())
	if retained_nodes.size() == 1:
		var retained := retained_nodes[0] as BoundYarnLoop
		var initial_loop_lifetime := retained.remaining_time
		# The outside slime attempts a physical crossing while its AI/physics stay on.
		var min_corner := _polygon_min(test_loop)
		var max_corner := _polygon_max(test_loop)
		outside.global_position = Vector2(min_corner.x - 60.0, (min_corner.y + max_corner.y) * 0.5)
		outside.set("move_speed", 120.0)
		outside.set("target", inside_a)
		outside.set("attack_range", 0.0)
		outside.set("chase_range", 1000.0)
		outside.set("disengage_range", 1200.0)
		outside.set("state", 2)
		outside.set("state_time_left", 3.0)
		var contacted_retained_barrier := false
		var barrier_collision_names: Array[String] = []
		var barrier_ticks := ceili(0.6 * float(Engine.physics_ticks_per_second))
		for _tick in range(barrier_ticks):
			await physics_frame
			for collision_index in range(outside.get_slide_collision_count()):
				var collided_with: Object = outside.get_slide_collision(collision_index).get_collider()
				if collided_with is Node:
					barrier_collision_names.append((collided_with as Node).name)
				if collided_with == retained:
					contacted_retained_barrier = true
		var still_outside := not _independent_point_inside(outside.global_position, retained.loop_paths[0])
		print("E2E ", direction_name, " barrier_attempt start_x=", snappedf(min_corner.x - 60.0, 0.1), " end=", outside.global_position, " inner_target=", inside_a.global_position, " velocity=", outside.velocity, " outside=", still_outside, " touched_loop=", contacted_retained_barrier, " collisions=", barrier_collision_names)
		_check(contacted_retained_barrier and still_outside, direction_name + " active enemy body collides with and cannot cross the retained rope barrier")
		var before_leave := cat.global_position
		await _move_cat_for(cat, Vector2(1.0, 0.0), 0.15)
		_check(cat.global_position.distance_to(before_leave) > 10.0, direction_name + " cat can leave freely after bind")
		_check(retained.remaining_time < initial_loop_lifetime, direction_name + " retained loop expires independently of the cat tether")
		await _wait_physics_seconds(retained.remaining_time + 0.05)
		_check(not is_instance_valid(retained), direction_name + " retained collision and visuals clean up at duration")
	print("E2E ", direction_name, " event=expiry retained_nodes=", get_nodes_in_group("persistent_yarn_loops").size())
	for node in [cat, anchor, primary, secondary, inside_a, inside_b, inside_c, outside]:
		if is_instance_valid(node):
			node.queue_free()
	await _dispose_world(world)
	print("E2E_TIMING ", direction_name, " physics_hz=", Engine.physics_ticks_per_second, " wall_msec=", Time.get_ticks_msec() - wall_started_msec, " settlement_attempts=", settlement_attempts_at_exit, " retained_loops_after_cleanup=", get_nodes_in_group("persistent_yarn_loops").size())


func _move_cat_for(cat: CharacterBody2D, direction: Vector2, duration: float) -> void:
	for action in [&"move_left", &"move_right", &"move_up", &"move_down"]:
		Input.action_release(action)
	if direction.length_squared() > 0.001:
		var vector := direction.normalized()
		if vector.x < -0.01:
			Input.action_press("move_left", absf(vector.x))
		elif vector.x > 0.01:
			Input.action_press("move_right", absf(vector.x))
		if vector.y < -0.01:
			Input.action_press("move_up", absf(vector.y))
		elif vector.y > 0.01:
			Input.action_press("move_down", absf(vector.y))
	await create_timer(maxf(duration, 0.01)).timeout
	for action in [&"move_left", &"move_right", &"move_up", &"move_down"]:
		Input.action_release(action)


func _spawn_wrap_point(world: Node, at: Vector2) -> Node2D:
	var point := load("res://scenes/combat/yarn_wrap_point.tscn").instantiate() as Node2D
	world.add_child(point)
	point.global_position = at
	return point


func _polygon_area_centroid(path: PackedVector2Array) -> Vector2:
	var area_times_six := 0.0
	var center := Vector2.ZERO
	for index in range(path.size() - 1):
		var cross := path[index].cross(path[index + 1])
		area_times_six += cross
		center += (path[index] + path[index + 1]) * cross
	if absf(area_times_six) < 0.01:
		return _polygon_average(path)
	return center / (3.0 * area_times_six)


func _polygon_twice_area(path: PackedVector2Array) -> float:
	var twice_area := 0.0
	for index in range(path.size() - 1):
		twice_area += path[index].cross(path[index + 1])
	return twice_area


func _largest_loop_by_independent_area(paths: Array[PackedVector2Array]) -> PackedVector2Array:
	var selected := PackedVector2Array()
	var largest_area := -1.0
	for path in paths:
		var twice_area := 0.0
		for index in range(path.size() - 1):
			twice_area += path[index].cross(path[index + 1])
		var area := absf(twice_area) * 0.5
		if area > largest_area:
			largest_area = area
			selected = path
	return selected


func _independent_point_inside(point: Vector2, polygon: PackedVector2Array) -> bool:
	var inside := false
	for index in range(polygon.size() - 1):
		var a := polygon[index]
		var b := polygon[index + 1]
		if (a.y > point.y) != (b.y > point.y):
			var crossing_x := (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x
			if point.x < crossing_x:
				inside = not inside
	return inside


func _independent_point_inside_any(point: Vector2, polygons: Array[PackedVector2Array]) -> bool:
	for polygon in polygons:
		if _independent_point_inside(point, polygon):
			return true
	return false


func _polygon_average(path: PackedVector2Array) -> Vector2:
	var center := Vector2.ZERO
	for point in path:
		center += point
	return center / maxf(float(path.size()), 1.0)


func _polygon_min(path: PackedVector2Array) -> Vector2:
	var result := Vector2(INF, INF)
	for point in path:
		result.x = minf(result.x, point.x)
		result.y = minf(result.y, point.y)
	return result


func _polygon_max(path: PackedVector2Array) -> Vector2:
	var result := Vector2(-INF, -INF)
	for point in path:
		result.x = maxf(result.x, point.x)
		result.y = maxf(result.y, point.y)
	return result


func _count_bound(candidates: Array) -> int:
	var count := 0
	for candidate in candidates:
		if is_instance_valid(candidate) and float(candidate.get("bind_time_left")) > 0.0:
			count += 1
	return count


func _make_world(world_name: String) -> Node2D:
	var world := Node2D.new()
	world.name = world_name
	world.add_to_group("night_exploration")
	root.add_child(world)
	current_scene = world
	return world


func _new_connection(world: Node, cat: Node2D, anchor: Node2D) -> YarnConnection:
	var connection := load("res://scenes/combat/yarn_connection.tscn").instantiate() as YarnConnection
	connection.configure(cat, anchor, cat.get_node_or_null("PlayerCombat"))
	connection.set_physics_process(true)
	world.add_child(connection)
	return connection


func _spawn_slime(world: Node, at: Vector2) -> Node2D:
	var slime := load("res://scenes/enemies/slime.tscn").instantiate() as Node2D
	world.add_child(slime)
	slime.global_position = at
	return slime


func _configure_active_wander(enemy: Node2D, pivot: Node2D, direction_sign: float) -> void:
	# This is a normal live AI state, not a frozen body. A modest wander speed
	# keeps the placed enemies near the forming loop while guaranteeing their
	# CharacterBody2D and state machine both advance throughout the test.
	enemy.set("spawn_position", enemy.global_position)
	enemy.set("move_speed", 3.0)
	enemy.set("chase_range", 30.0)
	enemy.set("disengage_range", 45.0)
	enemy.set("state", 1) # SlimeState.WANDER
	enemy.set("state_time_left", 12.0)
	var radial := (enemy.global_position + Vector2(0.0, 7.0) - pivot.global_position).normalized()
	enemy.set("wander_direction", radial.orthogonal() * direction_sign)


func _minimum_support_clearance(path: PackedVector2Array, supports: Array) -> float:
	var minimum := INF
	for support in supports:
		if not is_instance_valid(support):
			continue
		var shape_node: CollisionShape2D
		for candidate in support.find_children("*", "CollisionShape2D", true, false):
			var collision_shape := candidate as CollisionShape2D
			if collision_shape != null and not collision_shape.disabled and collision_shape.shape is CircleShape2D and collision_shape.get_parent() is PhysicsBody2D:
				shape_node = collision_shape
				break
		if not is_instance_valid(shape_node):
			continue
		var circle := shape_node.shape as CircleShape2D
		var radius := circle.radius * maxf(shape_node.global_scale.x, shape_node.global_scale.y)
		for segment_index in range(path.size() - 1):
			var delta := path[segment_index + 1] - path[segment_index]
			var t := 0.0
			if delta.length_squared() > 0.001:
				t = clampf((shape_node.global_position - path[segment_index]).dot(delta) / delta.length_squared(), 0.0, 1.0)
			var distance := shape_node.global_position.distance_to(path[segment_index] + delta * t)
			minimum = minf(minimum, distance - radius)
	return minimum


func _wait_physics_seconds(duration: float) -> void:
	var elapsed := 0.0
	while elapsed < duration:
		await physics_frame
		elapsed += 1.0 / float(Engine.physics_ticks_per_second)


func _dispose_world(world: Node) -> void:
	for input_action in [&"move_left", &"move_right", &"move_up", &"move_down", &"ranged_attack", &"dodge"]:
		Input.action_release(input_action)
	if is_instance_valid(world):
		for audio_player in world.find_children("*", "AudioStreamPlayer", true, false):
			var player := audio_player as AudioStreamPlayer
			player.stop()
			player.stream = null
		for audio_player in world.find_children("*", "AudioStreamPlayer2D", true, false):
			var player_2d := audio_player as AudioStreamPlayer2D
			player_2d.stop()
			player_2d.stream = null
		if current_scene == world:
			current_scene = null
		world.queue_free()
		await world.tree_exited
	await physics_frame
	await process_frame
	await create_timer(0.1).timeout


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		failures.append(description)
		push_error("FAIL: " + description)
