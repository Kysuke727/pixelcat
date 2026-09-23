extends Node
var hunger: int = 100
var mood: int = 100
var energy: int = 100
func add_hunger(amount: int) -> void:
	hunger = clamp(hunger + amount, 0, 100)
func reduce_hunger(amount: int) -> void:
	hunger = clamp(hunger - amount, 0, 100)
func add_mood(amount: int) -> void:
	mood = clamp(mood + amount, 0, 100)
func reduce_mood(amount: int) -> void:
	mood = clamp(mood - amount, 0, 100)
func add_energy(amount: int) ->void:
	energy = clamp(energy + amount, 0, 100)
func reduce_energy(amount: int) -> void:
	energy = clamp(energy - amount, 0, 100)
