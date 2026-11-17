extends Area2D
class_name LootSpot

## A hidden stash on a night map: walk into it to take what is inside (materials and/or fish).
## It can be taken once per run; the "taken" state is saved with the run. If the backpack cannot
## hold everything the stash stays closed (nothing is taken) and says so.
##
## All player-facing text is Simplified Chinese.

signal collected(loot_id: String)

@export var loot_id: String = ""
## item_id -> quantity
@export var items: Dictionary = {}
@export var fish: int = 0
@export var glow: bool = true

var taken: bool = false
var _full_warning_left: float = 0.0


func _ready() -> void:
	add_to_group("loot_spot")
	body_entered.connect(_on_body_entered)
	if ExpeditionManager.run_active and ExpeditionManager.is_loot_collected(loot_id):
		taken = true
		queue_free()
		return
	if glow and not get_tree().get_nodes_in_group("night_atmosphere").is_empty():
		var light := PointLight2D.new()
		light.name = "LootGlow"
		light.texture = NightAtmosphere._get_light_texture()
		light.color = Color("#ffe6a0")
		light.energy = 0.6
		light.texture_scale = 0.9
		add_child(light)


func _process(delta: float) -> void:
	_full_warning_left = maxf(_full_warning_left - delta, 0.0)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		collect()


## Returns true when the stash was emptied.
func collect() -> bool:
	if taken:
		return false
	if not items.is_empty():
		var result: Dictionary = InventoryManager.add_items_atomic(items)
		if not bool(result.get("success", false)):
			if _full_warning_left <= 0.0:
				_full_warning_left = 1.5
				HitFeel.damage_number(global_position + Vector2(0.0, -26.0), "背包放不下了", HitFeel.RED, 14)
			return false
	if fish > 0:
		CurrencyManager.add_fish(fish)
	taken = true
	ExpeditionManager.mark_loot_collected(loot_id)
	_celebrate()
	collected.emit(loot_id)
	return true


func _celebrate() -> void:
	var lines: Array[String] = []
	for item_id in items:
		var item = InventoryManager.get_item_data(str(item_id))
		lines.append("+%d %s" % [int(items[item_id]), item.display_name if item != null else str(item_id)])
	if fish > 0:
		lines.append("+%d 小鱼干" % fish)
	HitFeel.spark(global_position, HitFeel.GOLD, 16, 150.0)
	var offset := -30.0
	for line in lines:
		HitFeel.damage_number(global_position + Vector2(0.0, offset), line, HitFeel.GOLD, 14)
		offset -= 18.0
	for child in get_children():
		if child is Sprite2D:
			var tween := create_tween()
			tween.tween_property(child, "modulate:a", 0.0, 0.35)
	set_deferred("monitoring", false)
	get_tree().create_timer(0.45).timeout.connect(queue_free)
