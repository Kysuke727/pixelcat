extends SceneTree

# Growth panel: attribute rows + the moves list; retired skill points are refunded.

var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _texts(node: Node) -> String:
	var text := ""
	if node is Label:
		text += node.text + "|"
	for child in node.get_children():
		text += _texts(child)
	return text


func _run() -> void:
	var pm = root.get_node("ProgressionManager")
	pm._test_mode = true
	pm._load_profile_data({})

	# --- Retired skill points are refunded ------------------------------------------------
	pm._load_profile_data({"available_points": 2, "skill_points": {"slow": 3, "connection": 4, "bind": 5, "loop": 6}})
	_check(pm.available_points == 2 + 18, "points spent on the removed skills come back (2 + 18 = %d)" % pm.available_points)
	pm._load_profile_data({"skill_points": {"slow": 99, "connection": 99, "bind": 99, "loop": 99}})
	_check(pm.available_points == 15 + 50 + 20 + 30, "the refund is capped at what could ever have been spent (%d)" % pm.available_points)
	pm._load_profile_data({"skill_points": {"slow": -5, "bind": 2}})
	_check(pm.available_points == 2, "negative or missing entries refund nothing extra (%d)" % pm.available_points)
	pm._load_profile_data({"skill_points": "garbage"})
	_check(pm.available_points == 0, "a malformed skill_points value refunds nothing and does not crash")
	pm._load_profile_data({"available_points": 3})
	_check(pm.available_points == 3, "a new-format profile is not refunded anything")
	_check(pm.attributes.keys() == ["vitality", "attack", "defense", "agility"], "the four attributes remain, no technique")
	var saved: Dictionary = pm._profile_data()
	_check(not saved.has("skill_points"), "saving no longer writes skill_points")
	_check(pm._is_usable_current_profile(saved), "a new-format profile (without skill_points) is accepted when loading")
	var legacy: Dictionary = saved.duplicate(true)
	legacy["skill_points"] = {"slow": 1, "connection": 2, "bind": 3, "loop": 4}
	_check(pm._is_usable_current_profile(legacy), "an old profile (with skill_points) is still accepted")
	legacy["skill_points"] = "x"
	_check(not pm._is_usable_current_profile(legacy), "a corrupt skill_points value is still rejected")
	pm._load_profile_data({"available_points": 4, "attributes": {"vitality": 2, "attack": 1}})
	pm.attributes["agility"] = 3
	var points_before: int = pm.available_points
	root.get_node("CurrencyManager").fish_count = 1000
	_check(pm.respec_attributes(), "respec works")
	_check(pm.available_points == points_before + 2 + 1 + 3, "respec refunds the attribute points only")
	_check(not pm.has_method("allocate_point") or not pm.allocate_point("slow"), "there is no 'slow' branch to put a point into")

	# --- The panel ---------------------------------------------------------------------------
	pm._load_profile_data({"level": 3, "available_points": 2})
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var layer = scene.get_node("ProgressionPanel")
	_check(layer.rows.size() == 4 and layer.rows.has("vitality") and layer.rows.has("agility") and not layer.rows.has("slow"), "the panel has the four attribute rows and no skill rows")
	var text: String = _texts(layer.panel)
	_check(not text.contains("技巧") and not text.contains("减速") and not text.contains("束缚") and not text.contains("绕圈") and not text.contains("连接"), "no trace of the old skill branches in the panel text")
	_check(text.contains("招式"), "the panel has a moves section")
	var mysteries := text.count("？？？")
	_check(mysteries == 4, "nothing learned yet: four mystery entries (%d)" % mysteries)
	_check(not text.contains("✓"), "no learned marks yet")
	pm.unlock_move("pounce")
	await process_frame
	text = _texts(layer.panel)
	_check(text.contains("✓ 扑击") and text.contains("冲刺后 J"), "a learned move shows its name and key")
	_check(text.contains("冲刺之后马上按 J"), "...and its description")
	_check(text.count("？？？") == 3, "the others stay a mystery")
	pm.unlock_move("triple_combo")
	pm.unlock_move("counter_claw")
	pm.unlock_move("shield_bash")
	await process_frame
	text = _texts(layer.panel)
	_check(text.count("？？？") == 0 and text.count("✓") == 4, "all learned: no mysteries left")

	# The little Lv/XP strip.
	var hud_text: String = layer.hud_label.text
	_check(hud_text.contains("Lv.3") and hud_text.contains("2 个属性点"), "the top strip shows the level and unspent points (%s)" % hud_text)
	_check(not hud_text.contains("F3"), "the top strip no longer advertises the debug key")
	pm.available_points = 0
	pm.progression_changed.emit()
	_check(not layer.hud_label.text.contains("属性点"), "...and says nothing about points when there are none")

	# Allocating still works.
	pm.available_points = 2
	pm.begin_allocation()
	layer.rows["attack"]["plus"].pressed.emit()
	_check(int(pm.pending_allocation["attributes"]["attack"]) == 1, "the + button drafts a point")
	layer.rows["attack"]["minus"].pressed.emit()
	_check(int(pm.pending_allocation["attributes"]["attack"]) == 0, "the - button takes it back")
	layer.rows["vitality"]["plus"].pressed.emit()
	layer._commit()
	_check(pm.attributes["vitality"] == 1 and pm.available_points == 1, "committing spends the point")

	if failures.is_empty():
		print("MOVES_PANEL_PASSED: %d checks" % checks)
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
