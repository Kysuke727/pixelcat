extends Area2D

var cat_nearby = null


func _on_body_entered(body):
	if body.has_method("register_interactable"):
		cat_nearby = body
		body.register_interactable(self)
		print("小猫靠近了房门")


func _on_body_exited(body):
	if body == cat_nearby:
		body.unregister_interactable(self)
		cat_nearby = null
		print("小猫离开了房门")


func interact():
	if cat_nearby != null:
		print("小猫准备出门！")
		DayManager.switch_to_night()
