extends SceneTree

# Shield bash (破盾弹反, hold Z + press H): needs the move, costs shield, knocks enemies in
# front away and stuns them, parries an attack in progress, blocks for free while it lasts.

var failures: Array[String] = []
var checks: int = 0
var scene: Node2D
var cat: CharacterBody2D


func _initialize() -> void:
	call_deferred("_run")


func _frames(n: int) -> void:
	for _i in range(n):
		await physics_frame


func _spawn(path: String, pos: Vector2, enemy_name: String) -> Node:
	var e: Node = load(path).instantiate()
	e.name = enemy_name
	e.counts_toward_objective = false
	scene.add_child(e)
	e.global_position = pos
	return e


func _run() -> void:
	var pm = root.get_node("ProgressionManager")
	pm._test_mode = true
	pm._load_profile_data({})
	root.get_node("ExpeditionManager").begin_run("forest_grove")
	root.get_node("DayManager").current_state = root.get_node("DayManager").TimeState.NIGHT
	scene = load("res://scenes/worlds/forest_grove.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await _frames(2)
	for e in get_nodes_in_group("enemies"):
		e.set_physics_process(false)
		e.global_position = Vector2(100, 100)
	cat = scene.get_node("Cat")
	cat.set_process(false)
	var spot := Vector2(2600, 1150)   # the central clearing
	cat.global_position = spot
	cat.last_facing = Vector2.RIGHT
	cat.shield_durability = cat.shield_max_durability

	_check(MoveCatalog.has_move_id("shield_bash") and MoveCatalog.display_name("shield_bash") == "破盾弹反", "the move is in the catalog")
	_check(InputMap.has_action("shield_bash"), "the shield_bash input action (H) exists")

	# --- the secret that teaches it exists and is reachable on the map ---------------------------
	var level = JSON.parse_string(FileAccess.get_file_as_string("res://tools/data/forest_grove_level.json"))
	var ids: Array = []
	for s in level["secrets"]:
		ids.append(str(s["move_id"]))
	_check(ids.has("shield_bash"), "the forest has a secret that teaches the shield bash")
	_check(scene.get_node_or_null("SecretSpot_bench_hollow") != null, "...and its secret spot is in the scene")

	# --- not learned: nothing happens -------------------------------------------------------------
	cat.is_defending = true
	_check(not cat.try_shield_bash(), "without the move the bash does nothing")
	pm.unlock_move("shield_bash")
	cat.is_defending = false
	_check(not cat.try_shield_bash(), "without holding the shield the bash does nothing")

	# --- a slime in front is knocked away and stunned, one behind is left alone ---------------------
	var front: Node = _spawn("res://scenes/enemies/charger.tscn", spot + Vector2(80, 0), "Front")
	var behind: Node = _spawn("res://scenes/enemies/charger.tscn", spot + Vector2(-80, 0), "Behind")
	var far: Node = _spawn("res://scenes/enemies/charger.tscn", spot + Vector2(400, 0), "Far")
	front.set_physics_process(true)
	cat.is_defending = true
	var before: float = cat.shield_durability
	_check(cat.try_shield_bash(), "holding the shield, the bash goes off")
	_check(is_equal_approx(before - cat.shield_durability, cat.shield_bash_cost), "it costs shield durability")
	_check(cat.shield_bash_cooldown_left > 0.0, "it goes on cooldown")
	_check(not cat.try_shield_bash(), "it cannot be spammed")
	await _frames(40)
	_check(front.global_position.x > spot.x + 80.0 + 20.0, "the enemy in front was knocked away (x %s)" % front.global_position.x)
	_check(front.state == front.S.STUNNED, "...and is stunned")
	_check(behind.state != behind.S.STUNNED and behind.current_health == behind.max_health, "an enemy behind the cat is untouched")
	_check(far.state != far.S.STUNNED, "an enemy out of range is untouched")

	# --- the bash blocks for free while it lasts -----------------------------------------------------
	cat.shield_bash_cooldown_left = 0.0
	cat.shield_durability = cat.shield_max_durability
	cat.is_defending = true
	_check(cat.try_shield_bash(), "bash again")
	var left_after_bash: float = cat.shield_durability
	_check(cat.try_block_attack(1, 25.0), "an attack during the bash is blocked")
	_check(cat.shield_durability == left_after_bash, "...for free")

	# --- not enough shield -----------------------------------------------------------------------------
	cat.shield_bash_cooldown_left = 0.0
	cat.shield_bash_guard_left = 0.0
	cat.shield_durability = cat.shield_bash_cost - 1.0
	cat.is_defending = true
	_check(not cat.try_shield_bash(), "not enough shield durability: no bash")

	# --- a charger in the middle of its attack is parried -----------------------------------------------
	front.queue_free()
	behind.queue_free()
	far.queue_free()
	await _frames(2)
	var ch: Node = _spawn("res://scenes/enemies/charger.tscn", spot + Vector2(-220, 0), "Charger")
	cat.last_facing = Vector2.LEFT
	cat.invincibility_left = 0.0
	cat.shield_durability = cat.shield_max_durability
	cat.shield_bash_cooldown_left = 0.0
	cat.shield_bash_guard_left = 0.0
	for _f in range(400):
		await physics_frame
		if ch.state == ch.S.WINDUP and ch.state_time > 0.15:
			break
	Input.action_press("defend")
	await _frames(3)
	await process_frame
	Input.action_press("shield_bash")
	await _frames(3)
	Input.action_release("shield_bash")
	Input.action_release("defend")
	await _frames(40)
	_check(cat.current_health == float(cat.max_health), "the cat took no damage")
	_check(ch.state == ch.S.STUNNED, "a charger caught mid-attack is parried and stunned")

	if failures.is_empty():
		print("SHIELD_BASH_PASSED: %d checks" % checks)
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
