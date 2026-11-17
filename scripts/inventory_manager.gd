extends Node

signal inventory_changed
signal item_added(item_id: String, quantity: int)
signal item_removed(item_id: String, quantity: int)

const SLOT_COUNT := 24
## The home storage chest. Its contents are never lost when the cat falls (only the backpack is).
## It can be enlarged later by raising this number (older saves load fine).
const STORAGE_SLOT_COUNT := 56
const ITEM_PATHS := [
	"res://resources/items/yarn_ball.tres",
	"res://resources/items/wood.tres",
	"res://resources/items/stone.tres",
	"res://resources/items/test_potion.tres",
	"res://resources/items/yarn.tres",
	"res://resources/items/cat_teaser.tres",
	"res://resources/items/herb_pack.tres",
]

var item_database: Dictionary = {}
var slots: Array[Dictionary] = []
var storage_slots: Array[Dictionary] = []
var ui_open: bool = false
var _loading: bool = false


func _ready() -> void:
	_ensure_ready()


func _ensure_ready() -> void:
	if item_database.is_empty():
		_register_items()
	if slots.is_empty():
		_reset_slots()
	if storage_slots.is_empty():
		_reset_storage()


func _register_items() -> void:
	item_database.clear()
	for path in ITEM_PATHS:
		var item = load(path)
		if item == null or not item.is_valid_item():
			push_error("Invalid item definition: " + str(path))
			continue
		if item_database.has(item.item_id):
			push_error("Duplicate item id: " + item.item_id)
			continue
		item_database[item.item_id] = item


func _reset_slots() -> void:
	slots.clear()
	for _index in range(SLOT_COUNT):
		slots.append({"item_id": "", "quantity": 0})


func _reset_storage() -> void:
	storage_slots.clear()
	for _index in range(STORAGE_SLOT_COUNT):
		storage_slots.append({"item_id": "", "quantity": 0})


func get_storage_slot(index: int) -> Dictionary:
	_ensure_ready()
	if index < 0 or index >= storage_slots.size():
		return {}
	return storage_slots[index].duplicate(true)


func get_storage_item_count(item_id: String) -> int:
	_ensure_ready()
	var total := 0
	for slot in storage_slots:
		if str(slot["item_id"]) == item_id:
			total += int(slot["quantity"])
	return total


## Move up to `quantity` of an item between the backpack and the storage chest. It moves as
## many as the other side has room for (the rest stays where it was).
## Returns {"moved": int, "reason": "" | "none_to_move" | "full" | "invalid_item"}.
func transfer(item_id: String, quantity: int, to_storage: bool, persist: bool = true) -> Dictionary:
	_ensure_ready()
	var item = get_item_data(item_id)
	if item == null:
		return {"moved": 0, "reason": "invalid_item"}
	var source: Array[Dictionary] = slots if to_storage else storage_slots
	var target: Array[Dictionary] = storage_slots if to_storage else slots
	var have := 0
	for slot in source:
		if str(slot["item_id"]) == item_id:
			have += int(slot["quantity"])
	var wanted := mini(quantity, have)
	if wanted <= 0:
		return {"moved": 0, "reason": "none_to_move"}
	var staged: Array[Dictionary] = []
	for slot in target:
		staged.append(slot.duplicate(true))
	var moved := _add_to_slots(staged, item, wanted)
	if moved <= 0:
		return {"moved": 0, "reason": "full"}
	# take `moved` out of the source, emptiest stacks first so stacks stay tidy
	var remaining := moved
	var order: Array[int] = []
	for i in range(source.size()):
		if str(source[i]["item_id"]) == item_id:
			order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return int(source[a]["quantity"]) < int(source[b]["quantity"]))
	for i in order:
		var take := mini(remaining, int(source[i]["quantity"]))
		source[i]["quantity"] = int(source[i]["quantity"]) - take
		if int(source[i]["quantity"]) <= 0:
			source[i] = {"item_id": "", "quantity": 0}
		remaining -= take
		if remaining <= 0:
			break
	if to_storage:
		storage_slots = staged
	else:
		slots = staged
	inventory_changed.emit()
	if persist:
		_persist_change()
	return {"moved": moved, "reason": "" if moved == wanted else "full"}


