extends CanvasLayer

## 设置界面（自动加载）。按 Esc 打开 / 关闭（主菜单的“设置”按钮也能打开）。
## 打开时游戏暂停。内容：声音（总音量 / 音乐 / 音效）、画面（窗口模式、分辨率、屏幕震动、
## 打击停顿）、技能键位（可以改键，冲突会自动互换）。
## 设置单独存在 user://settings.cfg，和游戏存档无关。

const UI_THEME: Theme = preload("res://resources/ui/pixelcat_theme.tres")

const RESOLUTIONS: Array[Vector2i] = [Vector2i(1152, 648), Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]

## 可以改键的技能键：[动作名, 显示名]
const SKILL_ACTIONS := [
	["melee_attack", "爪击"],
	["ranged_attack", "黏黏球"],
	["defend", "防御（按住）"],
	["shield_bash", "破盾弹反（防御时按）"],
	["dodge", "闪避"],
	["dash", "冲刺"],
]
## 这些动作的按键不能被技能占用。
const RESERVED_ACTIONS := ["move_left", "move_right", "move_up", "move_down", "interact", "toggle_inventory", "quickbar_1", "quickbar_2", "quickbar_3", "quickbar_4"]
const RESERVED_KEYS := [KEY_ESCAPE, KEY_P, KEY_F3]

signal closed

var config_path: String = "user://settings.cfg"
var values: Dictionary = {
	"master": 1.0,
	"music": 0.8,
	"sfx": 0.8,
	"fullscreen": false,
	"resolution": 0,
	"screen_shake": true,
	"hit_stop": true,
	"keys": {},
}
var default_keys: Dictionary = {}
var listening_action: String = ""

var _root: Control
var _open: bool = false
var _was_paused: bool = false
var _widgets: Dictionary = {}
var _key_buttons: Dictionary = {}
var _message: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 110
	_ensure_buses()
	for entry in SKILL_ACTIONS:
		default_keys[entry[0]] = get_key(entry[0])
	load_settings()
	apply_all()
	_build()
	get_tree().node_added.connect(_on_node_added)


func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	_was_paused = get_tree().paused
	get_tree().paused = true
	_refresh()
	_root.visible = true


func close() -> void:
	if not _open:
		return
	_stop_listening()
	_open = false
	_root.visible = false
	get_tree().paused = _was_paused
	save_settings()
	closed.emit()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if listening_action != "":
		get_viewport().set_input_as_handled()
		if code == KEY_ESCAPE:
			_stop_listening()
			_say("已取消改键")
		else:
			rebind(listening_action, code)
		return
	if code == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if _open:
			close()
		else:
			open()


# --- audio ---------------------------------------------------------------------------------
func _ensure_buses() -> void:
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, "Master")


## Every sound player that enters the game goes to the Music or the SFX bus by its name.
func _on_node_added(node: Node) -> void:
	if not (node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D):
		return
	var lowered := String(node.name).to_lower()
	node.bus = &"Music" if (lowered.contains("bgm") or lowered.contains("music")) else &"SFX"


func set_volume(bus_name: String, linear: float) -> void:
	var key := bus_name.to_lower() if bus_name != "Master" else "master"
	values[key] = clampf(linear, 0.0, 1.0)
	_apply_volume(bus_name, float(values[key]))


func _apply_volume(bus_name: String, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index == -1:
		return
	AudioServer.set_bus_mute(index, linear <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.001)))


# --- screen -------------------------------------------------------------------------------------
func apply_screen() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if bool(values["fullscreen"]):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var size: Vector2i = RESOLUTIONS[clampi(int(values["resolution"]), 0, RESOLUTIONS.size() - 1)]
	DisplayServer.window_set_size(size)
	var screen := DisplayServer.window_get_current_screen()
	var area := DisplayServer.screen_get_usable_rect(screen)
	DisplayServer.window_set_position(area.position + (area.size - size) / 2)


func apply_effects() -> void:
	HitFeel.screen_shake_enabled = bool(values["screen_shake"])
	HitFeel.hit_stop_enabled = bool(values["hit_stop"])


func apply_all() -> void:
	_apply_volume("Master", float(values["master"]))
	_apply_volume("Music", float(values["music"]))
	_apply_volume("SFX", float(values["sfx"]))
	apply_effects()
	for action in values["keys"]:
		if default_keys.has(action):
			set_key(action, int(values["keys"][action]))
	apply_screen()


