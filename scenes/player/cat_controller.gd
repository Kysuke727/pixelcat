extends CharacterBody2D
const SPEED = 200.0
@onready var animated_sprite = $AnimatedSprite2D
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
	move_and_slide()
