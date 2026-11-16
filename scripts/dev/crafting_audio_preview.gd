extends Node

## Audition scene for crafting sound effects. Run it with F6 in the Godot editor.
## It never writes your save: progression is switched to test mode first.
##   R   = refill materials
##   Tab = toggle portable / workbench mode

const CRAFTING_UI_SCENE: PackedScene = preload("res://scenes/ui/crafting_ui.tscn")

var crafting_ui: CanvasLayer
var at_workbench: bool = true


func _ready() -> void:
	ProgressionManager._test_mode = true
	crafting_ui = CRAFTING_UI_SCENE.instantiate()
	add_child(crafting_ui)
	var hint := Label.new()
	hint.text = "合成音效试听  ·  R 补充材料  ·  Tab 切换 随身/工作台  ·  不会写入存档"
	hint.position = Vector2(16.0, 10.0)
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	layer.add_child(hint)
	_refill()
	crafting_ui.open_crafting(at_workbench)


func _refill() -> void:
	InventoryManager.clear_all()
	InventoryManager.add_item("yarn", 40, false)
	InventoryManager.add_item("wood", 40, false)
	InventoryManager.add_item("stone", 10, false)


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.physical_keycode == KEY_R:
		_refill()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_TAB:
		at_workbench = not at_workbench
		crafting_ui.close_crafting()
		crafting_ui.open_crafting(at_workbench)
		get_viewport().set_input_as_handled()
