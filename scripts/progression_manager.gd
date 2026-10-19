extends Node

signal progression_changed
signal level_changed(level: int, experience: int, experience_to_next: int)

const SAVE_VERSION := 1
const STAT_KEYS := ["vitality", "attack", "defense", "agility"]
const SKILL_KEYS := ["slow", "connection", "bind", "loop"]

@export var experience_base: float = 100.0
@export var experience_growth: float = 1.10
@export var loss_rounding: String = "floor"
var save_path: String = "user://pixelcat_profile.json"

var level: int = 1
var experience: int = 0
var available_points: int = 0
var permanent_hp_bonus: int = 0
var attributes: Dictionary = {"vitality": 0, "attack": 0, "defense": 0, "agility": 0, "technique": 0}
var skill_points: Dictionary = {"slow": 0, "connection": 0, "bind": 0, "loop": 0}
var permanent_items: Array[String] = []
var pending_allocation: Dictionary = {}
var debug_session: bool = false
var _debug_snapshot: Dictionary = {}
var _test_mode: bool = false
var _save_elapsed: float = 0.0


func _ready() -> void:
	_test_mode = OS.get_environment("PIXELCAT_TEST_MODE") == "1"
	_load_profile()


func _process(delta: float) -> void:
	_save_elapsed += delta
	if _save_elapsed >= 5.0:
		_save_elapsed = 0.0
		if is_instance_valid(ExpeditionManager):
			ExpeditionManager.capture_current_run()
		_save_profile()


func required_experience(current_level: int = -1) -> int:
	var target_level := level if current_level < 1 else current_level
	return maxi(int(round(experience_base * pow(experience_growth, target_level - 1))), 1)


func add_experience(amount: int) -> int:
	if amount <= 0:
		return 0
	experience += amount
	var gained_levels := 0
	while experience >= required_experience():
		experience -= required_experience()
		level += 1
		available_points += 1
		if level % 5 == 0:
			available_points += 3
		gained_levels += 1
	level_changed.emit(level, experience, required_experience())
	progression_changed.emit()
	_save_profile()
	return gained_levels


func begin_allocation() -> void:
	if pending_allocation.is_empty():
		pending_allocation = {"attributes": attributes.duplicate(true), "skills": skill_points.duplicate(true)}
	progression_changed.emit()


func allocate_point(key: String, is_skill: bool = false) -> bool:
	if available_points <= _pending_point_count():
		return false
	var choices: Dictionary = pending_allocation.get("skills" if is_skill else "attributes", {})
	if not choices.has(key):
		return false
	if is_skill and _skill_at_cap(key, int(choices[key])):
		return false
	choices[key] = int(choices[key]) + 1
	pending_allocation["skills" if is_skill else "attributes"] = choices
	progression_changed.emit()
	return true


func remove_pending_point(key: String, is_skill: bool = false) -> bool:
	if pending_allocation.is_empty():
		return false
	var category := "skills" if is_skill else "attributes"
	var choices: Dictionary = pending_allocation.get(category, {})
	var committed: Dictionary = skill_points if is_skill else attributes
	if not choices.has(key) or int(choices[key]) <= int(committed.get(key, 0)):
		return false
	choices[key] = int(choices[key]) - 1
	pending_allocation[category] = choices
	progression_changed.emit()
	return true


func cancel_allocation() -> void:
	pending_allocation.clear()
	progression_changed.emit()


func commit_allocation() -> bool:
	if pending_allocation.is_empty():
		return false
	var spent := _pending_point_count()
	if spent > available_points:
		return false
	attributes = pending_allocation["attributes"].duplicate(true)
	skill_points = pending_allocation["skills"].duplicate(true)
	attributes["technique"] = _skill_point_total(skill_points)
	available_points -= spent
	pending_allocation.clear()
	progression_changed.emit()
	_save_profile()
	return true


func _pending_point_count() -> int:
	if pending_allocation.is_empty():
		return 0
	var count := 0
	for key in STAT_KEYS:
		count += int(pending_allocation["attributes"].get(key, 0)) - int(attributes.get(key, 0))
	for key in SKILL_KEYS:
		count += int(pending_allocation["skills"].get(key, 0)) - int(skill_points.get(key, 0))
	return count


func _skill_point_total(points: Dictionary) -> int:
	var total := 0
	for key in SKILL_KEYS:
		total += int(points.get(key, 0))
	return total


func _skill_at_cap(key: String, count: int) -> bool:
	match key:
		"slow": return count >= 15
		"connection": return count >= 50
		"bind": return count >= 20
		"loop": return count >= 30
	return true


func get_skill_modifiers() -> Dictionary:
	return {
		"slow_reduction_bonus": minf(float(skill_points.get("slow", 0)) * 0.02, 0.30),
		"connection_duration_bonus": minf(float(skill_points.get("connection", 0)) * 0.1, 5.0),
		"bind_duration_bonus": minf(float(skill_points.get("bind", 0)) * 0.05, 1.0),
		"loop_angle_reduction": minf(float(skill_points.get("loop", 0)), 30.0),
	}


