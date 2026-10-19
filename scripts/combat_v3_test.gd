extends Node2D

@onready var debug_label: Label = $DebugLayer/Panel/DebugLabel


func _process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		debug_label.text = "Combat V3 Test · 等待玩家"
		return
	var enemies := get_tree().get_nodes_in_group("enemies")
	var combat := player.get_node_or_null("PlayerCombat")
	var status := "正常"
	if player.get("dead"):
		status = "死亡"
	elif player.get("guard_break_left") > 0.0:
		status = "破防 %.1fs" % float(player.get("guard_break_left"))
	elif player.get("perfect_guard_flash_left") > 0.0:
		status = "完美防御"
	elif player.get("is_defending"):
		status = "防御中"
	var yarn_count := 0
	if is_instance_valid(combat):
		for connection in combat.get("active_yarn_connections"):
			if is_instance_valid(connection):
				yarn_count += 1
	debug_label.text = (
		"COMBAT V3 TEST\nWASD 移动 · J 连爪 · K 毛线 · Q 剪线 · Z 防御\n"
		+ "史莱姆：%d · 毛线连接：%d\n状态：%s · 护盾：%.0f / %.0f"
		% [enemies.size(), yarn_count, status, float(player.get("shield_durability")), float(player.get("shield_max_durability"))]
	)
