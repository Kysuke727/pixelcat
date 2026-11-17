extends SceneTree

# Night look: tint, lights, fireflies, vignette; the HUD stays untouched; floating text stays readable.

var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check_scene(label: String, scene: Node, expected_lamps: int) -> void:
	var atmosphere: NightAtmosphere = scene.get_node_or_null("NightAtmosphere")
	_check(atmosphere != null and atmosphere.is_active(), "%s has an active NightAtmosphere" % label)
	if atmosphere == null:
		return
	_check(scene.get_child(scene.get_child_count() - 1) == atmosphere, "%s: the atmosphere is the last child (so everything it lights exists)" % label)
	var tint := atmosphere.canvas_modulate
	_check(tint != null and tint.color == atmosphere.ambient_color, "%s: the world is tinted with the ambient colour" % label)
	_check(tint.color.r < 0.8 and tint.color.g < 0.8 and tint.color.b < 0.9 and tint.color.r > 0.2, "%s: the tint is dark but not black (%s)" % [label, str(tint.color)])
	# The HUD must not be tinted: its controls live on CanvasLayers, not on the world canvas.
	for hud_name in ["BattleUI", "CoinUI", "QuickbarUI"]:
		var hud_node: Node = scene.get_node_or_null("HUD/" + hud_name)
		_check(hud_node != null and hud_node.get_parent() is CanvasLayer, "%s: %s sits on a CanvasLayer" % [label, hud_name])
		if hud_node is CanvasItem:
			_check((hud_node as CanvasItem).get_canvas() != tint.get_canvas(), "%s: %s is on a different canvas than the tint" % [label, hud_name])
	for layer_name in ["ExpeditionHUD", "ProgressionPanel"]:
		_check(scene.get_node_or_null(layer_name) is CanvasLayer, "%s: %s is a CanvasLayer (untinted)" % [label, layer_name])

	var lamp_lights := 0
	for light in atmosphere.lights:
		if str(light.name).begins_with("LampLight_"):
			lamp_lights += 1
			_check(light.texture != null and light.energy > 0.0 and light.color.r > 0.8, "%s: a lamp light is warm and has a texture" % label)
	_check(lamp_lights == expected_lamps, "%s: one light per street lamp (%d)" % [label, lamp_lights])
	var player := get_first_node_in_group("player")
	var cat_light: PointLight2D = player.get_node_or_null("CatLight")
	_check(cat_light != null and cat_light.get_parent() == player, "%s: a soft light follows the cat" % label)
	_check(scene.get_node("NightExit").get_node_or_null("ExitLight") != null, "%s: the exit glows" % label)
	for light in atmosphere.lights:
		_check(not light.shadow_enabled, "%s: lights do not cast shadows (cheap)" % label)
		break
	_check(atmosphere.firefly_emitters.size() == atmosphere.firefly_areas.size() and atmosphere.firefly_areas.size() >= 1, "%s: fireflies drift in %d areas" % [label, atmosphere.firefly_areas.size()])
	for index in range(atmosphere.firefly_emitters.size()):
		var emitter: CPUParticles2D = atmosphere.firefly_emitters[index]
		var area: Rect2 = atmosphere.firefly_areas[index]
		_check(emitter.position == area.get_center() and emitter.emission_rect_extents == area.size / 2.0, "%s: a firefly emitter covers its area" % label)
		_check(emitter.light_mask == 0, "%s: fireflies are not over-exposed by the lights" % label)
	var vignette: CanvasLayer = atmosphere.vignette_layer
	_check(vignette != null and vignette.layer == 3, "%s: the vignette is its own layer" % label)
	var vignette_rect: TextureRect = vignette.get_child(0)
	_check(vignette_rect.mouse_filter == Control.MOUSE_FILTER_IGNORE, "%s: the vignette never blocks clicks" % label)


