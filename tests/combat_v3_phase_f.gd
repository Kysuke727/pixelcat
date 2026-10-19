extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var test_scene: Node = load("res://scenes/combat_v3_test.tscn").instantiate()
	root.add_child(test_scene)
	current_scene = test_scene
	await physics_frame
	var player := get_first_node_in_group("player")
	var combat = player.get_node("PlayerCombat")
	var ui := get_first_node_in_group("battle_ui")
	_check(test_scene.is_in_group("night_exploration"), "dedicated test scene enables night-only combat")
	_check(player != null and combat != null, "test scene contains a playable cat and combat controller")
	_check(
		test_scene.get_node_or_null("NightWorld/SlimeA") != null
			and test_scene.get_node_or_null("NightWorld/SlimeB") != null,
		"test scene contains multiple slime targets"
	)
	_check(test_scene.get_node_or_null("NightWorld/Walls") != null, "test scene includes real wall collision geometry")
	_check(ui != null and ui.get_node_or_null("PanelContainer/VBoxContainer/ShieldBar") != null, "battle HUD includes shield durability")
	_check(ui.get_node_or_null("PanelContainer/VBoxContainer/YarnLabel") != null, "battle HUD includes yarn cooldown/connection feedback")
	_check(ui.get_node_or_null("PanelContainer/VBoxContainer/CombatFeedback") != null, "battle HUD includes defense and perfect-guard feedback")
	var slime_scene: Node = load("res://scenes/enemies/slime.tscn").instantiate()
	_check(
		slime_scene.get_node_or_null("StatusFeedback") != null,
		"slime scene includes status feedback for stun, bind, hit and slow"
	)
	slime_scene.free()
	_check(test_scene.get_node_or_null("DebugLayer/Panel/DebugLabel") != null, "combat test scene exposes live debug status")
	_check(combat._can_start_action(), "combat actions are permitted in the dedicated test scene")
	player.perfect_guard_flash_left = 0.2
	ui._update_combat_readout()
	_check(ui.get_node("PanelContainer/VBoxContainer/CombatFeedback").text == "完美防御！", "HUD displays perfect guard feedback")
	player.perfect_guard_flash_left = 0.0
	player.guard_break_left = 1.0
	ui._update_combat_readout()
	_check(ui.get_node("PanelContainer/VBoxContainer/CombatFeedback").text.begins_with("防御破碎"), "HUD displays guard-break recovery")
	player.guard_break_left = 0.0
	var status_label: Label = test_scene.get_node("DebugLayer/Panel/DebugLabel")
	_check(status_label.text.contains("COMBAT V3 TEST"), "debug overlay renders its input and status guide")

	for audio_player in test_scene.find_children("*", "AudioStreamPlayer2D", true, false):
		audio_player.stop()
		audio_player.stream = null
	test_scene.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.25).timeout
	if failures.is_empty():
		print("COMBAT_V3_PHASE_F_PASSED")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		failures.append(description)
