extends CharacterBody2D

const SPEED = 200.0
signal health_changed(current_health: int, max_health: int)
signal died

@export var max_health: int = 6
@export var invincibility_duration: float = 0.8
@export var hitstun_duration: float = 0.22
@export var player_hit_stagger_duration: float = 0.5
@export var received_knockback_decay: float = 700.0

@export_category("Defense")
@export var shield_max_durability: float = 100.0
@export var slime_attack_shield_cost: float = 35.0
@export var shield_regen_delay: float = 2.0
@export var shield_regen_per_second: float = 20.0
@export var defense_movement_multiplier: float = 0.55
@export var guard_break_stun_duration: float = 3.0
@export var perfect_guard_window: float = 0.7
@export var perfect_guard_pause_duration: float = 1.0

var current_health: int
var nearby_objects: Array[Node] = []
var last_facing: Vector2 = Vector2.DOWN
var invincibility_left: float = 0.0
var hitstun_left: float = 0.0
var knockback_velocity: Vector2 = Vector2.ZERO
var dead: bool = false
var shield_durability: float = 100.0
var shield_regen_delay_left: float = 0.0
var guard_break_left: float = 0.0
var is_defending: bool = false
var perfect_guard_flash_left: float = 0.0
var defend_must_release: bool = false
var perfect_guard_hold_consumed: bool = false
var received_attack_ids: Dictionary = {}
var received_attack_id_order: Array[int] = []
var attack_block_handler: Callable

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var combat = get_node_or_null("PlayerCombat")


func _ready() -> void:
	current_health = max_health
	shield_durability = shield_max_durability
	add_to_group("player")
	animated_sprite.play("idle")
	var time_controller := get_node_or_null("/root/CombatTimeController")
	if is_instance_valid(time_controller) and time_controller.is_enemy_side_paused():
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if enemy.has_method("set_combat_paused"):
				enemy.set_combat_paused(true)
	health_changed.emit(current_health, max_health)


func _physics_process(delta: float) -> void:
	invincibility_left = maxf(invincibility_left - delta, 0.0)
	hitstun_left = maxf(hitstun_left - delta, 0.0)

	if dead:
		velocity = Vector2.ZERO
		return
	_update_defense(delta)
	if guard_break_left > 0.0:
		velocity = Vector2.ZERO
		update_animation(Vector2.ZERO)
		move_and_slide()
		return

	if hitstun_left > 0.0:
		velocity = knockback_velocity
		knockback_velocity = knockback_velocity.move_toward(
			Vector2.ZERO,
			received_knockback_decay * delta
		)
		move_and_slide()
		return

	var direction = Input.get_vector(
		"move_left",
		"move_right",
		"move_up",
		"move_down"
	)
	if direction != Vector2.ZERO:
		last_facing = direction.normalized()

	var movement_multiplier := defense_movement_multiplier if is_defending else 1.0
	if combat != null and combat.has_method("get_movement_multiplier"):
		movement_multiplier *= combat.get_movement_multiplier()
	velocity = direction * SPEED * movement_multiplier

	if combat == null or not combat.has_method("is_action_active") or not combat.is_action_active():
		update_animation(direction)

	move_and_slide()


func update_animation(direction: Vector2) -> void:
	if dead:
		return
	if direction == Vector2.ZERO:
		animated_sprite.play("idle")
		return

	if abs(direction.x) > abs(direction.y):
		if direction.x > 0:
			animated_sprite.play("walk_right")
		else:
			animated_sprite.play("walk_left")
	else:
		if direction.y > 0:
			animated_sprite.play("walk_down")
		else:
			animated_sprite.play("walk_up")


func restore_movement_animation() -> void:
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	update_animation(direction)


func get_last_facing() -> Vector2:
	return last_facing


func get_facing_name() -> String:
	if absf(last_facing.x) > absf(last_facing.y):
		return "right" if last_facing.x > 0.0 else "left"
	return "down" if last_facing.y > 0.0 else "up"


func is_alive() -> bool:
	return not dead


func is_in_hitstun() -> bool:
	return hitstun_left > 0.0


func can_perform_combat_action() -> bool:
	return (
		not dead
		and hitstun_left <= 0.0
		and guard_break_left <= 0.0
		and not is_defending
	)


func is_guard_broken() -> bool:
	return guard_break_left > 0.0


func _update_defense(delta: float) -> void:
	perfect_guard_flash_left = maxf(perfect_guard_flash_left - delta, 0.0)
	var defend_held := Input.is_action_pressed("defend")
	var defend_just_pressed := Input.is_action_just_pressed("defend")
	if not defend_held:
		if is_defending:
			is_defending = false
			shield_regen_delay_left = shield_regen_delay
		defend_must_release = false
		perfect_guard_hold_consumed = false
	if guard_break_left > 0.0:
		guard_break_left = maxf(guard_break_left - delta, 0.0)
		is_defending = false
		return
	if hitstun_left > 0.0:
		is_defending = false
		return
	if defend_just_pressed and not defend_must_release and shield_durability > 0.0:
		_handle_defend_press(defend_held)
	elif (
		defend_held
		and not perfect_guard_hold_consumed
		and not defend_must_release
		and shield_durability > 0.0
		and not is_defending
	):
		is_defending = true
		if combat != null and combat.has_method("cancel_action"):
			combat.cancel_action()
	if is_defending:
		return
	if shield_regen_delay_left > 0.0:
		shield_regen_delay_left = maxf(shield_regen_delay_left - delta, 0.0)
	elif shield_durability < shield_max_durability:
		shield_durability = minf(
			shield_durability + shield_regen_per_second * delta,
			shield_max_durability
		)


