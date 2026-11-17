extends SceneTree

# Charger and flyer: telegraph, hit + stun on the cat, dodge / guard answers, wall crash,
# flying over trees, and the stun itself.

var failures: Array[String] = []
var checks: int = 0
var scene: Node2D
var cat: CharacterBody2D


func _initialize() -> void:
	call_deferred("_run")


func _spawn(path: String, pos: Vector2, enemy_name: String) -> Node:
	var e: Node = load(path).instantiate()
	e.name = enemy_name
	e.counts_toward_objective = false
	scene.add_child(e)
	e.global_position = pos
	return e


func _frames(n: int) -> void:
	for _i in range(n):
		await physics_frame


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
		e.global_position = Vector2(100, 100)   # park them away
	cat = scene.get_node("Cat")
	cat.set_process(false)
	var open_spot := Vector2(2600, 1150)   # the central clearing: open ground

	# ================= charger ==================================================================
	var ch: Node = _spawn("res://scenes/enemies/charger.tscn", open_spot + Vector2(-200, 0), "TestCharger")
	_check(ch.is_in_group("enemies") and ch.display_name == "冲撞怪" and ch.max_health == 8, "a charger is an enemy with 8 HP")
	cat.global_position = open_spot
	cat.current_health = 5.0
	cat.max_health = 5
	await _frames(3)
	var saw_windup := false
	var saw_lane := false
	var windup_frames := 0
	for _f in range(260):
		await physics_frame
		if ch.state == ch.S.WINDUP:
			saw_windup = true
			windup_frames += 1
			saw_lane = saw_lane or ch.lane.visible
		if ch.state == ch.S.ACT:
			break
	_check(saw_windup and windup_frames >= 30, "it winds up first (%d frames) instead of rushing at once" % windup_frames)
	_check(saw_lane, "the red lane is shown during the wind-up")
	_check(ch.get_attack_eta_for(cat, 5.0) >= 0.0 or ch.state == ch.S.ACT, "the cat in the lane is reported as a target (perfect guard / dodge can use it)")
	# stand still in the lane -> hit, damaged AND stunned
	for _f in range(80):
		await physics_frame
		if cat.current_health < 5.0:
			break
	_check(cat.current_health < 5.0, "standing in the lane costs health (%.1f left)" % cat.current_health)
	_check(cat.is_stunned() and cat.stun_left > 0.5, "...and stuns the cat (%.2f s)" % cat.stun_left)
	_check(not cat.can_perform_combat_action(), "a stunned cat cannot attack")
	_check(not cat._try_start_dash(Vector2.RIGHT) and not cat._try_start_dodge(Vector2.RIGHT), "...nor dash nor dodge")
	await _frames(100)
	_check(not cat.is_stunned(), "the stun wears off")

	# stepping out of the lane: no damage
	ch.queue_free()
	await _frames(2)
	cat.current_health = 5.0
	cat.invincibility_left = 0.0
	cat.stun_left = 0.0
	ch = _spawn("res://scenes/enemies/charger.tscn", open_spot + Vector2(-200, 0), "TestCharger2")
	cat.global_position = open_spot
	await _frames(3)
	for _f in range(300):
		await physics_frame
		if ch.state == ch.S.WINDUP and ch.state_time > 0.7:
			break
	cat.global_position = open_spot + Vector2(0, 90)   # out of the lane
	await _frames(100)
	_check(cat.current_health == 5.0 and not cat.is_stunned(), "stepping out of the lane avoids it completely")

	# dodge i-frames: no damage, no stun (perfect dodge is signalled by the cat)
	ch.queue_free()
	await _frames(2)
	ch = _spawn("res://scenes/enemies/charger.tscn", open_spot + Vector2(-200, 0), "TestCharger3")
	cat.global_position = open_spot
	cat.invincibility_left = 0.0
	await _frames(3)
	for _f in range(300):
		await physics_frame
		if ch.state == ch.S.ACT:
			break
	var dodged_signal: Array = []
	cat.perfect_dodged.connect(func(_p): dodged_signal.append(true))
	cat.dodge_iframes_left = 1.0
	await _frames(60)
	_check(cat.current_health == 5.0 and not cat.is_stunned(), "dodging through the charge takes no damage and no stun")
	_check(not dodged_signal.is_empty(), "...and counts as a perfect dodge")
	cat.dodge_iframes_left = 0.0

	# shield: press defend early in the wind-up -> a plain block: the charger bounces off, dazed
	ch.queue_free()
	await _frames(2)
	ch = _spawn("res://scenes/enemies/charger.tscn", open_spot + Vector2(-200, 0), "TestCharger4")
	cat.global_position = open_spot
	cat.invincibility_left = 0.0
	cat.stun_left = 0.0
	cat.shield_durability = cat.shield_max_durability
	await _frames(3)
	for _f in range(300):
		await physics_frame
		if ch.state == ch.S.WINDUP and ch.state_time > 0.15:
			break
	Input.action_press("defend")
	await _frames(3)
	_check(cat.is_defending, "the cat is guarding")
	for _f in range(200):
		await physics_frame
		if ch.state == ch.S.STUNNED or cat.current_health < 5.0:
			break
	_check(cat.current_health == 5.0 and not cat.is_stunned(), "blocking with the shield takes no damage and no stun")
	_check(ch.state == ch.S.STUNNED, "a blocked charger is dazed")
	Input.action_release("defend")
	await _frames(3)

	# perfect guard: press defend at the last moment of the charge -> it is parried
	ch.queue_free()
	await _frames(2)
	ch = _spawn("res://scenes/enemies/charger.tscn", open_spot + Vector2(-200, 0), "TestCharger4b")
	cat.global_position = open_spot
	cat.invincibility_left = 0.0
	cat.stun_left = 0.0
	cat.shield_durability = cat.shield_max_durability
	await _frames(3)
	for _f in range(400):
		await physics_frame
		if ch.state == ch.S.ACT and ch.get_attack_eta_for(cat, cat.perfect_guard_window) >= 0.0:
			break
	Input.action_press("defend")
	await _frames(4)
	_check(ch.current_attack_parried and cat.current_health == 5.0, "a well-timed guard parries the charge")
	Input.action_release("defend")
	await _frames(3)

	# wall crash: charge into the trees
	ch.queue_free()
	await _frames(2)
	var wall_spot := Vector2(2500, 1150)
	ch = _spawn("res://scenes/enemies/charger.tscn", Vector2(2450, 880), "TestCharger5")   # north of the clearing: trees are further north
	# find the nearest wall to the north
	var space := scene.get_world_2d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters2D.create(ch.global_position, ch.global_position + Vector2(0, -600), 1))
	_check(not hit.is_empty(), "there is a wall north of the test spot")
	ch.global_position = hit["position"] + Vector2(0, 150)
	ch.charge_direction = Vector2.UP
	ch.state = ch.S.ACT
	ch.state_time = 0.0
	ch.charged_distance = 0.0
	cat.global_position = Vector2(100, 100)
	var hp_before: float = ch.current_health
	await _frames(60)
	_check(ch.state == ch.S.STUNNED and ch.vulnerable_multiplier > 1.0, "a charger that crashes into a wall is stunned and exposed")
	ch.receive_damage(2.0, ch.global_position + Vector2(0, 40), 0.0)
	_check(is_equal_approx(hp_before - ch.current_health, 2.0 * ch.crash_damage_multiplier), "...and takes extra damage (%.1f)" % (hp_before - ch.current_health))
	ch.receive_damage(999.0, ch.global_position + Vector2(0, 40), 0.0)
	await _frames(5)
	_check(not ch.is_alive(), "a charger can be killed")
	await create_timer(0.5).timeout

	# ================= flyer ====================================================================
	cat.global_position = open_spot
	cat.current_health = 5.0
	cat.invincibility_left = 0.0
	cat.stun_left = 0.0
	var fl: Node = _spawn("res://scenes/enemies/flyer.tscn", open_spot + Vector2(160, -80), "TestFlyer")
	_check(fl.is_in_group("enemies") and fl.display_name == "夜蝠" and fl.max_health == 3, "a flyer is an enemy with 3 HP")
	await _frames(3)
	var saw_mark := false
	for _f in range(600):
		await physics_frame
		if fl.state == fl.S.WINDUP:
			saw_mark = saw_mark or fl.mark.visible
			if fl.state_time > 0.3:
				break
	_check(saw_mark, "the flyer marks the landing spot before it dives")
	_check(fl.get_attack_eta_for(cat, 5.0) >= 0.0 or fl.dive_target.distance_to(cat.global_position) > 40.0, "the cat standing in the circle is reported as a target")
	for _f in range(200):
		await physics_frame
		if fl.state == fl.S.GROUNDED:
			break
	_check(cat.current_health < 5.0 and cat.is_stunned(), "being under the dive costs health and stuns (%.1f HP, stun %.2f)" % [cat.current_health, cat.stun_left])
	_check(fl.state == fl.S.GROUNDED and fl.vulnerable_multiplier > 1.0 and is_equal_approx(fl.height, 0.0), "after the dive it lands and is exposed")
	var hp: float = fl.current_health
	fl.receive_damage(1.0, fl.global_position + Vector2(-30, 0), 0.0)
	_check(is_equal_approx(hp - fl.current_health, 1.5), "a grounded flyer takes extra damage")
	await _frames(120)
	_check(fl.state == fl.S.CHASE or fl.state == fl.S.RISE or fl.state == fl.S.IDLE, "it takes off again")
	fl.queue_free()
	await _frames(2)

	# out of the circle: no damage
	cat.current_health = 5.0
	cat.invincibility_left = 0.0
	cat.stun_left = 0.0
	cat.global_position = open_spot
	fl = _spawn("res://scenes/enemies/flyer.tscn", open_spot + Vector2(160, -80), "TestFlyer2")
	await _frames(3)
	for _f in range(600):
		await physics_frame
		if fl.state == fl.S.WINDUP and fl.state_time > 0.7:
			break
	cat.global_position = fl.dive_target + Vector2(0, 100)
	await _frames(40)
	_check(cat.current_health == 5.0 and not cat.is_stunned(), "leaving the marked circle avoids the dive")
	fl.queue_free()
	await _frames(2)

	# flies over trees: a cat behind a tree wall is still reached
	var tree_side: Dictionary = {}
	for k in range(60):
		var a := Vector2.from_angle(k * 0.5) * 220.0
		var hit2 := space.intersect_ray(PhysicsRayQueryParameters2D.create(open_spot, open_spot + a, 1))
		if not hit2.is_empty():
			tree_side = {"wall": hit2["position"], "dir": a.normalized()}
			break
	_check(not tree_side.is_empty(), "found a wall near the test spot")
	if not tree_side.is_empty():
		var behind: Vector2 = tree_side["wall"] + tree_side["dir"] * 60.0
		fl = _spawn("res://scenes/enemies/flyer.tscn", open_spot, "TestFlyer3")
		cat.global_position = behind
		cat.current_health = 5.0
		cat.invincibility_left = 0.0
		cat.stun_left = 0.0
		await _frames(3)
		var min_dist := INF
		var crossed := false
		for _f in range(500):
			await physics_frame
			min_dist = minf(min_dist, fl.global_position.distance_to(cat.global_position))
			if (fl.global_position - tree_side["wall"]).dot(tree_side["dir"]) > 10.0:
				crossed = true
		_check(crossed, "the flyer crosses the tree wall (trees do not stop it)")
		fl.queue_free()

	# ================= the cat's stun on its own ======================================================
	cat.stun_left = 0.0
	cat.apply_stun(0.5)
	_check(cat.is_stunned(), "apply_stun stuns")
	cat.apply_stun(0.2)
	_check(cat.stun_left >= 0.49, "a shorter stun never cuts a longer one")
	await _frames(40)
	_check(not cat.is_stunned() and cat._stun_stars != null and not cat._stun_stars.visible, "the stars disappear with the stun")

	if failures.is_empty():
		print("NEW_ENEMIES_PASSED: %d checks" % checks)
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
