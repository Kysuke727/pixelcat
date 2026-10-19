extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var progression: Node = root.get_node("ProgressionManager")
	var expedition: Node = root.get_node("ExpeditionManager")
	var currency: Node = root.get_node("CurrencyManager")
	var day_manager: Node = root.get_node("DayManager")
	_check(progression.required_experience(1) == 100, "level 1 to 2 uses 100 XP")
	_check(progression.required_experience(2) == 110, "level 2 to 3 uses rounded 1.10 growth")
	progression._load_profile_data({})
	progression.add_experience(99)
	_check(progression.level == 1 and progression.experience == 99, "XP below the threshold does not level up")
	progression.add_experience(1)
	_check(progression.level == 2 and progression.available_points == 1, "level-up awards one attribute point")
	progression.add_experience(110 + 121 + 133)
	_check(progression.level == 5, "XP can cross multiple thresholds in one reward")
	_check(progression.available_points == 7, "fifth level awards the normal point plus three milestone points")

	progression.begin_allocation()
	_check(progression.allocate_point("vitality"), "draft allocation accepts an available attribute point")
	_check(progression.attributes["vitality"] == 0, "draft allocation does not alter committed stats")
	_check(progression.remove_pending_point("vitality"), "draft points can be individually removed")
	_check(progression.allocate_point("attack"), "attack attribute point can be drafted")
	_check(progression.allocate_point("slow", true), "slow technique branch point can be drafted")
	_check(progression.commit_allocation(), "draft can be committed")
	_check(progression.available_points == 5, "commit spends only the selected points")
	_check(progression.allocate_point("vitality"), "allocation can continue immediately after a commit")
	progression.cancel_allocation()
	_check(progression.allocate_point("defense"), "allocation can be restarted immediately after undo")
	progression.cancel_allocation()
	_check(progression.attributes["attack"] == 1 and progression.attributes["technique"] == 1, "five-attribute data tracks branch investment as technique")
	_check(is_equal_approx(progression.get_attack_multiplier(), 1.05), "attack point applies a linear five percent modifier")
	_check(is_equal_approx(progression.get_movement_multiplier(), 1.0), "no agility points leave ordinary speed unchanged")
	progression.begin_allocation()
	progression.allocate_point("defense")
	progression.cancel_allocation()
	_check(progression.available_points == 5 and progression.attributes["defense"] == 0, "cancel restores the unsubmitted allocation for free")
	progression.begin_allocation()
	progression.allocate_point("vitality")
	progression.allocate_point("defense")
	progression.allocate_point("agility")
	progression.commit_allocation()
	_check(progression.get_effective_max_health(5) == 6, "vitality adds one maximum HP per committed point")
	_check(is_equal_approx(100.0 * progression.get_shield_multiplier(), 103.0), "defense adds three percent maximum shield per point")
	_check(is_equal_approx(progression.get_movement_multiplier(), 1.02), "agility adds two percent ordinary movement speed")
	_check(is_equal_approx(progression.get_skill_modifiers()["slow_reduction_bonus"], 0.02), "one slow skill point gives two percentage points")
	progression.skill_points["slow"] = 15
	_check(progression._skill_at_cap("slow", 15), "skill cap blocks investment past eighty percent slow")
	progression.skill_points["slow"] = 1

	var save_data: Dictionary = progression.get_save_data()
	progression._load_profile_data(save_data["profile"])
	_check(progression.level == 5 and progression.attributes["attack"] == 1, "versioned profile data restores progression fields")
	_check(save_data["version"] == progression.SAVE_VERSION, "save data carries an explicit schema version")
	_check(progression.get_respec_cost() == 150, "respec price follows 100 plus ten per level")
	var old_save_path: String = progression.save_path
	progression.save_path = "user://pixelcat_v3_1_autotest.json"
	progression._test_mode = false
	progression.save_now()
	_check(FileAccess.file_exists(progression.save_path), "profile data writes to the versioned persistent save file")
	var profile_file := FileAccess.open(progression.save_path, FileAccess.READ)
	var valid_profile_text := profile_file.get_as_text() if profile_file != null else ""
	if profile_file != null:
		profile_file.close()
	_check(not progression._write_profile_atomically("{ invalid json", progression.save_path), "corrupt temporary save payload is rejected")
	var retained_profile := FileAccess.open(progression.save_path, FileAccess.READ)
	_check(retained_profile != null and retained_profile.get_as_text() == valid_profile_text, "failed write leaves the previous valid save untouched")
	if retained_profile != null:
		retained_profile.close()
	progression._load_profile()
	_check(progression.attributes["vitality"] == 1 and progression.skill_points["slow"] == 1, "persistent save reload restores attributes and technique branches")
	var expected_recovery_level: int = progression.level
	progression.experience += 1
	progression.save_now()
	var corrupt_main := FileAccess.open(progression.save_path, FileAccess.WRITE)
	corrupt_main.store_string("{ damaged profile")
	corrupt_main.close()
	progression.level = 99
	progression._load_profile()
	_check(progression.level == expected_recovery_level, "damaged profile is recovered from the last verified backup")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(progression.save_path))
	for backup in progression._list_profile_backups(ProjectSettings.globalize_path(progression.save_path)):
		DirAccess.remove_absolute(backup)
	progression._test_mode = true
	progression.save_path = old_save_path

	var day_scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(day_scene)
	current_scene = day_scene
	await physics_frame
	var player := get_first_node_in_group("player")
	_check(is_instance_valid(player), "day scene still instantiates its cat")
	_check(player.max_health == 6, "committed vitality changes the next cat instance maximum HP")
	_check(is_equal_approx(player.shield_max_durability, 103.0), "committed defense changes the next cat instance shield")
	_check(is_instance_valid(day_scene.get_node_or_null("FishUI")), "day scene displays the saved fish currency")
	_check(is_instance_valid(day_scene.get_node_or_null("ProgressionPanel")) and is_instance_valid(day_scene.get_node_or_null("DebugPanel")), "day scene exposes growth and debug panels")
	var debug_level: int = progression.level
	var debug_xp: int = progression.experience
	var debug_fish: int = currency.fish_count
	progression.begin_debug_session()
	expedition.begin_debug_session()
	progression.add_experience(500)
	currency.add_permanent_fish(23)
	_check(currency.spend_fish(8), "debug session can exercise a real permanent-currency spend")
	expedition.begin_run()
	expedition.add_ordinary_fish(9)
	var debug_scene_path := current_scene.scene_file_path
	await day_manager.switch_to_night()
	_check(current_scene.scene_file_path == debug_scene_path and not expedition.run_active, "debug isolation blocks cross-scene changes and run creation")
	expedition.end_debug_session()
	progression.end_debug_session()
	expedition.restore_debug_player_snapshot()
	_check(progression.level == debug_level and progression.experience == debug_xp, "closing the debug session restores profile progress")
	_check(not expedition.run_active and currency.fish_count == debug_fish, "debug income and spending restore permanent currency and expedition state")
	var before_failed_switch: Dictionary = expedition.get_save_data()
	day_manager.scene_change_override = func(_scene_path: String) -> int: return ERR_FILE_NOT_FOUND
	await day_manager.switch_to_night()
	_check(day_manager.current_state == day_manager.TimeState.DAY, "failed night scene switch restores the daytime state")
	_check(not expedition.run_active and expedition.get_save_data() == before_failed_switch, "failed night scene switch rolls back the newly created expedition")
	day_manager.scene_change_override = Callable()

	var resume_state := {
		"run_active": true,
		"lives_left": 1,
		"ordinary_fish": 7,
		"objectives_total": 3,
		"objectives_completed": 1,
		"defeated_enemy_ids": ["SlimeA"],
		"exploration_reward_claimed": false,
		"safe_position": [300.0, 470.0],
		"player_position": [780.0, 500.0],
		"health": 3.5,
		"shield": 42.0,
	}
	expedition.load_save_data(resume_state)
	day_manager.current_state = 0
	await day_manager._resume_saved_expedition()
	await physics_frame
	var night_scene := current_scene
	player = get_first_node_in_group("player")
	var debug_slime := night_scene.get_node("SlimeB") as Node
	var debug_slime_health := float(debug_slime.get("current_health"))
	progression.begin_debug_session()
	expedition.begin_debug_session()
	debug_slime.receive_damage(999.0, player.global_position, 0.0)
	_check(is_equal_approx(float(debug_slime.get("current_health")), debug_slime_health), "debug isolation prevents destructive enemy kills")
	expedition.end_debug_session()
	progression.end_debug_session()
	_check(day_manager.current_state == 1, "active night save resumes into the night map")
	_check(player.global_position.is_equal_approx(Vector2(780.0, 500.0)), "resumed exploration restores the saved player position")
	_check(is_equal_approx(player.current_health, 3.5) and is_equal_approx(player.shield_durability, 42.0), "resume restores precise health and shield values")
	_check(is_instance_valid(night_scene.get_node_or_null("ProgressionPanel")) and is_instance_valid(night_scene.get_node_or_null("DebugPanel")), "night scene exposes growth and debug panels")
	_check(expedition.lives_left == 1 and expedition.ordinary_fish == 7, "resume restores lives and separated ordinary loot")
	_check(expedition.objectives_completed == 1, "resume preserves the already defeated objective")
	_check(night_scene.get_node("SlimeA").is_queued_for_deletion(), "previously defeated enemies are removed during resume")
	var exit_gate := night_scene.get_node("NightExit")
	_check(not exit_gate.monitoring, "extraction gate stays locked until all goals are complete")
	var combat := player.get_node("PlayerCombat")
	var damage_target := night_scene.get_node("SlimeB")
	combat._try_damage_target(damage_target)
	_check(is_equal_approx(damage_target.current_health, damage_target.max_health - 1.05), "attack attribute retains fractional damage internally")
	_check(is_equal_approx(player.get_effective_move_speed(), 204.0), "agility affects ordinary movement but not dodge tuning")

	for enemy in get_nodes_in_group("enemies"):
		if enemy.name != "SlimeA":
			enemy.set_physics_process(false)
			enemy.receive_damage(999.0, player.global_position, 0.0)
	await create_timer(0.35).timeout
	_check(expedition.objectives_complete(), "defeating all remaining enemies completes the exploration objective")
	_check(exit_gate.monitoring, "exit gate activates when the objective is complete")
	_check(expedition.exploration_reward_claimed, "objective completion awards exploration XP once")
	_check(not expedition.fish_drops.is_empty(), "enemy defeat saves unique unclaimed fish-drop records")
	if not expedition.fish_drops.is_empty():
		var drop_id := str(expedition.fish_drops.keys()[0])
		var drop_snapshot: Dictionary = expedition.get_save_data()
		for pickup in get_nodes_in_group("dried_fish_pickups"):
			pickup.queue_free()
		await process_frame
		night_scene.get_node("NightRunController")._restore_saved_drops()
		await physics_frame
		_check(get_nodes_in_group("dried_fish_pickups").size() == drop_snapshot["fish_drops"].size(), "unclaimed drops are reconstructed after a world reload")
		var pickup := get_nodes_in_group("dried_fish_pickups")[0]
		var before_pickup: int = expedition.ordinary_fish
		pickup._on_body_entered(player)
		_check(expedition.ordinary_fish == before_pickup + 1, "restored drop is picked up into expedition fish")
		pickup._on_body_entered(player)
		_check(expedition.ordinary_fish == before_pickup + 1, "a claimed drop cannot be collected twice")
		var post_pickup_snapshot: Dictionary = expedition.get_save_data()
		expedition.load_save_data(post_pickup_snapshot)
		_check(not expedition.fish_drops.has(drop_id), "claimed-drop state survives save reload")
	var pre_exit_fish: int = expedition.ordinary_fish
	_check(exit_gate.extract(), "player can explicitly extract through the unlocked gate")
	await scene_changed
	_check(day_manager.current_state == 0, "successful extraction returns to the day scene")
	_check(not expedition.run_active and expedition.last_outcome == "success", "successful extraction ends and records the run")
	_check(currency.fish_count >= pre_exit_fish, "successful extraction banks all ordinary loot")

	expedition.begin_run()
	expedition.add_ordinary_fish(5)
	var currency_before_failure: int = currency.fish_count
	expedition.finish_run(false, false)
	_check(currency.fish_count == currency_before_failure + 3, "failure floors a 50 percent loss for odd loot and banks the retained half")
	_check(expedition.last_outcome == "failed", "failed exploration records its outcome")

	day_manager.switch_to_night()
	await scene_changed
	await physics_frame
	var current_player := get_first_node_in_group("player")
	expedition.activate_safe_point(Vector2(280.0, 460.0))
	current_player.die()
	_check(expedition.saved_player_position.is_equal_approx(Vector2(280.0, 460.0)), "death autosave records the safe-point respawn position")
	_check(is_equal_approx(expedition.saved_health, current_player.max_health) and is_equal_approx(expedition.saved_shield, current_player.shield_max_durability * 0.5), "death autosave records the intended restored HP and half shield")
	await process_frame
	_check(not current_player.dead, "player returns from the death state after respawning")
	_check(expedition.lives_left == 1, "first death consumes exactly one exploration life")
	_check(current_player.global_position.is_equal_approx(Vector2(280.0, 460.0)), "death respawns at the most recently activated safe point")
	_check(is_equal_approx(current_player.current_health, current_player.max_health), "respawn restores full health")
	_check(is_equal_approx(current_player.shield_durability, current_player.shield_max_durability * 0.5), "respawn restores half shield")
	expedition.add_ordinary_fish(5)
	var currency_before_exhaustion: int = currency.fish_count
	var night_scene_before_failure := current_scene
	current_player.die()
	await scene_changed
	_check(expedition.lives_left == 0 and not expedition.run_active, "last death exhausts exploration lives and fails the run")
	_check(currency.fish_count == currency_before_exhaustion + 3, "life exhaustion applies the same configured loss and banks retained loot")
	_check(day_manager.current_state == 0 and current_scene.scene_file_path == "res://scenes/main.tscn", "life exhaustion automatically returns the player to the day")

	var active_scene := current_scene
	if is_instance_valid(active_scene):
		for audio_player in active_scene.find_children("*", "AudioStreamPlayer2D", true, false):
			audio_player.stop()
			audio_player.stream = null
		for audio_player in active_scene.find_children("*", "AudioStreamPlayer", true, false):
			audio_player.stop()
			audio_player.stream = null
		current_scene = null
		active_scene.queue_free()
	if is_instance_valid(night_scene) and night_scene != active_scene:
		night_scene.queue_free()
	if is_instance_valid(night_scene_before_failure) and night_scene_before_failure != active_scene:
		night_scene_before_failure.queue_free()
	if is_instance_valid(day_scene):
		if current_scene == day_scene:
			current_scene = null
		day_scene.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.3).timeout
	if failures.is_empty():
		print("V3_1_PHASES_04_TO_06_PASSED")
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
# End of phase 04–06 regression tests.

