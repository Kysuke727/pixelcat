extends RefCounted
class_name MapCatalog

## The night maps. A map is unlocked once the map it "requires" has been cleared
## (reached the exit after defeating every enemy). Until a second map is unlocked the
## game goes straight to the first one without asking.
##
## All player-facing text is Simplified Chinese.

const FIRST_MAP := "park"

## Order matters: it is the order of the selection screen.
const MAPS := {
	"park": {
		"name": "公园",
		"scene": "res://scenes/worlds/night_world.tscn",
		"requires": "",
		"start": Vector2(500, 350),
		"blurb": "熟悉的夜晚公园。清空史莱姆，从右边的出口回家。",
	},
	"forest_grove": {
		"name": "小树林",
		"scene": "res://scenes/worlds/forest_grove.tscn",
		"requires": "park",
		"start": Vector2(170, 1120),
		"blurb": "公园外的小树林，路很长。听说树林深处藏着猫猫的小秘密。",
	},
}


static func ids() -> Array:
	return MAPS.keys()


static func has_map(map_id: String) -> bool:
	return MAPS.has(map_id)


static func display_name(map_id: String) -> String:
	return str(MAPS.get(map_id, {}).get("name", map_id))


static func blurb(map_id: String) -> String:
	return str(MAPS.get(map_id, {}).get("blurb", ""))


static func required_map(map_id: String) -> String:
	return str(MAPS.get(map_id, {}).get("requires", ""))


## Unknown ids fall back to the first map so a damaged save can never strand the player.
static func scene_path(map_id: String) -> String:
	return str(MAPS.get(map_id, MAPS[FIRST_MAP]).get("scene"))


static func start_position(map_id: String) -> Vector2:
	return MAPS.get(map_id, MAPS[FIRST_MAP]).get("start", Vector2(500, 350))


static func is_available(map_id: String, cleared: Array) -> bool:
	if not MAPS.has(map_id):
		return false
	var requirement := required_map(map_id)
	return requirement.is_empty() or cleared.has(requirement)
