extends SceneTree

# Map catalog, cleared-map progress, saves, per-map expedition and the selection screen.

var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var pm = root.get_node("ProgressionManager")
	var exp = root.get_node("ExpeditionManager")
	var day = root.get_node("DayManager")
	var select = root.get_node("MapSelect")
	var inventory = root.get_node("InventoryManager")
	pm._test_mode = true

	# --- Catalog ----------------------------------------------------------------
	_check(MapCatalog.ids() == ["park", "forest_grove"], "two maps in selection order")
	_check(MapCatalog.display_name("forest_grove") == "小树林", "map display name")
	_check(MapCatalog.scene_path("forest_grove") == "res://scenes/worlds/forest_grove.tscn", "forest scene path")
	_check(MapCatalog.scene_path("nonsense") == MapCatalog.scene_path("park"), "unknown map falls back to the first map")
	_check(MapCatalog.start_position("park") == Vector2(500, 350), "park start unchanged")
	_check(MapCatalog.is_available("park", []), "the first map is always available")
	_check(not MapCatalog.is_available("forest_grove", []), "the forest is locked at the start")
	_check(MapCatalog.is_available("forest_grove", ["park"]), "clearing the park unlocks the forest")
	_check(not MapCatalog.is_available("nonsense", ["park"]), "unknown maps are never available")
	for id in MapCatalog.ids():
		_check(ResourceLoader.exists(MapCatalog.scene_path(id)), "scene exists for %s" % id)

	# --- Cleared maps -------------------------------------------------------------
	pm._load_profile_data({})
	_check(pm.available_maps() == ["park"], "new game: only the park")
	var cleared_events: Array = []
	pm.map_cleared.connect(func(id: String): cleared_events.append(id))
	_check(not pm.mark_map_cleared("nonsense"), "cannot clear an unknown map")
	_check(pm.mark_map_cleared("park"), "clearing the park is recorded")
	_check(not pm.mark_map_cleared("park"), "clearing it again is not 'new'")
	_check(cleared_events == ["park"], "map_cleared fired once")
	_check(pm.available_maps() == ["park", "forest_grove"], "the forest is now available")
	var saved: Dictionary = pm._profile_data()
	_check(saved.get("cleared_maps", []) == ["park"], "cleared maps are saved")
	pm._load_profile_data({})
	_check(pm.cleared_maps.is_empty(), "a new game forgets cleared maps")
	pm._load_profile_data(saved)
	_check(pm.is_map_cleared("park"), "cleared maps load back")
	var old_save := saved.duplicate(true)
	old_save.erase("cleared_maps")
	pm._load_profile_data(old_save)
	_check(pm.cleared_maps.is_empty(), "an older save without the field loads fine")
	pm._load_profile_data({"cleared_maps": ["park", "park", "from_the_future"]})
	_check(pm.cleared_maps == ["park"], "unknown and duplicate map ids are dropped")
	_check(pm._is_valid_profile_fields({"cleared_maps": ["park"]}, false), "valid cleared list passes validation")
	_check(not pm._is_valid_profile_fields({"cleared_maps": "park"}, false), "non-array cleared list is rejected")
	_check(not pm._is_valid_profile_fields({"cleared_maps": [3]}, false), "non-string map ids are rejected")
	_check(pm._is_valid_expedition_data({"map_id": "forest_grove"}), "expedition map_id string is valid")
	_check(not pm._is_valid_expedition_data({"map_id": 5}), "expedition map_id must be a string")

	# --- Expedition on a map ------------------------------------------------------------
	pm._load_profile_data({})
	exp.run_active = false
	exp.begin_run()
	_check(exp.current_map_id == "park" and exp.saved_player_position == Vector2(500, 350), "default run = park with the park start")
	exp.run_active = false
	exp.begin_run("forest_grove")
	_check(exp.current_map_id == "forest_grove", "a run can start on the forest")
	_check(exp.saved_player_position == Vector2(230, 2250), "a forest run starts at the forest start (not inside a wall)")
	exp.run_active = false
	exp.begin_run("nonsense")
	_check(exp.current_map_id == "park", "an unknown map id falls back to the park")
	exp.run_active = false
	exp.begin_run("forest_grove")
	var expedition_save: Dictionary = exp.get_save_data()
	_check(expedition_save.get("map_id", "") == "forest_grove", "the map is part of the expedition save")
	exp.run_active = false
	exp.current_map_id = "park"
	exp.load_save_data(expedition_save)
	_check(exp.current_map_id == "forest_grove" and exp.run_active, "Continue restores the map")
	var legacy := expedition_save.duplicate(true)
	legacy.erase("map_id")
	exp.load_save_data(legacy)
	_check(exp.current_map_id == "park", "an old expedition save without map_id means the park")
	exp.load_save_data({"run_active": true, "map_id": "from_the_future"})
	_check(exp.current_map_id == "park", "an unknown saved map id falls back to the park")
	exp.run_active = false

	# --- Finishing a run marks the map cleared ---------------------------------------------
	pm._load_profile_data({})
	pm.debug_session = false
	exp.run_active = false
	exp.begin_run("park")
	day.current_state = day.TimeState.DAY
	exp.finish_run(false, false)
	_check(not pm.is_map_cleared("park"), "failing a run does not clear the map")
	exp.begin_run("park")
	exp.finish_run(true, false)
	_check(pm.is_map_cleared("park"), "succeeding on the park clears it")
	_check(pm.available_maps().size() == 2, "...and unlocks the next map")
	pm._load_profile_data({})
	exp.begin_run("forest_grove")
	exp.finish_run(true, false)
	_check(pm.is_map_cleared("forest_grove"), "the forest can be cleared too")

	# --- Going out ----------------------------------------------------------------------
	var requested_scenes: Array = []
	day.scene_change_override = func(path: String) -> int:
		requested_scenes.append(path)
		return OK
	pm._load_profile_data({})
	exp.run_active = false
	day.current_state = day.TimeState.DAY
	day.switch_to_night()
	await process_frame
	_check(not select.is_open(), "only one map available: no selection screen")
	_check(requested_scenes.back() == "res://scenes/worlds/night_world.tscn", "...it goes straight to the park")
	_check(exp.current_map_id == "park" and exp.run_active, "...and starts a park run")

	pm._load_profile_data({})
	pm.mark_map_cleared("park")
	exp.run_active = false
	day.current_state = day.TimeState.DAY
	requested_scenes.clear()
	day.switch_to_night()
	_check(select.is_open(), "park cleared: going out opens the selection screen")
	_check(requested_scenes.is_empty() and not exp.run_active, "...and nothing starts until a map is chosen")
	_check(inventory.ui_open, "the cat is frozen while choosing")
	var enabled := 0
	var disabled := 0
	await process_frame
	for button in select._list.get_children():
		if button.disabled:
			disabled += 1
		else:
			enabled += 1
	_check(enabled == 2 and disabled == 0, "both maps are selectable once the park is cleared")
	select.close()
	_check(not select.is_open() and not inventory.ui_open, "closing releases the cat")
	_check(not exp.run_active, "cancelling leaves the cat at home")

	# The locked entry is shown disabled while only the park is available.
	pm._load_profile_data({})
	select.open()
	await process_frame
	var states: Array = []
	for button in select._list.get_children():
		states.append(button.disabled)
	_check(states == [false, true], "locked map is listed but disabled")
	var locked_text: String = select._list.get_child(1).text
	_check(locked_text.contains("通关「公园」后开放"), "the locked entry says how to unlock it")
	select.choose("forest_grove")
	_check(select.is_open(), "a locked map cannot be chosen")
	select.close()

	# Choosing the forest.
	pm.mark_map_cleared("park")
	exp.run_active = false
	day.current_state = day.TimeState.DAY
	requested_scenes.clear()
	select.open()
	select.choose("forest_grove")
	await process_frame
	_check(requested_scenes.back() == "res://scenes/worlds/forest_grove.tscn", "choosing the forest loads the forest scene")
	_check(exp.current_map_id == "forest_grove" and exp.saved_player_position == Vector2(230, 2250), "a forest run starts at the forest start")
	_check(not select.is_open(), "the selection screen closes after choosing")

	# A run in progress always resumes its own map, whatever is asked.
	day.current_state = day.TimeState.DAY
	requested_scenes.clear()
	day.switch_to_night("park")
	await process_frame
	_check(requested_scenes.back() == "res://scenes/worlds/forest_grove.tscn", "an active run resumes its saved map")

	day.scene_change_override = Callable()
	exp.run_active = false
	day.current_state = day.TimeState.DAY

	if failures.is_empty():
		print("MAP_SYSTEM_PASSED: %d checks" % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", description)
	else:
		failures.append(description)
