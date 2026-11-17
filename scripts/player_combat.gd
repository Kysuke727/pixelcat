extends Node2D

## ATTACK3, POUNCE and COUNTER are learnable moves (see MoveCatalog); they are
## appended so the numeric values of the original states never change.
enum ActionState { IDLE, ATTACK1, ATTACK2, RECOVERY, RANGED, ATTACK3, POUNCE, COUNTER }

## Sticky Yarn V4: a hit applies a fixed bind through the enemy's existing
## apply_yarn_bind() interface. No YarnConnection, wrapping, pivot or tension
## simulation is created, and the old skill-tree bind duration bonus is ignored.
const STICKY_YARN_BIND_DURATION := 1.8

@export_category("Melee")
@export var melee_damage: int = 2
@export var first_melee_damage: int = 1
@export var melee_cooldown: float = 0.45
@export var melee_duration: float = 0.25
@export var melee_active_start: float = 0.08
@export var melee_active_end: float = 0.16
@export var melee_movement_multiplier: float = 0.65
@export var melee_knockback: float = 150.0
@export_category("Combo")
@export var combo_window: float = 0.35
@export var stun_duration: float = 1.0
@export var control_immunity_duration: float = 1.0
@export_range(0.0, 1.0) var combo_stun_chance: float = 0.5

# Learnable-move tuning (filled from CombatV3Tuning in _apply_combat_tuning).
var third_claw_damage: float = 3.0
var third_claw_knockback_multiplier: float = 1.5
var third_claw_hitbox_scale: float = 1.5
var pounce_damage: float = 3.0
var pounce_distance: float = 80.0
var pounce_move_duration: float = 0.18
var pounce_duration: float = 0.32
var pounce_recovery: float = 0.75
var pounce_hitbox_scale: float = 1.4
var counter_claw_damage: float = 2.0
var counter_claw_hitbox_scale: float = 1.25
var combo_reward_fish: int = 1
var combo_reward_mood: float = 3.0
## Which claw swing a continued combo starts next (2 or 3).
var combo_next_step: int = 2
var reward_given_attack_id: int = 0
var reward_rng := RandomNumberGenerator.new()
# Backstab crit (tuned in CombatV3Tuning, "绕背暴击").
var backstab_crit_chance: float = 0.5
var crit_damage_multiplier: float = 2.0
var backstab_dot_threshold: float = -0.5
var crit_rng := RandomNumberGenerator.new()

static var _next_melee_attack_id: int = 1000000
var current_melee_attack_id: int = 0

@export_category("Ranged")
@export var projectile_scene: PackedScene
@export var ranged_damage: int = 1
@export var ranged_cooldown: float = 4.0
@export var ranged_duration: float = 0.30
@export var ranged_windup: float = 0.12
@export var projectile_speed: float = 220.0
@export var projectile_range: float = 160.0
@export var ranged_movement_multiplier: float = 0.8

var action_state: int = ActionState.IDLE
var action_time: float = 0.0
var melee_cooldown_left: float = 0.0
var ranged_cooldown_left: float = 0.0
var combo_window_left: float = 0.0
var combo_window_open: bool = false
var combo_hit_feedback_left: float = 0.0
## What the HUD shows while combo_hit_feedback_left > 0 (set by the move that just hit).
var combo_feedback_text: String = "二连命中！史莱姆可能眩晕"
var buffered_combo: bool = false
var combo_stun_targets: Dictionary = {}
var stun_rng := RandomNumberGenerator.new()
var combat_enabled: bool = true
var projectile_fired: bool = false
var yarn_projectile_in_flight: bool = false
var active_yarn_projectile: Node2D
var melee_window_open: bool = false
var hit_targets: Dictionary = {}
var facing: Vector2 = Vector2.DOWN
var using_formal_animation: bool = false
var slash_spawned: bool = false
var sprite_base_position: Vector2
var sprite_base_rotation: float
var sprite_base_scale: Vector2

@onready var player = get_parent()
@onready var sprite: AnimatedSprite2D = get_parent().get_node("AnimatedSprite2D")
@onready var melee_hitbox: Area2D = $MeleeHitbox
@onready var melee_shape: CollisionShape2D = $MeleeHitbox/CollisionShape2D
@onready var attack_arc: Line2D = $AttackArc


