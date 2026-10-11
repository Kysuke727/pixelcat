extends CharacterBody2D

const SPEED = 200.0
var nearby_objects = []
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready():
	animated_sprite.play("idle")


func _physics_process(delta):
	var direction = Input.get_vector(
		"move_left",
		"move_right",
		"move_up",
		"move_down"
	)

	velocity = direction * SPEED

	update_animation(direction)

	move_and_slide()


func update_animation(direction):
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
func register_interactable(object):
	if not nearby_objects.has(object):
		nearby_objects.append(object)
func unregister_interactable(object):
	nearby_objects.erase(object)
func _process(_delta):
	if Input.is_action_just_pressed("interact"):
		if nearby_objects.size() > 0:
			var min_distance = INF
			var nearest_object = null
			for object in nearby_objects:
				var distance = global_position.distance_to(object.get_node("CollisionShape2D").global_position)
				print(object.name, " 距离：", distance)
				if distance < min_distance:
					min_distance = distance
					nearest_object = object
			print("最近的家具：", nearest_object.name)
			if nearest_object.has_method("interact"):
				nearest_object.interact()
		else:
			print("附近没有家具")
