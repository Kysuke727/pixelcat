extends Node

## The screen shown when a run ends: what was earned (reached the exit) or lost (the cat
## died), then "回家". It pauses the game while it is open and listens to
## ExpeditionManager.run_settlement.
##
## All player-facing text is Simplified Chinese.

const UI_THEME: Theme = preload("res://resources/ui/pixelcat_theme.tres")

## Seconds (real time) to let the player see the cat go down before the failure screen
## appears. (The success screen appears at once.)
var show_delay: float = 0.8

var _layer: CanvasLayer
var _root: Control
var _title: Label
var _subtitle: Label
var _lines: VBoxContainer
var _items: VBoxContainer
var _open: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	ExpeditionManager.run_settlement.connect(show_report)


func is_open() -> bool:
	return _open


func show_report(report: Dictionary) -> void:
	if not bool(report.get("success", false)) and show_delay > 0.0:
		await get_tree().create_timer(show_delay, true, false, true).timeout
	_populate(report)
	_open = true
	_root.visible = true
	get_tree().paused = true


## "回家": close the screen and go home.
func confirm() -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	get_tree().paused = false
	DayManager.switch_to_day()


func _populate(report: Dictionary) -> void:
	for child in _lines.get_children():
		child.queue_free()
	for child in _items.get_children():
		child.queue_free()
	var map_name := MapCatalog.display_name(str(report.get("map_id", MapCatalog.FIRST_MAP)))
	if bool(report.get("success", false)):
		_populate_success(report, map_name)
	else:
		_populate_failure(report, map_name)


func _populate_failure(report: Dictionary, map_name: String) -> void:
	_title.text = "♡ 探险失败 ♡"
	_subtitle.text = "你在「%s」倒下了" % map_name
	_add_line(_lines, "击败敌人：%d / %d" % [int(report.get("objectives_completed", 0)), int(report.get("objectives_total", 0))])
	_add_line(_lines, "小鱼干：保住 %d 条，丢失 %d 条" % [int(report.get("retained", 0)), int(report.get("lost", 0))])
	_add_line(_lines, "经验和已学会的招式都保留了")

	var items: Dictionary = report.get("items", {})
	var lost: Dictionary = items.get("lost", {})
	var heading := Label.new()
	heading.theme_type_variation = &"HeadingLabel"
	if lost.is_empty():
		heading.text = "背包没有丢东西"
	else:
		heading.text = "背包里丢失了 %d 件物品" % int(items.get("lost_total", 0))
	_items.add_child(heading)
	for item_id in lost:
		_items.add_child(_item_row(str(item_id), int(lost[item_id]), true))
	var kept: Dictionary = items.get("kept", {})
	if not kept.is_empty():
		var kept_heading := Label.new()
		kept_heading.theme_type_variation = &"SoftLabel"
		kept_heading.text = "受保护、没有丢失的物品"
		_items.add_child(kept_heading)
		for item_id in kept:
			_items.add_child(_item_row(str(item_id), int(kept[item_id]), false))


func _populate_success(report: Dictionary, map_name: String) -> void:
	_title.text = "♡ 探险成功 ♡"
	_subtitle.text = "你从「%s」平安回来了" % map_name
	_add_line(_lines, "击败敌人：%d / %d" % [int(report.get("objectives_completed", 0)), int(report.get("objectives_total", 0))])
	_add_line(_lines, "小鱼干：+%d" % int(report.get("retained", 0)))
	_add_line(_lines, "经验：+%d" % int(report.get("experience", 0)))

	var gained: Dictionary = report.get("items_gained", {})
	var heading := Label.new()
	heading.theme_type_variation = &"HeadingLabel"
	heading.text = "本次带回的东西" if not gained.is_empty() else "这次没有带回材料"
	_items.add_child(heading)
	for item_id in gained:
		_items.add_child(_item_row(str(item_id), int(gained[item_id]), false))

	# Good news goes last: new moves, and the first clear of a map.
	var news: Array[String] = []
	for move_id in report.get("moves_learned", []):
		news.append("学会了新招式：%s" % MoveCatalog.display_name(str(move_id)))
	if bool(report.get("first_clear", false)):
		news.append("首次通关「%s」！" % map_name)
	for map_id in report.get("new_maps", []):
		news.append("解锁了新地图：%s" % MapCatalog.display_name(str(map_id)))
	if not news.is_empty():
		var news_heading := Label.new()
		news_heading.theme_type_variation = &"HeadingLabel"
		news_heading.text = "新收获"
		_items.add_child(news_heading)
		for line in news:
			var label := Label.new()
			label.text = "★ " + line
			label.theme_type_variation = &"GoodLabel"
			_items.add_child(label)


func _item_row(item_id: String, quantity: int, was_lost: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var item = InventoryManager.get_item_data(item_id)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(24, 24)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.texture = item.icon if item != null else null
	row.add_child(icon)
	var label := Label.new()
	label.text = "%s ×%d" % [item.display_name if item != null else item_id, quantity]
	label.theme_type_variation = &"BadLabel" if was_lost else &"GoodLabel"
	row.add_child(label)
	return row


func _add_line(parent: Node, text: String) -> void:
	var label := Label.new()
	label.text = text
	parent.add_child(label)


func _build() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 90
	add_child(_layer)
	_root = Control.new()
	_root.theme = UI_THEME
	_root.visible = false
	_layer.add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.1, 0.05, 0.1, 0.72)
	_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(480, 0)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	_title = Label.new()
	_title.theme_type_variation = &"TitleLabel"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title)
	_subtitle = Label.new()
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_subtitle)
	var stats_panel := PanelContainer.new()
	stats_panel.theme_type_variation = &"InsetPanel"
	column.add_child(stats_panel)
	_lines = VBoxContainer.new()
	_lines.add_theme_constant_override("separation", 4)
	stats_panel.add_child(_lines)
	var items_panel := PanelContainer.new()
	items_panel.theme_type_variation = &"InsetPanel"
	column.add_child(items_panel)
	_items = VBoxContainer.new()
	_items.add_theme_constant_override("separation", 4)
	items_panel.add_child(_items)
	var home := Button.new()
	home.text = "回家"
	home.custom_minimum_size = Vector2(0, 40)
	home.pressed.connect(confirm)
	column.add_child(home)
