extends SceneTree

## Builds res://scenes/worlds/forest_grove.tscn from the level data
## (tools/data/forest_grove_level.json, written by tools/make_forest_tiles.py).
##
##   python3 tools/make_forest_tiles.py
##   godot --headless --path . --script res://tools/build_forest_grove.gd
##
## The HUD and expedition logic nodes are taken from the park scene so the two night maps
## behave identically; only the terrain, enemies and objects differ. After the first build
## the .tscn is the source of truth: you can open it in Godot, repaint the tiles, move
## enemies, etc. Re-running this tool overwrites those edits.

const PARK_SCENE := "res://scenes/worlds/night_world.tscn"
const SLIME_SCENE := "res://scenes/enemies/slime.tscn"
const LEVEL_JSON := "res://tools/data/forest_grove_level.json"
const TILESET_PATH := "res://assets/tilesets/forest_tileset.tres"
const OUT_PATH := "res://scenes/worlds/forest_grove.tscn"

var park: Node
var map_root: Node2D
var level: Dictionary


func _initialize() -> void:
	var file := FileAccess.open(LEVEL_JSON, FileAccess.READ)
	if file == null:
		push_error("Missing %s - run tools/make_forest_tiles.py first" % LEVEL_JSON)
		quit(1)
		return
	level = JSON.parse_string(file.get_as_text())
	park = (load(PARK_SCENE) as PackedScene).instantiate()
	map_root = Node2D.new()
	map_root.name = "ForestGrove"
	map_root.add_to_group("night_exploration", true)

	_add_terrain()
	_add_props()
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	hud.layer = 5
	_adopt(hud)
	_take("CoinUI", hud)
	_take("BattleUI", hud)
	_take("QuickbarUI", hud)
	var cat := _take("Cat", map_root)
	cat.position = _vec(level["start"])
	_add_enemies()
	_add_music()
	_add_safe_points()
	var exit_gate := _take("NightExit", map_root)
	exit_gate.position = _vec(level["exit"])
	for node_name in ["ExpeditionHUD", "NightRunController", "ProgressionPanel", "DebugPanel", "InventoryUI", "CraftingUI"]:
		_take(node_name, map_root)
	var camera := _take("CombatCamera", map_root)
	camera.set("follow_player", true)
	var world: Array = level["world"]
	camera.set("world_rect", Rect2(0, 0, float(world[0]), float(world[1])))

	park.free()
	var packed := PackedScene.new()
	var pack_error := packed.pack(map_root)
	if pack_error != OK:
		push_error("pack failed: %d" % pack_error)
		quit(1)
		return
	var save_error := ResourceSaver.save(packed, OUT_PATH)
	if save_error != OK:
		push_error("save failed: %d" % save_error)
		quit(1)
		return
	print("FOREST_GROVE_BUILT ", OUT_PATH)
	quit(0)


func _vec(value: Variant) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))


## Add a node we created ourselves (and its children) to the scene root.
func _adopt(node: Node, parent: Node = null) -> void:
	(parent if parent != null else map_root).add_child(node)
	_set_owner_recursive(node)


func _set_owner_recursive(node: Node) -> void:
	node.owner = map_root
	if node.scene_file_path.is_empty():
		for child in node.get_children():
			_set_owner_recursive(child)


## Move a node of the park scene into the new scene, keeping its configuration.
func _take(node_name: String, new_parent: Node) -> Node:
	var node := park.get_node(node_name)
	var owners := {}
	for child in node.find_children("*", "", true, false):
		owners[child] = child.owner
	park.remove_child(node)
	# Clear the old owners first, otherwise Godot warns they are inconsistent.
	node.owner = null
	for child in owners:
		child.owner = null
	new_parent.add_child(node)
	node.owner = map_root
	for child in owners:
		child.owner = node if owners[child] == node else map_root
	return node


# ---------------------------------------------------------------------------

func _add_terrain() -> void:
	var tileset := _make_tileset()
	var layer := TileMapLayer.new()
	layer.name = "Terrain"
	layer.tile_set = tileset
	layer.z_index = -10
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var grid: Array = level["grid"]
	for r in range(grid.size()):
		var row: Array = grid[r]
		for c in range(row.size()):
			layer.set_cell(Vector2i(c, r), 0, Vector2i(int(row[c]), 0))
	_adopt(layer)


