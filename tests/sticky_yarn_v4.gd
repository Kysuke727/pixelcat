extends SceneTree

## Sticky Yarn V4 acceptance tests.
## Covers the fixed 1.8 s bind, 1 s post-bind resistance, launch-time cooldown,
## single in-flight projectile, range/wall destruction, duplicate hit guards,
## death and control interactions, scene-switch recovery, old save/skill-point
## compatibility and the absence of YarnConnection instances.

const BIND_DURATION := 1.8
const RESISTANCE_DURATION := 1.0

var failures: Array[String] = []
var world: Node
var player: Node2D
var combat: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var progression := root.get_node("ProgressionManager")
	progression._test_mode = true
	progression.debug_session = false
	progression._load_profile_data({})

	await _build_world()
	_configure_combat()

	_check(InputMap.has_action("ranged_attack"), "K ranged input action is retained")
	_check(not InputMap.has_action("yarn_cut"), "Q yarn-cut input action is removed")
	_check(is_equal_approx(combat.projectile_range, 160.0), "base projectile range stays 160 px")
	_check(is_equal_approx(combat.projectile_speed, 220.0), "base projectile speed stays 220 px/s")
	_check(is_equal_approx(combat.ranged_cooldown, 4.0), "base ranged cooldown stays 4 seconds")
	_check(combat.ranged_damage == 1, "base ranged damage stays 1")
	_check(combat.has_method("on_sticky_yarn_hit"), "sticky-yarn hit handler exists")
	_check(not combat.has_method("on_yarn_hit"), "legacy connection hit handler is gone")
	_check(not combat.has_method("_cut_all_yarn_connections"), "yarn-cut ability is gone")
	_check(not combat.has_method("on_yarn_cut_reward"), "yarn-cut cooldown refund is gone")

	# 1) Plain hit applies damage + bind through the existing slime interface.
	var target := _spawn_slime(Vector2(560.0, 350.0))
	var health_before: float = target.current_health
	_fire(Vector2.RIGHT)
	await _wait_for_resolution()
	_check(target.current_health == health_before - 1.0, "normal hit deals exactly 1 ranged damage")
	_check(target.state == target.SlimeState.HURT, "normal hit still applies the existing hurt reaction")
	_check(is_equal_approx(target.bind_time_left, BIND_DURATION), "normal hit applies the fixed 1.8 s bind")
	_check(target.get_control_status()["bound"], "existing bind control status reports bound")
	_check(get_nodes_in_group("yarn_connections").is_empty(), "normal hit creates no YarnConnection node")

	# An existing bind does not block the next launch once the cooldown is over.
	combat.ranged_cooldown_left = 0.0
	combat._spawn_projectile()
	_check(combat.yarn_projectile_in_flight, "an active bind does not block a new launch after cooldown")
	get_nodes_in_group("yarn_projectiles").back().set_physics_process(false)
	await _clear_projectiles()
	_check(is_equal_approx(target.bind_time_left, BIND_DURATION), "clearing the next projectile leaves the active bind intact")

	# 2) Bind is exactly 1.8 s, freezes movement/attack, then AI resumes.
	target.state = target.SlimeState.CHASE
	target.state_time_left = 0.0
	target.target = player
	var position_at_bind: Vector2 = target.global_position
	target._physics_process(1.7)
	_check(target.bind_time_left > 0.0 and target.bind_time_left <= 0.11, "bind remains active just before 1.8 s")
	_check(target.global_position.distance_to(position_at_bind) < 0.01, "bound enemy cannot move")
	_check(not target.can_perform_attack(), "bound enemy cannot start an attack")
	_check(target.velocity == Vector2.ZERO, "bound enemy velocity is cleared")
	target._physics_process(0.12)
	_check(target.bind_time_left <= 0.001, "bind ends at 1.8 s")
	_check(is_equal_approx(target.bind_resistance_left, RESISTANCE_DURATION), "bind end grants exactly 1 s resistance")
	var position_at_release: Vector2 = target.global_position
	target._physics_process(0.1)
	_check(
		target.global_position.distance_to(position_at_release) > 0.0 or target.state == target.SlimeState.WINDUP,
		"AI resumes: approaches player or charges long leap after bind ends"
	)

	# 3) Resistance lasts 1 s and rejects a new bind without refreshing itself.
	target._physics_process(0.25)
	_check(is_equal_approx(target.bind_resistance_left, 0.65), "resistance counts down after bind ends")
	_check(not target.apply_yarn_bind(BIND_DURATION), "resistance rejects a new bind")
	_check(target.bind_time_left <= 0.001, "rejected bind does not start a bind timer")
	_check(is_equal_approx(target.bind_resistance_left, 0.65), "rejected bind does not refresh resistance")
	target._physics_process(0.75)
	_check(target.bind_resistance_left <= 0.001, "resistance expires after 1 s")
	_check(target.apply_yarn_bind(BIND_DURATION), "bind is allowed again after resistance expires")
	_check(not target.apply_yarn_bind(BIND_DURATION), "an active bind cannot be refreshed by a second bind")
	_check(is_equal_approx(target.bind_time_left, BIND_DURATION), "repeated bind attempt leaves the original duration intact")
	target.bind_time_left = 0.0
	target.bind_resistance_left = 0.0

	# 4) A hit during resistance still damages but cannot bind or extend resistance.
	target.current_health = target.max_health
	target.bind_resistance_left = 0.4
	target.global_position = Vector2(560.0, 350.0)
	health_before = target.current_health
	_fire(Vector2.RIGHT)
	await _wait_for_resolution()
	_check(target.current_health == health_before - 1.0, "immunity to bind does not cancel ranged damage")
	_check(target.bind_time_left <= 0.001, "hit during resistance does not bind")
	_check(is_equal_approx(target.bind_resistance_left, 0.4), "hit during resistance does not refresh the timer")

	# 5) Cooldown starts at actual launch, after wind-up, not at input time.
	await _clear_projectiles()
	_remove_slime(target)
	combat.ranged_cooldown_left = 0.0
	combat.yarn_projectile_in_flight = false
	player.last_facing = Vector2.RIGHT
	combat._start_ranged()
	combat.action_time = combat.ranged_windup - 0.01
	combat._update_action(0.0)
	_check(combat.ranged_cooldown_left == 0.0, "cooldown does not start during wind-up")
	_check(not combat.yarn_projectile_in_flight, "no projectile exists before wind-up completes")
	combat.action_time = combat.ranged_windup
	combat._update_action(0.0)
	_check(is_equal_approx(combat.ranged_cooldown_left, 4.0), "cooldown starts at 4 s when the projectile launches")
	_check(combat.yarn_projectile_in_flight, "launch marks the projectile in flight")
	combat._process(0.5)
	_check(is_equal_approx(combat.ranged_cooldown_left, 3.5), "cooldown continues counting down after launch")

	# 6) Range exhaustion and a wall destroy the projectile without a bind.
	await _clear_projectiles()
	player.global_position = Vector2(500.0, 350.0)
	player.last_facing = Vector2.RIGHT
	combat.facing = Vector2.RIGHT
	_fire(Vector2.RIGHT)
	await _wait_for_resolution(120)
	_check(not combat.yarn_projectile_in_flight, "range exhaustion releases the in-flight lock")
	_check(get_nodes_in_group("yarn_projectiles").is_empty(), "range exhaustion destroys the projectile")

	var wall := _spawn_wall(Vector2(580.0, 350.0), Vector2(20.0, 80.0))
	var behind_wall := _spawn_slime(Vector2(660.0, 350.0))
	health_before = behind_wall.current_health
	_fire(Vector2.RIGHT)
	await _wait_for_resolution()
	_check(not combat.yarn_projectile_in_flight, "wall impact releases the in-flight lock")
	_check(get_nodes_in_group("yarn_projectiles").is_empty(), "wall impact destroys the projectile")
	_check(behind_wall.current_health == health_before, "wall blocks the projectile from damaging an enemy behind it")
	_check(behind_wall.bind_time_left <= 0.001, "wall impact cannot bind an enemy behind it")
	_remove_slime(wall)
	_remove_slime(behind_wall)

	# 7) Only one projectile may fly, and one projectile can hit only once.
	await _clear_projectiles()
	var single_target := _spawn_slime(Vector2(560.0, 350.0))
	combat.ranged_cooldown_left = 0.0
	combat.yarn_projectile_in_flight = false
	combat.facing = Vector2.RIGHT
	combat._spawn_projectile()
	combat._spawn_projectile()
	_check(get_nodes_in_group("yarn_projectiles").size() == 1, "a second launch is rejected while one projectile is in flight")
	var projectile: Node = get_nodes_in_group("yarn_projectiles")[0]
	projectile.set_physics_process(false)
	health_before = single_target.current_health
	projectile._handle_hit(single_target)
	projectile._handle_hit(single_target)
	_check(single_target.current_health == health_before - 1.0, "duplicate hit callbacks deal damage only once")
	_check(is_equal_approx(single_target.bind_time_left, BIND_DURATION), "duplicate hit callbacks bind only once")
	await process_frame

	# 8) Death and existing control interactions.
	await _clear_projectiles()
	_remove_slime(single_target)
	var dying := _spawn_slime(Vector2(560.0, 350.0))
	dying.current_health = 1.0
	dying.fish_drop_min = 0
	dying.fish_drop_max = 0
	dying.bind_resistance_left = 0.0
	_fire(Vector2.RIGHT)
	await _wait_for_resolution()
	_check(dying.state == dying.SlimeState.DEAD, "lethal projectile damage still kills the slime")
	_check(dying.current_health == 0.0, "dead slime health reaches zero")
	_check(dying.bind_time_left <= 0.001, "a dead enemy receives no bind")
	_check(not dying.apply_yarn_bind(BIND_DURATION), "apply_yarn_bind rejects a dead enemy")

	var control_target := _spawn_slime(Vector2(520.0, 460.0))
	_check(control_target.apply_stun(1.0, 1.0), "existing stun control still works")
	_check(control_target.state == control_target.SlimeState.STUNNED, "stun state is unchanged by the sticky-yarn work")
	control_target.current_health = control_target.max_health
	_check(control_target.receive_damage(1.0, control_target.global_position - Vector2.RIGHT, 90.0), "existing hit reaction still accepts damage")
	_remove_slime(control_target)
	await process_frame

	# 9) Scene switch and forced combat disable never leave the launch lock on.
	await _clear_projectiles()
	player.global_position = Vector2(500.0, 350.0)
	combat.ranged_cooldown_left = 0.0
	combat.facing = Vector2.RIGHT
	_fire(Vector2.RIGHT)
	_check(combat.yarn_projectile_in_flight, "projectile is in flight before forced disable")
	combat.set_combat_enabled(false)
	_check(not combat.yarn_projectile_in_flight, "forced combat disable releases the launch lock")
	await process_frame
	combat.set_combat_enabled(true)
	_check(combat.action_state == combat.ActionState.IDLE, "forced combat disable cancels the ranged action")
	combat.ranged_cooldown_left = 0.0
	combat._spawn_projectile()
	_check(combat.yarn_projectile_in_flight, "combat can launch again after being re-enabled")

	await _teardown_world()
	await _build_world()
	_configure_combat()
	_check(not combat.yarn_projectile_in_flight, "a new scene starts with no projectile lock")
	_check(combat.ranged_cooldown_left == 0.0, "a new scene starts with no stale cooldown")
	combat.ranged_cooldown_left = 0.0
	combat._spawn_projectile()
	_check(combat.yarn_projectile_in_flight, "ranged firing works after a scene switch")
	await _wait_for_resolution()

	# External destruction (scene teardown, manual cleanup) must release the lock.
	combat.ranged_cooldown_left = 0.0
	combat._spawn_projectile()
	var stray_projectile: Node = get_nodes_in_group("yarn_projectiles").back()
	stray_projectile.queue_free()
	await process_frame
	_check(not combat.yarn_projectile_in_flight, "externally destroyed projectile releases the launch lock")

	# 10) Basic night combat regression: melee still works.
	_check(current_scene.is_in_group("night_exploration"), "night combat scene group is retained")
	_check(combat._is_night_combat_scene(), "combat still recognises night combat")
	_check(combat._can_start_action(), "combat actions are still allowed at night")
	var melee_target := _spawn_slime(player.global_position + Vector2(24.0, 0.0))
	player.last_facing = Vector2.RIGHT
	combat._start_melee(false)
	var melee_health: float = melee_target.current_health
	combat._try_damage_target(melee_target)
	_check(melee_target.current_health == melee_health - 1.0, "first claw attack still deals its configured damage")
	_check(combat.combo_window_open, "melee hit still opens the combo window")
	_remove_slime(melee_target)

	# 11) Old save format and old skill points survive; V4 ignores bind bonuses.
	progression._load_profile_data({
		"level": 9,
		"experience": 42,
		"available_points": 5,
		"attributes": {"vitality": 2, "attack": 3, "defense": 1, "agility": 1},
		"skill_points": {"slow": 15, "connection": 50, "bind": 20, "loop": 30},
		"permanent_hp_bonus": 1,
		"permanent_items": ["legacy_charm"],
		"currency": {"fish_count": 12},
	})
	_check(progression.level == 9 and progression.experience == 42, "old profile level and experience are preserved")
	_check(progression.available_points == 5, "old unspent points are preserved")
	_check(int(progression.skill_points["bind"]) == 20, "old bind skill points are not cleared")
	_check(int(progression.skill_points["loop"]) == 30, "old loop skill points are not cleared")
	_check(progression.permanent_hp_bonus == 1, "old permanent HP bonus is preserved")
	_check(progression.attributes["attack"] == 3, "old attributes are preserved")
	_check(is_equal_approx(progression.get_attack_multiplier(), 1.15), "old attack attribute still applies")
	_check(progression.get_save_data()["version"] == 1, "save format version is unchanged")
	var save_profile: Dictionary = progression.get_save_data()["profile"]
	_check(int(save_profile["skill_points"]["bind"]) == 20, "saved profile keeps legacy skill points")
	_check(is_equal_approx(float(progression.get_skill_modifiers()["bind_duration_bonus"]), 1.0), "legacy bind bonus remains readable for save compatibility")
	var bonus_target := _spawn_slime(Vector2(560.0, 350.0))
	combat.yarn_projectile_in_flight = true
	_check(combat.on_sticky_yarn_hit(bonus_target), "sticky bind applies with legacy skill points present")
	_check(is_equal_approx(bonus_target.bind_time_left, BIND_DURATION), "V4 ignores the legacy +1 s bind duration bonus")
	_remove_slime(bonus_target)

	# 12) Normal combat never instantiates YarnConnection.
	_check(get_nodes_in_group("yarn_connections").is_empty(), "no YarnConnection remains anywhere after all combat tests")
	_check(not combat.has_method("on_yarn_cut_reward"), "no yarn-cut reward entry point remains")

	_remove_slime(bonus_target)
	await process_frame
	await _teardown_world()

	if failures.is_empty():
		print("STICKY_YARN_V4_PASSED")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		quit(1)


