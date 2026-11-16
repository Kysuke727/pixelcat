extends SceneTree

# Multi-craft (manager) + crafting UX (quantity, ordering, mode, audio preview).

var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var progression = root.get_node("ProgressionManager")
	progression._test_mode = true
	var inventory = root.get_node("InventoryManager")
	var crafting = root.get_node("CraftingManager")
	inventory.clear_all()

	# --- Manager -----------------------------------------------------------
	inventory.add_item("yarn", 7, false)
	_check(crafting.get_max_craftable("craft_yarn_ball", false) == 3, "7 yarn allows 3 yarn balls")
	_check(crafting.get_max_craftable("craft_cat_teaser", true) == 0, "no teaser materials means max 0")
	_check(crafting.get_max_craftable("craft_cat_teaser", false) == 0, "locked recipe has max 0 away from the workbench")
	var preview: Dictionary = crafting.check_craft("craft_yarn_ball", false, 3)
	_check(bool(preview.get("success", false)), "previewing 3 crafts succeeds")
	_check(inventory.get_item_count("yarn") == 7, "preview does not consume")
	_check(not bool(crafting.check_craft("craft_yarn_ball", false, 4).get("success", false)), "4 crafts need 8 yarn and fail")
	_check(not bool(crafting.check_craft("craft_yarn_ball", false, 0).get("success", false)), "zero crafts is invalid")
	var result: Dictionary = crafting.craft("craft_yarn_ball", false, 3)
	_check(bool(result.get("success", false)) and int(result.get("quantity", 0)) == 3, "crafting 3 yields 3 balls")
	_check(inventory.get_item_count("yarn") == 1, "3 crafts consumed 6 yarn")
	_check(inventory.get_item_count("yarn_ball") == 3, "3 balls added")
	var failed: Dictionary = crafting.craft("craft_yarn_ball", false, 2)
	_check(not bool(failed.get("success", false)), "crafting more than materials allow fails")
	_check(inventory.get_item_count("yarn") == 1 and inventory.get_item_count("yarn_ball") == 3, "failed batch changes nothing (atomic)")

	# Output room limits the batch. Fill all 24 slots with stone, free two, then
	# hold 50 yarn in one of them: that leaves exactly ONE empty slot, and a slot
	# holds at most 5 yarn balls (max stack), so the cap must be 5 - not the 25
	# the materials alone would allow.
	inventory.clear_all()
	for i in range(24):
		inventory.add_item("stone", 99, false)
	inventory.remove_item("stone", 99)
	inventory.remove_item("stone", 99)
	inventory.add_item("yarn", 50, false)
	_check(inventory.get_empty_slot_count() == 1, "test setup leaves exactly one free slot")
	var cap: int = crafting.get_max_craftable("craft_yarn_ball", false)
	_check(cap == 5, "one free slot caps the batch at one stack of 5 (got %d)" % cap)
	_check(bool(crafting.check_craft("craft_yarn_ball", false, 5).get("success", false)), "the reported max really is craftable")
	_check(not bool(crafting.check_craft("craft_yarn_ball", false, 6).get("success", false)), "one above the reported max fails")
	inventory.clear_all()

	# --- UI ----------------------------------------------------------------
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	inventory.clear_all()
	var ui = scene.get_node("CraftingUI")
	inventory.add_item("yarn", 7, false)
	ui.open_crafting(false)
	await process_frame
	_check(ui.title_label.text.contains("随身") and ui.badge_label.text == "随身", "portable mode is labelled")
	_check(ui._selected_recipe == "craft_yarn_ball", "craftable recipe is selected first")
	_check(ui._times == 1 and ui.quantity_label.text == "1", "quantity starts at 1")
	_check(ui.minus_button.disabled and not ui.plus_button.disabled, "minus disabled at 1, plus enabled")
	ui._change_quantity(1)
	_check(ui._times == 2 and ui.craft_button.text == "制作 ×2", "plus raises quantity and button label")
	ui._set_max_quantity()
	_check(ui._times == 3 and ui.plus_button.disabled, "max sets 3 and disables plus")
	ui._change_quantity(5)
	_check(ui._times == 3, "quantity cannot exceed the craftable maximum")
	ui._craft_selected()
	_check(inventory.get_item_count("yarn_ball") == 3 and inventory.get_item_count("yarn") == 1, "UI batch craft goes through CraftingManager")
	_check(ui.status_label.text.contains("制作成功"), "success message shown")
	_check(ui._times == 1, "quantity clamps back down after materials run out")
	ui._select_recipe("craft_cat_teaser")
	_check(ui._times == 1, "selecting a recipe resets quantity")
	ui.close_crafting()

	# Ordering: at the workbench a craftable teaser must sort ahead of an unaffordable ball.
	inventory.clear_all()
	inventory.add_item("wood", 2, false)
	inventory.add_item("yarn_ball", 1, false)
	ui.open_crafting(true)
	await process_frame
	var ordered: Array = ui._sorted_recipes()
	_check(str(ordered[0].recipe_id) == "craft_cat_teaser", "craftable recipe sorts first")
	_check(ui.badge_label.text == "工作台" and ui.title_label.text.contains("手工屋"), "workbench mode is labelled")
	_check(ui.panel.theme_type_variation == &"WorkbenchPanel", "workbench uses its own panel style")
	ui.close_crafting()
	inventory.clear_all()
	inventory.add_item("yarn", 2, false)
	ui.open_crafting(false)
	await process_frame
	var portable_order: Array = ui._sorted_recipes()
	_check(str(portable_order[0].recipe_id) == "craft_yarn_ball" and str(portable_order[1].recipe_id) == "craft_cat_teaser", "locked recipes sort last")
	ui.close_crafting()

	# Audio hooks: empty slots are silent and must never error.
	ui._play(null)
	_check(true, "empty sound slot is a safe no-op")

	# Audition scene boots with materials and an open crafting UI.
	var preview_scene = load("res://scenes/dev/crafting_audio_preview.tscn").instantiate()
	root.add_child(preview_scene)
	await process_frame
	_check(preview_scene.crafting_ui.is_open(), "audio preview opens the crafting UI")
	_check(inventory.get_item_count("wood") == 40, "audio preview provides materials")

	if failures.is_empty():
		print("CRAFTING_MULTI_PASSED: %d checks" % checks)
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
