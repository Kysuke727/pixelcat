extends SceneTree

# Backstab: attacking an enemy that faces away has a CHANCE to crit.

var failures: Array[String] = []
var checks: int = 0
var cat
var combat
var slime


func _initialize() -> void:
	call_deferred("_run")


func _place(cat_offset: Vector2, slime_facing: Vector2) -> void:
	slime.global_position = Vector2(600.0, 350.0)
	slime.facing = slime_facing
	cat.global_position = slime.global_position + cat_offset


## One melee swing at the slime; returns the damage it took.
func _swing() -> float:
	slime.current_health = 60.0
	slime.max_health = 60
	slime.stun_time_left = 0.0
	slime.stun_immunity_left = 0.0
	slime._change_state(slime.SlimeState.IDLE)
	combat.cancel_action()
	combat.action_state = combat.ActionState.IDLE
	combat.melee_cooldown_left = 0.0
	combat._start_melee(false)
	combat.hit_targets.clear()
	combat._try_damage_target(slime)
	return 60.0 - slime.current_health


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
	var hit_feel = root.get_node("HitFeel")

	# --- Defaults ----------------------------------------------------------------------
	var tuning = root.get_node("CombatBalance").tuning
	_check(is_equal_approx(tuning.backstab_crit_chance, 0.5), "default backstab crit chance is 50%")
	_check(is_equal_approx(tuning.crit_damage_multiplier, 2.0), "default crit damage is x2")
	_check(combat.backstab_crit_chance == 0.0, "tests run with crits off unless a test turns them on")

	# --- What counts as behind -----------------------------------------------------------
	_place(Vector2(0.0, -40.0), Vector2.DOWN)
	_check(combat._is_behind(slime), "cat directly behind a slime that faces down")
	_place(Vector2(0.0, 40.0), Vector2.DOWN)
	_check(not combat._is_behind(slime), "cat in front of it: not behind")
	_place(Vector2(40.0, 0.0), Vector2.DOWN)
	_check(not combat._is_behind(slime), "cat at its side: not behind")
	_place(Vector2(-30.0, -30.0), Vector2.DOWN)
	_check(combat._is_behind(slime), "behind-and-aside at 135 degrees counts as behind")
	_place(Vector2(-40.0, -8.0), Vector2.DOWN)
	_check(not combat._is_behind(slime), "almost directly beside it does not")
	_place(Vector2(-40.0, 0.0), Vector2.RIGHT)
	_check(combat._is_behind(slime), "works for every facing (slime faces right, cat on its left)")
	_place(Vector2(40.0, 0.0), Vector2.LEFT)
	_check(combat._is_behind(slime), "slime faces left, cat on its right")
	_place(Vector2(0.0, 40.0), Vector2.UP)
	_check(combat._is_behind(slime), "slime faces up, cat below")
	slime.facing = Vector2.ZERO
	_check(not combat._is_behind(slime), "no facing means no backstab")
	_check(not combat._is_behind(cat), "a target without a facing is never backstabbed")

	# --- Chance ------------------------------------------------------------------------------
	_place(Vector2(0.0, -30.0), Vector2.DOWN)
	combat.backstab_crit_chance = 0.0
	var normal := _swing()
	_check(is_equal_approx(normal, 1.0), "a plain first claw deals 1 damage (got %.1f)" % normal)
	combat.backstab_crit_chance = 1.0
	_check(is_equal_approx(_swing(), 2.0), "chance 100%: a backstab doubles the damage")
	_place(Vector2(0.0, 30.0), Vector2.DOWN)
	_check(is_equal_approx(_swing(), 1.0), "from the front there is never a crit, even at 100%")
	_place(Vector2(30.0, 0.0), Vector2.DOWN)
	_check(is_equal_approx(_swing(), 1.0), "from the side there is never a crit either")
	_place(Vector2(0.0, -30.0), Vector2.DOWN)
	combat.backstab_crit_chance = 0.0
	var crits := 0
	for _i in range(40):
		if _swing() > 1.5:
			crits += 1
	_check(crits == 0, "chance 0: a backstab never crits")

	combat.crit_rng.seed = 20261117
	combat.backstab_crit_chance = 0.5
	var trials := 800
	crits = 0
	for _i in range(trials):
		if _swing() > 1.5:
			crits += 1
	var rate := float(crits) / float(trials)
	_check(rate > 0.45 and rate < 0.55, "a 50%% chance crits about half the time (%.1f%%)" % (rate * 100.0))
	_check(rate < 1.0, "it is not guaranteed")

	# --- Other attacks and multipliers -----------------------------------------------------------
	combat.backstab_crit_chance = 1.0
	_place(Vector2(0.0, -30.0), Vector2.DOWN)
	slime.current_health = 60.0
	combat.cancel_action()
	combat.action_state = combat.ActionState.IDLE
	combat.melee_cooldown_left = 0.0
	combat._start_melee(false)
	combat._try_damage_target(slime)
	combat._finish_action()
	combat._start_melee(true)
	slime.stun_immunity_left = 0.0
	combat._try_damage_target(slime)
	_check(is_equal_approx(60.0 - slime.current_health, 2.0 + 4.0), "both claws of a combo can crit (1x2 + 2x2 = 6, got %.1f)" % (60.0 - slime.current_health))
	var pm_ref = root.get_node("ProgressionManager")
	pm_ref.attributes["attack"] = 4   # +20% attack
	var boosted := _swing()
	_check(is_equal_approx(boosted, 1.0 * 1.2 * 2.0), "the crit multiplies the already-boosted damage (got %.2f)" % boosted)
	pm_ref.attributes["attack"] = 0
	combat.crit_damage_multiplier = 3.0
	_check(is_equal_approx(_swing(), 3.0), "the multiplier is tunable")
	combat.crit_damage_multiplier = 2.0

	# --- Feedback ------------------------------------------------------------------------------------
	_swing()
	var after := _label_texts(night)
	var crit_label := ""
	for text in after:
		if text.begins_with("暴击"):
			crit_label = text
	_check(crit_label == "暴击 2", "a crit shows a floating '暴击 2' (got '%s')" % crit_label)
	_check(combat.combo_feedback_text == "绕背暴击！" and combat.combo_hit_feedback_left > 0.0, "the HUD message announces the backstab crit")
	var hud = get_first_node_in_group("battle_ui")
	hud._update_combat_readout()
	_check(hud.combat_feedback.text == "绕背暴击！", "the combat HUD shows it")
	combat.backstab_crit_chance = 0.0
	combat.combo_hit_feedback_left = 0.0
	var crit_labels_before := _count_crit_labels(night)
	_swing()
	_check(_count_crit_labels(night) == crit_labels_before, "a normal hit adds no crit text")
	_check(combat.combo_hit_feedback_left == 0.0, "...and no crit message")

	# --- A crit can kill, the fight goes on ---------------------------------------------------------------
	combat.backstab_crit_chance = 1.0
	_place(Vector2(0.0, -30.0), Vector2.DOWN)
	slime.max_health = 5
	slime.current_health = 2.0
	slime.stun_immunity_left = 0.0
	slime._change_state(slime.SlimeState.IDLE)
	combat.action_state = combat.ActionState.IDLE
	combat._start_melee(false)
	combat.hit_targets.clear()
	combat._try_damage_target(slime)
	_check(slime.current_health == 0.0 and not slime.is_alive(), "a backstab crit can finish an enemy off")

	if failures.is_empty():
		print("BACKSTAB_CRIT_PASSED: %d checks" % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		quit(1)


func _count_crit_labels(node: Node) -> int:
	var count := 0
	for text in _label_texts(node):
		if str(text).begins_with("暴击"):
			count += 1
	return count


func _label_texts(node: Node) -> Array:
	var texts: Array = []
	for child in node.get_children():
		if child is Label:
			texts.append(child.text)
	return texts


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", description)
	else:
		failures.append(description)
