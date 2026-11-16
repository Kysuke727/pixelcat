extends CanvasLayer

## Edge-of-screen arrows for big maps. While hunting the last few enemies they point at the
## ones still alive; once every objective is done they point at the exit.
##
## Only enemies that count toward the objective are shown (the optional secret guard is not),
## and only those that are off screen.

## Arrows appear when this many (or fewer) objective enemies remain.
const SHOW_WHEN_REMAINING := 3
const MARGIN := 30.0
const ENEMY_COLOR := Color("#ff6a6a")
const EXIT_COLOR := Color("#ffd84d")
const OUTLINE := Color("#5c3a4b")

var _canvas: Control


func _ready() -> void:
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_arrows)
	add_child(_canvas)


func _process(_delta: float) -> void:
	_canvas.queue_redraw()


## The things to point at right now: [{"position": Vector2, "color": Color}]
func get_targets() -> Array:
	var result: Array = []
	if not ExpeditionManager.run_active:
		return result
	if ExpeditionManager.objectives_complete():
		var exit_gate := get_tree().current_scene.get_node_or_null("NightExit") as Node2D
		if exit_gate != null:
			result.append({"position": exit_gate.global_position, "color": EXIT_COLOR})
		return result
	var remaining: Array = []
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not (enemy is Node2D) or not enemy.has_method("is_alive") or not enemy.is_alive():
			continue
		if enemy.get("counts_toward_objective") == false:
			continue
		remaining.append(enemy)
	if remaining.size() > SHOW_WHEN_REMAINING:
		return result
	for enemy in remaining:
		result.append({"position": (enemy as Node2D).global_position, "color": ENEMY_COLOR})
	return result


## Where an off-screen point should be drawn: the point on the (inset) screen edge in its
## direction from the screen centre. Returns {} when the point is already on screen.
static func edge_point(screen_point: Vector2, screen_size: Vector2, margin: float = MARGIN) -> Dictionary:
	var inner := Rect2(Vector2(margin, margin), screen_size - Vector2(margin, margin) * 2.0)
	if Rect2(Vector2.ZERO, screen_size).has_point(screen_point):
		return {}
	var center := screen_size / 2.0
	var direction := screen_point - center
	if direction == Vector2.ZERO:
		return {}
	var half := inner.size / 2.0
	var scale_x := half.x / absf(direction.x) if direction.x != 0.0 else INF
	var scale_y := half.y / absf(direction.y) if direction.y != 0.0 else INF
	var factor := minf(scale_x, scale_y)
	return {"position": center + direction * factor, "angle": direction.angle()}


func _draw_arrows() -> void:
	var viewport := get_viewport()
	var size := viewport.get_visible_rect().size
	var to_screen := viewport.get_canvas_transform()
	for target in get_targets():
		var world_position: Vector2 = target["position"]
		var screen_point: Vector2 = to_screen * world_position
		var edge := edge_point(screen_point, size)
		if edge.is_empty():
			continue
		var color: Color = target["color"]
		var at: Vector2 = edge["position"]
		var angle: float = edge["angle"]
		var points := PackedVector2Array([Vector2(13, 0), Vector2(-8, -9), Vector2(-3, 0), Vector2(-8, 9)])
		var xform := Transform2D(angle, at)
		var placed := PackedVector2Array()
		for point in points:
			placed.append(xform * point)
		_canvas.draw_colored_polygon(placed, color)
		var outline := PackedVector2Array(placed)
		outline.append(placed[0])
		_canvas.draw_polyline(outline, OUTLINE, 2.0)
		var distance_tiles := int(round(world_position.distance_to(viewport.get_canvas_transform().affine_inverse() * (size / 2.0)) / 32.0))
		var text := "%dm" % distance_tiles
		var font := ThemeDB.fallback_font
		var text_offset := Vector2(-12.0, 26.0) if at.y < size.y / 2.0 else Vector2(-12.0, -14.0)
		_canvas.draw_string_outline(font, at + text_offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, OUTLINE)
		_canvas.draw_string(font, at + text_offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)
