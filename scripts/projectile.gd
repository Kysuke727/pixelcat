extends Area2D

@export var damage: int = 1
@export var speed: float = 220.0
@export var max_range: float = 220.0
@export var knockback_force: float = 90.0

var direction: Vector2 = Vector2.RIGHT
var source: Node2D
var distance_travelled: float = 0.0
var hit_targets: Dictionary = {}
var consumed: bool = false
var combat_paused: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func setup(
	new_direction: Vector2,
	new_source: Node2D,
	new_damage: int,
	new_speed: float,
	new_max_range: float
) -> void:
	direction = new_direction.normalized()
	source = new_source
	if is_instance_valid(source) and source.is_in_group("enemies"):
		add_to_group("enemy_projectiles")
		var time_controller := get_node_or_null("/root/CombatTimeController")
		if is_instance_valid(time_controller) and time_controller.is_enemy_side_paused():
			combat_paused = true
	damage = new_damage
	speed = new_speed
	max_range = new_max_range
	rotation = direction.angle()


func _physics_process(delta: float) -> void:
	if consumed or combat_paused:
		return
	var movement := direction * speed * delta
	var query := PhysicsRayQueryParameters2D.create(global_position, global_position + movement)
	query.collision_mask = collision_mask
	if is_instance_valid(source) and source is CollisionObject2D:
		query.exclude = [source.get_rid()]
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_handle_hit(hit["collider"] as Node2D)
		return
	global_position += movement
	distance_travelled += movement.length()
	$Sprite2D.rotation += delta * 8.0
	if distance_travelled >= max_range:
		_notify_yarn_miss()
		_consume()


func set_combat_paused(paused: bool) -> void:
	combat_paused = paused


func _on_body_entered(body: Node2D) -> void:
	_handle_hit(body)


func _handle_hit(body: Node2D) -> void:
	if consumed or body == source:
		return
	var body_id := body.get_instance_id()
	if hit_targets.has(body_id):
		return
	hit_targets[body_id] = true
	var yarn_connected := false
	if body.has_method("receive_damage"):
		var accepted: bool = body.receive_damage(damage, global_position - direction * 4.0, knockback_force)
		if accepted and body.is_in_group("enemies"):
			var combat := _get_source_combat()
			if is_instance_valid(combat) and combat.has_method("on_yarn_hit"):
				yarn_connected = combat.on_yarn_hit(body)
	if not yarn_connected:
		_notify_yarn_miss()
	_consume()


func _get_source_combat() -> Node:
	if not is_instance_valid(source):
		return null
	return source.get_node_or_null("PlayerCombat")


func _notify_yarn_miss() -> void:
	var combat := _get_source_combat()
	if is_instance_valid(combat) and combat.has_method("on_yarn_miss"):
		combat.on_yarn_miss()


func _consume() -> void:
	if consumed:
		return
	consumed = true
	set_deferred("monitoring", false)
	queue_free()
