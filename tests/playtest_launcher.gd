extends SceneTree

# The one-click playtest scenes must land in the right map without touching saves.

var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var pm = root.get_node("ProgressionManager")
	var exp = root.get_node("ExpeditionManager")
	var day = root.get_node("DayManager")
	var requested: Array = []
	day.scene_change_override = func(path: String) -> int:
		requested.append(path)
		return OK
	for case in [["play_forest", "res://scenes/worlds/forest_grove.tscn", false], ["play_forest_all_moves", "res://scenes/worlds/forest_grove.tscn", true], ["play_park", "res://scenes/worlds/night_world.tscn", false]]:
		pm._test_mode = false
		pm._load_profile_data({})
		exp.run_active = false
		day.current_state = day.TimeState.DAY
		requested.clear()
		var launcher: Node = load("res://scenes/dev/%s.tscn" % case[0]).instantiate()
		root.add_child(launcher)
		await process_frame
		await process_frame
		_check(requested.size() == 1 and requested[0] == case[1], "%s loads %s" % [case[0], case[1]])
		_check(pm._test_mode, "%s runs in test mode (nothing is saved)" % case[0])
		_check(exp.run_active and day.current_state == day.TimeState.NIGHT, "%s starts a night run" % case[0])
		_check((pm.unlocked_moves.size() == 3) == case[2], "%s moves unlocked = %s" % [case[0], str(case[2])])
		_check(not pm.is_map_cleared("park"), "%s does not need (or fake) clearing the earlier maps" % case[0])
		launcher.queue_free()
		await process_frame
	day.scene_change_override = Callable()
	exp.run_active = false
	day.current_state = day.TimeState.DAY

	if failures.is_empty():
		print("PLAYTEST_LAUNCHER_PASSED: %d checks" % checks)
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
