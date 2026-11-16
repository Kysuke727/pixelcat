extends Node

signal expedition_changed
signal expedition_finished(success: bool, retained_fish: int, lost_fish: int)
## Emitted when a run is over and the settlement screen should be shown (the cat died, or
## it reached the exit). The report has "success", "reason" ("death" / "success") and the summary.
signal run_settlement(report: Dictionary)

## Dying ends the run (see on_player_died), so there is only one "life".
@export var starting_lives: int = 1
@export_range(0.0, 1.0) var failure_loss_ratio: float = 0.5
@export var odd_loot_rounding: String = "floor"
@export var exploration_clear_experience: int = 50

var run_active: bool = false
## What this run has earned so far (shown on the success settlement; saved with the run).
var run_experience_gained: int = 0
var run_items_gained: Dictionary = {}
var run_moves_learned: Array[String] = []
## Summary of the run that just ended: {success, retained, lost, map_id, objectives_*}.
var last_result: Dictionary = {}
## Ids of the enemies that count toward the objective (set by set_objectives, not saved).
## Empty = unknown, in which case every defeated enemy counts (the original behaviour).
var objective_ids: Array[String] = []
## Which night map this run is on (see MapCatalog); saved so Continue resumes the right map.
var current_map_id: String = MapCatalog.FIRST_MAP
var lives_left: int = 0
var ordinary_fish: int = 0
var objectives_total: int = 0
var objectives_completed: int = 0
var defeated_enemy_ids: Array[String] = []
var fish_drops: Dictionary = {}
var material_drops: Dictionary = {}
var exploration_reward_claimed: bool = false
var saved_player_position: Vector2 = Vector2(500.0, 350.0)
var saved_health: float = -1.0
var saved_shield: float = -1.0
var last_outcome: String = ""
var _is_resuming: bool = false
var _debug_snapshot: Dictionary = {}
var _debug_player_snapshot: Dictionary = {}


func _ready() -> void:
	InventoryManager.item_added.connect(_on_item_added)
	ProgressionManager.move_unlocked.connect(_on_move_unlocked)


func _on_item_added(item_id: String, quantity: int) -> void:
	if run_active and not ProgressionManager.debug_session and quantity > 0:
		run_items_gained[item_id] = int(run_items_gained.get(item_id, 0)) + quantity


func _on_move_unlocked(move_id: String) -> void:
	if run_active and not ProgressionManager.debug_session and not run_moves_learned.has(move_id):
		run_moves_learned.append(move_id)


## All experience granted by a run goes through here so the settlement can report it.
func _award_experience(amount: int) -> void:
	if amount <= 0:
		return
	run_experience_gained += amount
	ProgressionManager.add_experience(amount)


func begin_run(map_id: String = MapCatalog.FIRST_MAP) -> void:
	if ProgressionManager.debug_session:
		return
	run_active = true
	current_map_id = map_id if MapCatalog.has_map(map_id) else MapCatalog.FIRST_MAP
	lives_left = starting_lives
	ordinary_fish = 0
	objectives_total = 0
	objectives_completed = 0
	defeated_enemy_ids.clear()
	objective_ids.clear()
	run_experience_gained = 0
	run_items_gained.clear()
	run_moves_learned.clear()
	fish_drops.clear()
	material_drops.clear()
	exploration_reward_claimed = false
	# Every map has its own start (a resumed run before the first autosave starts there).
	saved_player_position = MapCatalog.start_position(current_map_id)
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


func set_objectives(enemy_ids: Array[String]) -> void:
	if not run_active:
		return
	objective_ids.assign(enemy_ids)
	objectives_total = enemy_ids.size()
	objectives_completed = 0
	for enemy_id in enemy_ids:
		if defeated_enemy_ids.has(enemy_id):
			objectives_completed += 1
	expedition_changed.emit()
	ProgressionManager.save_now()


## Optional enemies (e.g. the secret-trail guard) are remembered as defeated and give
## their drops and experience, but do not count toward opening the exit.
func _counts_for_objective(enemy_id: String) -> bool:
	return objective_ids.is_empty() or objective_ids.has(enemy_id)


func complete_enemy_objective(enemy_id: String, experience_reward: int = 0) -> void:
	if not run_active or ProgressionManager.debug_session or enemy_id.is_empty() or defeated_enemy_ids.has(enemy_id):
		return
	defeated_enemy_ids.append(enemy_id)
	if _counts_for_objective(enemy_id):
		objectives_completed = mini(objectives_completed + 1, objectives_total)
	_award_experience(maxi(experience_reward, 0))
	if objectives_complete() and not exploration_reward_claimed:
		exploration_reward_claimed = true
		_award_experience(exploration_clear_experience)
	ProgressionManager.save_now()
	expedition_changed.emit()


