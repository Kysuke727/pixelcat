extends Control
@onready var hunger_bar = $HungerBar
@onready var mood_bar = $MoodBar
@onready var energy_bar = $EnergyBar
@onready var stats = get_tree().current_scene.get_node("Cat/Stats")
func _process(delta) -> void:
	hunger_bar.value = stats.hunger
	mood_bar.value = stats.mood
	energy_bar.value = stats.energy
