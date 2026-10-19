extends CharacterBody2D

signal health_changed(current_health: int, max_health: int)
signal died(enemy: Node)

enum SlimeState {
	IDLE,
	WANDER,
	CHASE,
	WINDUP,
	LUNGE,
	RECOVER,
	HURT,
	STUNNED,
	DEAD
}

const FRONT_TEXTURE := preload("res://assets/characters/slime/slime_front.png")
const BACK_TEXTURE := preload("res://assets/characters/slime/slime_back.png")
const LEFT_TEXTURE := preload("res://assets/characters/slime/slime_left.png")
const RIGHT_TEXTURE := preload("res://assets/characters/slime/slime_right.png")
const FISH_PICKUP_SCENE := preload("res://scenes/pickups/dried_fish_pickup.tscn")
static var _next_attack_id: int = 1

@export_category("Identity")
@export var display_name: String = "史莱姆"

@export_category("Stats")
@export var max_health: int = 4
@export var move_speed: float = 35.0
@export var chase_range: float = 120.0
@export var disengage_range: float = 180.0
@export var attack_range: float = 25.0
@export var attack_damage: int = 1
@export var attack_cooldown: float = 1.5

@export_category("Lunge")
@export var windup_duration: float = 0.35
@export var lunge_duration: float = 0.22
@export var lunge_speed: float = 145.0
@export var recover_duration: float = 0.45
@export var attack_knockback: float = 135.0

@export_category("Collision Stun")
@export var collision_stun_duration: float = 1.0
@export var collision_stun_cooldown: float = 0.8
@export var collision_speed_threshold: float = 75.0
@export var wall_impact_speed_threshold: float = 90.0
@export var wall_impact_stun_duration: float = 0.20
@export var wall_impact_cooldown: float = 0.8

@export_category("Wander")
@export var wander_radius: float = 72.0
@export var idle_duration_min: float = 0.7
@export var idle_duration_max: float = 1.5
@export var wander_duration_min: float = 0.8
@export var wander_duration_max: float = 1.8

@export_category("Damage Response")
@export var hurt_duration: float = 0.20
@export var hurt_knockback_decay: float = 650.0
@export var fish_drop_min: int = 1
@export var fish_drop_max: int = 3

var state: int = SlimeState.IDLE
var current_health: int
var state_time_left: float = 0.0
var cooldown_left: float = 0.0
var stun_time_left: float = 0.0
var stun_resistance_left: float = 0.0
var collision_stun_cooldown_left: float = 0.0
var wall_impact_cooldown_left: float = 0.0
var slow_time_left: float = 0.0
var slow_multiplier: float = 1.0
var bind_time_left: float = 0.0
var spawn_position: Vector2
var wander_direction: Vector2 = Vector2.ZERO
var locked_target_position: Vector2
var lunge_direction: Vector2 = Vector2.DOWN
var hurt_velocity: Vector2 = Vector2.ZERO
var attacked_targets: Dictionary = {}
var target: Node2D
var animation_time: float = 0.0
var facing: Vector2 = Vector2.DOWN
var current_attack_id: int = 0

@onready var sprite: Sprite2D = $Sprite2D
@onready var body_collision: CollisionShape2D = $CollisionShape2D
@onready var attack_area: Area2D = $AttackArea
@onready var attack_sound: AudioStreamPlayer2D = $AttackSound
@onready var hit_sound: AudioStreamPlayer2D = $HitSound
@onready var death_sound: AudioStreamPlayer2D = $DeathSound


func _ready() -> void:
	current_health = max_health
	spawn_position = global_position
	add_to_group("enemies")
	add_to_group("damageable")
	attack_area.set_deferred("monitoring", false)
	_choose_idle_duration()
	_find_player()
	health_changed.emit(current_health, max_health)


