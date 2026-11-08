extends RefCounted
## Pure deterministic-on-seed loot rules. One roll per slime death.
## Count: 50% -> 1; 30% -> 2; 10% -> 3; 10% -> 4.
## Each item independently chooses yarn, stone or wood with probability 1/3.
const MATERIAL_IDS: Array[String] = ["yarn", "stone", "wood"]


static func count_from_roll(value: float) -> int:
	if value < 0.0 or value >= 1.0:
		return 0
	if value < 0.5:
		return 1
	if value < 0.8:
		return 2
	if value < 0.9:
		return 3
	return 4


static func roll_material_ids(rng: RandomNumberGenerator) -> Array[String]:
	var result: Array[String] = []
	var count: int = count_from_roll(rng.randf())
	for _i in range(count):
		result.append(MATERIAL_IDS[rng.randi_range(0, MATERIAL_IDS.size() - 1)])
	return result
