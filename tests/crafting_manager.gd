extends SceneTree

var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var inventory = root.get_node("InventoryManager")
	var manager = root.get_node("CraftingManager")
	var progression = root.get_node("ProgressionManager")
	progression._test_mode = true
	inventory.clear_all()
	_check(manager.get_recipes().size() == 2, "two recipes are registered")
	_check(inventory.get_item_data("yarn") != null, "approved material yarn has a separate item id")
	_check(inventory.get_item_data("wood").icon != null, "wood has an icon")
	_check(inventory.get_item_data("stone").icon != null, "stone has an icon")
	_check(inventory.get_item_data("yarn").icon != null, "yarn has an icon")
	_check(not bool(manager.check_craft("missing_recipe", true).get("success", false)), "unknown recipe rejected")
	_check(not bool(manager.craft("craft_cat_teaser", false).get("success", false)), "bench recipe rejected in portable mode")
	inventory.add_item("yarn", 2)
	_check(bool(manager.check_craft("craft_yarn_ball", false).get("success", false)), "portable recipe is available with materials")
	var changed := [0]
	var removed := [0]
	var added := [0]
	inventory.inventory_changed.connect(func(): changed[0] += 1)
	inventory.item_removed.connect(func(_item_id: String, _qty: int): removed[0] += 1)
	inventory.item_added.connect(func(_item_id: String, _qty: int): added[0] += 1)
	var result: Dictionary = manager.craft("craft_yarn_ball", false)
	_check(bool(result.get("success", false)), "portable craft succeeds")
	_check(inventory.get_item_count("yarn") == 0 and inventory.get_item_count("yarn_ball") == 1, "ingredients deducted and output added")
	_check(changed[0] == 1 and removed[0] == 1 and added[0] == 1, "one inventory commit emits one change")
	var before: Array = inventory.get_save_data()
	result = manager.craft("craft_yarn_ball", false)
	_check(not bool(result.get("success", false)), "craft fails without materials")
	_check(inventory.get_save_data() == before, "failed craft does not mutate inventory")
	inventory.clear_all()
	inventory.add_item("wood", 2)
	inventory.add_item("yarn", 1)
	result = manager.craft("craft_cat_teaser", true)
	_check(bool(result.get("success", false)), "workbench crafts a teaser")
	_check(inventory.get_item_count("cat_teaser") == 1, "workbench output is stored")
	_check(inventory.get_item_count("wood") == 0, "workbench wood is consumed")
	var saved: Array = inventory.get_save_data()
	inventory.clear_all()
	inventory.load_save_data(saved)
	_check(inventory.get_item_count("cat_teaser") == 1, "crafted item survives inventory save roundtrip")
	inventory.clear_all()
	inventory.add_item("wood", 2400)
	before = inventory.get_save_data()
	_check(not bool(manager.craft("craft_yarn_ball", false).get("success", false)), "missing yarn with full inventory rejects craft")
	_check(inventory.get_save_data() == before, "full inventory failure leaves every slot unchanged")
	inventory.clear_all()
	inventory.add_item("wood", 99 * 23)
	inventory.add_item("yarn", 4)
	result = inventory.preview_crafting({"yarn": 1}, "cat_teaser", 1)
	_check(not bool(result.get("success", false)) and str(result.get("reason")) == "inventory_full", "full inventory refuses new output without space")
	before = inventory.get_save_data()
	result = inventory.craft_items({"yarn": 1}, "cat_teaser", 1)
	_check(not bool(result.get("success", false)), "insufficient output space rejects transaction")
	_check(inventory.get_save_data() == before, "output-space failure does not consume yarn")
	inventory.clear_all()
	inventory.add_item("yarn", 1)
	result = inventory.craft_items({"yarn": 1}, "cat_teaser", 1)
	_check(bool(result.get("success", false)), "materials removal frees slot for output")
	inventory.clear_all()
	inventory.add_item("wood", 2)
	before = inventory.get_save_data()
	_check(not bool(inventory.craft_items({"wood": -1}, "yarn", 1).get("success", false)), "invalid negative input rejected")
	_check(not bool(inventory.craft_items({"wood": 2}, "missing", 1).get("success", false)), "unknown output rejected")
	_check(inventory.get_save_data() == before, "invalid recipe leaves inventory unchanged")
	inventory.clear_all()
	progression._test_mode = false
	if failures.is_empty():
		print("DAY14_CRAFTING_PASSED: %d checks" % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		printerr("DAY14_CRAFTING_FAILED: %d failures / %d checks" % [failures.size(), checks])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", description)
	else:
		failures.append(description)
