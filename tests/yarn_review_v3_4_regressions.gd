extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_actual_closed_loop_geometry()
	await _test_group_collection_uses_actual_closed_loop()
	await _test_stale_secondary_support_and_contact_solving()
	await _test_current_endpoint_pull()
	if failures.is_empty():
		print("YARN_REVIEW_V3_4_REGRESSIONS_PASSED")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _test_actual_closed_loop_geometry() -> void:
	var geometry := YarnConnection.new()
	var open_u := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(100.0, 0.0), Vector2(100.0, 100.0), Vector2(0.0, 100.0)
	])
	_check(not geometry._point_is_inside_routed_loop(Vector2(50.0, 50.0), open_u), "open U does not acquire a virtual closing edge")
	var closed_square := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(100.0, 0.0), Vector2(100.0, 100.0), Vector2(0.0, 100.0), Vector2(0.0, 0.0)
	])
	_check(geometry._point_is_inside_routed_loop(Vector2(50.0, 50.0), closed_square), "explicitly closed route contains a known interior point")
	_check(not geometry._point_is_inside_routed_loop(Vector2(130.0, 50.0), closed_square), "explicitly closed route excludes a known exterior point")
	_check(geometry._point_is_inside_routed_loop(Vector2(0.0, 50.0), closed_square), "loop boundary is included by the documented boundary rule")
	var bow_tie := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(100.0, 100.0), Vector2(0.0, 100.0), Vector2(100.0, 0.0)
	])
	_check(geometry._point_is_inside_routed_loop(Vector2(50.0, 80.0), bow_tie), "self-crossing route settles a target in its actually closed lobe")
	_check(not geometry._point_is_inside_routed_loop(Vector2(50.0, 20.0), bow_tie), "dangling tail beyond the crossing is not treated as a second lobe")
	var repeated_square := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(100.0, 0.0), Vector2(100.0, 100.0), Vector2(0.0, 100.0), Vector2(0.0, 0.0),
		Vector2(100.0, 0.0), Vector2(100.0, 100.0), Vector2(0.0, 100.0), Vector2(0.0, 0.0)
	])
	_check(geometry._point_is_inside_routed_loop(Vector2(50.0, 50.0), repeated_square), "repeated same-direction loop does not parity-cancel its interior")
	geometry.free()


func _test_group_collection_uses_actual_closed_loop() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var test_player := Node2D.new()
	var test_anchor := Node2D.new()
	world.add_child(test_player)
	world.add_child(test_anchor)
	var geometry := load("res://scenes/combat/yarn_connection.tscn").instantiate() as YarnConnection
	geometry.configure(test_player, test_anchor, null)
	world.add_child(geometry)
	geometry.set_physics_process(false)
	var closed_square := PackedVector2Array([
		Vector2(100.0, 100.0), Vector2(300.0, 100.0), Vector2(300.0, 300.0),
		Vector2(100.0, 300.0), Vector2(100.0, 100.0)
	])
	var inside_a := _spawn_slime(world, Vector2(150.0, 150.0))
	var inside_b := _spawn_slime(world, Vector2(250.0, 150.0))
	var inside_c := _spawn_slime(world, Vector2(150.0, 250.0))
	var outside := _spawn_slime(world, Vector2(350.0, 150.0))
	var selected := geometry._collect_targets_inside_actual_loops(closed_square)
	_check(selected.has(inside_a) and selected.has(inside_b) and selected.has(inside_c), "actual closed loop independently selects all three known interior enemies")
	_check(not selected.has(outside), "actual closed loop excludes the known exterior enemy")
	for node in [geometry, test_player, test_anchor, inside_a, inside_b, inside_c, outside]:
		if is_instance_valid(node):
			node.queue_free()
	world.queue_free()
	await physics_frame
	await process_frame


