extends Area2D
class_name SecretSpot

## A "cat secret": walking into it teaches a move the first time. It is never required
## to clear a map; it is a reward for exploring.

signal secret_found(move_id: String)

@export var move_id: String = "triple_combo"


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if ProgressionManager.has_move(move_id):
		HitFeel.damage_number(global_position + Vector2(0.0, -34.0), "这里你来过了", HitFeel.CREAM, 13)
		return
	if ProgressionManager.unlock_move(move_id):  # shows the "学会了新招式" banner
		HitFeel.spark(global_position, HitFeel.GOLD, 20, 170.0)
		HitFeel.damage_number(global_position + Vector2(0.0, -34.0), "猫猫的小秘密！", HitFeel.GOLD, 18)
		HitFeel.shake(0.15)
		secret_found.emit(move_id)
