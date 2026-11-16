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
	_check(terrain.get_used_cells().size() == 72 * 40, "terrain covers the whole 72 x 40 tile world")
	var enemies := get_nodes_in_group("enemies")
	_check(enemies.size() == 9, "nine slimes (got %d)" % enemies.size())
	var names := {}
	for enemy in enemies:
		names[enemy.name] = true
	_check(names.size() == 9, "enemy names are unique (they are the objective ids)")
	_check(exp.objectives_total == 8, "the run's objectives are the 8 slimes outside the secret (%d)" % exp.objectives_total)
	_check(names.has("SecretGuard") and not exp.objective_ids.has("SecretGuard"), "the secret-trail guard is not an objective")
	_check(scene.get_node("SecretGuard").counts_toward_objective == false, "the guard is flagged optional")
	_check(scene.get_node("EnemyCompass") != null, "the scene has the enemy compass")
	_check(scene.get_node("HUD") is CanvasLayer and scene.get_node("HUD/BattleUI") != null and scene.get_node("HUD/CoinUI") != null and scene.get_node("HUD/QuickbarUI") != null, "HUD controls live on a screen-space layer")
	var cat: CharacterBody2D = scene.get_node("Cat")
	_check(cat.global_position == Vector2(170, 1120), "the cat starts at the forest start")
	_check(scene.get_node("NightExit").global_position == Vector2(2200, 420), "exit is at the east end")
	_check(scene.get_node_or_null("SafePoint1") != null and scene.get_node_or_null("SafePoint2") != null, "two safe points")

	# --- Walkability from the REAL tile data (solid = tile has a collision polygon) ------------
	var solid := {}
	var grid: Array = level["grid"]
	var tile_set := terrain.tile_set
	for r in range(grid.size()):
		for c in range(grid[r].size()):
			var data := terrain.get_cell_tile_data(Vector2i(c, r))
			solid[Vector2i(c, r)] = data != null and data.get_collision_polygons_count(0) > 0
	var seen := {}
	var queue: Array[Vector2i] = [Vector2i(170 / 32, 1120 / 32)]
	seen[queue[0]] = true
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cell + step
			if n.x >= 0 and n.y >= 0 and n.x < 72 and n.y < 40 and not solid[n] and not seen.has(n):
				seen[n] = true
				queue.append(n)
	for enemy in enemies:
		var cell := Vector2i(int(enemy.global_position.x) / 32, int(enemy.global_position.y) / 32)
		_check(seen.has(cell), "%s stands on reachable ground" % enemy.name)
	for node_name in ["SafePoint1", "SafePoint2", "NightExit", "SecretSpot"]:
		var node: Node2D = scene.get_node(node_name)
		var cell := Vector2i(int(node.global_position.x) / 32, int(node.global_position.y) / 32)
		_check(seen.has(cell), "%s is reachable" % node_name)

	# --- Real physics: walls hold, paths are walkable ----------------------------------------
	for enemy in enemies:
		enemy.set_physics_process(false)
		enemy.get_node("CollisionShape2D").disabled = true
	cat.set_physics_process(false)
	cat.set_process(false)
	cat.global_position = Vector2(170, 1120)
	for _i in range(200):
		cat.velocity = Vector2.LEFT * 200.0
		cat.move_and_slide()
	_check(cat.global_position.x > 90.0, "trees stop the cat (x=%.0f after pushing left)" % cat.global_position.x)
	cat.global_position = Vector2(1250, 470)
	for _i in range(200):
		cat.velocity = Vector2.UP * 200.0
		cat.move_and_slide()
	_check(cat.global_position.y > 330.0, "the tree wall north of the road holds (y=%.0f)" % cat.global_position.y)
	cat.global_position = Vector2(1250, 620)
	for _i in range(200):
		cat.velocity = Vector2(1.0, 0.7).normalized() * 200.0
		cat.move_and_slide()
	# the pond (water tile) must block as well
	cat.global_position = Vector2(1450, 600)
	for _i in range(200):
		cat.velocity = Vector2.DOWN * 200.0
		cat.move_and_slide()
	_check(cat.global_position.y < 700.0, "the pond blocks the cat (y=%.0f)" % cat.global_position.y)

	var main_route: Array = level["path"]
	cat.global_position = Vector2(170, 1120)
	var ok_main := _walk(cat, main_route)
	_check(ok_main, "the cat can walk the whole main road from start to exit")
	_check(cat.global_position.distance_to(Vector2(2200, 420)) < 24.0, "...and arrives at the exit (%s)" % str(cat.global_position))

	var secret_route: Array = [Vector2(170, 1120), Vector2(480, 1135), Vector2(500, 970), Vector2(520, 900), Vector2(380, 720), Vector2(330, 520), Vector2(360, 330), Vector2(360, 282)]
	cat.global_position = Vector2(170, 1120)
	_check(not pm.has_move("triple_combo"), "triple combo not learned yet")
	var found: Array = []
	scene.get_node("SecretSpot").secret_found.connect(func(id: String): found.append(id))
	var ok_secret := _walk(cat, secret_route)
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

	# --- Camera ------------------------------------------------------------------------------
	var camera: Camera2D = scene.get_node("CombatCamera")
	_check(camera.follow_player and camera.is_current(), "camera follows the cat")
	cat.global_position = Vector2(1200, 700)
	camera._process(0.016)
	_check(camera.global_position.distance_to(Vector2(1200, 700)) < 1.5, "camera centres on the cat")
	cat.global_position = Vector2(10, 10)
	camera._process(0.016)
	var half_view := Vector2(get_root().size) / 2.0
	var screen_center := camera.get_screen_center_position()
	_check(screen_center.x >= half_view.x - 1.0 and screen_center.y >= half_view.y - 1.0, "camera never shows left of / above the map (%s)" % str(screen_center))
	cat.global_position = Vector2(2290, 1270)
	camera._process(0.016)
	screen_center = camera.get_screen_center_position()
	_check(screen_center.x <= 2304.0 - half_view.x + 1.0 and screen_center.y <= 1280.0 - half_view.y + 1.0, "camera never shows beyond the right / bottom edge (%s)" % str(screen_center))

	# --- Run flow -----------------------------------------------------------------------------
	day.scene_change_override = func(_path: String) -> int: return OK
	var exit_gate = scene.get_node("NightExit")
	_check(not exit_gate.extract(), "the exit stays closed while slimes remain")
	# Defeating only the optional guard does not help: the outside slimes still count.
	var guard: Node = scene.get_node("SecretGuard")
	guard.receive_damage(999.0, guard.global_position + Vector2.LEFT, 0.0)
	await process_frame
	await process_frame
	_check(exp.objectives_completed == 0, "killing the guard does not count toward the objective (%d)" % exp.objectives_completed)
	_check(exp.defeated_enemy_ids.has("SecretGuard"), "...but it is remembered as defeated (no respawn on resume)")
	_check(not exit_gate.extract(), "the exit is still closed after only the guard")
	# Now the eight outside slimes.
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.name != "SecretGuard":
			enemy.receive_damage(999.0, enemy.global_position + Vector2.LEFT, 0.0)
	await process_frame
	await process_frame
	_check(exp.objectives_completed == 8, "defeating the eight outside slimes completes the objectives (%d)" % exp.objectives_completed)
	_check(exit_gate.extract(), "the exit opens once the eight are defeated")
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


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", description)
	else:
		failures.append(description)
