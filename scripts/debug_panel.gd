extends CanvasLayer

var panel: PanelContainer
var status: Label
var details: Label
var active: bool = false


func _ready() -> void:
	layer = 30
	_build_ui()
	panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F3:
		if active:
			_close_debug()
		else:
			active = true
			ProgressionManager.begin_debug_session()
			ExpeditionManager.begin_debug_session()
			panel.visible = true
			_refresh()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-350.0, 18.0)
	panel.custom_minimum_size = Vector2(330.0, 0.0)
	add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var title := Label.new()
	title.text = "开发调试 · F3（隔离模式）"
	title.add_theme_font_size_override("font_size", 18)
	column.add_child(title)
	status = Label.new()
	column.add_child(status)
	details = Label.new()
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(details)
	_add_button(column, "HP +1", func(): _change_player("current_health", 1.0))
	_add_button(column, "HP -1", func(): _change_player("current_health", -1.0))
	_add_button(column, "护盾 +10", func(): _change_player("shield_durability", 10.0))
	_add_button(column, "护盾 -10", func(): _change_player("shield_durability", -10.0))
	_add_button(column, "增加 100 经验", func(): ProgressionManager.add_experience(100))
	_add_button(column, "增加探索生命", func(): ExpeditionManager.lives_left += 1)
	_add_button(column, "测试死亡/安全点复活", _test_player_death)
	_add_button(column, "模拟成功结算", func(): _simulate_settlement(true))
	_add_button(column, "模拟失败结算", func(): _simulate_settlement(false))
	_add_button(column, "关闭并还原调试数据", _close_debug)


func _add_button(parent: Node, title: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = title
	button.pressed.connect(callback)
	parent.add_child(button)


func _process(_delta: float) -> void:
	if active:
		_refresh()


func _refresh() -> void:
	var player := get_tree().get_first_node_in_group("player")
	var hp := "无玩家"
	if is_instance_valid(player):
		hp = "HP %.1f/%.1f · 护盾 %.1f/%.1f" % [float(player.get("current_health")), float(player.get("max_health")), float(player.get("shield_durability")), float(player.get("shield_max_durability"))]
	status.text = "%s · 等级 %d · XP %d/%d\n夜晚生命 %d · 本次鱼干 %d · 目标 %d/%d" % [hp, ProgressionManager.level, ProgressionManager.experience, ProgressionManager.required_experience(), ExpeditionManager.lives_left, ExpeditionManager.ordinary_fish, ExpeditionManager.objectives_completed, ExpeditionManager.objectives_total]
	var enemy_lines: Array[String] = []
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy_lines.append("%s: %s · HP %s · bind %.1f (免疫 %.1f) · stun %.1f (免疫 %.1f)" % [enemy.name, str(enemy.get("state")), str(enemy.get("current_health")), float(enemy.get("bind_time_left")), float(enemy.get("bind_resistance_left")), float(enemy.get("stun_time_left")), float(enemy.get("stun_immunity_left"))])
	var player_combat := player.get_node_or_null("PlayerCombat") if is_instance_valid(player) else null
	var cooldown_text := ""
	if is_instance_valid(player_combat):
		cooldown_text = "\n冷却：J %.1fs · K %.1fs · 闪避 %.1fs" % [float(player_combat.get("melee_cooldown_left")), float(player_combat.get("ranged_cooldown_left")), float(player.get("dodge_cooldown_left"))]
	details.text = "调试隔离：不会保存改动；击杀、拾取与场景切换已禁用。\n技巧：减速%d · 连接%d · 束缚%d · 绕圈%d\n" % [ProgressionManager.skill_points["slow"], ProgressionManager.skill_points["connection"], ProgressionManager.skill_points["bind"], ProgressionManager.skill_points["loop"]] + "敌人状态\n" + ("\n".join(enemy_lines) if not enemy_lines.is_empty() else "无存活敌人") + cooldown_text


func _change_player(property: String, amount: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player):
		return
	var current := float(player.get(property))
	var cap_property := "max_health" if property == "current_health" else "shield_max_durability"
	player.set(property, clampf(current + amount, 0.0, float(player.get(cap_property))))
	player.health_changed.emit(player.current_health, player.max_health)


func _test_player_death() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if is_instance_valid(player):
		player.receive_damage(999.0, player.global_position + Vector2(1.0, 0.0), 0.0)


func _simulate_settlement(success: bool) -> void:
	var loss := 0
	if not success:
		loss = int(floor(float(ExpeditionManager.ordinary_fish) * ExpeditionManager.failure_loss_ratio))
	var retained := ExpeditionManager.ordinary_fish - loss
	status.text += "\n模拟%s：保留 %d，损失 %d（未提交存档）" % ["成功撤离" if success else "失败结算", retained, loss]


func _close_debug() -> void:
	if not active:
		return
	if not _restore_debug_session():
		status.text += "\n调试快照恢复或存档失败；隔离状态仍保留，未写入正式存档。"
		return
	active = false
	panel.visible = false


func _restore_debug_session() -> bool:
	# Restore exploration, then growth/currency, then the player (whose caps depend
	# on progression); persistence remains disabled until the final commit.
	if not ExpeditionManager.restore_debug_expedition_snapshot():
		return false
	if not ProgressionManager.restore_debug_session_snapshot():
		return false
	if not ExpeditionManager.restore_debug_player_snapshot():
		return false
	if not ProgressionManager.commit_debug_session():
		return false
	ExpeditionManager.complete_debug_session()
	return true


func _exit_tree() -> void:
	if active:
		_restore_debug_session()
