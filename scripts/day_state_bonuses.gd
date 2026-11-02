extends RefCounted

## Day 12: converts the daytime stat snapshot captured on night entry into the
## night combat modifiers. Thresholds are strict:
##   hunger < 30 -> attack x0.90
##   mood   > 70 -> movement x1.10
##   energy > 70 -> max health +1
## The snapshot is the only input, so repeated scene loads cannot stack bonuses.
## Load this script with preload(); it intentionally has no global class_name so
## headless test runs do not depend on the editor-maintained class cache.

const HUNGER_PENALTY_THRESHOLD := 30.0
const MOOD_BONUS_THRESHOLD := 70.0
const ENERGY_BONUS_THRESHOLD := 70.0
const HUNGER_ATTACK_MULTIPLIER := 0.90
const MOOD_MOVEMENT_MULTIPLIER := 1.10
const ENERGY_MAX_HEALTH_BONUS := 1


static func neutral() -> Dictionary:
	return {
		"attack_multiplier": 1.0,
		"movement_multiplier": 1.0,
		"max_health_bonus": 0,
	}


static func compute(snapshot: Dictionary) -> Dictionary:
	var hunger := _stat(snapshot, "hunger")
	var mood := _stat(snapshot, "mood")
	var energy := _stat(snapshot, "energy")
	return {
		"attack_multiplier": HUNGER_ATTACK_MULTIPLIER if hunger < HUNGER_PENALTY_THRESHOLD else 1.0,
		"movement_multiplier": MOOD_MOVEMENT_MULTIPLIER if mood > MOOD_BONUS_THRESHOLD else 1.0,
		"max_health_bonus": ENERGY_MAX_HEALTH_BONUS if energy > ENERGY_BONUS_THRESHOLD else 0,
	}


static func is_valid_snapshot(snapshot: Variant) -> bool:
	if not snapshot is Dictionary:
		return false
	for key in ["hunger", "mood", "energy"]:
		if snapshot.has(key) and not _is_number(snapshot[key]):
			return false
	return true


static func _stat(snapshot: Dictionary, key: String) -> float:
	var value: Variant = snapshot.get(key, 100.0)
	if not _is_number(value):
		return 100.0
	return clampf(float(value), 0.0, 100.0)


static func _is_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT]
