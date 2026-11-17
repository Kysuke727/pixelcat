extends "res://scripts/enemies/enemy_base.gd"

## 夜蝠 (flyer): flies over the trees (walls do not stop it), circles the cat, then marks a spot on
## the ground and dives at it. Get out of the marked circle (or dodge / guard at the last moment):
## a hit costs health AND stuns the cat. After a dive it lands for a moment and takes extra damage.

@export var fly_speed: float = 95.0
@export var circle_radius: float = 130.0
@export var dive_trigger_distance: float = 230.0
@export var windup_duration: float = 0.85
@export var aim_lock_time: float = 0.5
@export var dive_duration: float = 0.3
@export var hit_radius: float = 26.0
@export var attack_damage: int = 1
@export var attack_knockback: float = 130.0
@export var shield_cost: float = 30.0
@export var cat_stun_duration: float = 1.0
@export var grounded_duration: float = 1.1
@export var grounded_damage_multiplier: float = 1.5
@export var cooldown: float = 1.8
@export var altitude: float = 30.0      # how many pixels above its shadow it hovers

var cooldown_left: float = 1.2
var circle_angle: float = 0.0
var dive_target: Vector2
var dive_from: Vector2
var target_locked: bool = false
var hit_cat: bool = false
var height: float = 1.0                 # 1 = flying, 0 = on the ground
var shadow: Polygon2D
var mark: Polygon2D
var mark_ring: Line2D
var frame_a: Texture2D = preload("res://assets/characters/slime/flyer_a.png")
var frame_b: Texture2D = preload("res://assets/characters/slime/flyer_b.png")


func _setup() -> void:
	display_name = "夜蝠"
	circle_angle = randf() * TAU
	shadow = Polygon2D.new()
	var shape := PackedVector2Array()
	for i in range(14):
		shape.append(Vector2(cos(TAU * float(i) / 14.0) * 13.0, sin(TAU * float(i) / 14.0) * 5.0))
	shadow.polygon = shape
	shadow.color = Color(0, 0, 0, 0.35)
	shadow.z_index = -2
	shadow.light_mask = 0
	add_child(shadow)
	mark = Polygon2D.new()
	var disc := PackedVector2Array()
	for i in range(24):
		disc.append(Vector2.from_angle(TAU * float(i) / 24.0) * hit_radius)
	mark.polygon = disc
	mark.z_index = -3
	mark.light_mask = 0
	mark.top_level = true
	mark.visible = false
	add_child(mark)
	mark_ring = Line2D.new()
	var ring := disc.duplicate()
	ring.append(disc[0])
	mark_ring.points = ring
	mark_ring.width = 2.0
	mark_ring.z_index = -3
	mark_ring.light_mask = 0
	mark_ring.top_level = true
	mark_ring.visible = false
	add_child(mark_ring)
	# it flies: trees and lamps do not stop it, and it only needs to be hit by the cat's weapons
	collision_mask = 0


func _behave(delta: float) -> void:
	cooldown_left = maxf(cooldown_left - delta, 0.0)
	match state:
		S.IDLE:
			velocity = Vector2.ZERO
			height = move_toward(height, 1.0, delta * 3.0)
			if _target_distance() <= chase_range:
				_enter(S.CHASE)
		S.CHASE:
			_circle(delta)
		S.WINDUP:
			_windup(delta)
		S.ACT:
			_dive(delta)
		S.GROUNDED:
			velocity = Vector2.ZERO
			height = 0.0
			if state_time >= grounded_duration:
				vulnerable_multiplier = 1.0
				cooldown_left = cooldown
				_enter(S.RISE)
		S.RISE:
			height = move_toward(height, 1.0, delta * 4.0)
			if height >= 1.0:
				_enter(S.CHASE)
		S.RECOVER:
			_enter(S.CHASE)


func _circle(delta: float) -> void:
	if not is_instance_valid(target):
		return
	var distance := _target_distance()
	if distance > disengage_range:
		_enter(S.IDLE)
		return
	height = move_toward(height, 1.0, delta * 3.0)
	circle_angle += delta * 0.9
	var goal := target.global_position + Vector2.from_angle(circle_angle) * circle_radius
	velocity = global_position.direction_to(goal) * fly_speed
	if global_position.distance_to(goal) < 8.0:
		velocity = Vector2.ZERO
	global_position += velocity * delta
	if absf(velocity.x) > 1.0:
		facing = Vector2.RIGHT if velocity.x > 0.0 else Vector2.LEFT
	if cooldown_left <= 0.0 and distance <= dive_trigger_distance:
		dive_target = target.global_position
		target_locked = false
		hit_cat = false
		new_attack_id()
		_enter(S.WINDUP)


