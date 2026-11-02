extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var inventory := root.get_node("InventoryManager")
	inventory.clear_all()
	_check(inventory.get_slot_count() == 24, "inventory exposes 24 fixed slots")
	_check(inventory.get_empty_slot_count() == 24, "empty inventory has 24 empty slots")
	_check(inventory.get_item_count("yarn_ball") == 0, "empty inventory reports zero item count")

	var added_events: Array = []
	var changed_events: Array = []
	inventory.item_added.connect(func(item_id: String, quantity: int) -> void: added_events.append([item_id, quantity]))
	inventory.inventory_changed.connect(func() -> void: changed_events.append(true))

	var add_result: Dictionary = inventory.add_item("yarn_ball", 12)
	_check(add_result["success"] and int(add_result["added"]) == 12, "adding 12 yarn balls succeeds")
	_check(inventory.get_item_count("yarn_ball") == 12, "stacked inventory reports all 12 yarn balls")
	_check(int(inventory.get_slot(0)["quantity"]) == 5, "first yarn stack respects max_stack 5")
	_check(int(inventory.get_slot(1)["quantity"]) == 5, "second yarn stack respects max_stack 5")
	_check(int(inventory.get_slot(2)["quantity"]) == 2, "remainder goes into a third stack")
	_check(added_events.size() == 1 and int(added_events[0][1]) == 12, "one add call emits one item_added event")
	_check(changed_events.size() == 1, "one add call emits one inventory_changed event")
	_check(inventory.has_item("yarn_ball", 12), "has_item checks the total across stacks")
	_check(not inventory.has_item("yarn_ball", 13), "has_item rejects a quantity above the total")

	added_events.clear()
	changed_events.clear()
	var invalid_quantity: Dictionary = inventory.add_item("yarn_ball", -1)
	_check(not invalid_quantity["success"] and invalid_quantity["reason"] == "invalid_quantity", "negative add quantity is rejected")
	var zero_quantity: Dictionary = inventory.add_item("yarn_ball", 0)
	_check(not zero_quantity["success"] and zero_quantity["reason"] == "invalid_quantity", "zero add quantity is rejected")
	var invalid_id: Dictionary = inventory.add_item("missing_item", 2)
	_check(not invalid_id["success"] and invalid_id["reason"] == "invalid_item", "unknown item id is rejected")
	_check(inventory.get_item_count("yarn_ball") == 12, "rejected adds do not change item count")
	_check(added_events.is_empty() and changed_events.is_empty(), "rejected adds do not emit settlement events")

	var remove_result: Dictionary = inventory.remove_item("yarn_ball", 6)
	_check(remove_result["success"] and int(remove_result["removed"]) == 6, "removing six yarn balls succeeds")
	_check(inventory.get_item_count("yarn_ball") == 6, "remove keeps the remaining yarn count exact")
	var too_many: Dictionary = inventory.remove_item("yarn_ball", 7)
	_check(not too_many["success"] and too_many["reason"] == "insufficient_quantity", "removing more than owned is rejected")
	_check(inventory.get_item_count("yarn_ball") == 6, "rejected removal leaves the inventory untouched")
	var invalid_remove: Dictionary = inventory.remove_item("missing_item", 1)
	_check(not invalid_remove["success"] and invalid_remove["reason"] == "invalid_item", "removing an unknown item is rejected")

	# Save round-trip keeps stacks and empty slots.
	inventory.add_item("wood", 3)
	var saved: Array = inventory.get_save_data()
	_check(saved.size() == 24, "save data contains all 24 slots")
	inventory.clear_all()
	_check(inventory.get_item_count("yarn_ball") == 0 and inventory.get_item_count("wood") == 0, "clear_all empties the inventory")
	inventory.load_save_data(saved)
	_check(inventory.get_item_count("yarn_ball") == 6, "save round-trip restores yarn count")
	_check(inventory.get_item_count("wood") == 3, "save round-trip restores wood count")

	# Defensive loading: unknown ids, negative, malformed and over-stacked entries.
	inventory.load_save_data([
		{"item_id": "yarn_ball", "quantity": 99},
		{"item_id": "missing_item", "quantity": 4},
		{"item_id": "wood", "quantity": -2},
		{"item_id": "stone", "quantity": 1.5},
		"not a slot",
		{"item_id": "", "quantity": 5},
	])
	_check(inventory.get_item_count("yarn_ball") == 99, "over-stacked save entry is split across slots")
	_check(inventory.get_item_count("wood") == 0, "negative save entry is ignored")
	_check(inventory.get_item_count("stone") == 0, "fractional save entry is ignored")
	_check(inventory.get_item_count("missing_item") == 0, "unknown save item id is ignored")
	_check(inventory.get_item_count("yarn_ball") <= 24 * 5, "loaded inventory never exceeds slot capacity")

	inventory.clear_all()
	inventory.load_save_data([])
	_check(inventory.get_empty_slot_count() == 24, "empty save data restores an empty inventory")

	inventory.clear_all()
	var full_result: Dictionary = inventory.add_item("wood", 2400)
	_check(not full_result["success"] and int(full_result["remaining"]) > 0, "adding beyond 24 stacks reports the remainder")
	_check(inventory.get_item_count("wood") == 24 * 99, "full inventory holds exactly 24 max stacks")
	_check(inventory.get_empty_slot_count() == 0, "full inventory has no empty slots left")
	var rejected_when_full: Dictionary = inventory.add_item("stone", 1)
	_check(not rejected_when_full["success"] and rejected_when_full["reason"] == "inventory_full", "new item is rejected when every slot is full")
	inventory.clear_all()

	if failures.is_empty():
		print("INVENTORY_MANAGER_PASSED")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		quit(1)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		failures.append(description)
