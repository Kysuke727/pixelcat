extends Resource

## A recipe is pure data. The UI never decides whether an inventory mutation is valid.
@export var recipe_id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var ingredients: Dictionary = {}
@export var result_item_id: String = ""
@export_range(1, 999, 1) var result_quantity: int = 1
@export var requires_workbench: bool = false


func is_valid_recipe() -> bool:
	if recipe_id.strip_edges().is_empty() or display_name.strip_edges().is_empty():
		return false
	if result_item_id.strip_edges().is_empty() or result_quantity <= 0 or ingredients.is_empty():
		return false
	for item_id in ingredients:
		if typeof(item_id) != TYPE_STRING or str(item_id).is_empty():
			return false
		if typeof(ingredients[item_id]) != TYPE_INT or int(ingredients[item_id]) <= 0:
			return false
	return true