# --- key bindings ---------------------------------------------------------------------------------
func get_key(action: String) -> int:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return event.physical_keycode if event.physical_keycode != 0 else event.keycode
	return 0


func set_key(action: String, code: int) -> void:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			InputMap.action_erase_event(action, event)
	var key := InputEventKey.new()
	key.physical_keycode = code as Key
	InputMap.action_add_event(action, key)


func key_name(code: int) -> String:
	if code == 0:
		return "未设置"
	var label := OS.get_keycode_string(code as Key)
	return label if label != "" else str(code)


## Bind `action` to the key `code`. Another skill using that key gets this action's old key
## (a swap); reserved keys (movement, E, I, 1-4, Esc, P, F3) are refused. Returns true on success.
func rebind(action: String, code: int) -> bool:
	var old := get_key(action)
	if RESERVED_KEYS.has(code):
		return _refuse("这个按键已被系统占用")
	for reserved in RESERVED_ACTIONS:
		if InputMap.has_action(reserved) and get_key(reserved) == code:
			return _refuse("这个按键已被移动 / 互动 / 背包 / 快捷栏占用")
	_stop_listening()
	for entry in SKILL_ACTIONS:
		var other: String = entry[0]
		if other != action and get_key(other) == code:
			set_key(other, old)
			values["keys"][other] = old
	set_key(action, code)
	values["keys"][action] = code
	save_settings()
	_refresh()
	_say("已改为 %s" % key_name(code))
	return true


func reset_keys() -> void:
	for entry in SKILL_ACTIONS:
		set_key(entry[0], int(default_keys[entry[0]]))
	values["keys"] = {}
	save_settings()
	_refresh()
	_say("已恢复默认键位")


func _refuse(text: String) -> bool:
	_say(text)
	return false


func _stop_listening() -> void:
	listening_action = ""
	_refresh_key_buttons()


func _say(text: String) -> void:
	if _message != null:
		_message.text = text


# --- saving -----------------------------------------------------------------------------------------
func save_settings() -> void:
	var config := ConfigFile.new()
	for key in values:
		config.set_value("settings", key, values[key])
	config.save(config_path)


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(config_path) != OK:
		return
	for key in values:
		if config.has_section_key("settings", key):
			var loaded = config.get_value("settings", key)
			if typeof(loaded) == typeof(values[key]):
				values[key] = loaded


# --- UI -------------------------------------------------------------------------------------------------
func _build() -> void:
	_root = Control.new()
	_root.theme = UI_THEME
	_root.visible = false
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := Label.new()
	title.text = "设置"
	title.theme_type_variation = &"HeadingLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(0, 330)
	var body := StyleBoxFlat.new()
	body.bg_color = Color(1.0, 0.95, 0.93)
	body.border_color = Color(0.83, 0.45, 0.6)
	body.set_border_width_all(2)
	body.set_corner_radius_all(6)
	body.set_content_margin_all(16)
	tabs.add_theme_stylebox_override("panel", body)
	tabs.add_theme_color_override("font_selected_color", Color(0.45, 0.17, 0.3))
	tabs.add_theme_color_override("font_unselected_color", Color(0.45, 0.17, 0.3))
	tabs.add_theme_color_override("font_hovered_color", Color(0.45, 0.17, 0.3))
	box.add_child(tabs)
	tabs.add_child(_build_sound_tab())
	tabs.add_child(_build_screen_tab())
	tabs.add_child(_build_keys_tab())
	_message = Label.new()
	_message.theme_type_variation = &"SoftLabel"
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_message)
	var close_button := Button.new()
	close_button.text = "关闭（Esc）"
	close_button.pressed.connect(close)
	box.add_child(close_button)


func _tab(tab_name: String) -> VBoxContainer:
	var tab := VBoxContainer.new()
	tab.name = tab_name
	tab.add_theme_constant_override("separation", 12)
	return tab


func _build_sound_tab() -> Control:
	var tab := _tab("声音")
	for entry in [["master", "总音量", "Master"], ["music", "音乐", "Music"], ["sfx", "音效", "SFX"]]:
		var row := HBoxContainer.new()
		tab.add_child(row)
		var label := Label.new()
		label.text = entry[1]
		label.custom_minimum_size = Vector2(90, 0)
		row.add_child(label)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.custom_minimum_size = Vector2(260, 24)
		row.add_child(slider)
		var percent := Label.new()
		percent.custom_minimum_size = Vector2(54, 0)
		row.add_child(percent)
		var bus_name: String = entry[2]
		var key: String = entry[0]
		slider.value_changed.connect(func(value: float) -> void:
			set_volume(bus_name, value)
			percent.text = "%d%%" % roundi(value * 100.0)
		)
		_widgets[key] = [slider, percent]
	return tab


