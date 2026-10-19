extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var progression := root.get_node("ProgressionManager")
	var expedition := root.get_node("ExpeditionManager")
	var currency := root.get_node("CurrencyManager")
	var day_manager := root.get_node("DayManager")
	progression._test_mode = true
	var day_scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(day_scene)
	current_scene = day_scene
	await physics_frame
	await day_manager.switch_to_night()
	var world := current_scene
	await physics_frame
	expedition.lives_left = 2
	expedition.ordinary_fish = 4
	expedition.objectives_total = 3
	expedition.objectives_completed = 1
	expedition.defeated_enemy_ids.clear()
	expedition.defeated_enemy_ids.append("SlimeA")
	expedition.active_safe_position = Vector2(300.0, 470.0)
	var player := get_first_node_in_group("player")
	var debug_panel := world.get_node("DebugPanel")
	player.global_position = Vector2(540.0, 420.0)
	player.current_health = 3.0
	player.shield_durability = 57.0
	var saved_position: Vector2 = player.global_position
	var saved_health: float = player.current_health
	var saved_shield: float = player.shield_durability
	var saved_max_health: float = player.max_health
	var saved_profile: Dictionary = progression.get_profile_data().duplicate(true)
	var saved_currency: int = currency.fish_count
	var saved_expedition: Dictionary = expedition.get_save_data().duplicate(true)
	_open_debug(debug_panel)
	debug_panel._change_player("current_health", -1.0)
	debug_panel._change_player("shield_durability", -10.0)
	player.global_position += Vector2(18.0, -11.0)
	progression.add_experience(250)
	progression.attributes["vitality"] += 2
	progression.progression_changed.emit()
	currency.add_permanent_fish(17)
	expedition.lives_left = 1
	expedition.ordinary_fish = 99
	expedition.objectives_completed = 3
	expedition.defeated_enemy_ids.append("SlimeB")
	player.die()
	_check(player.dead and not player.get_node("PlayerCombat").combat_enabled, "debug fixture kills the player and disables combat before closing")
	_click_close(debug_panel)
	_check(not debug_panel.active and not player.dead and player.get_node("PlayerCombat").combat_enabled, "actual DebugPanel close restores survival and combat state")
	_check(player.global_position.is_equal_approx(saved_position) and is_equal_approx(player.current_health, saved_health) and is_equal_approx(player.shield_durability, saved_shield) and is_equal_approx(player.max_health, saved_max_health), "actual DebugPanel close restores position, HP, shield and progression-derived max HP")
	_check(progression.get_profile_data() == saved_profile and currency.fish_count == saved_currency, "actual DebugPanel close restores growth and permanent currency")
	_check(expedition.get_save_data() == saved_expedition, "actual DebugPanel close restores exploration lives and objective records")

	var exit_panel: Node = load("res://scripts/debug_panel.gd").new()
	world.add_child(exit_panel)
	_open_debug(exit_panel)
	player.current_health = 1.0
	player.shield_durability = 2.0
	player.global_position += Vector2(-9.0, 14.0)
	player.die()
	exit_panel.free()
	_check(not player.dead and player.global_position.is_equal_approx(saved_position) and is_equal_approx(player.current_health, saved_health) and is_equal_approx(player.shield_durability, saved_shield), "DebugPanel _exit_tree restores player state when the panel is removed")
	_check(not progression.debug_session and expedition.get_save_data() == saved_expedition, "DebugPanel _exit_tree completes rollback without leaving debug mode active")

	await _test_profile_recovery(progression, expedition, currency)
	if is_instance_valid(world):
		for audio_player in world.find_children("*", "AudioStreamPlayer2D", true, false):
			audio_player.stop()
			audio_player.stream = null
		current_scene = null
		world.queue_free()
	await process_frame
	await create_timer(0.25).timeout
	if failures.is_empty():
		print("REVIEW_V3_1_2_REGRESSIONS_PASSED")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _test_profile_recovery(progression: Node, expedition: Node, currency: Node) -> void:
	var original_path: String = progression.save_path
	var original_test_mode: bool = progression._test_mode
	var original_profile: Dictionary = progression.get_profile_data().duplicate(true)
	var original_currency: Dictionary = currency.get_save_data().duplicate(true)
	var original_expedition: Dictionary = expedition.get_save_data().duplicate(true)
	var test_path := "user://review_v3_1_2_profile.json"
	progression.save_path = test_path
	progression._test_mode = false
	progression._profile_save_blocked_by_newer_version = false
	var absolute_path := ProjectSettings.globalize_path(test_path)
	_clear_profile_candidates(progression, absolute_path)
	var profile_2 := _profile_payload(progression, 2, 12)
	_write_text(absolute_path, JSON.stringify(profile_2))
	progression._load_profile_data({})
	progression._load_profile()
	_check(progression.level == 2 and currency.fish_count == 12, "valid formal profile is loaded before recovery candidates")

	_clear_profile_candidates(progression, absolute_path)
	var profile_3 := _profile_payload(progression, 3, 13)
	_write_text(absolute_path, "{ damaged main")
	_write_text(absolute_path + ".bak", JSON.stringify(profile_3))
	progression._load_profile_data({})
	progression._load_profile()
	_check(progression.level == 3 and currency.fish_count == 13 and progression._is_usable_profile_payload(progression._read_profile_payload(absolute_path)), "corrupt main restores from verified backup and repairs formal profile")

	_clear_profile_candidates(progression, absolute_path)
	var profile_4 := _profile_payload(progression, 4, 14)
	_write_text(absolute_path + ".bak", JSON.stringify(profile_4))
	progression._load_profile_data({})
	progression._load_profile()
	_check(progression.level == 4 and currency.fish_count == 14 and FileAccess.file_exists(absolute_path), "missing main recovers and reinstalls a valid backup")

	_clear_profile_candidates(progression, absolute_path)
	var profile_5 := _profile_payload(progression, 5, 15)
	var profile_6 := _profile_payload(progression, 6, 16)
	_write_text(absolute_path + ".bak", JSON.stringify(profile_5))
	_write_text(absolute_path + ".tmp", JSON.stringify(profile_6))
	progression._load_profile_data({})
	progression._load_profile()
	_check(progression.level == 6 and currency.fish_count == 16, "interrupted save with missing main completes from verified temp ahead of backup")

	# Simulate interruption after writing a valid temp but before rotating main.
	_clear_profile_candidates(progression, absolute_path)
	_write_text(absolute_path, JSON.stringify(profile_5))
	_write_text(absolute_path + ".tmp", JSON.stringify(profile_6))
	progression._load_profile_data({})
	progression._load_profile()
	_check(progression.level == 5, "valid old main wins when interruption happened before main rotation")

	# Simulate interruption after main was moved to backup but before temp install.
	_clear_profile_candidates(progression, absolute_path)
	_write_text(absolute_path + ".bak", JSON.stringify(profile_5))
	_write_text(absolute_path + ".tmp", JSON.stringify(profile_6))
	progression._load_profile_data({})
	progression._load_profile()
	_check(progression.level == 6 and progression._is_usable_profile_payload(progression._read_profile_payload(absolute_path)), "post-rotation interruption restores the fully verified pending save")

	progression.save_now()
	progression.level = 99
	progression._load_profile()
	_check(progression.level == 6 and currency.fish_count == 16, "recovered profile survives a new save and another load")

	_clear_profile_candidates(progression, absolute_path)
	var future_profile := _profile_payload(progression, 8, 20)
	future_profile["version"] = progression.SAVE_VERSION + 1
	var future_text := JSON.stringify(future_profile)
	_write_text(absolute_path, future_text)
	progression._load_profile_data({})
	progression._load_profile()
	_check(progression._profile_save_blocked_by_newer_version and progression.level == 1 and FileAccess.get_file_as_string(absolute_path) == future_text, "newer-version profile is preserved without loading defaults over it")

	_clear_profile_candidates(progression, absolute_path)
	_write_text(absolute_path, "invalid main")
	_write_text(absolute_path + ".tmp", "invalid temp")
	_write_text(absolute_path + ".bak", "invalid backup")
	progression._load_profile_data({})
	currency.load_save_data({"fish_count": 0})
	progression._load_profile()
	_check(progression.level == 1 and currency.fish_count == 0, "defaults are used only after every recovery candidate is invalid")

	_clear_profile_candidates(progression, absolute_path)
	progression.save_path = original_path
	progression._test_mode = original_test_mode
	progression._profile_save_blocked_by_newer_version = false
	progression._load_profile_data({})
	progression._load_profile_data(original_profile)
	currency.load_save_data(original_currency)
	expedition.load_save_data(original_expedition)


