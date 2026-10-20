extends Control

@onready var open_sound: AudioStreamPlayer = $OpenSound

var is_open: bool = false


func _ready() -> void:
	hide()


func toggle_inventory() -> void:
	is_open = not is_open
	visible = is_open

	if is_open:
		if open_sound.stream != null:
			open_sound.play()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory"):
		toggle_inventory()