func _test_stale_secondary_support_and_contact_solving() -> void:
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
	var primary := _spawn_slime(world, Vector2(500.0, 500.0))
	var anchor := _spawn_slime(world, Vector2(720.0, 500.0))
	var secondary := _spawn_slime(world, Vector2(930.0, 930.0))
	player.global_position = Vector2(430.0, 500.0)
	var connection := load("res://scenes/combat/yarn_connection.tscn").instantiate() as YarnConnection
	connection.configure(player, anchor, combat)
	connection.set_physics_process(false)
	world.add_child(connection)
	connection.wrap_pivot = primary
	connection.wrap_supports = [primary, secondary]
	connection.is_wrapped = true
	connection.wrap_state = YarnConnection.WrapState.WOUND
	connection.winding_complete = true
	connection.wrap_contact_radius = primary.yarn_wrap_radius
	var stale_targets := connection._collect_enclosed_targets()
	_check(not stale_targets.has(secondary), "released secondary enemy outside the routed path is not eligible by history alone")

	# Both obstacles touch distinct segments of the same currently routed cable.
	connection.wrap_supports = [primary]
	var initial_path := connection._build_routed_path()
	var first_segment := _select_route_segment(initial_path, primary.global_position, -1)
	var second_segment := _select_route_segment(initial_path, primary.global_position, first_segment[2])
	var support_a := load("res://scenes/combat/yarn_wrap_point.tscn").instantiate() as YarnWrapPoint
	var support_b := load("res://scenes/combat/yarn_wrap_point.tscn").instantiate() as YarnWrapPoint
	world.add_child(support_a)
	world.add_child(support_b)
	support_a.global_position = (first_segment[0] + first_segment[1]) * 0.5
	support_b.global_position = (second_segment[0] + second_segment[1]) * 0.5
	support_a.yarn_wrap_radius = 14.0
	support_b.yarn_wrap_radius = 14.0
	var angle_before := connection.accumulated_wrap_angle
	connection._add_contacted_supports()
	_check(connection.wrap_supports.size() >= 3, "one contact solve processes both newly contacted supports in path order")
	_check(is_equal_approx(connection.accumulated_wrap_angle, angle_before), "multi-contact solve preserves committed winding")
	_check(connection._validate_current_path(), "resolved multi-contact route clears every physical support")
	_check(not connection._collect_enclosed_targets().has(secondary), "historically touched enemy does not bind after release")

	for node in [connection, primary, anchor, secondary, support_a, support_b]:
		if is_instance_valid(node):
			node.queue_free()
	for enemy in get_nodes_in_group("enemies"):
		if is_instance_valid(enemy):
			enemy.queue_free()
	world.queue_free()
	await physics_frame
	await process_frame


