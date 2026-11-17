extends "res://scripts/enemies/enemy_base.gd"

## 冲撞怪 (charger): stands off, shows a red lane on the ground, then rushes down it. The cat must
## get out of the lane (or dodge / guard at the last moment). Getting hit costs health AND stuns
## the cat; a charger that crashes into a wall is stunned and takes extra damage.

@export var approach_speed: float = 62.0
@export var charge_speed: float = 340.0
@export var charge_range_min: float = 70.0
@export var charge_range_max: float = 270.0
@export var windup_duration: float = 0.9
@export var aim_lock_time: float = 0.55      # the lane keeps following the cat until this moment
@export var charge_max_distance: float = 300.0
@export var attack_damage: int = 2
@export var attack_knockback: float = 170.0
@export var shield_cost: float = 45.0
@export var cat_stun_duration: float = 1.3
@export var crash_stun_duration: float = 1.8
@export var crash_damage_multiplier: float = 1.6
@export var recover_duration: float = 0.8
@export var cooldown: float = 1.4
@export var lane_half_width: float = 20.0

var cooldown_left: float = 1.0
var charge_direction: Vector2 = Vector2.RIGHT
var charged_distance: float = 0.0
var lane_locked: bool = false
var hit_cat: bool = false
var lane: Polygon2D
var lane_edge: Line2D
var _wall_time: float = 0.0


func _setup() -> void:
	display_name = "冲撞怪"
	lane = Polygon2D.new()
	lane.z_index = -3
	lane.light_mask = 0
	lane.top_level = true
	lane.visible = false
	add_child(lane)
	lane_edge = Line2D.new()
	lane_edge.width = 2.0
	lane_edge.z_index = -3
	lane_edge.light_mask = 0
	lane_edge.top_level = true
	lane_edge.visible = false
	add_child(lane_edge)


func _behave(delta: float) -> void:
	cooldown_left = maxf(cooldown_left - delta, 0.0)
	match state:
		S.IDLE:
			velocity = Vector2.ZERO
			if _target_distance() <= chase_range:
				_enter(S.CHASE)
		S.CHASE:
			_chase(delta)
		S.WINDUP:
			_windup(delta)
		S.ACT:
			_charge(delta)
		S.RECOVER:
			velocity = Vector2.ZERO
			if state_time >= recover_duration:
				cooldown_left = cooldown
				_enter(S.CHASE if _target_distance() <= disengage_range else S.IDLE)


func _chase(delta: float) -> void:
	if not is_instance_valid(target):
		return
	var distance := _target_distance()
	if distance > disengage_range:
		_enter(S.IDLE)
		return
	if cooldown_left <= 0.0 and distance >= charge_range_min and distance <= charge_range_max and clear_line_to(target.global_position):
		charge_direction = global_position.direction_to(target.global_position)
		lane_locked = false
		new_attack_id()
		hit_cat = false
		_enter(S.WINDUP)
		return
	var aim := path_aim_point(target.global_position, delta)
	if aim == Vector2.INF:
		_enter(S.IDLE)
		return
	# keep some distance: back off when the cat is very close so the lane has room
	var direction := global_position.direction_to(aim)
	if distance < charge_range_min:
		direction = -global_position.direction_to(target.global_position)
	velocity = direction * approach_speed
	if absf(velocity.x) > 1.0:
		facing = Vector2.RIGHT if velocity.x > 0.0 else Vector2.LEFT
	move_and_slide()


func _windup(_delta: float) -> void:
	velocity = Vector2.ZERO
	if not lane_locked and state_time < aim_lock_time and is_instance_valid(target):
		charge_direction = global_position.direction_to(target.global_position)
	elif not lane_locked:
		lane_locked = true
		HitFeel.ring(global_position, HitFeel.RED, 26.0, 0.2)
	if absf(charge_direction.x) > 0.1:
		facing = Vector2.RIGHT if charge_direction.x > 0.0 else Vector2.LEFT
	if state_time >= windup_duration:
		charged_distance = 0.0
		_wall_time = 0.0
		_enter(S.ACT)
		HitFeel.dust(global_position, charge_direction)
		HitFeel.play_sfx("charger_rush")


func _charge(delta: float) -> void:
	velocity = charge_direction * charge_speed
	var step_before := global_position
	move_and_slide()
	charged_distance += global_position.distance_to(step_before)
	if state_time * 60.0 > 1.0 and int(state_time * 60.0) % 3 == 0:
		HitFeel.dust(global_position, charge_direction)
	for index in range(get_slide_collision_count()):
		var collider := get_slide_collision(index).get_collider()
		if collider is Node and collider.is_in_group("player"):
			_hit_cat(collider)
			if state != S.ACT:
				return
		elif collider is Node and not collider.is_in_group("enemies"):
			_crash()
			return
	if charged_distance >= charge_max_distance:
		velocity = Vector2.ZERO
		_enter(S.RECOVER)