## Put items straight into the chest (rewards that did not fit in the backpack). Returns how many fit.
func add_to_storage(item_id: String, quantity: int, persist: bool = true) -> int:
	_ensure_ready()
	var item = get_item_data(item_id)
	if item == null or quantity <= 0:
		return 0
	var added := _add_to_slots(storage_slots, item, quantity)
	if added > 0:
		inventory_changed.emit()
		if persist:
			_persist_change()
	return added


func get_storage_save_data() -> Array:
	_ensure_ready()
	var result: Array = []
	for slot in storage_slots:
		result.append({"item_id": str(slot["item_id"]), "quantity": int(slot["quantity"])})
	return result


func load_storage_save_data(data: Array) -> void:
	_ensure_ready()
	_reset_storage()
	for entry in data:
		if not entry is Dictionary:
			continue
		var item_id := str(entry.get("item_id", ""))
		var quantity_value: Variant = entry.get("quantity", 0)
		if item_id.is_empty() or typeof(quantity_value) not in [TYPE_INT, TYPE_FLOAT]:
			continue
		var quantity := int(quantity_value)
		var item = get_item_data(item_id)
		if quantity <= 0 or item == null:
			continue
		_add_to_slots(storage_slots, item, quantity)
	inventory_changed.emit()


func set_ui_open(open: bool) -> void:
	ui_open = open


func get_slot_count() -> int:
	return slots.size()


func get_slot(index: int) -> Dictionary:
	if index < 0 or index >= slots.size():
		return {}
	return slots[index].duplicate(true)


func get_item_data(item_id: String):
	if not item_database.has(item_id):
		return null
	return item_database[item_id]


func get_item_count(item_id: String) -> int:
	if not item_database.has(item_id):
		return 0
	var total := 0
	for slot in slots:
		if str(slot["item_id"]) == item_id:
			total += int(slot["quantity"])
	return total


func has_item(item_id: String, quantity: int = 1) -> bool:
	return quantity > 0 and get_item_count(item_id) >= quantity


func get_empty_slot_count() -> int:
	var total := 0
	for slot in slots:
		if str(slot["item_id"]).is_empty():
			total += 1
	return total


func get_addable_quantity(item_id: String, quantity: int = 999) -> int:
	var item = get_item_data(item_id)
	if item == null or quantity <= 0:
		return 0
	var total := 0
	for slot in slots:
		if str(slot["item_id"]) == item_id:
			total += maxi(item.max_stack - int(slot["quantity"]), 0)
		elif str(slot["item_id"]).is_empty():
			total += item.max_stack
		if total >= quantity:
			return quantity
	return total


func can_add_item(item_id: String, quantity: int) -> bool:
	return quantity > 0 and get_addable_quantity(item_id, quantity) >= quantity


func add_item(item_id: String, quantity: int, persist: bool = true) -> Dictionary:
	if quantity <= 0:
		return _result(false, quantity, 0, quantity, "invalid_quantity")
	var item = get_item_data(item_id)
	if item == null:
		return _result(false, quantity, 0, quantity, "invalid_item")

	var added := _add_stack(item, quantity)
	if added <= 0:
		return _result(false, quantity, 0, quantity, "inventory_full")
	var remaining := quantity - added
	item_added.emit(item_id, added)
	inventory_changed.emit()
	if persist:
		_persist_change()
	return _result(remaining == 0, quantity, added, remaining, "" if remaining == 0 else "inventory_full")


## Add several kinds of item at once, ALL or NOTHING: it is first tried on a copy of the
## backpack (like crafting), so two items that would compete for the last free slot are
## handled correctly. Returns {"success": bool, "reason": String, "added": {item_id: qty}}.
func add_items_atomic(entries: Dictionary, persist: bool = true) -> Dictionary:
	_ensure_ready()
	if entries.is_empty():
		return {"success": false, "reason": "nothing_to_add", "added": {}}
	var staged: Array[Dictionary] = []
	for slot in slots:
		staged.append(slot.duplicate(true))
	for raw_id in entries:
		var item_id := str(raw_id)
		var quantity := int(entries[raw_id])
		var item = get_item_data(item_id)
		if item == null:
			return {"success": false, "reason": "invalid_item", "added": {}}
		if quantity <= 0:
			return {"success": false, "reason": "invalid_quantity", "added": {}}
		if _add_to_slots(staged, item, quantity) != quantity:
			return {"success": false, "reason": "inventory_full", "added": {}}
	slots = staged
	var added := {}
	for raw_id in entries:
		added[str(raw_id)] = int(entries[raw_id])
		item_added.emit(str(raw_id), int(entries[raw_id]))
	inventory_changed.emit()
	if persist:
		_persist_change()
	return {"success": true, "reason": "", "added": added}


