extends CanvasLayer

## Growth panel (P): spend attribute points, and see which moves the cat has learned.
## Moves are learned by exploring (see MoveCatalog); more skills will be added to this
## panel step by step later.
##
## All player-facing text is Simplified Chinese.

const UI_THEME: Theme = preload("res://resources/ui/pixelcat_theme.tres")
const ROWS := [
	["vitality", "生命", "每点 +1 点最大生命"],
	["attack", "攻击", "每点 +5% 伤害"],
	["defense", "防御", "每点 +3% 护盾耐久"],
	["agility", "敏捷", "每点 +2% 移动速度"],
]

var panel: PanelContainer
var hud_panel: PanelContainer
var hud_label: Label
var summary: Label
var rows_box: VBoxContainer
var rows: Dictionary = {}
var moves_box: VBoxContainer
var status_label: Label


func _ready() -> void:
	layer = 20
	_build_hud_label()
	_build_ui()
	panel.visible = false
	ProgressionManager.progression_changed.connect(_refresh)
	ProgressionManager.level_changed.connect(_on_level_changed)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_P:
		panel.visible = not panel.visible
		if panel.visible:
			ProgressionManager.begin_allocation()
			_refresh()
		get_viewport().set_input_as_handled()


## The small "Lv / XP" strip at the top centre.
func _build_hud_label() -> void:
	hud_panel = PanelContainer.new()
	hud_panel.theme = UI_THEME
	hud_panel.theme_type_variation = &"HudPanel"
	hud_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hud_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud_panel.offset_top = 8.0
	add_child(hud_panel)
	hud_label = Label.new()
	hud_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_label.add_theme_font_size_override("font_size", 13)
	hud_panel.add_child(hud_label)


func _build_ui() -> void:
	var root := Control.new()
	root.theme = UI_THEME
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel = PanelContainer.new()
	panel.name = "ProgressionPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(panel)
	# Keep the panel visibility on the CanvasLayer's child so tests/callers can toggle it.
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var title := Label.new()
	title.text = "♡ 猫咪成长 ♡"
	title.theme_type_variation = &"TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	summary = Label.new()
	summary.theme_type_variation = &"SoftLabel"
	column.add_child(summary)

	var attributes_panel := PanelContainer.new()
	attributes_panel.theme_type_variation = &"InsetPanel"
	column.add_child(attributes_panel)
	rows_box = VBoxContainer.new()
	rows_box.add_theme_constant_override("separation", 4)
	attributes_panel.add_child(rows_box)
	for row_data in ROWS:
		_add_row(str(row_data[0]), str(row_data[1]), str(row_data[2]))

	status_label = Label.new()
	status_label.theme_type_variation = &"SoftLabel"
	column.add_child(status_label)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	column.add_child(actions)
	var commit := Button.new()
	commit.text = "提交加点"
	commit.pressed.connect(_commit)
	actions.add_child(commit)
	var cancel := Button.new()
	cancel.text = "撤销未提交"
	cancel.pressed.connect(_cancel)
	actions.add_child(cancel)
	var close := Button.new()
	close.text = "关闭 (P)"
	close.pressed.connect(func(): panel.visible = false)
	actions.add_child(close)

	var moves_heading := Label.new()
	moves_heading.text = "招式"
	moves_heading.theme_type_variation = &"HeadingLabel"
	column.add_child(moves_heading)
	var moves_panel := PanelContainer.new()
	moves_panel.theme_type_variation = &"InsetPanel"
	column.add_child(moves_panel)
	moves_box = VBoxContainer.new()
	moves_box.add_theme_constant_override("separation", 6)
	moves_panel.add_child(moves_box)
	var footer := Label.new()
	footer.text = "招式要靠探索地图学会，更多技能以后会加入。"
	footer.theme_type_variation = &"SoftLabel"
	column.add_child(footer)


func _add_row(key: String, title: String, effect: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	rows_box.add_child(row)
	var label := Label.new()
	label.custom_minimum_size.x = 56.0
	label.text = title
	row.add_child(label)
	var current := Label.new()
	current.custom_minimum_size.x = 52.0
	current.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(current)
	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(36.0, 28.0)
	plus.pressed.connect(func(): ProgressionManager.allocate_point(key))
	row.add_child(plus)
	var minus := Button.new()
	minus.text = "−"
	minus.custom_minimum_size = Vector2(36.0, 28.0)
	minus.pressed.connect(func(): ProgressionManager.remove_pending_point(key))
	row.add_child(minus)
	var note := Label.new()
	note.text = effect
	note.theme_type_variation = &"SoftLabel"
	row.add_child(note)
	rows[key] = {"current": current, "plus": plus, "minus": minus}


func _refresh() -> void:
	if is_instance_valid(hud_label):
		var text := "Lv.%d  ·  XP %d/%d" % [ProgressionManager.level, ProgressionManager.experience, ProgressionManager.required_experience()]
		if ProgressionManager.available_points > 0:
			text += "  ·  有 %d 个属性点，按 P 分配" % ProgressionManager.available_points
		hud_label.text = text
	if not is_instance_valid(summary):
		return
	var pending: Dictionary = ProgressionManager.pending_allocation
	var pending_attributes: Dictionary = pending.get("attributes", ProgressionManager.attributes)
	var spent: int = ProgressionManager._pending_point_count()
	summary.text = "等级 %d  ·  经验 %d/%d  ·  可用点数 %d  ·  待提交 %d" % [ProgressionManager.level, ProgressionManager.experience, ProgressionManager.required_experience(), ProgressionManager.available_points, spent]
	for key in rows:
		var entry: Dictionary = rows[key]
		entry["current"].text = "%d 点" % int(pending_attributes.get(key, 0))
		entry["minus"].disabled = int(pending_attributes.get(key, 0)) <= int(ProgressionManager.attributes.get(key, 0))
		entry["plus"].disabled = spent >= ProgressionManager.available_points
	_refresh_moves()


## Learned moves show their name, key and description; the rest stay a mystery so players
## are curious to go and find them.
func _refresh_moves() -> void:
	for child in moves_box.get_children():
		child.queue_free()
	for move_id in MoveCatalog.ids():
		var line := VBoxContainer.new()
		line.add_theme_constant_override("separation", 0)
		moves_box.add_child(line)
		var heading := Label.new()
		line.add_child(heading)
		if ProgressionManager.has_move(str(move_id)):
			heading.text = "✓ %s    [%s]" % [MoveCatalog.display_name(str(move_id)), MoveCatalog.input_text(str(move_id))]
			heading.theme_type_variation = &"GoodLabel"
			var hint := Label.new()
			hint.text = MoveCatalog.hint(str(move_id))
			hint.theme_type_variation = &"SoftLabel"
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hint.custom_minimum_size = Vector2(440.0, 0.0)
			line.add_child(hint)
		else:
			heading.text = "？？？    还没学会，去探索地图找找看"
			heading.theme_type_variation = &"SoftLabel"


func _commit() -> void:
	if ProgressionManager.commit_allocation():
		status_label.text = "加点已提交并保存。"
	else:
		status_label.text = "没有可提交的加点，或可用点数不足。"


func _cancel() -> void:
	ProgressionManager.cancel_allocation()
	status_label.text = "未提交的加点已撤销。"


func _on_level_changed(_new_level: int, _xp: int, _required: int) -> void:
	if is_instance_valid(status_label):
		status_label.text = "升级了！获得属性点，可按 P 分配。"
	_refresh()
