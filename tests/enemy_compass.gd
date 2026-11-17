extends SceneTree

# Edge arrows for big maps: geometry, which enemies are pointed at, exit mode.

var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var pm = root.get_node("ProgressionManager")
	var exp = root.get_node("ExpeditionManager")
	var day = root.get_node("DayManager")
	pm._test_mode = true
	var Compass = load("res://scripts/enemy_compass.gd")
	var size := Vector2(1152, 648)

	# --- Geometry ---------------------------------------------------------------------------
	_check(Compass.edge_point(Vector2(500, 300), size).is_empty(), "a point on screen gets no arrow")
	_check(Compass.edge_point(size / 2.0 + Vector2.ZERO, size).is_empty(), "the screen centre gets no arrow")
	var right: Dictionary = Compass.edge_point(Vector2(3000, 324), size)
	_check(is_equal_approx(right["position"].x, 1152.0 - 30.0) and is_equal_approx(right["position"].y, 324.0), "a point far to the right: arrow on the right edge, vertically centred")
	_check(is_equal_approx(right["angle"], 0.0), "...pointing right")
	var up: Dictionary = Compass.edge_point(Vector2(576, -900), size)
	_check(is_equal_approx(up["position"].y, 30.0) and is_equal_approx(up["position"].x, 576.0), "a point far above: arrow on the top edge")
	_check(is_equal_approx(up["angle"], -PI / 2.0), "...pointing up")
	var diagonal: Dictionary = Compass.edge_point(Vector2(-5000, -5000), size)
	_check(diagonal["position"].x >= 30.0 and diagonal["position"].y >= 30.0 and diagonal["position"].x <= 1122.0 and diagonal["position"].y <= 618.0, "arrows always stay inside the margin")
	var just_off: Dictionary = Compass.edge_point(Vector2(1200, 324), size)
	_check(not just_off.is_empty() and just_off["position"].x <= 1122.0, "a point just off screen is pulled inside the margin")

	# --- Targets in the forest -------------------------------------------------------------------
	exp.run_active = false
	exp.begin_run("forest_grove")
	day.current_state = day.TimeState.NIGHT
	var scene: Node2D = load("res://scenes/worlds/forest_grove.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await physics_frame
	await physics_frame
	var compass = scene.get_node("EnemyCompass")
	var enemies := get_nodes_in_group("enemies")
	for enemy in enemies:
		enemy.set_physics_process(false)
	day.scene_change_override = func(_path: String) -> int: return OK

	_check(compass.get_targets().is_empty(), "no arrows while many enemies remain (19 outside)")
	var mandatory: Array = []
	for enemy in enemies:
		if enemy.counts_toward_objective:
			mandatory.append(enemy)
	_check(mandatory.size() == 19, "19 slimes count toward the exit (%d)" % mandatory.size())
	for i in range(13):
		mandatory[i].receive_damage(999.0, mandatory[i].global_position, 0.0)
	await process_frame
	_check(compass.get_targets().is_empty(), "with 6 outside slimes left there are still no arrows")
	mandatory[13].receive_damage(999.0, mandatory[13].global_position, 0.0)
	await process_frame
	var five: Array = compass.get_targets()
	_check(five.size() == 5, "with 5 left, five arrows (got %d)" % five.size())
	var positions: Array = []
	for target in five:
		positions.append(target["position"])
	for enemy in enemies:
		if not enemy.counts_toward_objective:
			_check(not positions.has(enemy.global_position), "optional guard %s is never pointed at" % enemy.name)
	for target in five:
		_check(target["color"] == compass.ENEMY_COLOR, "enemy arrows are red")
	mandatory[14].receive_damage(999.0, mandatory[14].global_position, 0.0)
	await process_frame
	_check(compass.get_targets().size() == 4, "arrows follow the remaining count (4)")
	for i in range(15, 17):
		mandatory[i].receive_damage(999.0, mandatory[i].global_position, 0.0)
	await process_frame
	_check(compass.get_targets().size() == 2, "...and 2")
	for i in range(17, 19):
		mandatory[i].receive_damage(999.0, mandatory[i].global_position, 0.0)
	await process_frame
	await process_frame
	_check(exp.objectives_complete(), "all outside slimes defeated")
	var exit_targets: Array = compass.get_targets()
	_check(exit_targets.size() == 1 and exit_targets[0]["color"] == compass.EXIT_COLOR, "once the exit is open the only arrow points at it")
	_check(exit_targets[0]["position"] == scene.get_node("NightExit").global_position, "...at the exit's position")
	_check(scene.get_node("SecretGuard").is_alive(), "the guards are still alive and still ignored")

	# Drawing must not error.
	compass._canvas.queue_redraw()
	await process_frame
	await process_frame
	_check(true, "drawing the arrows runs without errors")

	# Not on a run: nothing.
	day.scene_change_override = Callable()
	exp.run_active = false
	_check(compass.get_targets().is_empty(), "no arrows outside a run")

	if failures.is_empty():
		print("ENEMY_COMPASS_PASSED: %d checks" % checks)
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