func remove_item(item_id: String, quantity: int) -> Dictionary:
	if quantity <= 0:
		return _remove_result(false, quantity, 0, "invalid_quantity")
	if not item_database.has(item_id):
		return _remove_result(false, quantity, 0, "invalid_item")
	if get_item_count(item_id) < quantity:
		return _remove_result(false, quantity, 0, "insufficient_quantity")

	var remaining := quantity
	for slot in slots:
		if str(slot["item_id"]) != item_id:
			continue
		var current := int(slot["quantity"])
		var amount := mini(remaining, current)
		slot["quantity"] = current - amount
		remaining -= amount
		if int(slot["quantity"]) <= 0:
			slot["item_id"] = ""
			slot["quantity"] = 0
		if remaining <= 0:
			break

	var removed := quantity - remaining
	if removed <= 0:
		return _remove_result(false, quantity, 0, "insufficient_quantity")
	item_removed.emit(item_id, removed)
	inventory_changed.emit()
	_persist_change()
	return _remove_result(true, quantity, removed, "")


## Crafting operates on a cloned inventory. Failure never removes ingredients
## or writes a partial output to the persistent save.
func preview_crafting(ingredients: Dictionary, result_item_id: String, result_quantity: int = 1) -> Dictionary:
	return _craft_transaction(ingredients, result_item_id, result_quantity, false)


func craft_items(ingredients: Dictionary, result_item_id: String, result_quantity: int = 1) -> Dictionary:
	return _craft_transaction(ingredients, result_item_id, result_quantity, true)


func _craft_transaction(ingredients: Dictionary, result_item_id: String, result_quantity: int, commit: bool) -> Dictionary:
	_ensure_ready()
	var result_item = get_item_data(result_item_id)
	if result_item == null:
		return {"success": false, "reason": "invalid_output"}
	if result_quantity <= 0 or ingredients.is_empty():
		return {"success": false, "reason": "invalid_recipe"}
	var staged: Array[Dictionary] = []
	for slot in slots:
		staged.append(slot.duplicate(true))
	for raw_id in ingredients:
		if typeof(raw_id) != TYPE_STRING or not item_database.has(raw_id):
			return {"success": false, "reason": "invalid_ingredient"}
		var value: Variant = ingredients[raw_id]
		if typeof(value) != TYPE_INT or int(value) <= 0:
			return {"success": false, "reason": "invalid_quantity"}
		if get_item_count(raw_id) < int(value):
			return {"success": false, "reason": "insufficient_materials"}
		var remaining: int = int(value)
		for slot in staged:
			if str(slot["item_id"]) != raw_id:
				continue
			var taken: int = mini(remaining, int(slot["quantity"]))
			slot["quantity"] = int(slot["quantity"]) - taken
			remaining -= taken
			if int(slot["quantity"]) == 0:
				slot["item_id"] = ""
			if remaining == 0:
				break
		if remaining != 0:
			return {"success": false, "reason": "insufficient_materials"}
	if _add_to_slots(staged, result_item, result_quantity) != result_quantity:
		return {"success": false, "reason": "inventory_full"}
	if commit:
		slots = staged
		for item_id in ingredients.keys():
			item_removed.emit(str(item_id), int(ingredients[item_id]))
		item_added.emit(result_item_id, result_quantity)
		inventory_changed.emit()
		_persist_change()
	return {"success": true, "reason": "", "result_item_id": result_item_id, "quantity": result_quantity}


func clear_all() -> void:
	_reset_slots()
	inventory_changed.emit()
	_persist_change()


func get_save_data() -> Array:
	var result: Array = []
	for slot in slots:
		result.append({
			"item_id": str(slot["item_id"]),
			"quantity": int(slot["quantity"]),
		})
	return result


