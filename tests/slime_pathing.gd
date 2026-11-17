extends SceneTree

# Slimes walk around trees: when the cat is behind a tree wall (and a short detour exists) the
# slime must reach it instead of pushing into the wall; when no short detour exists it gives up
# instead of grinding against the trees.

var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var pm = root.get_node("ProgressionManager")
	pm._test_mode = true
	pm._load_profile_data({})
	root.get_node("ExpeditionManager").begin_run("forest_grove")
	root.get_node("DayManager").current_state = root.get_node("DayManager").TimeState.NIGHT
	var scene: Node2D = load("res://scenes/worlds/forest_grove.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await physics_frame
	await physics_frame
	var terrain: TileMapLayer = scene.get_node("Terrain")
	var cat: CharacterBody2D = scene.get_node("Cat")
	cat.set_physics_process(false)
	cat.set_process(false)
	cat.max_health = 9999
	cat.current_health = 9999.0
	var enemies := get_nodes_in_group("enemies")
	for e in enemies:
		e.set_physics_process(false)
	var grid: AStarGrid2D = load("res://scripts/nav_grid.gd").for_scene(scene)
	_check(grid != null, "the forest has a path grid")
	var space := scene.get_world_2d().direct_space_state
	var reachable_cases := 0
	var reached := 0
	var grinding := 0
	var far_cases := 0
	for e in enemies:
		var spawn: Vector2 = e.global_position
		var found := 0
		for k in range(40):
			var p := spawn + Vector2.from_angle(k * 0.7) * (130 + (k % 4) * 30)
			var cell := Vector2i(int(p.x) / 32, int(p.y) / 32)
			var d := terrain.get_cell_tile_data(cell)
			if d == null or d.get_collision_polygons_count(0) > 0:
				continue
			if space.intersect_ray(PhysicsRayQueryParameters2D.create(spawn, p, 1)).is_empty():
				continue   # we only want "cat behind a wall" cases
			found += 1
			if found > 2:
				break
			var path: PackedVector2Array = grid.get_point_path(Vector2i(int(spawn.x) / 32, int(spawn.y) / 32), cell)
			var length := 0.0
			for i in range(1, path.size()):
				length += path[i].distance_to(path[i - 1])
			var short_detour: bool = path.size() > 1 and length < float(e.disengage_range) * 1.4
			e.global_position = spawn
			e.velocity = Vector2.ZERO
			e.chase_path = PackedVector2Array()
			e.chase_give_up_left = 0.0
			e._change_state(0)
			e.set_physics_process(true)
			cat.global_position = p
			var best := INF
			var history: Array[Vector2] = []
			var chase_frames := 0
			var attacked := false
			for _f in range(360):
				await physics_frame
				history.append(e.global_position)
				best = minf(best, e.global_position.distance_to(p))
				if e.state == 3:   # WINDUP: it got around the trees and is attacking (it needs a clear line)
					attacked = true
				if e.state == 2 and _f >= 180:
					chase_frames += 1
			e.set_physics_process(false)
			if short_detour:
				reachable_cases += 1
				if best < 70.0 or attacked:
					reached += 1
				else:
					printerr("  %s did not reach the cat at %s (best %.0f, detour %.0f)" % [e.name, str(p), best, length])
			else:
				far_cases += 1
			# grinding = still chasing during the last 3 s but barely moving and not near the cat
			var late_move: float = history[359].distance_to(history[180])
			if best >= 70.0 and not attacked and chase_frames > 150 and late_move < 24.0:
				grinding += 1
				printerr("  %s grinds against the trees near %s" % [e.name, str(e.global_position)])
	_check(reachable_cases >= 15, "enough 'cat behind trees' cases with a short way round (%d, plus %d long ones)" % [reachable_cases, far_cases])
	_check(reached >= int(ceil(reachable_cases * 0.9)), "slimes walk around the trees and attack the cat (%d of %d)" % [reached, reachable_cases])
	_check(grinding == 0, "no slime keeps pushing into a tree wall (%d did)" % grinding)

	if failures.is_empty():
		print("SLIME_PATHING_PASSED: %d checks" % checks)
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
