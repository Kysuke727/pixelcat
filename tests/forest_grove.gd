extends SceneTree

# The forest grove map: structure, walkability (real physics), camera, secret, run flow.

var failures: Array[String] = []
var checks: int = 0
var level: Dictionary


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var pm = root.get_node("ProgressionManager")
	var exp = root.get_node("ExpeditionManager")
	var day = root.get_node("DayManager")
	pm._test_mode = true
	pm._load_profile_data({})
	level = JSON.parse_string(FileAccess.get_file_as_string("res://tools/data/forest_grove_level.json"))

	exp.run_active = false
	exp.begin_run("forest_grove")
	day.current_state = day.TimeState.NIGHT
	var scene: Node2D = load("res://scenes/worlds/forest_grove.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await physics_frame
	await physics_frame
	await physics_frame

	# --- Structure ----------------------------------------------------------------
	_check(scene.is_in_group("night_exploration"), "scene is a night exploration map")
	for required in ["Terrain", "Cat", "NightExit", "ExpeditionHUD", "NightRunController", "CombatCamera", "NightMusic", "SecretSpot", "HUD", "InventoryUI", "CraftingUI", "ProgressionPanel", "DebugPanel"]:
		_check(scene.get_node_or_null(required) != null, "has %s" % required)
	_check(scene.get_node("NightMusic") is AudioStreamPlayer, "music is non-positional (does not fade on a big map)")
	var terrain: TileMapLayer = scene.get_node("Terrain")
	_check(terrain.get_used_cells().size() == 144 * 80, "terrain covers the whole 144 x 80 tile world")
	var enemies := get_nodes_in_group("enemies")
	var mandatory := 0
	var optional_names: Array[String] = []
	for e in level["enemies"]:
		if e["optional"]:
			optional_names.append(str(e["name"]))
		else:
			mandatory += 1
	_check(enemies.size() == level["enemies"].size() and enemies.size() == 22, "22 slimes in the forest (got %d)" % enemies.size())
	var names := {}
	for enemy in enemies:
		names[enemy.name] = true
	_check(names.size() == enemies.size(), "enemy names are unique (they are the objective ids)")
	_check(mandatory == 19 and exp.objectives_total == mandatory, "the run's objectives are the 19 slimes outside the side spots (%d)" % exp.objectives_total)
	for guard_name in optional_names:
		_check(names.has(guard_name) and not exp.objective_ids.has(guard_name), "%s is not an objective" % guard_name)
		_check(scene.get_node(guard_name).counts_toward_objective == false, "%s is flagged optional" % guard_name)
	_check(optional_names.size() == 3, "three optional guards (secret, mushroom nook, stash)")
	_check(scene.get_node("EnemyCompass") != null, "the scene has the enemy compass")
	_check(scene.get_node("HUD") is CanvasLayer and scene.get_node("HUD/BattleUI") != null and scene.get_node("HUD/CoinUI") != null and scene.get_node("HUD/QuickbarUI") != null, "HUD controls live on a screen-space layer")
	var cat: CharacterBody2D = scene.get_node("Cat")
	_check(MapCatalog.MAPS["forest_grove"]["start"] == Vector2(float(level["start"][0]), float(level["start"][1])), "MapCatalog start matches the level data")
	_check(cat.global_position == Vector2(float(level["start"][0]), float(level["start"][1])), "the cat starts at the forest start")
	_check(scene.get_node("NightExit").global_position == Vector2(float(level["exit"][0]), float(level["exit"][1])), "exit is at the east end")
	_check(scene.get_node_or_null("SafePoint1") == null and scene.get_node_or_null("SafePoint2") == null, "there are no safe points (dying ends the run)")

	# --- Walkability from the REAL tile data (solid = tile has a collision polygon) ------------
	var solid := {}
	var grid: Array = level["grid"]
	var tile_set := terrain.tile_set
	for r in range(grid.size()):
		for c in range(grid[r].size()):
			var data := terrain.get_cell_tile_data(Vector2i(c, r))
			solid[Vector2i(c, r)] = data != null and data.get_collision_polygons_count(0) > 0
	var seen := {}
	var queue: Array[Vector2i] = [Vector2i(int(level["start"][0]) / 32, int(level["start"][1]) / 32)]
	seen[queue[0]] = true
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cell + step
			if n.x >= 0 and n.y >= 0 and n.x < 144 and n.y < 80 and not solid[n] and not seen.has(n):
				seen[n] = true
				queue.append(n)
	for enemy in enemies:
		var cell := Vector2i(int(enemy.global_position.x) / 32, int(enemy.global_position.y) / 32)
		_check(seen.has(cell), "%s stands on reachable ground" % enemy.name)
	for loot_node in get_nodes_in_group("loot_spot"):
		var lcell := Vector2i(int(loot_node.global_position.x) / 32, int(loot_node.global_position.y) / 32)
		_check(seen.has(lcell), "%s is reachable" % loot_node.name)
	_check(get_nodes_in_group("loot_spot").size() == 4, "four hidden stashes")
	for node_name in ["NightExit", "SecretSpot"]:
		var node: Node2D = scene.get_node(node_name)
		var cell := Vector2i(int(node.global_position.x) / 32, int(node.global_position.y) / 32)
		_check(seen.has(cell), "%s is reachable" % node_name)

	# --- Real physics: walls hold, paths are walkable ----------------------------------------
	for enemy in enemies:
		enemy.set_physics_process(false)
		enemy.get_node("CollisionShape2D").disabled = true
	cat.set_physics_process(false)
	cat.set_process(false)
	cat.global_position = Vector2(230, 2250)
	for _i in range(200):
		cat.velocity = Vector2.LEFT * 200.0
		cat.move_and_slide()
	_check(cat.global_position.x > 90.0, "trees stop the cat at the west edge (x=%.0f)" % cat.global_position.x)
	cat.global_position = Vector2(2500, 1150)
	for _i in range(300):
		cat.velocity = Vector2.RIGHT * 200.0
		cat.move_and_slide()
	# the pond (water tile) must block as well: stand west of the central pond (2750,1370) and push through its middle
	cat.global_position = Vector2(2500, 1370)
	for _i in range(400):
		cat.velocity = Vector2.RIGHT * 200.0
		cat.move_and_slide()
	_check(cat.global_position.x < 2640.0, "the central pond blocks the cat (x=%.0f)" % cat.global_position.x)

	var main_route: Array = level["path"]
	cat.global_position = Vector2(float(level["start"][0]), float(level["start"][1]))
	var ok_main := _walk(cat, main_route)
	_check(ok_main, "the cat can walk the whole main road from start to exit")
	_check(cat.global_position.distance_to(Vector2(float(level["exit"][0]), float(level["exit"][1]))) < 24.0, "...and arrives at the exit (%s)" % str(cat.global_position))

	for branch in level["branches"]:
		cat.global_position = _vec(branch["points"][0])
		_check(_walk(cat, branch["points"]), "the cat can walk the side road %s" % branch["name"])
	var secret_route: Array = level["trails"][0]["points"]
	cat.global_position = _vec(secret_route[0])
	_check(not pm.has_move("triple_combo"), "triple combo not learned yet")
	var found: Array = []
	scene.get_node("SecretSpot").secret_found.connect(func(id: String): found.append(id))
	var ok_secret := _walk(cat, secret_route + [level["secrets"][0]["pos"]])
	_check(ok_secret, "the cat can walk the secret trail to the old tree hollow")
	await physics_frame
	await physics_frame
	await physics_frame
	_check(pm.has_move("triple_combo"), "arriving at the hollow teaches the triple combo (real overlap)")
	_check(found == ["triple_combo"], "secret_found fired once")
	var banner = root.get_node("MoveBanner")
	_check(banner.is_showing(), "the move banner appears")
	scene.get_node("SecretSpot")._on_body_entered(cat)
	_check(found.size() == 1, "going back in does not teach it twice")

	# --- Paw print hint is subtle -------------------------------------------------------------
	var paws := 0
	for child in scene.get_node("Decorations").get_children():
		if child.name.begins_with("PawPrint"):
			paws += 1
			_check(child.modulate.a < 0.5, "%s is faint" % child.name)
	_check(paws >= 3, "a few paw prints hint at the trail (%d)" % paws)

	# --- Hidden stashes -----------------------------------------------------------------------
	var stash: Node = scene.get_node("Loot_stash")
	var wood_before: int = root.get_node("InventoryManager").get_item_count("wood")
	var fish_before: int = exp.ordinary_fish
	# a full backpack must not take anything
	var inv = root.get_node("InventoryManager")
	var saved_slots: Array = inv.slots.duplicate(true)
	for i in range(inv.SLOT_COUNT):
		inv.slots[i] = {"item_id": "stone", "quantity": 99}
	_check(not stash.collect(), "a full backpack cannot take the stash")
	_check(not stash.taken and not exp.is_loot_collected("stash"), "the stash stays closed (nothing lost)")
	inv.slots = saved_slots
	cat.global_position = stash.global_position + Vector2(0, 80)
	await physics_frame
	_check(_walk(cat, [stash.global_position]), "the cat can step on the stash")
	await physics_frame
	await physics_frame
	_check(stash.taken and exp.is_loot_collected("stash"), "stepping in takes the stash once")
	_check(inv.get_item_count("wood") == wood_before + 4, "the stash gave 4 wood")
	_check(exp.ordinary_fish == fish_before + 3, "the stash gave 3 fish")
	_check(not stash.collect(), "it cannot be taken twice")

	# --- Signposts ----------------------------------------------------------------------------
	var signs := 0
	for child in scene.get_node("Decorations").get_children():
		if child is Sprite2D and child.get_script() != null and child.get("text") != null:
			signs += 1
			_check(str(child.get("text")) != "" and child.get_node_or_null("Text") != null, "%s shows its text" % child.name)
	_check(signs == 3, "three signposts (%d)" % signs)

	# --- Camera ------------------------------------------------------------------------------
	var camera: Camera2D = scene.get_node("CombatCamera")
	_check(camera.follow_player and camera.is_current(), "camera follows the cat")
	cat.global_position = Vector2(2500, 1150)
	camera._process(0.016)
	_check(camera.global_position.distance_to(Vector2(2500, 1150)) < 1.5, "camera centres on the cat")
	cat.global_position = Vector2(10, 10)
	camera._process(0.016)
	var half_view := Vector2(get_root().size) / 2.0
	var screen_center := camera.get_screen_center_position()
	_check(screen_center.x >= half_view.x - 1.0 and screen_center.y >= half_view.y - 1.0, "camera never shows left of / above the map (%s)" % str(screen_center))
	cat.global_position = Vector2(4600, 2550)
	camera._process(0.016)
	screen_center = camera.get_screen_center_position()
	_check(screen_center.x <= 4608.0 - half_view.x + 1.0 and screen_center.y <= 2560.0 - half_view.y + 1.0, "camera never shows beyond the right / bottom edge (%s)" % str(screen_center))

	# --- Run flow -----------------------------------------------------------------------------
	day.scene_change_override = func(_path: String) -> int: return OK
	var exit_gate = scene.get_node("NightExit")
	_check(not exit_gate.extract(), "the exit stays closed while slimes remain")
	# Defeating only the optional guard does not help: the outside slimes still count.
	for guard_name in optional_names:
		var guard: Node = scene.get_node(guard_name)
		guard.receive_damage(999.0, guard.global_position + Vector2.LEFT, 0.0)
	await process_frame
	await process_frame
	_check(exp.objectives_completed == 0, "killing the guards does not count toward the objective (%d)" % exp.objectives_completed)
	_check(exp.defeated_enemy_ids.has("SecretGuard"), "...but they are remembered as defeated (no respawn on resume)")
	_check(not exit_gate.extract(), "the exit is still closed after only the guards")
	# Now the nineteen outside slimes.
	for enemy in enemies:
		if is_instance_valid(enemy) and not optional_names.has(str(enemy.name)):
			enemy.receive_damage(999.0, enemy.global_position + Vector2.LEFT, 0.0)
	await process_frame
	await process_frame
	_check(exp.objectives_completed == 19, "defeating the nineteen outside slimes completes the objectives (%d)" % exp.objectives_completed)
	_check(exit_gate.extract(), "the exit opens once the nineteen are defeated")
	_check(pm.is_map_cleared("forest_grove"), "reaching the exit clears the forest")
	day.scene_change_override = Callable()

	if failures.is_empty():
		print("FOREST_GROVE_PASSED: %d checks" % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		quit(1)


## Walk the cat along waypoints with real collisions. Returns false if it gets stuck.
func _walk(cat: CharacterBody2D, waypoints: Array) -> bool:
	for waypoint in waypoints:
		var target: Vector2 = Vector2(float(waypoint[0]), float(waypoint[1])) if waypoint is Array else waypoint
		var steps := 0
		while cat.global_position.distance_to(target) > 10.0 and steps < 900:
			cat.velocity = cat.global_position.direction_to(target) * 200.0
			cat.move_and_slide()
			steps += 1
		if cat.global_position.distance_to(target) > 24.0:
			printerr("stuck before ", target, " at ", cat.global_position)
			return false
	return true


func _vec(value) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", description)
	else:
		failures.append(description)
