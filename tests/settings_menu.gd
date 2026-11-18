extends SceneTree

# Settings screen: Esc opens / closes it (and pauses), volume buses, key rebinding with swap,
# reserved keys refused, persistence, effect toggles.

var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _esc() -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = KEY_ESCAPE
	e.pressed = true
	return e


func _run() -> void:
	var sm = root.get_node("SettingsMenu")
	sm.config_path = "user://settings_test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(sm.config_path))
	var hit = root.get_node("HitFeel")

	_check(AudioServer.get_bus_index("Music") != -1 and AudioServer.get_bus_index("SFX") != -1, "Music and SFX buses exist")
	var bgm := AudioStreamPlayer.new()
	bgm.name = "NightMusic"
	var fx := AudioStreamPlayer.new()
	fx.name = "Hit"
	root.add_child(bgm)
	root.add_child(fx)
	_check(bgm.bus == &"Music" and fx.bus == &"SFX", "players are routed to the Music / SFX bus by name")

	# --- Esc toggles, pausing the game ---------------------------------------------------------
	_check(not sm.is_open() and not paused, "closed at start")
	sm._input(_esc())
	_check(sm.is_open() and paused, "Esc opens the settings and pauses")
	sm._input(_esc())
	_check(not sm.is_open() and not paused, "Esc again closes and resumes")
	paused = true
	sm.open()
	sm.close()
	_check(paused, "closing restores a pause that was already on")
	paused = false

	# --- volume --------------------------------------------------------------------------------
	sm.set_volume("Music", 0.5)
	_check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")), linear_to_db(0.5)), "music volume sets the bus")
	sm.set_volume("SFX", 0.0)
	_check(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "volume 0 mutes the bus")
	sm.set_volume("Master", 2.0)
	_check(is_equal_approx(float(sm.values["master"]), 1.0), "volume is clamped")

	# --- key binding -----------------------------------------------------------------------------
	_check(sm.get_key("melee_attack") == KEY_J and sm.get_key("shield_bash") == KEY_H, "default keys are J and H")
	_check(sm.rebind("melee_attack", KEY_U), "rebinding J to U works")
	_check(sm.get_key("melee_attack") == KEY_U, "...the action now uses U")
	_check(InputMap.action_get_events("melee_attack").size() == 1, "...and has exactly one key event")
	_check(sm.rebind("ranged_attack", KEY_U), "binding K to U (taken) works")
	_check(sm.get_key("ranged_attack") == KEY_U and sm.get_key("melee_attack") == KEY_K, "...and swaps the two skills")
	_check(not sm.rebind("defend", KEY_W), "movement keys are refused")
	_check(not sm.rebind("defend", KEY_ESCAPE), "Esc is refused")
	_check(not sm.rebind("defend", KEY_1), "quickbar keys are refused")
	_check(sm.get_key("defend") == KEY_Z, "a refused key leaves the binding alone")
	sm.rebind("dodge", KEY_Q)
	_check(sm.get_key("dodge") == KEY_Q, "dodge (was Shift) can be rebound")

	# --- listening flow ----------------------------------------------------------------------------
	sm.open()
	sm.listening_action = "dash"
	var e := InputEventKey.new()
	e.physical_keycode = KEY_R
	e.pressed = true
	sm._input(e)
	_check(sm.get_key("dash") == KEY_R and sm.listening_action == "", "pressing a key while listening binds it")
	sm.listening_action = "dash"
	sm._input(_esc())
	_check(sm.listening_action == "" and sm.get_key("dash") == KEY_R and sm.is_open(), "Esc while listening only cancels")
	sm.close()

	# --- persistence --------------------------------------------------------------------------------
	sm.values["screen_shake"] = false
	sm.save_settings()
	var saved_keys: Dictionary = sm.values["keys"].duplicate()
	sm.values["keys"] = {}
	sm.values["screen_shake"] = true
	sm.load_settings()
	_check(not bool(sm.values["screen_shake"]) and sm.values["keys"] == saved_keys, "settings are saved and loaded")
	sm.apply_all()
	_check(not hit.screen_shake_enabled, "the shake toggle reaches HitFeel")
	sm.reset_keys()
	_check(sm.get_key("melee_attack") == KEY_J and sm.get_key("dodge") == KEY_SHIFT and sm.get_key("dash") == KEY_SPACE, "reset restores the default keys")
	_check(sm.values["keys"].is_empty(), "...and forgets the overrides")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(sm.config_path))
	if failures.is_empty():
		print("SETTINGS_MENU_PASSED: %d checks" % checks)
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