func _ready() -> void:
	_apply_combat_tuning()
	stun_rng.randomize()
	reward_rng.randomize()
	crit_rng.randomize()
	sprite_base_position = sprite.position
	sprite_base_rotation = sprite.rotation
	sprite_base_scale = sprite.scale
	melee_hitbox.monitoring = false
	attack_arc.visible = false
	melee_hitbox.body_entered.connect(_on_melee_body_entered)


func _process(delta: float) -> void:
	melee_cooldown_left = maxf(melee_cooldown_left - delta, 0.0)
	ranged_cooldown_left = maxf(ranged_cooldown_left - delta, 0.0)
	combo_hit_feedback_left = maxf(combo_hit_feedback_left - delta, 0.0)
	if combo_window_open:
		combo_window_left = maxf(combo_window_left - delta, 0.0)
		if combo_window_left <= 0.0:
			combo_window_open = false
			buffered_combo = false
	if _is_melee_state(action_state):
		if _can_chain_from(action_state) and combo_window_open and Input.is_action_just_pressed("melee_attack"):
			buffered_combo = true
		var previous_action_time := action_time
		action_time += delta
		_update_action(previous_action_time)
		return
	if action_state == ActionState.RANGED:
		var previous_action_time := action_time
		action_time += delta
		_update_action(previous_action_time)
		return
	if action_state == ActionState.RECOVERY and melee_cooldown_left <= 0.0 and not combo_window_open:
		action_state = ActionState.IDLE

	if not _can_start_action():
		return
	if Input.is_action_just_pressed("melee_attack"):
		if _try_start_special_move():
			pass
		elif combo_window_open:
			_start_melee(true)
		elif action_state == ActionState.IDLE and melee_cooldown_left <= 0.0:
			_start_melee(false)
	elif (
		Input.is_action_just_pressed("ranged_attack")
		and ranged_cooldown_left <= 0.0
		and not yarn_projectile_in_flight
	):
		_start_ranged()


func _can_start_action() -> bool:
	if not combat_enabled or not _is_night_combat_scene() or InventoryManager.ui_open:
		return false
	if player.has_method("can_perform_combat_action"):
		return player.can_perform_combat_action()
	if player.has_method("is_alive") and not player.is_alive():
		return false
	if player.has_method("is_in_hitstun") and player.is_in_hitstun():
		return false
	if player.has_method("is_guard_broken") and player.is_guard_broken():
		return false
	if player.get("is_defending") == true:
		return false
	return true


func _is_night_combat_scene() -> bool:
	var scene := get_tree().current_scene
	return scene != null and scene.is_in_group("night_exploration")


func _is_melee_state(state: int) -> bool:
	return (
		state == ActionState.ATTACK1
		or state == ActionState.ATTACK2
		or state == ActionState.ATTACK3
		or state == ActionState.POUNCE
		or state == ActionState.COUNTER
	)


## Can this swing be continued into the next one by pressing the attack button again?
func _can_chain_from(state: int) -> bool:
	return state == ActionState.ATTACK1 or (state == ActionState.ATTACK2 and ProgressionManager.has_move("triple_combo"))


## Kept for compatibility: `true` continues the combo (second claw, or third when unlocked).
func _start_melee(is_second_attack: bool = false) -> void:
	_start_melee_step(clampi(combo_next_step, 2, 3) if is_second_attack else 1)


func _start_melee_step(step: int) -> void:
	current_melee_attack_id = _next_melee_attack_id
	_next_melee_attack_id += 1
	match step:
		3:
			action_state = ActionState.ATTACK3
		2:
			action_state = ActionState.ATTACK2
		_:
			action_state = ActionState.ATTACK1
	action_time = 0.0
	melee_cooldown_left = melee_cooldown
	melee_window_open = false
	hit_targets.clear()
	slash_spawned = false
	if step >= 2:
		combo_window_open = false
		combo_window_left = 0.0
		buffered_combo = false
	else:
		combo_stun_targets.clear()
		combo_next_step = 2
	facing = _get_facing()
	_update_hitbox_transform()
	_begin_action_visual("attack")
	attack_arc.visible = false   # the slash effect (HitFeel.slash) replaces the old triangle


