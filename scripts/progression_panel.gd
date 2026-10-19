extends CanvasLayer

const ROWS := [
	["vitality", "生命", false], ["attack", "攻击", false], ["defense", "防御", false], ["agility", "敏捷", false],
	["slow", "技巧·减速", true], ["connection", "技巧·连接", true], ["bind", "技巧·束缚", true], ["loop", "技巧·绕圈", true],
]

var panel: PanelContainer
var hud_label: Label
var summary: Label
var rows_box: VBoxContainer
var rows: Dictionary = {}
var status_label: Label


func _ready() -> void:
	layer = 20
	_build_ui()
	panel.visible = false
	hud_label = Label.new()
	hud_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hud_label.offset_left = -150.0
	hud_label.offset_top = 8.0
	hud_label.offset_right = 150.0
	hud_label.offset_bottom = 34.0
	hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.68))
	add_child(hud_label)
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


func _build_ui() -> void:
	panel = PanelContainer.new()
	panel.name = "ProgressionPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -245.0
	panel.offset_top = -270.0
	panel.offset_right = 245.0
	panel.offset_bottom = 270.0
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.065, 0.08, 0.14, 0.97)))
	add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	margin.add_child(column)
	var title := Label.new()
	title.text = "猫咪成长 · P 打开/关闭"
	title.add_theme_font_size_override("font_size", 22)
	column.add_child(title)
	summary = Label.new()
	column.add_child(summary)
	rows_box = VBoxContainer.new()
	rows_box.add_theme_constant_override("separation", 3)
	column.add_child(rows_box)
	for row_data in ROWS:
		_add_row(str(row_data[0]), str(row_data[1]), bool(row_data[2]))
	status_label = Label.new()
	status_label.text = ""
	column.add_child(status_label)
	var actions := HBoxContainer.new()
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
	close.text = "关闭"
	close.pressed.connect(func(): panel.visible = false)
	actions.add_child(close)


func _add_row(key: String, title: String, is_skill: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	rows_box.add_child(row)
	var label := Label.new()
	label.custom_minimum_size.x = 136.0
	label.text = title
	row.add_child(label)
	var current := Label.new()
	current.custom_minimum_size.x = 64.0
	current.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(current)
	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size.x = 42.0
	plus.pressed.connect(func(): ProgressionManager.allocate_point(key, is_skill))
	row.add_child(plus)
	var minus := Button.new()
	minus.text = "−"
	minus.custom_minimum_size.x = 42.0
	minus.pressed.connect(func(): ProgressionManager.remove_pending_point(key, is_skill))
	row.add_child(minus)
	rows[key] = {"current": current, "plus": plus, "minus": minus, "skill": is_skill}


func _refresh() -> void:
	if is_instance_valid(hud_label):
		hud_label.text = "Lv.%d  ·  XP %d/%d  ·  属性点 %d  ·  P 成长 / F3 调试" % [ProgressionManager.level, ProgressionManager.experience, ProgressionManager.required_experience(), ProgressionManager.available_points]
	if not is_instance_valid(summary):
		return
	var pending: Dictionary = ProgressionManager.pending_allocation
	var pending_attributes: Dictionary = pending.get("attributes", ProgressionManager.attributes)
	var pending_skills: Dictionary = pending.get("skills", ProgressionManager.skill_points)
	var spent: int = ProgressionManager._pending_point_count()
	summary.text = "等级 %d  ·  经验 %d/%d  ·  可用点数 %d  ·  待提交 %d\n属性：生命、攻击、防御、敏捷；技巧（第五属性）分为四个独立分支。" % [ProgressionManager.level, ProgressionManager.experience, ProgressionManager.required_experience(), ProgressionManager.available_points, spent]
	for key in rows:
		var entry: Dictionary = rows[key]
		var values: Dictionary = pending_skills if entry["skill"] else pending_attributes
		var committed: Dictionary = ProgressionManager.skill_points if entry["skill"] else ProgressionManager.attributes
		entry["current"].text = "%d 点" % int(values.get(key, 0))
		entry["minus"].disabled = int(values.get(key, 0)) <= int(committed.get(key, 0))
		entry["plus"].disabled = spent >= ProgressionManager.available_points or (entry["skill"] and ProgressionManager._skill_at_cap(key, int(values.get(key, 0))))


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


func _panel_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.4, 0.56, 0.78, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style
