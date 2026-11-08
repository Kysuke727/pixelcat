extends Area2D

var cat_nearby: Node2D


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node2D) -> void:
	if body.name == "Cat":
		cat_nearby = body
		body.register_interactable(self)


func _on_body_exited(body: Node2D) -> void:
	if body == cat_nearby:
		body.unregister_interactable(self)
		cat_nearby = null


func interact() -> void:
	if cat_nearby == null:
		return
	var crafting = get_tree().get_first_node_in_group("crafting_ui")
	if crafting != null:
		crafting.open_crafting(true, false)
