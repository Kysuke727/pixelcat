extends Resource

## Item definition loaded from resources/items/*.tres. It intentionally has no
## global class_name so headless test runs do not depend on the editor class
## cache; InventoryManager treats definitions through their exported fields.

enum Category {
	FOOD,
	MATERIAL,
	TOOL,
	QUEST,
}

@export var item_id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var category: Category = Category.MATERIAL
@export var icon: Texture2D
@export_range(1, 999, 1) var max_stack: int = 99
@export var usable: bool = false
@export var discardable: bool = true


func is_valid_item() -> bool:
	return (
		not item_id.strip_edges().is_empty()
		and not display_name.strip_edges().is_empty()
		and max_stack >= 1
	)


func category_name() -> String:
	match category:
		Category.FOOD:
			return "食物"
		Category.MATERIAL:
			return "材料"
		Category.TOOL:
			return "工具"
		Category.QUEST:
			return "任务"
	return "材料"
