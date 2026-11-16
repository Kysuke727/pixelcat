extends Control

@onready var player_hp_bar: ProgressBar = $PanelContainer/VBoxContainer/PlayerHPBar
@onready var shield_label: Label = $PanelContainer/VBoxContainer/ShieldLabel
@onready var shield_bar: ProgressBar = $PanelContainer/VBoxContainer/ShieldBar
@onready var yarn_label: Label = $PanelContainer/VBoxContainer/YarnLabel
@onready var dash_label: Label = $PanelContainer/VBoxContainer/DashLabel
@onready var combat_feedback: Label = $PanelContainer/VBoxContainer/CombatFeedback
@onready var enemy_name: Label = $PanelContainer/VBoxContainer/EnemyName
@onready var enemy_hp_bar: ProgressBar = $PanelContainer/VBoxContainer/EnemyHPBar

var shown_enemy: Node
var player: Node
var combat: Node


func _ready() -> void:
	add_to_group("battle_ui")
	enemy_name.visible = false
	enemy_hp_bar.visible = false
	call_deferred("_bind_player")


func _bind_player() -> void:
	player = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	combat = player.get_node_or_null("PlayerCombat")
	player_hp_bar.max_value = player.max_health
	player_hp_bar.value = player.current_health
	shield_bar.max_value = player.shield_max_durability
	shield_bar.value = player.shield_durability
	if not player.health_changed.is_connected(_on_player_health_changed):
		player.health_changed.connect(_on_player_health_changed)
	_update_combat_readout()


func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		_bind_player()
		return
	_update_combat_readout()


func _update_combat_readout() -> void:
	if not is_instance_valid(player):
		return
	var durability: float = float(player.get("shield_durability"))
	var max_durability: float = float(player.get("shield_max_durability"))
	shield_bar.max_value = maxf(max_durability, 1.0)
	shield_bar.value = durability
	shield_label.text = "护盾 %.0f / %.0f" % [durability, max_durability]
	if player.get("guard_break_left") > 0.0:
		combat_feedback.text = "防御破碎 %.1fs" % float(player.get("guard_break_left"))
		combat_feedback.add_theme_color_override("font_color", Color(1.0, 0.38, 0.32))
	elif player.get("perfect_guard_flash_left") > 0.0:
		combat_feedback.text = "完美防御！"
		combat_feedback.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	elif player.get("is_defending"):
		combat_feedback.text = "炸毛防御中 · Z 松开恢复"
		combat_feedback.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	elif is_instance_valid(combat) and combat.get("combo_hit_feedback_left") > 0.0:
		combat_feedback.text = str(combat.get("combo_feedback_text"))
		combat_feedback.add_theme_color_override("font_color", Color(1.0, 0.87, 0.45))
	else:
		combat_feedback.text = "J 爪击 · K 黏黏球 · Z 防御 · 空格 冲刺 · Shift 闪避"
		if ProgressionManager.has_move("triple_combo"):
			combat_feedback.text += " · J×3 三段"
		combat_feedback.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	_update_dash_readout()
	if is_instance_valid(combat):
		var remaining: float = float(combat.get("ranged_cooldown_left"))
		var yarn_state := "就绪" if remaining <= 0.0 else "冷却 %.1fs" % remaining
		if bool(combat.get("yarn_projectile_in_flight")):
			yarn_state += " · 飞行中"
		yarn_label.text = "黏黏球：" + yarn_state


## "冲刺 ●○ · 闪避 就绪/冷却" - filled dots are available dash charges.
func _update_dash_readout() -> void:
	var charges: int = int(player.get("dash_charges"))
	var max_charges: int = int(player.get("dash_max_charges"))
	var dots := "●".repeat(charges) + "○".repeat(maxi(max_charges - charges, 0))
	var dodge_left: float = float(player.get("dodge_cooldown_left"))
	var dodge_state := "就绪" if dodge_left <= 0.0 else "冷却 %.0fs" % ceilf(dodge_left)
	dash_label.text = "冲刺 %s · 闪避 %s" % [dots, dodge_state]
	if ProgressionManager.has_move("counter_claw") and bool(player.call("is_counter_window_open")):
		dash_label.text += " · 反击机会！按 J"
	elif ProgressionManager.has_move("pounce") and bool(player.call("can_pounce")):
		dash_label.text += " · 扑击！按 J"


func _on_player_health_changed(current_health: float, max_health: float) -> void:
	player_hp_bar.max_value = max_health
	player_hp_bar.value = current_health


func show_enemy(enemy: Node, new_name: String, hp: float, hp_max: float) -> void:
	shown_enemy = enemy
	enemy_name.text = new_name
	enemy_hp_bar.max_value = maxf(hp_max, 1.0)
	enemy_hp_bar.value = clampf(hp, 0.0, hp_max)
	enemy_name.visible = true
	enemy_hp_bar.visible = true


func hide_enemy(enemy: Node) -> void:
	if shown_enemy != enemy:
		return
	shown_enemy = null
	enemy_name.visible = false
	enemy_hp_bar.visible = false
