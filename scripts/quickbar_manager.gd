
extends Node

signal quickbar_changed
signal quickbar_slot_changed(slot_index: int)

const SLOT_COUNT: int = 4

# 每个槽位只保存物品 ID，不保存数量
var bound_item_ids: Array[String] = ["", "", "", ""]


func _ready() -> void:
	# 确保快捷栏固定为 4 个槽位
	if bound_item_ids.size() != SLOT_COUNT:
		bound_item_ids.resize(SLOT_COUNT)


# 检查槽位索引
func _is_valid_slot_index(slot_index: int) -> bool:
	return slot_index >= 0 and slot_index < SLOT_COUNT


# 绑定物品到快捷栏
func bind_item(slot_index: int, item_id: String) -> bool:
	if not _is_valid_slot_index(slot_index):
		push_warning("快捷栏索引无效：" + str(slot_index))
		return false

	if item_id.is_empty():
		return clear_slot(slot_index)

	# 必须是已注册的物品
	var item: ItemData = InventoryManager.get_item_data(item_id)

	if item == null:
		push_warning("快捷栏无法绑定未知物品：" + item_id)
		return false

	# V1.1：只允许绑定标记为可使用的物品
	if not item.usable:
		push_warning("该物品不可使用，不能绑定快捷栏：" + item_id)
		return false

	# 允许同一物品绑定多个槽位
	# 替换绑定时不改变背包数量
	bound_item_ids[slot_index] = item_id

	quickbar_slot_changed.emit(slot_index)
	quickbar_changed.emit()
	return true


# 清空指定槽位
func clear_slot(slot_index: int) -> bool:
	if not _is_valid_slot_index(slot_index):
		push_warning("快捷栏索引无效：" + str(slot_index))
		return false

	if bound_item_ids[slot_index].is_empty():
		return true

	bound_item_ids[slot_index] = ""

	quickbar_slot_changed.emit(slot_index)
	quickbar_changed.emit()
	return true


# 获取槽位绑定的物品 ID
func get_bound_item_id(slot_index: int) -> String:
	if not _is_valid_slot_index(slot_index):
		return ""

	return bound_item_ids[slot_index]


# 获取槽位绑定的物品数据
func get_bound_item_data(slot_index: int) -> ItemData:
	var item_id: String = get_bound_item_id(slot_index)

	if item_id.is_empty():
		return null

	return InventoryManager.get_item_data(item_id)


# 实时查询背包数量，不在快捷栏重复保存数量
func get_bound_item_count(slot_index: int) -> int:
	var item_id: String = get_bound_item_id(slot_index)

	if item_id.is_empty():
		return 0

	return InventoryManager.get_item_count(item_id)


# 判断绑定物品当前是否有库存
func has_usable_quantity(slot_index: int) -> bool:
	var item: ItemData = get_bound_item_data(slot_index)

	if item == null:
		return false

	if not item.usable:
		return false

	return get_bound_item_count(slot_index) > 0


# 保存快捷栏数据
func get_save_data() -> Array[String]:
	var save_data: Array[String] = []

	for item_id in bound_item_ids:
		save_data.append(item_id)

	return save_data


# 加载快捷栏数据
func load_save_data(data: Array) -> void:
	bound_item_ids = ["", "", "", ""]

	for i in range(min(data.size(), SLOT_COUNT)):
		var item_id: String = str(data[i])

		if item_id.is_empty():
			continue

		var item: ItemData = InventoryManager.get_item_data(item_id)

		# 无效、已删除或不可使用的物品不恢复绑定
		if item == null or not item.usable:
			push_warning("忽略无效的快捷栏绑定：" + item_id)
			continue

		bound_item_ids[i] = item_id

	quickbar_changed.emit()
