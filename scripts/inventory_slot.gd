
extends PanelContainer

signal slot_clicked(slot_index: int)

@onready var item_icon: TextureRect = $ItemIcon
@onready var quantity_label: Label = $QuantityLabel

var slot_index: int = -1
var item_id: String = ""
var quantity: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clear_slot()


func set_slot_index(index: int) -> void:
	slot_index = index


func set_item(item: ItemData, amount: int) -> void:
	if item == null or amount <= 0:
		clear_slot()
		return

	item_id = item.item_id
	quantity = amount

	item_icon.texture = item.icon
	item_icon.visible = item.icon != null

	if amount > 1:
		quantity_label.text = str(amount)
		quantity_label.visible = true
	else:
		quantity_label.text = ""
		quantity_label.visible = false


func clear_slot() -> void:
	item_id = ""
	quantity = 0

	if is_node_ready():
		item_icon.texture = null
		item_icon.visible = false
		quantity_label.text = ""
		quantity_label.visible = false


func get_item_id() -> String:
	return item_id


func get_quantity() -> int:
	return quantity


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			slot_clicked.emit(slot_index)
			accept_event()