func _physics_process(delta: float) -> void:
	if state == SlimeState.DEAD:
		return
	cooldown_left = maxf(cooldown_left - delta, 0.0)
	stun_resistance_left = maxf(stun_resistance_left - delta, 0.0)
	collision_stun_cooldown_left = maxf(collision_stun_cooldown_left - delta, 0.0)
	wall_impact_cooldown_left = maxf(wall_impact_cooldown_left - delta, 0.0)
	slow_time_left = maxf(slow_time_left - delta, 0.0)
	if slow_time_left <= 0.0:
		slow_multiplier = 1.0
	bind_time_left = maxf(bind_time_left - delta, 0.0)
	stun_time_left = maxf(stun_time_left - delta, 0.0)
	animation_time += delta
	if not is_instance_valid(target):
		_find_player()
	if bind_time_left > 0.0:
		velocity = Vector2.ZERO
		_move_and_check_impacts()
		_update_sprite()
		return
	state_time_left = maxf(state_time_left - delta, 0.0)

	match state:
		SlimeState.IDLE:
			_process_idle()
		SlimeState.WANDER:
			_process_wander()
		SlimeState.CHASE:
			_process_chase()
		SlimeState.WINDUP:
			_process_windup()
		SlimeState.LUNGE:
			_process_lunge()
		SlimeState.RECOVER:
			_process_recover()
		SlimeState.HURT:
			_process_hurt(delta)
		SlimeState.STUNNED:
			_process_stunned()

	_update_sprite()


func _find_player() -> void:
	target = get_tree().get_first_node_in_group("player") as Node2D


func _target_distance() -> float:
	if not is_instance_valid(target):
		return INF
	return global_position.distance_to(target.global_position)


func _process_idle() -> void:
	velocity = Vector2.ZERO
	if _target_distance() <= chase_range:
		_change_state(SlimeState.CHASE)
	elif state_time_left <= 0.0:
		_begin_wander()


func _process_wander() -> void:
	if _target_distance() <= chase_range:
		_change_state(SlimeState.CHASE)
		return
	if global_position.distance_to(spawn_position) > wander_radius:
		wander_direction = global_position.direction_to(spawn_position)
	velocity = wander_direction * move_speed * slow_multiplier * 0.55
	_update_facing(velocity)
	_move_and_check_impacts()
	if state != SlimeState.WANDER:
		return
	if get_slide_collision_count() > 0:
		wander_direction = wander_direction.rotated(randf_range(1.7, 3.8))
	if state_time_left <= 0.0:
		_change_state(SlimeState.IDLE)
		_choose_idle_duration()


func _process_chase() -> void:
	var distance := _target_distance()
	if distance > disengage_range:
		_change_state(SlimeState.WANDER)
		wander_direction = global_position.direction_to(spawn_position)
		state_time_left = randf_range(wander_duration_min, wander_duration_max)
		return
	if distance <= attack_range and cooldown_left <= 0.0:
		locked_target_position = target.global_position
		velocity = Vector2.ZERO
		_change_state(SlimeState.WINDUP)
		state_time_left = windup_duration
		return
	if is_instance_valid(target):
		velocity = global_position.direction_to(target.global_position) * move_speed * slow_multiplier
		_update_facing(velocity)
		_move_and_check_impacts()


func _process_windup() -> void:
	velocity = Vector2.ZERO
	if state_time_left <= 0.0:
		lunge_direction = global_position.direction_to(locked_target_position)
		if lunge_direction == Vector2.ZERO:
			lunge_direction = facing
		_update_facing(lunge_direction)
		attacked_targets.clear()
		current_attack_id = _next_attack_id
		_next_attack_id += 1
		attack_area.monitoring = true
		if attack_sound.stream != null:
			attack_sound.play()
		_change_state(SlimeState.LUNGE)
		state_time_left = lunge_duration


func _process_lunge() -> void:
	velocity = lunge_direction * lunge_speed * slow_multiplier
	_move_and_check_impacts()
	if state != SlimeState.LUNGE:
		return
	if state_time_left <= 0.0:
		attack_area.monitoring = false
		cooldown_left = attack_cooldown
		_change_state(SlimeState.RECOVER)
		state_time_left = recover_duration


func _process_recover() -> void:
	velocity = Vector2.ZERO
	if state_time_left <= 0.0:
		_change_state(SlimeState.CHASE if _target_distance() <= disengage_range else SlimeState.WANDER)


