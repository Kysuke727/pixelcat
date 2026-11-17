extends CanvasLayer

## Home storage screen: backpack on the left, chest on the right. Click an item, then move 1 or
## all of it to the other side. The chest is safe when the cat falls; the backpack is not.
## All player-facing text is Simplified Chinese.

const SLOT_SCENE: PackedScene = preload("res://scenes/ui/inventory_slot.tscn")
const THEME: Theme = preload("res://resources/ui/pixelcat_theme.tres")

var is_open: bool = false
var root_control: Control
var pack_grid: GridContainer
var chest_grid: GridContainer
var pack_slots: Array[Node] = []
var chest_slots: Array[Node] = []
var info_label: Label
var move_one_button: Button
var move_all_button: Button
var selected_from_chest: bool = false
var selected_index: int = -1
var selected_item_id: String = ""


func _ready() -> void:
	add_to_group("storage_ui")
	layer = 50
	_build()
	root_control.visible = false
	InventoryManager.inventory_changed.connect(_refresh)
	_refresh()


func _exit_tree() -> void:
	if is_open:
		is_open = false
		InventoryManager.set_ui_open(false)


func _build() -> void:
	root_control = Control.new()
	root_control.theme = THEME
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root_control)
	var dim := ColorRect.new()
	dim.color = Color(0.12, 0.07, 0.12, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = "♡ 储物箱 ♡"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	column.add_child(body)
	pack_grid = _make_side(body, "背包（倒下会丢一半）", InventoryManager.SLOT_COUNT, 6, pack_slots, false)
	chest_grid = _make_side(body, "储物箱（倒下不会丢）", InventoryManager.STORAGE_SLOT_COUNT, 8, chest_slots, true)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 10)
	column.add_child(buttons)
	move_one_button = Button.new()
	move_one_button.text = "移动 1 个"
	move_one_button.disabled = true
	move_one_button.pressed.connect(func(): _move(1))
	buttons.add_child(move_one_button)
	move_all_button = Button.new()
	move_all_button.text = "全部移动"
	move_all_button.disabled = true
	move_all_button.pressed.connect(func(): _move(999))
	buttons.add_child(move_all_button)
	info_label = Label.new()
	info_label.theme_type_variation = &"SoftLabel"
	info_label.text = "点一个物品，再点“移动”。Esc 关闭。"
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(info_label)


func _make_side(parent: Control, heading: String, count: int, columns: int, slot_list: Array[Node], from_chest: bool) -> GridContainer:
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 4)
	parent.add_child(side)
	var label := Label.new()
	label.theme_type_variation = &"HeadingLabel"
	label.text = heading
	side.add_child(label)
	var inset := PanelContainer.new()
	inset.theme_type_variation = &"InsetPanel"
	inset.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	side.add_child(inset)
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	inset.add_child(grid)
	for index in range(count):
		var slot: Node = SLOT_SCENE.instantiate()
		grid.add_child(slot)
		slot.set_slot_index(index)
		slot.slot_clicked.connect(func(i: int): _on_slot_clicked(i, from_chest))
		slot_list.append(slot)
	return grid


func _slot_data(index: int, from_chest: bool) -> Dictionary:
	return InventoryManager.get_storage_slot(index) if from_chest else InventoryManager.get_slot(index)


func _refresh() -> void:
	if not is_node_ready():
		return
	for from_chest in [false, true]:
		var list: Array[Node] = chest_slots if from_chest else pack_slots
		for index in range(list.size()):
			var data: Dictionary = _slot_data(index, from_chest)
			var item = InventoryManager.get_item_data(str(data.get("item_id", "")))
			var quantity := int(data.get("quantity", 0))
			if item == null or quantity <= 0:
				list[index].clear_slot()
			else:
				list[index].set_item(item, quantity)
			list[index].set_selected(from_chest == selected_from_chest and index == selected_index)
	if selected_index >= 0 and int(_slot_data(selected_index, selected_from_chest).get("quantity", 0)) <= 0:
		_select(-1, false)


func _on_slot_clicked(index: int, from_chest: bool) -> void:
	if int(_slot_data(index, from_chest).get("quantity", 0)) <= 0:
		_select(-1, false)
		return
	_select(index, from_chest)


func _select(index: int, from_chest: bool) -> void:
	selected_index = index
	selected_from_chest = from_chest
	selected_item_id = ""
	for slot in pack_slots + chest_slots:
		slot.set_selected(false)
	var have_item := index >= 0
	move_one_button.disabled = not have_item
	move_all_button.disabled = not have_item
	if not have_item:
		return
	var list: Array[Node] = chest_slots if from_chest else pack_slots
	list[index].set_selected(true)
	var data: Dictionary = _slot_data(index, from_chest)
	selected_item_id = str(data["item_id"])
	var item = InventoryManager.get_item_data(selected_item_id)
	var name_text: String = item.display_name if item != null else selected_item_id
	info_label.text = "%s ×%d" % [name_text, int(data["quantity"])]
	move_one_button.text = "取回背包 1 个" if from_chest else "存入箱子 1 个"
	move_all_button.text = "全部取回" if from_chest else "全部存入"


func _move(amount: int) -> void:
	if selected_item_id.is_empty():
		return
	var item_id := selected_item_id
	var from_chest := selected_from_chest
	var total_before := InventoryManager.get_storage_item_count(item_id) if from_chest else InventoryManager.get_item_count(item_id)
	var result: Dictionary = InventoryManager.transfer(item_id, amount, not from_chest)
	var item = InventoryManager.get_item_data(item_id)
	var name_text: String = item.display_name if item != null else item_id
	if int(result["moved"]) <= 0:
		info_label.text = ("背包已经满了，放不下" if from_chest else "储物箱已经满了，放不下") + name_text
		return
	if str(result["reason"]) == "full":
		info_label.text = "只移动了 %d 个%s，%s放不下了" % [int(result["moved"]), name_text, "背包" if from_chest else "储物箱"]
	else:
		info_label.text = "%s %d 个%s" % ["取回" if from_chest else "存入", int(result["moved"]), name_text]
	var left := InventoryManager.get_storage_item_count(item_id) if from_chest else InventoryManager.get_item_count(item_id)
	if left <= 0 or total_before <= int(result["moved"]):
		_select(-1, false)
	_refresh()


func is_storage_open() -> bool:
	return is_open


func open_storage() -> void:
	if is_open:
		return
	is_open = true
	root_control.visible = true
	InventoryManager.set_ui_open(true)
	_select(-1, false)
	info_label.text = "点一个物品，再点“移动”。Esc 关闭。"
	_refresh()


func close_storage() -> void:
	if not is_open:
		return
	is_open = false
	root_control.visible = false
	InventoryManager.set_ui_open(false)
	_select(-1, false)


func _unhandled_input(event: InputEvent) -> void:
	if is_open and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("toggle_inventory")):
		close_storage()
		get_viewport().set_input_as_handled()
