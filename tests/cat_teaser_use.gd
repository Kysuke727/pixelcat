extends SceneTree

var failures: Array[String] = []
var assertions := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var progress = root.get_node("ProgressionManager")
	progress._test_mode = true
	var inventory = root.get_node("InventoryManager")
	var quickbar = root.get_node("QuickbarManager")
	inventory.clear_all()
	quickbar.clear_all()
	var cat_scene = load("res://scenes/player/cat.tscn")
	var player: Node2D = cat_scene.instantiate()
	root.add_child(player)
	await process_frame
	var stats = player.get_node("Stats")
	stats.mood = 50
	inventory.add_item("cat_teaser", 3)
	_check(quickbar.bind_item(0, "cat_teaser"), "consumable teaser can bind quickbar")
	_check(not quickbar.bind_item(1, "yarn_ball"), "tier-two yarn material cannot be equipped")
	_check(not quickbar.bind_item(2, "yarn"), "raw yarn cannot be equipped")
	var result: Dictionary = quickbar.activate_slot(0)
	_check(bool(result.get("handled", false)), "quickbar uses teaser")
	_check(result.get("reason", "") == "used_cat_teaser", "quickbar reports item-use success")
	_check(is_equal_approx(float(stats.mood), 70.0), "one teaser adds exactly 20 mood")
	_check(inventory.get_item_count("cat_teaser") == 2, "one use consumes exactly one teaser")
	stats.mood = 95.0
	result = quickbar.activate_slot(0)
	_check(bool(result.get("handled", false)), "teaser can be used with partially full mood")
	_check(is_equal_approx(float(stats.mood), 100.0), "mood cannot exceed 100")
	_check(inventory.get_item_count("cat_teaser") == 1, "partial overflow still costs one teaser")
	result = quickbar.activate_slot(0)
	_check(result.get("reason", "") == "mood_full", "full mood reports an understandable reason")
	_check(inventory.get_item_count("cat_teaser") == 1, "full mood never consumes teaser")
	_check(is_equal_approx(float(stats.mood), 100.0), "full mood stays unchanged")
	stats.mood = 30.0
	result = quickbar.use_item("cat_teaser")
	_check(bool(result.get("handled", false)), "inventory detail uses same item effect")
	_check(is_equal_approx(float(stats.mood), 50.0), "inventory usage also grants 20 mood")
	_check(inventory.get_item_count("cat_teaser") == 0, "third teaser consumed correctly")
	_check(quickbar.activate_slot(0).get("reason", "") == "out_of_stock", "empty quickbar slot cannot consume")
	_check(not bool(quickbar.use_item("yarn_ball").get("handled", false)), "tier-two yarn material remains non-usable")
	_check(quickbar.use_item("test_potion").get("reason", "") == "out_of_stock", "missing test potion reports out of stock")
	player.queue_free()
	await process_frame
	result = quickbar.use_item("cat_teaser")
	_check(result.get("reason", "") == "out_of_stock", "no stock is rejected even without player")
	quickbar.clear_all()
	inventory.clear_all()
	if failures.is_empty():
		print("CAT_TEASER_USE_PASSED: %d checks" % assertions)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		printerr("CAT_TEASER_USE_FAILED: %d" % failures.size())
		quit(1)


func _check(condition: bool, description: String) -> void:
	assertions += 1
	if not condition:
		failures.append(description)
