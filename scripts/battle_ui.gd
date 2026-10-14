
extends Control

@onready var enemy_name = get_node_or_null("PanelContainer/VBoxContainer/EnemyName")
@onready var enemy_hp_bar = get_node_or_null("PanelContainer/VBoxContainer/EnemyHPBar")

func _ready() -> void:
	if enemy_name == null:
		print("找不到 EnemyName，请检查节点路径")
		return

	if enemy_hp_bar == null:
		print("找不到 EnemyHPBar，请检查节点路径")
		return

	enemy_name.text = "测试敌人"
	enemy_hp_bar.min_value = 0
	enemy_hp_bar.max_value = 100
	enemy_hp_bar.value = 100

func set_enemy_hp(current_hp: float, max_hp: float) -> void:
	if enemy_hp_bar == null:
		return

	enemy_hp_bar.max_value = maxf(max_hp, 1.0)
	enemy_hp_bar.value = clampf(current_hp, 0.0, max_hp)
