extends Resource
class_name ItemData

enum Category {
	FOOD,
	MATERIAL,
	TOOL,
	QUEST
}

@export var item_id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var category: Category = Category.MATERIAL
@export_range(1, 999) var max_stack: int = 99
@export var usable: bool = false
@export var discardable: bool = true


func is_valid_item() -> bool:
	return (
		not item_id.strip_edges().is_empty()
		and not display_name.strip_edges().is_empty()
		and max_stack >= 1
	)
