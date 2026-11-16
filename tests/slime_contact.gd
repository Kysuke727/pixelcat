extends SceneTree

# Touching a slime: a CHANCE to slip or get stuck (never 100%).

var failures: Array[String] = []
var checks: int = 0
var cat
var combat
var slime


func _initialize() -> void:
	call_deferred("_run")


## Put the slime right against the cat and run one slide so a real collision is recorded.
func _touch() -> void:
	cat.velocity = Vector2.RIGHT * 200.0
	cat.move_and_slide()


# The cat is a rectangle and the slime a circle: they only collide when closer than about
# 24 px, and a moved body needs one physics frame before collisions see it.
const TOUCH_GAP := 22.0


func _reset_cat() -> void:
	cat.global_position = Vector2(500.0, 350.0)
	cat.velocity = Vector2.ZERO
	cat.slip_time_left = 0.0
	cat.stick_time_left = 0.0
	cat.contact_immunity_left = 0.0
	cat.contact_roll_left = 0.0
	cat.dodge_iframes_left = 0.0
	cat.hitstun_left = 0.0
	cat.guard_break_left = 0.0
	cat.dead = false
	cat.animated_sprite.modulate = Color.WHITE
	slime.global_position = Vector2(500.0 + TOUCH_GAP, 350.0)
	slime.stun_time_left = 0.0
	slime.bind_time_left = 0.0
	slime._change_state(slime.SlimeState.IDLE)
	await physics_frame


func _trigger(chance: float, slip_share: float) -> void:
	await _reset_cat()
	cat.slime_contact_chance = chance
	cat.slip_share = slip_share
	_touch()
	cat._check_slime_contact()


