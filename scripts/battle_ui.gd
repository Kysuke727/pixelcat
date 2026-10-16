
extends Control

@onready var enemy_name: Label = $PanelContainer/VBoxContainer/EnemyName
@onready var enemy_hp_bar: ProgressBar = $PanelContainer/VBoxContainer/EnemyHPBar

var current_hp: float = 100.0
var max_hp: float = 100.0

func _ready() -> void:
	set_enemy_info("测试敌人", 100.0, 100.0)

func set_enemy_info(
	new_name: String,
	hp: float,
	hp_max: float
) -> void:
	enemy_name.text = new_name

	max_hp = maxf(hp_max, 1.0)
	current_hp = clampf(hp, 0.0, max_hp)

	enemy_hp_bar.min_value = 0.0
	enemy_hp_bar.max_value = max_hp
	enemy_hp_bar.value = current_hp

func set_enemy_hp(hp: float, hp_max: float) -> void:
	max_hp = maxf(hp_max, 1.0)
	current_hp = clampf(hp, 0.0, max_hp)

	enemy_hp_bar.max_value = max_hp
	enemy_hp_bar.value = current_hp


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1:
			set_enemy_hp(75.0, 100.0)
		elif event.keycode == KEY_2:
			set_enemy_hp(50.0, 100.0)
		elif event.keycode == KEY_3:
			set_enemy_hp(25.0, 100.0)
		elif event.keycode == KEY_0:
			set_enemy_hp(100.0, 100.0)
