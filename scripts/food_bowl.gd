extends Area2D

func _on_body_entered(body):

	if body.name == "Cat":

		var stats = body.get_node("Cat_stats")

		stats.hunger += 20
		stats.hunger = clamp(stats.hunger, 0.0, 100.0)

		print("吃饭")
