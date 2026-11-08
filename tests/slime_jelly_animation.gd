extends SceneTree

const MOTION := preload("res://scripts/enemies/slime_jelly_motion.gd")
var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var progression = root.get_node("ProgressionManager")
	progression._test_mode = true
	var slime: CharacterBody2D = load("res://scenes/enemies/slime.tscn").instantiate()
	root.add_child(slime)
	await process_frame
	var sprite: Sprite2D = slime.get_node("Sprite2D")
	var shadow: Node2D = slime.get_node("JellyShadow")
	var collision: CollisionShape2D = slime.get_node("CollisionShape2D")
	var attack: Area2D = slime.get_node("AttackArea")
	var collision_position := collision.position
	var collision_scale := collision.scale
	var shape_radius: float = collision.shape.radius
	var attack_position := attack.position
	var attack_scale := attack.scale
	var base_sprite := sprite.position
	var base_body := slime.position
	_check(shadow != null and shadow.get_child_count() == 0, "flat procedural shadow is separate from sprite")
	_check(sprite.texture != null, "existing four-direction slime sprite remains present")

	var pressed: Dictionary = MOTION.sample(0.14)
	var airborne: Dictionary = MOTION.sample(0.53)
	var landed: Dictionary = MOTION.sample(0.83)
	_check(pressed["scale"].x > 1.12 and pressed["scale"].y < 0.86, "anticipation widens and squashes jelly")
	_check(airborne["offset"] <= -6.8 and airborne["airborne"] > 0.95, "slime lifts visually at the top of its arc")
	_check(landed["scale"].x > 1.15 and landed["scale"].y < 0.85, "landing briefly splats down")
	_check(MOTION.sample(0.0)["scale"].is_equal_approx(Vector2.ONE), "start of hop has regular scale")
	_check(MOTION.sample(1.0)["scale"].is_equal_approx(Vector2.ONE), "end of hop returns to regular scale")

	# Prevent real movement / physics from changing a collision metric while
	# driving visual updates with a controlled simulated timer.
	slime.velocity = Vector2(35, 0)
	slime.state = slime.SlimeState.CHASE
	slime.visual_smoothing = 40.0
	var min_y := 0.0
	var max_x := 1.0
	var min_shadow_x := 1.0
	for i in range(35):
		slime._update_sprite(0.016)
		min_y = minf(min_y, sprite.position.y - base_sprite.y)
		max_x = maxf(max_x, sprite.scale.x)
		min_shadow_x = minf(min_shadow_x, shadow.scale.x)
	_check(min_y < -3.0, "CHASE animation repeatedly leaves ground visually")
	_check(max_x > 1.07, "CHASE animation shows squash before takeoff")
	_check(shadow.position == Vector2(0, 16), "floor shadow stays at ground position")
	_check(min_shadow_x < 0.85, "airborne shadow contracts under the slime")
	_check(collision.position == collision_position and collision.scale == collision_scale, "body collision transform is untouched")
	_check(is_equal_approx(collision.shape.radius, shape_radius), "body hitbox size remains untouched")
	_check(attack.position == attack_position and attack.scale == attack_scale, "attack area is not animated")
	_check(slime.position == base_body, "jelly movement never changes CharacterBody2D position")

	for direction in [Vector2.UP, Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN]:
		slime.facing = direction
		slime._update_sprite(0.02)
		_check(sprite.texture != null and sprite.texture.get_size() == Vector2(64, 64), "each facing retains original 64x64 artwork")

	slime.state = slime.SlimeState.WINDUP
	slime.attack_state_elapsed = slime.windup_duration * 0.9
	slime._update_sprite(0.1)
	_check(sprite.scale.x > 1.1 and sprite.scale.y < 0.9, "WINDUP is compressed")
	slime.state = slime.SlimeState.LUNGE
	slime.attack_state_elapsed = slime.lunge_duration * 0.13
	slime._update_sprite(0.1)
	_check(sprite.scale.y > 1.1 and sprite.position.y < base_sprite.y, "LUNGE stretches and hops")
	slime.state = slime.SlimeState.HURT
	slime.state_time_left = slime.hurt_duration
	slime._update_sprite(0.1)
	_check(sprite.scale.x > 1.1 and sprite.scale.y < 0.85, "HURT splats")
	slime.state = slime.SlimeState.STUNNED
	slime._update_sprite(0.1)
	_check(sprite.scale.x > 1.03 and sprite.scale.y < 0.96, "STUNNED stays mildly compressed")
	slime.state = slime.SlimeState.CHASE
	slime.bind_time_left = 1.0
	slime._update_sprite(0.1)
	_check(sprite.scale.x > 1.08 and sprite.scale.y < 0.90, "BIND keeps slime on the ground")
	_check(sprite.position.y >= base_sprite.y, "BOUND slime does not visually hop")
	slime.bind_time_left = 0.0
	slime.state = slime.SlimeState.IDLE
	slime.animation_time = 0.3
	slime._update_sprite(0.1)
	_check(absf(sprite.scale.x - 1.0) < 0.06, "IDLE breathes softly without drastic deformation")

	slime.queue_free()
	await process_frame
	progression._test_mode = false
	if failures.is_empty():
		print("SLIME_JELLY_ANIMATION_PASSED: %d checks" % checks)
		quit(0)
	else:
		for detail in failures:
			printerr("FAIL: ", detail)
		printerr("SLIME_JELLY_ANIMATION_FAILED: %d/%d" % [failures.size(), checks])
		quit(1)


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
