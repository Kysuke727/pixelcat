extends Node

var enemy_pause_time_left: float = 0.0
var observed_scene: Node


func _process(delta: float) -> void:
	var scene := get_tree().current_scene
	if scene != observed_scene:
		observed_scene = scene
		if enemy_pause_time_left > 0.0:
			clear_enemy_pause()
	if enemy_pause_time_left <= 0.0:
		return
	enemy_pause_time_left = maxf(enemy_pause_time_left - delta, 0.0)
	if enemy_pause_time_left <= 0.0:
		_set_enemy_side_paused(false)


func pause_enemy_side(duration: float) -> bool:
	if duration <= 0.0 or enemy_pause_time_left > 0.0:
		return false
	enemy_pause_time_left = duration
	observed_scene = get_tree().current_scene
	_set_enemy_side_paused(true)
	return true


func is_enemy_side_paused() -> bool:
	return enemy_pause_time_left > 0.0


func clear_enemy_pause() -> void:
	if enemy_pause_time_left <= 0.0:
		return
	enemy_pause_time_left = 0.0
	_set_enemy_side_paused(false)


func _set_enemy_side_paused(paused: bool) -> void:
	for group_name in ["enemies", "enemy_projectiles"]:
		for actor in get_tree().get_nodes_in_group(group_name):
			if actor.has_method("set_combat_paused"):
				actor.set_combat_paused(paused)
