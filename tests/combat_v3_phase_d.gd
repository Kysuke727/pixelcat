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
	var time_controller: Node = root.get_node("CombatTimeController")
	player.set_physics_process(false)
	player.set_process(false)
	combat.set_process(false)
	time_controller.set_process(false)
	time_controller.clear_enemy_pause()
	player.global_position = Vector2(100.0, 100.0)
	for existing_enemy in get_nodes_in_group("enemies"):
		existing_enemy.set_physics_process(false)
		existing_enemy.global_position = Vector2(850.0, 600.0)
		if existing_enemy.has_method("set_combat_paused"):
			existing_enemy.set_combat_paused(false)

	_check(InputMap.has_action("defend"), "Z defense input action is configured")
	var health_before: int = player.current_health
	player.is_defending = true
	_check(
		player.receive_attack_damage(810001, 1, Vector2(90.0, 100.0), 100.0, 35.0),
		"ordinary defense consumes an incoming attack"
	)
	_check(is_equal_approx(player.shield_durability, 65.0), "ordinary lunge defense consumes 35 durability")
	_check(player.current_health == health_before, "ordinary defense blocks all attack damage")
	_check(player.hitstun_left == 0.0, "ordinary defense blocks normal hitstun")
	_check(
		not player.receive_attack_damage(810001, 1, Vector2(90.0, 100.0), 100.0, 35.0),
		"repeated same attack ID cannot consume shield twice"
	)
	_check(is_equal_approx(player.shield_durability, 65.0), "deduplication preserves shield durability")
	player.is_defending = true
	player.receive_attack_damage(810002, 1, Vector2(90.0, 100.0), 100.0, 35.0)
	player.is_defending = true
	player.receive_attack_damage(810003, 1, Vector2(90.0, 100.0), 100.0, 35.0)
	_check(is_equal_approx(player.shield_durability, 0.0), "shield durability never becomes negative")
	_check(is_equal_approx(player.guard_break_left, 3.0), "empty shield triggers a 3-second guard break")
	_check(not player.is_defending, "guard break cancels active defense")
	_check(not combat._can_start_action(), "guard break prevents J/K actions")
	player._physics_process(0.5)
	_check(is_equal_approx(player.guard_break_left, 2.5), "guard break timer advances without pausing the world")

	player.guard_break_left = 0.0
	player.shield_durability = 30.0
	player.shield_regen_delay_left = 2.0
	player.is_defending = false
	Input.action_release("defend")
	player._update_defense(1.0)
	_check(is_equal_approx(player.shield_durability, 30.0), "shield does not regenerate before the two-second delay")
	player._update_defense(1.0)
	_check(is_equal_approx(player.shield_durability, 30.0), "shield begins recovery only after the full delay")
	player._update_defense(0.5)
	_check(is_equal_approx(player.shield_durability, 40.0), "shield restores at 20 durability per second")
	player.is_defending = true
	_check(not combat._can_start_action(), "holding ordinary defense prevents J/K actions")
	player.is_defending = false

	var early_enemy := _spawn_slime(night_scene, player.global_position + Vector2(100.0, 0.0))
	early_enemy.state = early_enemy.SlimeState.WINDUP
	early_enemy.current_attack_id = 810010
	early_enemy.locked_target_position = player.global_position
	early_enemy.state_time_left = 0.35
	_check(early_enemy.get_attack_eta_for(player, 0.7) < 0.0, "attack forecast rejects an impact outside the 0.7-second window")
	player._handle_defend_press(true)
	_check(player.is_defending, "pressing Z too early enters ordinary defense")
	_check(not early_enemy.current_attack_parried, "early defense press does not parry an invalid attack")
	_check(not time_controller.is_enemy_side_paused(), "early defense press does not pause enemies")
	player._handle_defend_press(false)
	player.is_defending = false

	var parry_enemy := _spawn_slime(night_scene, player.global_position + Vector2(0.0, -25.0))
	parry_enemy.state = parry_enemy.SlimeState.WINDUP
	parry_enemy.current_attack_id = 810011
	parry_enemy.locked_target_position = player.global_position
	parry_enemy.state_time_left = 0.35
	var eta: float = parry_enemy.get_attack_eta_for(player, 0.7)
	_check(eta >= 0.0 and eta <= 0.7, "nearby valid lunge has an imminent hit forecast")
	var enemy_projectile: Area2D = load("res://scenes/combat/yarn_projectile.tscn").instantiate()
	night_scene.add_child(enemy_projectile)
	enemy_projectile.global_position = Vector2(300.0, 300.0)
	enemy_projectile.setup(Vector2.RIGHT, parry_enemy, 1, 220.0, 220.0)
	var projectile_position_before: Vector2 = enemy_projectile.global_position
	var recover_time_before: float = parry_enemy.recover_duration
	player._handle_defend_press(true)
	_check(parry_enemy.current_attack_parried, "new Z press within the hit window parries that attack instance")
	_check(parry_enemy.state == parry_enemy.SlimeState.RECOVER, "perfect guard cancels the approaching lunge")
	_check(time_controller.is_enemy_side_paused(), "perfect guard pauses the enemy side")
	_check(parry_enemy.combat_paused, "all slime AI receives the combat pause")
	_check(enemy_projectile.combat_paused, "enemy projectiles pause without Engine.time_scale")
	_check(is_equal_approx(Engine.time_scale, 1.0), "perfect guard leaves global time scale unchanged")
	var paused_state_time: float = parry_enemy.state_time_left
	parry_enemy._physics_process(0.2)
	enemy_projectile._physics_process(0.2)
	_check(is_equal_approx(parry_enemy.state_time_left, paused_state_time), "enemy attack timers freeze during the pause")
	_check(enemy_projectile.global_position == projectile_position_before, "enemy projectile movement freezes during the pause")
	_check(recover_time_before > 0.0, "parried attack retains a valid recovery state")
	_check(not player.is_defending, "perfect guard does not lock the cat out of actions")
	var player_position_before: Vector2 = player.global_position
	Input.action_press("move_right")
	player._physics_process(1.0 / 60.0)
	Input.action_release("move_right")
	_check(player.global_position.x > player_position_before.x, "cat can still move during the enemy pause")
	var pause_left_before: float = time_controller.enemy_pause_time_left
	player._handle_defend_press(true)
	_check(is_equal_approx(time_controller.enemy_pause_time_left, pause_left_before), "held/repeated Z cannot refresh or retrigger pause")
	time_controller._process(0.5)
	_check(time_controller.is_enemy_side_paused(), "enemy pause remains active for its configured second")
	time_controller._process(0.6)
	_check(not time_controller.is_enemy_side_paused(), "enemy pause expires and releases all actors")
	_check(not parry_enemy.combat_paused, "slime AI resumes after the pause")
	_check(not enemy_projectile.combat_paused, "enemy projectile resumes after the pause")
	_check(is_equal_approx(Engine.time_scale, 1.0), "global time scale remains unchanged after recovery")

	time_controller.set_process(true)
	player.die()
	_check(not time_controller.is_enemy_side_paused(), "player death leaves no stale enemy pause state")
	for slime in [early_enemy, parry_enemy]:
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
		print("COMBAT_V3_PHASE_D_PASSED")
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


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		failures.append(description)


