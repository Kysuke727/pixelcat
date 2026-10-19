extends Node2D

enum ActionState { IDLE, ATTACK1, ATTACK2, RECOVERY, RANGED }

const YARN_CONNECTION_SCENE := preload("res://scenes/combat/yarn_connection.tscn")

@export_category("Melee")
@export var melee_damage: int = 2
@export var melee_cooldown: float = 0.45
@export var melee_duration: float = 0.25
@export var melee_active_start: float = 0.08
@export var melee_active_end: float = 0.16
@export var melee_movement_multiplier: float = 0.65
@export var melee_knockback: float = 150.0
@export_category("Combo")
@export var combo_window: float = 0.35
@export var stun_duration: float = 1.0
@export var stun_resistance_duration: float = 1.0

const COMBO_STUN_CHANCE: float = 0.5

@export_category("Ranged")
@export var projectile_scene: PackedScene
@export var ranged_damage: int = 1
@export var ranged_cooldown: float = 6.0
@export var ranged_duration: float = 0.30
@export var ranged_windup: float = 0.12
@export var projectile_speed: float = 220.0
@export var projectile_range: float = 220.0
@export var ranged_movement_multiplier: float = 0.8

@export_category("Yarn Connection")
@export var yarn_slow_multiplier: float = 0.5
@export var yarn_slow_duration: float = 3.0
@export var yarn_bind_duration: float = 2.0
@export var yarn_connection_duration: float = 10.0
@export var yarn_maximum_length: float = 500.0
@export var yarn_sample_distance: float = 6.0
@export var yarn_closure_distance: float = 18.0
@export var yarn_minimum_loop_perimeter: float = 120.0
@export var yarn_minimum_loop_area: float = 450.0
@export var yarn_maximum_samples: int = 384
@export var yarn_cut_cooldown_reduction: float = 1.5

var action_state: int = ActionState.IDLE
var action_time: float = 0.0
var melee_cooldown_left: float = 0.0
var ranged_cooldown_left: float = 0.0
var combo_window_left: float = 0.0
var combo_window_open: bool = false
var buffered_combo: bool = false
var combo_stun_targets: Dictionary = {}
var stun_rng := RandomNumberGenerator.new()
var combat_enabled: bool = true
var projectile_fired: bool = false
var yarn_projectile_in_flight: bool = false
var active_yarn_connections: Array[Node2D] = []
var melee_window_open: bool = false
var hit_targets: Dictionary = {}
var facing: Vector2 = Vector2.DOWN
var using_formal_animation: bool = false
var sprite_base_position: Vector2
var sprite_base_rotation: float
var sprite_base_scale: Vector2

@onready var player = get_parent()
@onready var sprite: AnimatedSprite2D = get_parent().get_node("AnimatedSprite2D")
@onready var melee_hitbox: Area2D = $MeleeHitbox
@onready var melee_shape: CollisionShape2D = $MeleeHitbox/CollisionShape2D
@onready var attack_arc: Line2D = $AttackArc


func _ready() -> void:
	stun_rng.randomize()
	sprite_base_position = sprite.position
	sprite_base_rotation = sprite.rotation
	sprite_base_scale = sprite.scale
	melee_hitbox.monitoring = false
	attack_arc.visible = false
	melee_hitbox.body_entered.connect(_on_melee_body_entered)


func _process(delta: float) -> void:
	melee_cooldown_left = maxf(melee_cooldown_left - delta, 0.0)
	ranged_cooldown_left = maxf(ranged_cooldown_left - delta, 0.0)
	if combo_window_open:
		combo_window_left = maxf(combo_window_left - delta, 0.0)
		if combo_window_left <= 0.0:
			combo_window_open = false
			buffered_combo = false
	if Input.is_action_just_pressed("yarn_cut"):
		_cut_all_yarn_connections()

	if action_state == ActionState.ATTACK1 or action_state == ActionState.ATTACK2:
		if action_state == ActionState.ATTACK1 and combo_window_open and Input.is_action_just_pressed("melee_attack"):
			buffered_combo = true
		action_time += delta
		_update_action()
		return
	if action_state == ActionState.RANGED:
		action_time += delta
		_update_action()
		return
	if action_state == ActionState.RECOVERY and melee_cooldown_left <= 0.0 and not combo_window_open:
		action_state = ActionState.IDLE

	if not _can_start_action():
		return
	if Input.is_action_just_pressed("melee_attack"):
		if combo_window_open:
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
	if not combat_enabled or not _is_night_combat_scene():
		return false
	if player.has_method("is_alive") and not player.is_alive():
		return false
	if player.has_method("is_in_hitstun") and player.is_in_hitstun():
		return false
	return true


func _is_night_combat_scene() -> bool:
	var scene := get_tree().current_scene
	return scene != null and scene.is_in_group("night_exploration")


func _start_melee(is_second_attack: bool = false) -> void:
	action_state = ActionState.ATTACK2 if is_second_attack else ActionState.ATTACK1
	action_time = 0.0
	melee_cooldown_left = melee_cooldown
	melee_window_open = false
	hit_targets.clear()
	if is_second_attack:
		combo_window_open = false
		combo_window_left = 0.0
		buffered_combo = false
	else:
		combo_stun_targets.clear()
	facing = _get_facing()
	_update_hitbox_transform()
	_begin_action_visual("attack")
	attack_arc.visible = not using_formal_animation


func _start_ranged() -> void:
	action_state = ActionState.RANGED
	action_time = 0.0
	projectile_fired = false
	combo_window_open = false
	combo_window_left = 0.0
	buffered_combo = false
	facing = _get_facing()
	_begin_action_visual("cast")


