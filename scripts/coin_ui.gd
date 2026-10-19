extends Control

@onready var fish_label: Label = $PanelContainer/HBoxContainer/CoinLabel
@onready var fish_icon: TextureRect = $PanelContainer/HBoxContainer/CoinIcon
@onready var pickup_sound: AudioStreamPlayer2D = $PickupSound
var has_received_currency_change: bool = false


func _ready() -> void:
	CurrencyManager.fish_changed.connect(_on_fish_changed)
	_on_fish_changed(CurrencyManager.fish_count)


func _on_fish_changed(amount: int) -> void:
	fish_label.text = "小鱼干：%d" % amount
	if has_received_currency_change:
		play_pickup_animation()
	else:
		has_received_currency_change = true


func play_pickup_animation() -> void:
	if pickup_sound.stream != null:
		pickup_sound.play()
	fish_icon.scale = Vector2.ONE
	var tween := create_tween()
	tween.tween_property(fish_icon, "scale", Vector2(1.25, 1.25), 0.09)
	tween.tween_property(fish_icon, "scale", Vector2.ONE, 0.11)
