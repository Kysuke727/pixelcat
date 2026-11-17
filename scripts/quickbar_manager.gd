extends Node

signal quickbar_changed
signal quickbar_slot_changed(slot_index: int)
signal quickbar_slot_activated(slot_index: int, item_id: String)

const SLOT_COUNT := 4

const HERB_PACK := "herb_pack"
const HERB_PACK_HEAL := 2.0
## Items that bind themselves to a free quickbar slot the first time you get them.
const AUTO_BIND := [HERB_PACK]

## Only item IDs are stored. Quantity always comes from InventoryManager.
var bound_item_ids: Array[String] = ["", "", "", ""]
var _loading: bool = false


func _ready() -> void:
	_ensure_slot_count()
	if not InventoryManager.item_added.is_connected(_on_item_added):
		InventoryManager.item_added.connect(_on_item_added)


func _on_item_added(item_id: String, _quantity: int) -> void:
	if _loading or not AUTO_BIND.has(item_id) or bound_item_ids.has(item_id):
		return
	for index in range(SLOT_COUNT):
		if bound_item_ids[index].is_empty():
			bind_item(index, item_id)
			return


func _ensure_slot_count() -> void:
	if bound_item_ids.size() != SLOT_COUNT:
		bound_item_ids.resize(SLOT_COUNT)


func _is_valid_slot_index(slot_index: int) -> bool:
	return slot_index >= 0 and slot_index < SLOT_COUNT


func bind_item(slot_index: int, item_id: String) -> bool:
	if not _is_valid_slot_index(slot_index):
		push_warning("快捷栏索引无效：" + str(slot_index))
		return false
	if item_id.is_empty():
		return clear_slot(slot_index)

	var item = InventoryManager.get_item_data(item_id)
	if item == null:
		push_warning("快捷栏无法绑定未知物品：" + item_id)
		return false
	if not bool(item.usable):
		push_warning("该物品没有明确的可使用规则，不能绑定快捷栏：" + item_id)
		return false
	if bound_item_ids[slot_index] == item_id:
		return true

	bound_item_ids[slot_index] = item_id
	quickbar_slot_changed.emit(slot_index)
	quickbar_changed.emit()
	_persist_change()
	return true


func clear_slot(slot_index: int) -> bool:
	if not _is_valid_slot_index(slot_index):
		push_warning("快捷栏索引无效：" + str(slot_index))
		return false
	if bound_item_ids[slot_index].is_empty():
		return true

	bound_item_ids[slot_index] = ""
	quickbar_slot_changed.emit(slot_index)
	quickbar_changed.emit()
	_persist_change()
	return true


func clear_all() -> void:
	var changed := false
	for index in range(SLOT_COUNT):
		if not bound_item_ids[index].is_empty():
			bound_item_ids[index] = ""
			changed = true
	if changed:
		quickbar_changed.emit()
		_persist_change()


func get_bound_item_id(slot_index: int) -> String:
	if not _is_valid_slot_index(slot_index):
		return ""
	return bound_item_ids[slot_index]


func get_bound_item_data(slot_index: int):
	var item_id := get_bound_item_id(slot_index)
	if item_id.is_empty():
		return null
	return InventoryManager.get_item_data(item_id)


func get_bound_item_count(slot_index: int) -> int:
	var item_id := get_bound_item_id(slot_index)
	if item_id.is_empty():
		return 0
	return InventoryManager.get_item_count(item_id)


func has_usable_quantity(slot_index: int) -> bool:
	var item = get_bound_item_data(slot_index)
	if item == null or not bool(item.usable):
		return false
	return get_bound_item_count(slot_index) > 0


