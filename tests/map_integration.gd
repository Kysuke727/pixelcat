extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var day_manager := root.get_node("DayManager")
	_check(day_manager.DAY_SCENE == "res://scenes/main.tscn", "day scene path remains main.tscn")
	_check(day_manager.NIGHT_SCENE == "res://scenes/worlds/night_world.tscn", "night scene path remains night_world.tscn")

	var day_scene: Node = load("res://scenes/main.tscn").instantiate()
	_disable_audio(day_scene)
	root.add_child(day_scene)
	current_scene = day_scene
	await process_frame
	_check(day_scene.get_node_or_null("Cat") != null, "day map keeps the player cat")
	_check(day_scene.get_node_or_null("Cat/PlayerCombat") != null, "day map keeps the combat controller")
	_check(day_scene.get_node_or_null("Cat/Stats") != null, "day map keeps cat stats")
	_check(day_scene.get_node_or_null("World/Toy") != null, "day map keeps the toy interaction")
	_check(day_scene.get_node_or_null("World/Bed") != null, "day map keeps the bed interaction")
	_check(day_scene.get_node_or_null("World/FoodBowl") != null, "day map keeps the food bowl interaction")
	_check(day_scene.get_node_or_null("World/ExitDoor") != null, "day map keeps the exit door")
	_check(day_scene.get_node_or_null("UI") != null, "day map keeps the status HUD")
	_check(day_scene.get_node_or_null("InventoryUI") != null, "day map keeps the inventory UI")
	_check(day_scene.get_node_or_null("QuickbarUI") != null, "day map contains the quickbar UI")
	var day_wall_top: CollisionShape2D = day_scene.get_node("World/wall_top/CollisionShape2D")
	var day_wall_bottom: CollisionShape2D = day_scene.get_node("World/wall_bottom/CollisionShape2D")
	var day_wall_left: CollisionShape2D = day_scene.get_node("World/wall_left/CollisionShape2D")
	var day_wall_right: CollisionShape2D = day_scene.get_node("World/wall_right/CollisionShape2D")
	_check(_shape_size(day_wall_top) == Vector2(1152, 40), "day top wall uses the new 1152-wide map")
	_check(_shape_size(day_wall_bottom) == Vector2(1152, 40), "day bottom wall uses the new map")
	_check(_shape_size(day_wall_left) == Vector2(40, 648), "day left wall uses the new map")
	_check(_shape_size(day_wall_right) == Vector2(560, 40), "day right wall keeps the friend map collision shape")
	_check(day_wall_top.position == Vector2(576, 20), "day top wall is positioned for the new map")
	_check(day_wall_bottom.position == Vector2(576, 628), "day bottom wall is positioned for the new map")
	_check(day_wall_left.position == Vector2(324, -20), "day left wall is positioned for the new map")
	_check(day_wall_right.position == Vector2(325, -1132), "day right wall is positioned for the new map")
	_check(day_scene.get_node("World/Toy").scale == Vector2(3, 3), "day furniture keeps the new map scale")
	_check(day_scene.get_node("UI").position == Vector2(40, 40), "day HUD uses the new map offset")
	_check(day_scene.get_node_or_null("LeftBorder") == null, "obsolete left border is removed from the new day map")
	day_scene.queue_free()
	await process_frame
	await process_frame

	var night_scene: Node = load("res://scenes/worlds/night_world.tscn").instantiate()
	_disable_audio(night_scene)
	root.add_child(night_scene)
	current_scene = night_scene
	await process_frame
	_check(night_scene.is_in_group("night_exploration"), "night map keeps its exploration scene group")
	_check(night_scene.get_node_or_null("Cat") != null, "night map keeps the player cat")
	_check(night_scene.get_node_or_null("SlimeA") != null and night_scene.get_node_or_null("SlimeB") != null and night_scene.get_node_or_null("SlimeC") != null, "night map keeps all three slimes")
	_check(night_scene.get_node_or_null("NightExit") != null, "night map keeps the extraction gate")
	_check(night_scene.get_node_or_null("SafePointPark") != null and night_scene.get_node_or_null("SafePointStreet") != null, "night map keeps both safe points")
	_check(night_scene.get_node_or_null("NightRunController") != null, "night map keeps the run controller")
	_check(night_scene.get_node_or_null("BattleUI") != null and night_scene.get_node_or_null("CoinUI") != null, "night map keeps combat and currency HUDs")
	_check(night_scene.get_node_or_null("InventoryUI") != null, "night map contains the inventory UI")
	_check(night_scene.get_node_or_null("QuickbarUI") != null, "night map contains the quickbar UI")
	var night_wall_top: CollisionShape2D = night_scene.get_node("Walls/WallTop/CollisionShape2D")
	var night_wall_bottom: CollisionShape2D = night_scene.get_node("Walls/WallBottom/CollisionShape2D")
	var night_wall_left: CollisionShape2D = night_scene.get_node("Walls/WallLeft/CollisionShape2D")
	var night_wall_right: CollisionShape2D = night_scene.get_node("Walls/WallRight/CollisionShape2D")
	_check(_shape_size(night_wall_top) == Vector2(1152, 40), "night top wall uses the new map")
	_check(_shape_size(night_wall_bottom) == Vector2(1152, 40), "night bottom wall uses the new map")
	_check(_shape_size(night_wall_left) == Vector2(40, 648), "night left wall uses the new map")
	_check(_shape_size(night_wall_right) == Vector2(40, 648), "night right wall uses the new map")
	_check(night_wall_top.position == Vector2(576, 20), "night top wall is positioned for the new map")
	_check(night_wall_bottom.position == Vector2(576, 628), "night bottom wall is positioned for the new map")
	_check(night_wall_left.position == Vector2(20, 324), "night left wall is positioned for the new map")
	_check(night_wall_right.position == Vector2(1152, 324), "night right wall is positioned for the new map")
	_check(night_scene.get_node("Groud/NightFloor").scale.is_equal_approx(Vector2(1.1730138, 0.9273835)), "night floor uses the new map scale")
	_check(night_scene.get_node("Groud/Street").scale.is_equal_approx(Vector2(1.013099, 0.9251612)), "night street uses the new map scale")
	_check(night_scene.get_node("ExpeditionHUD/Panel").offset_left == 812.0, "night expedition HUD uses the new map offset")

	night_scene.queue_free()
	current_scene = null
	await process_frame
	await process_frame

	if failures.is_empty():
		print("MAP_INTEGRATION_PASSED")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		quit(1)


func _shape_size(shape_node: CollisionShape2D) -> Vector2:
	var shape := shape_node.shape as RectangleShape2D
	return shape.size if shape != null else Vector2.ZERO


func _disable_audio(scene: Node) -> void:
	for audio_player in scene.find_children("*", "AudioStreamPlayer", true, false):
		audio_player.autoplay = false
		audio_player.stream = null
	for audio_player in scene.find_children("*", "AudioStreamPlayer2D", true, false):
		audio_player.autoplay = false
		audio_player.stream = null


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		failures.append(description)
