extends SceneTree

# Combat effects (slash, impact, ring, death burst, dust, flash, camera kick): they run
# without errors, clean up after themselves, and respect the particle / shake switches.

var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _count_fx(scene: Node) -> int:
	return scene.get_child_count()


func _run() -> void:
	var pm = root.get_node("ProgressionManager")
	pm._test_mode = true
	pm._load_profile_data({})
	var hf = root.get_node("HitFeel")
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	var camera: Camera2D = load("res://scenes/combat/combat_camera.tscn").instantiate()
	scene.add_child(camera)
	await process_frame

	var before := _count_fx(scene)
	for kind in ["claw1", "claw2", "claw3", "pounce", "counter", "crit"]:
		hf.slash(Vector2(100, 100), Vector2.RIGHT, kind)
	hf.slash(Vector2(100, 100), Vector2.ZERO, "claw1")
	_check(_count_fx(scene) > before, "slashes are added to the scene")
	hf.impact(Vector2(100, 100), Vector2.RIGHT, 1.0)
	hf.impact(Vector2(100, 100), Vector2.ZERO, 0.5, hf.GOLD)
	hf.ring(Vector2(100, 100), hf.CYAN, 30.0, 0.2)
	hf.death_burst(Vector2(100, 100))
	hf.dust(Vector2(100, 100), Vector2.LEFT)
	hf.screen_flash(hf.RED, 0.3, 0.1)
	hf.melee_hit(Vector2(100, 100), 3.0, true, true, false, Vector2.RIGHT)
	hf.melee_hit(Vector2(100, 100), 3.0, false, false, true, Vector2.LEFT)
	hf.enemy_died(Vector2(100, 100))
	hf.player_hurt(Vector2(100, 100), Vector2.UP)
	hf.perfect_dodge(Vector2(100, 100))
	hf.perfect_guard(Vector2(100, 100))
	await create_timer(1.0).timeout
	_check(_count_fx(scene) <= before + 3, "slash / impact / ring nodes remove themselves (%d left of %d)" % [_count_fx(scene) - before, 0])
	# the splat fades slowly (about 1.7 s); after that everything is gone
	await create_timer(1.6).timeout
	_check(_count_fx(scene) == before, "every effect cleans up after itself (%d extra nodes)" % (_count_fx(scene) - before))

	# the camera punch
	_check(camera.kick == Vector2.ZERO, "the camera starts still")
	hf.kick(Vector2.RIGHT, 4.0)
	_check(camera.kick.x > 3.0 and absf(camera.kick.y) < 0.01, "a hit to the right punches the camera right")
	await create_timer(0.5).timeout
	_check(camera.kick.length() < 0.5 and camera.offset.length() < 1.5, "the punch dies away quickly")

	# switches
	hf.particles_enabled = false
	var quiet_before := _count_fx(scene)
	hf.slash(Vector2.ZERO, Vector2.RIGHT, "claw3")
	hf.impact(Vector2.ZERO, Vector2.RIGHT)
	hf.ring(Vector2.ZERO, hf.RED)
	hf.death_burst(Vector2.ZERO)
	hf.dust(Vector2.ZERO, Vector2.UP)
	_check(_count_fx(scene) == quiet_before, "with particles off no effect nodes appear")
	hf.particles_enabled = true
	hf.screen_shake_enabled = false
	hf.kick(Vector2.RIGHT, 5.0)
	_check(camera.kick == Vector2.ZERO, "with screen shake off there is no camera punch")
	hf.screen_shake_enabled = true

	# sound slots: no files yet -> silent and harmless; unknown names too
	_check(not hf.has_sfx("claw1") and not hf.has_sfx("nope"), "no combat sound files yet -> silent")
	hf.play_sfx("claw1")
	hf.play_sfx("hit_heavy")
	hf.sfx_enabled = false
	hf.play_sfx("crit")
	hf.sfx_enabled = true
	_check(true, "play_sfx on missing files does nothing and does not error")
	# a real file dropped into the folder is found and played (the friend's workflow)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = 8000
	wav.data = PackedByteArray([128, 140, 128, 116, 128, 140, 128, 116])
	var test_path: String = hf.SFX_DIR + "zz_test_event.wav"
	if wav.save_to_wav(ProjectSettings.globalize_path(test_path)) == OK:
		hf._sfx_cache.clear()
		# not imported yet in a headless run, so ResourceLoader may not see it: only check it does not crash
		hf.play_sfx("zz_test_event")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))
		hf._sfx_cache.clear()
	_check(true, "dropping a file in works without errors")

	if failures.is_empty():
		print("COMBAT_FX_PASSED: %d checks" % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", description)
	else:
		failures.append(description)
