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


## Ingredients and output scaled for `times` crafts. Crafting N at once is still
## ONE atomic inventory transaction: it either fully succeeds or changes nothing.
func _scaled(recipe, times: int) -> Dictionary:
	var ingredients := {}
	for item_id in recipe.ingredients.keys():
		ingredients[item_id] = int(recipe.ingredients[item_id]) * times
	return {"ingredients": ingredients, "quantity": int(recipe.result_quantity) * times}


func check_craft(recipe_id: String, at_workbench: bool = false, times: int = 1) -> Dictionary:
	var recipe = get_recipe(recipe_id)
	if recipe == null:
		return {"success": false, "reason": "unknown_recipe"}
	if times < 1:
		return {"success": false, "reason": "invalid_quantity"}
	if recipe.requires_workbench and not at_workbench:
		return {"success": false, "reason": "workbench_required"}
	var scaled := _scaled(recipe, times)
	return InventoryManager.preview_crafting(scaled["ingredients"], recipe.result_item_id, scaled["quantity"])


## How many times the recipe can be crafted right now, limited by BOTH the
## materials owned and the room left in the inventory. 0 when none (or when the
## workbench is required but not available).
func get_max_craftable(recipe_id: String, at_workbench: bool = false) -> int:
	var recipe = get_recipe(recipe_id)
	if recipe == null:
		return 0
	if recipe.requires_workbench and not at_workbench:
		return 0
	var by_materials := 999
	for item_id in recipe.ingredients.keys():
		var required: int = int(recipe.ingredients[item_id])
		by_materials = mini(by_materials, floori(float(InventoryManager.get_item_count(item_id)) / float(required)))
	if by_materials <= 0:
		return 0
	# Output may not fit even when the materials are there; step down until it does.
	var times := by_materials
	while times > 0:
		if bool(check_craft(recipe_id, at_workbench, times).get("success", false)):
			return times
		times -= 1
	return 0


func craft(recipe_id: String, at_workbench: bool = false, times: int = 1) -> Dictionary:
	var recipe = get_recipe(recipe_id)
	if recipe == null:
		return {"success": false, "reason": "unknown_recipe"}
	if times < 1:
		return {"success": false, "reason": "invalid_quantity"}
	if recipe.requires_workbench and not at_workbench:
		return {"success": false, "reason": "workbench_required"}
	var scaled := _scaled(recipe, times)
	var result: Dictionary = InventoryManager.craft_items(
		scaled["ingredients"], recipe.result_item_id, scaled["quantity"]
	)
	if bool(result.get("success", false)):
		crafted.emit(recipe_id, recipe.result_item_id, int(scaled["quantity"]))
	return result