func _windup(_delta: float) -> void:
	velocity = Vector2.ZERO
	if not target_locked and state_time < aim_lock_time and is_instance_valid(target):
		dive_target = target.global_position
	elif not target_locked:
		target_locked = true
		HitFeel.ring(dive_target, HitFeel.RED, hit_radius + 6.0, 0.25)
	if state_time >= windup_duration:
		dive_from = global_position
		hit_cat = false
		_enter(S.ACT)
		HitFeel.play_sfx("flyer_dive")


func _dive(_delta: float) -> void:
	var t := clampf(state_time / dive_duration, 0.0, 1.0)
	var eased := t * t
	global_position = dive_from.lerp(dive_target, eased)
	height = 1.0 - eased
	if absf(dive_target.x - dive_from.x) > 1.0:
		facing = Vector2.RIGHT if dive_target.x > dive_from.x else Vector2.LEFT
	if t >= 1.0:
		_land()


func _land() -> void:
	global_position = dive_target
	height = 0.0
	HitFeel.dust(global_position, Vector2.UP)
	if is_instance_valid(target) and not current_attack_parried and target.global_position.distance_to(dive_target) <= hit_radius + 10.0:
		_hit_cat(target)
	vulnerable_multiplier = grounded_damage_multiplier
	_enter(S.GROUNDED)


func _hit_cat(cat: Node) -> void:
	if hit_cat:
		return
	hit_cat = true
	var health_before := float(cat.get("current_health"))
	if cat.has_method("receive_attack_damage"):
		cat.receive_attack_damage(current_attack_id, float(attack_damage), global_position, attack_knockback, shield_cost)
	var damaged := float(cat.get("current_health")) < health_before
	if damaged and cat.has_method("apply_stun"):
		cat.apply_stun(cat_stun_duration)
		HitFeel.impact(cat.global_position, Vector2.DOWN, 1.0, HitFeel.RED)


func _can_be_knocked_back() -> bool:
	return state != S.ACT and state != S.WINDUP and state != S.GROUNDED


func apply_stun(duration: float, immunity_duration: float = 1.0) -> bool:
	# a stunned flyer drops to the ground and is easy to hit
	var accepted := super.apply_stun(duration, immunity_duration)
	if accepted:
		height = 0.0
	return accepted


func _attack_eta(candidate: Node2D, max_window: float) -> float:
	if candidate.global_position.distance_to(dive_target) > hit_radius + 6.0:
		return -1.0
	var windup_left := maxf(windup_duration - state_time, 0.0) if state == S.WINDUP else 0.0
	var dive_left := dive_duration if state == S.WINDUP else maxf(dive_duration - state_time, 0.0)
	var eta := windup_left + dive_left
	return eta if eta <= max_window else -1.0


func _animate(_delta: float) -> void:
	sprite.flip_h = facing.x < 0.0
	var flapping := state != S.GROUNDED and state != S.STUNNED
	var bob := sin(Time.get_ticks_msec() / 160.0) * 2.0 * height
	sprite.position = Vector2(0.0, -altitude * height + bob)
	sprite.texture = frame_a if (not flapping or int(Time.get_ticks_msec() / 110.0) % 2 == 0) else frame_b
	var scale_target := Vector2.ONE
	base_color = Color.WHITE
	match state:
		S.WINDUP:
			var t := clampf(state_time / windup_duration, 0.0, 1.0)
			scale_target = Vector2(1.0 - 0.08 * t, 1.0 + 0.1 * t)
			base_color = Color(1.0, 1.0 - 0.3 * t, 1.0 - 0.4 * t)
		S.ACT:
			scale_target = Vector2(0.85, 1.25)
		S.GROUNDED, S.STUNNED:
			scale_target = Vector2(1.1, 0.9)
			base_color = Color(0.9, 0.9, 1.0)
	sprite.scale = scale_target
	# shadow shrinks with height
	shadow.scale = Vector2.ONE * lerpf(1.0, 0.55, height)
	shadow.color.a = lerpf(0.4, 0.2, height)
	_update_mark()


func _update_mark() -> void:
	var show := state == S.WINDUP or state == S.ACT
	mark.visible = show
	mark_ring.visible = show
	if not show:
		return
	var t := clampf(state_time / windup_duration, 0.0, 1.0) if state == S.WINDUP else 1.0
	var pulse := 0.5 + 0.5 * sin(state_time * (10.0 + 16.0 * t))
	mark.global_position = dive_target
	mark_ring.global_position = dive_target
	mark.color = Color(1.0, 0.25, 0.2, (0.2 if not target_locked else 0.36) + 0.14 * pulse)
	mark_ring.default_color = Color(1.0, 0.45, 0.35, 0.55 + 0.3 * pulse)
