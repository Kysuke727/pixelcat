extends CanvasLayer

const SLOT_SCENE: PackedScene = preload("res://scenes/ui/inventory_slot.tscn")
const COLUMN_COUNT := 6

@onready var root_control: Control = $Root
@onready var slot_grid: GridContainer = $Root/Center/Panel/Margin/VBox/Grid
@onready var detail_name: Label = $Root/Center/Panel/Margin/VBox/Detail/DetailName
@onready var detail_type: Label = $Root/Center/Panel/Margin/VBox/Detail/DetailType
@onready var detail_quantity: Label = $Root/Center/Panel/Margin/VBox/Detail/DetailQuantity
@onready var detail_description: Label = $Root/Center/Panel/Margin/VBox/Detail/DetailDescription
@onready var empty_hint: Label = $Root/Center/Panel/Margin/VBox/Detail/EmptyHint
@onready var bind_button: Button = $Root/Center/Panel/Margin/VBox/Detail/BindQuickbarButton

var is_open: bool = false
var inventory_slots: Array[Node] = []
var selected_slot_index: int = -1
var selected_item_id: String = ""
var bind_popup: PopupMenu


func _ready() -> void:
	add_to_group("inventory_ui")
	root_control.visible = false
	slot_grid.columns = COLUMN_COUNT
	_create_slots()
	_create_bind_popup()
	bind_button.pressed.connect(_on_bind_button_pressed)
	if not InventoryManager.inventory_changed.is_connected(refresh_inventory):
		InventoryManager.inventory_changed.connect(refresh_inventory)
	if not QuickbarManager.quickbar_changed.is_connected(_on_quickbar_changed):
		QuickbarManager.quickbar_changed.connect(_on_quickbar_changed)
	InventoryManager.set_ui_open(false)
	refresh_inventory()


func _exit_tree() -> void:
	if is_open:
		is_open = false
		InventoryManager.set_ui_open(false)


func _create_slots() -> void:
	for child in slot_grid.get_children():
		slot_grid.remove_child(child)
		child.queue_free()
	inventory_slots.clear()
	for index in range(InventoryManager.SLOT_COUNT):
		var slot: Node = SLOT_SCENE.instantiate()
		slot_grid.add_child(slot)
		slot.set_slot_index(index)
		slot.slot_clicked.connect(_on_slot_clicked)
		inventory_slots.append(slot)


func _create_bind_popup() -> void:
	bind_popup = PopupMenu.new()
	bind_popup.name = "BindQuickbarPopup"
	for index in range(QuickbarManager.SLOT_COUNT):
		bind_popup.add_item("绑定到快捷栏 %d" % (index + 1), index)
	bind_popup.add_separator()
	bind_popup.add_item("清除所选物品的快捷栏绑定", 4)
	add_child(bind_popup)
	bind_popup.id_pressed.connect(_on_bind_popup_id_pressed)


func refresh_inventory() -> void:
	if not is_node_ready():
		return
	for index in range(inventory_slots.size()):
		var slot: Node = inventory_slots[index]
		var data: Dictionary = InventoryManager.get_slot(index)
		var item_id := str(data.get("item_id", ""))
		var quantity := int(data.get("quantity", 0))
		var item = InventoryManager.get_item_data(item_id)
		if item == null or quantity <= 0:
			slot.clear_slot()
		else:
			slot.set_item(item, quantity)
	if selected_slot_index >= 0:
		var selected_data: Dictionary = InventoryManager.get_slot(selected_slot_index)
		if selected_data.is_empty() or int(selected_data.get("quantity", 0)) <= 0:
			select_slot(-1)
		else:
			_update_detail(selected_slot_index)
	var inventory_empty := InventoryManager.get_empty_slot_count() == InventoryManager.SLOT_COUNT
	empty_hint.visible = inventory_empty and selected_slot_index < 0
	if inventory_empty and selected_slot_index < 0:
		_show_empty_detail()


func toggle_inventory() -> void:
	if is_open:
		close_inventory()
	else:
		open_inventory()


func open_inventory() -> void:
	if is_open:
		return
	is_open = true
	root_control.visible = true
	InventoryManager.set_ui_open(true)
	refresh_inventory()
	if selected_slot_index < 0:
		_show_empty_detail()


func close_inventory() -> void:
	if not is_open:
		return
	is_open = false
	root_control.visible = false
	InventoryManager.set_ui_open(false)
	select_slot(-1)


func select_slot(index: int) -> void:
	if index < 0 or index >= InventoryManager.SLOT_COUNT:
		selected_slot_index = -1
		selected_item_id = ""
		for slot in inventory_slots:
			slot.set_selected(false)
		_show_empty_detail()
		return
	selected_slot_index = index
	for slot_index in range(inventory_slots.size()):
		inventory_slots[slot_index].set_selected(slot_index == index)
	_update_detail(index)


func _on_slot_clicked(index: int) -> void:
	select_slot(index)


func _update_detail(index: int) -> void:
	var data: Dictionary = InventoryManager.get_slot(index)
	var item = InventoryManager.get_item_data(str(data.get("item_id", "")))
	if item == null:
		_show_empty_detail()
		return
	selected_item_id = item.item_id
	detail_name.text = item.display_name
	detail_type.text = item.category_name()
	detail_quantity.text = "数量：%d / %d" % [int(data.get("quantity", 0)), int(item.max_stack)]
	detail_description.text = item.description
	empty_hint.visible = false
	var can_bind := bool(item.usable)
	bind_button.disabled = not can_bind
	bind_button.text = "设置快捷栏" if can_bind else "该物品不可绑定"


func _show_empty_detail() -> void:
	var inventory_empty := InventoryManager.get_empty_slot_count() == InventoryManager.SLOT_COUNT
	detail_name.text = "我的背包 ♡"
	detail_type.text = ""
	detail_quantity.text = ""
	if inventory_empty:
		detail_description.text = "背包是空的。以后获得的材料与道具会出现在这里。"
	else:
		detail_description.text = "选择一个物品查看描述。"
	empty_hint.text = "I 键打开 / 关闭背包"
	empty_hint.visible = true
	bind_button.disabled = true
	bind_button.text = "设置快捷栏"


func _on_bind_button_pressed() -> void:
	if selected_item_id.is_empty():
		return
	var item = InventoryManager.get_item_data(selected_item_id)
	if item == null:
		_show_empty_detail()
		return
	if not bool(item.usable):
		detail_description.text = "该物品暂不可使用，无法绑定快捷栏。"
		return
	bind_popup.position = Vector2i(get_viewport().get_mouse_position())
	bind_popup.popup()


func _on_bind_popup_id_pressed(id: int) -> void:
	if id == 4:
		for index in range(QuickbarManager.SLOT_COUNT):
			if QuickbarManager.get_bound_item_id(index) == selected_item_id:
				QuickbarManager.clear_slot(index)
		detail_description.text = "已清除该物品的快捷栏绑定。"
		return
	if id < 0 or id >= QuickbarManager.SLOT_COUNT or selected_item_id.is_empty():
		return
	if QuickbarManager.bind_item(id, selected_item_id):
		detail_description.text = "已绑定到快捷栏 %d。" % (id + 1)
	else:
		detail_description.text = "绑定失败：该物品没有明确的可使用规则。"


func _on_quickbar_changed() -> void:
	if selected_slot_index >= 0:
		_update_detail(selected_slot_index)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory") and not event.is_echo():
		toggle_inventory()
		get_viewport().set_input_as_handled()
		return
	if is_open and event.is_action_pressed("ui_cancel"):
		close_inventory()
		get_viewport().set_input_as_handled()
