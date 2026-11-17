extends SceneTree

# Drops must never land inside trees/bushes (the cat could not pick them up).

var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var pm = root.get_node("ProgressionManager")
	var exp = root.get_node("ExpeditionManager")
	pm._test_mode = true
	pm._load_profile_data({})
	exp.begin_run("forest_grove")
	root.get_node("DayManager").current_state = root.get_node("DayManager").TimeState.NIGHT
	var scene: Node2D = load("res://scenes/worlds/forest_grove.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await physics_frame
	await physics_frame
	var terrain: TileMapLayer = scene.get_node("Terrain")
	var enemies := get_nodes_in_group("enemies")
	for e in enemies:
		e.set_physics_process(false)
	var slime: Node2D = enemies[0]
	slime.get_node("CollisionShape2D").disabled = true

	# Find walkable cells that touch a solid cell on their east side (a wall right next to the slime).
	var spots: Array[Vector2] = []
	for r in range(1, 79):
		for c in range(1, 143):
			if _solid(terrain, Vector2i(c, r)) or not _solid(terrain, Vector2i(c + 1, r)):
				continue
			spots.append(Vector2(c * 32 + 28, r * 32 + 16))   # hard against the wall
			if spots.size() >= 60:
				break
		if spots.size() >= 60:
			break
	_check(spots.size() >= 30, "found wall-side spots to test (%d)" % spots.size())
	var bad := 0
	var total := 0
	for spot in spots:
		slime.global_position = spot
		await physics_frame
		for _i in range(6):
			var records: Array = []
			records.append_array(slime._prepare_fish_drop_records())
			records.append_array(slime._prepare_material_drop_records())
			for record in records:
				total += 1
				var p := Vector2(float(record["position"][0]), float(record["position"][1]))
				if _solid(terrain, Vector2i(int(p.x) / 32, int(p.y) / 32)):
					bad += 1
	_check(total > 200, "enough drops were checked (%d)" % total)
	_check(bad == 0, "no drop landed inside a tree or bush (%d of %d did)" % [bad, total])

	if failures.is_empty():
		print("DROP_IN_WALLS_PASSED: %d checks" % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		quit(1)


func _solid(terrain: TileMapLayer, cell: Vector2i) -> bool:
	var data := terrain.get_cell_tile_data(cell)
	return data != null and data.get_collision_polygons_count(0) > 0


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", description)
	else:
		failures.append(description)