func _process_hurt(delta: float) -> void:
	velocity = hurt_velocity
	hurt_velocity = hurt_velocity.move_toward(Vector2.ZERO, hurt_knockback_decay * delta)
	_move_and_check_impacts()
	if state != SlimeState.HURT:
		return
	if state_time_left <= 0.0:
		_change_state(SlimeState.CHASE if _target_distance() <= disengage_range else SlimeState.WANDER)


func _process_stunned() -> void:
	velocity = Vector2.ZERO
	_move_and_check_impacts()
	if state != SlimeState.STUNNED:
		return
	if stun_time_left <= 0.0:
		_change_state(SlimeState.CHASE if _target_distance() <= disengage_range else SlimeState.WANDER)
		_choose_idle_duration()


func apply_stun(duration: float, resistance_duration: float) -> bool:
	if state == SlimeState.DEAD or duration <= 0.0 or stun_resistance_left > 0.0:
		return false
	stun_time_left = duration
	stun_resistance_left = duration + maxf(resistance_duration, 0.0)
	velocity = Vector2.ZERO
	attack_area.set_deferred("monitoring", false)
	_change_state(SlimeState.STUNNED)
	_play_hit_flash()
	return true


func _move_and_check_impacts() -> void:
	var incoming_velocity := velocity
	move_and_slide()
	for index in range(get_slide_collision_count()):
		var collision := get_slide_collision(index)
		var collider := collision.get_collider()
		if not collider is Node:
			continue
		var relative_velocity := incoming_velocity - collision.get_collider_velocity()
		var approach_speed := maxf(0.0, -relative_velocity.dot(collision.get_normal()))
		if collider.is_in_group("player"):
			if state == SlimeState.LUNGE:
				_try_lunge_hit(collider)
			continue
		if collider.is_in_group("enemies") and collider.has_method("receive_collision_impact"):
			if approach_speed >= collision_speed_threshold:
				receive_collision_impact(collider, approach_speed)
			continue
		if approach_speed >= wall_impact_speed_threshold and wall_impact_cooldown_left <= 0.0:
			wall_impact_cooldown_left = wall_impact_cooldown
			hurt_velocity = incoming_velocity.bounce(collision.get_normal()) * 0.25
			velocity = hurt_velocity
			_change_state(SlimeState.HURT)
			state_time_left = wall_impact_stun_duration


func _try_lunge_hit(body: Node) -> void:
	var body_id := body.get_instance_id()
	if attacked_targets.has(body_id):
		return
	attacked_targets[body_id] = true
	if body.has_method("receive_attack_damage"):
		body.receive_attack_damage(current_attack_id, attack_damage, global_position, attack_knockback)
	elif body.has_method("receive_damage"):
		body.receive_damage(attack_damage, global_position, attack_knockback)


func receive_collision_impact(other: Node, approach_speed: float) -> bool:
	if (
		state == SlimeState.DEAD
		or not is_instance_valid(other)
		or not other.is_in_group("enemies")
		or not other.has_method("apply_collision_stun")
		or approach_speed < collision_speed_threshold
		or collision_stun_cooldown_left > 0.0
		or float(other.get("collision_stun_cooldown_left")) > 0.0
	):
		return false
	collision_stun_cooldown_left = collision_stun_cooldown
	other.set("collision_stun_cooldown_left", collision_stun_cooldown)
	apply_collision_stun(collision_stun_duration)
	other.call("apply_collision_stun", float(other.get("collision_stun_duration")))
	return true


func apply_collision_stun(duration: float) -> void:
	if state == SlimeState.DEAD:
		return
	stun_time_left = maxf(stun_time_left, duration)
	velocity = Vector2.ZERO
	attack_area.set_deferred("monitoring", false)
	_change_state(SlimeState.STUNNED)
	_play_hit_flash()


func apply_yarn_slow(duration: float, multiplier: float) -> void:
	if state == SlimeState.DEAD or duration <= 0.0:
		return
	slow_time_left = maxf(slow_time_left, duration)
	slow_multiplier = minf(slow_multiplier, clampf(multiplier, 0.0, 1.0))


