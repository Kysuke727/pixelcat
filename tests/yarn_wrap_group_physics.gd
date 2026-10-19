extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := load("res://scenes/worlds/night_world.tscn").instantiate() as Node2D
	root.add_child(world)
	current_scene = world
	await physics_frame
	var player := get_first_node_in_group("player") as CharacterBody2D
	var combat := player.get_node("PlayerCombat")
	for enemy in get_nodes_in_group("enemies"):
		enemy.global_position = Vector2(1450.0, 900.0)
		enemy.set_physics_process(false)
	player.set_physics_process(false)
	player.set_process(false)
	combat.set_process(false)

	# Construct a wound route from actual endpoints and a live dynamic pivot.
	var pivot := _spawn_slime(world, Vector2(500.0, 420.0), false)
	var anchor := _spawn_slime(world, Vector2(710.0, 420.0), false)
	player.global_position = Vector2(500.0, 350.0)
	var connection := _new_connection(world, combat, player, anchor)
	connection.wrap_pivot = pivot
	connection.wrap_supports = [pivot]
	connection._dynamic_pivot = true
	connection.is_wrapped = true
	connection.wrap_state = YarnConnection.WrapState.WOUND
	connection.wrap_contact_radius = pivot.yarn_wrap_radius
	connection.wrap_player_radius_at_contact = 70.0
	connection.wrap_contact_history = [Vector2.LEFT]
	connection.wrap_angle_history.clear()
	connection.wrap_angle_history.append(-270.0)
	connection.accumulated_wrap_angle = -270.0
	connection.winding_complete = true
	connection._wrap_route_seeded = true
	connection._wrap_seed_player_side = -1.0
	connection._wrap_seed_target_side = 1.0
	connection._wrap_seed_arc_direction = -1.0
	connection.player_position_at_wound = player.global_position
	connection.pivot_position_at_wound = connection._get_support_center(pivot)
	connection.player_radius_at_wound = player.global_position.distance_to(connection.pivot_position_at_wound)
	connection.routed_path_length_at_wound = connection._routed_path_length()
	player.global_position += Vector2(0.0, -30.0)
	var routed := connection._build_routed_path()
	var inside_position := _find_point_inside(connection, routed, pivot.global_position, anchor.global_position, player.global_position)
	_check(inside_position != Vector2.INF, "routed yarn path creates a non-empty enclosed region for the test fixture")
	var enclosed := _spawn_slime(world, inside_position, false)
	var outside := _spawn_slime(world, inside_position + Vector2(0.0, 240.0), false)
	anchor.bind_resistance_left = 1.0
	await physics_frame
	var enclosed_targets := connection._collect_enclosed_targets()
	_check(enclosed_targets.has(anchor) and enclosed_targets.has(pivot), "anchor A and participating pivot B are always eligible")
	_check(enclosed_targets.has(enclosed), "enemy center inside the routed yarn loop is collected")
	_check(not enclosed_targets.has(outside), "enemy outside the routed yarn loop is excluded")
	connection._update_tension_and_bind()
	_check(connection.is_taut, "active radial pull satisfies winding tension")
	_check(anchor.bind_time_left <= 0.0, "an immune anchor does not receive an invalid bind")
	_check(pivot.bind_time_left > 0.0 and enclosed.bind_time_left > 0.0, "immune A does not block independent B and enclosed enemy settlement")
	_check(outside.bind_time_left <= 0.0, "outside enemy remains unbound")
	var late_enclosed := _spawn_slime(world, inside_position + Vector2(0.0, 10.0), false)
	_check(connection._point_is_inside_routed_loop(late_enclosed.global_position, routed), "late target is physically inside the established routed loop")
	connection._update_tension_and_bind()
	_check(late_enclosed.bind_time_left > 0.0, "partial success does not stop later eligible target settlement")

	# A new physical contact is appended, never substituted for the first pivot.
	connection.loop_bound = false
	var support2 := load("res://scenes/combat/yarn_wrap_point.tscn").instantiate() as Node2D
	world.add_child(support2)
	var route_segment := _longest_non_primary_segment(routed, pivot.global_position)
	support2.global_position = (route_segment[0] + route_segment[1]) * 0.5
	support2.set("yarn_wrap_radius", 12.0)
	var angle_before := connection.accumulated_wrap_angle
	var history_count_before := connection.wrap_angle_history.size()
	connection._add_contacted_supports()
	_check(connection.wrap_pivot == pivot, "new contact does not replace the original primary pivot")
	_check(connection.wrap_supports.size() >= 2, "second contacted obstacle is retained as a routed support")
	_check(is_equal_approx(connection.accumulated_wrap_angle, angle_before) and connection.wrap_angle_history.size() == history_count_before, "adding a support preserves winding progress")
	_check(connection._build_routed_path().size() > routed.size(), "secondary support adds visible route points")
	await physics_frame
	_check(connection._validate_current_path(), "multi-support route remains clear of physical support colliders")
	var dead_secondary: Node2D = connection.wrap_supports.back()
	dead_secondary.queue_free()
	await physics_frame
	connection._add_contacted_supports()
	_check(connection.is_wrapped and connection.wrap_pivot == pivot and connection.winding_complete, "secondary support removal does not switch or clear a valid primary winding")
	var second_anchor := _spawn_slime(world, Vector2(710.0, 520.0), false)
	var second_connection := _new_connection(world, combat, player, second_anchor)
	await process_frame
	_check(connection.debug_status.position != second_connection.debug_status.position, "simultaneous connection diagnostics occupy separate rows")
	_check(get_nodes_in_group("yarn_connections").size() == 2, "multiple live yarn connections keep independent state")

	connection.finish_naturally()
	second_connection.finish_naturally()
	for enemy in [pivot, anchor, enclosed, outside, late_enclosed, second_anchor]:
		if is_instance_valid(enemy):
			enemy.queue_free()
	if is_instance_valid(support2):
		support2.queue_free()
	await process_frame

	# Real physics phase: both the cat and slime scripts remain active while the
	# slime moves laterally from beneath the cat. It must not act as a platform.
	for action in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(action)
	player.set_physics_process(true)
	player.set_process(false)
	var runner := _spawn_slime(world, Vector2(900.0, 620.0), true) as CharacterBody2D
	runner.get_node("AttackArea").set_deferred("monitoring", false)
	player.global_position = runner.global_position + Vector2(0.0, -21.0)
	runner.set("state", 5) # SlimeState.RECOVER
	runner.set("state_time_left", 0.5)
	Input.action_press("move_down")
	await physics_frame
	Input.action_release("move_down")
	var player_before_runner_motion := player.global_position
	var runner_before_motion := runner.global_position
	runner.set("state", 4) # SlimeState.LUNGE
	runner.set("state_time_left", 0.7)
	runner.set("lunge_duration", 0.8)
	runner.set("lunge_direction", Vector2.RIGHT)
	runner.set("lunge_speed", 100.0)
	for _frame in range(12):
		await physics_frame
	var player_dx := player.global_position.x - player_before_runner_motion.x
	var runner_dx := runner.global_position.x - runner_before_motion.x
	_check(player.is_physics_processing() and runner.is_physics_processing(), "player and slime physics processing remain enabled in the movement test")
	_check(runner_dx > 12.0, "slime moved under active CharacterBody2D physics")
	_check(absf(player_dx) < 4.0, "slime platform velocity does not carry the nearby cat")
	_check(player.platform_floor_layers == 1 and runner.platform_floor_layers == 0, "cat rides only world geometry and enemies ride no CharacterBody2D platforms")
	player.global_position = runner.global_position + Vector2(0.0, -21.0)
	runner.set("state", 5)
	runner.set("state_time_left", 1.0)
	Input.action_press("move_down")
	await physics_frame
	Input.action_release("move_down")
	player.platform_floor_layers = 3
	var legacy_player_x := player.global_position.x
	var legacy_runner_x := runner.global_position.x
	runner.set("state", 4)
	runner.set("state_time_left", 0.7)
	runner.set("lunge_direction", Vector2.RIGHT)
	for _frame in range(12):
		await physics_frame
	_check(runner.global_position.x - legacy_runner_x > 12.0, "legacy platform-layer control moved the slime")
	_check(absf(player.global_position.x - legacy_player_x) > 4.0, "including enemy layer reproduces CharacterBody2D platform carry")
	player.platform_floor_layers = 1

	# Live rope + moving AI: a moving support cannot manufacture player winding.
	for action in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(action)
	player.global_position = Vector2(500.0, 820.0)
	var live_anchor := _spawn_slime(world, Vector2(700.0, 820.0), false)
	var live_pivot := _spawn_slime(world, Vector2(600.0, 820.0), true)
	var live_connection := load("res://scenes/combat/yarn_connection.tscn").instantiate() as YarnConnection
	live_connection.configure(player, live_anchor, combat)
	world.add_child(live_connection)
	await physics_frame
	await physics_frame
	_check(live_connection.is_wrapped and live_connection.wrap_pivot == live_pivot, "live connection acquires the physically moving slime pivot")
	var live_angle_before := live_connection.accumulated_wrap_angle
	var live_pivot_before := live_pivot.global_position
	for _frame in range(24):
		await physics_frame
	_check(live_pivot.global_position.distance_to(live_pivot_before) > 5.0, "enemy AI moves the support with physics processing enabled")
	_check(is_equal_approx(live_connection.accumulated_wrap_angle, live_angle_before), "support-only motion does not add cat winding")
	_check(not live_connection.winding_complete and not live_connection.loop_bound, "support-only motion cannot wind or bind the live connection")
	live_connection.finish_naturally()
	for enemy in [live_anchor, live_pivot]:
		if is_instance_valid(enemy):
			enemy.queue_free()
	var physical_pivot := load("res://scenes/combat/yarn_wrap_point.tscn").instantiate() as Node2D
	world.add_child(physical_pivot)
	physical_pivot.global_position = Vector2(600.0, 820.0)
	var physical_anchor := _spawn_slime(world, Vector2(820.0, 820.0), true)
	player.global_position = Vector2(530.0, 820.0)
	player.velocity = Vector2.ZERO
	player.set_physics_process(true)
	player.set_process(true)
	var physical_connection := load("res://scenes/combat/yarn_connection.tscn").instantiate() as YarnConnection
	physical_connection.configure(player, physical_anchor, combat)
	world.add_child(physical_connection)
	await physics_frame
	_check(physical_connection.is_wrapped and physical_connection.wrap_pivot == physical_pivot, "live physical route acquires the obstacle between the player and anchor")
	for movement in [
		{"action": "move_up", "frames": 21},
		{"action": "move_right", "frames": 42},
		{"action": "move_down", "frames": 42},
		{"action": "move_left", "frames": 21},
	]:
		Input.action_press(str(movement.action))
		for _frame in range(int(movement.frames)):
			await physics_frame
		Input.action_release(str(movement.action))
		await physics_frame
	_check(player.is_physics_processing() and physical_anchor.is_physics_processing(), "player and anchor physics stay enabled during the real winding route")
	_check(physical_connection.accumulated_wrap_angle >= physical_connection.required_wrap_angle_degrees - 2.0, "real CharacterBody2D movement accumulates winding around a physical obstacle")
	_check(physical_connection.winding_complete, "real physical winding reaches the bind-ready state")
	_check(not physical_connection.loop_bound, "real winding alone does not bind before active pull")
	Input.action_press("move_down")
	for _frame in range(15):
		await physics_frame
	Input.action_release("move_down")
	await physics_frame
	_check(physical_connection.is_taut and physical_connection.loop_bound, "real outward CharacterBody2D pull completes the physical bind")
	physical_connection.finish_naturally()
	physical_pivot.queue_free()
	physical_anchor.queue_free()
	await physics_frame
	var reverse_pivot := load("res://scenes/combat/yarn_wrap_point.tscn").instantiate() as Node2D
	world.add_child(reverse_pivot)
	reverse_pivot.global_position = Vector2(600.0, 820.0)
	var reverse_anchor := _spawn_slime(world, Vector2(820.0, 820.0), true)
	player.global_position = Vector2(530.0, 820.0)
	player.velocity = Vector2.ZERO
	var reverse_connection := load("res://scenes/combat/yarn_connection.tscn").instantiate() as YarnConnection
	reverse_connection.configure(player, reverse_anchor, combat)
	world.add_child(reverse_connection)
	await physics_frame
	for movement in [
		{"action": "move_down", "frames": 21},
		{"action": "move_right", "frames": 42},
		{"action": "move_up", "frames": 42},
		{"action": "move_left", "frames": 21},
	]:
		Input.action_press(str(movement.action))
		for _frame in range(int(movement.frames)):
			await physics_frame
		Input.action_release(str(movement.action))
		await physics_frame
	_check(reverse_connection.accumulated_wrap_angle <= -reverse_connection.required_wrap_angle_degrees + 2.0, "real CharacterBody2D movement also accumulates reverse-direction winding")
	_check(reverse_connection.winding_complete and not reverse_connection.loop_bound, "reverse physical winding also waits for active pull")
	Input.action_press("move_up")
	for _frame in range(15):
		await physics_frame
	Input.action_release("move_up")
	await physics_frame
	_check(reverse_connection.is_taut and reverse_connection.loop_bound, "reverse-direction physical pull completes the bind")
	reverse_connection.finish_naturally()

	for enemy in get_nodes_in_group("enemies"):
		if is_instance_valid(enemy):
			enemy.queue_free()
	for audio_player in world.find_children("*", "AudioStreamPlayer2D", true, false):
		audio_player.stop()
		audio_player.stream = null
	world.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.25).timeout
	if failures.is_empty():
		print("YARN_WRAP_GROUP_PHYSICS_PASSED")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _spawn_slime(parent: Node, position: Vector2, physics_enabled: bool) -> Node2D:
	var slime := load("res://scenes/enemies/slime.tscn").instantiate() as Node2D
	parent.add_child(slime)
	slime.global_position = position
	slime.set_physics_process(physics_enabled)
	return slime