func _build_world() -> void:
	world = load("res://scenes/worlds/night_world.tscn").instantiate()
	# The acceptance test does not need the night music; keeping it stopped also
	# avoids an AudioStreamPlayback leak when the scene is switched mid-test.
	var night_music := world.get_node_or_null("NightMusic")
	if night_music != null:
		night_music.autoplay = false
		night_music.stream = null
	root.add_child(world)
	current_scene = world
	await physics_frame
	player = get_first_node_in_group("player")
	combat = player.get_node("PlayerCombat")
	player.global_position = Vector2(500.0, 350.0)
	for enemy in get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
		enemy.global_position = Vector2(960.0, 660.0)
	await physics_frame


func _teardown_world() -> void:
	if not is_instance_valid(world):
		return
	# Stop audio before freeing the scene; otherwise the MP3 playback resource
	# can outlive the test process.
	for audio_player in world.find_children("*", "AudioStreamPlayer2D", true, false):
		audio_player.stop()
		audio_player.stream = null
	for audio_player in world.find_children("*", "AudioStreamPlayer", true, false):
		audio_player.stop()
		audio_player.stream = null
	current_scene = null
	world.queue_free()
	await process_frame
	await process_frame


func _configure_combat() -> void:
	player.set_physics_process(false)
	player.set_process(false)
	combat.set_process(false)
	combat.combat_enabled = true
	combat.ranged_cooldown_left = 0.0
	combat.yarn_projectile_in_flight = false
	combat.action_state = combat.ActionState.IDLE
	combat.facing = Vector2.RIGHT