func _profile_payload(progression: Node, profile_level: int, fish: int) -> Dictionary:
	var profile: Dictionary = progression._profile_data().duplicate(true)
	profile["level"] = profile_level
	profile["experience"] = profile_level * 3
	profile["currency"] = {"fish_count": fish}
	return {"version": progression.SAVE_VERSION, "profile": profile, "expedition": {}}


func _clear_profile_candidates(progression: Node, absolute_path: String) -> void:
	for candidate in [absolute_path, absolute_path + ".tmp", absolute_path + ".bak"]:
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)
	for candidate in progression._list_profile_backups(absolute_path):
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)
	var directory := DirAccess.open(absolute_path.get_base_dir())
	if directory != null:
		for filename in directory.get_files():
			if filename.begins_with(absolute_path.get_file() + ".restore.") or filename.begins_with(absolute_path.get_file() + ".invalid."):
				DirAccess.remove_absolute(absolute_path.get_base_dir().path_join(filename))


func _write_text(path: String, contents: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check(false, "test fixture file opens: " + path)
		return
	file.store_string(contents)
	file.close()


func _open_debug(panel: Node) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.physical_keycode = KEY_F3
	panel._unhandled_input(event)


func _click_close(panel: Node) -> void:
	for button in panel.find_children("*", "Button", true, false):
		if button.text == "关闭并还原调试数据":
			button.pressed.emit()
			return
	_check(false, "debug close button is present")


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		failures.append(description)
