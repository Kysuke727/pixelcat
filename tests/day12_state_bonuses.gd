extends SceneTree

const DayStateBonuses = preload("res://scripts/day_state_bonuses.gd")

var failures: Array[String] = []
var world: Node
var player: Node2D
var combat: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var progression := root.get_node("ProgressionManager")
	progression._test_mode = true
	progression.debug_session = false
	progression._load_profile_data({})

	# 1) Raw threshold interface.
	var low := DayStateBonuses.compute({"hunger": 29.0, "mood": 70.0, "energy": 70.0})
	_check(is_equal_approx(low["attack_multiplier"], 0.90), "hunger 29 applies x0.90 attack")
	_check(is_equal_approx(low["movement_multiplier"], 1.0), "mood 70 does not trigger movement bonus")
	_check(int(low["max_health_bonus"]) == 0, "energy 70 does not trigger HP bonus")
	var high := DayStateBonuses.compute({"hunger": 30.0, "mood": 71.0, "energy": 71.0})
	_check(is_equal_approx(high["attack_multiplier"], 1.0), "hunger 30 is the strict no-penalty boundary")
	_check(is_equal_approx(high["movement_multiplier"], 1.10), "mood 71 applies x1.10 movement")
	_check(int(high["max_health_bonus"]) == 1, "energy 71 applies +1 max HP")
	_check(is_equal_approx(DayStateBonuses.compute({"hunger": 29.999})["attack_multiplier"], 0.90), "hunger just below 30 still penalizes")
	_check(is_equal_approx(DayStateBonuses.compute({"mood": 70.001})["movement_multiplier"], 1.10), "mood just above 70 rewards")
	_check(int(DayStateBonuses.compute({"energy": 70.001})["max_health_bonus"]) == 1, "energy just above 70 rewards")

	await _build_world()
	player.set_physics_process(false)
	player.set_process(false)
	combat.set_process(false)
	player.global_position = Vector2(500.0, 350.0)

	# 2) Night snapshot feeds the live player without overwriting progression.
	var day_manager := root.get_node("DayManager")
	day_manager.current_state = day_manager.TimeState.NIGHT
	day_manager.set_night_snapshot({"hunger": 29.0, "mood": 71.0, "energy": 71.0})
	progression.attributes["attack"] = 0
	progression.attributes["agility"] = 0
	progression.attributes["vitality"] = 0
	progression.permanent_hp_bonus = 0
	player._apply_progression_stats(true)
	player.current_health = player.max_health
	_check(player.max_health == 6, "night energy bonus raises max HP from 5 to 6")
	player._apply_progression_stats(true)
	player._apply_progression_stats(true)
	_check(player.max_health == 6, "recalculating night stats does not stack the HP bonus")
	_check(progression.permanent_hp_bonus == 0, "night HP bonus never writes permanent_hp_bonus")
	_check(is_equal_approx(player.get_effective_move_speed(), 220.0), "mood bonus raises the actual move speed to 220")

	# 3) Growth multipliers combine with the snapshot multipliers.
	progression.attributes["agility"] = 5
	_check(is_equal_approx(player.get_effective_move_speed(), 242.0), "agility growth and mood bonus multiply together")
	progression.attributes["agility"] = 0

	var melee_target := _spawn_slime(Vector2(560.0, 350.0))
	player.last_facing = Vector2.RIGHT
	combat._start_melee(false)
	combat._try_damage_target(melee_target)
	_check(is_equal_approx(melee_target.current_health, 4.1), "low hunger applies x0.90 to the melee damage flow")
	_remove_slime(melee_target)

	progression.attributes["attack"] = 2
	var combined_target := _spawn_slime(Vector2(560.0, 350.0))
	player.last_facing = Vector2.RIGHT
	combat._start_melee(false)
	combat._try_damage_target(combined_target)
	_check(is_equal_approx(combined_target.current_health, 4.01), "attack growth and hunger penalty combine in melee")
	_remove_slime(combined_target)

	combat.facing = Vector2.RIGHT
	combat.ranged_cooldown_left = 0.0
	combat.yarn_projectile_in_flight = false
	combat._spawn_projectile()
	var projectile: Node = get_nodes_in_group("yarn_projectiles").back()
	_check(is_equal_approx(projectile.damage, 0.99), "attack growth and hunger penalty combine in the ranged flow")
	projectile.queue_free()
	combat.yarn_projectile_in_flight = false
	await process_frame
	progression.attributes["attack"] = 0

	# 4) Level-up and safe-point revival recalculate from base + snapshot only.
	progression.attributes["vitality"] = 2
	player._apply_progression_stats(true)
	_check(player.max_health == 8, "vitality growth and energy bonus combine on level-up recalculation")
	player.current_health = 1.0
	player.revive_from_expedition(Vector2(480.0, 350.0))
	_check(player.current_health == player.max_health and player.max_health == 8, "safe-point revival keeps the night HP bonus without stacking it")
	progression.attributes["vitality"] = 0

	# 5) Returning to day clears the temporary modifiers.
	day_manager.current_state = day_manager.TimeState.DAY
	day_manager.clear_night_snapshot()
	player._apply_progression_stats(true)
	_check(player.max_health == 5, "daytime max HP returns to the base value")
	_check(is_equal_approx(player.get_effective_move_speed(), 200.0), "daytime movement returns to base speed")
	var day_target := _spawn_slime(Vector2(560.0, 350.0))
	player.last_facing = Vector2.RIGHT
	combat._start_melee(false)
	combat._try_damage_target(day_target)
	_check(is_equal_approx(day_target.current_health, 4.0), "daytime melee damage is not penalized")
	_remove_slime(day_target)

	await _teardown_world()
	day_manager.current_state = day_manager.TimeState.DAY
	day_manager.clear_night_snapshot()

	if failures.is_empty():
		print("DAY12_STATE_BONUSES_PASSED")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		quit(1)


func _build_world() -> void:
	world = load("res://scenes/worlds/night_world.tscn").instantiate()
	var night_music := world.get_node_or_null("NightMusic")
	if night_music != null:
		night_music.autoplay = false
		night_music.stream = null
	root.add_child(world)
	current_scene = world
	await physics_frame
	player = get_first_node_in_group("player")
	combat = player.get_node("PlayerCombat")
	for enemy in get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
		enemy.global_position = Vector2(960.0, 660.0)
	await physics_frame


func _spawn_slime(position: Vector2) -> CharacterBody2D:
	var slime: CharacterBody2D = load("res://scenes/enemies/slime.tscn").instantiate()
	world.add_child(slime)
	slime.global_position = position
	slime.set_physics_process(false)
	slime.set_process(false)
	for sound_name in ["AttackSound", "HitSound", "DeathSound"]:
		var sound := slime.get_node_or_null(sound_name)
		if sound != null:
			sound.stream = null
	return slime


func _remove_slime(node: Variant) -> void:
	if is_instance_valid(node):
		node.queue_free()


func _teardown_world() -> void:
	if is_instance_valid(world):
		for audio_player in world.find_children("*", "AudioStreamPlayer", true, false):
			audio_player.stop()
			audio_player.stream = null
		for audio_player in world.find_children("*", "AudioStreamPlayer2D", true, false):
			audio_player.stop()
			audio_player.stream = null
		current_scene = null
		world.queue_free()
		await process_frame
		await process_frame


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		failures.append(description)
