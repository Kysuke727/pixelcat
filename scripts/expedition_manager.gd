extends Node

signal expedition_changed
signal expedition_finished(success: bool, retained_fish: int, lost_fish: int)

@export var starting_lives: int = 2
@export_range(0.0, 1.0) var failure_loss_ratio: float = 0.5
@export var odd_loot_rounding: String = "floor"
@export var exploration_clear_experience: int = 50

var run_active: bool = false
var lives_left: int = 0
var ordinary_fish: int = 0
var objectives_total: int = 0
var objectives_completed: int = 0
var defeated_enemy_ids: Array[String] = []
var exploration_reward_claimed: bool = false
var active_safe_position: Vector2 = Vector2(500.0, 350.0)
var saved_player_position: Vector2 = Vector2(500.0, 350.0)
var saved_health: float = -1.0
var saved_shield: float = -1.0
var last_outcome: String = ""
var _is_resuming: bool = false
var _debug_snapshot: Dictionary = {}
var _debug_player_snapshot: Dictionary = {}


func begin_run() -> void:
	run_active = true
	lives_left = starting_lives
	ordinary_fish = 0
	objectives_total = 0
	objectives_completed = 0
	defeated_enemy_ids.clear()
	exploration_reward_claimed = false
	active_safe_position = Vector2(500.0, 350.0)
	saved_player_position = active_safe_position
	saved_health = -1.0
	saved_shield = -1.0
	last_outcome = ""
	_is_resuming = false
	expedition_changed.emit()
	ProgressionManager.save_now()


func add_ordinary_fish(amount: int) -> void:
	if not run_active or amount <= 0:
		return
	ordinary_fish += amount
	expedition_changed.emit()
	ProgressionManager.save_now()


func activate_safe_point(position: Vector2) -> void:
	if not run_active:
		return
	active_safe_position = position
	ProgressionManager.save_now()
	expedition_changed.emit()


func set_objectives(enemy_ids: Array[String]) -> void:
	if not run_active:
		return
	objectives_total = enemy_ids.size()
	objectives_completed = 0
	for enemy_id in enemy_ids:
		if defeated_enemy_ids.has(enemy_id):
			objectives_completed += 1
	expedition_changed.emit()
	ProgressionManager.save_now()


func complete_enemy_objective(enemy_id: String, experience_reward: int = 0) -> void:
	if not run_active or enemy_id.is_empty() or defeated_enemy_ids.has(enemy_id):
		return
	defeated_enemy_ids.append(enemy_id)
	objectives_completed = mini(objectives_completed + 1, objectives_total)
	ProgressionManager.add_experience(maxi(experience_reward, 0))
	if objectives_complete() and not exploration_reward_claimed:
		exploration_reward_claimed = true
		ProgressionManager.add_experience(exploration_clear_experience)
	ProgressionManager.save_now()
	expedition_changed.emit()


func objectives_complete() -> bool:
	return run_active and objectives_total > 0 and objectives_completed >= objectives_total


func award_quest_experience(amount: int) -> int:
	return ProgressionManager.add_experience(maxi(amount, 0))


func on_player_died(player: Node) -> void:
	if not run_active:
		return
	lives_left = maxi(lives_left - 1, 0)
	if lives_left > 0 and is_instance_valid(player):
		saved_player_position = active_safe_position
		saved_health = float(player.get("max_health"))
		saved_shield = float(player.get("shield_max_durability")) * 0.5
	else:
		saved_health = -1.0
		saved_shield = -1.0
	expedition_changed.emit()
	ProgressionManager.save_now()
	if lives_left <= 0:
		finish_run(false, DayManager.current_state == DayManager.TimeState.NIGHT)
	else:
		call_deferred("_respawn_player", player)


func _respawn_player(player: Node) -> void:
	if not run_active or not is_instance_valid(player):
		return
	if player.has_method("revive_from_expedition"):
		player.revive_from_expedition(active_safe_position)
	else:
		player.global_position = active_safe_position


func finish_run(success: bool, transition_to_day: bool = true) -> void:
	if not run_active:
		return
	var before := ordinary_fish
	var lost := 0
	if not success:
		lost = int(floor(float(ordinary_fish) * failure_loss_ratio)) if odd_loot_rounding == "floor" else int(ceil(float(ordinary_fish) * failure_loss_ratio))
	ordinary_fish = maxi(ordinary_fish - lost, 0)
	var retained := ordinary_fish
	ordinary_fish = 0
	run_active = false
	last_outcome = "success" if success else "failed"
	_is_resuming = false
	if retained > 0:
		CurrencyManager.add_permanent_fish(retained)
	expedition_finished.emit(success, retained, lost)
	expedition_changed.emit()
	ProgressionManager.save_now()
	if transition_to_day and DayManager.current_state == DayManager.TimeState.NIGHT:
		DayManager.switch_to_day()
	elif transition_to_day:
		push_warning("Expedition ended outside the night scene; settlement saved for next day")
	if before < 0:
		push_warning("Invalid expedition loot state was clamped")