## Moves that start from a special situation instead of the normal combo:
## the counter claw (just after a perfect dodge) and the pounce (just after a dash).
func _try_start_special_move() -> bool:
	if action_state != ActionState.IDLE and action_state != ActionState.RECOVERY:
		return false
	if (
		ProgressionManager.has_move("counter_claw")
		and player.has_method("is_counter_window_open")
		and player.is_counter_window_open()
	):
		_start_special(ActionState.COUNTER)
		return true
	if (
		ProgressionManager.has_move("pounce")
		and player.has_method("can_pounce")
		and player.can_pounce()
	):
		_start_special(ActionState.POUNCE)
		return true
	return false


func _start_special(state: int) -> void:
	current_melee_attack_id = _next_melee_attack_id
	_next_melee_attack_id += 1
	action_state = state
	action_time = 0.0
	melee_window_open = false
	hit_targets.clear()
	slash_spawned = false
	combo_window_open = false
	combo_window_left = 0.0
	buffered_combo = false
	melee_cooldown_left = pounce_recovery if state == ActionState.POUNCE else melee_cooldown
	facing = _get_facing()
	_update_hitbox_transform()
	_begin_action_visual("attack")
	attack_arc.visible = false   # the slash effect (HitFeel.slash) replaces the old triangle
	if state == ActionState.POUNCE:
		var direction: Vector2 = player.get_last_facing() if player.has_method("get_last_facing") else facing
		player.start_pounce(direction, pounce_distance, pounce_move_duration)
	elif player.has_method("consume_counter_window"):
		player.consume_counter_window()


func _start_ranged() -> void:
	action_state = ActionState.RANGED
	action_time = 0.0
	projectile_fired = false
	combo_window_open = false
	combo_window_left = 0.0
	buffered_combo = false
	facing = _get_facing()
	_begin_action_visual("cast")


## (active start, active end, total duration) of the current melee-type action.
func _melee_timings() -> Vector3:
	match action_state:
		ActionState.POUNCE:
			return Vector3(0.03, 0.2, pounce_duration)
		ActionState.COUNTER:
			return Vector3(0.03, 0.12, 0.2)
		_:
			return Vector3(melee_active_start, melee_active_end, melee_duration)


func _update_action(previous_action_time: float = -1.0) -> void:
	if _is_melee_state(action_state):
		var timings := _melee_timings()
		var active_start := timings.x
		var active_end := timings.y
		var duration := timings.z
		var previous_time := action_time if previous_action_time < 0.0 else previous_action_time
		if not slash_spawned and action_time >= active_start * 0.6:
			slash_spawned = true
			_spawn_slash()
		if not melee_window_open and previous_time < active_start and action_time >= active_end:
			_apply_melee_shape_query()
		elif not melee_window_open and previous_time < active_end and action_time >= active_start:
			_set_melee_window(true)
		if melee_window_open:
			_apply_overlapping_melee_hits()
		if melee_window_open and action_time >= active_end:
			_set_melee_window(false)
		_update_fallback_visual(action_time / duration)
		if action_time >= duration:
			_finish_action()
	elif action_state == ActionState.RANGED:
		if not projectile_fired and action_time >= ranged_windup:
			projectile_fired = true
			_spawn_projectile()
		_update_fallback_visual(action_time / ranged_duration)
		if action_time >= ranged_duration:
			_finish_action()


func _set_melee_window(open: bool) -> void:
	melee_window_open = open
	melee_hitbox.monitoring = open
	if open:
		_apply_overlapping_melee_hits()


func _hitbox_scale() -> float:
	match action_state:
		ActionState.ATTACK3:
			return third_claw_hitbox_scale
		ActionState.POUNCE:
			return pounce_hitbox_scale
		ActionState.COUNTER:
			return counter_claw_hitbox_scale
		_:
			return 1.0