func _make_tileset() -> TileSet:
	var tile := int(level["tile"])
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(tile, tile)
	tileset.add_physics_layer()
	tileset.set_physics_layer_collision_layer(0, 1)
	tileset.set_physics_layer_collision_mask(0, 0)
	var source := TileSetAtlasSource.new()
	source.texture = load("res://assets/tilesets/forest_tiles.png")
	source.texture_region_size = Vector2i(tile, tile)
	# The source must belong to the TileSet (which owns the physics layer) before
	# per-tile collision shapes can be set.
	tileset.add_source(source, 0)
	var names: Array = level["tile_names"]
	var solid: Array = level["solid"]
	var half := float(tile) / 2.0
	for i in range(names.size()):
		source.create_tile(Vector2i(i, 0))
		if solid.has(names[i]):
			var data := source.get_tile_data(Vector2i(i, 0), 0)
			data.add_collision_polygon(0)
			data.set_collision_polygon_points(0, 0, PackedVector2Array([
				Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)
			]))
	ResourceSaver.save(tileset, TILESET_PATH)
	return load(TILESET_PATH)


func _add_props() -> void:
	var decorations := Node2D.new()
	decorations.name = "Decorations"
	_adopt(decorations)
	var lamp_texture: Texture2D = load("res://assets/objects/street_lamp.png")
	var lamp_shape := CircleShape2D.new()
	lamp_shape.radius = 10.0
	var lamp_index := 1
	for lamp in level["lamps"]:
		var position := _vec(lamp)
		var sprite := Sprite2D.new()
		sprite.name = "StreetLamp%d" % lamp_index
		sprite.texture = lamp_texture
		sprite.scale = Vector2(0.75, 0.75)
		sprite.position = position
		_adopt(sprite, decorations)
		var body := StaticBody2D.new()
		body.name = "LampCollider%d" % lamp_index
		body.position = position + Vector2(0.0, 6.0)
		body.collision_layer = 1
		body.collision_mask = 0
		_adopt(body, decorations)
		var shape := CollisionShape2D.new()
		shape.shape = lamp_shape
		_adopt(shape, body)
		lamp_index += 1

	# Faint paw prints leading towards the secret trail (kept subtle on purpose).
	var paw_texture: Texture2D = load("res://assets/props/pawprint.png")
	var paw_index := 1
	for paw in level["pawprints"]:
		var print_sprite := Sprite2D.new()
		print_sprite.name = "PawPrint%d" % paw_index
		print_sprite.texture = paw_texture
		print_sprite.position = _vec(paw)
		print_sprite.scale = Vector2(1.5, 1.5)
		print_sprite.flip_h = paw_index % 2 == 0
		print_sprite.rotation = -0.5
		print_sprite.modulate = Color(1.0, 1.0, 1.0, 0.32)
		print_sprite.z_index = -5
		print_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_adopt(print_sprite, decorations)
		paw_index += 1

	# The old tree hollow, and the secret spot inside it.
	var secret := _vec(level["secret"])
	var hollow := Sprite2D.new()
	hollow.name = "TreeHollow"
	hollow.texture = load("res://assets/props/tree_hollow.png")
	hollow.position = secret + Vector2(0.0, -14.0)
	hollow.scale = Vector2(1.5, 1.5)
	hollow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_adopt(hollow, decorations)
	# The script is attached at run time (not via its class name) so this tool does not
	# need the autoload singletons the script uses at compile time.
	var spot := Area2D.new()
	spot.set_script(load("res://scripts/secret_spot.gd"))
	spot.name = "SecretSpot"
	spot.position = secret + Vector2(0.0, 22.0)
	spot.collision_layer = 0
	spot.collision_mask = 1
	spot.set("move_id", "triple_combo")
	_adopt(spot)
	var spot_shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 34.0
	spot_shape.shape = circle
	_adopt(spot_shape, spot)


func _add_enemies() -> void:
	var slime_scene: PackedScene = load(SLIME_SCENE)
	var index := 1
	for enemy_position in level["enemies"]:
		var slime := slime_scene.instantiate()
		slime.name = "Slime%d" % index
		slime.position = _vec(enemy_position)
		_adopt(slime)
		index += 1


func _add_music() -> void:
	# The park uses a positional player at the origin; on a big map that would fade out
	# as the cat walks away, so the forest uses a plain (non-positional) player.
	var original: AudioStreamPlayer2D = park.get_node("NightMusic")
	var music := AudioStreamPlayer.new()
	music.name = "NightMusic"
	music.stream = original.stream
	music.autoplay = true
	_adopt(music)


func _add_safe_points() -> void:
	var template: Node = park.get_node("SafePointPark")
	var index := 1
	for safe in level["safe"]:
		var point: Node2D = template.duplicate()
		point.name = "SafePoint%d" % index
		point.position = _vec(safe["pos"])
		point.scale = Vector2.ONE
		point.set("checkpoint_label", str(safe["label"]))
		_adopt(point)
		var label := point.get_node_or_null("Label") as Label
		if label != null:
			label.text = str(safe["label"])
		index += 1