func capture_current_run() -> void:
	if not run_active or ProgressionManager.debug_session:
		return
	var scene := get_tree().current_scene
	if scene == null or not scene.is_in_group("night_exploration"):
		return
	var player := get_tree().get_first_node_in_group("player")
	if is_instance_valid(player):
		if bool(player.get("dead")):
			saved_player_position = active_safe_position
			return
		saved_player_position = player.global_position
		if player.get("current_health") != null:
			saved_health = float(player.get("current_health"))
		if player.get("shield_durability") != null:
			saved_shield = float(player.get("shield_durability"))


func restore_player_if_resuming(player: Node) -> void:
	if not run_active or not _is_resuming:
		return
	player.global_position = saved_player_position
	if player.has_method("restore_expedition_state"):
		player.restore_expedition_state(saved_health, saved_shield)
	_is_resuming = false
	expedition_changed.emit()


func get_save_data() -> Dictionary:
	return {
		"run_active": run_active,
		"lives_left": lives_left,
		"ordinary_fish": ordinary_fish,
		"objectives_total": objectives_total,
		"objectives_completed": objectives_completed,
		"defeated_enemy_ids": defeated_enemy_ids.duplicate(),
		"exploration_reward_claimed": exploration_reward_claimed,
		"safe_position": [active_safe_position.x, active_safe_position.y],
		"player_position": [saved_player_position.x, saved_player_position.y],
		"health": saved_health,
		"shield": saved_shield,
		"last_outcome": last_outcome,
	}


func load_save_data(data: Dictionary) -> void:
	run_active = bool(data.get("run_active", false))
	lives_left = clampi(int(data.get("lives_left", starting_lives)), 0, starting_lives)
	ordinary_fish = maxi(int(data.get("ordinary_fish", 0)), 0)
	objectives_total = maxi(int(data.get("objectives_total", 0)), 0)
	objectives_completed = clampi(int(data.get("objectives_completed", 0)), 0, objectives_total)
	defeated_enemy_ids.clear()
	for enemy_id in data.get("defeated_enemy_ids", []):
		defeated_enemy_ids.append(str(enemy_id))
	exploration_reward_claimed = bool(data.get("exploration_reward_claimed", objectives_completed >= objectives_total and objectives_total > 0))
	active_safe_position = _vector_from_data(data.get("safe_position", [500.0, 350.0]))
	saved_player_position = _vector_from_data(data.get("player_position", [500.0, 350.0]))
	saved_health = float(data.get("health", -1.0))
	saved_shield = float(data.get("shield", -1.0))
	last_outcome = str(data.get("last_outcome", ""))
	_is_resuming = run_active
	expedition_changed.emit()


func _vector_from_data(value: Variant) -> Vector2:
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2(500.0, 350.0)


func begin_debug_session() -> void:
	_debug_snapshot = get_save_data().duplicate(true)
	var player := get_tree().get_first_node_in_group("player")
	if is_instance_valid(player):
		_debug_player_snapshot = {
			"scene_path": get_tree().current_scene.scene_file_path,
			"position": player.global_position,
			"health": float(player.get("current_health")),
			"shield": float(player.get("shield_durability")),
			"dead": bool(player.get("dead")),
		}


func end_debug_session() -> void:
	if not _debug_snapshot.is_empty():
		load_save_data(_debug_snapshot)
		_debug_snapshot.clear()


func restore_debug_player_snapshot() -> void:
	if _debug_player_snapshot.is_empty():
		return
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path != str(_debug_player_snapshot.get("scene_path", "")):
		_debug_player_snapshot.clear()
		return
	var player := get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player):
		_debug_player_snapshot.clear()
		return
	if not bool(_debug_player_snapshot["dead"]) and bool(player.get("dead")) and player.has_method("revive_from_expedition"):
		player.revive_from_expedition(_debug_player_snapshot["position"])
	player.global_position = _debug_player_snapshot["position"]
	player.set("current_health", _debug_player_snapshot["health"])
	player.set("shield_durability", _debug_player_snapshot["shield"])
	player.set("dead", _debug_player_snapshot["dead"])
	var combat := player.get_node_or_null("PlayerCombat")
	if is_instance_valid(combat) and combat.has_method("set_combat_enabled"):
		combat.set_combat_enabled(not bool(_debug_player_snapshot["dead"]))
	if player.has_signal("health_changed"):
		player.health_changed.emit(player.current_health, player.max_health)
	_debug_player_snapshot.clear()
