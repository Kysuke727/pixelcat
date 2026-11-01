
extends PanelContainer

signal slot_clicked(slot_index: int)

@onready var item_icon: TextureRect = $ItemIcon
@onready var quantity_label: Label = $QuantityLabel

var slot_index: int = -1
var item_id: String = ""
var quantity: int = 0

# 三种格子样式
var normal_style: StyleBoxFlat
var hover_style: StyleBoxFlat
var selected_style: StyleBoxFlat

# 是否选中
var is_selected: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

	# 普通状态
	normal_style = get_theme_stylebox("panel").duplicate() as StyleBoxFlat

	# 鼠标悬停状态
	hover_style = normal_style.duplicate()
	hover_style.bg_color = Color("#F8DCE5")

	# 选中状态
	selected_style = normal_style.duplicate()
	selected_style.bg_color = Color("#FFF0F3")
	selected_style.border_color = Color("#DDA6B9")
	selected_style.set_border_width_all(3)

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

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


# 设置格子是否被选中
func set_selected(value: bool) -> void:
	is_selected = value

	if is_selected:
		add_theme_stylebox_override("panel", selected_style)
	else:
		add_theme_stylebox_override("panel", normal_style)


# 鼠标进入
func _on_mouse_entered() -> void:
	if not is_selected:
		add_theme_stylebox_override("panel", hover_style)


# 鼠标离开
func _on_mouse_exited() -> void:
	if is_selected:
		add_theme_stylebox_override("panel", selected_style)
	else:
		add_theme_stylebox_override("panel", normal_style)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			slot_clicked.emit(slot_index)
			accept_event()