func load_save_data(data: Array) -> void:
	_ensure_ready()
	_loading = true
	_reset_slots()
	for index in range(mini(data.size(), SLOT_COUNT)):
		var entry: Variant = data[index]
		if not entry is Dictionary:
			continue
		var item_id := str(entry.get("item_id", ""))
		if item_id.is_empty():
			continue
		var quantity_value: Variant = entry.get("quantity", 0)
		if typeof(quantity_value) not in [TYPE_INT, TYPE_FLOAT]:
			continue
		var quantity_float := float(quantity_value)
		if quantity_float <= 0.0 or not is_equal_approx(quantity_float, roundf(quantity_float)):
			continue
		var quantity := int(quantity_float)
		var item = get_item_data(item_id)
		if item == null:
			push_warning("Unknown item id in inventory save: " + item_id)
			continue
		_add_stack(item, quantity)
	_loading = false
	inventory_changed.emit()


func _add_stack(item, quantity: int) -> int:
	return _add_to_slots(slots, item, quantity)


func _add_to_slots(target_slots: Array[Dictionary], item, quantity: int) -> int:
	var remaining := quantity
	var added := 0
	for slot in target_slots:
		if str(slot["item_id"]) != item.item_id:
			continue
		var space: int = int(item.max_stack) - int(slot["quantity"])
		if space <= 0:
			continue
		var amount: int = mini(remaining, space)
		slot["quantity"] = int(slot["quantity"]) + amount
		remaining -= amount
		added += amount
		if remaining <= 0:
			return added
	for slot in target_slots:
		if not str(slot["item_id"]).is_empty():
			continue
		var amount: int = mini(remaining, int(item.max_stack))
		slot["item_id"] = item.item_id
		slot["quantity"] = amount
		remaining -= amount
		added += amount
		if remaining <= 0:
			return added
	return added


## What a death costs: a random half (rounded down) of the items in the backpack, counted
## one by one, so 7 yarn + 12 wood (19 items) loses 9 random ones. Items marked
## keep_on_death are never lost and do not count. Returns
## {"lost": {item_id: quantity}, "kept": {item_id: quantity}, "total": int, "lost_total": int}
## where "kept" lists the protected items the cat still has.
func apply_death_loss(rng: RandomNumberGenerator = null) -> Dictionary:
	_ensure_ready()
	var generator := rng if rng != null else RandomNumberGenerator.new()
	if rng == null:
		generator.randomize()
	var units: Array[int] = []  # one entry per loseable item: the slot it sits in
	var kept := {}
	for index in range(slots.size()):
		var slot: Dictionary = slots[index]
		var item_id := str(slot.get("item_id", ""))
		var quantity := int(slot.get("quantity", 0))
		if item_id.is_empty() or quantity <= 0:
			continue
		var item = get_item_data(item_id)
		if item != null and bool(item.keep_on_death):
			kept[item_id] = int(kept.get(item_id, 0)) + quantity
			continue
		for _unit in range(quantity):
			units.append(index)
	var total := units.size()
	var lose_count := total / 2
	# Random choice without replacement (Fisher-Yates partial shuffle).
	for i in range(lose_count):
		var j := generator.randi_range(i, total - 1)
		var swap := units[i]
		units[i] = units[j]
		units[j] = swap
	var lost := {}
	for i in range(lose_count):
		var slot_index := units[i]
		var item_id := str(slots[slot_index]["item_id"])
		lost[item_id] = int(lost.get(item_id, 0)) + 1
		slots[slot_index]["quantity"] = int(slots[slot_index]["quantity"]) - 1
		if int(slots[slot_index]["quantity"]) <= 0:
			slots[slot_index] = {"item_id": "", "quantity": 0}
	if lose_count > 0:
		for item_id in lost:
			item_removed.emit(str(item_id), int(lost[item_id]))
		inventory_changed.emit()
		_persist_change()
	return {"lost": lost, "kept": kept, "total": total, "lost_total": lose_count}


func _persist_change() -> void:
	if _loading:
		return
	if is_instance_valid(ProgressionManager):
		ProgressionManager.save_now()


func _result(success: bool, requested: int, added: int, remaining: int, reason: String) -> Dictionary:
	return {
		"success": success,
		"requested": requested,
		"added": added,
		"remaining": remaining,
		"reason": reason,
	}


func _remove_result(success: bool, requested: int, removed: int, reason: String) -> Dictionary:
	return {
		"success": success,
		"requested": requested,
		"removed": removed,
		"reason": reason,
	}
