extends SceneTree

# Herb pack: heals 2 HP, never wasted at full health, binds itself to the quickbar, and
# clearing a map gives 2 (into the chest when the backpack is full).

var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var pm = root.get_node("ProgressionManager")
	var inv = root.get_node("InventoryManager")
	var qb = root.get_node("QuickbarManager")
	var exp = root.get_node("ExpeditionManager")
	var day = root.get_node("DayManager")
	pm._test_mode = true
	pm._load_profile_data({})
	inv.clear_all()
	inv.load_storage_save_data([])
	for i in range(qb.SLOT_COUNT):
		qb.clear_slot(i)

	var item = inv.get_item_data("herb_pack")
	_check(item != null and item.usable and item.display_name == "草药包" and item.icon != null, "the herb pack item exists, is usable and has an icon")

	# auto-bind
	qb.bind_item(0, "cat_teaser")
	inv.add_item("herb_pack", 2, false)
	_check(qb.bound_item_ids[1] == "herb_pack", "a new herb pack binds itself to the first free quickbar slot")
	inv.add_item("herb_pack", 1, false)
	_check(qb.bound_item_ids.count("herb_pack") == 1, "...only once")
	qb.clear_slot(1)

	# the night scene
	exp.run_active = false
	exp.begin_run("forest_grove")
	day.current_state = day.TimeState.NIGHT
	var scene: Node2D = load("res://scenes/worlds/forest_grove.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await physics_frame
	await physics_frame
	for e in get_nodes_in_group("enemies"):
		e.set_physics_process(false)
	var cat = scene.get_node("Cat")
	var full_hp := float(cat.max_health)
	var r: Dictionary = qb.use_item("herb_pack")
	_check(r["reason"] == "health_full" and inv.get_item_count("herb_pack") == 3, "at full health nothing is used")
	cat.current_health = full_hp - 3.0
	r = qb.use_item("herb_pack")
	_check(r["handled"] and is_equal_approx(cat.current_health, full_hp - 1.0) and inv.get_item_count("herb_pack") == 2, "using one heals 2 and uses it up")
	r = qb.use_item("herb_pack")
	_check(r["handled"] and is_equal_approx(cat.current_health, full_hp) and is_equal_approx(float(r["healed"]), 1.0), "healing never goes above max health (healed %.1f)" % float(r["healed"]))
	_check(cat.heal(5.0) == 0.0, "heal() on a full cat does nothing")
	cat.dead = true
	cat.current_health = 1.0
	_check(cat.heal(2.0) == 0.0, "a fallen cat cannot be healed")
	cat.dead = false

	# stashes in the forest hold herb packs
	var herb_stashes := 0
	for spot in get_nodes_in_group("loot_spot"):
		if spot.items.has("herb_pack"):
			herb_stashes += 1
	_check(herb_stashes == 3, "three forest stashes hold a herb pack (%d)" % herb_stashes)

	# clearing a map gives two
	day.scene_change_override = func(_path: String) -> int: return OK
	inv.clear_all()
	exp.finish_run(true, false)
	_check(inv.get_item_count("herb_pack") == 2, "a successful run gives 2 herb packs")
	_check(int(exp.last_result["items_gained"].get("herb_pack", 0)) == 2 and int(exp.last_result["reward_in_storage"]) == 0, "...listed in the settlement")
	# with a full backpack they go into the chest
	exp.begin_run("forest_grove")
	inv.clear_all()
	for i in range(inv.SLOT_COUNT):
		inv.slots[i] = {"item_id": "stone", "quantity": 99}
	exp.finish_run(true, false)
	_check(inv.get_storage_item_count("herb_pack") == 2 and int(exp.last_result["reward_in_storage"]) == 2, "a full backpack sends the reward to the chest")
	# a failed run gives nothing
	exp.begin_run("forest_grove")
	inv.clear_all()
	inv.load_storage_save_data([])
	exp.finish_run(false, false)
	_check(inv.get_item_count("herb_pack") == 0 and inv.get_storage_item_count("herb_pack") == 0, "falling gives no reward")
	day.scene_change_override = Callable()

	if failures.is_empty():
		print("HERB_PACK_PASSED: %d checks" % checks)
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
