extends SceneTree

# Success settlement: what a run earned, first clear / new maps, the screen, old-save compat.

var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _texts(container: Node) -> String:
	var text := ""
	for child in container.get_children():
		if child is Label:
			text += child.text + "|"
		else:
			for inner in child.get_children():
				if inner is Label:
					text += inner.text + "|"
	return text


func _run() -> void:
	var pm = root.get_node("ProgressionManager")
	var exp = root.get_node("ExpeditionManager")
	var day = root.get_node("DayManager")
	var inventory = root.get_node("InventoryManager")
	var currency = root.get_node("CurrencyManager")
	var screen = root.get_node("SettlementScreen")
	pm._test_mode = true
	screen.show_delay = 0.0
	var reports: Array = []
	exp.run_settlement.connect(func(report: Dictionary): reports.append(report))
	var home_requests: Array = []
	day.scene_change_override = func(path: String) -> int:
		home_requests.append(path)
		return OK

	# --- Per-run counters --------------------------------------------------------------
	pm._load_profile_data({})
	inventory.clear_all()
	exp.run_active = false
	inventory.add_item("yarn", 3, false)   # before the run: not counted
	exp.begin_run("park")
	_check(exp.run_experience_gained == 0 and exp.run_items_gained.is_empty() and exp.run_moves_learned.is_empty(), "a new run starts with empty counters")
	inventory.add_item("wood", 5, false)
	inventory.add_item("wood", 2, false)
	inventory.add_item("stone", 1, false)
	_check(exp.run_items_gained == {"wood": 7, "stone": 1}, "items picked up during the run are counted (%s)" % str(exp.run_items_gained))
	exp.objectives_total = 2
	exp.objective_ids.assign(["A", "B"] as Array[String])
	exp.complete_enemy_objective("A", 10)
	_check(exp.run_experience_gained == 10, "experience from an enemy is counted")
	exp.complete_enemy_objective("B", 10)
	_check(exp.run_experience_gained == 20 + exp.exploration_clear_experience, "the clear bonus is counted too (%d)" % exp.run_experience_gained)
	pm.unlock_move("pounce")
	_check(exp.run_moves_learned == ["pounce"], "a move learned during the run is recorded")
	pm.unlock_move("triple_combo")
	_check(exp.run_moves_learned == ["pounce", "triple_combo"], "...in order")
	pm.debug_session = true
	inventory.add_item("yarn", 4, false)
	pm.debug_session = false
	_check(not exp.run_items_gained.has("yarn"), "debug sessions are not counted")
	var saved: Dictionary = exp.get_save_data()
	_check(saved["experience_gained"] == exp.run_experience_gained and saved["items_gained"] == {"wood": 7, "stone": 1} and saved["moves_learned"] == ["pounce", "triple_combo"], "the counters are part of the run save")

	# Save / load / compatibility.
	exp.run_active = false
	exp.load_save_data(saved)
	_check(exp.run_experience_gained == saved["experience_gained"] and exp.run_items_gained == {"wood": 7, "stone": 1}, "Continue restores what the run had earned")
	_check(exp.run_moves_learned == ["pounce", "triple_combo"], "...including learned moves")
	var legacy := saved.duplicate(true)
	legacy.erase("experience_gained")
	legacy.erase("items_gained")
	legacy.erase("moves_learned")
	exp.load_save_data(legacy)
	_check(exp.run_experience_gained == 0 and exp.run_items_gained.is_empty() and exp.run_moves_learned.is_empty(), "an older save without the summary loads as empty")
	var with_old_key := saved.duplicate(true)
	with_old_key["safe_position"] = [300.0, 470.0]
	_check(pm._is_valid_expedition_data(with_old_key), "a save that still has the removed safe_position is accepted")
	exp.load_save_data(with_old_key)
	_check(exp.run_active == saved["run_active"], "...and loads (the old key is ignored)")
	_check(not pm._is_valid_expedition_data({"experience_gained": "lots"}), "a non-number experience is rejected")
	_check(not pm._is_valid_expedition_data({"items_gained": [1, 2]}), "a non-dictionary item summary is rejected")
	_check(not pm._is_valid_expedition_data({"items_gained": {"wood": "x"}}), "non-number item amounts are rejected")
	_check(not pm._is_valid_expedition_data({"moves_learned": [1]}), "non-string move ids are rejected")
	_check(pm._is_valid_expedition_data({"experience_gained": 5, "items_gained": {"wood": 2}, "moves_learned": ["pounce"]}), "a valid summary passes")
	_check(not exp.has_method("activate_safe_point") and not exp.has_method("_respawn_player"), "the safe-point API is gone")

	# --- Success report ---------------------------------------------------------------------------
	pm._load_profile_data({})
	inventory.clear_all()
	exp.run_active = false
	exp.begin_run("park")
	day.current_state = day.TimeState.NIGHT
	inventory.add_item("wood", 6, false)
	inventory.add_item("yarn", 4, false)
	exp.objectives_total = 3
	exp.objectives_completed = 3
	exp.ordinary_fish = 7
	exp.run_experience_gained = 42
	exp.run_moves_learned.assign(["triple_combo"] as Array[String])
	exp.run_items_gained = {"wood": 6, "yarn": 4}
	var fish_before: int = currency.fish_count
	reports.clear()
	exp.complete_run_with_settlement()
	await process_frame
	_check(reports.size() == 1, "one settlement report on success")
	var report: Dictionary = reports[0]
	_check(report["success"] and report["reason"] == "success" and report["map_id"] == "park", "it is a success report for the park")
	_check(report["retained"] == 7 and report["lost"] == 0 and currency.fish_count == fish_before + 7, "all the fish are banked on success")
	_check(report["experience"] == 42 and report["items_gained"] == {"wood": 6, "yarn": 4, "herb_pack": 2} and report["moves_learned"] == ["triple_combo"], "the report carries what the run earned")
	_check(report["first_clear"] and report["new_maps"] == ["forest_grove"], "the first clear of the park unlocks the forest")
	_check(not exp.run_active and exp.last_outcome == "success", "the run is over")
	_check(inventory.get_item_count("wood") == 6, "the backpack is untouched on success")

	# --- The screen ---------------------------------------------------------------------------------
	_check(screen.is_open() and paused, "the success screen is open and the game is paused")
	_check(screen._title.text.contains("探险成功"), "title says success")
	_check(screen._subtitle.text.contains("公园"), "it names the map")
	var lines: String = _texts(screen._lines)
	_check(lines.contains("3 / 3") and lines.contains("小鱼干：+7") and lines.contains("经验：+42"), "stat lines (%s)" % lines)
	var items_text: String = _texts(screen._items)
	_check(items_text.contains("本次带回的东西") and items_text.contains("木材 ×6") and items_text.contains("毛线 ×4"), "the items brought back are listed (%s)" % items_text)
	_check(items_text.contains("学会了新招式：三段连击"), "learned moves are listed")
	_check(items_text.contains("首次通关「公园」") and items_text.contains("解锁了新地图：小树林"), "first clear and the unlocked map are announced")
	_check(day.current_state == day.TimeState.NIGHT and home_requests.is_empty(), "still out until 回家 is pressed")
	screen.confirm()
	await process_frame
	_check(not screen.is_open() and not paused and home_requests.size() == 1, "回家 goes home and unpauses")

	# --- Second clear / forest clear / failure ------------------------------------------------------
	pm.mark_map_cleared("park")
	exp.run_active = false
	exp.begin_run("park")
	day.current_state = day.TimeState.NIGHT
	exp.objectives_total = 1
	exp.objectives_completed = 1
	reports.clear()
	exp.complete_run_with_settlement()
	await process_frame
	_check(not reports[0]["first_clear"] and reports[0]["new_maps"].is_empty(), "clearing the park again is not a first clear and unlocks nothing")
	_check(reports[0]["items_gained"] == {"herb_pack": 2}, "even an otherwise empty clear brings back the 2 herb packs")
	_check(_texts(screen._items).contains("通关奖励：草药包 ×2") and not _texts(screen._items).contains("首次通关"), "the reward is listed, without a first-clear line")
	screen.confirm()
	await process_frame

	exp.run_active = false
	exp.begin_run("forest_grove")
	day.current_state = day.TimeState.NIGHT
	exp.objectives_total = 8
	exp.objectives_completed = 8
	reports.clear()
	exp.complete_run_with_settlement()
	await process_frame
	_check(reports[0]["first_clear"] and reports[0]["new_maps"].is_empty(), "the first clear of the last map unlocks nothing new")
	_check(_texts(screen._items).contains("首次通关「小树林」") and not _texts(screen._items).contains("解锁了新地图"), "...and the screen only celebrates the clear")
	screen.confirm()
	await process_frame

	# A failure still works and carries no first clear.
	exp.run_active = false
	exp.begin_run("park")
	day.current_state = day.TimeState.NIGHT
	reports.clear()
	exp.on_player_died(null)
	await process_frame
	_check(reports.size() == 1 and not reports[0]["success"] and not reports[0]["first_clear"], "a failed run is not a first clear")
	_check(screen._title.text.contains("探险失败"), "the failure variant of the screen is still used for deaths")
	screen.confirm()
	await process_frame

	# --- Guards -------------------------------------------------------------------------------------------
	reports.clear()
	exp.run_active = false
	exp.complete_run_with_settlement()
	_check(reports.is_empty(), "no settlement when there is no run")
	exp.begin_run("park")
	pm.debug_session = true
	exp.complete_run_with_settlement()
	_check(reports.is_empty() and exp.run_active, "no settlement during a debug session")
	pm.debug_session = false
	exp.run_active = false

	# --- The exit gate goes through the settlement ---------------------------------------------------------
	pm._load_profile_data({})
	exp.begin_run("park")
	day.current_state = day.TimeState.NIGHT
	exp.objectives_total = 1
	exp.objectives_completed = 0
	var gate_script = load("res://scripts/night_exit.gd")
	var gate := Area2D.new()
	gate.set_script(gate_script)
	root.add_child(gate)
	reports.clear()
	_check(not gate.extract() and reports.is_empty(), "the exit does nothing while objectives remain")
	exp.objectives_completed = 1
	_check(gate.extract() and reports.size() == 1 and screen.is_open(), "the exit opens the settlement once the objectives are done")
	screen.confirm()
	await process_frame
	gate.queue_free()

	day.scene_change_override = Callable()
	exp.run_active = false
	day.current_state = day.TimeState.DAY

	if failures.is_empty():
		print("SUCCESS_SETTLEMENT_PASSED: %d checks" % checks)
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
