extends CharacterBody2D

const SPEED = 200.0

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
