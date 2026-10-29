extends Node2D

@onready var debug_label: Label = $DebugLayer/Panel/DebugLabel


func _process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		debug_label.text = "Combat V3 Test · 等待玩家"
		return
	var enemies := get_tree().get_nodes_in_group("enemies")
	var status := "正常"
	if player.get("dead"):
		status = "死亡"
	elif player.get("guard_break_left") > 0.0:
		status = "破防 %.1fs" % float(player.get("guard_break_left"))
	elif player.get("perfect_guard_flash_left") > 0.0:
		status = "完美防御"
	elif player.get("is_defending"):
		status = "防御中"
	var bound_count := 0
	for enemy in enemies:
		if float(enemy.get("bind_time_left")) > 0.0:
			bound_count += 1
	debug_label.text = (
		"COMBAT V3 TEST\nWASD 移动 · J 连爪 · K 黏黏球 · Z 防御\n"
		+ "史莱姆：%d · 束缚中：%d\n状态：%s · 护盾：%.0f / %.0f"
		% [enemies.size(), bound_count, status, float(player.get("shield_durability")), float(player.get("shield_max_durability"))]
	)
