extends SceneTree

# Main menu: unfinished buttons are greyed out; the working ones are untouched.

var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.get_node("ProgressionManager")._test_mode = true
	var menu: Control = load("res://scenes/menu/main_menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	for path in ["GalleryButton2", "SettingsButtonButton4"]:
		var button: Button = menu.get_node("MenuPanel/MenuButtons/" + path)
		_check(button.disabled, "%s is disabled" % path)
		_check(button.tooltip_text.contains("还没做"), "%s explains why" % path)
		_check(button.modulate.a < 1.0, "%s is visibly dimmed" % path)
	for path in ["NewGameButton2", "ExitButton2"]:
		var button: Button = menu.get_node("MenuPanel/MenuButtons/" + path)
		_check(not button.disabled and is_equal_approx(button.modulate.a, 1.0), "%s is untouched" % path)
	# Continue is only available with a save (not touched by this change).
	var cont: Button = menu.get_node("MenuPanel/MenuButtons/ContinueButton")
	_check(is_equal_approx(cont.modulate.a, 1.0), "Continue keeps its normal look")

	if failures.is_empty():
		print("MENU_BUTTONS_PASSED: %d checks" % checks)
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
