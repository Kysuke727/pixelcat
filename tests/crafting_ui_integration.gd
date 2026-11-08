extends SceneTree

var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var progression = root.get_node("ProgressionManager")
	progression._test_mode = true
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var inventory = root.get_node("InventoryManager")
	var inventory_ui = scene.get_node("InventoryUI")
	var crafting = scene.get_node("CraftingUI")
	var bench = scene.get_node("World/CraftingWorkbench")
	_check(crafting != null and bench != null, "day scene contains shared crafting UI and workbench")
	_check(not crafting.is_open(), "crafting overlay starts closed")
	inventory_ui.open_inventory()
	_check(inventory_ui.is_open and inventory.ui_open, "inventory uses existing input lock")
	inventory_ui._on_craft_button_pressed()
	_check(crafting.is_open() and not inventory_ui.is_open, "inventory craft tab opens portable crafting")
	_check(not crafting._at_workbench and inventory.ui_open, "portable crafting preserves movement lock")
	_check(crafting.craft_button.disabled, "empty-inventory recipe is not craftable")
	crafting.close_crafting(true)
	_check(inventory_ui.is_open and not crafting.is_open(), "back button returns to inventory")
	inventory_ui.close_inventory()
	_check(not inventory.ui_open, "closing all menus releases movement lock")
	var cat = scene.get_node("Cat")
	bench.cat_nearby = cat
	bench.interact()
	_check(crafting.is_open() and crafting._at_workbench, "E workbench interaction enables workbench recipe mode")
	_check(inventory.ui_open, "workbench crafting locks movement and combat")
	crafting._select_recipe("craft_cat_teaser")
	_check(crafting._selected_recipe == "craft_cat_teaser", "advanced recipe selectable at workbench")
	crafting.close_crafting()
	_check(not inventory.ui_open, "workbench close releases movement lock")
	var yarn_pickup = scene.get_node("World/MaterialPickupYarn")
	var wood_pickup = scene.get_node("World/MaterialPickupWood")
	var stone_pickup = scene.get_node("World/MaterialPickupStone")
	for pickup in [yarn_pickup, wood_pickup, stone_pickup]:
		pickup.cat_nearby = cat
		pickup.interact()
	_check(inventory.get_item_count("yarn") == 5, "day prototype pickup grants yarn")
	_check(inventory.get_item_count("wood") == 5, "day prototype pickup grants wood")
	_check(inventory.get_item_count("stone") == 5, "day prototype pickup grants stone")
	await process_frame
	_check(not is_instance_valid(yarn_pickup), "collected pickup is removed from scene")
	inventory.clear_all()
	scene.queue_free()
	await process_frame
	if failures.is_empty():
		print("DAY14_CRAFTING_SCENES_PASSED: %d checks" % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		printerr("DAY14_CRAFTING_SCENES_FAILED: %d failures / %d checks" % [failures.size(), checks])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", description)
	else:
		failures.append(description)
