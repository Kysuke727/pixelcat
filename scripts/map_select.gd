extends Node

## "去哪里探险？" screen. Only shown once the player has more than one map available;
## before that, going out just goes to the first map (see DayManager.switch_to_night).

const UI_THEME: Theme = preload("res://resources/ui/pixelcat_theme.tres")

var _layer: CanvasLayer
var _root: Control
var _list: VBoxContainer
var _open: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	InventoryManager.set_ui_open(true)  # freezes the cat while the screen is up
	_refresh()
	_root.visible = true


func close() -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	InventoryManager.set_ui_open(false)


func choose(map_id: String) -> void:
	if not _open or not MapCatalog.is_available(map_id, ProgressionManager.cleared_maps):
		return
	close()
	DayManager.switch_to_night(map_id)


func _unhandled_input(event: InputEvent) -> void:
	if _open and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("toggle_inventory")) and not event.is_echo():
		close()
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	for child in _list.get_children():
		child.queue_free()
	for map_id in MapCatalog.ids():
		var available: bool = MapCatalog.is_available(map_id, ProgressionManager.cleared_maps)
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 64)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.disabled = not available
		var title := MapCatalog.display_name(map_id)
		if ProgressionManager.is_map_cleared(map_id):
			title += "   ✓ 已通关"
		if available:
			button.text = "%s\n%s" % [title, MapCatalog.blurb(map_id)]
		else:
			button.text = "%s\n通关「%s」后开放" % [title, MapCatalog.display_name(MapCatalog.required_map(map_id))]
		button.pressed.connect(choose.bind(map_id))
		_list.add_child(button)


func _build() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 70
	add_child(_layer)
	_root = Control.new()
	_root.theme = UI_THEME
	_root.visible = false
	_layer.add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.12, 0.07, 0.12, 0.6)
	_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var title := Label.new()
	title.text = "♡ 今晚去哪里探险？ ♡"
	title.theme_type_variation = &"TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	column.add_child(_list)
	var cancel := Button.new()
	cancel.text = "先不出门"
	cancel.custom_minimum_size = Vector2(0, 36)
	cancel.pressed.connect(close)
	column.add_child(cancel)