func _update_action() -> void:
	if action_state == ActionState.ATTACK1 or action_state == ActionState.ATTACK2:
		if not melee_window_open and action_time >= melee_active_start and action_time < melee_active_end:
			_set_melee_window(true)
		if melee_window_open:
			_apply_overlapping_melee_hits()
		if melee_window_open and action_time >= melee_active_end:
			_set_melee_window(false)
		_update_fallback_visual(action_time / melee_duration)
		if action_time >= melee_duration:
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


func _update_hitbox_transform() -> void:
	melee_hitbox.position = facing * 16.0
	melee_hitbox.rotation = facing.angle()
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


func _try_damage_target(target: Node) -> void:
	if target == player or not target.has_method("receive_damage"):
		return
	var target_id := target.get_instance_id()
	if hit_targets.has(target_id):
		return
	hit_targets[target_id] = true
	var accepted: bool = target.receive_damage(melee_damage, player.global_position, melee_knockback)
	if not accepted:
		return
	if action_state == ActionState.ATTACK1:
		if not combo_window_open:
			combo_window_open = true
			combo_window_left = combo_window
	elif action_state == ActionState.ATTACK2 and not combo_stun_targets.has(target_id):
		combo_stun_targets[target_id] = true
		if stun_rng.randf() < COMBO_STUN_CHANCE and target.has_method("apply_stun"):
			target.apply_stun(stun_duration, stun_resistance_duration)


func _spawn_projectile() -> void:
	if projectile_scene == null:
		push_warning("PlayerCombat: projectile_scene 未配置")
		return
	var projectile = projectile_scene.instantiate()
	get_tree().current_scene.add_child(projectile)
	yarn_projectile_in_flight = true
	ranged_cooldown_left = ranged_cooldown
	projectile.global_position = player.global_position + facing * 20.0
	if projectile.has_method("setup"):
		projectile.setup(
			facing,
			player,
			ranged_damage,
			projectile_speed,
			projectile_range
		)


func on_yarn_hit(target: Node2D) -> bool:
	yarn_projectile_in_flight = false
	if (
		not is_instance_valid(target)
		or not target.is_in_group("enemies")
		or not target.has_method("apply_yarn_slow")
		or not target.has_method("apply_yarn_bind")
		or not _is_night_combat_scene()
	):
		return false
	var connection = YARN_CONNECTION_SCENE.instantiate()
	connection.configure(player, target, self, {
		"slow_multiplier": yarn_slow_multiplier,
		"slow_duration": yarn_slow_duration,
		"bind_duration": yarn_bind_duration,
		"maximum_duration": yarn_connection_duration,
		"maximum_length": yarn_maximum_length,
		"sample_distance": yarn_sample_distance,
		"closure_distance": yarn_closure_distance,
		"minimum_loop_perimeter": yarn_minimum_loop_perimeter,
		"minimum_loop_area": yarn_minimum_loop_area,
		"maximum_samples": yarn_maximum_samples,
		"cooldown_reduction_on_cut": yarn_cut_cooldown_reduction
	})
	get_tree().current_scene.add_child(connection)
	active_yarn_connections.append(connection)
	return true


func on_yarn_miss() -> void:
	yarn_projectile_in_flight = false


func on_yarn_cut_reward(cooldown_reduction: float) -> void:
	ranged_cooldown_left = maxf(ranged_cooldown_left - maxf(cooldown_reduction, 0.0), 0.0)


func on_yarn_connection_finished(connection: Node) -> void:
	active_yarn_connections.erase(connection)


func _cut_all_yarn_connections() -> void:
	for connection in active_yarn_connections.duplicate():
		if is_instance_valid(connection) and connection.has_method("cut_by_player"):
			connection.cut_by_player()


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
		sprite.play(animation_name)


func _update_fallback_visual(progress: float) -> void:
	if using_formal_animation:
		return
	var eased := sin(clampf(progress, 0.0, 1.0) * PI)
	sprite.position = sprite_base_position + facing * eased * 3.0
	if action_state == ActionState.ATTACK1 or action_state == ActionState.ATTACK2:
		sprite.rotation = sprite_base_rotation + eased * 0.18 * (1.0 if facing.x >= 0.0 else -1.0)
	else:
		sprite.scale = sprite_base_scale * (1.0 + eased * 0.08)


func _finish_action() -> void:
	_set_melee_window(false)
	var completed_state := action_state
	action_state = ActionState.RECOVERY if completed_state == ActionState.ATTACK1 or completed_state == ActionState.ATTACK2 else ActionState.IDLE
	action_time = 0.0
	attack_arc.visible = false
	_restore_sprite()
	if player.has_method("restore_movement_animation"):
		player.restore_movement_animation()
	if completed_state == ActionState.ATTACK1 and buffered_combo and combo_window_open and _can_start_action():
		_start_melee(true)


func cancel_action() -> void:
	if action_state == ActionState.IDLE:
		return
	_finish_action()
	combo_window_open = false
	combo_window_left = 0.0
	buffered_combo = false


func set_combat_enabled(enabled: bool) -> void:
	combat_enabled = enabled
	if not enabled:
		cancel_action()


func _restore_sprite() -> void:
	sprite.position = sprite_base_position
	sprite.rotation = sprite_base_rotation
	sprite.scale = sprite_base_scale


func is_action_active() -> bool:
	return action_state == ActionState.ATTACK1 or action_state == ActionState.ATTACK2 or action_state == ActionState.RANGED


func get_movement_multiplier() -> float:
	if action_state == ActionState.ATTACK1 or action_state == ActionState.ATTACK2:
		return melee_movement_multiplier
	if action_state == ActionState.RANGED:
		return ranged_movement_multiplier
	return 1.0
