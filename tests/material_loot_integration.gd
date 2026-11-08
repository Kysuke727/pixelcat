extends SceneTree

const Loot := preload("res://scripts/material_loot.gd")
const PICKUP := preload("res://scenes/pickups/material_drop_pickup.tscn")
var failures: Array[String] = []
var assertions := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Prevent the project main scene and real enemies from fighting the fake test player.
	if current_scene != null:
		var live_scene := current_scene
		current_scene = null
		live_scene.queue_free()
		await process_frame
	var progress = root.get_node("ProgressionManager")
	progress._test_mode = true
	var inventory = root.get_node("InventoryManager")
	var exp = root.get_node("ExpeditionManager")
	inventory.clear_all()
	_check(Loot.count_from_roll(0.0) == 1 and Loot.count_from_roll(0.49999) == 1, "50% tier boundary")
	_check(Loot.count_from_roll(0.5) == 2 and Loot.count_from_roll(0.79999) == 2, "30% tier boundary")
	_check(Loot.count_from_roll(0.8) == 3 and Loot.count_from_roll(0.89999) == 3, "10% tier-3 boundary")
	_check(Loot.count_from_roll(0.9) == 4 and Loot.count_from_roll(0.99999) == 4, "10% tier-4 boundary")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261108
	var counts := [0, 0, 0, 0]
	var item_counts := {"yarn": 0, "stone": 0, "wood": 0}
	for _i in range(12000):
		var rolled: Array[String] = Loot.roll_material_ids(rng)
		_check_silent(rolled.size() >= 1 and rolled.size() <= 4, "1-4 material drops guaranteed")
		counts[rolled.size() - 1] += 1
		for id in rolled:
			_check_silent(item_counts.has(id), "only allowed material ids")
			item_counts[id] += 1
	var expected := [0.5, 0.3, 0.1, 0.1]
	for i in range(4):
		_check(absf(float(counts[i]) / 12000.0 - expected[i]) < 0.025, "weighted count tier %d ~ %f" % [i + 1, expected[i]])
	var total := 0
	for value in item_counts.values():
		total += int(value)
	for id in item_counts:
		_check(absf(float(item_counts[id]) / float(total) - 1.0 / 3.0) < 0.025, "%s type is ~1/3" % id)
	_check(Loot.count_from_roll(-0.1) == 0 and Loot.count_from_roll(1.0) == 0, "invalid count roll rejected")

	# Wait for DayManager startup resume callback before activating the isolated run.
	await create_timer(0.35).timeout
	if current_scene != null:
		var scene_after_resume := current_scene
		current_scene = null
		scene_after_resume.queue_free()
		await process_frame
	# One enemy death sets saved pending material drops before spawning.
	exp.begin_run()
	var records: Array[Dictionary] = []
	for i in range(3):
		records.append({"id": "SlimeTest:material:%d" % i, "item_id": ["yarn", "stone", "wood"][i],
			"amount": 1, "position": [float(i * 20), 50.0]})
	var objective_ids: Array[String] = ["SlimeTest"]
	exp.set_objectives(objective_ids)
	var empty_fish_drops: Array[Dictionary] = []
	exp.complete_enemy_with_drops("SlimeTest", 0, empty_fish_drops, records)
	_check(exp.material_drops.size() == 3, "enemy drops registered before pickup")
	_check(exp.defeated_enemy_ids.has("SlimeTest"), "enemy completion and drops committed together")
	var snapshot: Dictionary = exp.get_save_data().duplicate(true)
	exp.load_save_data(snapshot)
	_check(exp.material_drops.size() == 3, "pending drops survive save/load")
	exp.complete_enemy_with_drops("SlimeTest", 0, empty_fish_drops, records)
	_check(exp.material_drops.size() == 3, "replayed enemy completion cannot duplicate drops")
	_check(progress._is_valid_expedition_data(snapshot), "material drop save payload is valid")
	var corrupt: Dictionary = snapshot.duplicate(true)
	corrupt["material_drops"]["SlimeTest:material:0"]["item_id"] = "unknown_material"
	_check(not progress._is_valid_expedition_data(corrupt), "unknown material id in save rejected")
	exp.load_save_data(snapshot)
	_check(exp.collect_saved_material_drop("SlimeTest:material:0"), "pending yarn can be collected")
	_check(inventory.get_item_count("yarn") == 1, "collected item enters inventory")
	_check(not exp.collect_saved_material_drop("SlimeTest:material:0"), "same drop cannot be claimed twice")
	_check(not exp.material_drops.has("SlimeTest:material:0"), "claimed record removed from pending list")
	_check(exp.get_save_data()["material_drops"].size() == 2, "save stores only unclaimed drops")
	# A full bag must not silently destroy material or mark it collected.
	inventory.clear_all()
	inventory.add_item("wood", 99 * 23)
	inventory.add_item("yarn", 99)
	var before: Array = inventory.get_save_data()
	_check(not exp.collect_saved_material_drop("SlimeTest:material:1"), "stone pickup blocked by full bag")
	_check(inventory.get_save_data() == before, "full-bag rejection changes no item")
	_check(exp.material_drops.has("SlimeTest:material:1"), "full-bag rejection leaves pickup pending")
	inventory.remove_item("wood", 99)
	_check(exp.collect_saved_material_drop("SlimeTest:material:1"), "pending pickup can be claimed after freeing slot")
	_check(inventory.get_item_count("stone") == 1, "stone material enters inventory")
	inventory.remove_item("wood", 1)
	var pickup = PICKUP.instantiate()
	pickup.setup_saved_drop("SlimeTest:material:2", "wood", 1)
	root.add_child(pickup)
	await process_frame
	var player = CharacterBody2D.new()
	player.add_to_group("player")
	root.add_child(player)
	pickup._on_body_entered(player)
	await process_frame
	_check(not exp.material_drops.has("SlimeTest:material:2"), "scene pickup collects and removes record")
	_check(inventory.get_item_count("wood") == 99 * 22, "scene pickup adds exact wood quantity")
	player.queue_free()
	exp.load_save_data({})
	inventory.clear_all()
	if failures.is_empty():
		print("MATERIAL_LOOT_PASSED: %d+ randomized checks" % assertions)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		printerr("MATERIAL_LOOT_FAILED: %d" % failures.size())
		quit(1)


func _check(condition: bool, description: String) -> void:
	assertions += 1
	if not condition:
		failures.append(description)


func _check_silent(condition: bool, description: String) -> void:
	if not condition and not failures.has(description):
		failures.append(description)