func _update_hitbox_transform() -> void:
	melee_hitbox.position = facing * 16.0
	melee_hitbox.rotation = facing.angle()
	melee_hitbox.scale = Vector2.ONE * _hitbox_scale()
	var perpendicular := facing.orthogonal()
	attack_arc.points = PackedVector2Array([
		facing * 10.0 - perpendicular * 15.0,
		facing * 25.0,
		facing * 10.0 + perpendicular * 15.0
	])


func _on_melee_body_entered(body: Node2D) -> void:
	if melee_window_open:
		_try_damage_target(body)


func _apply_overlapping_melee_hits() -> void:
	for body in melee_hitbox.get_overlapping_bodies():
		_try_damage_target(body)


func _apply_melee_shape_query() -> void:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = melee_shape.shape
	query.transform = melee_shape.global_transform
	query.collision_mask = melee_hitbox.collision_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [player.get_rid()]
	for result in get_world_2d().direct_space_state.intersect_shape(query, 64):
		var collider: Object = result.get("collider")
		if collider is Node:
			_try_damage_target(collider as Node)


func _try_damage_target(target: Node) -> void:
	if target == player or not target.has_method("receive_damage"):
		return
	var target_id := target.get_instance_id()
	if hit_targets.has(target_id):
		return
	hit_targets[target_id] = true
	var state := action_state
	var is_combo_finisher := state == ActionState.ATTACK2
	var base_damage: float = float(melee_damage if is_combo_finisher else first_melee_damage)
	var knockback := melee_knockback
	match state:
		ActionState.ATTACK3:
			base_damage = third_claw_damage
			knockback = melee_knockback * third_claw_knockback_multiplier
		ActionState.POUNCE:
			base_damage = pounce_damage
			knockback = melee_knockback * 1.3
		ActionState.COUNTER:
			base_damage = counter_claw_damage
	var attack_damage := (
		base_damage
		* ProgressionManager.get_attack_multiplier()
		* DayManager.get_night_attack_multiplier()
	)
	# Backstab: attacking an enemy that is facing away has a chance to crit.
	var is_crit := false
	if _is_behind(target) and crit_rng.randf() < backstab_crit_chance:
		is_crit = true
		attack_damage *= crit_damage_multiplier
	var accepted: bool = target.receive_damage(attack_damage, player.global_position, knockback)
	if not accepted:
		return
	var hit_position: Vector2 = (target as Node2D).global_position if target is Node2D else player.global_position
	var blow_direction: Vector2 = (hit_position - player.global_position).normalized()
	HitFeel.melee_hit(hit_position, attack_damage, state != ActionState.ATTACK1, state == ActionState.ATTACK3 or state == ActionState.POUNCE, is_crit, blow_direction)
	if state == ActionState.ATTACK1:
		if not combo_window_open:
			combo_window_open = true
			combo_window_left = combo_window
			combo_next_step = 2
	elif state == ActionState.ATTACK2:
		# With the triple combo learned, the second claw also opens the window for a third.
		if ProgressionManager.has_move("triple_combo") and not combo_window_open:
			combo_window_open = true
			combo_window_left = combo_window
			combo_next_step = 3
		if not combo_stun_targets.has(target_id):
			combo_stun_targets[target_id] = true
			combo_hit_feedback_left = 0.65
			combo_feedback_text = "二连命中！史莱姆可能眩晕"
			var stun_roll_succeeded := stun_rng.randf() < combo_stun_chance
			if target.has_method("register_combo_finisher"):
				target.register_combo_finisher(
					current_melee_attack_id,
					stun_roll_succeeded,
					stun_duration,
					control_immunity_duration
				)
			elif stun_roll_succeeded and target.has_method("apply_stun"):
				target.apply_stun(stun_duration, control_immunity_duration)
	else:
		# Third claw, pounce and counter claw: the enemy is always stunned, and the
		# finishing move pays a small reward.
		combo_hit_feedback_left = 0.65
		match state:
			ActionState.ATTACK3:
				combo_feedback_text = "三段连击！史莱姆被击晕"
			ActionState.POUNCE:
				combo_feedback_text = "扑击命中！史莱姆被击晕"
			_:
				combo_feedback_text = "反击命中！史莱姆被击晕"
		_apply_guaranteed_stun(target)
		_grant_combo_reward(hit_position)
	if is_crit:
		HitFeel.slash(hit_position, blow_direction, "crit")
		combo_feedback_text = "绕背暴击！"
		combo_hit_feedback_left = 0.65