func _spawn_slime(position: Vector2) -> CharacterBody2D:
	var slime: CharacterBody2D = load("res://scenes/enemies/slime.tscn").instantiate()
	world.add_child(slime)
	slime.global_position = position
	slime.set_physics_process(false)
	slime.set_process(false)
	return slime


func _spawn_wall(position: Vector2, size: Vector2) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.position = position
	wall.collision_layer = 1
	wall.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	shape.shape = rectangle
	wall.add_child(shape)
	world.add_child(wall)
	return wall


func _remove_slime(node: Node) -> void:
	if is_instance_valid(node):
		node.queue_free()


func _fire(direction: Vector2) -> void:
	combat.facing = direction
	combat.ranged_cooldown_left = 0.0
	combat.yarn_projectile_in_flight = false
	combat._spawn_projectile()


func _wait_for_resolution(max_frames: int = 120) -> void:
	for _frame in range(max_frames):
		if not combat.yarn_projectile_in_flight:
			break
		await physics_frame
	# Let queued deletion run so node-group assertions see the consumed projectile removed.
	await process_frame


func _clear_projectiles() -> void:
	for projectile in get_nodes_in_group("yarn_projectiles"):
		if is_instance_valid(projectile):
			projectile.queue_free()
	await process_frame
	if is_instance_valid(combat):
		combat.yarn_projectile_in_flight = false


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		failures.append(description)
