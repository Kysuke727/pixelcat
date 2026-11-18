extends RefCounted
class_name MoveCatalog

## The list of learnable moves. A move is learned by exploring (a "cat secret" spot
## on a map) and stays learned in the save. Basic claw combo, dash, dodge, guard
## and the yarn ball are always available and are not listed here.
##
## All player-facing text is Simplified Chinese.

const MOVES := {
	"triple_combo": {
		"name": "三段连击",
		"input": "J J J",
		"hint": "连按 J 三次，第三下范围更大、击退更强，并且必定让敌人眩晕。",
	},
	"pounce": {
		"name": "扑击",
		"input": "冲刺后 J",
		"hint": "冲刺之后马上按 J，向前扑出去一记重击。伤害高、必定眩晕，但落地后有一小段硬直。",
	},
	"counter_claw": {
		"name": "反击爪",
		"input": "完美闪避后 J",
		"hint": "完美闪避之后的 1 秒内按 J，快速反击，必定让敌人眩晕。",
	},
	"shield_bash": {
		"name": "破盾弹反",
		"input": "按住 Z 再按 H",
		"hint": "举盾时按 H，把面前的敌人击开并眩晕；正在出招的敌人会被直接弹反。消耗盾耐久，出招瞬间盾不会受损。",
	},
}


static func ids() -> Array:
	return MOVES.keys()


static func has_move_id(move_id: String) -> bool:
	return MOVES.has(move_id)


static func display_name(move_id: String) -> String:
	return str(MOVES.get(move_id, {}).get("name", move_id))


static func input_text(move_id: String) -> String:
	return str(MOVES.get(move_id, {}).get("input", ""))


static func hint(move_id: String) -> String:
	return str(MOVES.get(move_id, {}).get("hint", ""))
