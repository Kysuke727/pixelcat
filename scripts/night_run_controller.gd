extends Node

@onready var exit_gate: Area2D = get_parent().get_node("NightExit")
@onready var objective_label: Label = get_parent().get_node("ExpeditionHUD/Panel/Status")


func _ready() -> void:
	call_deferred("_initialize_run")


func _initialize_run() -> void:
	if not ExpeditionManager.run_active:
		return
	var enemy_ids: Array[String] = []
	var enemies := get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		var enemy_id := String(enemy.name)
		enemy_ids.append(enemy_id)
		if ExpeditionManager.defeated_enemy_ids.has(enemy_id):
			enemy.set_physics_process(false)
			enemy.set_process(false)
			enemy.set_deferred("visible", false)
			enemy.queue_free()
		elif enemy.has_signal("died"):
			enemy.died.connect(_on_enemy_died.bind(enemy_id), CONNECT_ONE_SHOT)
	ExpeditionManager.set_objectives(enemy_ids)
	var player := get_tree().get_first_node_in_group("player")
	if is_instance_valid(player):
		ExpeditionManager.restore_player_if_resuming(player)
	ExpeditionManager.expedition_changed.connect(_refresh)
	_refresh()


func _on_enemy_died(_enemy: Node, enemy_id: String) -> void:
	var reward := 0
	if is_instance_valid(_enemy):
		reward = int(_enemy.get("experience_reward"))
	ExpeditionManager.complete_enemy_objective(enemy_id, reward)
	_refresh()


func _refresh() -> void:
	if not is_instance_valid(objective_label):
		return
	var ready_to_leave := ExpeditionManager.objectives_complete()
	exit_gate.set_deferred("monitoring", ready_to_leave)
	exit_gate.set_deferred("monitorable", ready_to_leave)
	objective_label.text = "夜晚探索  ·  生命 %d/2  ·  目标 %d/%d  ·  本次小鱼干 %d\n%s" % [
		ExpeditionManager.lives_left,
		ExpeditionManager.objectives_completed,
		ExpeditionManager.objectives_total,
		ExpeditionManager.ordinary_fish,
		"出口已开启：进入右侧蓝色门撤离" if ready_to_leave else "击败全部史莱姆后开启出口",
	]


func force_complete_objectives() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		ExpeditionManager.complete_enemy_objective(String(enemy.name))
	_refresh()
