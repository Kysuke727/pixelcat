extends SceneTree

# The home storage chest: transfers, safety from the death penalty, save/load, UI.

var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var pm = root.get_node("ProgressionManager")
	var inv = root.get_node("InventoryManager")
	var exp = root.get_node("ExpeditionManager")
	pm._test_mode = true
	pm._load_profile_data({})
	inv.clear_all()
	_check(inv.STORAGE_SLOT_COUNT == 56 and inv.storage_slots.size() == 56, "the chest has 56 slots")

	inv.add_item("wood", 30, false)
	inv.add_item("yarn", 5, false)
	var r: Dictionary = inv.transfer("wood", 10, true, false)
	_check(r["moved"] == 10 and inv.get_item_count("wood") == 20 and inv.get_storage_item_count("wood") == 10, "store 10 wood")
	r = inv.transfer("wood", 999, true, false)
	_check(r["moved"] == 20 and inv.get_item_count("wood") == 0 and inv.get_storage_item_count("wood") == 30, "store all the rest")
	r = inv.transfer("wood", 5, true, false)
	_check(r["moved"] == 0 and r["reason"] == "none_to_move", "nothing left to store")
	r = inv.transfer("wood", 12, false, false)
	_check(r["moved"] == 12 and inv.get_item_count("wood") == 12 and inv.get_storage_item_count("wood") == 18, "take 12 back")
	_check(inv.transfer("nope", 1, true, false)["reason"] == "invalid_item", "unknown item refused")

	# a full backpack only takes what fits
	inv.clear_all()
	for i in range(inv.SLOT_COUNT - 1):
		inv.slots[i] = {"item_id": "stone", "quantity": 99}
	inv.storage_slots[0] = {"item_id": "wood", "quantity": 99}
	inv.storage_slots[1] = {"item_id": "wood", "quantity": 99}
	r = inv.transfer("wood", 150, false, false)
	_check(r["moved"] == 99 and r["reason"] == "full", "a nearly full backpack takes one stack only (%d)" % r["moved"])
	_check(inv.get_storage_item_count("wood") == 99 and inv.get_item_count("wood") == 99, "nothing was lost or duplicated")
	r = inv.transfer("wood", 5, false, false)
	_check(r["moved"] == 0 and r["reason"] == "full", "a full backpack takes nothing")

	# death only costs the backpack
	inv.clear_all()
	inv.load_storage_save_data([])
	inv.add_item("wood", 40, false)
	inv.transfer("wood", 20, true, false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var loss: Dictionary = inv.apply_death_loss(rng)
	_check(inv.get_storage_item_count("wood") == 20, "the chest is untouched by dying")
	_check(inv.get_item_count("wood") == 20 - int(loss["lost_total"]), "the backpack lost items")

	# save / load
	inv.clear_all()
	inv.load_storage_save_data([])
	inv.add_item("yarn", 7, false)
	inv.transfer("yarn", 7, true, false)
	var storage_data: Array = inv.get_storage_save_data()
	inv.clear_all()
	_check(inv.get_storage_item_count("yarn") == 7, "clear_all (backpack) leaves the chest alone")
	inv.load_storage_save_data(storage_data)
	_check(inv.get_storage_item_count("yarn") == 7, "storage save data round-trips")
	inv.load_storage_save_data([])
	_check(inv.get_storage_item_count("yarn") == 0, "an old save without a chest loads an empty chest")
	inv.load_storage_save_data([{"item_id": "bogus", "quantity": 3}, {"item_id": "wood", "quantity": -4}, 5, {"item_id": "wood", "quantity": 8}])
	_check(inv.get_storage_item_count("wood") == 8 and inv.get_storage_item_count("bogus") == 0, "bad entries are skipped when loading")
	_check(pm._is_valid_inventory_data(storage_data, 56 * 4), "profile validation accepts a chest")
	_check(not pm._is_valid_inventory_data([{"item_id": "wood"}], 56 * 4), "...and rejects a malformed one")

	# the home scene
	inv.clear_all()
	inv.load_storage_save_data([{"item_id": "stone", "quantity": 6}])
	inv.add_item("yarn", 3, false)
	exp.run_active = false
	var home: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(home)
	current_scene = home
	await process_frame
	await process_frame
	var chest: Node = home.get_node("World/StorageChest")
	var ui: Node = home.get_node("StorageUI")
	_check(chest != null and ui.is_in_group("storage_ui"), "the home has a chest and a storage screen")
	var cat: Node2D = home.get_node("World/Cat") if home.has_node("World/Cat") else home.get_node_or_null("Cat")
	_check(cat != null, "found the cat")
	cat.global_position = chest.global_position
	await physics_frame
	await physics_frame
	await physics_frame
	_check(chest.cat_nearby != null, "standing at the chest registers it")
	chest.interact()
	_check(ui.is_open and inv.ui_open, "pressing E at the chest opens the storage screen (and blocks the cat)")
	ui._on_slot_clicked(0, false)
	_check(ui.selected_item_id == "yarn", "click selects the item")
	ui._move(1)
	_check(inv.get_item_count("yarn") == 2 and inv.get_storage_item_count("yarn") == 1, "the button moves one yarn into the chest")
	ui._on_slot_clicked(0, true)
	_check(ui.selected_item_id == "stone", "chest side selects too")
	ui._move(999)
	_check(inv.get_storage_item_count("stone") == 0 and inv.get_item_count("stone") == 6, "all stone comes back")
	_check(ui.selected_index == -1, "selection clears when the stack is gone")
	ui.close_storage()
	_check(not ui.is_open and not inv.ui_open, "closing releases the cat")

	if failures.is_empty():
		print("STORAGE_CHEST_PASSED: %d checks" % checks)
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