func _test_current_endpoint_pull() -> void:
	var world := Node2D.new()
	world.name = "YarnPhysicalContractTest"
	root.add_child(world)
	current_scene = world
	var player := CharacterBody2D.new()
	player.name = "TestCat"
	player.collision_layer = 1
	player.collision_mask = 4
	var player_shape := CollisionShape2D.new()
	var player_circle := CircleShape2D.new()
	player_circle.radius = 5.0
	player_shape.shape = player_circle
	player.add_child(player_shape)
	world.add_child(player)
	player.global_position = Vector2(100.0, 200.0)
	var anchor := Node2D.new()
	anchor.name = "TestAnchor"
	world.add_child(anchor)
	anchor.global_position = Vector2(300.0, 200.0)
	var connection := load("res://scenes/combat/yarn_connection.tscn").instantiate() as YarnConnection
	connection.configure(player, anchor, null)
	connection.initial_slack_length = 20.0
	world.add_child(connection)
	await physics_frame
	var original_effective_length := connection.effective_rope_length
	connection._update_rope_lengths_and_barrier()
	_check(is_equal_approx(connection.effective_rope_length, 220.0), "effective rope length is fixed once the yarn sticks")
	_check(is_equal_approx(connection.remaining_slack, 20.0), "actual routed length and remaining slack are separate values")
	var routed_start := connection.actual_routed_length
	for _frame in range(18):
		player.velocity = connection.constrain_player_velocity(Vector2(-100.0, 0.0), 1.0 / 60.0)
		player.move_and_slide()
		connection.on_player_physics_moved(Vector2.ZERO, player.global_position)
		await physics_frame
	_check(player.global_position.x >= 79.0, "cat cannot exceed its released rope length while moving outward")
	_check(is_equal_approx(connection.effective_rope_length, original_effective_length), "movement does not automatically pay out more rope")
	var x_at_leash := player.global_position.x
	player.velocity = connection.constrain_player_velocity(Vector2(80.0, 0.0), 1.0 / 60.0)
	_check(player.velocity.x > 0.0, "cat can move inward and release tension")
	player.move_and_slide()
	await physics_frame
	player.global_position = Vector2(100.0, 200.0)
	connection.effective_rope_length = connection._routed_path_length() + 12.0
	connection._update_rope_lengths_and_barrier()
	_check(connection._rope_barrier_body.collision_layer == 0, "a slack rope does not hard-stop a contacting enemy")
	var enemy := CharacterBody2D.new()
	enemy.name = "CrossingEnemy"
	enemy.collision_layer = 2
	enemy.collision_mask = 4
	var enemy_shape := CollisionShape2D.new()
	var enemy_circle := CircleShape2D.new()
	enemy_circle.radius = 8.0
	enemy_shape.shape = enemy_circle
	enemy.add_child(enemy_shape)
	world.add_child(enemy)
	enemy.global_position = Vector2(200.0, 130.0)
	await physics_frame
	for _frame in range(50):
		enemy.velocity = Vector2(0.0, 120.0)
		enemy.move_and_slide()
		await physics_frame
	_check(enemy.global_position.y > 210.0, "enemy can push through the cable while it is slack")
	enemy.global_position = Vector2(200.0, 130.0)
	connection.effective_rope_length = connection._routed_path_length()
	connection._update_rope_lengths_and_barrier()
	await physics_frame
	await physics_frame
	_check(connection._rope_barrier_body.collision_layer == 4, "taut route activates collision along the visible cable")
	for _frame in range(30):
		enemy.velocity = Vector2(0.0, 120.0)
		enemy.move_and_slide()
		await physics_frame
	_check(enemy.global_position.y < 195.0, "taut rope physically blocks enemy crossing")
	var blocked_y := enemy.global_position.y
	for _frame in range(20):
		enemy.velocity = Vector2(60.0, 0.0)
		enemy.move_and_slide()
		await physics_frame
	_check(enemy.global_position.x > 205.0 and absf(enemy.global_position.y - blocked_y) < 2.0, "enemy can slide tangentially along the taut cable")
	_check(connection.cut_by_player(), "Q cut ends the rope constraint immediately")
	_check(connection.constrain_player_velocity(Vector2(-50.0, 0.0), 1.0 / 60.0).x < 0.0, "cut cable no longer constrains the cat")
	for node in [connection, player, anchor, enemy]:
		if is_instance_valid(node):
			node.queue_free()
	world.queue_free()
	await physics_frame
	await process_frame


func _spawn_slime(parent: Node, position: Vector2) -> Node2D:
	var slime := load("res://scenes/enemies/slime.tscn").instantiate() as Node2D
	parent.add_child(slime)
	slime.global_position = position
	slime.set_physics_process(false)
	slime.set_process(false)
	return slime


func _select_route_segment(path: PackedVector2Array, primary: Vector2, exclude_index: int) -> Array:
	var candidates: Array = []
	for index in range(path.size() - 1):
		var start := path[index]
		var end := path[index + 1]
		if index == exclude_index or start.distance_to(end) < 25.0:
			continue
		if ((start + end) * 0.5).distance_to(primary) < 30.0:
			continue
		candidates.append([start, end, index])
	if candidates.is_empty():
		return [path[0], path[1], -1]
	return candidates[0]


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		failures.append(description)
