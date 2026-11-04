extends Control

@onready var slot_nodes: Array[PanelContainer] = [
	$QuickbarPanel/QuickbarSlots/Slot1,
	$QuickbarPanel/QuickbarSlots/Slot2,
	$QuickbarPanel/QuickbarSlots/Slot3,
	$QuickbarPanel/QuickbarSlots/Slot4,
]

var key_labels: Array[Label] = []
var item_name_labels: Array[Label] = []
var quantity_labels: Array[Label] = []
var selected_slot_index: int = -1
var last_activation: Dictionary = {}


func _ready() -> void:
	add_to_group("quickbar_ui")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cache_labels()
	if not QuickbarManager.quickbar_changed.is_connected(refresh_quickbar):
		QuickbarManager.quickbar_changed.connect(refresh_quickbar)
	if not InventoryManager.inventory_changed.is_connected(refresh_quickbar):
		InventoryManager.inventory_changed.connect(refresh_quickbar)
	refresh_quickbar()


func _cache_labels() -> void:
	for index in range(slot_nodes.size()):
		var content: Node = slot_nodes[index].get_node("Content")
		key_labels.append(content.get_node("KeyLabel") as Label)
		item_name_labels.append(content.get_node("ItemName") as Label)
		quantity_labels.append(content.get_node("QuantityLabel") as Label)
		key_labels[index].text = str(index + 1)


func refresh_quickbar() -> void:
	for index in range(slot_nodes.size()):
		var item_id: String = QuickbarManager.get_bound_item_id(index)
		var item = QuickbarManager.get_bound_item_data(index)
		var quantity: int = QuickbarManager.get_bound_item_count(index)
		if item_id.is_empty() or item == null:
			item_name_labels[index].text = "空"
			quantity_labels[index].text = ""
			slot_nodes[index].modulate = Color(1, 1, 1, 0.55)
		else:
			item_name_labels[index].text = item.display_name
			quantity_labels[index].text = str(quantity)
			if quantity <= 0:
				slot_nodes[index].modulate = Color(0.5, 0.5, 0.5, 0.65)
			else:
				slot_nodes[index].modulate = Color.WHITE
		if index == selected_slot_index and not item_id.is_empty():
			slot_nodes[index].modulate = Color(1.0, 1.0, 0.7, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if InventoryManager.ui_open:
		return
	for index in range(QuickbarManager.SLOT_COUNT):
		var action := StringName("quickbar_%d" % (index + 1))
		if InputMap.has_action(action) and event.is_action_pressed(action) and not event.is_echo():
			activate_slot(index)
			get_viewport().set_input_as_handled()
			return


func activate_slot(slot_index: int) -> void:
	selected_slot_index = slot_index
	last_activation = QuickbarManager.activate_slot(slot_index)
	refresh_quickbar()
