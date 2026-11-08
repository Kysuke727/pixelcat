extends Control

const DAY_SCENE := "res://scenes/main.tscn"
const NIGHT_SCENE := "res://scenes/worlds/night_world.tscn"

@onready var continue_button: Button = $MenuPanel/MenuButtons/ContinueButton
@onready var new_game_button: Button = $MenuPanel/MenuButtons/NewGameButton2
@onready var exit_button: Button = $MenuPanel/MenuButtons/ExitButton2

var confirmation: ConfirmationDialog
var busy := false


func _ready() -> void:
	continue_button.disabled = not ProgressionManager.has_saved_game()
	continue_button.pressed.connect(_continue_game)
	new_game_button.pressed.connect(_request_new_game)
	exit_button.pressed.connect(func() -> void: get_tree().quit())
	confirmation = ConfirmationDialog.new()
	confirmation.title = "重新开始游戏"
	confirmation.dialog_text = "开始新游戏将覆盖当前存档，确定继续吗？"
	confirmation.ok_button_text = "开始新游戏"
	confirmation.confirmed.connect(_start_new_game)
	add_child(confirmation)


func _continue_game() -> void:
	if busy or not ProgressionManager.has_saved_game():
		return
	busy = true
	ProgressionManager.continue_game()
	var target := NIGHT_SCENE if ExpeditionManager.run_active else DAY_SCENE
	DayManager.current_state = DayManager.TimeState.NIGHT if ExpeditionManager.run_active else DayManager.TimeState.DAY
	DayManager.enter_from_menu(target, false)


func _request_new_game() -> void:
	if busy:
		return
	if ProgressionManager.has_any_save_file():
		confirmation.popup_centered()
	else:
		_start_new_game()


func _start_new_game() -> void:
	if busy:
		return
	busy = true
	ProgressionManager.new_game()
	DayManager.enter_from_menu(DAY_SCENE, true)
