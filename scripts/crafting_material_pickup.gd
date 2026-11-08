extends Area2D

## Day 14 prototype supply spot. Day 16 may replace this with real gathering.
@export var item_id: String = "yarn"
@export_range(1, 99, 1) var quantity: int = 3

var cat_nearby: Node2D
var icon: Sprite2D


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	icon = Sprite2D.new()
	var item = InventoryManager.get_item_data(item_id)
	if item == null:
		push_error("Invalid material pickup item: " + item_id)
		return
	icon.texture = item.icon
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.scale = Vector2(0.65, 0.65)
	add_child(icon)


func _on_body_entered(body: Node2D) -> void:
	if body.name == "Cat":
		cat_nearby = body
		body.register_interactable(self)


func _on_body_exited(body: Node2D) -> void:
	if body == cat_nearby:
		body.unregister_interactable(self)
		cat_nearby = null


func interact() -> void:
	if cat_nearby == null or InventoryManager.ui_open:
		return
	var result: Dictionary = InventoryManager.add_item(item_id, quantity)
	var added: int = int(result.get("added", 0))
	if added == 0:
		return
	quantity -= added
	if quantity <= 0:
		# The same input press cannot collect a second resource twice.
		set_deferred("monitoring", false)
		queue_free()
