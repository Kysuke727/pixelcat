extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_feeding_stop_and_loop_barrier()
	if failures.is_empty():
		print("YARN_FEED_RETAINED_LOOP_PASSED")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _test_feeding_stop_and_loop_barrier() -> void:
	_check(_input_uses_key("ranged_attack", KEY_K), "existing ranged_attack binding remains K")
	_check(_input_uses_key("yarn_cut", KEY_Q), "existing yarn_cut binding remains Q")
	var world := load("res://scenes/worlds/night_world.tscn").instantiate() as Node2D
	root.add_child(world)
	current_scene = world
	await physics_frame
	var player := get_first_node_in_group("player") as CharacterBody2D
	var combat := player.get_node("PlayerCombat")
	player.set_physics_process(false)
	for enemy in get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
		enemy.set_process(false)
		enemy.global_position = Vector2(1450.0, 900.0)
	var anchor := _spawn_slime(world, Vector2(1000.0, 900.0))
	player.global_position = Vector2(800.0, 900.0)
	var connection := load("res://scenes/combat/yarn_connection.tscn").instantiate() as YarnConnection
	connection.configure(player, anchor, combat)
	connection.set_physics_process(false)
	world.add_child(connection)
	combat.active_yarn_connections.append(connection)
	await physics_frame
	var original_length := connection.effective_rope_length
	var route_before := connection._build_routed_path()
	connection._capture_feed_step(route_before)
	var old_player_position := player.global_position
	player.global_position += Vector2(-20.0, 0.0)
	connection._pay_out_for_player_route_growth(old_player_position, player.global_position)
	_check(is_equal_approx(connection.effective_rope_length, original_length + 20.0), "player-caused routed growth pays out rope while feeding")
	var feed_length_after_player_move := connection.effective_rope_length
	connection._capture_feed_step(connection._build_routed_path())
	var anchor_before_motion := anchor.global_position
	anchor.global_position += Vector2(0.0, 8.0)
	var player_before_anchor_motion := player.global_position
	player.global_position += Vector2(-8.0, 0.0)
	connection._pay_out_for_player_route_growth(player_before_anchor_motion, player.global_position)
	_check(is_equal_approx(connection.effective_rope_length, feed_length_after_player_move), "anchor movement cannot manufacture paid-out rope length")
	anchor.global_position = anchor_before_motion
	var support := load("res://scenes/combat/yarn_wrap_point.tscn").instantiate() as Node2D
	world.add_child(support)
	connection.wrap_supports = [support]
	connection._capture_feed_step(connection._build_routed_path())
	var player_before_support_motion := player.global_position
	player.global_position += Vector2(-8.0, 0.0)
	support.global_position += Vector2(0.0, 12.0)
	connection._pay_out_for_player_route_growth(player_before_support_motion, player.global_position)
	_check(is_equal_approx(connection.effective_rope_length, feed_length_after_player_move), "support motion and topology cannot manufacture paid-out rope length")
	connection.wrap_supports.clear()
	connection._update_rope_lengths_and_barrier()
	var slack_before_stop := connection.remaining_slack
	var action_before_stop: int = combat.action_state
	_check(combat._handle_ranged_attack_pressed(), "K with a live link is consumed as stop-feeding")
	_check(not connection.feeding_enabled, "K locks the current released rope length")
	_check(is_equal_approx(connection.remaining_slack, slack_before_stop), "stopping feed preserves remaining slack")
	_check(is_equal_approx(connection.effective_rope_length, original_length + 20.0), "stopping feed does not add or discard released length")
	_check(combat.action_state == action_before_stop and not combat.projectile_fired, "stopping feed does not start another projectile action")
	_check(combat._handle_ranged_attack_pressed(), "later K press remains consumed while the cat-side link exists")

	# The retained loop is independent of the cat endpoint and has physical edges.
	var loop_path := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(0.0, 100.0), Vector2(100.0, 100.0),
		Vector2(100.0, 0.0), Vector2(0.0, 0.0)
	])
	connection.bind_duration = 0.45
	connection._retain_bound_loops([loop_path])
	await physics_frame
	var retained := get_first_node_in_group("persistent_yarn_loops") as BoundYarnLoop
	_check(is_instance_valid(retained), "successful-wrap retention creates an independent loop node")
	_check(retained.collision_layer == 8 and retained.is_in_group("yarn_barriers"), "retained closed loop is a separate physical yarn barrier")
	_check((player.collision_mask & 8) == 0, "cat is not trapped by the retained loop and can leave")
	var crossing_enemy := _new_crossing_body(world, Vector2(-20.0, 50.0))
	for _frame in range(18):
		crossing_enemy.velocity = Vector2(120.0, 0.0)
		crossing_enemy.move_and_slide()
		await physics_frame
	_check(crossing_enemy.global_position.x < -5.0, "outside enemy cannot cross the active retained loop")
	await create_timer(0.55).timeout
	await physics_frame
	_check(not is_instance_valid(retained), "retained loop collision and visual are removed at configured expiry")
	for _frame in range(18):
		crossing_enemy.velocity = Vector2(120.0, 0.0)
		crossing_enemy.move_and_slide()
		await physics_frame
	_check(crossing_enemy.global_position.x > 5.0, "enemy can cross after the retained loop expires")

	# Active physics verifies that lunge collision ends in ordinary recovery, not stun.
	var lunge_loop := BoundYarnLoop.new()
	var lunge_path := PackedVector2Array([
		Vector2(250.0, 0.0), Vector2(250.0, 100.0), Vector2(350.0, 100.0),
		Vector2(350.0, 0.0), Vector2(250.0, 0.0)
	])
	lunge_loop.setup([lunge_path], 1.5, 2.5)
	world.add_child(lunge_loop)
	var lunging_slime := _spawn_slime(world, Vector2(225.0, 50.0))
	lunging_slime.set("state", 4) # SlimeState.LUNGE
	lunging_slime.set("state_time_left", 1.0)
	lunging_slime.set("lunge_duration", 0.9)
	lunging_slime.set("lunge_direction", Vector2.RIGHT)
	lunging_slime.set("lunge_speed", 220.0)
	for _frame in range(20):
		await physics_frame
	_check(lunging_slime.get("state") == 5, "lunge hitting a retained loop stops and enters ordinary RECOVER")
	_check(lunging_slime.get("stun_time_left") <= 0.0, "yarn loop impact does not apply extra stun")

	connection.finish_naturally()
	for node in [connection, anchor, support, crossing_enemy, lunging_slime, lunge_loop, world]:
		if is_instance_valid(node):
			node.queue_free()
	await physics_frame
	await process_frame


func _input_uses_key(action: StringName, physical_code: Key) -> bool:
	if not InputMap.has_action(action):
		return false
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == physical_code:
			return true
	return false


func _spawn_slime(parent: Node, position: Vector2) -> Node2D:
	var slime := load("res://scenes/enemies/slime.tscn").instantiate() as Node2D
	parent.add_child(slime)
	slime.global_position = position
	return slime


func _new_crossing_body(parent: Node, position: Vector2) -> CharacterBody2D:
	var body := CharacterBody2D.new()
	body.collision_layer = 2
	body.collision_mask = 8
	var collision := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 5.0
	collision.shape = circle
	body.add_child(collision)
	parent.add_child(body)
	body.global_position = position
	return body


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		failures.append(description)
