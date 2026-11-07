extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var pm := root.get_node("ProgressionManager")
	var day := root.get_node("DayManager")
	var expedition := root.get_node("ExpeditionManager")
	pm.save_path = "user://pixelcat_menu_flow_test.json"
	var path := ProjectSettings.globalize_path(pm.save_path)
	for candidate in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)
	var menu: Control = load("res://scenes/menu/main_menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	var cont: Button = menu.get_node("MenuPanel/MenuButtons/ContinueButton")
	assert(cont.disabled, "Continue should be unavailable without saves")
	print("MENU_PASS: no save disables continue")
	assert(not pm.has_saved_game())
	menu.get_node("MenuPanel/MenuButtons/NewGameButton2").emit_signal("pressed")
	await scene_changed
	await process_frame
	assert(current_scene.scene_file_path == "res://scenes/main.tscn", "New game should enter day scene")
	assert(pm.level == 1 and not expedition.run_active)
	await create_timer(0.3).timeout
	assert(pm.has_saved_game(), "New game should create save")
	print("MENU_PASS: new game enters day and creates save")
	pm.level = 4
	pm.save_now()
	var saved: Dictionary = pm._read_profile_payload(path)
	assert(int(saved["profile"]["level"]) == 4)
	pm._load_profile()
	var next_menu: Control = load("res://scenes/menu/main_menu.tscn").instantiate()
	current_scene.queue_free()
	root.add_child(next_menu)
	current_scene = next_menu
	await process_frame
	assert(not next_menu.get_node("MenuPanel/MenuButtons/ContinueButton").disabled)
	print("MENU_PASS: valid save enables continue")
	next_menu.get_node("MenuPanel/MenuButtons/ContinueButton").emit_signal("pressed")
	await scene_changed
	await process_frame
	assert(current_scene.scene_file_path == "res://scenes/main.tscn")
	assert(pm.level == 4, "Continue should restore saved progression")
	print("MENU_PASS: continue enters day scene with saved level")
	# Simulate a persisted, ongoing night expedition and return to the menu.
	expedition.begin_run()
	day.current_state = day.TimeState.NIGHT
	pm.save_now()
	var menu_night: Control = load("res://scenes/menu/main_menu.tscn").instantiate()
	current_scene.queue_free()
	root.add_child(menu_night)
	current_scene = menu_night
	await process_frame
	var before := FileAccess.get_file_as_string(path)
	pm._save_profile()
	assert(FileAccess.get_file_as_string(path) == before, "Menu should not overwrite saved data")
	print("MENU_PASS: idle menu leaves save untouched")
	menu_night.get_node("MenuPanel/MenuButtons/ContinueButton").emit_signal("pressed")
	await scene_changed
	await process_frame
	assert(current_scene.scene_file_path == "res://scenes/worlds/night_world.tscn", "Continue should resume the night")
	assert(expedition.run_active)
	print("MENU_PASS: continue resumes night expedition")
	# Returning to menu and starting new game must ask for confirmation first.
	var menu_confirm: Control = load("res://scenes/menu/main_menu.tscn").instantiate()
	current_scene.queue_free()
	root.add_child(menu_confirm)
	current_scene = menu_confirm
	await process_frame
	menu_confirm.get_node("MenuPanel/MenuButtons/NewGameButton2").emit_signal("pressed")
	assert(menu_confirm.confirmation.visible, "Existing save must require confirmation")
	assert(pm.level == 4 and expedition.run_active, "Prompt must preserve existing state")
	print("MENU_PASS: new game requires confirmation and preserves old state")
	menu_confirm.confirmation.emit_signal("confirmed")
	await scene_changed
	await create_timer(0.3).timeout
	assert(current_scene.scene_file_path == "res://scenes/main.tscn")
	assert(pm.level == 1 and not expedition.run_active)
	assert(pm.has_saved_game())
	print("MENU_PASS: confirmed new game resets state and saves")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".bak")
	print("MENU_FLOW_PASSED")
	quit(0)
