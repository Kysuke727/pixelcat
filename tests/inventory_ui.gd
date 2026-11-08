extends SceneTree

var failures: Array[String] = []
var world: Node
var player: Node2D
var combat: Node
var ui


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var inventory := root.get_node("InventoryManager")
	inventory.clear_all()
	await _build_world()
	ui = get_first_node_in_group("inventory_ui")
	_check(ui != null, "night scene contains the inventory UI")
	_check(not ui.is_open, "inventory starts closed")
	_check(not ui.get_node("Root").visible, "inventory root starts hidden")
	_check(not inventory.ui_open, "manager reports inventory closed")

	_check(InputMap.has_action("toggle_inventory"), "I inventory input action is configured")
	var has_i_key := false
	for input_event in InputMap.action_get_events("toggle_inventory"):
		if input_event is InputEventKey and input_event.physical_keycode == KEY_I:
			has_i_key = true
	_check(has_i_key, "toggle_inventory is bound to I")

	# Empty backpack still renders normally.
	ui.open_inventory()
	_check(ui.is_open and ui.get_node("Root").visible, "open_inventory shows the panel")
	_check(inventory.ui_open, "opening the panel marks the manager as open")
	_check(ui.detail_description.text.contains("空"), "empty backpack shows an empty-state description")
	ui.close_inventory()
	_check(not ui.is_open and not ui.get_node("Root").visible, "close_inventory hides the panel")
	_check(not inventory.ui_open, "closing the panel clears the manager flag")

	# Populated grid, names, quantities and description.
	inventory.add_item("yarn_ball", 3)
	ui.open_inventory()
	_check(ui.inventory_slots[0].get_item_id() == "yarn_ball", "first slot receives the added item")
	_check(ui.inventory_slots[0].get_node("VBox/NameLabel").text == "毛线球", "slot shows the display name")
	_check(ui.inventory_slots[0].get_node("VBox/QuantityLabel").text == "×3", "slot shows the stack quantity")
	ui.select_slot(0)
	_check(ui.detail_name.text == "毛线球", "selecting a slot shows the item name")
	_check(ui.detail_type.text == "材料", "selecting a slot shows the item type")
	_check(ui.detail_description.text.contains("二级合成材料"), "selecting a slot shows its description")
	_check(ui.detail_quantity.text.contains("3"), "detail panel shows the selected quantity")

	inventory.add_item("yarn_ball", 2)
	await process_frame
	_check(ui.inventory_slots[0].get_node("VBox/QuantityLabel").text == "×5", "quantity changes refresh the slot immediately")

	# UI state blocks combat and movement input penetration.
	ui.close_inventory()
	_check(combat._can_start_action(), "combat is available while the inventory is closed")
	ui.open_inventory()
	_check(not combat._can_start_action(), "combat actions are blocked while the inventory is open")
	Input.action_press("move_right")
	player._physics_process(0.1)
	Input.action_release("move_right")
	_check(player.velocity == Vector2.ZERO, "player movement is frozen while the inventory is open")
	ui.close_inventory()

	# I and Esc toggle handling.
	var toggle_event := InputEventAction.new()
	toggle_event.action = &"toggle_inventory"
	toggle_event.pressed = true
	ui._unhandled_input(toggle_event)
	_check(ui.is_open, "toggle_inventory event opens the panel")
	var cancel_event := InputEventAction.new()
	cancel_event.action = &"ui_cancel"
	cancel_event.pressed = true
	ui._unhandled_input(cancel_event)
	_check(not ui.is_open, "ui_cancel closes the panel")

	# Empty state again after removing the item through the data API.
	inventory.clear_all()
	await process_frame
	ui.open_inventory()
	_check(ui.inventory_slots[0].get_item_id() == "", "slots clear after the inventory is emptied")
	_check(ui.detail_description.text.contains("空"), "emptying the inventory restores the empty-state text")
	ui.close_inventory()

	await _teardown_world()

	if failures.is_empty():
		print("INVENTORY_UI_PASSED")
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
	player.set_physics_process(false)
	player.set_process(false)
	combat.set_process(false)
	player.global_position = Vector2(500.0, 350.0)
	for enemy in get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
		enemy.global_position = Vector2(960.0, 660.0)
	await physics_frame


func _teardown_world() -> void:
	if is_instance_valid(world):
		current_scene = null
		world.queue_free()
		await process_frame
		await process_frame


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		failures.append(description)