## Number keys use the same validated item action as the inventory detail panel.
func activate_slot(slot_index: int) -> Dictionary:
	if not _is_valid_slot_index(slot_index):
		return {"handled": false, "reason": "invalid_slot", "slot": slot_index}
	var item = get_bound_item_data(slot_index)
	if item == null:
		return {"handled": false, "reason": "empty_slot", "slot": slot_index}
	if not bool(item.usable):
		return {"handled": false, "reason": "not_usable", "slot": slot_index, "item_id": item.item_id}
	if get_bound_item_count(slot_index) <= 0:
		return {"handled": false, "reason": "out_of_stock", "slot": slot_index, "item_id": item.item_id}
	var result: Dictionary = use_item(item.item_id)
	if bool(result.get("handled", false)):
		quickbar_slot_activated.emit(slot_index, item.item_id)
	result["slot"] = slot_index
	return result


func use_item(item_id: String) -> Dictionary:
	var item = InventoryManager.get_item_data(item_id)
	if item == null:
		return {"handled": false, "reason": "invalid_item", "item_id": item_id}
	if not bool(item.usable):
		return {"handled": false, "reason": "not_usable", "item_id": item_id}
	if InventoryManager.get_item_count(item_id) < 1:
		return {"handled": false, "reason": "out_of_stock", "item_id": item_id}
	if item_id == "cat_teaser":
		var player: Node = get_tree().get_first_node_in_group("player")
		if player == null or bool(player.get("dead")):
			return {"handled": false, "reason": "no_player", "item_id": item_id}
		var stats: Node = player.get_node_or_null("Stats")
		if stats == null:
			return {"handled": false, "reason": "no_stats", "item_id": item_id}
		if float(stats.get("mood")) >= 100.0:
			return {"handled": false, "reason": "mood_full", "item_id": item_id}
		var before_mood: float = float(stats.get("mood"))
		stats.add_mood(20)
		var removed: Dictionary = InventoryManager.remove_item(item_id, 1)
		if not bool(removed.get("success", false)):
			stats.set("mood", before_mood)
			return {"handled": false, "reason": "consume_failed", "item_id": item_id}
		return {"handled": true, "reason": "used_cat_teaser", "item_id": item_id, "mood_after": float(stats.get("mood"))}
	if item_id == HERB_PACK:
		var cat: Node = get_tree().get_first_node_in_group("player")
		if cat == null or bool(cat.get("dead")) or not cat.has_method("heal"):
			return {"handled": false, "reason": "no_player", "item_id": item_id}
		if float(cat.get("current_health")) >= float(cat.get("max_health")):
			return {"handled": false, "reason": "health_full", "item_id": item_id}
		var removed_herb: Dictionary = InventoryManager.remove_item(item_id, 1)
		if not bool(removed_herb.get("success", false)):
			return {"handled": false, "reason": "consume_failed", "item_id": item_id}
		var healed: float = cat.heal(HERB_PACK_HEAL)
		if cat is Node2D and is_instance_valid(HitFeel):
			HitFeel.damage_number(cat.global_position + Vector2(0.0, -30.0), "+%d" % int(round(healed)), HitFeel.GREEN, 18)
			HitFeel.spark(cat.global_position, HitFeel.GREEN, 10, 110.0)
		return {"handled": true, "reason": "used_herb_pack", "item_id": item_id, "healed": healed}
	return {"handled": false, "reason": "item_use_not_implemented", "item_id": item_id}


func get_save_data() -> Array[String]:
	_ensure_slot_count()
	var result: Array[String] = []
	for item_id in bound_item_ids:
		result.append(item_id)
	return result


func load_save_data(data: Array) -> void:
	_ensure_slot_count()
	_loading = true
	for index in range(SLOT_COUNT):
		bound_item_ids[index] = ""
	for index in range(mini(data.size(), SLOT_COUNT)):
		var item_id := str(data[index])
		if item_id.is_empty():
			continue
		var item = InventoryManager.get_item_data(item_id)
		if item == null or not bool(item.usable):
			push_warning("忽略无效或不可使用的快捷栏绑定：" + item_id)
			continue
		bound_item_ids[index] = item_id
	_loading = false
	quickbar_changed.emit()


func _persist_change() -> void:
	if _loading:
		return
	if is_instance_valid(ProgressionManager):
		ProgressionManager.save_now()
