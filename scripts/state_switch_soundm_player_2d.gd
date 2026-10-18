extends AudioStreamPlayer2D


func play_switch_sound() -> void:
	if stream != null:
		play()
func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.pressed and not event.echo:
			if event.keycode == KEY_T:
				play_switch_sound()
