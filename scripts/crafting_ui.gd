extends CanvasLayer

## Shared UI for portable and workbench crafting. Only CraftingManager mutates inventory.

const UI_THEME: Theme = preload("res://resources/ui/pixelcat_theme.tres")

## --- Audio hooks -----------------------------------------------------------
## Leave empty for silence. Drop sound files under assets/audio/sfx/crafting/
## and assign them in the Inspector (select the CraftingUI node in
## scenes/ui/crafting_ui.tscn). No code changes needed; see
## docs/crafting-audio.md.
@export_group("Audio (assign in Inspector)")
@export var sound_open: AudioStream
@export var sound_close: AudioStream
@export var sound_select_recipe: AudioStream
@export var sound_quantity_change: AudioStream
@export var sound_craft_success: AudioStream
@export var sound_craft_fail: AudioStream
@export_range(-30.0, 6.0, 0.5) var sound_volume_db: float = 0.0

const STATE_CRAFTABLE := 0
const STATE_MISSING := 1
const STATE_LOCKED := 2

var root_control: Control
var panel: PanelContainer
var title_label: Label
var badge_panel: PanelContainer
var badge_label: Label
var recipe_list: VBoxContainer
var detail_title: Label
var detail_description: Label
var detail_icon: TextureRect
var detail_materials: VBoxContainer
var detail_result: Label
var quantity_row: HBoxContainer
var minus_button: Button
var plus_button: Button
var max_button: Button
var quantity_label: Label
var craft_button: Button
var status_label: Label
var _open: bool = false
var _at_workbench: bool = false
var _opened_from_inventory: bool = false
var _selected_recipe: String = ""
var _times: int = 1


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
	_times = 1
	var recipes := _sorted_recipes()
	if (_selected_recipe.is_empty() or CraftingManager.get_recipe(_selected_recipe) == null) and not recipes.is_empty():
		_selected_recipe = str(recipes[0].recipe_id)
	_play(sound_open)
	_refresh()


func close_crafting(back_to_inventory: bool = false) -> void:
	if not _open:
		return
	_open = false
	root_control.visible = false
	InventoryManager.set_ui_open(false)
	_play(sound_close)
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


# ---------------------------------------------------------------------------
# Recipe state / ordering
# ---------------------------------------------------------------------------

func _recipe_state(recipe) -> int:
	var check: Dictionary = CraftingManager.check_craft(recipe.recipe_id, _at_workbench, 1)
	if bool(check.get("success", false)):
		return STATE_CRAFTABLE
	if str(check.get("reason", "")) == "workbench_required":
		return STATE_LOCKED
	return STATE_MISSING


## Craftable first, then "not enough materials", then locked; declaration order
## is kept inside each group so the list never reshuffles randomly.
func _sorted_recipes() -> Array:
	var entries: Array = []
	var index := 0
	for recipe in CraftingManager.get_recipes():
		entries.append({"recipe": recipe, "state": _recipe_state(recipe), "index": index})
		index += 1
	entries.sort_custom(func(a, b):
		if a["state"] != b["state"]:
			return a["state"] < b["state"]
		return a["index"] < b["index"])
	var result: Array = []
	for entry in entries:
		result.append(entry["recipe"])
	return result


# ---------------------------------------------------------------------------
# Refresh
# ---------------------------------------------------------------------------