func complete_enemy_with_drops(enemy_id: String, experience_reward: int, drops: Array[Dictionary], material_records: Array[Dictionary] = []) -> void:
	if not run_active or ProgressionManager.debug_session or enemy_id.is_empty() or defeated_enemy_ids.has(enemy_id):
		return
	for drop in drops:
		var drop_id := str(drop.get("id", ""))
		if drop_id.is_empty():
			continue
		fish_drops[drop_id] = drop.duplicate(true)
	for record in material_records:
		var drop_id := str(record.get("id", ""))
		var item_id := str(record.get("item_id", ""))
		if drop_id.is_empty() or not ["yarn", "stone", "wood"].has(item_id):
			continue
		material_drops[drop_id] = record.duplicate(true)
	defeated_enemy_ids.append(enemy_id)
	if _counts_for_objective(enemy_id):
		objectives_completed = mini(objectives_completed + 1, objectives_total)
	_award_experience(maxi(experience_reward, 0))
	if objectives_complete() and not exploration_reward_claimed:
		exploration_reward_claimed = true
		_award_experience(exploration_clear_experience)
	ProgressionManager.save_now()
	expedition_changed.emit()


## Successful pickup modifies the material count and pending drop table together.
## add_item(..., false) skips an intermediate save; the final save includes both.
func collect_saved_material_drop(drop_id: String) -> bool:
	if ProgressionManager.debug_session or not run_active or not material_drops.has(drop_id):
		return false
	var record: Dictionary = material_drops[drop_id]
	var item_id: String = str(record.get("item_id", ""))
	var amount: int = int(record.get("amount", 1))
	if not ["yarn", "stone", "wood"].has(item_id) or amount <= 0:
		return false
	if InventoryManager.get_addable_quantity(item_id, amount) < amount:
		return false
	var result: Dictionary = InventoryManager.add_item(item_id, amount, false)
	if not bool(result.get("success", false)):
		return false
	material_drops.erase(drop_id)
	ProgressionManager.save_now()
	expedition_changed.emit()
	return true


func collect_saved_fish_drop(drop_id: String) -> bool:
	if ProgressionManager.debug_session or not run_active or not fish_drops.has(drop_id):
		return false
	var record: Dictionary = fish_drops[drop_id]
	var amount := maxi(int(record.get("amount", 1)), 1)
	fish_drops.erase(drop_id)
	ordinary_fish += amount
	ProgressionManager.save_now()
	expedition_changed.emit()
	return true


func objectives_complete() -> bool:
	return run_active and objectives_total > 0 and objectives_completed >= objectives_total


func award_quest_experience(amount: int) -> int:
	return ProgressionManager.add_experience(maxi(amount, 0))


## Dying ends the run: fish are halved (as before), the backpack loses a random half of its
## loseable items, and the settlement screen is shown. There is no respawn.
func on_player_died(player: Node) -> void:
	if not run_active or ProgressionManager.debug_session:
		return
	lives_left = 0
	saved_health = -1.0
	saved_shield = -1.0
	expedition_changed.emit()
	finish_run(false, false)  # banks the surviving fish, ends the run, saves
	var report: Dictionary = last_result.duplicate(true)
	report["reason"] = "death"
	report["items"] = InventoryManager.apply_death_loss()
	run_settlement.emit(report)


func finish_run(success: bool, transition_to_day: bool = true) -> void:
	if not run_active or ProgressionManager.debug_session:
		return
	var before := ordinary_fish
	var maps_before: Array = ProgressionManager.available_maps()
	var first_clear := false
	var lost := 0
	if not success:
		lost = int(floor(float(ordinary_fish) * failure_loss_ratio)) if odd_loot_rounding == "floor" else int(ceil(float(ordinary_fish) * failure_loss_ratio))
	ordinary_fish = maxi(ordinary_fish - lost, 0)
	var retained := ordinary_fish
	ordinary_fish = 0
	run_active = false
	last_outcome = "success" if success else "failed"
	if success:
		first_clear = ProgressionManager.mark_map_cleared(current_map_id)
	_is_resuming = false
	if retained > 0:
		CurrencyManager.add_permanent_fish(retained)
	last_result = {
		"success": success,
		"retained": retained,
		"lost": lost,
		"map_id": current_map_id,
		"objectives_completed": objectives_completed,
		"objectives_total": objectives_total,
		"experience": run_experience_gained,
		"items_gained": run_items_gained.duplicate(),
		"moves_learned": run_moves_learned.duplicate(),
		"first_clear": first_clear,
		"new_maps": _newly_available(maps_before),
	}
	expedition_finished.emit(success, retained, lost)
	expedition_changed.emit()
	ProgressionManager.save_now()
	if transition_to_day and DayManager.current_state == DayManager.TimeState.NIGHT:
		DayManager.switch_to_day()
	elif transition_to_day:
		push_warning("Expedition ended outside the night scene; settlement saved for next day")
	if before < 0:
		push_warning("Invalid expedition loot state was clamped")


func _newly_available(maps_before: Array) -> Array:
	var result: Array = []
	for map_id in ProgressionManager.available_maps():
		if not maps_before.has(map_id):
			result.append(map_id)
	return result


