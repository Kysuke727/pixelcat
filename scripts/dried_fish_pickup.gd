extends Area2D

@export var value: int = 1
var collected: bool = false
var elapsed: float = 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	elapsed += delta
	$Sprite2D.position.y = sin(elapsed * 4.0) * 2.0


func _on_body_entered(body: Node2D) -> void:
	if collected or not body.is_in_group("player"):
		return
	collected = true
	set_deferred("monitoring", false)
	CurrencyManager.add_fish(value)
	queue_free()
