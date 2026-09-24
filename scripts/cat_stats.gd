extends Node

var hunger: float = 100
var mood: float = 100
var energy: float = 100

func add_hunger(amount):
	hunger = clamp(hunger + amount, 0, 100)

func add_mood(amount):
	mood = clamp(mood + amount, 0, 100)

func add_energy(amount):
	energy = clamp(energy + amount, 0, 100)

func reduce_hunger(amount):
	hunger = clamp(hunger - amount, 0, 100)

func reduce_mood(amount):
	mood = clamp(mood - amount, 0, 100)

func reduce_energy(amount):
	energy = clamp(energy - amount, 0, 100)
