extends SceneTree

var failures: Array[String] = []
var world: Node
var inventory
var quickbar
var quickbar_ui
var inventory_ui
var test_path := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var progression := root.get_node("ProgressionManager")
	inventory = root.get_node("InventoryManager")
	quickbar = root.get_node("QuickbarManager")
	var original_path: String = progression.save_path
	var original_test_mode: bool = progression._test_mode
	progression._test_mode = true
	progression._profile_save_blocked_by_newer_version = false
	inventory.clear_all()
	quickbar.clear_all()

	_check(InputMap.has_action("quickbar_1") and InputMap.has_action("quickbar_4"), "four quickbar input actions are configured")
	var has_key_one := false
	for input_event in InputMap.action_get_events("quickbar_1"):
		if input_event is InputEventKey and input_event.physical_keycode == KEY_1:
			has_key_one = true
	_check(has_key_one, "quickbar slot 1 is bound to number key 1")

	var potion = inventory.get_item_data("test_potion")
	var wood = inventory.get_item_data("wood")
	_check(potion != null and bool(potion.usable), "test potion has an explicit usable rule")
	_check(wood != null and not bool(wood.usable), "ordinary material is not implicitly usable")
	_check(inventory.get_item_data("test_potion").get_script() != null, "ItemData definitions still load without a global class_name")

	inventory.add_item("test_potion", 6)
	inventory.add_item("wood", 2)
	_check(quickbar.bind_item(0, "test_potion"), "usable item can bind to quickbar slot 1")
	_check(quickbar.get_bound_item_id(0) == "test_potion", "quickbar stores the item id")
	_check(quickbar.get_bound_item_count(0) == 6, "quickbar reads quantity from InventoryManager")
	_check(not quickbar.bind_item(1, "wood"), "non-usable material cannot bind to quickbar")
	_check(not quickbar.bind_item(1, "missing_item"), "unknown item cannot bind to quickbar")
	_check(not quickbar.bind_item(4, "test_potion"), "out-of-range quickbar slot is rejected")
	_check(quickbar.bind_item(1, "test_potion"), "same usable item may bind to a second slot")
	_check(quickbar.get_save_data().size() == 4, "quickbar save data keeps four slot ids")

	await _build_world()
	quickbar_ui = get_first_node_in_group("quickbar_ui")
	inventory_ui = get_first_node_in_group("inventory_ui")
	_check(quickbar_ui != null, "night scene contains the quickbar UI")
	_check(quickbar_ui.item_name_labels[0].text == "测试药水", "quickbar shows the bound item name")
	_check(quickbar_ui.quantity_labels[0].text == "6", "quickbar shows the live inventory quantity")

	inventory.remove_item("test_potion", 1)
	await process_frame
	_check(quickbar.get_bound_item_count(0) == 5, "removing inventory items updates the queried quantity")
	_check(quickbar_ui.quantity_labels[0].text == "5", "inventory_changed refreshes the quickbar quantity")
	inventory.add_item("test_potion", 2)
	await process_frame
	_check(quickbar_ui.quantity_labels[0].text == "7", "adding inventory items refreshes the quickbar quantity")

	var count_before: int = inventory.get_item_count("test_potion")
	quickbar_ui.activate_slot(0)
	_check(quickbar_ui.last_activation["reason"] == "item_use_not_implemented", "activation reports that item use is not implemented")
	_check(inventory.get_item_count("test_potion") == count_before, "activation does not consume the bound item")

	var quickbar_event := InputEventAction.new()
	quickbar_event.action = &"quickbar_1"
	quickbar_event.pressed = true
	var before_key_count: int = inventory.get_item_count("test_potion")
	quickbar_ui._unhandled_input(quickbar_event)
	_check(quickbar_ui.selected_slot_index == 0, "number key selects quickbar slot 1")
	_check(quickbar_ui.last_activation["reason"] == "item_use_not_implemented", "number key uses the safe activation path")
	_check(inventory.get_item_count("test_potion") == before_key_count, "number key does not consume inventory")

	var before_blocked_activation: Dictionary = quickbar_ui.last_activation.duplicate(true)
	inventory_ui.open_inventory()
	quickbar_ui._unhandled_input(quickbar_event)
	_check(quickbar_ui.last_activation == before_blocked_activation, "quickbar keys are ignored while the inventory is open")
	inventory_ui.close_inventory()

	# Bind through the inventory UI, using main's InventoryManager data layer.
	inventory_ui.open_inventory()
	inventory_ui.select_slot(0)
	_check(not inventory_ui.bind_button.disabled, "usable item enables the quickbar bind button")
	inventory_ui._on_bind_popup_id_pressed(3)
	_check(quickbar.get_bound_item_id(3) == "test_potion", "inventory UI binds the selected item to a quickbar slot")
	inventory_ui.select_slot(2)
	_check(inventory_ui.bind_button.disabled, "non-usable material leaves the bind button disabled")
	inventory_ui.close_inventory()

	# Isolated profile round-trip keeps both inventory quantities and quickbar ids.
	test_path = "user://v2_quickbar_%d.json" % Time.get_ticks_usec()
	_remove_profile_family(test_path)
	progression.save_path = test_path
	progression._test_mode = false
	progression.save_now()
	_check(FileAccess.file_exists(ProjectSettings.globalize_path(test_path)), "quickbar profile save writes the isolated file")
	progression._test_mode = true
	inventory.clear_all()
	quickbar.clear_all()
	progression._test_mode = false
	progression._load_profile()
	_check(inventory.get_item_count("test_potion") == 7, "profile reload restores quickbar item quantity")
	_check(quickbar.get_bound_item_id(0) == "test_potion" and quickbar.get_bound_item_id(3) == "test_potion", "profile reload restores quickbar bindings")
	_check(quickbar.get_bound_item_count(0) == 7, "restored quickbar reads the restored quantity")

	# Invalid quickbar payloads are rejected by profile validation.
	_check(progression._is_valid_quickbar_data(["test_potion", "", "", ""]), "valid four-slot quickbar payload passes validation")
	_check(not progression._is_valid_quickbar_data(["test_potion", 3, "", ""]), "non-string quickbar entry is invalid")
	_check(not progression._is_valid_quickbar_data(["a", "b", "c", "d", "e"]), "quickbar payload longer than four slots is invalid")

	progression._test_mode = true
	inventory.clear_all()
	quickbar.clear_all()
	progression._test_mode = original_test_mode
	progression.save_path = original_path
	_remove_profile_family(test_path)
	await _teardown_world()

	if failures.is_empty():
		print("QUICKBAR_INTEGRATION_PASSED")
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
	var player = get_first_node_in_group("player")
	player.set_physics_process(false)
	player.set_process(false)
	var combat = player.get_node("PlayerCombat")
	combat.set_process(false)
	for enemy in get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
		enemy.global_position = Vector2(1000.0, 600.0)
	await physics_frame


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
