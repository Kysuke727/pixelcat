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
	var slime: CharacterBody2D = load("res://scenes/enemies/slime.tscn").instantiate()
	night_scene.add_child(slime)
	slime.global_position = Vector2(300.0, 350.0)
	slime.set_physics_process(false)

	slime.apply_yarn_slow(3.0, 0.5)
	slime.apply_yarn_bind(2.0)
	slime._physics_process(0.5)
	var status: Dictionary = slime.get_control_status()
	_check(status["slowed"] and status["bound"], "slow and bind remain independent simultaneous effects")
	_check(not status["can_attack"], "a bound slime cannot initiate an attack")
	_check(is_equal_approx(slime.slow_time_left, 2.5), "slow timer advances independently while bound")
	_check(is_equal_approx(slime.bind_time_left, 1.5), "bind timer advances independently from slow")

	slime.bind_time_left = 1.0
	slime.state = slime.SlimeState.CHASE
	var health_before: int = slime.current_health
	slime.receive_damage(1, Vector2(250.0, 350.0), 100.0)
	_check(slime.state == slime.SlimeState.HURT, "damage creates knockback while an existing bind remains active")
	_check(slime.get_control_status()["knocked_back"], "knockback is represented independently from the bind")
	var position_before: Vector2 = slime.global_position
	slime._physics_process(0.1)
	_check(slime.global_position.x > position_before.x, "bind does not suppress a higher-priority hit reaction")
	_check(slime.bind_time_left < 1.0, "bind duration continues to elapse during knockback")
	_check(slime.current_health == health_before - 1, "combined status handling does not duplicate damage")

	slime.combat_paused = true
	var slow_before: float = slime.slow_time_left
	var bind_before: float = slime.bind_time_left
	slime._physics_process(0.5)
	_check(is_equal_approx(slime.slow_time_left, slow_before), "enemy time pause preserves remaining slow duration")
	_check(is_equal_approx(slime.bind_time_left, bind_before), "enemy time pause preserves remaining bind duration")
	slime.set_combat_paused(false)

	slime.state = slime.SlimeState.LUNGE
	slime.current_attack_id = 990002
	slime.current_attack_parried = false
	slime.attacked_targets.clear()
	var paused_player_health: float = player.current_health
	slime.set_combat_paused(true)
	slime._on_attack_area_body_entered(player)
	slime._try_lunge_hit(player)
	_check(player.current_health == paused_player_health and slime.attacked_targets.is_empty(), "paused lunge callbacks cannot damage or consume an attack hit")
	slime.set_combat_paused(false)
	await physics_frame
	slime._try_lunge_hit(player)
	var resumed_player_health: float = player.current_health
	slime._try_lunge_hit(player)
	_check(slime.attacked_targets.has(player.get_instance_id()), "resumed lunge can resolve the still-active attack")
	_check(player.current_health == resumed_player_health, "attack id still prevents duplicate lunge damage after resume")

	slime.state = slime.SlimeState.WINDUP
	slime.current_attack_id = 990001
	slime.bind_time_left = 0.0
	slime.bind_resistance_left = 0.0
	slime.apply_yarn_bind(2.0)
	await physics_frame
	_check(slime.state == slime.SlimeState.RECOVER, "binding cancels an active lunge or windup")
	_check(not slime.attack_area.monitoring, "bound attack hitbox is disabled")

	player.guard_break_left = 1.0
	player.is_defending = false
	_check(not player.can_perform_combat_action(), "guard-break stun has priority over ordinary input")
	player.dead = true
	_check(not player.can_perform_combat_action(), "death remains the highest-priority player state")
	_check(not combat._can_start_action(), "combat cannot start after player death")

	if is_instance_valid(night_scene):
		for audio_player in night_scene.find_children("*", "AudioStreamPlayer2D", true, false):
			audio_player.stop()
			audio_player.stream = null
		night_scene.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.25).timeout
	if failures.is_empty():
		print("COMBAT_V3_PHASE_E_PASSED")
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