## Is the cat behind this enemy (the enemy is facing away from the cat)?
func _is_behind(target: Node) -> bool:
	if not (target is Node2D):
		return false
	var facing_value: Variant = target.get("facing")
	if not (facing_value is Vector2) or facing_value == Vector2.ZERO:
		return false
	var to_cat: Vector2 = (player.global_position - (target as Node2D).global_position).normalized()
	return (facing_value as Vector2).normalized().dot(to_cat) <= backstab_dot_threshold


func _apply_guaranteed_stun(target: Node) -> void:
	if target.has_method("register_combo_finisher"):
		target.register_combo_finisher(current_melee_attack_id, true, stun_duration, control_immunity_duration)
	elif target.has_method("apply_stun"):
		target.apply_stun(stun_duration, control_immunity_duration)


## Randomly fish or mood, once per swing (hitting two enemies at once pays only once).
func _grant_combo_reward(world_position: Vector2) -> void:
	if reward_given_attack_id == current_melee_attack_id:
		return
	reward_given_attack_id = current_melee_attack_id
	if reward_rng.randf() < 0.5:
		CurrencyManager.add_fish(combo_reward_fish)
		HitFeel.damage_number(world_position + Vector2(0.0, -24.0), "+%d 小鱼干" % combo_reward_fish, HitFeel.GOLD, 14)
	else:
		DayManager.add_mood(combo_reward_mood)
		HitFeel.damage_number(world_position + Vector2(0.0, -24.0), "心情 +%d" % int(combo_reward_mood), HitFeel.PINK, 14)


func _apply_combat_tuning() -> void:
	var tuning: CombatV3Tuning = CombatBalance.tuning
	first_melee_damage = int(tuning.first_claw_damage)
	melee_damage = int(tuning.second_claw_damage)
	combo_window = tuning.combo_window
	melee_cooldown = tuning.melee_recovery
	stun_duration = tuning.stun_duration
	control_immunity_duration = tuning.control_immunity_duration
	combo_stun_chance = tuning.second_claw_stun_chance
	ranged_cooldown = tuning.yarn_cooldown
	third_claw_damage = tuning.third_claw_damage
	third_claw_knockback_multiplier = tuning.third_claw_knockback_multiplier
	third_claw_hitbox_scale = tuning.third_claw_hitbox_scale
	pounce_damage = tuning.pounce_damage
	pounce_distance = tuning.pounce_distance
	pounce_move_duration = tuning.pounce_move_duration
	pounce_duration = tuning.pounce_duration
	pounce_recovery = tuning.pounce_recovery
	pounce_hitbox_scale = tuning.pounce_hitbox_scale
	counter_claw_damage = tuning.counter_claw_damage
	counter_claw_hitbox_scale = tuning.counter_claw_hitbox_scale
	combo_reward_fish = tuning.combo_reward_fish
	combo_reward_mood = tuning.combo_reward_mood
	backstab_crit_chance = tuning.backstab_crit_chance
	crit_damage_multiplier = tuning.crit_damage_multiplier
	backstab_dot_threshold = tuning.backstab_dot_threshold
	# Automated tests must stay deterministic; tests that cover crits switch the chance on.
	if OS.get_environment("PIXELCAT_TEST_MODE") == "1":
		backstab_crit_chance = 0.0


func _spawn_projectile() -> void:
	if projectile_scene == null:
		push_warning("PlayerCombat: projectile_scene 未配置")
		return
	if yarn_projectile_in_flight:
		return
	if is_instance_valid(active_yarn_projectile) and not active_yarn_projectile.is_queued_for_deletion():
		return
	var projectile = projectile_scene.instantiate()
	get_tree().current_scene.add_child(projectile)
	active_yarn_projectile = projectile
	yarn_projectile_in_flight = true
	# The cooldown starts when the projectile is actually launched, after the
	# cast wind-up, not when the input is pressed.
	ranged_cooldown_left = ranged_cooldown
	projectile.global_position = player.global_position + facing * 20.0
	if projectile.has_method("setup"):
		projectile.setup(
			facing,
			player,
			float(ranged_damage)
			* ProgressionManager.get_attack_multiplier()
			* DayManager.get_night_attack_multiplier(),
			projectile_speed,
			projectile_range
		)
	else:
		push_warning("PlayerCombat: projectile_scene 缺少 setup()")


