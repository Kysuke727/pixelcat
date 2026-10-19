extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	var mode := str(arguments[0]) if not arguments.is_empty() else "verify"
	var progression: Node = root.get_node("ProgressionManager")
	var currency: Node = root.get_node("CurrencyManager")
	var expedition: Node = root.get_node("ExpeditionManager")
	progression._test_mode = false
	if mode == "new":
		_check(progression.level == 1, "new profile starts at level one")
		_check(currency.fish_count == 0, "new profile starts with no permanent fish")
		_check(not expedition.run_active, "new profile has no active expedition")
	elif mode == "write":
		progression.level = 7
		progression.experience = 42
		progression.available_points = 3
		progression.attributes["vitality"] = 2
		currency.load_save_data({"fish_count": 31})
		expedition.load_save_data({
			"run_active": true,
			"lives_left": 1,
			"ordinary_fish": 5,
			"objectives_total": 4,
			"objectives_completed": 2,
			"defeated_enemy_ids": ["BootA", "BootB"],
			"fish_drops": {"BootA:fish:0": {"id": "BootA:fish:0", "position": [321.0, 456.0], "amount": 2}},
		})
		progression.save_now()
		print("PROFILE_FIXTURE_WRITTEN")
	elif mode == "verify":
		_check(progression.level == 7 and progression.experience == 42, "restart restores level and experience")
		_check(progression.available_points == 3 and progression.attributes["vitality"] == 2, "restart restores growth attributes")
		_check(currency.fish_count == 31, "restart restores permanent currency after all autoloads initialize")
		_check(expedition.run_active and expedition.lives_left == 1, "restart restores active expedition and lives")
		_check(expedition.ordinary_fish == 5 and expedition.defeated_enemy_ids.size() == 2, "restart restores expedition resources and defeats")
		_check(expedition.fish_drops.has("BootA:fish:0"), "restart restores an unclaimed fish drop record")
		_check(int(expedition.fish_drops["BootA:fish:0"].get("amount", 0)) == 2, "restart preserves drop quantity and pickup identity")
	else:
		failures.append("Unknown profile bootstrap mode: " + mode)
	if failures.is_empty():
		print("PROFILE_BOOTSTRAP_%s_PASSED" % mode.to_upper())
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
