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
	_settle(slime)
	_check(sprite.frame == 0, "idle animation does not cycle cropped frames")
	_check(
		absf(sprite.scale.x - 1.0) <= 0.03 and absf(sprite.scale.y - 1.0) <= 0.03,
		"idle scale stays within the subtle breathing range"
	)
	_check(_stays_centered(slime, sprite, 2.0), "idle breathing only moves the Sprite2D vertically, by a little")

	# Jelly motion is smoothed, so settle on the target before asserting.
	# A full wind-up squashes wide and low (pulse term is zero at full charge).
	slime.state = slime.SlimeState.WINDUP
	slime.attack_state_elapsed = slime.windup_duration
	_settle(slime)
	_check(
		sprite.scale.is_equal_approx(Vector2(1.30, 0.72)),
		"wind-up squash/stretch bounce is preserved"
	)
	_check(_stays_centered(slime, sprite, 6.0), "wind-up bounce does not move the Sprite2D off-center")

	# Mid-flight of the lunge: scale crosses through (1.01, 1.01) and the
	# artwork is lifted about 18 px above its resting position.
	slime.state = slime.SlimeState.LUNGE
	slime.attack_state_elapsed = slime.lunge_duration * 0.5
	_settle(slime)
	_check(
		sprite.scale.is_equal_approx(Vector2(1.01, 1.01)),
		"lunge stretch bounce is preserved"
	)
	_check(
		sprite.position.y < slime.jelly_base_position.y - 15.0,
		"lunge lifts the artwork off the ground"
	)
	_check(sprite.frame == 0, "lunge does not jump to a cropped frame")
	_check(_stays_centered(slime, sprite, 24.0), "lunge bounce does not move the Sprite2D off-center")

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


# Run the smoothed visual update long enough to reach its target values.
func _settle(slime: Node) -> void:
	for _i in 120:
		slime._update_sprite(0.1)


# Jelly offsets are vertical only: x must stay on the base position and the
# vertical travel must stay within max_travel pixels.
func _stays_centered(slime: Node, sprite: Sprite2D, max_travel: float) -> bool:
	var delta: Vector2 = sprite.position - slime.jelly_base_position
	return is_zero_approx(delta.x) and absf(delta.y) <= max_travel
