extends SceneTree

# End-to-end through the real input path (Input actions -> _process -> buffering ->
# next swing), with real elapsed time. Uses generous timing windows.

var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


# Real key events arrive at the start of a frame. Calling action_press after a timer
# (which fires after this frame's _process calls) would make the press miss
# is_action_just_pressed, so always sync to a frame start first.
func _press(action: String) -> void:
	await process_frame
	Input.action_press(action)
	await process_frame
	await process_frame
	Input.action_release(action)


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _run() -> void:
	var pm = root.get_node("ProgressionManager")
	var night: Node = load("res://scenes/worlds/night_world.tscn").instantiate()
	root.add_child(night)
	current_scene = night
	await process_frame
	await process_frame
	var player: Node2D = get_first_node_in_group("player")
	var combat = player.get_node("PlayerCombat")
	var enemies := get_nodes_in_group("enemies")
	for enemy in enemies:
		enemy.set_physics_process(false)
		enemy.global_position = Vector2(950.0, 120.0)
	var slime: Node2D = enemies[0]
	slime.max_health = 80
	slime.current_health = 80
	player.global_position = Vector2(500.0, 350.0)
	player.last_facing = Vector2.RIGHT

	# --- Triple combo with real input ---------------------------------------------
	pm.unlock_move("triple_combo")
	slime.global_position = Vector2(525.0, 350.0)
	var seen: Array[int] = []
	await _press("melee_attack")
	var started := Time.get_ticks_msec()
	var pressed_second := false
	var pressed_third := false
	while Time.get_ticks_msec() - started < 1800:
		if seen.is_empty() or seen.back() != combat.action_state:
			seen.append(combat.action_state)
		var elapsed := Time.get_ticks_msec() - started
		# Keep the target planted in front of the cat so every swing connects.
		slime.global_position = Vector2(525.0, 350.0)
		slime.velocity = Vector2.ZERO
		# Press again while the previous swing is active (after its hit): input buffering.
		if not pressed_second and combat.action_state == combat.ActionState.ATTACK1 and combat.action_time > 0.17:
			pressed_second = true
			await _press("melee_attack")
		if not pressed_third and combat.action_state == combat.ActionState.ATTACK2 and combat.action_time > 0.17:
			pressed_third = true
			await _press("melee_attack")
		await process_frame
		if combat.action_state == combat.ActionState.ATTACK3 and combat.action_time > 0.2:
			break
	var names := {}
	for state in seen:
		names[state] = true
	_check(names.has(combat.ActionState.ATTACK1), "real input: first claw happened")
	_check(names.has(combat.ActionState.ATTACK2), "real input: buffered press chained into the second claw")
	_check(names.has(combat.ActionState.ATTACK3), "real input: buffered press chained into the third claw")
	_check(slime.current_health <= 80.0 - 6.0, "real input: the three claws dealt 1 + 2 + 3 damage (hp left %.0f)" % slime.current_health)
	# Wait for everything to settle.
	await _wait(1.2)
	_check(combat.action_state == combat.ActionState.IDLE or combat.action_state == combat.ActionState.RECOVERY, "real input: combat settles after the chain")

	# --- Without the move, J J J stays a two-hit combo ----------------------------------
	pm._load_profile_data({})
	slime.current_health = 80
	slime.stun_immunity_left = 0.0
	slime._change_state(slime.SlimeState.IDLE)
	await _wait(0.8)
	seen.clear()
	await _press("melee_attack")
	started = Time.get_ticks_msec()
	pressed_second = false
	pressed_third = false
	while Time.get_ticks_msec() - started < 1400:
		if seen.is_empty() or seen.back() != combat.action_state:
			seen.append(combat.action_state)
		slime.global_position = Vector2(525.0, 350.0)
		slime.velocity = Vector2.ZERO
		if not pressed_second and combat.action_state == combat.ActionState.ATTACK1 and combat.action_time > 0.17:
			pressed_second = true
			await _press("melee_attack")
		if not pressed_third and combat.action_state == combat.ActionState.ATTACK2 and combat.action_time > 0.17:
			pressed_third = true
			await _press("melee_attack")
		await process_frame
	_check(not seen.has(combat.ActionState.ATTACK3), "locked: no third claw even with perfect input")
	await _wait(1.2)

	# --- Pounce with real input ---------------------------------------------------------------
	pm.unlock_move("pounce")
	# A) Distance: nothing in the way (a slime's body would block the cat).
	slime.global_position = Vector2(950.0, 120.0)
	await _wait(0.8)
	player.global_position = Vector2(300.0, 350.0)
	player.last_facing = Vector2.RIGHT
	player.dash_charges = 2
	Input.action_press("move_right")
	await _press("dash")
	await _wait(0.05)
	Input.action_release("move_right")
	_check(player.can_pounce() or player.is_dashing(), "real input: space started a dash (pounce window open)")
	# Let the dash finish so only the pounce's own travel is measured (pouncing mid-dash
	# would cancel whatever distance of the dash was left).
	var guard := 0
	while player.is_dashing() and guard < 120:
		await process_frame
		guard += 1
	_check(player.can_pounce(), "real input: the pounce window outlives the dash")
	var start_x: float = player.global_position.x
	await _press("melee_attack")
	_check(combat.action_state == combat.ActionState.POUNCE, "real input: J right after the dash pounces")
	await _wait(0.5)
	var travelled: float = player.global_position.x - start_x
	_check(travelled >= 70.0 and travelled <= 90.0, "real input: the pounce carried the cat about 80 px (%.0f px)" % travelled)
	await _wait(0.9)

	# B) Hit: a slime right in front takes the pounce.
	slime.current_health = 80
	slime.stun_immunity_left = 0.0
	slime.stun_time_left = 0.0
	slime._change_state(slime.SlimeState.IDLE)
	player.global_position = Vector2(400.0, 350.0)
	player.last_facing = Vector2.RIGHT
	player.dash_charges = 2
	slime.global_position = Vector2(470.0, 350.0)
	Input.action_press("move_right")
	await _press("dash")
	await _wait(0.05)
	Input.action_release("move_right")
	var hp_before: float = slime.current_health
	await _press("melee_attack")
	await _wait(0.5)
	_check(hp_before - slime.current_health >= 3.0, "real input: the pounce hit for 3 damage")
	_check(slime.state == slime.SlimeState.STUNNED or slime.stun_immunity_left > 0.0, "real input: the pounce stunned the slime")

	if failures.is_empty():
		print("COMBO_REAL_INPUT_PASSED: %d checks" % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", description)
	else:
		failures.append(description)
