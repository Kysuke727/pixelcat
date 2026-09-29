extends Area2D

var player_nearby: bool = false

func _on_body_entered(body) -> void:
	if body.name == "Cat":
		player_nearby = true
func _on_body_exited(body) -> void:
	if body.name == "Cat":
		player_nearby = false
func _process(_delta: float) -> void:
	if player_nearby and Input.is_action_just_pressed("interact"):
		var stats = get_tree().current_scene.get_node("Cat/Stats")
		stats.add_hunger(20)