func _run() -> void:
	var pm = root.get_node("ProgressionManager")
	pm._test_mode = true
	var night: Node = load("res://scenes/worlds/night_world.tscn").instantiate()
	root.add_child(night)
	current_scene = night
	await physics_frame
	cat = get_first_node_in_group("player")
	combat = cat.get_node("PlayerCombat")
	cat.set_physics_process(false)
	cat.set_process(false)
	combat.set_process(false)
	var enemies := get_nodes_in_group("enemies")
	for enemy in enemies:
		enemy.set_physics_process(false)
		enemy.global_position = Vector2(950.0, 120.0)
	slime = enemies[0]
	await physics_frame

	# --- Defaults ------------------------------------------------------------------
	var tuning = root.get_node("CombatBalance").tuning
	_check(is_equal_approx(tuning.slime_contact_chance, 0.35), "default chance is 35% (not 100%)")
	_check(tuning.slime_contact_chance < 1.0 and tuning.slime_contact_chance > 0.0, "the chance is strictly between 0 and 1")
	_check(cat.slime_contact_chance == 0.0, "tests run with the effect off unless a test turns it on")

	# --- Chance 0 never triggers ------------------------------------------------------
	var fired := 0
	for _i in range(60):
		await _trigger(0.0, 0.5)
		if cat.slip_time_left > 0.0 or cat.stick_time_left > 0.0:
			fired += 1
	_check(fired == 0, "chance 0: nothing ever happens")

	# --- Chance 1: slip -------------------------------------------------------------------
	var slip_events: Array = []
	cat.slipped.connect(func(source: Node): slip_events.append(source))
	await _trigger(1.0, 1.0)
	_check(cat.slip_time_left > 0.0 and is_equal_approx(cat.slip_time_left, cat.slip_duration), "a slip starts")
	_check(slip_events.size() == 1 and slip_events[0] == slime, "slipped is emitted with the slime")
	_check(cat.stick_time_left == 0.0, "a slip is not also a stick")
	_check(not cat.can_perform_combat_action(), "no attacking while slipping")
	_check(cat.slip_velocity.length() > 0.0 and is_equal_approx(cat.slip_velocity.length(), cat.slip_speed), "the slide has the configured speed")
	_check(cat.contact_immunity_left > 0.0, "slipping grants immunity")
	var before: Vector2 = cat.global_position
	cat.slime_contact_chance = 0.0
	slime.global_position = Vector2(950.0, 120.0)
	cat.set_physics_process(true)
	for _i in range(5):
		cat._physics_process(1.0 / 60.0)
	_check(cat.global_position.distance_to(before) > 1.0, "the cat slides while slipping")
	var early_speed: float = cat.velocity.length()
	for _i in range(20):
		cat._physics_process(1.0 / 60.0)
	_check(cat.velocity.length() < early_speed, "the slide fades out")
	for _i in range(20):
		cat._physics_process(1.0 / 60.0)
	_check(cat.slip_time_left == 0.0 and cat.can_perform_combat_action(), "after the slip the cat has control again")

	# --- Chance 1: stick --------------------------------------------------------------------
	var stuck_events: Array = []
	cat.got_stuck.connect(func(source: Node): stuck_events.append(source))
	cat.set_physics_process(false)
	await _trigger(1.0, 0.0)
	_check(cat.stick_time_left > 0.0 and cat.slip_time_left == 0.0, "a stick starts (not a slip)")
	_check(stuck_events.size() == 1, "got_stuck is emitted")
	_check(cat.can_perform_combat_action(), "while stuck the cat can still attack")
	_check(not cat._try_start_dash(Vector2.RIGHT), "...but cannot dash")
	cat.dodge_cooldown_left = 0.0
	_check(not cat._try_start_dodge(Vector2.RIGHT), "...and cannot dodge")
	_check(cat.animated_sprite.modulate.g > cat.animated_sprite.modulate.r, "the cat is tinted green while stuck")
	slime.global_position = Vector2(950.0, 120.0)
	cat.slime_contact_chance = 0.0
	await physics_frame
	Input.action_press("move_right")
	cat.set_physics_process(true)
	cat._physics_process(1.0 / 60.0)
	var stuck_speed: float = cat.velocity.x
	Input.action_release("move_right")
	cat.stick_time_left = 0.0
	Input.action_press("move_right")
	cat._physics_process(1.0 / 60.0)
	var free_speed: float = cat.velocity.x
	Input.action_release("move_right")
	cat.set_physics_process(false)
	_check(free_speed > 0.0 and absf(stuck_speed / free_speed - cat.stick_speed_multiplier) < 0.01, "being stuck slows movement to %d%% (%.0f vs %.0f)" % [int(cat.stick_speed_multiplier * 100.0), stuck_speed, free_speed])
	await _trigger(1.0, 0.0)
	cat.slime_contact_chance = 0.0
	slime.global_position = Vector2(950.0, 120.0)
	cat.set_physics_process(true)
	for _i in range(int(cat.stick_duration * 60.0) + 3):
		cat._physics_process(1.0 / 60.0)
	cat.set_physics_process(false)
	_check(cat.stick_time_left == 0.0 and _is_white(cat.animated_sprite.modulate), "the stick wears off and the tint clears")
	cat.dodge_cooldown_left = 0.0
	cat.dash_charges = 2
	_check(cat._try_start_dash(Vector2.RIGHT), "dashing works again afterwards")

	# --- Immunity and roll interval -----------------------------------------------------------
	await _trigger(1.0, 1.0)
	_check(cat.contact_immunity_left > 0.0, "immunity after an effect")
	cat.slip_time_left = 0.0
	cat.contact_roll_left = 0.0
	slime.global_position = Vector2(500.0 + TOUCH_GAP, 350.0)
	cat.global_position = Vector2(500.0, 350.0)
	await physics_frame
	_touch()
	cat.slime_contact_chance = 1.0
	cat._check_slime_contact()
	_check(cat.slip_time_left == 0.0 and cat.stick_time_left == 0.0, "immune cats cannot be affected again straight away")
	cat.contact_immunity_left = 0.0
	cat._check_slime_contact()
	_check(cat.slip_time_left > 0.0 or cat.stick_time_left > 0.0, "once the immunity is over, contact can trigger again")
	_check(cat.contact_immunity_duration >= 1.0, "the immunity lasts at least a second (no chain-locking)")

	await _reset_cat()
	cat.slime_contact_chance = 0.0
	_touch()
	cat._check_slime_contact()
	_check(cat.contact_roll_left > 0.0, "a failed roll still uses up the roll interval")
	cat.slime_contact_chance = 1.0
	cat._check_slime_contact()
	_check(cat.slip_time_left == 0.0 and cat.stick_time_left == 0.0, "no second roll within the interval")
	cat.contact_roll_left = 0.0
	cat._check_slime_contact()
	_check(cat.slip_time_left > 0.0 or cat.stick_time_left > 0.0, "after the interval the next roll happens")

	# --- Which slimes count --------------------------------------------------------------------
	for case in [["stunned", slime.SlimeState.STUNNED], ["dead", slime.SlimeState.DEAD]]:
		await _reset_cat()
		cat.slime_contact_chance = 1.0
		slime._change_state(case[1])
		_touch()
		cat._check_slime_contact()
		_check(cat.slip_time_left == 0.0 and cat.stick_time_left == 0.0, "a %s slime is harmless" % case[0])
	await _reset_cat()
	cat.slime_contact_chance = 1.0
	slime.bind_time_left = 1.0
	_touch()
	cat._check_slime_contact()
	_check(cat.slip_time_left == 0.0 and cat.stick_time_left == 0.0, "a yarn-bound slime is harmless")
	slime.bind_time_left = 0.0
	slime._change_state(slime.SlimeState.IDLE)

	# --- Protected moments ----------------------------------------------------------------------
	await _reset_cat()
	cat.slime_contact_chance = 1.0
	cat.dodge_iframes_left = 0.1
	_touch()
	cat._check_slime_contact()
	_check(cat.slip_time_left == 0.0 and cat.stick_time_left == 0.0, "a dodging cat slips past slimes without effect")
	await _reset_cat()
	cat.slime_contact_chance = 1.0
	cat.hitstun_left = 0.2
	_touch()
	cat._check_slime_contact()
	_check(cat.slip_time_left == 0.0 and cat.stick_time_left == 0.0, "no effect while already in hitstun")
	await _reset_cat()
	cat.slime_contact_chance = 1.0
	cat.dead = true
	_touch()
	cat._check_slime_contact()
	_check(cat.slip_time_left == 0.0 and cat.stick_time_left == 0.0, "a dead cat is not affected")
	cat.dead = false

	# --- Dash / pounce are interrupted --------------------------------------------------------------
	await _reset_cat()
	cat.slime_contact_chance = 1.0
	cat.dash_charges = 2
	cat._try_start_dash(Vector2.RIGHT)
	_check(cat.is_dashing(), "dash running")
	_touch()
	cat._check_slime_contact()
	_check(not cat.is_dashing(), "a slime effect stops a dash in progress")

	# --- Real physics frames ---------------------------------------------------------------------------
	await _reset_cat()
	cat.slime_contact_chance = 1.0
	cat.slip_share = 0.5
	slime.global_position = Vector2(545.0, 350.0)
	await physics_frame
	cat.set_physics_process(true)
	Input.action_press("move_right")
	var triggered := false
	for _i in range(90):
		await physics_frame
		if cat.slip_time_left > 0.0 or cat.stick_time_left > 0.0:
			triggered = true
			break
	Input.action_release("move_right")
	_check(triggered, "walking into a slime for real triggers the effect (chance 100%% in this test)")
	cat.set_physics_process(false)

	# --- HUD ------------------------------------------------------------------------------------------------
	var hud = get_first_node_in_group("battle_ui")
	await _reset_cat()
	cat.slip_time_left = 0.3
	hud._update_combat_readout()
	_check(hud.combat_feedback.text.contains("滑倒"), "HUD says the cat slipped")
	cat.slip_time_left = 0.0
	cat.stick_time_left = 0.5
	hud._update_combat_readout()
	_check(hud.combat_feedback.text.contains("黏住"), "HUD says the cat is stuck")
	cat.stick_time_left = 0.0

	# --- Probability --------------------------------------------------------------------------------------------
	cat.contact_rng.seed = 20261117
	var hits := 0
	var slips := 0
	var trials := 800
	for _i in range(trials):
		await _reset_cat()
		cat.slime_contact_chance = 0.35
		cat.slip_share = 0.5
		_touch()
		cat._check_slime_contact()
		if cat.slip_time_left > 0.0 or cat.stick_time_left > 0.0:
			hits += 1
			if cat.slip_time_left > 0.0:
				slips += 1
	var rate := float(hits) / float(trials)
	_check(rate > 0.30 and rate < 0.40, "a 35%% chance triggers about 35%% of the time (%.1f%%)" % (rate * 100.0))
	var slip_rate := float(slips) / float(maxi(hits, 1))
	_check(slip_rate > 0.42 and slip_rate < 0.58, "slips and sticks split about 50/50 (%.0f%% slips)" % (slip_rate * 100.0))

	# --- Revive resets everything ---------------------------------------------------------------------------------
	cat.slip_time_left = 0.5
	cat.stick_time_left = 0.5
	cat.contact_immunity_left = 1.0
	cat.revive_from_expedition(Vector2(500.0, 350.0))
	_check(cat.slip_time_left == 0.0 and cat.stick_time_left == 0.0 and cat.contact_immunity_left == 0.0, "reviving clears slip, stick and immunity")

	if failures.is_empty():
		print("SLIME_CONTACT_PASSED: %d checks" % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		quit(1)


func _is_white(color: Color) -> bool:
	return color.is_equal_approx(Color.WHITE)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", description)
	else:
		failures.append(description)
