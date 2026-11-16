extends Control

const LOW_THRESHOLD := 25.0

@onready var hunger_bar: ProgressBar = $Strip/Row/Hunger/HungerBar
@onready var mood_bar: ProgressBar = $Strip/Row/Mood/MoodBar
@onready var energy_bar: ProgressBar = $Strip/Row/Energy/EnergyBar

@onready var stats = get_parent().get_node("Cat/Stats")

func _ready():
	hunger_bar.max_value = 100
	mood_bar.max_value = 100
	energy_bar.max_value = 100

func _process(delta):

	# 数值缓慢下降
	stats.hunger -= delta * 0.3
	stats.mood -= delta * 0.2
	stats.energy -= delta * 0.25

	# 限制范围
	stats.hunger = clamp(stats.hunger, 0.0, 100.0)
	stats.mood = clamp(stats.mood, 0.0, 100.0)
	stats.energy = clamp(stats.energy, 0.0, 100.0)

	# 更新进度条
	_set_bar(hunger_bar, stats.hunger, &"HungerBar")
	_set_bar(mood_bar, stats.mood, &"MoodBar")
	_set_bar(energy_bar, stats.energy, &"EnergyBar")


## A bar turns red when its stat is low so it is noticeable without text.
func _set_bar(bar: ProgressBar, value: float, normal_variation: StringName) -> void:
	bar.value = value
	var variation := &"LowBar" if value < LOW_THRESHOLD else normal_variation
	if bar.theme_type_variation != variation:
		bar.theme_type_variation = variation
