extends Area2D

signal extraction_requested


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	monitoring = false


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		extract()


func extract() -> bool:
	if not ExpeditionManager.objectives_complete():
		return false
	extraction_requested.emit()
	ExpeditionManager.finish_run(true)
	return true
