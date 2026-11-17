extends SceneTree

# The compact night battle HUD (replaces the old 260x206 default-styled panel).

var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _rect(control: Control) -> Rect2:
	return Rect2(control.global_position, control.size)


func _run() -> void:
	var pm = root.get_node("ProgressionManager")
	pm._test_mode = true
	pm._load_profile_data({})
	var scene: Node = load("res://scenes/worlds/night_world.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for _i in range(4):
		await process_frame
	var hud = get_first_node_in_group("battle_ui")
	var player = get_first_node_in_group("player")
	var coin: Control = scene.get_node("CoinUI/PanelContainer")
	var strip: Control = hud.get_node("Strip")

	# --- Size and placement -------------------------------------------------------------
	var strip_rect := _rect(strip)
	_check(strip_rect.size.x <= 230.0 and strip_rect.size.y <= 110.0, "the status strip is compact (%s; the old panel was 260 x 206)" % str(strip_rect.size))
	_check(strip_rect.position.x <= 12.0 and strip_rect.position.y <= 12.0, "it sits in the top-left corner")
	_check(not strip_rect.intersects(_rect(coin)), "the fish counter no longer overlaps it")
	_check(_rect(coin).position.x >= strip_rect.end.x, "the fish counter is to its right")
	var expedition: Control = scene.get_node("ExpeditionHUD/Panel")
	_check(not strip_rect.intersects(_rect(expedition)) and not _rect(coin).intersects(_rect(expedition)), "the expedition panel overlaps nothing")
	# Headless runs have no real window (the root is 64 x 64), so use the project's viewport size.
	var screen := Vector2(float(ProjectSettings.get_setting("display/window/size/viewport_width", 1152)), float(ProjectSettings.get_setting("display/window/size/viewport_height", 648)))
	var panel_rect := _rect(expedition)
	_check(panel_rect.position.x >= 0.0 and panel_rect.position.y >= 0.0 and panel_rect.end.x <= screen.x and panel_rect.end.y <= screen.y, "the expedition panel stays on screen (panel %s, screen %s)" % [str(panel_rect), str(screen)])
	_check(strip.theme_type_variation == &"HudPanel" and expedition.theme_type_variation == &"HudPanel", "both use the shared HUD panel style")

	# --- Contents ---------------------------------------------------------------------------
	_check(hud.player_hp_bar.max_value == player.max_health and hud.player_hp_bar.value == player.current_health, "the HP bar matches the cat")
	_check(hud.hp_label.text == "%d/%d" % [int(player.current_health), int(player.max_health)], "HP is also written as a number (%s)" % hud.hp_label.text)
	player.current_health = 2.0
	player.health_changed.emit(2.0, float(player.max_health))
	_check(hud.player_hp_bar.value == 2.0 and hud.hp_label.text.begins_with("2/"), "taking damage updates the bar and the number")
	player.current_health = float(player.max_health)
	player.health_changed.emit(player.current_health, float(player.max_health))
	hud._update_combat_readout()
	_check(hud.shield_label.text == "%d" % ceili(player.shield_durability) and hud.shield_bar.value == player.shield_durability, "the shield shows as a bar and a number")
	_check(hud.shield_bar.theme_type_variation == &"ShieldBar", "the shield bar has its own colour")
	player.shield_durability = 40.0
	hud._update_combat_readout()
	_check(hud.shield_label.text == "40" and hud.shield_bar.value == 40.0, "the shield updates")
	player.guard_break_left = 1.2
	hud._update_combat_readout()
	_check(hud.shield_bar.theme_type_variation == &"LowBar" and hud.combat_feedback.text.contains("防御破碎"), "a broken guard turns the shield bar red and says so")
	player.guard_break_left = 0.0
	hud._update_combat_readout()
	_check(hud.shield_bar.theme_type_variation == &"ShieldBar", "...and back to normal afterwards")
	_check(hud.dash_label.text.contains("冲刺") and hud.dash_label.text.contains("闪避"), "dash charges and dodge state are shown")
	_check(hud.yarn_label.text.begins_with("黏黏球"), "the yarn ball state is shown")
	player.dodge_cooldown_left = 6.2
	hud._update_combat_readout()
	_check(hud.dash_label.text.contains("冷却 7s"), "the dodge cooldown counts down (%s)" % hud.dash_label.text)
	player.dodge_cooldown_left = 0.0

	# --- The message bar -------------------------------------------------------------------------
	hud._elapsed = 0.0
	hud._update_combat_readout()
	_check(hud.feedback_panel.visible and hud.combat_feedback.text.contains("J 爪击"), "at the start the key reminder is shown")
	hud._elapsed = 60.0
	hud._update_combat_readout()
	_check(not hud.feedback_panel.visible, "after the first seconds the idle reminder folds away")
	player.slip_time_left = 0.4
	hud._update_combat_readout()
	_check(hud.feedback_panel.visible and hud.combat_feedback.text.contains("滑倒"), "a real message shows up even after that")
	player.slip_time_left = 0.0
	hud._update_combat_readout()
	_check(not hud.feedback_panel.visible, "...and folds away again when it is over")

	# --- The enemy bar ----------------------------------------------------------------------------
	_check(not hud.enemy_panel.visible, "no enemy bar when nothing is targeted")
	var slime: Node = get_nodes_in_group("enemies")[0]
	hud.show_enemy(slime, "史莱姆", 3.0, 5.0)
	_check(hud.enemy_panel.visible and hud.enemy_name.text == "史莱姆" and hud.enemy_hp_bar.value == 3.0 and hud.enemy_hp_bar.max_value == 5.0, "targeting an enemy shows its name and health")
	hud.hide_enemy(get_nodes_in_group("enemies")[1])
	_check(hud.enemy_panel.visible, "hiding some other enemy does nothing")
	hud.hide_enemy(slime)
	_check(not hud.enemy_panel.visible, "hiding the targeted enemy hides the bar")
	_check(hud.enemy_hp_bar.theme_type_variation == &"EnemyBar", "the enemy bar has its own colour")

	# --- Real hit shows the enemy bar ------------------------------------------------------------------
	for enemy in get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
	var target: Node = get_nodes_in_group("enemies")[0]
	target.receive_damage(1.0, player.global_position, 0.0)
	_check(hud.enemy_panel.visible and hud.shown_enemy == target, "hitting a slime for real shows its bar")

	if failures.is_empty():
		print("BATTLE_HUD_PASSED: %d checks" % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", description)
	else:
		failures.append(description)
