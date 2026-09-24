extends Area2D

func _on_body_entered(body):

	if body.name == "Cat":

		var stats = body.get_node("Cat_stats")

		stats.mood += 20
		stats.mood = clamp(stats.mood, 0.0, 100.0)

		print("玩耍")
