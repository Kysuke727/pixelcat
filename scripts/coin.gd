
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

	var coin_ui = get_tree().current_scene.find_child(
		"CoinUI",
		true,
		false
	)

	if coin_ui == null:
		print("没有找到 CoinUI，请检查金币 UI 是否已加入当前场景")
		return

	if not coin_ui.has_method("add_coins"):
		print("CoinUI 没有 add_coins 方法")
		return

	coin_ui.add_coins(1)
	collected = true

	var cat = cat_nearby
	if cat.has_method("unregister_interactable"):
		cat.unregister_interactable(self)

	cat_nearby = null
	queue_free()
