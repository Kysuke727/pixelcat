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
	player.set_physics_process(false)
	player.set_process(false)
	player.global_position = Vector2(500.0, 350.0)
	for existing_enemy in get_nodes_in_group("enemies"):
		existing_enemy.set_physics_process(false)
		existing_enemy.global_position = Vector2(850.0, 600.0)

	var fast_a := _spawn_slime(night_scene, Vector2(350.0, 350.0))
	var fast_b := _spawn_slime(night_scene, Vector2(410.0, 350.0))
	fast_a.lunge_speed = 170.0
	fast_b.lunge_speed = 170.0
	fast_a.lunge_direction = Vector2.RIGHT
	fast_b.lunge_direction = Vector2.LEFT
	fast_a.state = fast_a.SlimeState.LUNGE
	fast_b.state = fast_b.SlimeState.LUNGE
	fast_a.state_time_left = 1.0
	fast_b.state_time_left = 1.0
	for _frame in range(35):
		await physics_frame
	_check(fast_a.state == fast_a.SlimeState.STUNNED, "high-speed slime collision stuns the first slime")
	_check(fast_b.state == fast_b.SlimeState.STUNNED, "high-speed slime collision stuns both participants")
	_check(fast_a.collision_stun_cooldown_left > 0.0, "collision starts the repeat-trigger cooldown")
	var stun_left_before: float = fast_a.stun_time_left
	_check(not fast_a.receive_collision_impact(fast_b, 170.0), "same collision cannot retrigger during cooldown")
	_check(fast_a.stun_time_left == stun_left_before, "cooldown prevents repeated stun refresh")

	var slow_a := _spawn_slime(night_scene, Vector2(350.0, 460.0))
	var slow_b := _spawn_slime(night_scene, Vector2(410.0, 460.0))
	slow_a.lunge_speed = 30.0
	slow_b.lunge_speed = 30.0
	slow_a.lunge_direction = Vector2.RIGHT
	slow_b.lunge_direction = Vector2.LEFT
	slow_a.state = slow_a.SlimeState.LUNGE
	slow_b.state = slow_b.SlimeState.LUNGE
	slow_a.state_time_left = 2.0
	slow_b.state_time_left = 2.0
	for _frame in range(55):
		await physics_frame
	_check(slow_a.state != slow_a.SlimeState.STUNNED, "low-speed contact does not stun a slime")
	_check(slow_b.state != slow_b.SlimeState.STUNNED, "low-speed contact does not stun the other slime")

	var lunger := _spawn_slime(night_scene, Vector2(570.0, 350.0))
	lunger.lunge_speed = 260.0
	lunger.state = lunger.SlimeState.WINDUP
	# This test injects WINDUP directly instead of entering through CHASE.
	# Real gameplay assigns the attack ID when CHASE starts the windup.
	lunger.current_attack_id = 880002
	lunger.locked_target_position = player.global_position
	lunger.state_time_left = 0.0
	var health_before: int = player.current_health
	for _frame in range(30):
		await physics_frame
	_check(player.current_health == health_before - lunger.attack_damage, "lunge deals damage once on physical player contact")
	_check(is_equal_approx(player.hitstun_left, player.player_hit_stagger_duration), "lunge applies configurable player stagger")
	_check(lunger.current_attack_id > 0, "each lunge receives an attack ID")
	var health_after_lunge: int = player.current_health
	_check(
		not player.receive_attack_damage(lunger.current_attack_id, 1, lunger.global_position, 0.0),
		"player rejects duplicate damage for the same attack ID"
	)
	_check(player.current_health == health_after_lunge, "duplicate attack ID leaves player health unchanged")
	_check(player.knockback_velocity.x < 0.0, "player knockback points away from the attacking slime")
	player.attack_block_handler = func(_attack_id: int) -> bool: return true
	player.hitstun_left = 0.0
	player.invincibility_left = 0.0
	var health_before_block: int = player.current_health
	_check(
		player.receive_attack_damage(900001, 1, lunger.global_position, 100.0),
		"successful defense hook consumes the incoming attack"
	)
	_check(player.current_health == health_before_block, "successfully defended attack causes no damage")
	_check(player.hitstun_left == 0.0, "successfully defended attack causes no stagger")
	player.attack_block_handler = Callable()

	var wall_hitter := _spawn_slime(night_scene, Vector2(30.0, 250.0))
	wall_hitter.lunge_speed = 180.0
	wall_hitter.lunge_direction = Vector2.LEFT
	wall_hitter.state = wall_hitter.SlimeState.LUNGE
	wall_hitter.state_time_left = 1.0
	for _frame in range(5):
		await physics_frame
	_check(wall_hitter.global_position.x >= 20.0, "wall impact does not pass through the wall")
	_check(wall_hitter.state == wall_hitter.SlimeState.HURT, "fast wall impact enters brief rebound/stagger")
	_check(wall_hitter.hurt_velocity.x > 0.0, "wall impact rebounds away from the wall")

	for slime in [fast_a, fast_b, slow_a, slow_b, lunger, wall_hitter]:
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
		print("COMBAT_V3_PHASE_B_PASSED")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _spawn_slime(parent: Node, position: Vector2) -> CharacterBody2D:
	var slime: CharacterBody2D = load("res://scenes/enemies/slime.tscn").instantiate()
	parent.add_child(slime)
	slime.global_position = position
	return slime


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		failures.append(description)
