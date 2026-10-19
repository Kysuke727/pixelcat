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
	combat.set_process(false)
	player.global_position = Vector2(500.0, 350.0)
	for existing_enemy in get_nodes_in_group("enemies"):
		existing_enemy.set_physics_process(false)
		existing_enemy.global_position = Vector2(850.0, 600.0)
	_check(root.get_node("CombatBalance").tuning != null, "central combat tuning resource is loaded")
	_check(player.max_health == 5, "base player HP is five")
	_check(combat.first_melee_damage == 1 and combat.melee_damage == 2, "claw combo uses 1 then 2 damage")
	var has_shift_binding := false
	for input_event in InputMap.action_get_events("dodge"):
		if input_event is InputEventKey and input_event.physical_keycode == KEY_SHIFT:
			has_shift_binding = true
	_check(has_shift_binding, "dodge is bound to the Shift key")
	_check(player._try_start_dodge(Vector2.RIGHT), "dodge starts when available")
	_check(is_equal_approx(player.dodge_time_left, 0.15), "dodge lasts for its configured 0.15 seconds")
	_check(is_equal_approx(player.dodge_cooldown_left, 15.0), "dodge starts the 15-second cooldown")
	var health_before_dash_hit: int = player.current_health
	_check(not player.receive_damage(1, player.global_position + Vector2.LEFT), "dodge grants damage invulnerability")
	_check(player.current_health == health_before_dash_hit, "dodging does not reduce HP")
	_check(not player._try_start_dodge(Vector2.RIGHT), "dodge cannot be retriggered during cooldown")
	for _frame in range(9):
		player._physics_process(1.0 / 60.0)
	_check(absf(player.global_position.x - 555.0) <= 1.0, "dodge moves approximately 55 pixels in open space")

	player.global_position = Vector2(26.0, 350.0)
	player.dodge_cooldown_left = 0.0
	_check(player._try_start_dodge(Vector2.LEFT), "dodge can be used again after cooldown")
	for _frame in range(9):
		player._physics_process(1.0 / 60.0)
	_check(player.global_position.x >= 10.0, "dodge collides with walls instead of passing through")

	player.invincibility_left = 0.0
	player.current_health = player.max_health
	_check(player.receive_damage(1, player.global_position + Vector2.LEFT), "ordinary hit is accepted outside invulnerability")
	_check(is_equal_approx(player.hitstun_left, 0.3), "ordinary hitstun lasts 0.3 seconds")
	_check(is_equal_approx(player.invincibility_left, 1.0), "one-second hit invulnerability starts with damage")
	var health_after_hit: int = player.current_health
	player.hitstun_left = 0.1
	_check(not player.receive_damage(1, player.global_position + Vector2.LEFT), "hit invulnerability rejects repeated damage")
	_check(player.current_health == health_after_hit, "repeated hit during invulnerability cannot remove HP")
	_check(is_equal_approx(player.hitstun_left, 0.1), "rejected hit does not restart ordinary hitstun")
	player.hitstun_left = 0.0
	player.invincibility_left = 0.0

	Input.action_press("defend")
	player._physics_process(1.0 / 60.0)
	_check(player.velocity == Vector2.ZERO, "holding shield prevents movement")
	player.receive_attack_damage(920001, 1, player.global_position + Vector2.LEFT, 100.0, 25.0)
	_check(is_equal_approx(player.shield_durability, 75.0), "ordinary slime guard costs 25 shield")
	_check(player.current_health == health_after_hit, "shield blocks all lunge damage")
	_check(is_equal_approx(player.shield_regen_delay_left, 3.0), "shield recovery delay restarts when hit")
	player._update_defense(3.0)
	_check(is_equal_approx(player.shield_durability, 75.0), "shield waits the full three seconds without another hit")
	player._update_defense(0.5)
	_check(is_equal_approx(player.shield_durability, 82.5), "shield regenerates at 15 per second while held after the delay")
	Input.action_release("defend")
	player.is_defending = false
	player.shield_durability = 100.0
	for attack_id in range(920002, 920006):
		player.is_defending = true
		player.receive_attack_damage(attack_id, 1, player.global_position + Vector2.LEFT, 100.0, 25.0)
	_check(is_equal_approx(player.guard_break_left, 1.5), "empty shield enters the configured 1.5-second break")
	_check(not player.can_perform_combat_action(), "shield break prevents movement skills and attacks")
	var hp_during_break: int = player.current_health
	_check(not player.receive_damage(1, player.global_position + Vector2.LEFT), "guard-break stun grants damage immunity")
	_check(player.current_health == hp_during_break, "damage immunity preserves HP while broken")
	player._update_defense(1.5)
	_check(is_equal_approx(player.shield_durability, 30.0), "guard-break recovery restores 30 percent of maximum shield")
	_check(player.can_perform_combat_action(), "movement and attacks resume after the guard-break timer")
	player.guard_break_left = 0.0
	player.shield_durability = 100.0

	var slime: CharacterBody2D = load("res://scenes/enemies/slime.tscn").instantiate()
	night_scene.add_child(slime)
	slime.set_physics_process(false)
	_check(slime.max_health == 5, "normal slime HP is five")
	_check(is_equal_approx(slime.windup_duration, 0.4), "slime windup warning lasts 0.4 seconds")
	_check(is_equal_approx(slime.recover_duration, 0.5), "slime recovers for 0.5 seconds")
	slime.apply_yarn_bind(0.3)
	_check(is_equal_approx(slime.bind_time_left, 0.3), "initial binding applies normally")
	slime.apply_yarn_bind(1.0)
	_check(is_equal_approx(slime.bind_time_left, 0.3), "repeated bind cannot extend active control")
	slime._physics_process(0.3)
	_check(slime.bind_resistance_left > 0.0, "binding grants post-control immunity")
	slime.apply_yarn_bind(1.0)
	_check(is_equal_approx(slime.bind_time_left, 0.0), "binding immunity rejects an immediate rebind")
	_check(slime.apply_stun(0.5, 1.0), "stun can coexist with another status immunity")
	var stun_time_before_repeat: float = slime.stun_time_left
	_check(not slime.apply_stun(1.0, 1.0), "active stun cannot be refreshed indefinitely")
	_check(is_equal_approx(slime.stun_time_left, stun_time_before_repeat), "rejected stun does not prolong control")
	# Advance through stun and its complete one-second recovery immunity.
	for _frame in range(90):
		slime._physics_process(1.0 / 60.0)
	_check(slime.state != slime.SlimeState.STUNNED, "slime exits stun and returns to its AI")
	_check(slime.stun_immunity_left > 0.0, "stun immunity starts after stun ends")
	_check(not slime.apply_stun(1.0, 1.0), "post-stun immunity prevents immediate re-stun")

	var wall_slime: CharacterBody2D = load("res://scenes/enemies/slime.tscn").instantiate()
	night_scene.add_child(wall_slime)
	wall_slime.global_position = Vector2(978.0, 580.0)
	wall_slime.state = wall_slime.SlimeState.CHASE
	var wall_health: int = wall_slime.current_health
	wall_slime.receive_damage(2, wall_slime.global_position + Vector2.LEFT, 500.0)
	wall_slime.register_combo_finisher(920002, false, 1.0, 1.0)
	for _frame in range(4):
		wall_slime._physics_process(1.0 / 60.0)
	_check(wall_slime.current_health == wall_health - 2, "combo finisher resolves damage once before wall impact")
	_check(wall_slime.state == wall_slime.SlimeState.STUNNED, "failed random roll still guarantees stun on wall impact")
	_check(wall_slime.pending_combo_wall_attack_id == 0, "wall impact consumes its finisher ID once")
	var wall_stun_time: float = wall_slime.stun_time_left
	wall_slime.register_combo_finisher(920002, true, 1.0, 1.0)
	_check(is_equal_approx(wall_slime.stun_time_left, wall_stun_time), "same finisher ID cannot retrigger stun after wall impact")

	for node in [slime, wall_slime]:
		if is_instance_valid(node):
			node.queue_free()
	for audio_player in night_scene.find_children("*", "AudioStreamPlayer2D", true, false):
		audio_player.stop()
		audio_player.stream = null
	night_scene.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.25).timeout
	if failures.is_empty():
		print("COMBAT_V3_1_PHASE_02_PASSED")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		failures.append(description)
