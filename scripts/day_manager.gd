
extends Node

enum TimeState {
	DAY,
	NIGHT
}

var current_state = TimeState.DAY

const DAY_SCENE = "res://scenes/main.tscn"
const NIGHT_SCENE = "res://scenes/worlds/night_world.tscn"

var saved_hunger: float = 100.0
var saved_mood: float = 100.0
var saved_energy: float = 100.0
var scene_change_override: Callable



func switch_to_night():
	if current_state == TimeState.NIGHT or ProgressionManager.debug_session:
		return
	var expedition_before := ExpeditionManager.get_save_data().duplicate(true)
	if not ExpeditionManager.run_active:
		ExpeditionManager.begin_run()

	save_cat_stats()
	current_state = TimeState.NIGHT

	print("现在进入夜晚了！")

	var error: Error = _request_scene_change(NIGHT_SCENE)
	if error != OK:
		print("夜晚场景切换失败：", error)
		current_state = TimeState.DAY
		ExpeditionManager.load_save_data(expedition_before)
		ProgressionManager.save_now()
		return
	await get_tree().scene_changed
	restore_cat_stats(get_tree().current_scene)







func switch_to_day():
	if current_state == TimeState.DAY or ProgressionManager.debug_session:
		return
	if ExpeditionManager.run_active:
		ExpeditionManager.finish_run(false)
		return

	save_cat_stats()
	current_state = TimeState.DAY

	print("现在回到白天了！")

	var error: Error = _request_scene_change(DAY_SCENE)
	if error != OK:
		print("白天场景切换失败：", error)
		current_state = TimeState.NIGHT
		return

	
	await get_tree().scene_changed
	restore_cat_stats(get_tree().current_scene)





func save_cat_stats():
	print("开始保存猫咪状态")

	var cat = get_tree().current_scene.get_node_or_null("Cat")

	if cat == null:
		print("错误：找不到 Cat")
		return

	var stats = cat.get_node_or_null("Stats")

	if stats == null:
		print("错误：找不到 Stats")
		return

	saved_hunger = stats.hunger
	saved_mood = stats.mood
	saved_energy = stats.energy

	print("保存成功！")
	print("Hunger: ", saved_hunger)
	print("Mood: ", saved_mood)
	print("Energy: ", saved_energy)





func restore_cat_stats(scene):
	print("开始恢复猫咪状态")

	if scene == null:
		print("恢复失败：场景为空")
		return

	var cat = scene.get_node_or_null("Cat")

	if cat == null:
		print("恢复失败：找不到 Cat")
		return

	var stats = cat.get_node_or_null("Stats")

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


func _ready():
	print("DayManager 已启动")
	call_deferred("_resume_saved_expedition")


func _resume_saved_expedition() -> void:
	if ExpeditionManager.run_active and current_state == TimeState.DAY and not ProgressionManager.debug_session:
		current_state = TimeState.NIGHT
		var error: Error = _request_scene_change(NIGHT_SCENE)
		if error != OK:
			current_state = TimeState.DAY
			push_error("保存的夜晚探索无法恢复；保留存档并回到白天")
			return
		await get_tree().scene_changed
		restore_cat_stats(get_tree().current_scene)
