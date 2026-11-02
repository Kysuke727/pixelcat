extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var progression := root.get_node("ProgressionManager")
	var expedition := root.get_node("ExpeditionManager")
	var day_manager := root.get_node("DayManager")
	progression._test_mode = true
	progression.debug_session = false
	progression._load_profile_data({})
	expedition.load_save_data({})
	day_manager.current_state = day_manager.TimeState.DAY
	day_manager.clear_night_snapshot()

	var day_scene: Node = load("res://scenes/main.tscn").instantiate()
	var day_bgm := day_scene.get_node_or_null("BGMPlayer")
	if day_bgm != null:
		day_bgm.autoplay = false
		day_bgm.stream = null
	root.add_child(day_scene)
	current_scene = day_scene
	await physics_frame
	var day_stats := day_scene.get_node("Cat/Stats")
	day_stats.hunger = 20.0
	day_stats.mood = 80.0
	day_stats.energy = 80.0
	var day_player := get_first_node_in_group("player")
	_check(day_player.max_health == 5, "day scene starts with the base 5 max HP")
	_check(is_equal_approx(day_player.get_effective_move_speed(), 200.0), "day scene starts with base movement speed")

	await day_manager.switch_to_night()
	await physics_frame
	_check(day_manager.current_state == day_manager.TimeState.NIGHT, "normal switch enters the night state")
	_check(is_equal_approx(day_manager.saved_hunger, 20.0), "night entry captures the daytime hunger snapshot")
	_check(is_equal_approx(day_manager.night_state_snapshot.get("mood", 0.0), 80.0), "night entry captures the daytime mood snapshot")
	_check(is_equal_approx(day_manager.night_state_snapshot.get("energy", 0.0), 80.0), "night entry captures the daytime energy snapshot")
	var night_scene := current_scene
	var night_music := night_scene.get_node_or_null("NightMusic")
	if night_music != null:
		night_music.stop()
		night_music.stream = null
	var night_player := get_first_node_in_group("player")
	night_player.set_physics_process(false)
	night_player.set_process(false)
	var combat := night_player.get_node("PlayerCombat")
	combat.set_process(false)
	_check(night_player.max_health == 6, "night energy snapshot adds exactly one max HP")
	_check(is_equal_approx(night_player.get_effective_move_speed(), 220.0), "night mood snapshot raises actual speed")
	_check(is_equal_approx(day_manager.get_night_attack_multiplier(), 0.90), "night hunger snapshot applies the damage penalty")
	var night_stats = night_scene.get_node("Cat/Stats")
	_check(is_equal_approx(night_stats.hunger, 20.0), "night scene receives the captured daytime stats")

	var target: CharacterBody2D = load("res://scenes/enemies/slime.tscn").instantiate()
	night_scene.add_child(target)
	target.global_position = night_player.global_position + Vector2(60.0, 0.0)
	target.set_physics_process(false)
	target.set_process(false)
	night_player.last_facing = Vector2.RIGHT
	combat._start_melee(false)
	combat._try_damage_target(target)
	_check(is_equal_approx(target.current_health, 4.1), "night scene melee uses the combined growth/status multiplier")

	# The scene reload must not re-apply or stack the snapshot.
	var max_health_before: float = night_player.max_health
	night_player._apply_progression_stats(true)
	_check(is_equal_approx(night_player.max_health, max_health_before), "night scene recalculation does not stack the HP bonus")

	expedition.finish_run(true)
	await scene_changed
	await physics_frame
	var returned_bgm = current_scene.get_node_or_null("BGMPlayer")
	if returned_bgm != null:
		returned_bgm.stop()
		returned_bgm.stream = null
		await process_frame
	_check(day_manager.current_state == day_manager.TimeState.DAY, "successful extraction returns to day")
	_check(day_manager.night_state_snapshot.is_empty(), "returning to day clears the temporary night snapshot")
	var returned_player := get_first_node_in_group("player")
	_check(returned_player.max_health == 5, "returning to day removes the temporary max HP bonus")
	_check(is_equal_approx(returned_player.get_effective_move_speed(), 200.0), "returning to day removes the movement bonus")
	var returned_stats = current_scene.get_node("Cat/Stats")
	_check(absf(returned_stats.hunger - 20.0) < 1.0 and absf(returned_stats.mood - 80.0) < 1.0, "day scene restores the persisted stats")
	_check(not expedition.run_active, "extraction ends the expedition")
	_check(not day_manager.has_night_snapshot(), "no snapshot remains after extraction")
	for _frame in range(10):
		await process_frame

	if failures.is_empty():
		print("DAY12_NIGHT_INTEGRATION_PASSED")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		quit(1)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		failures.append(description)