## Attempts a sticky-yarn bind through the enemy's existing control interface.
## Returns whether the bind was actually applied; damage is resolved separately
## by the projectile before this is called.
func on_sticky_yarn_hit(target: Node2D, projectile: Node = null) -> bool:
	_release_projectile(projectile)
	if (
		not is_instance_valid(target)
		or not target.is_in_group("enemies")
		or not target.has_method("apply_yarn_bind")
		or not _is_night_combat_scene()
	):
		return false
	return bool(target.apply_yarn_bind(STICKY_YARN_BIND_DURATION))


## Called when a projectile is consumed without applying a bind (miss, wall,
## range exhaustion or external destruction). Always releases the launch lock.
func on_sticky_yarn_miss(projectile: Node = null) -> void:
	_release_projectile(projectile)


func _release_projectile(projectile: Node) -> void:
	# Ignore a late callback from a previous projectile so it cannot clear the
	# lock of the projectile that is currently in flight.
	if projectile != null and projectile != active_yarn_projectile:
		return
	yarn_projectile_in_flight = false
	active_yarn_projectile = null


func _get_facing() -> Vector2:
	if player.has_method("get_last_facing"):
		var player_facing: Vector2 = player.get_last_facing()
		if player_facing != Vector2.ZERO:
			if absf(player_facing.x) > absf(player_facing.y):
				return Vector2.RIGHT if player_facing.x > 0.0 else Vector2.LEFT
			return Vector2.DOWN if player_facing.y > 0.0 else Vector2.UP
	return Vector2.DOWN


func _begin_action_visual(prefix: String) -> void:
	using_formal_animation = false
	var facing_name := "down"
	if player.has_method("get_facing_name"):
		facing_name = player.get_facing_name()
	var animation_name := StringName("%s_%s" % [prefix, facing_name])
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(animation_name):
		using_formal_animation = true
		var custom_speed := 1.0
		if prefix == "attack" and _is_melee_state(action_state):
			var action_duration := _melee_timings().z
			var frame_count := sprite.sprite_frames.get_frame_count(animation_name)
			var animation_speed := sprite.sprite_frames.get_animation_speed(animation_name)
			if action_duration > 0.0 and animation_speed > 0.0:
				custom_speed = float(frame_count) / (action_duration * animation_speed)
		sprite.play(animation_name, custom_speed)


func _update_fallback_visual(progress: float) -> void:
	if using_formal_animation:
		return
	var p := clampf(progress, 0.0, 1.0)
	if _is_melee_state(action_state):
		_apply_attack_pose(p)
	else:
		var eased := sin(p * PI)
		sprite.position = sprite_base_position + facing * eased * 3.0
		sprite.scale = sprite_base_scale * (1.0 + eased * 0.08)


