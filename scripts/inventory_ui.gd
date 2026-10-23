
extends Control

const SLOT_SCENE: PackedScene = preload("res://scenes/ui/inventory_slot.tscn")
const SLOT_COUNT: int = 24
const COLUMN_COUNT: int = 6

@onready var open_sound: AudioStreamPlayer = $OpenSound
@onready var slot_grid: GridContainer = $Background/Content/SlotGrid

@onready var item_name_label: Label = $Background/Content/ItemDetails/ItemName
@onready var item_description_label: Label = $Background/Content/ItemDetails/ItemDescription
@onready var item_quantity_label: Label = $Background/Content/ItemDetails/ItemQuantity
@onready var bind_button: Button = $Background/Content/ItemDetails/BindQuickbarButton

var is_open: bool = false
var inventory_slots: Array[Node] = []
var selected_slot_index: int = -1
var selected_item_id: String = ""

var bind_popup: PopupMenu


func _ready() -> void:
	hide()
	is_open = false

	slot_grid.columns = COLUMN_COUNT

	_create_slots()
	_create_bind_popup()
	_clear_item_details()

	bind_button.text = "设置快捷栏"
	bind_button.pressed.connect(_on_bind_button_pressed)

	if not InventoryManager.inventory_changed.is_connected(refresh_inventory):
		InventoryManager.inventory_changed.connect(refresh_inventory)

	if not QuickbarManager.quickbar_changed.is_connected(_on_quickbar_changed):
		QuickbarManager.quickbar_changed.connect(_on_quickbar_changed)

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


func _create_bind_popup() -> void:
	bind_popup = PopupMenu.new()
	bind_popup.name = "BindQuickbarPopup"

	for i in range(4):
		bind_popup.add_item("绑定到快捷栏 " + str(i + 1), i)

	bind_popup.add_separator()
	bind_popup.add_item("清除所选快捷栏绑定", 4)

	add_child(bind_popup)
	bind_popup.id_pressed.connect(_on_bind_popup_id_pressed)


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

	# 物品被消耗或移除后，同步更新详情
	if selected_slot_index >= 0:
		var selected_data: Dictionary = InventoryManager.get_slot(selected_slot_index)

		if selected_data.is_empty():
			_clear_item_details()
		else:
			var current_id: String = str(selected_data.get("item_id", ""))
			var current_quantity: int = int(selected_data.get("quantity", 0))

			if current_id != selected_item_id or current_quantity <= 0:
				_clear_item_details()
			else:
				_show_item_details(current_id, current_quantity)


func _on_slot_clicked(index: int) -> void:
	selected_slot_index = index

	var data: Dictionary = InventoryManager.get_slot(index)

	if data.is_empty():
		_clear_item_details()
		return

	var item_id: String = str(data.get("item_id", ""))
	var quantity: int = int(data.get("quantity", 0))

	if item_id.is_empty() or quantity <= 0:
		_clear_item_details()
		return

	selected_item_id = item_id
	_show_item_details(item_id, quantity)


func _show_item_details(item_id: String, quantity: int) -> void:
	var item: ItemData = InventoryManager.get_item_data(item_id)

	if item == null:
		_clear_item_details()
		return

	selected_item_id = item_id
	item_name_label.text = item.display_name
	item_description_label.text = item.description
	item_quantity_label.text = "数量：" + str(quantity)

	bind_button.disabled = not item.usable


func _clear_item_details() -> void:
	selected_slot_index = -1
	selected_item_id = ""

	item_name_label.text = "请选择物品"
	item_description_label.text = ""
	item_quantity_label.text = "数量：0"
	bind_button.disabled = true


func _on_bind_button_pressed() -> void:
	if selected_item_id.is_empty():
		return

	var item: ItemData = InventoryManager.get_item_data(selected_item_id)

	if item == null:
		_clear_item_details()
		return

	if not item.usable:
		item_description_label.text = "该物品暂不可使用，无法绑定快捷栏。"
		return

	bind_popup.position = Vector2i(get_global_mouse_position())
	bind_popup.popup()


func _on_bind_popup_id_pressed(id: int) -> void:
	if id == 4:
		# 清除所选物品在快捷栏中的所有绑定
		for i in range(QuickbarManager.SLOT_COUNT):
			if QuickbarManager.get_bound_item_id(i) == selected_item_id:
				QuickbarManager.clear_slot(i)

		return

	if id < 0 or id >= QuickbarManager.SLOT_COUNT:
		return

	if selected_item_id.is_empty():
		return

	var success: bool = QuickbarManager.bind_item(id, selected_item_id)

	if success:
		item_description_label.text = "已绑定到快捷栏 " + str(id + 1)


func _on_quickbar_changed() -> void:
	# 快捷栏数据变化时，后续可在这里刷新快捷栏显示
	pass


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
