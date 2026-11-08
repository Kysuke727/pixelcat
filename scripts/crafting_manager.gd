extends Node

signal crafted(recipe_id: String, result_item_id: String, quantity: int)

const RECIPE_PATHS := [
	"res://resources/crafting/yarn_ball.tres",
	"res://resources/crafting/cat_teaser.tres",
]

var recipes: Dictionary = {}


func _ready() -> void:
	_ensure_recipes()


func _ensure_recipes() -> void:
	if not recipes.is_empty():
		return
	for path in RECIPE_PATHS:
		var recipe = load(path)
		if recipe == null or not recipe.is_valid_recipe():
			push_error("Invalid crafting recipe: " + path)
			continue
		if recipes.has(recipe.recipe_id):
			push_error("Duplicate recipe: " + recipe.recipe_id)
			continue
		if InventoryManager.get_item_data(recipe.result_item_id) == null:
			push_error("Recipe output missing from inventory: " + recipe.recipe_id)
			continue
		var ingredients_valid := true
		for item_id in recipe.ingredients.keys():
			if InventoryManager.get_item_data(str(item_id)) == null:
				ingredients_valid = false
		if not ingredients_valid:
			push_error("Recipe ingredients missing from inventory: " + recipe.recipe_id)
			continue
		recipes[recipe.recipe_id] = recipe


func get_recipes() -> Array:
	_ensure_recipes()
	var result: Array = []
	for path in RECIPE_PATHS:
		for recipe in recipes.values():
			if recipe.resource_path == path:
				result.append(recipe)
	return result


func get_recipe(recipe_id: String):
	_ensure_recipes()
	return recipes.get(recipe_id, null)


func get_missing_materials(recipe_id: String) -> Dictionary:
	var recipe = get_recipe(recipe_id)
	if recipe == null:
		return {}
	var missing := {}
	for item_id in recipe.ingredients.keys():
		var required: int = int(recipe.ingredients[item_id])
		var owned: int = InventoryManager.get_item_count(item_id)
		if owned < required:
			missing[item_id] = required - owned
	return missing


func check_craft(recipe_id: String, at_workbench: bool = false) -> Dictionary:
	var recipe = get_recipe(recipe_id)
	if recipe == null:
		return {"success": false, "reason": "unknown_recipe"}
	if recipe.requires_workbench and not at_workbench:
		return {"success": false, "reason": "workbench_required"}
	return InventoryManager.preview_crafting(recipe.ingredients, recipe.result_item_id, recipe.result_quantity)


func craft(recipe_id: String, at_workbench: bool = false) -> Dictionary:
	var recipe = get_recipe(recipe_id)
	if recipe == null:
		return {"success": false, "reason": "unknown_recipe"}
	if recipe.requires_workbench and not at_workbench:
		return {"success": false, "reason": "workbench_required"}
	var result: Dictionary = InventoryManager.craft_items(
		recipe.ingredients, recipe.result_item_id, recipe.result_quantity
	)
	if bool(result.get("success", false)):
		crafted.emit(recipe_id, recipe.result_item_id, recipe.result_quantity)
	return result
