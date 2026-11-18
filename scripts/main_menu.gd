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
	_disable_unfinished_buttons()
	var settings_button := get_node_or_null("MenuPanel/MenuButtons/SettingsButtonButton4") as Button
	if settings_button != null:
		settings_button.pressed.connect(func() -> void: SettingsMenu.open())


func _continue_game() -> void:
	if busy or not ProgressionManager.has_saved_game():
		return
	busy = true
	ProgressionManager.continue_game()
	var target := MapCatalog.scene_path(ExpeditionManager.current_map_id) if ExpeditionManager.run_active else DAY_SCENE
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


## The gallery button is a placeholder for now: show them greyed out with a
## tooltip instead of letting players click buttons that do nothing. To enable one later,
## connect its `pressed` signal and remove its path from this list.
const UNFINISHED_BUTTONS := [
	"MenuPanel/MenuButtons/GalleryButton2",
]


func _disable_unfinished_buttons() -> void:
	for path in UNFINISHED_BUTTONS:
		var button := get_node_or_null(path) as Button
		if button != null:
			button.disabled = true
			button.tooltip_text = "还没做，敬请期待"
			button.modulate = Color(1.0, 1.0, 1.0, 0.5)
