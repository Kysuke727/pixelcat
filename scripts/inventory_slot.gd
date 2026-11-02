extends PanelContainer

signal slot_clicked(slot_index: int)

@onready var icon: TextureRect = $VBox/Icon
@onready var name_label: Label = $VBox/NameLabel
@onready var quantity_label: Label = $VBox/QuantityLabel

var slot_index: int = -1
var item_id: String = ""
var quantity: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clear_slot()


func set_slot_index(index: int) -> void:
	slot_index = index


func set_item(item, amount: int) -> void:
	if item == null or amount <= 0:
		clear_slot()
		return
	item_id = item.item_id
	quantity = amount
	icon.texture = item.icon
	icon.visible = item.icon != null
	name_label.text = item.display_name
	quantity_label.text = "×%d" % amount if amount > 1 else ""


func clear_slot() -> void:
	item_id = ""
	quantity = 0
	icon.texture = null
	icon.visible = false
	name_label.text = ""
	quantity_label.text = ""
	set_selected(false)


func set_selected(selected: bool) -> void:
	self_modulate = Color(1.0, 1.0, 0.7, 1.0) if selected else Color.WHITE


func get_item_id() -> String:
	return item_id


func get_quantity() -> int:
	return quantity


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		slot_clicked.emit(slot_index)
		accept_event()