func _refresh() -> void:
	if not _open or not is_node_ready():
		return
	_refresh_mode()
	_refresh_recipe_list()
	for child in detail_materials.get_children():
		child.queue_free()
	var recipe = CraftingManager.get_recipe(_selected_recipe)
	if recipe == null:
		detail_title.text = "没有可制作配方"
		detail_description.text = ""
		detail_result.text = ""
		detail_icon.texture = null
		quantity_row.visible = false
		craft_button.disabled = true
		return
	var max_craftable: int = CraftingManager.get_max_craftable(_selected_recipe, _at_workbench)
	_times = clampi(_times, 1, maxi(max_craftable, 1))
	detail_title.text = recipe.display_name
	detail_description.text = recipe.description
	var output_item = InventoryManager.get_item_data(recipe.result_item_id)
	detail_icon.texture = output_item.icon if output_item else null
	for id in recipe.ingredients.keys():
		var owned: int = InventoryManager.get_item_count(id)
		var required: int = int(recipe.ingredients[id]) * _times
		var item = InventoryManager.get_item_data(id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(28, 28)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.texture = item.icon if item else null
		row.add_child(icon)
		var name_label := Label.new()
		name_label.text = item.display_name if item else str(id)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var count_label := Label.new()
		count_label.text = "%d / %d" % [owned, required]
		count_label.theme_type_variation = &"GoodLabel" if owned >= required else &"BadLabel"
		row.add_child(count_label)
		detail_materials.add_child(row)
	detail_result.text = "获得：%s ×%d" % [output_item.display_name if output_item else recipe.result_item_id, recipe.result_quantity * _times]

	quantity_row.visible = true
	quantity_label.text = str(_times)
	minus_button.disabled = _times <= 1
	plus_button.disabled = _times >= max_craftable
	max_button.disabled = _times >= max_craftable

	var check: Dictionary = CraftingManager.check_craft(recipe.recipe_id, _at_workbench, _times)
	craft_button.disabled = not bool(check.get("success", false))
	var reason: String = str(check.get("reason", ""))
	if reason == "workbench_required":
		craft_button.text = "需要工作台"
		if status_label.text.is_empty():
			status_label.text = "这个配方要在家里的工作台才能制作。"
	elif reason == "insufficient_materials":
		craft_button.text = "材料不足"
	elif reason == "inventory_full":
		craft_button.text = "背包空间不足"
	else:
		craft_button.text = "制作 ×%d" % _times


func _refresh_mode() -> void:
	if _at_workbench:
		title_label.text = "♡ 小猫手工屋 ♡"
		panel.theme_type_variation = &"WorkbenchPanel"
		badge_panel.theme_type_variation = &"BadgeWorkbench"
		badge_label.text = "工作台"
	else:
		title_label.text = "♡ 随身制作 ♡"
		panel.theme_type_variation = &""
		badge_panel.theme_type_variation = &"BadgePortable"
		badge_label.text = "随身"


func _refresh_recipe_list() -> void:
	for child in recipe_list.get_children():
		child.queue_free()
	for recipe in _sorted_recipes():
		var state := _recipe_state(recipe)
		var result_item = InventoryManager.get_item_data(recipe.result_item_id)
		var button := Button.new()
		button.custom_minimum_size = Vector2(250, 46)
		button.text = recipe.display_name
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.theme_type_variation = &"RecipeButton"
		button.toggle_mode = true
		button.button_pressed = str(recipe.recipe_id) == _selected_recipe
		button.tooltip_text = "需要工作台" if state == STATE_LOCKED else "选择配方"
		if result_item != null and result_item.icon != null:
			button.icon = result_item.icon
			button.expand_icon = true
			button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var tag := Label.new()
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
		tag.offset_left = -90.0
		tag.offset_right = -10.0
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		match state:
			STATE_CRAFTABLE:
				tag.text = "可制作"
				tag.theme_type_variation = &"GoodLabel"
			STATE_LOCKED:
				tag.text = "需工作台"
				tag.theme_type_variation = &"SoftLabel"
			_:
				tag.text = "材料不足"
				tag.theme_type_variation = &"SoftLabel"
		button.add_child(tag)
		button.pressed.connect(_select_recipe.bind(recipe.recipe_id))
		recipe_list.add_child(button)


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

func _select_recipe(recipe_id: String) -> void:
	var changed := recipe_id != _selected_recipe
	_selected_recipe = recipe_id
	_times = 1
	status_label.text = ""
	if changed:
		_play(sound_select_recipe)
	_refresh()


func _change_quantity(delta: int) -> void:
	var max_craftable: int = CraftingManager.get_max_craftable(_selected_recipe, _at_workbench)
	var next := clampi(_times + delta, 1, maxi(max_craftable, 1))
	if next == _times:
		return
	_times = next
	_play(sound_quantity_change)
	_refresh()


func _set_max_quantity() -> void:
	var max_craftable: int = CraftingManager.get_max_craftable(_selected_recipe, _at_workbench)
	if max_craftable < 1 or _times == max_craftable:
		return
	_times = max_craftable
	_play(sound_quantity_change)
	_refresh()


func _craft_selected() -> void:
	var recipe = CraftingManager.get_recipe(_selected_recipe)
	var times := _times
	var result: Dictionary = CraftingManager.craft(_selected_recipe, _at_workbench, times)
	if bool(result.get("success", false)):
		var gained: int = int(result.get("quantity", 0))
		var item = InventoryManager.get_item_data(str(result.get("result_item_id", "")))
		var item_name: String = item.display_name if item else ""
		status_label.text = "制作成功！%s ×%d 已放入背包 ♡" % [item_name, gained]
		_play(sound_craft_success)
		_play_success_feedback("+%d %s ♡" % [gained, item_name])
	else:
		status_label.text = "未能制作：" + _reason_text(str(result.get("reason", "unknown")))
		_play(sound_craft_fail)
	_refresh()


func _reason_text(reason: String) -> String:
	match reason:
		"insufficient_materials":
			return "材料不够"
		"inventory_full":
			return "背包放不下了"
		"workbench_required":
			return "需要在工作台制作"
		_:
			return reason


# ---------------------------------------------------------------------------
# Feedback (visual) and audio hooks
# ---------------------------------------------------------------------------

## The result icon pops and a "+N item" toast floats up and fades.
func _play_success_feedback(text: String) -> void:
	detail_icon.pivot_offset = detail_icon.size / 2.0
	detail_icon.scale = Vector2.ONE
	var pop := create_tween()
	pop.tween_property(detail_icon, "scale", Vector2(1.4, 1.4), 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(detail_icon, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

	var toast := Label.new()
	toast.text = text
	toast.theme_type_variation = &"HeadingLabel"
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.z_index = 10
	root_control.add_child(toast)
	# Start just above the icon so the floating text never covers the recipe name.
	toast.global_position = detail_icon.global_position + Vector2(0.0, -14.0)
	var rise := create_tween().set_parallel(true)
	rise.tween_property(toast, "global_position:y", toast.global_position.y - 22.0, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	rise.tween_property(toast, "modulate:a", 0.0, 0.35).set_delay(0.5)
	rise.chain().tween_callback(toast.queue_free)


func _play(stream: AudioStream) -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = sound_volume_db
	player.bus = &"SFX"
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	root_control = Control.new()
	root_control.theme = UI_THEME
	add_child(root_control)
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.12, 0.07, 0.12, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root_control.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	root_control.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel = PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(margin)
	var vertical := VBoxContainer.new()
	vertical.add_theme_constant_override("separation", 8)
	margin.add_child(vertical)

	# Title row: [equal spacer][centered title][mode badge]
	var title_row := HBoxContainer.new()
	vertical.add_child(title_row)
	var left_spacer := Control.new()
	left_spacer.custom_minimum_size = Vector2(74, 0)
	title_row.add_child(left_spacer)
	title_label = Label.new()
	title_label.theme_type_variation = &"TitleLabel"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title_label)
	badge_panel = PanelContainer.new()
	badge_panel.custom_minimum_size = Vector2(74, 0)
	badge_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(badge_panel)
	badge_label = Label.new()
	badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge_panel.add_child(badge_label)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 10)
	vertical.add_child(columns)

	# Left: recipe list
	var left_panel := PanelContainer.new()
	left_panel.theme_type_variation = &"InsetPanel"
	left_panel.custom_minimum_size = Vector2(278, 330)
	columns.add_child(left_panel)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left_panel.add_child(left)
	var recipes_heading := Label.new()
	recipes_heading.text = "配方列表"
	recipes_heading.theme_type_variation = &"HeadingLabel"
	left.add_child(recipes_heading)
	recipe_list = VBoxContainer.new()
	recipe_list.add_theme_constant_override("separation", 6)
	left.add_child(recipe_list)

	# Right: selected recipe
	var right_panel := PanelContainer.new()
	right_panel.theme_type_variation = &"InsetPanel"
	right_panel.custom_minimum_size = Vector2(360, 330)
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right_panel)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right_panel.add_child(right)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	right.add_child(header)
	detail_icon = TextureRect.new()
	detail_icon.custom_minimum_size = Vector2(48, 48)
	detail_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	detail_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	header.add_child(detail_icon)
	detail_title = Label.new()
	detail_title.theme_type_variation = &"HeadingLabel"
	detail_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(detail_title)
	detail_description = Label.new()
	detail_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_description.custom_minimum_size = Vector2(0, 44)
	right.add_child(detail_description)
	right.add_child(HSeparator.new())
	var materials_heading := Label.new()
	materials_heading.text = "所需材料"
	materials_heading.theme_type_variation = &"SoftLabel"
	right.add_child(materials_heading)
	detail_materials = VBoxContainer.new()
	detail_materials.add_theme_constant_override("separation", 4)
	right.add_child(detail_materials)
	detail_result = Label.new()
	right.add_child(detail_result)

	quantity_row = HBoxContainer.new()
	quantity_row.add_theme_constant_override("separation", 6)
	right.add_child(quantity_row)
	var quantity_heading := Label.new()
	quantity_heading.text = "数量"
	quantity_heading.theme_type_variation = &"SoftLabel"
	quantity_row.add_child(quantity_heading)
	minus_button = Button.new()
	minus_button.text = "−"
	minus_button.custom_minimum_size = Vector2(36, 32)
	minus_button.pressed.connect(_change_quantity.bind(-1))
	quantity_row.add_child(minus_button)
	quantity_label = Label.new()
	quantity_label.custom_minimum_size = Vector2(36, 0)
	quantity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quantity_label.theme_type_variation = &"HeadingLabel"
	quantity_row.add_child(quantity_label)
	plus_button = Button.new()
	plus_button.text = "+"
	plus_button.custom_minimum_size = Vector2(36, 32)
	plus_button.pressed.connect(_change_quantity.bind(1))
	quantity_row.add_child(plus_button)
	max_button = Button.new()
	max_button.text = "最大"
	max_button.custom_minimum_size = Vector2(56, 32)
	max_button.pressed.connect(_set_max_quantity)
	quantity_row.add_child(max_button)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)
	craft_button = Button.new()
	craft_button.custom_minimum_size = Vector2(0, 40)
	craft_button.pressed.connect(_craft_selected)
	right.add_child(craft_button)
	status_label = Label.new()
	status_label.theme_type_variation = &"SoftLabel"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(status_label)

	var close_button := Button.new()
	close_button.text = "返回背包 / 关闭"
	close_button.custom_minimum_size = Vector2(0, 36)
	close_button.pressed.connect(func(): close_crafting(true))
	vertical.add_child(close_button)
