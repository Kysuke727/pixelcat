extends SceneTree

class MockPlayer:
	extends CharacterBody2D
	var health: int = 5
	func receive_damage(amount: int, _source_position: Vector2, _knockback: float = 0.0) -> void:
		health -= amount

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
		enemy.global_position = Vector2(900.0, 650.0)
	_check(is_equal_approx(combat.ranged_cooldown, 4.0), "central yarn cooldown defaults to four seconds")
	_check(is_equal_approx(combat.yarn_connection_duration, 10.0), "base yarn connection duration remains ten seconds")
	_check(is_equal_approx(combat.yarn_cut_cooldown_reduction, 1.5), "Q cut refund remains 1.5 seconds")

	# The actual fired projectile hits a real enemy and creates a connection.
	player.global_position = Vector2(200.0, 300.0)
	combat.facing = Vector2.RIGHT
	var hit_target := _spawn_slime(world, Vector2(270.0, 300.0))
	combat._spawn_projectile()
	for _frame in range(30):
		await physics_frame
		if not combat.yarn_projectile_in_flight:
			break
	_check(combat.active_yarn_connections.size() == 1, "K projectile hit records a live connection target")
	if combat.active_yarn_connections.size() > 0:
		var fired_connection: YarnConnection = combat.active_yarn_connections[0]
		_check(fired_connection.target == hit_target, "connection stores the exact struck slime")
		_check(is_equal_approx(combat.ranged_cooldown_left, 4.0), "cooldown starts on launch, not after connection expiry")
		fired_connection.finish_naturally()

	# Both directions, a 270-degree wrap crossing +/-180, and a moving target.
	for clockwise in [true, false]:
		var target := _spawn_slime(world, Vector2(500.0, 350.0))
		var radius := 70.0
		player.global_position = target.global_position + Vector2(radius, 0.0)
		var connection := _create_connection(combat, player, target)
		await process_frame
		for step in range(1, 46): # 6° increments; the final point is exactly 270°.
			var sign := -1.0 if clockwise else 1.0
			var angle := sign * deg_to_rad(6.0 * step)
			var orbit_offset := Vector2.from_angle(angle) * radius
			if step > 1:
				target.global_position += Vector2(0.15, 0.0)
			player.global_position = target.global_position + orbit_offset
			connection._process(1.0 / 60.0)
			if step == 36:
				_check(not connection.loop_bound, "240-degree orbit does not trigger early")
		_check(connection.loop_bound, "270-degree %s orbit binds the tethered target" % ("clockwise" if clockwise else "counterclockwise"))
		_check(absf(connection.accumulated_loop_angle) >= 270.0, "signed angle survives the +/-180-degree wrap")
		_check(target.bind_time_left >= combat.yarn_bind_duration, "base yarn bind lasts 1.5 seconds")
		_check(connection.get_node("DebugStatus").text.contains("目标："), "live yarn connection displays its target and debug status")
		connection.finish_naturally()

	# Reversal must cancel angular progress instead of accumulating absolute jitter.
	var reverse_target := _spawn_slime(world, Vector2(500.0, 350.0))
	player.global_position = reverse_target.global_position + Vector2(70.0, 0.0)
	var reverse_connection := _create_connection(combat, player, reverse_target)
	await process_frame
	for angle_degrees in range(6, 151, 6):
		player.global_position = reverse_target.global_position + Vector2.from_angle(deg_to_rad(float(angle_degrees))) * 70.0
		reverse_connection._process(1.0 / 60.0)
	for angle_degrees in range(144, 59, -6):
		player.global_position = reverse_target.global_position + Vector2.from_angle(deg_to_rad(float(angle_degrees))) * 70.0
		reverse_connection._process(1.0 / 60.0)
	_check(absf(reverse_connection.accumulated_loop_angle) < 100.0, "mid-orbit reversal subtracts progress")
	_check(not reverse_connection.loop_bound, "reversing cannot satisfy the loop condition")
	for angle_degrees in range(66, 271, 6):
		player.global_position = reverse_target.global_position + Vector2.from_angle(deg_to_rad(float(angle_degrees))) * 70.0
		reverse_connection._process(1.0 / 60.0)
	_check(reverse_connection.loop_bound, "continuing in one direction eventually completes the loop")
	reverse_connection.finish_naturally()

	# Small repeated motion is below the sampling threshold; it cannot farm angle.
	var jitter_target := _spawn_slime(world, Vector2(500.0, 350.0))
	player.global_position = jitter_target.global_position + Vector2(70.0, 0.0)
	var jitter_connection := _create_connection(combat, player, jitter_target)
	await process_frame
	for index in range(80):
		player.global_position = jitter_target.global_position + Vector2(70.0 + (1.0 if index % 2 == 0 else -1.0), 0.0)
		jitter_connection._process(1.0 / 60.0)
	_check(is_zero_approx(jitter_connection.accumulated_loop_angle), "small left-right jitter cannot farm loop angle")
	_check(jitter_connection.get_debug_status_text().contains("有效轨迹点不足"), "debug display reports why a loop has not triggered")
	jitter_connection.finish_naturally()

	# Connection expiration yields a concrete debug reason.
	var timeout_target := _spawn_slime(world, Vector2(500.0, 350.0))
	player.global_position = timeout_target.global_position + Vector2(70.0, 0.0)
	var timeout_connection := _create_connection(combat, player, timeout_target)
	await process_frame
	timeout_connection.lifetime_left = 0.01
	timeout_connection._process(0.02)
	_check(timeout_connection.finished, "yarn connection timeout cleans itself up")
	_check(timeout_connection.last_bind_failure_reason == "连接超时", "debug reason identifies connection timeout")

	# Slime detects, chases, winds up with visible feedback, lunges, and hits once.
	player.global_position = Vector2(600.0, 350.0)
	var attacker := _spawn_slime(world, player.global_position + Vector2(150.0, 0.0))
	attacker.set_physics_process(true)
	attacker._physics_process(1.0 / 60.0)
	_check(attacker.state == attacker.SlimeState.CHASE, "slime detects the player and enters chase")
	for _frame in range(180):
		await physics_frame
		attacker._physics_process(1.0 / 60.0)
		if attacker.state == attacker.SlimeState.WINDUP:
			break
	_check(attacker.state == attacker.SlimeState.WINDUP, "slime closes distance and enters attack warning")
	_check(attacker.sprite.modulate.r > attacker.sprite.modulate.g, "windup has visible warning tint")
	_check(attacker.windup_duration >= 0.4, "slime windup is at least 0.4 seconds")
	attacker.state_time_left = 0.0
	attacker._process_windup()
	_check(attacker.state == attacker.SlimeState.LUNGE, "windup transitions into lunge")
	_check(attacker.attack_area.body_entered.is_connected(attacker._on_attack_area_body_entered), "lunge area is wired to its hit handler")
	var mock := MockPlayer.new()
	mock.add_to_group("player")
	world.add_child(mock)
	attacker._on_attack_area_body_entered(mock)
	attacker._on_attack_area_body_entered(mock)
	_check(mock.health == 4, "one lunge cannot deal duplicate damage to the same player")
	attacker.apply_stun(0.1, 0.0)
	_check(attacker.state == attacker.SlimeState.STUNNED, "control effect interrupts slime attack")
	attacker.stun_time_left = 0.0
	attacker._process_stunned()
	_check(attacker.state == attacker.SlimeState.CHASE, "slime resumes AI after control ends")

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
	if failures.is_empty():
		print("V3_1_1_YARN_SLIME_FIXES_PASSED")
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


func _create_connection(combat: Node, player: Node2D, target: Node2D) -> YarnConnection:
	var connection := load("res://scenes/combat/yarn_connection.tscn").instantiate() as YarnConnection
	connection.configure(player, target, combat)
	current_scene.add_child(connection)
	return connection


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		failures.append(description)
