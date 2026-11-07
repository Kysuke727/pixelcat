extends Node

const DayStateBonuses = preload("res://scripts/day_state_bonuses.gd")

enum TimeState {
	DAY,
	NIGHT
}

const DAY_SCENE = "res://scenes/main.tscn"
const NIGHT_SCENE = "res://scenes/worlds/night_world.tscn"

var current_state: int = TimeState.DAY
var saved_hunger: float = 100.0
var saved_mood: float = 100.0
var saved_energy: float = 100.0
var night_state_snapshot: Dictionary = {}
var scene_change_override: Callable


func _ready() -> void:
	print("DayManager 已启动")
	# ProgressionManager may load the profile before this autoload is ready.
	# Consume any day-state payload it left behind, then restore the scene once
	# the main scene has entered the tree.
	var pending_state: Dictionary = ProgressionManager.consume_pending_day_state()
	if not pending_state.is_empty():
		load_save_data(pending_state)
	call_deferred("_resume_saved_expedition")


## Persistent autoload owns post-transition work; the menu node is freed on change_scene.
func enter_from_menu(scene_path: String, save_after: bool) -> void:
	var tree := get_tree()
	var error: Error = _request_scene_change(scene_path)
	if error != OK:
		push_error("无法进入游戏，错误码：%d" % error)
		return
	await tree.scene_changed
	restore_cat_stats(tree.current_scene)
	if save_after:
		ProgressionManager.save_now()


func switch_to_night() -> void:
	if current_state == TimeState.NIGHT or ProgressionManager.debug_session:
		return
	var expedition_before := ExpeditionManager.get_save_data().duplicate(true)
	capture_cat_stats()
	set_night_snapshot(_snapshot_from_saved_stats())
	if not ExpeditionManager.run_active:
		ExpeditionManager.begin_run()

	current_state = TimeState.NIGHT
	print("现在进入夜晚了！")

	var error: Error = _request_scene_change(NIGHT_SCENE)
	if error != OK:
		print("夜晚场景切换失败：", error)
		current_state = TimeState.DAY
		night_state_snapshot.clear()
		ExpeditionManager.load_save_data(expedition_before)
		ProgressionManager.save_now()
		return

	await get_tree().scene_changed
	restore_cat_stats(get_tree().current_scene)
	ProgressionManager.save_now()


func switch_to_day() -> void:
	if current_state == TimeState.DAY or ProgressionManager.debug_session:
		return
	if ExpeditionManager.run_active:
		ExpeditionManager.finish_run(false)
		return

	capture_cat_stats()
	var previous_snapshot: Dictionary = night_state_snapshot.duplicate(true)
	night_state_snapshot.clear()
	current_state = TimeState.DAY
	print("现在回到白天了！")

	var error: Error = _request_scene_change(DAY_SCENE)
	if error != OK:
		print("白天场景切换失败：", error)
		current_state = TimeState.NIGHT
		night_state_snapshot = previous_snapshot
		return

	await get_tree().scene_changed
	restore_cat_stats(get_tree().current_scene)
	ProgressionManager.save_now()


func save_cat_stats() -> void:
	print("开始保存猫咪状态")
	if not capture_cat_stats():
		print("错误：找不到 Cat/Stats")
		return
	print("保存成功！")
	print("Hunger: ", saved_hunger)
	print("Mood: ", saved_mood)
	print("Energy: ", saved_energy)


## Copies the live daytime stats into the persisted fields without printing.
## Returns false when the current scene has no Cat/Stats node.
func capture_cat_stats() -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return false
	var stats := scene.get_node_or_null("Cat/Stats")
	if stats == null:
		return false
	saved_hunger = clampf(float(stats.get("hunger")), 0.0, 100.0)
	saved_mood = clampf(float(stats.get("mood")), 0.0, 100.0)
	saved_energy = clampf(float(stats.get("energy")), 0.0, 100.0)
	return true