func _hit_cat(cat: Node) -> void:
	if hit_cat or current_attack_parried:
		return
	hit_cat = true
	var health_before := float(cat.get("current_health"))
	if cat.has_method("receive_attack_damage"):
		cat.receive_attack_damage(current_attack_id, float(attack_damage), global_position, attack_knockback, shield_cost)
	var damaged := float(cat.get("current_health")) < health_before
	if damaged and cat.has_method("apply_stun"):
		cat.apply_stun(cat_stun_duration)
		HitFeel.impact(cat.global_position, charge_direction, 1.2, HitFeel.RED)
	velocity = Vector2.ZERO
	if damaged:
		_enter(S.RECOVER)
	elif is_instance_valid(cat) and cat.get("is_defending") == true:
		# blocked with the shield: the charger bounces off and is dazed
		apply_stun(1.0, 1.0)
	# dodged (no damage, not blocked): it just keeps running and ends up past the cat


func _crash() -> void:
	velocity = Vector2.ZERO
	HitFeel.impact(global_position + charge_direction * 16.0, charge_direction, 1.4, HitFeel.GOLD)
	HitFeel.shake(0.4)
	HitFeel.hit_stop(0.06)
	vulnerable_multiplier = crash_damage_multiplier
	apply_stun(crash_stun_duration, 1.0)
	HitFeel.damage_number(global_position + Vector2(0.0, -30.0), "撞晕了！", HitFeel.GOLD, 15)


func _can_be_knocked_back() -> bool:
	return state != S.ACT and state != S.WINDUP


func _attack_eta(candidate: Node2D, max_window: float) -> float:
	var offset := candidate.global_position - global_position
	var along := offset.dot(charge_direction)
	if along < 0.0 or absf(offset.cross(charge_direction)) > lane_half_width + 6.0 or along > charge_max_distance:
		return -1.0
	var windup_left := maxf(windup_duration - state_time, 0.0) if state == S.WINDUP else 0.0
	var eta := windup_left + maxf(along - 18.0, 0.0) / charge_speed
	return eta if eta <= max_window else -1.0


func _animate(delta: float) -> void:
	sprite.flip_h = facing.x < 0.0
	var scale_target := Vector2.ONE
	base_color = Color.WHITE
	var offset := Vector2.ZERO
	match state:
		S.WINDUP:
			var t := clampf(state_time / windup_duration, 0.0, 1.0)
			scale_target = Vector2(1.0 + 0.1 * t, 1.0 - 0.14 * t)
			offset = Vector2(sin(state_time * 55.0) * 1.5 * t, 0.0)    # trembling, ready to rush
			base_color = Color(1.0, 1.0 - 0.35 * t, 1.0 - 0.45 * t)
		S.ACT:
			scale_target = Vector2(1.2, 0.86)
		S.STUNNED:
			scale_target = Vector2(1.05, 0.92)
			base_color = Color(0.85, 0.85, 1.0)
		S.RECOVER:
			scale_target = Vector2(1.06, 0.94)
		_:
			var bob := sin(Time.get_ticks_msec() / 220.0) * 0.03
			scale_target = Vector2(1.0 + bob, 1.0 - bob)
	sprite.scale = sprite.scale.lerp(scale_target, clampf(delta * 18.0, 0.0, 1.0))
	sprite.position = offset
	_update_lane()


func _update_lane() -> void:
	var show := state == S.WINDUP
	lane.visible = show
	lane_edge.visible = show
	if not show:
		return
	var t := clampf(state_time / windup_duration, 0.0, 1.0)
	var length := charge_max_distance
	var side := charge_direction.orthogonal() * lane_half_width
	var origin := global_position
	var end := origin + charge_direction * length
	lane.global_position = Vector2.ZERO
	lane.polygon = PackedVector2Array([origin + side, end + side, end - side, origin - side])
	var pulse := 0.5 + 0.5 * sin(state_time * (10.0 + 14.0 * t))
	var alpha := (0.24 if not lane_locked else 0.4) + 0.14 * pulse
	lane.color = Color(1.0, 0.25, 0.2, alpha)
	lane_edge.global_position = Vector2.ZERO
	lane_edge.points = PackedVector2Array([origin + side, end + side, end - side, origin - side, origin + side])
	lane_edge.default_color = Color(1.0, 0.45, 0.35, 0.55 + 0.3 * pulse)
