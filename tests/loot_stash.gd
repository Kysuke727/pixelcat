extends SceneTree

# Atomic backpack adds, loot-collected save state, and the LootSpot node.

var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var pm = root.get_node("ProgressionManager")
	var exp = root.get_node("ExpeditionManager")
	var inv = root.get_node("InventoryManager")
	pm._test_mode = true
	pm._load_profile_data({})
	inv.clear_all()

	# --- add_items_atomic ---------------------------------------------------------------------
	var ok: Dictionary = inv.add_items_atomic({"wood": 4, "stone": 3}, false)
	_check(ok["success"] and inv.get_item_count("wood") == 4 and inv.get_item_count("stone") == 3, "atomic add puts everything in")
	_check(not inv.add_items_atomic({}, false)["success"], "an empty request is refused")
	var bad: Dictionary = inv.add_items_atomic({"wood": 1, "no_such_item": 1}, false)
	_check(not bad["success"] and bad["reason"] == "invalid_item" and inv.get_item_count("wood") == 4, "an unknown item rolls everything back")
	_check(inv.add_items_atomic({"wood": 0}, false)["reason"] == "invalid_quantity", "a zero quantity is refused")
	# fill all slots but one with full stacks of stone; then ask for two different stacks
	inv.clear_all()
	for i in range(inv.SLOT_COUNT - 1):
		inv.slots[i] = {"item_id": "stone", "quantity": 99}
	var full: Dictionary = inv.add_items_atomic({"wood": 2, "yarn": 2}, false)
	_check(not full["success"] and full["reason"] == "inventory_full", "not enough room -> refused")
	_check(inv.get_item_count("wood") == 0 and inv.get_item_count("yarn") == 0, "...and NOTHING was added (all-or-nothing)")
	_check(inv.add_items_atomic({"wood": 5}, false)["success"], "but one stack still fits in the free slot")

	# --- loot_collected in the run state ------------------------------------------------------
	inv.clear_all()
	exp.run_active = false
	exp.begin_run("forest_grove")
	_check(not exp.is_loot_collected("stash"), "a new run has no stash taken")
	exp.mark_loot_collected("stash")
	exp.mark_loot_collected("stash")
	exp.mark_loot_collected("")
	_check(exp.run_loot_collected == ["stash"], "marking is idempotent and ignores empty ids")
	var data: Dictionary = exp.get_save_data()
	_check(data["loot_collected"] == ["stash"], "it is part of the save data")
	exp.begin_run("forest_grove")
	_check(not exp.is_loot_collected("stash"), "a new run resets it")
	exp.load_save_data(data)
	_check(exp.is_loot_collected("stash"), "loading the save restores it")
	data.erase("loot_collected")
	exp.load_save_data(data)
	_check(exp.run_loot_collected.is_empty(), "an old save without the field loads fine")
	data["loot_collected"] = ["a", "a", 7]
	exp.load_save_data(data)
	_check(exp.run_loot_collected == ["a", "7"], "duplicates are dropped and ids become strings")

	# --- the LootSpot node --------------------------------------------------------------------
	exp.run_active = false
	exp.begin_run("forest_grove")
	var spot := Area2D.new()
	spot.set_script(load("res://scripts/loot_spot.gd"))
	spot.set("loot_id", "t1")
	spot.set("items", {"yarn": 2})
	root.add_child(spot)
	await process_frame
	_check(spot.collect() and inv.get_item_count("yarn") == 2, "collect() hands over the items")
	_check(exp.is_loot_collected("t1") and not spot.collect(), "and only once")
	await create_timer(0.7).timeout
	_check(not is_instance_valid(spot), "the spot removes itself after being taken")
	# a spot that was already taken in this run vanishes on load
	var again := Area2D.new()
	again.set_script(load("res://scripts/loot_spot.gd"))
	again.set("loot_id", "t1")
	again.set("items", {"yarn": 2})
	root.add_child(again)
	await process_frame
	await process_frame
	_check(not is_instance_valid(again) or again.is_queued_for_deletion(), "a taken stash does not come back after resuming")
	_check(inv.get_item_count("yarn") == 2, "...and gives nothing again")

	if failures.is_empty():
		print("LOOT_STASH_PASSED: %d checks" % checks)
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
