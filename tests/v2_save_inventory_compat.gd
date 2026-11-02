extends SceneTree

var failures: Array[String] = []
var test_path := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var progression := root.get_node("ProgressionManager")
	var inventory := root.get_node("InventoryManager")
	var currency := root.get_node("CurrencyManager")
	var expedition := root.get_node("ExpeditionManager")
	var day_manager := root.get_node("DayManager")
	var original_path: String = progression.save_path
	var original_test_mode: bool = progression._test_mode

	test_path = "user://v2_inventory_compat_%d.json" % Time.get_ticks_usec()
	_remove_profile_family(test_path)
	progression.save_path = test_path
	progression._test_mode = true
	progression._profile_save_blocked_by_newer_version = false
	inventory.clear_all()
	day_manager.load_save_data({"hunger": 28.0, "mood": 75.0, "energy": 60.0})
	inventory.add_item("yarn_ball", 3)
	inventory.add_item("wood", 2)

	progression._test_mode = false
	progression.save_now()
	_check(FileAccess.file_exists(ProjectSettings.globalize_path(test_path)), "profile save creates the isolated file")
	_check(not FileAccess.file_exists(ProjectSettings.globalize_path(test_path + ".tmp")), "profile save leaves no temporary file")

	progression._test_mode = true
	inventory.clear_all()
	day_manager.load_save_data({})
	progression._test_mode = false
	progression._load_profile()
	_check(inventory.get_item_count("yarn_ball") == 3, "profile reload restores yarn stacks")
	_check(inventory.get_item_count("wood") == 2, "profile reload restores wood stacks")
	_check(is_equal_approx(day_manager.saved_hunger, 28.0), "profile reload restores day-state hunger")

	# Second save creates a valid .bak, then corrupt the primary profile.
	progression._test_mode = true
	inventory.add_item("stone", 1)
	day_manager.load_save_data({"hunger": 10.0, "mood": 10.0, "energy": 10.0})
	progression._test_mode = false
	progression.save_now()
	_check(FileAccess.file_exists(ProjectSettings.globalize_path(test_path + ".bak")), "second save keeps the previous profile as backup")
	var corrupt_payload: Dictionary = progression.get_save_data()
	corrupt_payload["profile"]["inventory"] = "not-an-array"
	_write_text(ProjectSettings.globalize_path(test_path), JSON.stringify(corrupt_payload))
	progression._load_profile()
	_check(inventory.get_item_count("yarn_ball") == 3 and inventory.get_item_count("wood") == 2, "corrupt inventory is recovered from the valid backup")
	_check(inventory.get_item_count("stone") == 0, "recovery uses the backup inventory snapshot, not the corrupt file")
	_check(is_equal_approx(day_manager.saved_hunger, 28.0), "recovery also restores the backup day state")
	_check(_read_text(ProjectSettings.globalize_path(test_path)).contains("\"inventory\""), "recovered primary profile contains a valid inventory field")

	# Old profile without the new sections stays loadable.
	var old_profile: Dictionary = progression._profile_data().duplicate(true)
	old_profile.erase("inventory")
	old_profile.erase("day_state")
	old_profile["level"] = 6
	old_profile["skill_points"] = {"slow": 2, "connection": 7, "bind": 4, "loop": 9}
	_write_text(
		ProjectSettings.globalize_path(test_path),
		JSON.stringify({"version": progression.SAVE_VERSION, "profile": old_profile, "expedition": {}})
	)
	progression._load_profile()
	_check(inventory.get_item_count("yarn_ball") == 0 and inventory.get_item_count("wood") == 0, "old profile loads an empty inventory")
	_check(progression.level == 6 and progression.skill_points["loop"] == 9, "old profile keeps progression and skill points")
	_check(is_equal_approx(day_manager.saved_hunger, 100.0), "old profile keeps the neutral day-state default")

	# Currency and ordinary inventory are separate ledgers.
	progression._test_mode = true
	inventory.clear_all()
	var currency_before: int = currency.fish_count
	currency.add_permanent_fish(5)
	_check(currency.fish_count == currency_before + 5, "permanent fish is credited to CurrencyManager")
	_check(inventory.get_item_count("golden_fish") == 0, "currency fish is not duplicated in the backpack")
	expedition.begin_run()
	expedition.add_ordinary_fish(4)
	var inventory_snapshot: Array = inventory.get_save_data()
	expedition.finish_run(true, false)
	_check(currency.fish_count == currency_before + 9, "night settlement credits retained fish once")
	_check(inventory.get_save_data() == inventory_snapshot, "night settlement does not alter ordinary inventory")
	expedition.load_save_data({})
	progression._test_mode = original_test_mode
	progression.save_path = original_path
	_remove_profile_family(test_path)

	if failures.is_empty():
		print("V2_SAVE_INVENTORY_COMPAT_PASSED")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		quit(1)


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


func _remove_profile_family(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	var directory := absolute.get_base_dir()
	var prefix := absolute.get_file()
	var dir := DirAccess.open(directory)
	if dir == null:
		return
	for file_name in dir.get_files():
		if file_name.begins_with(prefix):
			DirAccess.remove_absolute(directory.path_join(file_name))


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		failures.append(description)
