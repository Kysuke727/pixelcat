
extends Control

const SLOT_SCENE: PackedScene = preload("res://scenes/ui/inventory_slot.tscn")
const SLOT_COUNT: int = 24
const COLUMN_COUNT: int = 6

@onready var open_sound: AudioStreamPlayer = $OpenSound
@onready var slot_grid: GridContainer = $Background/Content/SlotGrid

var is_open: bool = false
var inventory_slots: Array[Node] = []
var selected_slot_index: int = -1


func _ready() -> void:
	hide()
	is_open = false
	slot_grid.columns = COLUMN_COUNT
	_create_slots()

	if not InventoryManager.inventory_changed.is_connected(refresh_inventory):
		InventoryManager.inventory_changed.connect(refresh_inventory)

	refresh_inventory()


func _create_slots() -> void:
	for child in slot_grid.get_children():
		slot_grid.remove_child(child)
		child.queue_free()

	inventory_slots.clear()

	for i in range(SLOT_COUNT):
		var slot_scene: Control = SLOT_SCENE.instantiate()
		slot_scene.custom_minimum_size = Vector2(88, 72)
		slot_grid.add_child(slot_scene)

		var slot: Node = slot_scene.get_node_or_null("InventorySlot")

		if slot == null:
			push_error("inventory_slot.tscn 缺少 InventorySlot 子节点")
			continue

		slot.set_slot_index(i)
		slot.slot_clicked.connect(_on_slot_clicked)
		inventory_slots.append(slot)


func refresh_inventory() -> void:
	if not is_node_ready():
		return

	for i in range(inventory_slots.size()):
		var slot: Node = inventory_slots[i]
		var data: Dictionary = InventoryManager.get_slot(i)

		if data.is_empty():
			slot.clear_slot()
			continue

		var item_id: String = str(data.get("item_id", ""))
		var quantity: int = int(data.get("quantity", 0))
		var item: ItemData = InventoryManager.get_item_data(item_id)

		if item == null or quantity <= 0:
			slot.clear_slot()
		else:
			slot.set_item(item, quantity)


func _on_slot_clicked(index: int) -> void:
	selected_slot_index = index

	var data: Dictionary = InventoryManager.get_slot(index)

	if data.is_empty():
		return

	var item_id: String = str(data.get("item_id", ""))
	var item: ItemData = InventoryManager.get_item_data(item_id)

	if item != null:
		print("选中物品：", item.display_name)
		print("物品说明：", item.description)
		print("物品数量：", data.get("quantity", 0))


func toggle_inventory() -> void:
	is_open = not is_open
	visible = is_open

	if is_open:
		refresh_inventory()

		if open_sound.stream != null:
			open_sound.play()


func close_inventory() -> void:
	if not is_open:
		return

	is_open = false
	hide()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory") and not event.is_echo():
		toggle_inventory()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_cancel") and is_open:
		close_inventory()
		get_viewport().set_input_as_handled()