func apply_yarn_bind(duration: float) -> void:
	if state == SlimeState.DEAD or duration <= 0.0:
		return
	bind_time_left = maxf(bind_time_left, duration)
	attack_area.set_deferred("monitoring", false)
	if state == SlimeState.WINDUP or state == SlimeState.LUNGE:
		_change_state(SlimeState.RECOVER)
		state_time_left = recover_duration


func is_alive() -> bool:
	return state != SlimeState.DEAD


func receive_damage(amount: int, source_position: Vector2, knockback_force: float = 130.0) -> bool:
	if state == SlimeState.DEAD or amount <= 0:
		return false
	current_health = maxi(current_health - amount, 0)
	health_changed.emit(current_health, max_health)
	_show_in_battle_ui()
	if current_health <= 0:
		_die()
		return true
	if state == SlimeState.STUNNED:
		_play_hit_flash()
		return true

	attack_area.set_deferred("monitoring", false)
	var knockback_direction := (global_position - source_position).normalized()
	if knockback_direction == Vector2.ZERO:
		knockback_direction = -facing
	hurt_velocity = knockback_direction * knockback_force
	_change_state(SlimeState.HURT)
	state_time_left = hurt_duration
	if hit_sound.stream != null:
		hit_sound.play()
	_play_hit_flash()
	return true


func _die() -> void:
	if state == SlimeState.DEAD:
		return
	_change_state(SlimeState.DEAD)
	velocity = Vector2.ZERO
	attack_area.set_deferred("monitoring", false)
	body_collision.set_deferred("disabled", true)
	call_deferred("_drop_fish")
	if death_sound.stream != null:
		death_sound.play()
	died.emit(self)
	for ui in get_tree().get_nodes_in_group("battle_ui"):
		if ui.has_method("hide_enemy"):
			ui.hide_enemy(self)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(sprite, "scale", Vector2.ZERO, 0.28)
	tween.tween_property(sprite, "modulate:a", 0.0, 0.28)
	await tween.finished
	queue_free()


func _drop_fish() -> void:
	var drop_count := randi_range(fish_drop_min, fish_drop_max)
	for index in range(drop_count):
		var pickup = FISH_PICKUP_SCENE.instantiate()
		get_parent().add_child(pickup)
		var angle := TAU * float(index) / float(maxi(drop_count, 1)) + randf_range(-0.25, 0.25)
		pickup.global_position = global_position + Vector2.from_angle(angle) * randf_range(8.0, 16.0)


func _show_in_battle_ui() -> void:
	for ui in get_tree().get_nodes_in_group("battle_ui"):
		if ui.has_method("show_enemy"):
			ui.show_enemy(self, display_name, current_health, max_health)


func _play_hit_flash() -> void:
	sprite.modulate = Color(3.0, 3.0, 3.0, 1.0)
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.14)


func _change_state(new_state: int) -> void:
	state = new_state


func _choose_idle_duration() -> void:
	state_time_left = randf_range(idle_duration_min, idle_duration_max)


func _begin_wander() -> void:
	wander_direction = Vector2.from_angle(randf_range(0.0, TAU))
	_change_state(SlimeState.WANDER)
	state_time_left = randf_range(wander_duration_min, wander_duration_max)


func _update_facing(movement: Vector2) -> void:
	if movement == Vector2.ZERO:
		return
	if absf(movement.x) > absf(movement.y):
		facing = Vector2.RIGHT if movement.x > 0.0 else Vector2.LEFT
	else:
		facing = Vector2.DOWN if movement.y > 0.0 else Vector2.UP


func _update_sprite() -> void:
	if facing == Vector2.UP:
		sprite.texture = BACK_TEXTURE
	elif facing == Vector2.LEFT:
		sprite.texture = LEFT_TEXTURE
	elif facing == Vector2.RIGHT:
		sprite.texture = RIGHT_TEXTURE
	else:
		sprite.texture = FRONT_TEXTURE
	if state == SlimeState.WINDUP:
		sprite.frame = 0
		sprite.scale = Vector2(1.08, 0.86)
	elif state == SlimeState.LUNGE:
		sprite.frame = 3
		sprite.scale = Vector2(0.92, 1.12)
	else:
		sprite.frame = int(animation_time * 8.0) % 4
		sprite.scale = Vector2.ONE