func _run() -> void:
	var pm = root.get_node("ProgressionManager")
	pm._test_mode = true
	var exp = root.get_node("ExpeditionManager")
	var day = root.get_node("DayManager")
	var hit_feel = root.get_node("HitFeel")
	day.current_state = day.TimeState.NIGHT

	# --- Both night maps ----------------------------------------------------------------
	exp.run_active = false
	exp.begin_run("park")
	var park: Node = load("res://scenes/worlds/night_world.tscn").instantiate()
	root.add_child(park)
	current_scene = park
	await physics_frame
	await physics_frame
	_check_scene("park", park, 3)
	var atmosphere: NightAtmosphere = park.get_node("NightAtmosphere")

	# --- Lift: floating text and sparks stay readable ----------------------------------------------
	var lift := atmosphere.lift_modulate()
	_check(absf(lift.r * atmosphere.ambient_color.r - 1.0) < 0.001 and absf(lift.g * atmosphere.ambient_color.g - 1.0) < 0.001 and absf(lift.b * atmosphere.ambient_color.b - 1.0) < 0.001, "the lift exactly cancels the tint")
	var before := _labels(park)
	hit_feel.damage_number(Vector2(300.0, 300.0), "7")
	var added: Label = _new_label(park, before)
	_check(added != null and added.modulate.is_equal_approx(lift) and added.light_mask == 0, "a damage number is lifted and ignores the lights")
	var particles_before := _count(park, "CPUParticles2D")
	hit_feel.spark(Vector2(300.0, 300.0))
	var spark_node: CPUParticles2D = null
	for child in park.get_children():
		if child is CPUParticles2D and child.name != "Fireflies" and not atmosphere.firefly_emitters.has(child):
			spark_node = child
	_check(_count(park, "CPUParticles2D") == particles_before + 1 and spark_node != null and spark_node.modulate.is_equal_approx(lift) and spark_node.light_mask == 0, "sparks are lifted too")

	# --- Switching it off and on ------------------------------------------------------------------------------
	atmosphere.set_enabled(false)
	_check(not atmosphere.canvas_modulate.visible and not atmosphere.vignette_layer.visible, "switching off hides the tint and the vignette")
	var any_light_visible := false
	for light in atmosphere.lights:
		any_light_visible = any_light_visible or light.visible
	_check(not any_light_visible, "...and all the lights")
	_check(atmosphere.lift_modulate() == Color.WHITE, "...and there is nothing to cancel any more")
	var before_off := _labels(park)
	hit_feel.damage_number(Vector2(300.0, 300.0), "8")
	var added_off: Label = _new_label(park, before_off)
	_check(added_off != null and added_off.modulate == Color.WHITE, "with the effect off, floating text is not lifted")
	atmosphere.set_enabled(true)
	_check(atmosphere.canvas_modulate.visible and atmosphere.vignette_layer.visible and atmosphere.lights[0].visible, "switching back on restores everything")
	_check(atmosphere.lift_modulate() != Color.WHITE, "...including the lift")

	# --- A scene that starts with it disabled builds nothing ---------------------------------------------------------
	var off := NightAtmosphere.new()
	off.enabled = false
	park.add_child(off)
	_check(off.canvas_modulate == null and off.lights.is_empty() and off.vignette_layer == null and not off.is_active(), "a disabled atmosphere builds no tint, lights or vignette")
	_check(off.lift_modulate() == Color.WHITE, "...and lifts nothing")
	off.queue_free()

	# --- The forest -----------------------------------------------------------------------------------------------------
	park.queue_free()
	await process_frame
	exp.run_active = false
	exp.begin_run("forest_grove")
	var forest: Node = load("res://scenes/worlds/forest_grove.tscn").instantiate()
	root.add_child(forest)
	current_scene = forest
	await physics_frame
	await physics_frame
	var lamp_count := 0
	for child in forest.get_node("Decorations").get_children():
		if str(child.name).begins_with("StreetLamp") and child is Sprite2D:
			lamp_count += 1
	_check_scene("forest", forest, lamp_count)
	var forest_atmosphere: NightAtmosphere = forest.get_node("NightAtmosphere")
	# The cat light follows the cat for real.
	var cat: Node2D = get_first_node_in_group("player")
	cat.global_position = Vector2(900.0, 700.0)
	var cat_light: PointLight2D = cat.get_node("CatLight")
	_check(cat_light.global_position.distance_to(Vector2(900.0, 700.0)) < 1.0, "the cat's light moves with the cat")
	# A lamp light sits at the lamp head.
	var first_lamp: Sprite2D = forest.get_node("Decorations/StreetLamp1")
	var lamp_light: PointLight2D = forest.get_node("Decorations/LampLight_StreetLamp1")
	_check(lamp_light.global_position.x == first_lamp.global_position.x and lamp_light.global_position.y < first_lamp.global_position.y, "a lamp's light is above the lamp, at its head")
	var level: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/data/forest_grove_level.json"))
	_check(forest_atmosphere.firefly_areas.size() == level["firefly_areas"].size(), "the forest fireflies come from the map data (%d areas)" % level["firefly_areas"].size())

	exp.run_active = false
	day.current_state = day.TimeState.DAY

	if failures.is_empty():
		print("NIGHT_ATMOSPHERE_PASSED: %d checks" % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		quit(1)


func _labels(node: Node) -> Array:
	var result: Array = []
	for child in node.get_children():
		if child is Label:
			result.append(child)
	return result


func _new_label(node: Node, before: Array) -> Label:
	for child in node.get_children():
		if child is Label and not before.has(child):
			return child
	return null


func _count(node: Node, type_name: String) -> int:
	var count := 0
	for child in node.get_children():
		if child.get_class() == type_name:
			count += 1
	return count


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", description)
	else:
		failures.append(description)
