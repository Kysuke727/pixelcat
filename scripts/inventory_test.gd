extends Node


func _ready() -> void:
	print("========== 背包测试开始 ==========")

	# 检查背包管理器
	if not is_instance_valid(InventoryManager):
		print("错误：找不到 InventoryManager")
		return

	print("背包管理器加载成功")

	# 检查格子数量
	print("背包格子数量：", InventoryManager.get_slot_count())

	# 检查物品资源
	var wood = InventoryManager.get_item_data("wood")
	var stone = InventoryManager.get_item_data("stone")
	var yarn = InventoryManager.get_item_data("yarn")

	print("木材资源：", wood)
	print("石头资源：", stone)
	print("毛线资源：", yarn)

	# 检查物品是否存在
	if wood == null or stone == null or yarn == null:
		print("测试失败：有物品资源没有正确注册")
		return

	print("三种物品资源注册成功")

	# 添加 10 个木材
	var add_result = InventoryManager.add_item(wood, 10)
	print("添加木材结果：", add_result)

	# 查询木材数量
	print(
		"当前木材数量：",
		InventoryManager.get_item_count("wood")
	)

	# 移除 3 个木材
	var remove_result = InventoryManager.remove_item("wood", 3)
	print("移除木材结果：", remove_result)

	# 再次查询
	print(
		"移除后木材数量：",
		InventoryManager.get_item_count("wood")
	)

	print("========== 背包测试结束 ==========")
