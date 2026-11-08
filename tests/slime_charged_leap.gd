extends SceneTree

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var progression: Node = root.get_node("ProgressionManager")
	progression._test_mode = true
	var slime: CharacterBody2D = load("res://scenes/enemies/slime.tscn").instantiate()
	root.add_child(slime)
	await process_frame
	slime.set_physics_process(false)
	var cat := Node2D.new()
	cat.position = Vector2(120, 0)
	root.add_child(cat)
	slime.target = cat
	slime.position = Vector2.ZERO
	var body_collision: CollisionShape2D = slime.get_node("CollisionShape2D")
	var collision_shape: Shape2D = body_collision.shape
	_check(slime.attack_range >= 120.0, "attack trigger reaches cat beyond melee range")
	_check(slime.lunge_speed * slime.lunge_duration >= 115.0, "attack covers at least 115 px with default tuning")
	_check(slime.windup_duration >= 0.6, "charge-up lasts long enough to read")
	slime.state = slime.SlimeState.CHASE
	slime.cooldown_left = 0.0
	slime._process_chase()
	_check(slime.state == slime.SlimeState.WINDUP, "cat at 120 px triggers distinct WINDUP")
	_check(slime.velocity == Vector2.ZERO, "charging stops the slime's movement")
	_check(slime.locked_target_position == cat.global_position, "windup targets cat's position")
	_check(slime.state_time_left == slime.windup_duration, "windup uses tuned charge duration")
	slime.attack_state_elapsed = slime.windup_duration * 0.95
	slime._update_sprite(0.05)
	var sprite: Sprite2D = slime.get_node("Sprite2D")
	_check(sprite.scale.x > 1.2 and sprite.scale.y < 0.8, "charge telegraph visibly squashes slime")
	cat.position = Vector2(120, 100)
	slime.state_time_left = 0
	slime._process_windup()
	_check(slime.state == slime.SlimeState.LUNGE, "windup launches a true LUNGE attack")
	_check(slime.lunge_direction.dot(Vector2.RIGHT) > 0.95, "leap is committed to warned target, not homing")
	slime.attack_state_elapsed = slime.lunge_duration * 0.5
	slime._update_sprite(0.05)
	_check(sprite.position.y < -12.0, "leap sprite reaches clear airborne height")
	_check(slime.get_node("JellyShadow").scale.x < 0.88, "shadow shrinks under a high leap")
	var start := slime.global_position
	for index in range(25):
		await physics_frame
		slime._process_lunge()
	var traveled := slime.global_position.distance_to(start)
	_check(traveled > 85.0, "long leap actually moves character more than 85 px: %.1f" % traveled)
	_check(collision_shape == body_collision.shape, "jump does not replace collision shape")
	_check(not is_instance_valid(cat) or slime.lunge_direction.x > 0.95, "target movement does not steer midair")
	slime.state = slime.SlimeState.LUNGE
	slime.current_attack_id = 123
	slime.current_attack_parried = false
	_check(slime.parry_attack(123), "existing parry still interrupts the long leap")
	_check(slime.state == slime.SlimeState.RECOVER, "successful parry cancels leap into recovery")
	slime.queue_free()
	cat.queue_free()
	await process_frame
	progression._test_mode = false
	if failures.is_empty():
		print("SLIME_CHARGED_LEAP_PASSED: %d checks" % checks)
		quit(0)
	else:
		for msg in failures:
			printerr("FAIL: ", msg)
		printerr("SLIME_CHARGED_LEAP_FAILED: %d/%d" % [failures.size(), checks])
		quit(1)


func _check(ok: bool, desc: String) -> void:
	checks += 1
	if not ok:
		failures.append(desc)
