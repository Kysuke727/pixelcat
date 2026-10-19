extends Node2D

enum ActionState { NONE, MELEE, RANGED }

@export_category("Melee")
@export var melee_damage: int = 2
@export var melee_cooldown: float = 0.45
@export var melee_duration: float = 0.25
@export var melee_active_start: float = 0.08
@export var melee_active_end: float = 0.16
@export var melee_movement_multiplier: float = 0.65
@export var melee_knockback: float = 150.0

@export_category("Ranged")
@export var projectile_scene: PackedScene
@export var ranged_damage: int = 1
@export var ranged_cooldown: float = 0.8
@export var ranged_duration: float = 0.30
@export var ranged_windup: float = 0.12
@export var projectile_speed: float = 220.0
@export var projectile_range: float = 220.0
@export var ranged_movement_multiplier: float = 0.8

var action_state: int = ActionState.NONE
var action_time: float = 0.0
var melee_cooldown_left: float = 0.0
var ranged_cooldown_left: float = 0.0
var combat_enabled: bool = true
var projectile_fired: bool = false
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
	sprite_base_position = sprite.position
	sprite_base_rotation = sprite.rotation
	sprite_base_scale = sprite.scale
	melee_hitbox.monitoring = false
	attack_arc.visible = false
	melee_hitbox.body_entered.connect(_on_melee_body_entered)


func _process(delta: float) -> void:
	melee_cooldown_left = maxf(melee_cooldown_left - delta, 0.0)
	ranged_cooldown_left = maxf(ranged_cooldown_left - delta, 0.0)

	if action_state != ActionState.NONE:
		action_time += delta
		_update_action()
		return

	if not _can_start_action():
		return
	if Input.is_action_just_pressed("melee_attack") and melee_cooldown_left <= 0.0:
		_start_melee()
	elif Input.is_action_just_pressed("ranged_attack") and ranged_cooldown_left <= 0.0:
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


func _start_melee() -> void:
	action_state = ActionState.MELEE
	action_time = 0.0
	melee_cooldown_left = melee_cooldown
	melee_window_open = false
	hit_targets.clear()
	facing = _get_facing()
	_update_hitbox_transform()
	_begin_action_visual("attack")
	attack_arc.visible = not using_formal_animation


func _start_ranged() -> void:
	action_state = ActionState.RANGED
	action_time = 0.0
	ranged_cooldown_left = ranged_cooldown
	projectile_fired = false
	facing = _get_facing()
	_begin_action_visual("cast")


func _update_action() -> void:
	if action_state == ActionState.MELEE:
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
	target.receive_damage(melee_damage, player.global_position, melee_knockback)


func _spawn_projectile() -> void:
	if projectile_scene == null:
		push_warning("PlayerCombat: projectile_scene 未配置")
		return
	var projectile = projectile_scene.instantiate()
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = player.global_position + facing * 20.0
	if projectile.has_method("setup"):
		projectile.setup(
			facing,
			player,
			ranged_damage,
			projectile_speed,
			projectile_range
		)


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
	if action_state == ActionState.MELEE:
		sprite.rotation = sprite_base_rotation + eased * 0.18 * (1.0 if facing.x >= 0.0 else -1.0)
	else:
		sprite.scale = sprite_base_scale * (1.0 + eased * 0.08)


func _finish_action() -> void:
	_set_melee_window(false)
	action_state = ActionState.NONE
	action_time = 0.0
	attack_arc.visible = false
	_restore_sprite()
	if player.has_method("restore_movement_animation"):
		player.restore_movement_animation()


func cancel_action() -> void:
	if action_state == ActionState.NONE:
		return
	_finish_action()


func set_combat_enabled(enabled: bool) -> void:
	combat_enabled = enabled
	if not enabled:
		cancel_action()


func _restore_sprite() -> void:
	sprite.position = sprite_base_position
	sprite.rotation = sprite_base_rotation
	sprite.scale = sprite_base_scale


func is_action_active() -> bool:
	return action_state != ActionState.NONE


func get_movement_multiplier() -> float:
	if action_state == ActionState.MELEE:
		return melee_movement_multiplier
	if action_state == ActionState.RANGED:
		return ranged_movement_multiplier
	return 1.0
