extends CanvasLayer

## Shared UI for portable and workbench crafting. Only CraftingManager mutates inventory.
var root_control: Control
var recipe_list: VBoxContainer
var detail_title: Label
var detail_description: Label
var detail_materials: VBoxContainer
var detail_result: Label
var craft_button: Button
var status_label: Label
var _open: bool = false
var _at_workbench: bool = false
var _opened_from_inventory: bool = false
var _selected_recipe: String = ""


func _ready() -> void:
	add_to_group("crafting_ui")
	_build_ui()
	root_control.visible = false
	InventoryManager.inventory_changed.connect(_refresh)


func _exit_tree() -> void:
	if _open:
		InventoryManager.set_ui_open(false)


func is_open() -> bool:
	return _open


func open_crafting(at_workbench: bool = false, from_inventory: bool = false) -> void:
	if _open:
		return
	_at_workbench = at_workbench
	_opened_from_inventory = from_inventory
	_open = true
	InventoryManager.set_ui_open(true)
	root_control.visible = true
	status_label.text = ""
	var recipes := CraftingManager.get_recipes()
	if _selected_recipe.is_empty() and not recipes.is_empty():
		_selected_recipe = str(recipes[0].recipe_id)
	_refresh()


func close_crafting(back_to_inventory: bool = false) -> void:
	if not _open:
		return
	_open = false
	root_control.visible = false
	InventoryManager.set_ui_open(false)
	if back_to_inventory and _opened_from_inventory:
		var inventory_ui = get_tree().get_first_node_in_group("inventory_ui")
		if inventory_ui != null:
			inventory_ui.open_inventory()


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if (event.is_action_pressed("ui_cancel") or event.is_action_pressed("toggle_inventory")) and not event.is_echo():
		close_crafting()
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	if not _open or not is_node_ready():
		return
	for child in recipe_list.get_children():
		child.queue_free()
	for recipe in CraftingManager.get_recipes():
		var button := Button.new()
		button.custom_minimum_size = Vector2(205, 44)
		button.text = ("🔒 " if recipe.requires_workbench and not _at_workbench else "") + recipe.display_name
		button.tooltip_text = "需要工作台" if recipe.requires_workbench and not _at_workbench else "选择配方"
		button.pressed.connect(_select_recipe.bind(recipe.recipe_id))
		recipe_list.add_child(button)
	for child in detail_materials.get_children():
		child.queue_free()
	var recipe = CraftingManager.get_recipe(_selected_recipe)
	if recipe == null:
		detail_title.text = "没有可制作配方"
		detail_description.text = ""
		detail_result.text = ""
		craft_button.disabled = true
		return
	detail_title.text = recipe.display_name
	detail_description.text = recipe.description
	for id in recipe.ingredients.keys():
		var owned: int = InventoryManager.get_item_count(id)
		var required: int = int(recipe.ingredients[id])
		var item = InventoryManager.get_item_data(id)
		var label := Label.new()
		label.text = "%s：%d / %d" % [item.display_name if item else id, owned, required]
		label.add_theme_color_override("font_color", Color(0.24, 0.58, 0.4) if owned >= required else Color(0.82, 0.32, 0.36))
		detail_materials.add_child(label)
	var output_item = InventoryManager.get_item_data(recipe.result_item_id)
	detail_result.text = "获得：%s ×%d" % [output_item.display_name if output_item else recipe.result_item_id, recipe.result_quantity]
	var check: Dictionary = CraftingManager.check_craft(recipe.recipe_id, _at_workbench)
	craft_button.disabled = not bool(check.get("success", false))
	var reason: String = str(check.get("reason", ""))
	if reason == "workbench_required":
		craft_button.text = "需要工作台"
	elif reason == "insufficient_materials":
		craft_button.text = "材料不足"
	elif reason == "inventory_full":
		craft_button.text = "背包空间不足"
	else:
		craft_button.text = "制作 ×1"


func _select_recipe(recipe_id: String) -> void:
	_selected_recipe = recipe_id
	status_label.text = ""
	_refresh()


func _craft_selected() -> void:
	var result: Dictionary = CraftingManager.craft(_selected_recipe, _at_workbench)
	if bool(result.get("success", false)):
		status_label.text = "制作成功！物品已放入背包 ♡"
	else:
		status_label.text = "未能制作：" + str(result.get("reason", "unknown"))
	_refresh()


func _build_ui() -> void:
	root_control = Control.new()
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root_control)
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.12, 0.08, 0.13, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root_control.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	root_control.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(645, 440)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#fff4ee")
	style.border_color = Color("#efb7c9")
	style.set_border_width_all(4)
	style.set_corner_radius_all(16)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)
	var vertical := VBoxContainer.new()
	vertical.add_theme_constant_override("separation", 12)
	margin.add_child(vertical)
	var title := Label.new()
	title.text = "♡ 小猫手工屋 ♡"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 27)
	title.add_theme_color_override("font_color", Color("#a65d77"))
	vertical.add_child(title)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 22)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vertical.add_child(columns)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(205, 0)
	columns.add_child(left)
	var recipes_heading := Label.new()
	recipes_heading.text = "配方列表"
	left.add_child(recipes_heading)
	recipe_list = VBoxContainer.new()
	left.add_child(recipe_list)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	columns.add_child(right)
	detail_title = Label.new()
	detail_title.add_theme_font_size_override("font_size", 22)
	right.add_child(detail_title)
	detail_description = Label.new()
	detail_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(detail_description)
	detail_materials = VBoxContainer.new()
	right.add_child(detail_materials)
	detail_result = Label.new()
	right.add_child(detail_result)
	craft_button = Button.new()
	craft_button.custom_minimum_size = Vector2(0, 42)
	craft_button.pressed.connect(_craft_selected)
	right.add_child(craft_button)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(status_label)
	var close_button := Button.new()
	close_button.text = "返回背包 / 关闭"
	close_button.pressed.connect(func(): close_crafting(true))
	vertical.add_child(close_button)
