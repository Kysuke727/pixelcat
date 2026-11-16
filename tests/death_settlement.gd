extends SceneTree

# Death: item loss rules, run end, settlement screen, no respawn.

var failures: Array[String] = []
var checks: int = 0
var inventory
var exp
var day
var pm


func _initialize() -> void:
	call_deferred("_run")


func _total(item_id: String) -> int:
	return inventory.get_item_count(item_id)


func _all_items() -> int:
	var sum := 0
	for slot in inventory.slots:
		sum += int(slot.get("quantity", 0))
	return sum


func _run() -> void:
	pm = root.get_node("ProgressionManager")
	exp = root.get_node("ExpeditionManager")
	day = root.get_node("DayManager")
	inventory = root.get_node("InventoryManager")
	var settlement = root.get_node("SettlementScreen")
	pm._test_mode = true
	settlement.show_delay = 0.0

	# --- Item flags ------------------------------------------------------------------
	_check(inventory.get_item_data("cat_teaser").keep_on_death, "the crafted cat teaser is protected")
	_check(not inventory.get_item_data("yarn").keep_on_death, "raw materials are not protected")
	_check(not inventory.get_item_data("wood").keep_on_death and not inventory.get_item_data("yarn_ball").keep_on_death, "wood and yarn balls can be lost")

	# --- The loss rule ----------------------------------------------------------------
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	inventory.clear_all()
	var empty_report: Dictionary = inventory.apply_death_loss(rng)
	_check(empty_report["lost_total"] == 0 and empty_report["lost"].is_empty(), "an empty backpack loses nothing")

	inventory.clear_all()
	inventory.add_item("yarn", 1, false)
	_check(inventory.apply_death_loss(rng)["lost_total"] == 0 and _total("yarn") == 1, "a single item is kept (half rounds down)")

	inventory.clear_all()
	inventory.add_item("yarn", 1, false)
	inventory.add_item("wood", 1, false)
	var two: Dictionary = inventory.apply_death_loss(rng)
	_check(two["lost_total"] == 1 and _all_items() == 1, "two items: exactly one is lost")

	inventory.clear_all()
	inventory.add_item("yarn", 7, false)
	inventory.add_item("wood", 12, false)
	var changed_events: Array = []
	inventory.inventory_changed.connect(func(): changed_events.append(1))
	var removed: Array = []
	inventory.item_removed.connect(func(id: String, q: int): removed.append([id, q]))
	var nineteen: Dictionary = inventory.apply_death_loss(rng)
	_check(nineteen["total"] == 19 and nineteen["lost_total"] == 9, "19 items lose 9 (half, rounded down)")
	var lost_sum := 0
	for id in nineteen["lost"]:
		lost_sum += int(nineteen["lost"][id])
	_check(lost_sum == 9, "the reported losses add up to 9")
	_check(_all_items() == 10, "10 items are left")
	_check(_total("yarn") == 7 - int(nineteen["lost"].get("yarn", 0)) and _total("wood") == 12 - int(nineteen["lost"].get("wood", 0)), "per-item counts match the report")
	_check(int(nineteen["lost"].get("yarn", 0)) <= 7 and int(nineteen["lost"].get("wood", 0)) <= 12, "never loses more than owned")
	_check(changed_events.size() == 1, "one inventory_changed for the whole loss")
	_check(removed.size() == nineteen["lost"].size(), "one item_removed per lost item type")

	# Protected items.
	inventory.clear_all()
	inventory.add_item("cat_teaser", 6, false)
	inventory.add_item("yarn", 8, false)
	var mixed: Dictionary = inventory.apply_death_loss(rng)
	_check(mixed["total"] == 8 and mixed["lost_total"] == 4, "protected items do not count: 8 loseable, 4 lost")
	_check(_total("cat_teaser") == 6 and not mixed["lost"].has("cat_teaser"), "protected items are never lost")
	_check(mixed["kept"] == {"cat_teaser": 6}, "the report lists the protected items that were kept")
	inventory.clear_all()
	inventory.add_item("cat_teaser", 4, false)
	var only_protected: Dictionary = inventory.apply_death_loss(rng)
	_check(only_protected["lost_total"] == 0 and _total("cat_teaser") == 4, "a backpack of only protected items loses nothing")

	# Stacks across several slots; emptied slots are cleared.
	inventory.clear_all()
	inventory.add_item("yarn", 99, false)
	inventory.add_item("yarn", 5, false)
	var split: Dictionary = inventory.apply_death_loss(rng)
	_check(split["lost_total"] == 52 and _total("yarn") == 52, "104 yarn across two slots lose 52")
	for slot in inventory.slots:
		_check(not (int(slot["quantity"]) <= 0 and str(slot["item_id"]) != ""), "no empty-but-named slot is left behind")
		if int(slot["quantity"]) < 0:
			_check(false, "slot quantity went negative")

	# Randomness: reproducible with a seed, different between seeds, fair per item.
	var outcomes := {}
	for seed_value in range(1, 9):
		inventory.clear_all()
		inventory.add_item("yarn", 6, false)
		inventory.add_item("wood", 6, false)
		var r := RandomNumberGenerator.new()
		r.seed = seed_value
		outcomes[str(inventory.apply_death_loss(r)["lost"])] = true
	_check(outcomes.size() > 2, "different seeds lose different things (%d distinct outcomes)" % outcomes.size())
	inventory.clear_all()
	inventory.add_item("yarn", 6, false)
	inventory.add_item("wood", 6, false)
	var seeded_a := RandomNumberGenerator.new()
	seeded_a.seed = 99
	var first: Dictionary = inventory.apply_death_loss(seeded_a)
	inventory.clear_all()
	inventory.add_item("yarn", 6, false)
	inventory.add_item("wood", 6, false)
	var seeded_b := RandomNumberGenerator.new()
	seeded_b.seed = 99
	_check(inventory.apply_death_loss(seeded_b)["lost"] == first["lost"], "the same seed gives the same loss")
	var yarn_lost_total := 0
	var trials := 400
	var fair := RandomNumberGenerator.new()
	fair.seed = 2026
	for _i in range(trials):
		inventory.clear_all()
		inventory.add_item("yarn", 4, false)
		inventory.add_item("wood", 4, false)
		yarn_lost_total += int(inventory.apply_death_loss(fair)["lost"].get("yarn", 0))
	var average := float(yarn_lost_total) / float(trials)
	_check(average > 1.8 and average < 2.2, "each item is equally likely to go (yarn averaged %.2f of 4 over %d trials, expect 2)" % [average, trials])

	# --- Run end + settlement screen -----------------------------------------------------------
	var reports: Array = []
	exp.run_settlement.connect(func(report: Dictionary): reports.append(report))
	var home_requests: Array = []
	day.scene_change_override = func(path: String) -> int:
		home_requests.append(path)
		return OK

	pm._load_profile_data({})
	inventory.clear_all()
	inventory.add_item("yarn", 7, false)
	inventory.add_item("wood", 12, false)
	inventory.add_item("cat_teaser", 2, false)
	exp.run_active = false
	exp.begin_run("forest_grove")
	day.current_state = day.TimeState.NIGHT
	exp.objectives_total = 8
	exp.objectives_completed = 3
	exp.ordinary_fish = 5
	var fish_before: int = root.get_node("CurrencyManager").fish_count
	exp.on_player_died(null)
	await process_frame
	await process_frame
	_check(not exp.run_active and exp.lives_left == 0, "death ends the run")
	_check(reports.size() == 1, "exactly one settlement report")
	var report: Dictionary = reports[0]
	_check(report["reason"] == "death" and report["map_id"] == "forest_grove", "the report says death on the forest map")
	_check(report["objectives_completed"] == 3 and report["objectives_total"] == 8, "the report carries the objective progress")
	_check(report["retained"] == 3 and report["lost"] == 2, "fish: 5 -> keep 3, lose 2")
	_check(root.get_node("CurrencyManager").fish_count == fish_before + 3, "the kept fish are banked")
	_check(report["items"]["lost_total"] == 9 and report["items"]["kept"] == {"cat_teaser": 2}, "items: 9 of 19 lost, the teasers kept")
	_check(_total("cat_teaser") == 2 and _all_items() == 12, "the backpack really lost them (12 left = 10 + 2 teasers)")
	_check(settlement.is_open() and paused, "the settlement screen is open and the game is paused")
	_check(settlement._subtitle.text.contains("小树林"), "it names the map")
	var line_text := ""
	for child in settlement._lines.get_children():
		line_text += child.text + "|"
	_check(line_text.contains("3 / 8") or line_text.contains("3 /"), "it shows defeated enemies (%s)" % line_text)
	_check(line_text.contains("保住 3") and line_text.contains("丢失 2"), "it shows the fish outcome")
	var item_rows := 0
	for child in settlement._items.get_children():
		if child is HBoxContainer:
			item_rows += 1
	_check(item_rows == report["items"]["lost"].size() + 1, "one row per lost item type plus one for the protected teaser (%d)" % item_rows)
	_check(day.current_state == day.TimeState.NIGHT and home_requests.is_empty(), "nothing happens until 回家 is pressed")
	settlement.confirm()
	await process_frame
	_check(not settlement.is_open() and not paused, "回家 closes the screen and unpauses")
	_check(home_requests.size() == 1 and home_requests[0] == "res://scenes/main.tscn", "it goes back to the house")
	settlement.confirm()
	_check(home_requests.size() == 1, "pressing again does nothing")

	# Nothing to lose.
	inventory.clear_all()
	reports.clear()
	exp.begin_run("park")
	day.current_state = day.TimeState.NIGHT
	exp.on_player_died(null)
	await process_frame
	await process_frame
	_check(reports.size() == 1 and reports[0]["items"]["lost_total"] == 0, "an empty backpack reports no loss")
	var empty_text := ""
	for child in settlement._items.get_children():
		if child is Label:
			empty_text += child.text
	_check(empty_text.contains("没有丢东西"), "the screen says nothing was lost")
	settlement.confirm()
	await process_frame

	# Guards: not on a run, and debug sessions.
	reports.clear()
	exp.run_active = false
	exp.on_player_died(null)
	_check(reports.is_empty(), "no settlement when there is no run")
	exp.begin_run("park")
	pm.debug_session = true
	exp.on_player_died(null)
	_check(reports.is_empty() and exp.run_active, "no settlement during a debug session")
	pm.debug_session = false
	exp.run_active = false
	day.scene_change_override = Callable()
	day.current_state = day.TimeState.DAY

	if failures.is_empty():
		print("DEATH_SETTLEMENT_PASSED: %d checks" % checks)
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
