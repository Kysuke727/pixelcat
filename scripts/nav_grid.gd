extends RefCounted

## Grid path-finding for enemies on tile maps (the forest). Built once per Terrain layer from the
## tiles' collision shapes and shared by every enemy. Maps without a "Terrain" TileMapLayer
## (the park) get null and enemies keep walking straight at the cat.

static var _cache: Dictionary = {}   # terrain instance id -> AStarGrid2D


static func for_scene(scene: Node) -> AStarGrid2D:
	if scene == null:
		return null
	var terrain := scene.get_node_or_null("Terrain") as TileMapLayer
	if terrain == null or terrain.tile_set == null:
		return null
	var key := terrain.get_instance_id()
	if _cache.has(key):
		return _cache[key]
	for old_key in _cache.keys():
		if not is_instance_id_valid(old_key):
			_cache.erase(old_key)
	var grid := AStarGrid2D.new()
	grid.region = terrain.get_used_rect()
	grid.cell_size = Vector2(terrain.tile_set.tile_size)
	grid.offset = grid.cell_size / 2.0
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	for cell in terrain.get_used_cells():
		var data := terrain.get_cell_tile_data(cell)
		if data != null and data.get_collision_polygons_count(0) > 0:
			grid.set_point_solid(cell, true)
	# Lamps, signposts, benches... are solid too (static bodies on the world layer).
	for body in scene.find_children("*", "StaticBody2D", true, false):
		if (body.collision_layer & 1) == 0:
			continue
		for shape_node in body.get_children():
			if not shape_node is CollisionShape2D or shape_node.shape == null or shape_node.disabled:
				continue
			var rect: Rect2 = shape_node.global_transform * shape_node.shape.get_rect()
			var first := cell_of(grid, rect.position)
			var last := cell_of(grid, rect.end)
			for cy in range(first.y, last.y + 1):
				for cx in range(first.x, last.x + 1):
					if grid.is_in_bounds(cx, cy):
						grid.set_point_solid(Vector2i(cx, cy), true)
	_cache[key] = grid
	return grid


static func cell_of(grid: AStarGrid2D, world: Vector2) -> Vector2i:
	return Vector2i(floori(world.x / grid.cell_size.x), floori(world.y / grid.cell_size.y))
