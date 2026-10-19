extends Control

@onready var player_hp_bar: ProgressBar = $PanelContainer/VBoxContainer/PlayerHPBar
@onready var enemy_name: Label = $PanelContainer/VBoxContainer/EnemyName
@onready var enemy_hp_bar: ProgressBar = $PanelContainer/VBoxContainer/EnemyHPBar

var shown_enemy: Node


func _ready() -> void:
	add_to_group("battle_ui")
	enemy_name.visible = false
	enemy_hp_bar.visible = false
	call_deferred("_bind_player")


func _bind_player() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	player_hp_bar.max_value = player.max_health
	player_hp_bar.value = player.current_health
	if not player.health_changed.is_connected(_on_player_health_changed):
		player.health_changed.connect(_on_player_health_changed)


func _on_player_health_changed(current_health: int, max_health: int) -> void:
	player_hp_bar.max_value = max_health
	player_hp_bar.value = current_health


func show_enemy(enemy: Node, new_name: String, hp: int, hp_max: int) -> void:
	shown_enemy = enemy
	enemy_name.text = new_name
	enemy_hp_bar.max_value = maxi(hp_max, 1)
	enemy_hp_bar.value = clampi(hp, 0, hp_max)
	enemy_name.visible = true
	enemy_hp_bar.visible = true


func hide_enemy(enemy: Node) -> void:
	if shown_enemy != enemy:
		return
	shown_enemy = null
	enemy_name.visible = false
	enemy_hp_bar.visible = false
