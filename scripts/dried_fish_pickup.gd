extends Area2D

@export var value: int = 1
var collected: bool = false
var elapsed: float = 0.0
var saved_drop_id: String = ""


func setup_saved_drop(drop_id: String, amount: int) -> void:
	saved_drop_id = drop_id
	value = maxi(amount, 1)


func _ready() -> void:
	add_to_group("dried_fish_pickups")
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	elapsed += delta
	$Sprite2D.position.y = sin(elapsed * 4.0) * 2.0


func _on_body_entered(body: Node2D) -> void:
	if collected or not body.is_in_group("player") or ProgressionManager.debug_session:
		return
	if not saved_drop_id.is_empty() and ExpeditionManager.run_active:
		if not ExpeditionManager.collect_saved_fish_drop(saved_drop_id):
			return
		collected = true
		set_deferred("monitoring", false)
		queue_free()
		return
	collected = true
	set_deferred("monitoring", false)
	CurrencyManager.add_fish(value)
	queue_free()
