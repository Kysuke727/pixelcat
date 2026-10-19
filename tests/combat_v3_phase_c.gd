extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var night_scene: Node = load("res://scenes/worlds/night_world.tscn").instantiate()
	root.add_child(night_scene)
	current_scene = night_scene
	await physics_frame
	var player := get_first_node_in_group("player")
	var combat = player.get_node("PlayerCombat")
	player.set_physics_process(false)
	player.set_process(false)
	player.global_position = Vector2(100.0, 300.0)
	combat.set_process(false)
	combat.ranged_cooldown = 6.0
	combat.facing = Vector2.RIGHT
	for existing_enemy in get_nodes_in_group("enemies"):
		existing_enemy.set_physics_process(false)
		existing_enemy.global_position = Vector2(850.0, 600.0)

	var target_a := _spawn_slime(night_scene, Vector2(190.0, 300.0))
	combat._spawn_projectile()
	_check(is_equal_approx(combat.ranged_cooldown_left, 6.0), "yarn cooldown starts when the projectile launches")
	_check(combat.yarn_projectile_in_flight, "firing marks one projectile in flight")
	for _frame in range(40):
		if not combat.yarn_projectile_in_flight:
			break
		await physics_frame
	_check(target_a.current_health == target_a.max_health - combat.ranged_damage, "yarn projectile damages the struck slime")
	_check(not combat.yarn_projectile_in_flight, "projectile collision releases the in-flight lock")
	_check(is_equal_approx(target_a.slow_multiplier, 0.5), "yarn applies a 50 percent movement slow")
	_check(is_equal_approx(target_a.slow_time_left, combat.yarn_slow_duration), "yarn slow lasts the configured 3 seconds")
	_check(combat.active_yarn_connections.size() == 1, "successful hit creates a tracked yarn connection")
	var connection_a: Node2D = combat.active_yarn_connections[0]
	_check(connection_a.get_node("TetherLine").points.size() == 2, "connection draws a live tether line")
	_check(InputMap.has_action("yarn_cut"), "Q yarn-cut input action is configured")
	player.global_position = Vector2(400.0, 300.0)
	combat.ranged_cooldown_left = 0.0
	combat._spawn_projectile()
	for _frame in range(70):
		if not combat.yarn_projectile_in_flight:
			break
		await physics_frame
	_check(not combat.yarn_projectile_in_flight, "a projectile that reaches max range releases the in-flight lock")
	_check(combat.active_yarn_connections.size() == 1, "a miss does not create a yarn connection")
	_check(is_equal_approx(combat.ranged_cooldown_left, combat.ranged_cooldown), "miss still respects cooldown from launch")
	player.global_position = Vector2(100.0, 300.0)

	var target_b := _spawn_slime(night_scene, Vector2(260.0, 300.0))
	_check(combat.on_yarn_hit(target_b), "a second successful hit can establish another connection")
	var connection_b: Node2D = combat.active_yarn_connections[1]
	target_a.apply_yarn_bind(2.0)
	combat.ranged_cooldown_left = 4.0
	combat._cut_all_yarn_connections()
	_check(combat.active_yarn_connections.is_empty(), "Q cuts all active connections")
	_check(is_equal_approx(combat.ranged_cooldown_left, 1.0), "each cut line reduces remaining cooldown by 1.5 seconds")
	_check(is_equal_approx(target_a.bind_time_left, 2.0), "cutting yarn does not cancel an applied bind")
	_check(not connection_a.cut_by_player(), "one connection cannot claim the Q reward twice")
	_check(not connection_b.cut_by_player(), "a second cut call cannot claim a second reward")
	_check(is_equal_approx(combat.ranged_cooldown_left, 1.0), "duplicate cut cannot reduce cooldown again")

	var loop_target := _spawn_slime(night_scene, Vector2(500.0, 350.0))
	player.global_position = loop_target.global_position + Vector2(60.0, 0.0)
	var loop_connection := _create_connection(combat, player, loop_target)
	for index in range(1, 25):
		var angle := TAU * float(index) / 24.0
		player.global_position = loop_target.global_position + Vector2.from_angle(angle) * 60.0
		loop_connection._process(1.0 / 60.0)
	_check(loop_connection.loop_bound, "closed polygon around the target is recognized")
	_check(loop_target.bind_time_left >= combat.yarn_bind_duration, "valid loop binds the slime for 2 seconds")
	_check(loop_connection.trail_points.size() <= loop_connection.maximum_samples, "trail sample storage stays bounded")
	loop_target.apply_yarn_slow(3.0, 0.5)
	loop_connection.cut_by_player()
	_check(loop_target.slow_time_left > 0.0, "cutting a line does not cancel the independently timed slow")
	_check(loop_target.bind_time_left > 0.0, "cutting a line does not cancel the independent bind")
	loop_target.slow_time_left = 0.05
	loop_target._physics_process(0.06)
	_check(is_equal_approx(loop_target.slow_multiplier, 1.0), "slow effect restores normal speed after its timer")

	var outside_target := _spawn_slime(night_scene, Vector2(250.0, 350.0))
	var outside_center := Vector2(250.0, 500.0)
	player.global_position = outside_center + Vector2(60.0, 0.0)
	var outside_connection := _create_connection(combat, player, outside_target)
	for index in range(1, 25):
		var angle := TAU * float(index) / 24.0
		player.global_position = outside_center + Vector2.from_angle(angle) * 60.0
		outside_connection._process(1.0 / 60.0)
	_check(not outside_connection.loop_bound, "a closed polygon that excludes the slime does not bind it")

	var expiring_connection := _create_connection(combat, player, outside_target)
	combat.ranged_cooldown_left = 2.0
	expiring_connection.lifetime_left = 0.05
	expiring_connection._process(0.1)
	_check(expiring_connection.finished, "connection naturally expires after its duration")
	_check(is_equal_approx(combat.ranged_cooldown_left, 2.0), "natural expiry gives no Q cooldown reward")

	var long_connection := _create_connection(combat, player, outside_target)
	long_connection.maximum_length = 100.0
	player.global_position += Vector2(200.0, 0.0)
	long_connection._process(0.1)
	_check(long_connection.finished, "connection safely breaks when yarn length is exceeded")

	var blocked_target := _spawn_slime(night_scene, Vector2(600.0, 400.0))
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var wall_shape := CollisionShape2D.new()
	var wall_rectangle := RectangleShape2D.new()
	wall_rectangle.size = Vector2(20.0, 120.0)
	wall_shape.shape = wall_rectangle
	wall.add_child(wall_shape)
	wall.global_position = Vector2(550.0, 400.0)
	night_scene.add_child(wall)
	player.global_position = Vector2(500.0, 400.0)
	var blocked_connection := _create_connection(combat, player, blocked_target)
	await physics_frame
	await physics_frame
	_check(
		not is_instance_valid(blocked_connection) or blocked_connection.finished,
		"wall occlusion safely breaks yarn instead of drawing through it"
	)

	var dead_target := _spawn_slime(night_scene, Vector2(300.0, 550.0))
	var dead_connection := _create_connection(combat, player, dead_target)
	dead_target.state = dead_target.SlimeState.DEAD
	combat.ranged_cooldown_left = 2.0
	dead_connection._process(1.0 / 60.0)
	_check(dead_connection.finished, "target death cleans up its yarn connection")
	_check(is_equal_approx(combat.ranged_cooldown_left, 2.0), "target death does not grant Q cooldown reduction")

	var transition_target := _spawn_slime(night_scene, Vector2(700.0, 550.0))
	var transition_connection := _create_connection(combat, player, transition_target)
	var replacement_scene := Node2D.new()
	root.add_child(replacement_scene)
	current_scene = replacement_scene
	transition_connection._process(1.0 / 60.0)
	_check(transition_connection.finished, "scene transition cleans up stale yarn nodes")
	current_scene = night_scene
	replacement_scene.queue_free()

	for slime in [target_a, target_b, loop_target, outside_target, blocked_target, dead_target, transition_target]:
		if is_instance_valid(slime):
			slime.queue_free()
	if is_instance_valid(night_scene):
		for audio_player in night_scene.find_children("*", "AudioStreamPlayer2D", true, false):
			audio_player.stop()
			audio_player.stream = null
		night_scene.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.25).timeout
	if failures.is_empty():
		print("COMBAT_V3_PHASE_C_PASSED")
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


func _create_connection(combat: Node, player: Node2D, target: Node2D) -> Node2D:
	var connection: Node2D = load("res://scenes/combat/yarn_connection.tscn").instantiate()
	connection.configure(player, target, combat)
	current_scene.add_child(connection)
	return connection


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		failures.append(description)
