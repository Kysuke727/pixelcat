extends Node

## "学会了新招式" banner. Listens to ProgressionManager.move_unlocked and shows the move
## name and how to perform it for a few seconds at the top of the screen. Several moves
## learned at once are shown one after another.

const UI_THEME: Theme = preload("res://resources/ui/pixelcat_theme.tres")
const HOLD_SECONDS := 3.2

var _queue: Array[String] = []
var _showing: bool = false
var _root: Control
var _panel: PanelContainer
var _title: Label
var _hint: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	ProgressionManager.move_unlocked.connect(show_move)


func show_move(move_id: String) -> void:
	HitFeel.play_sfx("learn_move")
	_queue.append(move_id)
	if not _showing:
		_show_next()


func is_showing() -> bool:
	return _showing


func _show_next() -> void:
	if _queue.is_empty():
		_showing = false
		return
	_showing = true
	var move_id: String = _queue.pop_front()
	_title.text = "学会了新招式：%s" % MoveCatalog.display_name(move_id)
	_hint.text = "%s\n%s" % [MoveCatalog.input_text(move_id), MoveCatalog.hint(move_id)]
	_panel.modulate.a = 0.0
	_panel.position.y = -20.0
	_root.visible = true
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_panel, "modulate:a", 1.0, 0.25)
	tween.tween_property(_panel, "position:y", 0.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_interval(HOLD_SECONDS)
	tween.chain().tween_property(_panel, "modulate:a", 0.0, 0.5)
	tween.chain().tween_callback(_on_finished)


func _on_finished() -> void:
	_root.visible = false
	_show_next()


func _build() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 95
	add_child(layer)
	_root = Control.new()
	_root.theme = UI_THEME
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	layer.add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.anchor_right = 1.0
	center.offset_top = 70.0
	center.offset_bottom = 70.0
	_root.add_child(center)
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.custom_minimum_size = Vector2(460, 0)
	center.add_child(_panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	_panel.add_child(box)
	_title = Label.new()
	_title.theme_type_variation = &"HeadingLabel"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_hint = Label.new()
	_hint.theme_type_variation = &"SoftLabel"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_hint)
