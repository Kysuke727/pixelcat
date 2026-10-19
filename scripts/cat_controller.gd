extends CharacterBody2D

const SPEED = 200.0
signal health_changed(current_health: int, max_health: int)
signal died

@export var max_health: int = 6
@export var invincibility_duration: float = 0.8
@export var hitstun_duration: float = 0.22
@export var received_knockback_decay: float = 700.0

var current_health: int
var nearby_objects: Array[Node] = []
var last_facing: Vector2 = Vector2.DOWN
var invincibility_left: float = 0.0
var hitstun_left: float = 0.0
var knockback_velocity: Vector2 = Vector2.ZERO
var dead: bool = false

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var combat = get_node_or_null("PlayerCombat")


func _ready() -> void:
	current_health = max_health
	add_to_group("player")
	animated_sprite.play("idle")
	health_changed.emit(current_health, max_health)


func _physics_process(delta: float) -> void:
	invincibility_left = maxf(invincibility_left - delta, 0.0)
	hitstun_left = maxf(hitstun_left - delta, 0.0)

	if dead:
		velocity = Vector2.ZERO
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

	var movement_multiplier := 1.0
	if combat != null and combat.has_method("get_movement_multiplier"):
		movement_multiplier = combat.get_movement_multiplier()
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


func play_hit_feedback() -> void:
	animated_sprite.modulate = Color(1.0, 0.35, 0.35, 1.0)
	var tween := create_tween()
	tween.tween_property(animated_sprite, "modulate", Color.WHITE, 0.16)


func die() -> void:
	if dead:
		return
	dead = true
	velocity = Vector2.ZERO
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