## Reaching the exit: ends the run successfully and shows the settlement screen
## (the player presses "回家" to go home).
func complete_run_with_settlement() -> void:
	if not run_active or ProgressionManager.debug_session:
		return
	finish_run(true, false)
	var report: Dictionary = last_result.duplicate(true)
	report["reason"] = "success"
	run_settlement.emit(report)


func capture_current_run() -> void:
	if not run_active or ProgressionManager.debug_session:
		return
	var scene := get_tree().current_scene
	if scene == null or not scene.is_in_group("night_exploration"):
		return
	var player := get_tree().get_first_node_in_group("player")
	if is_instance_valid(player):
		if bool(player.get("dead")):
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
		"map_id": current_map_id,
		"lives_left": lives_left,
		"ordinary_fish": ordinary_fish,
		"objectives_total": objectives_total,
		"objectives_completed": objectives_completed,
		"defeated_enemy_ids": defeated_enemy_ids.duplicate(),
		"fish_drops": fish_drops.duplicate(true),
		"material_drops": material_drops.duplicate(true),
		"exploration_reward_claimed": exploration_reward_claimed,
		"player_position": [saved_player_position.x, saved_player_position.y],
		"health": saved_health,
		"shield": saved_shield,
		"last_outcome": last_outcome,
		"experience_gained": run_experience_gained,
		"items_gained": run_items_gained.duplicate(),
		"moves_learned": run_moves_learned.duplicate(),
	}


func load_save_data(data: Dictionary) -> void:
	run_active = bool(data.get("run_active", false))
	var loaded_map_id := str(data.get("map_id", MapCatalog.FIRST_MAP))
	current_map_id = loaded_map_id if MapCatalog.has_map(loaded_map_id) else MapCatalog.FIRST_MAP
	lives_left = clampi(int(data.get("lives_left", starting_lives)), 0, starting_lives)
	ordinary_fish = maxi(int(data.get("ordinary_fish", 0)), 0)
	objectives_total = maxi(int(data.get("objectives_total", 0)), 0)
	objectives_completed = clampi(int(data.get("objectives_completed", 0)), 0, objectives_total)
	defeated_enemy_ids.clear()
	for enemy_id in data.get("defeated_enemy_ids", []):
		defeated_enemy_ids.append(str(enemy_id))
	fish_drops = data.get("fish_drops", {}).duplicate(true)
	material_drops = data.get("material_drops", {}).duplicate(true)
	exploration_reward_claimed = bool(data.get("exploration_reward_claimed", objectives_completed >= objectives_total and objectives_total > 0))
	saved_player_position = _vector_from_data(data.get("player_position", [500.0, 350.0]))
	saved_health = float(data.get("health", -1.0))
	saved_shield = float(data.get("shield", -1.0))
	last_outcome = str(data.get("last_outcome", ""))
	# Older saves do not have the per-run summary: treat it as empty.
	run_experience_gained = maxi(int(data.get("experience_gained", 0)), 0)
	run_items_gained.clear()
	var loaded_items: Variant = data.get("items_gained", {})
	if loaded_items is Dictionary:
		for item_id in loaded_items:
			run_items_gained[str(item_id)] = maxi(int(loaded_items[item_id]), 0)
	run_moves_learned.clear()
	var loaded_moves: Variant = data.get("moves_learned", [])
	if loaded_moves is Array:
		for move_id in loaded_moves:
			if not run_moves_learned.has(str(move_id)):
				run_moves_learned.append(str(move_id))
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


func restore_debug_expedition_snapshot() -> bool:
	if _debug_snapshot.is_empty():
		return _debug_player_snapshot.is_empty()
	load_save_data(_debug_snapshot)
	return true


func complete_debug_session() -> void:
	_debug_snapshot.clear()
	_debug_player_snapshot.clear()


func restore_debug_player_snapshot() -> bool:
	if _debug_player_snapshot.is_empty():
		return true
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path != str(_debug_player_snapshot.get("scene_path", "")):
		return false
	var player := get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player):
		return false
	if not bool(_debug_player_snapshot["dead"]) and bool(player.get("dead")) and player.has_method("revive_from_expedition"):
		player.revive_from_expedition(_debug_player_snapshot["position"])
	elif player.has_method("mark_position_discontinuity"):
		player.mark_position_discontinuity()
	player.global_position = _debug_player_snapshot["position"]
	player.set("current_health", _debug_player_snapshot["health"])
	player.set("shield_durability", _debug_player_snapshot["shield"])
	player.set("dead", _debug_player_snapshot["dead"])
	var combat := player.get_node_or_null("PlayerCombat")
	if is_instance_valid(combat) and combat.has_method("set_combat_enabled"):
		combat.set_combat_enabled(not bool(_debug_player_snapshot["dead"]))
	if player.has_signal("health_changed"):
		player.health_changed.emit(player.current_health, player.max_health)
	return true
