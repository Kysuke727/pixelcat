
extends Control

@onready var slot_nodes: Array[PanelContainer] = [
	$QuickbarPanel/QuickbarSlots/Slot1,
	$QuickbarPanel/QuickbarSlots/Slot2,
	$QuickbarPanel/QuickbarSlots/Slot3,
	$QuickbarPanel/QuickbarSlots/Slot4
]

var key_labels: Array[Label] = []
var item_name_labels: Array[Label] = []
var quantity_labels: Array[Label] = []


func _ready() -> void:
	_cache_labels()

	if not QuickbarManager.quickbar_changed.is_connected(refresh_quickbar):
		QuickbarManager.quickbar_changed.connect(refresh_quickbar)

	if not InventoryManager.inventory_changed.is_connected(refresh_quickbar):
		InventoryManager.inventory_changed.connect(refresh_quickbar)

	refresh_quickbar()


func _cache_labels() -> void:
	for i in range(slot_nodes.size()):
		var content: Node = slot_nodes[i].get_node("Content")

		key_labels.append(content.get_node("KeyLabel") as Label)
		item_name_labels.append(content.get_node("ItemName") as Label)
		quantity_labels.append(content.get_node("QuantityLabel") as Label)

		key_labels[i].text = str(i + 1)


func refresh_quickbar() -> void:
	for i in range(slot_nodes.size()):
		var item_id: String = QuickbarManager.get_bound_item_id(i)
		var item: ItemData = QuickbarManager.get_bound_item_data(i)
		var quantity: int = QuickbarManager.get_bound_item_count(i)

		if item_id.is_empty() or item == null:
			item_name_labels[i].text = "空"
			quantity_labels[i].text = ""
			slot_nodes[i].modulate = Color(1, 1, 1, 0.65)
			continue

		item_name_labels[i].text = item.display_name
		quantity_labels[i].text = str(quantity)

		if quantity <= 0:
			slot_nodes[i].modulate = Color(0.5, 0.5, 0.5, 0.65)
		else:
			slot_nodes[i].modulate = Color(1, 1, 1, 1)
