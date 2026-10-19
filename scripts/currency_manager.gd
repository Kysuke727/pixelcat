extends Node

signal fish_changed(new_amount: int)

var fish_count: int = 0


func add_fish(amount: int) -> void:
	if amount <= 0:
		return
	if is_instance_valid(ExpeditionManager) and ExpeditionManager.run_active:
		ExpeditionManager.add_ordinary_fish(amount)
		return
	add_permanent_fish(amount)


func add_permanent_fish(amount: int) -> void:
	if amount <= 0:
		return
	fish_count += amount
	fish_changed.emit(fish_count)
	if is_instance_valid(ProgressionManager):
		ProgressionManager.save_now()


func can_afford(amount: int) -> bool:
	return amount >= 0 and fish_count >= amount


func spend_fish(amount: int) -> bool:
	if not can_afford(amount):
		return false
	fish_count -= amount
	fish_changed.emit(fish_count)
	if is_instance_valid(ProgressionManager):
		ProgressionManager.save_now()
	return true


func get_save_data() -> Dictionary:
	return {"fish_count": fish_count}


func load_save_data(data: Dictionary) -> void:
	fish_count = maxi(int(data.get("fish_count", 0)), 0)
	fish_changed.emit(fish_count)