func _handle_defend_press(defend_held: bool) -> void:
	if defend_must_release or shield_durability <= 0.0 or guard_break_left > 0.0 or hitstun_left > 0.0:
		return
	if _try_perfect_guard():
		perfect_guard_hold_consumed = defend_held
		is_defending = false
	else:
		is_defending = true
		if combat != null and combat.has_method("cancel_action"):
			combat.cancel_action()


func _try_perfect_guard() -> bool:
	var time_controller := get_node_or_null("/root/CombatTimeController")
	if not is_instance_valid(time_controller) or time_controller.is_enemy_side_paused():
		return false
	var best_enemy: Node = null
	var best_attack_id: int = 0
	var best_eta := INF
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy.has_method("get_attack_eta_for"):
			continue
		var eta: float = enemy.get_attack_eta_for(self, perfect_guard_window)
		if eta >= 0.0 and eta < best_eta:
			best_enemy = enemy
			best_attack_id = int(enemy.current_attack_id)
			best_eta = eta
	if not is_instance_valid(best_enemy) or not best_enemy.has_method("parry_attack"):
		return false
	if not best_enemy.parry_attack(best_attack_id):
		return false
	time_controller.pause_enemy_side(perfect_guard_pause_duration)
	perfect_guard_flash_left = perfect_guard_pause_duration
	return true


func _break_shield() -> void:
	shield_durability = 0.0
	guard_break_left = guard_break_stun_duration
	is_defending = false
	defend_must_release = Input.is_action_pressed("defend")
	if combat != null and combat.has_method("cancel_action"):
		combat.cancel_action()


func receive_damage(amount: int, source_position: Vector2, knockback_force: float = 120.0) -> bool:
	if dead or invincibility_left > 0.0 or amount <= 0:
		return false

	current_health = maxi(current_health - amount, 0)
	invincibility_left = invincibility_duration
	hitstun_left = hitstun_duration
	var knockback_direction := (global_position - source_position).normalized()
	if knockback_direction == Vector2.ZERO:
		knockback_direction = -last_facing
	knockback_velocity = knockback_direction.normalized() * knockback_force
	if combat != null and combat.has_method("cancel_action"):
		combat.cancel_action()
	health_changed.emit(current_health, max_health)
	play_hit_feedback()

	if current_health <= 0:
		die()
	return true


func receive_attack_damage(
	attack_id: int,
	amount: int,
	source_position: Vector2,
	knockback_force: float = 120.0,
	shield_damage: float = 35.0
) -> bool:
	if attack_id <= 0 or received_attack_ids.has(attack_id):
		return false
	received_attack_ids[attack_id] = true
	received_attack_id_order.append(attack_id)
	if received_attack_id_order.size() > 128:
		var expired_id: int = received_attack_id_order.pop_front()
		received_attack_ids.erase(expired_id)
	if try_block_attack(attack_id, shield_damage):
		return true
	var accepted := receive_damage(amount, source_position, knockback_force)
	if accepted and not dead:
		hitstun_left = player_hit_stagger_duration
	return accepted


func try_block_attack(attack_id: int, shield_damage: float = 35.0) -> bool:
	if attack_block_handler.is_valid():
		return bool(attack_block_handler.call(attack_id))
	if dead or guard_break_left > 0.0 or not is_defending or shield_durability <= 0.0:
		return false
	shield_durability = maxf(shield_durability - maxf(shield_damage, 0.0), 0.0)
	if shield_durability <= 0.0:
		_break_shield()
	return true


func play_hit_feedback() -> void:
	animated_sprite.modulate = Color(1.0, 0.35, 0.35, 1.0)
	var tween := create_tween()
	tween.tween_property(animated_sprite, "modulate", Color.WHITE, 0.16)


func die() -> void:
	if dead:
		return
	dead = true
	is_defending = false
	velocity = Vector2.ZERO
	var time_controller := get_node_or_null("/root/CombatTimeController")
	if is_instance_valid(time_controller):
		time_controller.clear_enemy_pause()
	if combat != null and combat.has_method("set_combat_enabled"):
		combat.set_combat_enabled(false)
	animated_sprite.stop()
	animated_sprite.modulate = Color(0.45, 0.45, 0.55, 1.0)
	died.emit()


func register_interactable(object: Node) -> void:
	if not nearby_objects.has(object):
		nearby_objects.append(object)


func unregister_interactable(object: Node) -> void:
	nearby_objects.erase(object)


func _process(_delta: float) -> void:
	if dead:
		return
	if Input.is_action_just_pressed("interact"):
		nearby_objects = nearby_objects.filter(func(object: Node) -> bool: return is_instance_valid(object))
		if nearby_objects.size() > 0:
			var min_distance = INF
			var nearest_object: Node = null
			for object in nearby_objects:
				var interactable := object as Node2D
				if interactable == null:
					continue
				var collision_shape := interactable.get_node_or_null("CollisionShape2D") as Node2D
				var target_position := interactable.global_position
				if collision_shape != null:
					target_position = collision_shape.global_position
				var distance = global_position.distance_to(target_position)
				print(object.name, " 距离：", distance)
				if distance < min_distance:
					min_distance = distance
					nearest_object = object
			print("最近的家具：", nearest_object.name)
			if nearest_object.has_method("interact"):
				nearest_object.interact()
		else:
			print("附近没有家具")
