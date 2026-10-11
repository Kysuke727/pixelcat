extends Area2D
var cat_nearby = null
func _on_body_entered(body):
	if body.name == "Cat":
		cat_nearby = body
		body.register_interactable(self)
func _on_body_exited(body):
	if body == cat_nearby:
		body.unregister_interactable(self)
		cat_nearby = null
func interact():
	if cat_nearby != null:
		var stats = cat_nearby.get_node_or_null("Stats")
		if stats != null:
			stats.add_mood(20)
			print("玩耍")
