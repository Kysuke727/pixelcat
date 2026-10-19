extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var night_scene: Node = load("res://scenes/worlds/night_world.tscn").instantiate()
	root.add_child(night_scene)
	current_scene = night_scene
	await process_frame
	await process_frame

	var player := get_first_node_in_group("player")
	var combat = player.get_node("PlayerCombat")
	combat.set_process(false)
	player.set_physics_process(false)
	player.global_position = Vector2(500.0, 350.0)
	for slime in get_nodes_in_group("enemies"):
		slime.set_physics_process(false)
		slime.global_position = Vector2(850.0, 600.0)

	var enemy: CharacterBody2D = load("res://scenes/enemies/slime.tscn").instantiate()
	night_scene.add_child(enemy)
	enemy.max_health = 10
	enemy.current_health = 10
	enemy.global_position = player.global_position + Vector2(17.0, 0.0)
	enemy.set_physics_process(false)
	player.last_facing = Vector2.RIGHT
	await physics_frame

	combat.stun_rng.seed = 20261019
	combat._start_melee(false)
	_advance_action(combat, 0.10)
	await physics_frame
	await physics_frame
	combat._apply_overlapping_melee_hits()
	combat._apply_overlapping_melee_hits()
	_check(enemy.current_health == 9, "Attack1 deals one configured damage once")
	_check(combat.combo_window_open, "combo window opens only after a successful Attack1 hit")
	_advance_action(combat, 0.16)
	_check(combat.action_state == combat.ActionState.RECOVERY, "first attack enters recovery")

	var expected_rng := RandomNumberGenerator.new()
	expected_rng.seed = 20261019
	var expected_stun := expected_rng.randf() < 0.5
	combat._start_melee(true)
	_advance_action(combat, 0.10)
	await physics_frame
	combat._apply_overlapping_melee_hits()
	combat._apply_overlapping_melee_hits()
	_check(enemy.current_health == 7, "Attack2 deals two damage once without duplicate damage")
	_check((enemy.state == enemy.SlimeState.STUNNED) == expected_stun, "Attack2 stun chance follows the seeded 50 percent roll")
	if expected_stun:
		_check(enemy.stun_time_left > 0.0, "successful stun lasts for its configured duration")
		_check(not enemy.apply_stun(1.0, 1.0), "stun resistance prevents refreshing the stun")
		_advance_slime_physics(enemy, 70)
		_check(enemy.state != enemy.SlimeState.STUNNED, "slime resumes AI after stun ends")
		_check(enemy.stun_immunity_left > 0.0, "slime gains one second of post-stun immunity")
		_check(not enemy.apply_stun(1.0, 1.0), "post-stun immunity prevents immediate re-control")
		_advance_slime_physics(enemy, 70)
	else:
		_check(enemy.state != enemy.SlimeState.STUNNED, "failed stun roll leaves the target unstunned")

	var rng_state_before_miss: int = combat.stun_rng.state
	_advance_action(combat, 0.16)
	enemy.global_position = player.global_position + Vector2(250.0, 0.0)
	await physics_frame
	await physics_frame
	combat.melee_cooldown_left = 0.0
	combat._start_melee(false)
	_advance_action(combat, 0.25)
	_check(not combat.combo_window_open, "missed Attack1 does not open a combo window")
	_check(combat.stun_rng.state == rng_state_before_miss, "missed attack does not consume a stun roll")

	# Exercise the other deterministic RNG outcome so a successful stun is covered too.
	var success_seed := 1
	var success_rng := RandomNumberGenerator.new()
	success_rng.seed = success_seed
	while success_rng.randf() >= 0.5:
		success_seed += 1
		success_rng.seed = success_seed
	enemy.global_position = player.global_position + Vector2(17.0, 0.0)
	await physics_frame
	await physics_frame
	combat.melee_cooldown_left = 0.0
	combat._start_melee(false)
	_advance_action(combat, 0.10)
	await physics_frame
	await physics_frame
	combat._apply_overlapping_melee_hits()
	_advance_action(combat, 0.16)
	combat.melee_cooldown_left = 0.0
	combat.stun_rng.seed = success_seed
	combat._start_melee(true)
	_advance_action(combat, 0.10)
	await physics_frame
	await physics_frame
	combat._apply_overlapping_melee_hits()
	_check(enemy.state == enemy.SlimeState.STUNNED, "seeded successful stun roll enters STUNNED")
	_check(enemy.stun_time_left > 0.0, "successful stun lasts for its configured duration")
	_check(not enemy.apply_stun(1.0, 1.0), "stun resistance prevents refreshing the stun")
	_advance_slime_physics(enemy, 70)
	_check(enemy.state != enemy.SlimeState.STUNNED, "slime resumes AI after stun ends")

	for direction in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
		combat.melee_hitbox.monitoring = false
		player.last_facing = direction
		enemy.global_position = player.global_position + direction * 18.0
		combat.facing = combat._get_facing()
		combat._update_hitbox_transform()
		combat.melee_hitbox.monitoring = true
		await physics_frame
		await physics_frame
		_check(combat.melee_hitbox.get_overlapping_bodies().has(enemy), "melee hitbox faces %s" % direction)
		combat.melee_hitbox.monitoring = false
		await physics_frame
	enemy.global_position = player.global_position + Vector2(250.0, 0.0)

	if is_instance_valid(night_scene):
		for audio_player in night_scene.find_children("*", "AudioStreamPlayer2D", true, false):
			audio_player.stop()
			audio_player.stream = null
		night_scene.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.25).timeout
	if failures.is_empty():
		print("COMBAT_V3_PHASE_A_PASSED")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _advance_action(combat: Node, duration: float) -> void:
	var elapsed := 0.0
	while elapsed < duration:
		var step: float = minf(1.0 / 60.0, duration - elapsed)
		combat.action_time += step
		combat._update_action()
		elapsed += step


func _advance_slime_physics(slime: Node, count: int) -> void:
	for _index in range(count):
		slime._physics_process(1.0 / 60.0)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		failures.append(description)