func _build_screen_tab() -> Control:
	var tab := _tab("画面")
	var mode_row := HBoxContainer.new()
	tab.add_child(mode_row)
	var mode_label := Label.new()
	mode_label.text = "窗口模式"
	mode_label.custom_minimum_size = Vector2(120, 0)
	mode_row.add_child(mode_label)
	var mode := OptionButton.new()
	mode.add_item("窗口", 0)
	mode.add_item("全屏", 1)
	mode.item_selected.connect(func(index: int) -> void:
		values["fullscreen"] = index == 1
		apply_screen()
		_refresh()
	)
	mode_row.add_child(mode)
	_widgets["fullscreen"] = mode
	var res_row := HBoxContainer.new()
	tab.add_child(res_row)
	var res_label := Label.new()
	res_label.text = "窗口分辨率"
	res_label.custom_minimum_size = Vector2(120, 0)
	res_row.add_child(res_label)
	var res := OptionButton.new()
	for i in RESOLUTIONS.size():
		res.add_item("%d × %d" % [RESOLUTIONS[i].x, RESOLUTIONS[i].y], i)
	res.item_selected.connect(func(index: int) -> void:
		values["resolution"] = index
		apply_screen()
	)
	res_row.add_child(res)
	_widgets["resolution"] = res
	var hint := Label.new()
	hint.text = "分辨率只在窗口模式下生效，全屏会用屏幕本身的大小。"
	hint.theme_type_variation = &"SoftLabel"
	tab.add_child(hint)
	for entry in [["screen_shake", "屏幕震动"], ["hit_stop", "打击停顿（命中时的瞬间定格）"]]:
		var check := CheckBox.new()
		check.text = entry[1]
		var key: String = entry[0]
		check.toggled.connect(func(on: bool) -> void:
			values[key] = on
			apply_effects()
		)
		tab.add_child(check)
		_widgets[key] = check
	return tab


func _build_keys_tab() -> Control:
	var tab := _tab("技能键位")
	var hint := Label.new()
	hint.text = "点一下按键，再按想用的新键。Esc 取消。和别的技能撞键会自动互换。"
	hint.theme_type_variation = &"SoftLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(hint)
	for entry in SKILL_ACTIONS:
		var row := HBoxContainer.new()
		tab.add_child(row)
		var label := Label.new()
		label.text = entry[1]
		label.custom_minimum_size = Vector2(220, 0)
		row.add_child(label)
		var button := Button.new()
		button.custom_minimum_size = Vector2(160, 0)
		var action: String = entry[0]
		button.pressed.connect(func() -> void:
			listening_action = action
			_refresh_key_buttons()
			_say("请按下新的按键…")
		)
		row.add_child(button)
		_key_buttons[action] = button
	var reset := Button.new()
	reset.text = "恢复默认键位"
	reset.pressed.connect(reset_keys)
	tab.add_child(reset)
	return tab


func _refresh() -> void:
	if _root == null:
		return
	for key in ["master", "music", "sfx"]:
		var pair: Array = _widgets[key]
		(pair[0] as HSlider).set_value_no_signal(float(values[key]))
		(pair[1] as Label).text = "%d%%" % roundi(float(values[key]) * 100.0)
	(_widgets["fullscreen"] as OptionButton).select(1 if bool(values["fullscreen"]) else 0)
	var res := _widgets["resolution"] as OptionButton
	res.select(clampi(int(values["resolution"]), 0, RESOLUTIONS.size() - 1))
	res.disabled = bool(values["fullscreen"])
	(_widgets["screen_shake"] as CheckBox).set_pressed_no_signal(bool(values["screen_shake"]))
	(_widgets["hit_stop"] as CheckBox).set_pressed_no_signal(bool(values["hit_stop"]))
	_refresh_key_buttons()


func _refresh_key_buttons() -> void:
	for action in _key_buttons:
		var button: Button = _key_buttons[action]
		button.text = "按下新按键…" if action == listening_action else key_name(get_key(action))
