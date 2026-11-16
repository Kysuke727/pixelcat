extends SceneTree

# Combat foundation: cat-step dash, perfect dodge, combat camera, hit feedback.

var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var night: Node = load("res://scenes/worlds/night_world.tscn").instantiate()
	root.add_child(night)
	current_scene = night
	await physics_frame
	var player: Node2D = get_first_node_in_group("player")
	var combat = player.get_node("PlayerCombat")
	player.set_physics_process(false)
	player.set_process(false)
	combat.set_process(false)
	for enemy in get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
		enemy.global_position = Vector2(900.0, 600.0)
	var hit_feel = root.get_node("HitFeel")

	# --- Dash ----------------------------------------------------------------
	var has_space := false
	for input_event in InputMap.action_get_events("dash"):
		if input_event is InputEventKey and input_event.physical_keycode == KEY_SPACE:
			has_space = true
	_check(has_space, "dash is bound to the Space key")
	player.global_position = Vector2(500.0, 350.0)
	player.invincibility_left = 0.0
	player.hitstun_left = 0.0
	_check(player.dash_charges == 2 and player.dash_max_charges == 2, "player starts with 2 dash charges")
	_check(player._try_start_dash(Vector2.RIGHT), "first dash starts")
	_check(player.is_dashing() and player.dash_charges == 1, "dash spends a charge and is active")
	_check(player._try_start_dash(Vector2.RIGHT), "second dash is allowed while a charge remains")
	_check(not player._try_start_dash(Vector2.RIGHT), "no dash with 0 charges")
	_check(player.dash_charges == 0, "charges are exhausted")
	var health_before: int = player.current_health
	_check(player.receive_damage(1, player.global_position + Vector2.LEFT), "dash gives NO invulnerability (a hit still lands)")
	_check(player.current_health == health_before - 1, "damage taken while dashing")
	_check(not player.is_counter_window_open(), "being hit while dashing is not a perfect dodge")

	# Recharge: one charge per 1.2 s, one at a time.
	player.hitstun_left = 0.0
	player.dash_time_left = 0.0
	player.invincibility_left = 0.0
	for _i in range(60):
		player._update_dash_recharge(1.0 / 60.0)
	_check(player.dash_charges == 0, "no charge back after 1.0 s")
	for _i in range(15):
		player._update_dash_recharge(1.0 / 60.0)
	_check(player.dash_charges == 1, "one charge back after 1.2 s")
	for _i in range(75):
		player._update_dash_recharge(1.0 / 60.0)
	_check(player.dash_charges == 2, "second charge back after another 1.2 s")
	for _i in range(120):
		player._update_dash_recharge(1.0 / 60.0)
	_check(player.dash_charges == 2, "charges never exceed the maximum")

	# Distance in open space.
	player.global_position = Vector2(300.0, 350.0)
	player.velocity = Vector2.ZERO
	player.dash_time_left = 0.0
	_check(player._try_start_dash(Vector2.RIGHT), "dash for distance test")
	for _i in range(8):
		player._move_during_dash(1.0 / 60.0)
	_check(absf(player.global_position.x - 390.0) <= 2.0, "dash travels about 90 px (got %.1f)" % (player.global_position.x - 300.0))
	_check(not player.is_dashing(), "dash ends after its duration")
	# The distance must not depend on the frame rate. Integrate velocity * delta
	# ourselves (move_and_slide always uses the engine step, so it can't be varied here).
	for hz in [30.0, 60.0, 144.0, 240.0]:
		player.dash_charges = 2
		player.dash_time_left = 0.0
		_check(player._try_start_dash(Vector2.RIGHT), "dash starts for the %d Hz distance check" % int(hz))
		var travelled := 0.0
		var guard := 0
		while player.is_dashing() and guard < 100:
			player._move_during_dash(1.0 / hz)
			travelled += player.velocity.x * (1.0 / hz)
			guard += 1
		_check(absf(travelled - 90.0) <= 0.5, "dash covers 90 px at %d Hz (got %.2f)" % [int(hz), travelled])

	# Blocked states.
	player.dash_charges = 2
	player.hitstun_left = 0.3
	_check(not player._try_start_dash(Vector2.RIGHT), "cannot dash while in hitstun")
	player.hitstun_left = 0.0
	player.is_defending = true
	_check(not player._try_start_dash(Vector2.RIGHT), "cannot dash while defending")
	player.is_defending = false

	# --- Perfect dodge --------------------------------------------------------
	player.dash_time_left = 0.0
	player.invincibility_left = 0.0
	player.hitstun_left = 0.0
	player.current_health = player.max_health
	var perfect_events: Array = []
	player.perfect_dodged.connect(func(position: Vector2): perfect_events.append(position))
	player.dodge_cooldown_left = 0.0
	_check(player._try_start_dodge(Vector2.RIGHT), "dodge starts")
	_check(is_equal_approx(player.dodge_cooldown_left, 15.0), "dodge cooldown is 15 s")
	_check(not player.receive_damage(1, player.global_position + Vector2.LEFT), "hit inside the dodge frames is avoided")
	_check(is_equal_approx(player.dodge_cooldown_left, 0.0), "perfect dodge refunds the cooldown")
	_check(player.is_counter_window_open(), "perfect dodge opens a counter window")
	_check(perfect_events.size() == 1, "perfect_dodged signal fired once")
	_check(not player.receive_damage(1, player.global_position + Vector2.LEFT), "second hit in the same dodge is still avoided")
	_check(perfect_events.size() == 1, "a single dodge can only be 'perfect' once")
	_check(player.current_health == player.max_health, "no damage from perfect-dodged hits")

	# Ordinary hit-invulnerability (no dodge) must NOT count as a perfect dodge.
	player.dodge_iframes_left = 0.0
	player.dodge_time_left = 0.0
	player.dodge_cooldown_left = 9.0
	player.counter_window_left = 0.0
	player.invincibility_left = 1.0
	_check(not player.receive_damage(1, player.global_position + Vector2.LEFT), "hit-invulnerability still blocks damage")
	_check(is_equal_approx(player.dodge_cooldown_left, 9.0), "hit-invulnerability does not refund the dodge cooldown")
	_check(perfect_events.size() == 1, "no perfect dodge from ordinary invulnerability")
	player.invincibility_left = 0.0

	# --- Camera ---------------------------------------------------------------
	var camera: Camera2D = get_first_node_in_group("combat_camera")
	_check(camera != null and camera.is_current(), "night world has an active combat camera")
	_check(root.get_canvas_transform().origin == Vector2.ZERO, "camera leaves the view identical to having none")
	camera.add_trauma(0.8)
	var moved := false
	for _i in range(5):
		camera._process(1.0 / 60.0)
		if camera.offset != Vector2.ZERO:
			moved = true
	_check(moved, "trauma shakes the camera")
	_check(absf(camera.offset.x) <= camera.max_offset and absf(camera.offset.y) <= camera.max_offset, "shake stays within max_offset")
	_check(camera.offset == camera.offset.round(), "shake offsets are whole pixels")
	for _i in range(120):
		camera._process(1.0 / 60.0)
	_check(camera.trauma == 0.0 and camera.offset == Vector2.ZERO, "shake decays back to a still camera")
	camera.add_trauma(5.0)
	_check(camera.trauma <= 1.0, "trauma is clamped to 1")
	camera.trauma = 0.0

	# --- HitFeel --------------------------------------------------------------
	_check(not hit_feel.time_effects_enabled, "time effects default to OFF in test mode")
	hit_feel.time_effects_enabled = true
	hit_feel.hit_stop(0.05)
	_check(Engine.time_scale < 1.0, "hit-stop slows the game")
	await create_timer(0.15, true, false, true).timeout
	_check(is_equal_approx(Engine.time_scale, 1.0), "hit-stop restores normal speed")
	hit_feel.hit_stop_enabled = false
	hit_feel.hit_stop(0.05)
	_check(is_equal_approx(Engine.time_scale, 1.0), "hit-stop can be switched off")
	hit_feel.hit_stop_enabled = true
	hit_feel.slow_motion_enabled = false
	hit_feel.slow_motion(0.05)
	_check(is_equal_approx(Engine.time_scale, 1.0), "slow motion can be switched off")
	hit_feel.slow_motion_enabled = true
	hit_feel.time_effects_enabled = false

	var labels_before := _count_labels(night)
	hit_feel.damage_number(Vector2(400.0, 300.0), "7")
	_check(_count_labels(night) == labels_before + 1, "damage_number adds a floating label")
	hit_feel.damage_numbers_enabled = false
	hit_feel.damage_number(Vector2(400.0, 300.0), "8")
	_check(_count_labels(night) == labels_before + 1, "damage numbers can be switched off")
	hit_feel.damage_numbers_enabled = true
	var particles_before := _count_type(night, "CPUParticles2D")
	hit_feel.spark(Vector2(400.0, 300.0))
	_check(_count_type(night, "CPUParticles2D") == particles_before + 1, "spark spawns a particle burst")
	hit_feel.particles_enabled = false
	hit_feel.spark(Vector2(400.0, 300.0))
	_check(_count_type(night, "CPUParticles2D") == particles_before + 1, "particles can be switched off")
	hit_feel.particles_enabled = true
	var sprite_count := _count_type(night, "Sprite2D")
	hit_feel.afterimage(player.get_node("AnimatedSprite2D"))
	_check(_count_type(night, "Sprite2D") == sprite_count + 1, "afterimage adds a fading ghost sprite")

	# Melee hit on a real slime produces feedback with the damage number.
	var slime: Node2D = get_nodes_in_group("enemies")[0]
	slime.global_position = Vector2(520.0, 350.0)
	combat.hit_targets.clear()
	combat.action_state = combat.ActionState.ATTACK1
	var before_hit := _count_labels(night)
	combat._try_damage_target(slime)
	_check(_count_labels(night) == before_hit + 1, "a melee hit pops a damage number")
	_check(_has_label_text(night, "1"), "the damage number shows the dealt damage")

	if failures.is_empty():
		print("COMBAT_FOUNDATION_PASSED: %d checks" % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		quit(1)


func _count_labels(node: Node) -> int:
	return _count_type(node, "Label")


func _count_type(node: Node, type_name: String) -> int:
	var count := 0
	for child in node.get_children():
		if child.get_class() == type_name:
			count += 1
	return count


func _has_label_text(node: Node, text: String) -> bool:
	for child in node.get_children():
		if child is Label and child.text == text:
			return true
	return false


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", description)
	else:
		failures.append(description)
