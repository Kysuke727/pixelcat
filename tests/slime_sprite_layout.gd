extends SceneTree

## Guards the slime sprite layout: the four directional PNGs are single 64x64
## frames, so the Sprite2D must not divide them with hframes. Also checks that
## the scale-based wind-up/lunge bounce is preserved.

const SLIME_SCENE := "res://scenes/enemies/slime.tscn"
const DIRECTIONS := {
	"front": Vector2.DOWN,
	"back": Vector2.UP,
	"left": Vector2.LEFT,
	"right": Vector2.RIGHT,
}

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var slime: CharacterBody2D = load(SLIME_SCENE).instantiate()
	root.add_child(slime)
	await process_frame
	var sprite: Sprite2D = slime.get_node("Sprite2D")

	_check(sprite.hframes == 1, "Sprite2D hframes is 1 for single-frame directional art")
	_check(sprite.vframes == 1, "Sprite2D vframes is 1")
	_check(sprite.frame == 0, "Sprite2D starts on frame 0")
	_check(not sprite.region_enabled, "Sprite2D region is disabled")
	_check(sprite.region_rect == Rect2(), "Sprite2D has no region rect")

	for direction_name in DIRECTIONS:
		slime.facing = DIRECTIONS[direction_name]
		slime._update_sprite(0.0)
		var expected_path := "res://assets/characters/slime/slime_%s.png" % direction_name
		_check(sprite.texture.resource_path == expected_path, "facing %s uses its directional texture" % direction_name)
		_check(
			sprite.get_rect().size == Vector2(64.0, 64.0),
			"facing %s draws the complete 64x64 frame, not a cropped strip" % direction_name
		)
		_check(sprite.frame == 0, "facing %s stays on the single art frame" % direction_name)

	# Idle must not cycle through artificial frames.
	slime.facing = Vector2.DOWN
	slime.animation_time = 0.2
	slime.state = slime.SlimeState.IDLE
	slime._update_sprite(0.0)
	_check(sprite.frame == 0, "idle animation does not cycle cropped frames")
	_check(sprite.scale == Vector2.ONE, "idle scale is neutral")

	# Preserve the existing scale-based bounce.
	slime.state = slime.SlimeState.WINDUP
	slime._update_sprite(0.0)
	_check(sprite.scale == Vector2(1.08, 0.86), "wind-up squash/stretch bounce is preserved")
	_check(sprite.position == Vector2.ZERO, "wind-up bounce does not move the Sprite2D off-center")

	slime.state = slime.SlimeState.LUNGE
	slime._update_sprite(0.0)
	_check(sprite.scale == Vector2(0.92, 1.12), "lunge stretch bounce is preserved")
	_check(sprite.frame == 0, "lunge does not jump to a cropped frame")
	_check(sprite.position == Vector2.ZERO, "lunge bounce does not move the Sprite2D off-center")

	# Unrelated gameplay configuration must remain untouched.
	var body_shape: CollisionShape2D = slime.get_node("CollisionShape2D")
	var attack_shape: CollisionShape2D = slime.get_node("AttackArea/CollisionShape2D")
	_check(slime is CharacterBody2D, "slime remains a CharacterBody2D")
	_check(is_equal_approx((body_shape.shape as CircleShape2D).radius, 12.0), "body collision radius is unchanged")
	_check(is_equal_approx((attack_shape.shape as CircleShape2D).radius, 20.0), "attack area radius is unchanged")
	_check(slime.collision_layer == 2 and slime.collision_mask == 3, "slime collision layers are unchanged")
	_check(is_equal_approx(slime.move_speed, 35.0), "slime move speed is unchanged")

	slime.queue_free()
	await process_frame

	if failures.is_empty():
		print("SLIME_SPRITE_LAYOUT_PASSED")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		quit(1)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		failures.append(description)
