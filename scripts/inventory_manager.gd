extends Node

signal inventory_changed
signal item_added(item_id: String, quantity: int)
signal item_removed(item_id: String, quantity: int)

const SLOT_COUNT: int = 24

var item_database: Dictionary = {}
var slots: Array[Dictionary] = []


func _ready() -> void:
	_register_item(preload("res://resources/items/wood.tres"))
	_register_item(preload("res://resources/items/stone.tres"))
	_register_item(preload("res://resources/items/yarn.tres"))
	_register_item(preload("res://resources/items/test_potion.tres"))

	_create_empty_slots()

	# 测试用：给背包添加物品
	add_item(get_item_data("wood"), 10)
	add_item(get_item_data("stone"), 5)
	add_item(get_item_data("yarn"), 3)
	add_item(get_item_data("test_potion"), 3)


# 注册物品
func _register_item(item: ItemData) -> void:
	if item == null:
		push_error("物品资源为空！")
		return

	if not item.is_valid_item():
		push_error("物品数据无效：" + item.resource_path)
		return

	if item_database.has(item.item_id):
		push_error("重复的物品 ID：" + item.item_id)
		return

	item_database[item.item_id] = item


# 创建 24 个空格
func _create_empty_slots() -> void:
	slots.clear()

	for i in range(SLOT_COUNT):
		slots.append({
			"item_id": "",
			"quantity": 0
		})


# 获取背包格子数量
func get_slot_count() -> int:
	return slots.size()


# 获取指定格子
func get_slot(index: int) -> Dictionary:
	if index < 0 or index >= slots.size():
		push_warning("背包格子索引超出范围：" + str(index))
		return {}

	return slots[index].duplicate(true)


# 获取物品数据
func get_item_data(item_id: String) -> ItemData:
	if not item_database.has(item_id):
		return null

	return item_database[item_id] as ItemData


# 查询某种物品的总数量
func get_item_count(item_id: String) -> int:
	var total: int = 0

	for slot in slots:
		if slot["item_id"] == item_id:
			total += int(slot["quantity"])

	return total


# 获取空格数量
func get_empty_slot_count() -> int:
	var total: int = 0

	for slot in slots:
		if slot["item_id"] == "":
			total += 1

	return total


# 计算还能放入多少个指定物品
func get_addable_quantity(item: ItemData) -> int:
	if not _is_valid_item(item):
		return 0

	var total: int = 0

	for slot in slots:
		if slot["item_id"] == item.item_id:
			var current_quantity: int = int(slot["quantity"])
			total += max(0, item.max_stack - current_quantity)

		elif slot["item_id"] == "":
			total += item.max_stack

	return total


# 检查是否能够完整放入指定数量
func can_add_item(item: ItemData, quantity: int) -> bool:
	if quantity <= 0:
		return false

	if not _is_valid_item(item):
		return false

	return get_addable_quantity(item) >= quantity


# 添加物品
func add_item(item: ItemData, quantity: int) -> Dictionary:
	if quantity <= 0:
		return {
			"success": false,
			"requested": quantity,
			"added": 0,
			"remaining": quantity,
			"reason": "invalid_quantity"
		}

	if not _is_valid_item(item):
		return {
			"success": false,
			"requested": quantity,
			"added": 0,
			"remaining": quantity,
			"reason": "invalid_item"
		}

	var remaining: int = quantity
	var added: int = 0

	# 第一轮：优先填满已有的同类物品堆
	for slot in slots:
		if slot["item_id"] != item.item_id:
			continue

		var current_quantity: int = int(slot["quantity"])
		var space: int = item.max_stack - current_quantity

		if space <= 0:
			continue

		var amount: int = min(remaining, space)

		slot["quantity"] = current_quantity + amount
		remaining -= amount
		added += amount

		if remaining == 0:
			break

	# 第二轮：将剩余物品放入空格
	if remaining > 0:
		for slot in slots:
			if slot["item_id"] != "":
				continue

			var amount: int = min(remaining, item.max_stack)

			slot["item_id"] = item.item_id
			slot["quantity"] = amount

			remaining -= amount
			added += amount

			if remaining == 0:
				break

	# 有物品成功放入时，通知界面更新
	if added > 0:
		item_added.emit(item.item_id, added)
		inventory_changed.emit()

	return {
		"success": remaining == 0,
		"requested": quantity,
		"added": added,
		"remaining": remaining,
		"reason": "" if remaining == 0 else "inventory_full"
	}


# 移除物品
func remove_item(item_id: String, quantity: int) -> Dictionary:
	if quantity <= 0:
		return {
			"success": false,
			"removed": 0,
			"reason": "invalid_quantity"
		}

	if not item_database.has(item_id):
		return {
			"success": false,
			"removed": 0,
			"reason": "invalid_item"
		}

	if get_item_count(item_id) < quantity:
		return {
			"success": false,
			"removed": 0,
			"reason": "insufficient_quantity"
		}

	var remaining: int = quantity

	for slot in slots:
		if slot["item_id"] != item_id:
			continue

		var current_quantity: int = int(slot["quantity"])
		var amount: int = min(remaining, current_quantity)

		slot["quantity"] = current_quantity - amount
		remaining -= amount

		if int(slot["quantity"]) == 0:
			slot["item_id"] = ""

		if remaining == 0:
			break

	item_removed.emit(item_id, quantity)
	inventory_changed.emit()

	return {
		"success": true,
		"removed": quantity,
		"reason": ""
	}


# 验证物品资源
func _is_valid_item(item: ItemData) -> bool:
	if item == null:
		return false

	if not item.is_valid_item():
		return false

	if not item_database.has(item.item_id):
		return false

	if item_database[item.item_id] != item:
		return false

	return true


# 获取背包保存数据
func get_save_data() -> Array[Dictionary]:
	var save_data: Array[Dictionary] = []

	for slot in slots:
		save_data.append({
			"item_id": slot["item_id"],
			"quantity": slot["quantity"]
		})

	return save_data


# 加载背包保存数据
func load_save_data(data: Array) -> void:
	# 先创建空背包，避免旧数据污染
	_create_empty_slots()

	for i in range(min(data.size(), SLOT_COUNT)):
		if not data[i] is Dictionary:
			continue

		var item_id: String = str(data[i].get("item_id", ""))
		var quantity: int = int(data[i].get("quantity", 0))

		# 空格
		if item_id == "" or quantity <= 0:
			continue

		# 不存在的物品不加载
		var item: ItemData = get_item_data(item_id)

		if item == null:
			push_warning("存档中存在未知物品：" + item_id)
			continue

		# 单格数量不能超过最大堆叠数
		if quantity > item.max_stack:
			push_warning("存档物品数量超过上限：" + item_id)
			continue

		slots[i]["item_id"] = item_id
		slots[i]["quantity"] = quantity

	inventory_changed.emit()
