extends SceneTree

var failures: Array[String] = []
var test_paths: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var progression := root.get_node("ProgressionManager")
	var day_manager := root.get_node("DayManager")
	var original_path: String = progression.save_path
	var original_test_mode: bool = progression._test_mode
	progression._test_mode = true

	var snapshot := {"hunger": 25.0, "mood": 80.0, "energy": 65.0}
	day_manager.load_save_data({
		"hunger": 25.0,
		"mood": 80.0,
		"energy": 65.0,
		"night_snapshot": snapshot,
	})
	day_manager.current_state = day_manager.TimeState.NIGHT
	_check(is_equal_approx(day_manager.saved_hunger, 25.0), "day-state load preserves hunger instead of resetting to 100")
	_check(is_equal_approx(day_manager.saved_mood, 80.0), "day-state load preserves mood")
	_check(is_equal_approx(day_manager.saved_energy, 65.0), "day-state load preserves energy")
	var modifiers: Dictionary = day_manager.get_night_modifiers()
	_check(is_equal_approx(modifiers["attack_multiplier"], 0.90), "restored snapshot drives the night attack penalty")
	_check(is_equal_approx(modifiers["movement_multiplier"], 1.10), "restored snapshot drives the night movement bonus")
	_check(int(modifiers["max_health_bonus"]) == 0, "restored snapshot keeps the energy boundary")
	var reloaded: Dictionary = day_manager.get_save_data()
	_check(is_equal_approx(float(reloaded["night_snapshot"]["hunger"]), 25.0), "snapshot is included in the day-state payload")

	# Actual profile file round-trip, isolated from the real player save.
	var temp_path := "user://v2_day12_profile_%d.json" % Time.get_ticks_usec()
	test_paths.append(temp_path)
	_remove_profile_files(temp_path)
	progression.save_path = temp_path
	progression._test_mode = false
	progression._profile_save_blocked_by_newer_version = false
	progression.save_now()
	_check(FileAccess.file_exists(ProjectSettings.globalize_path(temp_path)), "day-state save writes the isolated profile")
	_check(not FileAccess.file_exists(ProjectSettings.globalize_path(temp_path + ".tmp")), "atomic save leaves no temporary file behind")

	day_manager.load_save_data({"hunger": 100.0, "mood": 100.0, "energy": 100.0})
	day_manager.current_state = day_manager.TimeState.NIGHT
	progression._load_profile()
	_check(is_equal_approx(day_manager.saved_hunger, 25.0), "profile reload restores saved hunger")
	_check(is_equal_approx(day_manager.saved_mood, 80.0), "profile reload restores saved mood")
	_check(is_equal_approx(day_manager.saved_energy, 65.0), "profile reload restores saved energy")
	_check(is_equal_approx(float(day_manager.night_state_snapshot.get("hunger", 0.0)), 25.0), "profile reload restores the night snapshot")
	_check(is_equal_approx(day_manager.get_night_attack_multiplier(), 0.90), "reloaded snapshot still applies exactly once")

	# Reapplying the same loaded snapshot must not stack bonuses.
	var hp_before: int = int(day_manager.get_night_max_health_bonus())
	day_manager.load_save_data(day_manager.get_save_data())
	_check(day_manager.get_night_max_health_bonus() == hp_before, "reloading the same snapshot does not stack its bonus")

	# Old version-1 profile without day_state/inventory remains loadable.
	var old_profile: Dictionary = progression._profile_data().duplicate(true)
	old_profile.erase("inventory")
	old_profile.erase("day_state")
	old_profile["level"] = 7
	old_profile["experience"] = 21
	old_profile["skill_points"] = {"slow": 3, "connection": 4, "bind": 5, "loop": 6}
	var old_payload := {"version": progression.SAVE_VERSION, "profile": old_profile, "expedition": {}}
	_write_text(ProjectSettings.globalize_path(temp_path), JSON.stringify(old_payload))
	_day_reset(day_manager)
	progression._load_profile()
	_check(progression.level == 7 and progression.skill_points["bind"] == 5, "old profile keeps progression and skill points")
	_check(is_equal_approx(day_manager.saved_hunger, 100.0), "old profile without day_state falls back to the neutral default")
	_check(day_manager.night_state_snapshot.is_empty(), "old profile without snapshot has no night bonuses")
	_check(day_manager.get_night_max_health_bonus() == 0, "old profile does not gain a phantom night bonus")

	# Future schema is still protected and never overwritten.
	var future_payload: Dictionary = old_payload.duplicate(true)
	future_payload["version"] = progression.SAVE_VERSION + 1
	var future_text := JSON.stringify(future_payload)
	_write_text(ProjectSettings.globalize_path(temp_path), future_text)
	progression._load_profile()
	_check(progression._profile_save_blocked_by_newer_version, "future profile version blocks overwriting")
	progression.save_now()
	_check(_read_text(ProjectSettings.globalize_path(temp_path)) == future_text, "future profile file remains byte-for-byte unchanged")

	_cleanup(progression, day_manager, original_path, original_test_mode)

	if failures.is_empty():
		print("DAY12_PERSISTENCE_PASSED")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		quit(1)


func _day_reset(day_manager: Node) -> void:
	day_manager.current_state = day_manager.TimeState.DAY
	day_manager.load_save_data({})


func _cleanup(progression: Node, day_manager: Node, original_path: String, original_test_mode: bool) -> void:
	for path in test_paths:
		_remove_profile_files(path)
	progression.save_path = original_path
	progression._test_mode = original_test_mode
	progression._profile_save_blocked_by_newer_version = false
	_day_reset(day_manager)


func _remove_profile_files(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	for suffix in ["", ".tmp", ".bak"]:
		var candidate: String = absolute + str(suffix)
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)


func _write_text(absolute_path: String, text: String) -> void:
	var file := FileAccess.open(absolute_path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _read_text(absolute_path: String) -> String:
	var file := FileAccess.open(absolute_path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		failures.append(description)
