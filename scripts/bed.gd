extends Area2D

func _on_body_entered(body):

	if body.name == "Cat":

		var stats = body.get_node("Cat_stats")

		stats.energy += 20
		stats.energy = clamp(stats.energy, 0.0, 100.0)

		print("睡觉")
