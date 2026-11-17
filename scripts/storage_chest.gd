extends Area2D

## The storage chest at home: stand next to it and press E. Whatever is inside is safe from
## the death penalty (only the backpack loses items).

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
	var storage = get_tree().get_first_node_in_group("storage_ui")
	if storage != null:
		storage.open_storage()
