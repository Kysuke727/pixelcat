
extends Area2D

var cat_nearby = null
var collected: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node2D) -> void:
	if body.name == "Cat":
		cat_nearby = body
		if body.has_method("register_interactable"):
			body.register_interactable(self)


func _on_body_exited(body: Node2D) -> void:
	if body == cat_nearby:
		if body.has_method("unregister_interactable"):
			body.unregister_interactable(self)
		cat_nearby = null


func interact() -> void:
	if collected:
		return

	if cat_nearby == null:
		return

	CurrencyManager.add_fish(1)
	collected = true

	var cat = cat_nearby
	if cat.has_method("unregister_interactable"):
		cat.unregister_interactable(self)

	cat_nearby = null
	queue_free()