func restore_cat_stats(scene: Node) -> void:
	print("开始恢复猫咪状态")
	if scene == null:
		print("恢复失败：场景为空")
		return
	var cat := scene.get_node_or_null("Cat")
	if cat == null:
		print("恢复失败：找不到 Cat")
		return
	var stats := cat.get_node_or_null("Stats")
	if stats == null:
		print("恢复失败：找不到 Stats")
		return
	stats.hunger = saved_hunger
	stats.mood = saved_mood
	stats.energy = saved_energy
	print("恢复状态成功！")
	print("Hunger: ", stats.hunger)
	print("Mood: ", stats.mood)
	print("Energy: ", stats.energy)


func set_night_snapshot(snapshot: Dictionary) -> void:
	night_state_snapshot = _sanitize_snapshot(snapshot)


func clear_night_snapshot() -> void:
	night_state_snapshot.clear()


func has_night_snapshot() -> bool:
	return not night_state_snapshot.is_empty()


func get_night_modifiers() -> Dictionary:
	if current_state != TimeState.NIGHT or night_state_snapshot.is_empty():
		return DayStateBonuses.neutral()
	return DayStateBonuses.compute(night_state_snapshot)


func get_night_attack_multiplier() -> float:
	return float(get_night_modifiers()["attack_multiplier"])


func get_night_movement_multiplier() -> float:
	return float(get_night_modifiers()["movement_multiplier"])


func get_night_max_health_bonus() -> int:
	return int(get_night_modifiers()["max_health_bonus"])


func get_save_data() -> Dictionary:
	return {
		"hunger": saved_hunger,
		"mood": saved_mood,
		"energy": saved_energy,
		"night_snapshot": night_state_snapshot.duplicate(true),
	}


func load_save_data(data: Dictionary) -> void:
	if data.is_empty():
		saved_hunger = 100.0
		saved_mood = 100.0
		saved_energy = 100.0
		night_state_snapshot.clear()
		return
	saved_hunger = clampf(_read_number(data, "hunger", 100.0), 0.0, 100.0)
	saved_mood = clampf(_read_number(data, "mood", 100.0), 0.0, 100.0)
	saved_energy = clampf(_read_number(data, "energy", 100.0), 0.0, 100.0)
	night_state_snapshot = _sanitize_snapshot(data.get("night_snapshot", {}))


func _snapshot_from_saved_stats() -> Dictionary:
	return {
		"hunger": saved_hunger,
		"mood": saved_mood,
		"energy": saved_energy,
	}


func _sanitize_snapshot(value: Variant) -> Dictionary:
	if not value is Dictionary or value.is_empty():
		return {}
	return {
		"hunger": clampf(_read_number(value, "hunger", saved_hunger), 0.0, 100.0),
		"mood": clampf(_read_number(value, "mood", saved_mood), 0.0, 100.0),
		"energy": clampf(_read_number(value, "energy", saved_energy), 0.0, 100.0),
	}


func _read_number(data: Dictionary, key: String, fallback: float) -> float:
	var value: Variant = data.get(key, fallback)
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return fallback
	return float(value)


func _request_scene_change(scene_path: String) -> Error:
	if scene_change_override.is_valid():
		return int(scene_change_override.call(scene_path))
	return get_tree().change_scene_to_file(scene_path)


func _input(event):
	if event is InputEventKey:
		if event.pressed and not event.echo:
			if event.keycode == KEY_N:
				switch_to_night()
			elif event.keycode == KEY_B and current_state == TimeState.DAY:
				switch_to_day()


func _resume_saved_expedition() -> void:
	if get_tree().current_scene != null and get_tree().current_scene.scene_file_path == "res://scenes/menu/main_menu.tscn":
		return
	if ProgressionManager.debug_session:
		return
	if ExpeditionManager.run_active and current_state == TimeState.DAY:
		# New saves carry the night snapshot. Older saves without one stay
		# neutral instead of silently turning default 100 stats into bonuses.
		current_state = TimeState.NIGHT
		var error: Error = _request_scene_change(NIGHT_SCENE)
		if error != OK:
			current_state = TimeState.DAY
			push_error("保存的夜晚探索无法恢复；保留存档并回到白天")
			return
		await get_tree().scene_changed
		restore_cat_stats(get_tree().current_scene)
		ProgressionManager.save_now()
		return
	if current_state == TimeState.DAY:
		clear_night_snapshot()
		restore_cat_stats(get_tree().current_scene)
