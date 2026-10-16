
extends Control

@onready var coin_label: Label = $PanelContainer/HBoxContainer/CoinLabel
@onready var coin_icon: TextureRect = $PanelContainer/HBoxContainer/CoinIcon
@onready var pickup_sound: AudioStreamPlayer2D = $PickupSound

var coins: int = 0


func _ready() -> void:
	update_coin_display()


func update_coin_display() -> void:
	coin_label.text = "金币：%d" % coins


func add_coins(amount: int) -> void:
	if amount <= 0:
		return

	coins += amount
	update_coin_display()

	if pickup_sound.stream != null:
		pickup_sound.play()

	play_coin_animation()


func play_coin_animation() -> void:
	coin_icon.scale = Vector2.ONE

	var tween = create_tween()
	tween.tween_property(
		coin_icon,
		"scale",
		Vector2(1.3, 1.3),
		0.1
	)
	tween.tween_property(
		coin_icon,
		"scale",
		Vector2.ONE,
		0.1
	)


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.pressed and not event.echo:
			if event.keycode == KEY_C:
				add_coins(1)
