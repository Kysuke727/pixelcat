extends Area2D

var cat_nearby: Node2D


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	queue_redraw()


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


func _draw() -> void:
	# Pixel-sharp little workbench; no blurred image or separate imported asset.
	draw_rect(Rect2(-25, -17, 50, 32), Color("#85533e"))
	draw_rect(Rect2(-22, -14, 44, 23), Color("#d99460"))
	draw_rect(Rect2(-19, -11, 38, 17), Color("#efba80"))
	draw_rect(Rect2(-17, 12, 8, 13), Color("#9d6345"))
	draw_rect(Rect2(9, 12, 8, 13), Color("#9d6345"))
	draw_rect(Rect2(-13, -8, 12, 7), Color("#f5a3c0"))
	draw_rect(Rect2(-11, -6, 8, 3), Color("#cf729b"))
	draw_rect(Rect2(4, -8, 13, 5), Color("#c9c2cb"))
	draw_rect(Rect2(8, -11, 4, 11), Color("#8d808c"))
