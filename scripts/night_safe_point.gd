extends Area2D

@export var checkpoint_label: String = "安全点"
var activated_for_run: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if activated_for_run or not body.is_in_group("player") or not ExpeditionManager.run_active:
		return
	activated_for_run = true
	ExpeditionManager.activate_safe_point(global_position)
	var label := get_node_or_null("Label") as Label
	if is_instance_valid(label):
		label.text = "✓ " + checkpoint_label
