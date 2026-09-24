extends Control

@onready var hunger_bar = $HungerBar
@onready var mood_bar = $MoodBar
@onready var energy_bar = $EnergyBar

@onready var stats = get_parent().get_node("Cat/Cat_stats")

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
	hunger_bar.value = stats.hunger
	mood_bar.value = stats.mood
	energy_bar.value = stats.energy