## Placeholder attack animation (until real frames are drawn): wind up (pull back and squash),
## strike (lunge and stretch along the swing), then settle. Each claw step swings its own way.
func _apply_attack_pose(p: float) -> void:
	var timings := _melee_timings()
	var strike_start := timings.x / timings.z
	var strike_end := timings.y / timings.z
	var lunge := _attack_lunge_distance()
	var offset := Vector2.ZERO
	var squash := 0.0     # +1 = fully stretched along the swing, -1 = fully squashed
	var tilt := 0.0
	var side := 1.0 if facing.x >= 0.0 else -1.0
	if action_state == ActionState.ATTACK2 or action_state == ActionState.COUNTER:
		side = -side
	if p < strike_start:
		var w := p / maxf(strike_start, 0.001)
		offset = -facing * 3.0 * w
		squash = -0.6 * w
		tilt = -0.2 * side * w
	elif p < strike_end:
		var w := (p - strike_start) / maxf(strike_end - strike_start, 0.001)
		var e := 1.0 - pow(1.0 - w, 3.0)
		offset = facing * lerpf(-3.0, lunge * 0.55, e)
		squash = lerpf(-0.6, 1.0, e)
		tilt = lerpf(-0.2, 0.3, e) * side
	else:
		var w := (p - strike_end) / maxf(1.0 - strike_end, 0.001)
		var e := 1.0 - pow(1.0 - clampf(w, 0.0, 1.0), 2.0)
		offset = facing * lerpf(lunge * 0.55, 0.0, e)
		squash = lerpf(1.0, 0.0, e)
		tilt = lerpf(0.3, 0.0, e) * side
	var along := Vector2(1.0, 1.0)
	if absf(facing.x) > absf(facing.y):
		along = Vector2(1.0 + 0.16 * squash, 1.0 - 0.10 * squash)
	else:
		along = Vector2(1.0 - 0.10 * squash, 1.0 + 0.16 * squash)
	sprite.position = sprite_base_position + offset
	sprite.scale = sprite_base_scale * along
	sprite.rotation = sprite_base_rotation + tilt


func _attack_lunge_distance() -> float:
	match action_state:
		ActionState.ATTACK3:
			return 22.0
		ActionState.ATTACK2:
			return 16.0
		ActionState.COUNTER:
			return 9.0
		ActionState.POUNCE:
			return 8.0
		_:
			return 13.0


## The forward step of a claw swing, as extra velocity for the cat (only during the strike).
## The pounce moves the cat by itself, so it adds nothing.
func get_attack_step_velocity() -> Vector2:
	if not _is_melee_state(action_state) or action_state == ActionState.POUNCE:
		return Vector2.ZERO
	var timings := _melee_timings()
	if action_time < timings.x * 0.6 or action_time > timings.y:
		return Vector2.ZERO
	var window := maxf(timings.y - timings.x * 0.6, 0.02)
	return facing * (_attack_lunge_distance() / window) * 0.8


func _spawn_slash() -> void:
	var kind := "claw1"
	match action_state:
		ActionState.ATTACK2:
			kind = "claw2"
		ActionState.ATTACK3:
			kind = "claw3"
		ActionState.POUNCE:
			kind = "pounce"
		ActionState.COUNTER:
			kind = "counter"
	HitFeel.slash(player.global_position + Vector2(0.0, 4.0), facing, kind)


func _finish_action() -> void:
	_set_melee_window(false)
	var completed_state := action_state
	action_state = ActionState.RECOVERY if _is_melee_state(completed_state) else ActionState.IDLE
	action_time = 0.0
	attack_arc.visible = false
	_restore_sprite()
	if player.has_method("restore_movement_animation"):
		player.restore_movement_animation()
	if _can_chain_from(completed_state) and buffered_combo and combo_window_open and _can_start_action():
		_start_melee(true)


func cancel_action() -> void:
	combo_window_open = false
	combo_window_left = 0.0
	buffered_combo = false
	if action_state == ActionState.IDLE:
		return
	if action_state == ActionState.POUNCE and player.has_method("stop_pounce"):
		player.stop_pounce()
	_finish_action()


func set_combat_enabled(enabled: bool) -> void:
	combat_enabled = enabled
	if not enabled:
		# Death, scene teardown and other forced exits must not leave the
		# one-projectile launch lock stuck on.
		yarn_projectile_in_flight = false
		if is_instance_valid(active_yarn_projectile):
			active_yarn_projectile.queue_free()
		active_yarn_projectile = null
		cancel_action()


func _restore_sprite() -> void:
	sprite.position = sprite_base_position
	sprite.rotation = sprite_base_rotation
	sprite.scale = sprite_base_scale


func is_action_active() -> bool:
	return _is_melee_state(action_state) or action_state == ActionState.RANGED


func get_movement_multiplier() -> float:
	if _is_melee_state(action_state):
		return melee_movement_multiplier
	if action_state == ActionState.RANGED:
		return ranged_movement_multiplier
	return 1.0
