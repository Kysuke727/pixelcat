extends Area2D
## Persisted, auto-collected enemy loot. ID is unique to one enemy death.
var saved_drop_id: String = ""
var item_id: String = ""
var amount: int = 1
var collected: bool = false


func setup_saved_drop(drop_id: String, material_id: String, quantity: int = 1) -> void:
	saved_drop_id = drop_id
	item_id = material_id
	amount = maxi(quantity, 1)


func _ready() -> void:
	add_to_group("material_drops")
	var inventory: Node = get_node("/root/InventoryManager")
	var item = inventory.get_item_data(item_id)
	if item == null:
		push_warning("Missing material drop item: " + item_id)
		return
	var sprite := Sprite2D.new()
	sprite.texture = item.icon
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(0.55, 0.55)
	add_child(sprite)
	body_entered.connect(_on_body_entered)
	# If the player is standing on a spawn position, a physics update still
	# emits the overlap signal on the next frame.


func _on_body_entered(body: Node2D) -> void:
	var progression: Node = get_node("/root/ProgressionManager")
	var expedition: Node = get_node("/root/ExpeditionManager")
	if collected or not body.is_in_group("player") or progression.debug_session:
		return
	if saved_drop_id.is_empty() or not expedition.run_active:
		return
	if not expedition.collect_saved_material_drop(saved_drop_id):
		return
	collected = true
	set_deferred("monitoring", false)
	queue_free()
