extends Area2D

var cat_nearby = null

func _on_body_entered(body):
	if body.name == "Cat":
		cat_nearby = body

func _on_body_exited(body):
	if body == cat_nearby:
		cat_nearby = null

func _process(_delta):
	if cat_nearby != null and Input.is_action_just_pressed("interact"):
		var stats = cat_nearby.get_node_or_null("Cat_stats")
		if stats != null:
			stats.add_hunger(20)
			print("吃饭")