func get_effective_max_health(base_value: int) -> int:
	return base_value + int(attributes.get("vitality", 0)) + permanent_hp_bonus


func get_attack_multiplier() -> float:
	return 1.0 + float(attributes.get("attack", 0)) * 0.05


func get_shield_multiplier() -> float:
	return 1.0 + float(attributes.get("defense", 0)) * 0.03


func get_movement_multiplier() -> float:
	return 1.0 + float(attributes.get("agility", 0)) * 0.02


func add_permanent_hp(amount: int = 1) -> void:
	permanent_hp_bonus = maxi(permanent_hp_bonus + amount, 0)
	progression_changed.emit()
	_save_profile()


func add_permanent_item(item_id: String) -> void:
	if item_id.is_empty() or permanent_items.has(item_id):
		return
	permanent_items.append(item_id)
	_save_profile()


func get_respec_cost() -> int:
	return 100 + level * 10


func respec_attributes() -> bool:
	var cost := get_respec_cost()
	if not CurrencyManager.spend_fish(cost):
		return false
	available_points += _skill_point_total(skill_points)
	for key in STAT_KEYS:
		available_points += int(attributes.get(key, 0))
	for key in STAT_KEYS:
		attributes[key] = 0
	for key in SKILL_KEYS:
		skill_points[key] = 0
	attributes["technique"] = 0
	pending_allocation.clear()
	progression_changed.emit()
	_save_profile()
	return true


func begin_debug_session() -> void:
	if debug_session:
		return
	_debug_snapshot = {"profile": _profile_data().duplicate(true), "pending": pending_allocation.duplicate(true)}
	debug_session = true


func end_debug_session() -> void:
	if not debug_session:
		return
	debug_session = false
	_load_profile_data(_debug_snapshot.get("profile", {}))
	pending_allocation = _debug_snapshot.get("pending", {}).duplicate(true)
	_debug_snapshot.clear()
	_save_profile()
	progression_changed.emit()


func get_profile_data() -> Dictionary:
	return _profile_data()


func get_save_data() -> Dictionary:
	return {"version": SAVE_VERSION, "profile": _profile_data(), "expedition": ExpeditionManager.get_save_data()}


func save_now() -> void:
	if is_instance_valid(ExpeditionManager):
		ExpeditionManager.capture_current_run()
	_save_profile()


func _profile_data() -> Dictionary:
	return {
		"level": level,
		"experience": experience,
		"available_points": available_points,
		"attributes": attributes.duplicate(true),
		"skill_points": skill_points.duplicate(true),
		"permanent_hp_bonus": permanent_hp_bonus,
		"permanent_items": permanent_items.duplicate(),
		"currency": CurrencyManager.get_save_data(),
	}


func _load_profile() -> void:
	if _test_mode:
		return
	if not FileAccess.file_exists(save_path):
		return
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		push_warning("PixelCat profile save could not be opened")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_warning("PixelCat profile save is invalid; defaults were kept")
		return
	var payload: Dictionary = parsed
	if int(payload.get("version", 0)) > SAVE_VERSION:
		push_warning("PixelCat profile version is newer than this build; defaults were kept")
		return
	var profile: Dictionary = payload.get("profile", payload)
	_load_profile_data(profile)
	if profile.has("currency"):
		CurrencyManager.load_save_data(profile["currency"])
	ExpeditionManager.load_save_data(payload.get("expedition", {}))


func _load_profile_data(data: Dictionary) -> void:
	level = maxi(int(data.get("level", 1)), 1)
	experience = maxi(int(data.get("experience", 0)), 0)
	available_points = maxi(int(data.get("available_points", 0)), 0)
	permanent_hp_bonus = maxi(int(data.get("permanent_hp_bonus", 0)), 0)
	var loaded_attributes: Dictionary = data.get("attributes", {})
	var loaded_skills: Dictionary = data.get("skill_points", {})
	for key in STAT_KEYS:
		attributes[key] = maxi(int(loaded_attributes.get(key, 0)), 0)
	for key in SKILL_KEYS:
		skill_points[key] = clampi(int(loaded_skills.get(key, 0)), 0, _skill_cap(key))
	attributes["technique"] = _skill_point_total(skill_points)
	permanent_items.clear()
	for item in data.get("permanent_items", []):
		permanent_items.append(str(item))
	pending_allocation.clear()
	level_changed.emit(level, experience, required_experience())


func _skill_cap(key: String) -> int:
	match key:
		"slow": return 15
		"connection": return 50
		"bind": return 20
		"loop": return 30
	return 0


func _save_profile() -> void:
	if _test_mode or debug_session:
		return
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_warning("PixelCat profile save could not be written")
		return
	file.store_string(JSON.stringify(get_save_data(), "\t"))
	file.flush()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		save_now()
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_release_runtime_audio()


func _release_runtime_audio() -> void:
	for audio_player in get_tree().root.find_children("*", "AudioStreamPlayer", true, false):
		audio_player.stop()
		audio_player.stream = null
	for audio_player in get_tree().root.find_children("*", "AudioStreamPlayer2D", true, false):
		audio_player.stop()
		audio_player.stream = null
