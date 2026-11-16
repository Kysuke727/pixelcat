extends Node

## One-click playtest entry. Open one of the scenes in scenes/dev/play_*.tscn in the Godot
## editor and press F6 (Run Current Scene): you land directly in the chosen night map.
##
##  * NOTHING is written to your save: progression is switched to test mode first.
##  * You do not need to clear the earlier maps first.
##  * When you reach the exit (or run out of lives) you go back to the house like in
##    the real game.
##
## Controls are listed in docs/how-to-play.md.

@export var map_id: String = "forest_grove"
## Start with every move already learned (handy for trying the combos right away).
@export var unlock_all_moves: bool = false


func _ready() -> void:
	# The scene tree is still being built here; changing scene right now is refused
	# ("parent node is busy"), so wait for the next frame.
	call_deferred("_launch")


func _launch() -> void:
	ProgressionManager._test_mode = true
	ProgressionManager._load_profile_data({})
	ProgressionManager.game_started = true
	if unlock_all_moves:
		for move_id in MoveCatalog.ids():
			ProgressionManager.unlock_move(move_id)
	ExpeditionManager.run_active = false
	ExpeditionManager.begin_run(map_id)
	DayManager.current_state = DayManager.TimeState.NIGHT
	DayManager.enter_from_menu(MapCatalog.scene_path(ExpeditionManager.current_map_id), false)