func _new_connection(parent: Node, combat_node: Node, player_node: Node2D, anchor_node: Node2D) -> YarnConnection:
	var connection := load("res://scenes/combat/yarn_connection.tscn").instantiate() as YarnConnection
	connection.configure(player_node, anchor_node, combat_node)
	connection.set_process(false)
	parent.add_child(connection)
	return connection


func _find_point_inside(
	connection: YarnConnection,
	path: PackedVector2Array,
	pivot_position: Vector2,
	anchor_position: Vector2,
	player_position: Vector2
) -> Vector2:
	for x in range(520, 710, 10):
		for y in range(300, 540, 10):
			var candidate := Vector2(float(x), float(y))
			if candidate.distance_to(pivot_position) < 24.0 or candidate.distance_to(anchor_position) < 20.0 or candidate.distance_to(player_position) < 20.0:
				continue
			var nearest_path_distance := INF
			for index in range(path.size() - 1):
				nearest_path_distance = minf(nearest_path_distance, _distance_to_segment(candidate, path[index], path[index + 1]))
			if nearest_path_distance < 18.0:
				continue
			if connection._point_is_inside_routed_loop(candidate, path):
				return candidate
	return Vector2.INF


func _longest_non_primary_segment(path: PackedVector2Array, primary: Vector2) -> Array[Vector2]:
	var best: Array[Vector2] = []
	var longest := 0.0
	for index in range(path.size() - 1):
		var start := path[index]
		var end := path[index + 1]
		if ((start + end) * 0.5).distance_to(primary) < 25.0:
			continue
		var length := start.distance_to(end)
		if length > longest:
			longest = length
			best = [start, end]
	return best


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		failures.append(description)


func _distance_to_segment(point: Vector2, start: Vector2, end: Vector2) -> float:
	var segment := end - start
	if segment.length_squared() <= 0.001:
		return point.distance_to(start)
	var along := clampf((point - start).dot(segment) / segment.length_squared(), 0.0, 1.0)
	return point.distance_to(start + segment * along)
