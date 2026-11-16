extends SceneTree

# Move unlock system + triple combo, pounce, counter claw, combo rewards.

var failures: Array[String] = []
var checks: int = 0
var player: Node2D
var combat: Node
var slime: Node2D
var pm: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	pm = root.get_node("ProgressionManager")
	var night: Node = load("res://scenes/worlds/night_world.tscn").instantiate()
	root.add_child(night)
	current_scene = night
	await physics_frame
	player = get_first_node_in_group("player")
	combat = player.get_node("PlayerCombat")
	player.set_physics_process(false)
	player.set_process(false)
	combat.set_process(false)
	var enemies := get_nodes_in_group("enemies")
	for enemy in enemies:
		enemy.set_physics_process(false)
		enemy.global_position = Vector2(950.0, 120.0)
	slime = enemies[0]
	var banner = root.get_node("MoveBanner")
	var currency = root.get_node("CurrencyManager")
	var day = root.get_node("DayManager")

	# --- Catalog and unlock API -------------------------------------------------
	_check(MoveCatalog.ids().size() == 3, "three learnable moves are defined")
	for id in MoveCatalog.ids():
		_check(MoveCatalog.display_name(id) != id and MoveCatalog.hint(id) != "", "move %s has a name and hint" % id)
	_check(pm.unlocked_moves.is_empty(), "no moves are learned at the start")
	var unlock_events: Array = []
	pm.move_unlocked.connect(func(id: String): unlock_events.append(id))
	_check(not pm.unlock_move("no_such_move"), "unknown move ids cannot be learned")
	_check(pm.unlock_move("pounce"), "a move can be learned")
	_check(pm.has_move("pounce") and not pm.has_move("triple_combo"), "has_move reflects what was learned")
	_check(not pm.unlock_move("pounce"), "learning a move twice does nothing")
	_check(unlock_events == ["pounce"], "move_unlocked fired exactly once")
	_check(banner.is_showing(), "learning a move shows the banner")

	# Save / load
	var saved: Dictionary = pm._profile_data()
	_check(saved.get("unlocked_moves", []) == ["pounce"], "learned moves are written to the save")
	pm._load_profile_data({})
	_check(pm.unlocked_moves.is_empty(), "a new game / empty profile has no moves")
	pm._load_profile_data(saved)
	_check(pm.has_move("pounce"), "learned moves are restored from the save")
	var old_save := saved.duplicate(true)
	old_save.erase("unlocked_moves")
	pm._load_profile_data(old_save)
	_check(pm.unlocked_moves.is_empty(), "an older save without the field loads fine")
	pm._load_profile_data({"unlocked_moves": ["pounce", "pounce", "from_the_future", "triple_combo"]})
	_check(pm.unlocked_moves == ["pounce", "triple_combo"], "unknown and duplicate ids are dropped on load")
	_check(pm._is_valid_profile_fields({"unlocked_moves": ["pounce"]}, false), "a valid move list passes validation")
	_check(not pm._is_valid_profile_fields({"unlocked_moves": "pounce"}, false), "a non-array move list is rejected")
	_check(not pm._is_valid_profile_fields({"unlocked_moves": [1, 2]}, false), "non-string move ids are rejected")
	pm._load_profile_data({})

	# --- Triple combo ------------------------------------------------------------
	_reset_player()
	_check(not combat._can_chain_from(combat.ActionState.ATTACK2), "locked: the second claw is the end of the chain")
	_fresh_slime()
	combat._start_melee(false)
	combat._try_damage_target(slime)
	_check(combat.combo_window_open and combat.combo_next_step == 2, "first claw opens the window for the second")
	combat._finish_action()
	combat._start_melee(true)
	_check(combat.action_state == combat.ActionState.ATTACK2, "second claw follows")
	combat._try_damage_target(slime)
	_check(not combat.combo_window_open, "locked: the second claw does NOT open a third-claw window")

	pm.unlock_move("triple_combo")
	_reset_player()
	_fresh_slime()
	var hp0: float = slime.current_health
	combat._start_melee(false)
	combat._try_damage_target(slime)
	combat._finish_action()
	combat._start_melee(true)
	combat._try_damage_target(slime)
	_check(combat.combo_window_open and combat.combo_next_step == 3, "unlocked: the second claw opens the window for a third")
	_check(combat._can_chain_from(combat.ActionState.ATTACK2), "unlocked: the second claw can chain")
	combat._finish_action()
	_check(combat.action_state == combat.ActionState.RECOVERY and combat.combo_window_open, "window stays open during recovery")
	combat._start_melee(true)
	_check(combat.action_state == combat.ActionState.ATTACK3, "third claw starts")
	_check(is_equal_approx(combat.melee_hitbox.scale.x, 1.5), "third claw has a wider hitbox")
	var before_third: float = slime.current_health
	combat._try_damage_target(slime)
	_check(is_equal_approx(before_third - slime.current_health, 3.0), "third claw deals 3 damage")
	_check(slime.state == slime.SlimeState.STUNNED, "third claw always stuns")
	_check(combat.reward_given_attack_id == combat.current_melee_attack_id, "the finisher pays a reward")
	_check(hp0 - slime.current_health == 6.0, "1 + 2 + 3 damage over the three claws")
	combat._finish_action()
	combat._start_melee(false)
	_check(is_equal_approx(combat.melee_hitbox.scale.x, 1.0), "a new first claw resets the hitbox size")
	_reset_player()

	# --- Pounce -----------------------------------------------------------------------
	pm._load_profile_data({})
	player.dash_charges = 2
	player.dash_time_left = 0.0
	_check(player._try_start_dash(Vector2.RIGHT), "dash starts")
	_check(player.can_pounce(), "a dash opens the pounce window")
	_check(is_equal_approx(player.pounce_window_left, 0.12 + 0.3), "pounce window = dash duration + 0.3 s")
	_check(not combat._try_start_special_move(), "locked: no pounce even right after a dash")
	pm.unlock_move("pounce")
	_check(combat._try_start_special_move(), "unlocked: J after a dash starts the pounce")
	_check(combat.action_state == combat.ActionState.POUNCE and player.is_pouncing(), "pounce is active and moving the cat")
	_check(not player.can_pounce() and player.dash_time_left == 0.0, "the pounce consumes the window and the dash")
	_check(is_equal_approx(combat.melee_hitbox.scale.x, 1.4), "pounce has a bigger hitbox")
	_check(combat.melee_cooldown_left == combat.pounce_recovery, "pounce has a recovery (committed move)")
	_fresh_slime()
	var before_pounce: float = slime.current_health
	combat._try_damage_target(slime)
	_check(is_equal_approx(before_pounce - slime.current_health, 3.0), "pounce deals 3 damage")
	_check(slime.state == slime.SlimeState.STUNNED, "pounce always stuns")
	_check(player.receive_damage(1, player.global_position + Vector2.LEFT), "the pounce has NO invulnerability")
	_check(not player.is_pouncing() and combat.action_state != combat.ActionState.POUNCE, "being hit ends the pounce")
	_reset_player()
	for hz in [30.0, 60.0, 144.0, 240.0]:
		player.dash_charges = 2
		player.dash_time_left = 0.0
		player._try_start_dash(Vector2.RIGHT)
		_check(combat._try_start_special_move(), "pounce starts for the %d Hz check" % int(hz))
		var travelled := 0.0
		var guard := 0
		while player.is_pouncing() and guard < 100:
			player._move_during_pounce(1.0 / hz)
			travelled += player.velocity.x * (1.0 / hz)
			guard += 1
		_check(absf(travelled - 80.0) <= 0.5, "pounce covers 80 px at %d Hz (got %.2f)" % [int(hz), travelled])
		_reset_player()
	player.dash_charges = 2
	player._try_start_dash(Vector2.RIGHT)
	player.hitstun_left = 0.3
	_check(not player.can_pounce(), "no pounce while in hitstun")
	player.hitstun_left = 0.0
	player.pounce_window_left = 0.0
	_check(not combat._try_start_special_move(), "no pounce once the window has expired")
	_reset_player()

	# --- Counter claw -----------------------------------------------------------------------
	pm._load_profile_data({})
	player.dodge_cooldown_left = 0.0
	player._try_start_dodge(Vector2.RIGHT)
	player.receive_damage(1, player.global_position + Vector2.LEFT)
	_check(player.is_counter_window_open(), "a perfect dodge opens the counter window")
	_check(not combat._try_start_special_move(), "locked: no counter claw")
	pm.unlock_move("counter_claw")
	_check(combat._try_start_special_move(), "unlocked: J after a perfect dodge starts the counter claw")
	_check(combat.action_state == combat.ActionState.COUNTER, "counter claw is active")
	_check(not player.is_counter_window_open(), "the counter claw spends the window")
	_check(is_equal_approx(combat.melee_hitbox.scale.x, 1.25), "counter claw hitbox size")
	_fresh_slime()
	var before_counter: float = slime.current_health
	combat._try_damage_target(slime)
	_check(is_equal_approx(before_counter - slime.current_health, 2.0), "counter claw deals 2 damage")
	_check(slime.state == slime.SlimeState.STUNNED, "counter claw always stuns")
	_reset_player()
	# Priority and busy states.
	pm.unlock_move("pounce")
	player.counter_window_left = 1.0
	player.pounce_window_left = 1.0
	_check(combat._try_start_special_move() and combat.action_state == combat.ActionState.COUNTER, "counter claw wins over pounce when both are possible")
	_reset_player()
	player.counter_window_left = 1.0
	combat.action_state = combat.ActionState.ATTACK1
	_check(not combat._try_start_special_move(), "special moves cannot start in the middle of another attack")
	_reset_player()

	# --- Rewards ------------------------------------------------------------------------
	var fish0: int = currency.fish_count
	day.saved_mood = 0.0
	var fish_events := 0
	var mood_events := 0
	combat.reward_rng.seed = 12345
	for i in range(12):
		combat.current_melee_attack_id = 9000 + i
		var fish_before: int = currency.fish_count
		var mood_before: float = day.saved_mood
		combat._grant_combo_reward(Vector2(500.0, 300.0))
		if currency.fish_count > fish_before:
			fish_events += 1
		if day.saved_mood > mood_before:
			mood_events += 1
	_check(fish_events > 0 and mood_events > 0, "rewards are random between fish and mood (fish %d, mood %d)" % [fish_events, mood_events])
	_check(fish_events + mood_events == 12, "every reward gives exactly one of the two")
	_check(currency.fish_count - fish0 == fish_events * combat.combo_reward_fish, "fish rewards add the configured amount")
	_check(is_equal_approx(day.saved_mood, mood_events * combat.combo_reward_mood), "mood rewards add the configured amount")
	var total_before: float = currency.fish_count + day.saved_mood
	combat._grant_combo_reward(Vector2.ZERO)
	_check(currency.fish_count + day.saved_mood == total_before, "a swing pays its reward only once")
	day.saved_mood = 99.0
	combat.current_melee_attack_id = 9100
	combat.reward_rng.seed = 7
	for i in range(6):
		combat.current_melee_attack_id += 1
		combat._grant_combo_reward(Vector2.ZERO)
	_check(day.saved_mood <= 100.0, "mood never exceeds 100")

	# --- HUD, debug panel -----------------------------------------------------------------------
	pm._load_profile_data({})
	var hud = get_first_node_in_group("battle_ui")
	# The HUD shows the last combo hit's message while it is fresh.
	combat.combo_hit_feedback_left = 0.5
	combat.combo_feedback_text = "三段连击！史莱姆被击晕"
	hud._update_combat_readout()
	_check(hud.combat_feedback.text == "三段连击！史莱姆被击晕", "HUD shows which move just hit")
	combat.combo_hit_feedback_left = 0.0
	hud._update_combat_readout()
	_check(not hud.combat_feedback.text.contains("三段"), "HUD hides unlearned moves")
	pm.unlock_move("triple_combo")
	hud._update_combat_readout()
	_check(hud.combat_feedback.text.contains("三段"), "HUD lists a learned move")
	var main_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(main_scene)
	await process_frame
	pm._load_profile_data({})
	var debug_panel = main_scene.get_node("DebugPanel")
	debug_panel._unlock_all_moves()
	_check(pm.unlocked_moves.size() == 3, "debug panel unlocks every move")
	debug_panel._clear_moves()
	_check(pm.unlocked_moves.is_empty(), "debug panel clears learned moves")

	if failures.is_empty():
		print("COMBO_FRAMEWORK_PASSED: %d checks" % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		quit(1)


func _reset_player() -> void:
	combat.cancel_action()
	combat.action_state = combat.ActionState.IDLE
	combat.melee_cooldown_left = 0.0
	combat.combo_window_open = false
	combat.combo_window_left = 0.0
	combat.buffered_combo = false
	combat.hit_targets.clear()
	player.stop_pounce()
	player.dash_time_left = 0.0
	player.pounce_window_left = 0.0
	player.counter_window_left = 0.0
	player.dodge_iframes_left = 0.0
	player.dodge_time_left = 0.0
	player.invincibility_left = 0.0
	player.hitstun_left = 0.0
	player.current_health = player.max_health
	player.global_position = Vector2(500.0, 350.0)
	player.velocity = Vector2.ZERO


func _fresh_slime() -> void:
	slime.max_health = 60
	slime.current_health = 60
	slime.stun_immunity_left = 0.0
	slime.stun_time_left = 0.0
	slime._change_state(slime.SlimeState.IDLE)
	slime.global_position = Vector2(530.0, 350.0)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", description)
	else:
		failures.append(description)
