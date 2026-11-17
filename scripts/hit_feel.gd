extends Node

## Central combat "juice": hit-stop, slow motion, camera shake, hit sparks,
## floating numbers and dash after-images. Gameplay code only calls the small
## semantic helpers (melee_hit, enemy_died, perfect_dodge, ...); all tuning of how
## a hit *feels* lives here.
##
## Accessibility / "relaxed game" switches: every effect family can be turned off.
## Time effects (hit-stop / slow motion) are off by default in test mode so tests
## stay deterministic.

var hit_stop_enabled: bool = true
var slow_motion_enabled: bool = true
var screen_shake_enabled: bool = true
var particles_enabled: bool = true
var damage_numbers_enabled: bool = true
## Master switch for effects that change Engine.time_scale.
var time_effects_enabled: bool = true

var _time_token: int = 0
var _flash_layer: CanvasLayer
var _flash_rect: ColorRect
var _flash_tween: Tween

const SLASH_SCRIPT := preload("res://scripts/slash_fx.gd")
const SFX_DIR := "res://assets/audio/sfx/combat/"
const SFX_EXTENSIONS := ["wav", "ogg", "mp3"]

## Combat sound effects are looked up by name in SFX_DIR (claw1, hit_light, dash, ...). A missing
## file just means silence, so the audio can be added later without touching code.
var sfx_enabled: bool = true
var _sfx_cache: Dictionary = {}

const INK := Color("#5c3a4b")
const CREAM := Color("#fff3c9")
const GOLD := Color("#ffd84d")
const PINK := Color("#f07aa0")
const CYAN := Color("#8fe3ff")
const RED := Color("#ff6a6a")
const CRIT := Color("#ff7a3d")
const GREEN := Color("#9be39b")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.get_environment("PIXELCAT_TEST_MODE") == "1":
		time_effects_enabled = false


func _exit_tree() -> void:
	Engine.time_scale = 1.0


# ---------------------------------------------------------------------------
# Semantic helpers called by gameplay code
# ---------------------------------------------------------------------------

## `direction` = from the cat towards the enemy that was hit (used for the slash-impact burst and
## the camera punch). `step` = which move it was: 1/2/3 = claw steps, 4 = pounce, 5 = counter claw.
func melee_hit(world_position: Vector2, amount: float, is_finisher: bool = false, is_heavy: bool = false, is_crit: bool = false, direction: Vector2 = Vector2.ZERO) -> void:
	if is_crit:
		_crit_hit(world_position, amount, direction)
		return
	var big := is_finisher or is_heavy
	var strength := 1.0 if is_heavy else (0.8 if is_finisher else 0.55)
	play_sfx("hit_heavy" if is_heavy else "hit_light")
	spark(world_position, GOLD if big else CREAM, 12 if is_heavy else (9 if is_finisher else 5), 150.0 if is_heavy else (130.0 if is_finisher else 100.0))
	impact(world_position, direction, strength, GOLD if big else CREAM)
	damage_number(world_position, _format_amount(amount), GOLD if big else CREAM, 22 if is_heavy else (18 if is_finisher else 14))
	hit_stop(0.1 if is_heavy else (0.075 if is_finisher else 0.04))
	shake(0.45 if is_heavy else (0.32 if is_finisher else 0.16))
	kick(direction, 5.0 if is_heavy else (3.5 if is_finisher else 2.0))


## A backstab crit: bigger, orange-red, longer freeze.
func _crit_hit(world_position: Vector2, amount: float, direction: Vector2 = Vector2.ZERO) -> void:
	spark(world_position, CRIT, 14, 170.0)
	spark(world_position, CREAM, 6, 110.0)
	impact(world_position, direction, 1.3, CRIT)
	damage_number(world_position, "暴击 %s" % _format_amount(amount), CRIT, 22)
	hit_stop(0.11)
	shake(0.5)
	kick(direction, 6.0)
	screen_flash(Color(1.0, 0.6, 0.3), 0.18, 0.12)


func yarn_hit(world_position: Vector2, amount: float) -> void:
	spark(world_position, PINK, 5, 90.0)
	damage_number(world_position, _format_amount(amount), PINK, 13)
	shake(0.1)


func enemy_died(world_position: Vector2) -> void:
	spark(world_position, GREEN, 14, 150.0)
	spark(world_position, CREAM, 6, 90.0)
	death_burst(world_position, GREEN)
	hit_stop(0.09)
	shake(0.3)


func player_hurt(world_position: Vector2, direction: Vector2 = Vector2.ZERO) -> void:
	play_sfx("player_hurt")
	spark(world_position, RED, 7, 110.0)
	ring(world_position, RED, 22.0, 0.22)
	hit_stop(0.06)
	shake(0.5)
	kick(direction, 4.0)
	screen_flash(RED, 0.3, 0.28)


func perfect_dodge(world_position: Vector2) -> void:
	play_sfx("perfect_dodge")
	spark(world_position, CYAN, 9, 130.0)
	damage_number(world_position + Vector2(0.0, -10.0), "闪避！", CYAN, 16)
	ring(world_position, CYAN, 34.0, 0.3)
	screen_flash(CYAN, 0.12, 0.2)
	slow_motion(0.3, 0.3)
	shake(0.12)


func perfect_guard(world_position: Vector2) -> void:
	play_sfx("perfect_guard")
	spark(world_position, GOLD, 10, 140.0)
	damage_number(world_position + Vector2(0.0, -10.0), "完美防御！", GOLD, 16)
	ring(world_position, GOLD, 30.0, 0.26)
	shake(0.25)


# ---------------------------------------------------------------------------
# Building blocks
# ---------------------------------------------------------------------------

## Play the combat sound called `event` (see assets/audio/sfx/combat/README.txt). Silent when
## there is no such file. Pitch varies a little so repeated hits do not sound identical.
func play_sfx(event: String, volume_db: float = 0.0, pitch_variation: float = 0.06) -> void:
	if not sfx_enabled:
		return
	var stream: AudioStream = _find_sfx(event)
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func has_sfx(event: String) -> bool:
	return _find_sfx(event) != null


func _find_sfx(event: String) -> AudioStream:
	if _sfx_cache.has(event):
		return _sfx_cache[event]
	var found: AudioStream = null
	for extension in SFX_EXTENSIONS:
		var path := "%s%s.%s" % [SFX_DIR, event, extension]
		if ResourceLoader.exists(path):
			found = load(path) as AudioStream
			if found != null:
				break
	_sfx_cache[event] = found
	return found


## One claw slash in front of the cat. kind: "claw1" / "claw2" (the two alternating swipes),
## "claw3" (heavy cross slash), "pounce" (forward streak), "counter" (spinning ring), "crit".
func slash(world_position: Vector2, direction: Vector2, kind: String = "claw1") -> void:
	if not particles_enabled:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var dir := direction.normalized() if direction != Vector2.ZERO else Vector2.DOWN
	play_sfx(kind if kind != "crit" else "crit")
	var specs: Array[Dictionary] = []
	match kind:
		"claw2":
			specs.append({"r": 33.0, "w": 15.0, "arc": 1.25, "color": CREAM, "dur": 0.2, "sweep": -1.0, "rot": 0.0})
		"claw3":
			specs.append({"r": 38.0, "w": 17.0, "arc": 1.35, "color": GOLD, "dur": 0.24, "sweep": 1.0, "rot": 0.28})
			specs.append({"r": 38.0, "w": 17.0, "arc": 1.35, "color": GOLD, "dur": 0.24, "sweep": -1.0, "rot": -0.28})
		"pounce":
			specs.append({"r": 40.0, "w": 14.0, "arc": 0.55, "color": GOLD, "dur": 0.18, "sweep": 1.0, "rot": 0.0})
			specs.append({"r": 30.0, "w": 9.0, "arc": 0.5, "color": CREAM, "dur": 0.16, "sweep": -1.0, "rot": 0.0})
		"counter":
			specs.append({"r": 30.0, "w": 12.0, "arc": 3.0, "color": CYAN, "dur": 0.24, "sweep": 1.0, "rot": 0.0, "circle": true})
		"crit":
			specs.append({"r": 36.0, "w": 16.0, "arc": 1.35, "color": CRIT, "dur": 0.2, "sweep": 1.0, "rot": 0.25})
			specs.append({"r": 36.0, "w": 16.0, "arc": 1.35, "color": CRIT, "dur": 0.2, "sweep": -1.0, "rot": -0.25})
		_:
			specs.append({"r": 32.0, "w": 15.0, "arc": 1.2, "color": CREAM, "dur": 0.2, "sweep": 1.0, "rot": 0.0})
	for spec in specs:
		var fx := Node2D.new()
		fx.set_script(SLASH_SCRIPT)
		fx.set("radius", spec["r"])
		fx.set("thickness", spec["w"])
		fx.set("half_arc", spec["arc"])
		fx.set("color", spec["color"])
		fx.set("duration", spec["dur"])
		fx.set("sweep", spec["sweep"])
		fx.set("full_circle", bool(spec.get("circle", false)))
		fx.z_index = 60
		fx.light_mask = 0
		fx.modulate = _lift()
		fx.rotation = dir.angle() + float(spec["rot"])
		scene.add_child(fx)
		fx.global_position = world_position + dir * 6.0


## The burst where a hit lands: a flash star of speed lines, an expanding ring and sparks that
## fly along the direction of the blow.
func impact(world_position: Vector2, direction: Vector2, strength: float = 1.0, color: Color = CREAM) -> void:
	if not particles_enabled:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var holder := Node2D.new()
	holder.z_index = 90
	holder.light_mask = 0
	holder.modulate = _lift()
	scene.add_child(holder)
	holder.global_position = world_position
	var base := direction.angle() if direction != Vector2.ZERO else randf() * TAU
	var lines := 6 + int(strength * 4.0)
	for i in range(lines):
		var angle := base + (TAU * float(i) / float(lines)) + randf_range(-0.12, 0.12)
		var line := Line2D.new()
		line.width = 2.0 if i % 2 == 0 else 1.0
		line.default_color = color if i % 3 else Color.WHITE
		var inner := 5.0 + randf() * 3.0
		var outer := (14.0 + randf() * 10.0) * (0.7 + strength * 0.5)
		# blows throw more lines forward than backwards
		if direction != Vector2.ZERO:
			var forward := Vector2.from_angle(angle).dot(direction)
			outer *= 1.0 + 0.5 * maxf(forward, 0.0)
		line.points = PackedVector2Array([Vector2.from_angle(angle) * inner, Vector2.from_angle(angle) * outer])
		var outline := Line2D.new()
		outline.width = line.width + 3.0
		outline.default_color = Color(INK.r, INK.g, INK.b, 0.8)
		outline.points = line.points
		holder.add_child(outline)
		holder.add_child(line)
		var outline_tween := outline.create_tween().set_parallel(true)
		outline_tween.tween_property(outline, "scale", Vector2(1.5, 1.5), 0.14)
		outline_tween.tween_property(outline, "modulate:a", 0.0, 0.14)
		var tween := line.create_tween().set_parallel(true)
		tween.tween_property(line, "scale", Vector2(1.5, 1.5), 0.14)
		tween.tween_property(line, "modulate:a", 0.0, 0.14)
	ring(world_position, color, 18.0 * (0.7 + strength * 0.5), 0.18, holder)
	if direction != Vector2.ZERO:
		var streak := CPUParticles2D.new()
		streak.one_shot = true
		streak.explosiveness = 1.0
		streak.amount = 4 + int(strength * 4.0)
		streak.lifetime = 0.22
		streak.direction = direction
		streak.spread = 28.0
		streak.gravity = Vector2.ZERO
		streak.initial_velocity_min = 110.0 * strength
		streak.initial_velocity_max = 210.0 * strength
		streak.damping_min = 160.0
		streak.damping_max = 260.0
		streak.scale_amount_min = 1.5
		streak.scale_amount_max = 3.0
		streak.color = color
		streak.light_mask = 0
		holder.add_child(streak)
		streak.emitting = true
	get_tree().create_timer(0.45).timeout.connect(holder.queue_free)


## An expanding, fading ring (shock wave).
func ring(world_position: Vector2, color: Color, radius: float = 24.0, duration: float = 0.22, parent: Node = null) -> void:
	if not particles_enabled:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var line := Line2D.new()
	var points := PackedVector2Array()
	for i in range(21):
		points.append(Vector2.from_angle(TAU * float(i) / 20.0))
	line.points = points
	line.width = 2.5
	line.default_color = color
	line.scale = Vector2.ONE * radius * 0.3
	line.z_index = 85
	line.light_mask = 0
	if parent != null:
		parent.add_child(line)
		line.position = Vector2.ZERO
	else:
		line.modulate = _lift()
		scene.add_child(line)
		line.global_position = world_position
	var tween := line.create_tween().set_parallel(true)
	tween.tween_property(line, "scale", Vector2.ONE * radius, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(line, "modulate:a", 0.0, duration)
	tween.chain().tween_callback(line.queue_free)


## Jelly chunks that fly out and fall, and a splat that fades on the ground.
func death_burst(world_position: Vector2, color: Color = GREEN) -> void:
	if not particles_enabled:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var chunks := CPUParticles2D.new()
	chunks.one_shot = true
	chunks.explosiveness = 1.0
	chunks.amount = 10
	chunks.lifetime = 0.55
	chunks.direction = Vector2.UP
	chunks.spread = 100.0
	chunks.gravity = Vector2(0.0, 420.0)
	chunks.initial_velocity_min = 70.0
	chunks.initial_velocity_max = 170.0
	chunks.scale_amount_min = 3.0
	chunks.scale_amount_max = 5.0
	chunks.color = color
	chunks.z_index = 80
	chunks.light_mask = 0
	chunks.modulate = _lift()
	scene.add_child(chunks)
	chunks.global_position = world_position
	chunks.emitting = true
	get_tree().create_timer(chunks.lifetime + 0.2).timeout.connect(chunks.queue_free)
	# the splat: a flat ellipse that shrinks and fades
	var splat := Polygon2D.new()
	var shape := PackedVector2Array()
	for i in range(16):
		var angle := TAU * float(i) / 16.0
		shape.append(Vector2(cos(angle) * 16.0, sin(angle) * 8.0))
	splat.polygon = shape
	splat.color = Color(color.r, color.g, color.b, 0.55)
	splat.z_index = -4
	splat.light_mask = 0
	splat.modulate = _lift()
	scene.add_child(splat)
	splat.global_position = world_position + Vector2(0.0, 6.0)
	splat.scale = Vector2(0.4, 0.4)
	var tween := splat.create_tween()
	tween.tween_property(splat, "scale", Vector2.ONE, 0.12)
	tween.tween_property(splat, "modulate:a", 0.0, 1.2).set_delay(0.5)
	tween.tween_callback(splat.queue_free)


## Little dust puffs kicked up when the cat dashes or dodges (`direction` = way it is going).
func dust(world_position: Vector2, direction: Vector2) -> void:
	if not particles_enabled:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var puff := CPUParticles2D.new()
	puff.one_shot = true
	puff.explosiveness = 0.9
	puff.amount = 6
	puff.lifetime = 0.3
	puff.direction = -direction if direction != Vector2.ZERO else Vector2.UP
	puff.spread = 50.0
	puff.gravity = Vector2.ZERO
	puff.initial_velocity_min = 25.0
	puff.initial_velocity_max = 60.0
	puff.damping_min = 80.0
	puff.damping_max = 120.0
	puff.scale_amount_min = 2.0
	puff.scale_amount_max = 4.0
	puff.color = Color(0.85, 0.8, 0.7, 0.7)
	puff.z_index = 5
	puff.light_mask = 0
	puff.modulate = _lift()
	scene.add_child(puff)
	puff.global_position = world_position + Vector2(0.0, 10.0)
	puff.emitting = true
	get_tree().create_timer(puff.lifetime + 0.2).timeout.connect(puff.queue_free)


## A brief coloured wash over the whole screen (being hit, a crit, a perfect dodge).
func screen_flash(color: Color, alpha: float = 0.25, duration: float = 0.2) -> void:
	if not particles_enabled:
		return
	if _flash_layer == null or not is_instance_valid(_flash_layer):
		_flash_layer = CanvasLayer.new()
		_flash_layer.layer = 40
		add_child(_flash_layer)
		_flash_rect = ColorRect.new()
		_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_flash_rect.color = Color(1, 1, 1, 0)
		_flash_layer.add_child(_flash_rect)
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_rect.color = Color(color.r, color.g, color.b, alpha)
	_flash_tween = _flash_rect.create_tween()
	_flash_tween.tween_property(_flash_rect, "color:a", 0.0, duration)


## Punch the camera away from the cat (directional, unlike the random shake).
func kick(direction: Vector2, amount: float) -> void:
	if not screen_shake_enabled or direction == Vector2.ZERO:
		return
	for camera in get_tree().get_nodes_in_group("combat_camera"):
		if camera.has_method("add_kick"):
			camera.add_kick(direction, amount)


## Freeze the game for a few frames when a hit lands.
func hit_stop(duration: float, time_scale: float = 0.04) -> void:
	if not (time_effects_enabled and hit_stop_enabled):
		return
	_run_time_scale(time_scale, duration)


func slow_motion(duration: float, time_scale: float = 0.35) -> void:
	if not (time_effects_enabled and slow_motion_enabled):
		return
	_run_time_scale(time_scale, duration)


func _run_time_scale(time_scale: float, duration: float) -> void:
	if duration <= 0.0:
		return
	_time_token += 1
	var token := _time_token
	# Overlapping effects: the strongest (lowest) scale wins until the latest expires.
	Engine.time_scale = minf(Engine.time_scale, time_scale) if Engine.time_scale < 1.0 else time_scale
	# Real-time timer (ignores Engine.time_scale), so the game always resumes.
	await get_tree().create_timer(duration, true, false, true).timeout
	if token == _time_token:
		Engine.time_scale = 1.0


func shake(strength: float) -> void:
	if not screen_shake_enabled:
		return
	for camera in get_tree().get_nodes_in_group("combat_camera"):
		if camera.has_method("add_trauma"):
			camera.add_trauma(strength)


## A small burst of pixel squares.
func spark(world_position: Vector2, color: Color = CREAM, count: int = 6, speed: float = 100.0) -> void:
	if not particles_enabled:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var particles := CPUParticles2D.new()
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = maxi(count, 1)
	particles.lifetime = 0.28
	particles.direction = Vector2.UP
	particles.spread = 180.0
	particles.gravity = Vector2.ZERO
	particles.initial_velocity_min = speed * 0.45
	particles.initial_velocity_max = speed
	particles.damping_min = 180.0
	particles.damping_max = 240.0
	particles.scale_amount_min = 2.0
	particles.scale_amount_max = 3.0
	particles.color = color
	particles.z_index = 80
	particles.modulate = _lift()
	particles.light_mask = 0
	scene.add_child(particles)
	particles.global_position = world_position
	particles.emitting = true
	get_tree().create_timer(particles.lifetime + 0.2).timeout.connect(particles.queue_free)


## A number / word that pops, rises and fades.
func damage_number(world_position: Vector2, text: String, color: Color = CREAM, font_size: int = 14) -> void:
	if not damage_numbers_enabled:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 100
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", INK)
	label.add_theme_constant_override("outline_size", 5)
	label.modulate = _lift()
	label.light_mask = 0  # not lit by the night lights: the lift above already cancels the tint
	scene.add_child(label)
	label.reset_size()
	label.global_position = world_position - label.size / 2.0 + Vector2(randf_range(-8.0, 8.0), -14.0)
	label.pivot_offset = label.size / 2.0
	label.scale = Vector2(1.5, 1.5)
	var tween := label.create_tween().set_parallel(true)
	tween.tween_property(label, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "global_position:y", label.global_position.y - 22.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.25).set_delay(0.4)
	tween.chain().tween_callback(label.queue_free)


## A fading copy of an AnimatedSprite2D's current frame (dash trail).
func afterimage(source: AnimatedSprite2D, tint: Color = Color(1.0, 1.0, 1.0, 0.55)) -> void:
	if not particles_enabled or source == null or source.sprite_frames == null:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var texture := source.sprite_frames.get_frame_texture(source.animation, source.frame)
	if texture == null:
		return
	var ghost := Sprite2D.new()
	ghost.texture = texture
	ghost.centered = source.centered
	ghost.offset = source.offset
	ghost.flip_h = source.flip_h
	ghost.modulate = tint
	# Same z as the cat (a lower z would hide it under the floor), but inserted just
	# before the cat's top-level node so it is drawn behind it.
	ghost.z_index = source.z_index
	scene.add_child(ghost)
	var top: Node = source
	while top.get_parent() != null and top.get_parent() != scene:
		top = top.get_parent()
	if top.get_parent() == scene:
		scene.move_child(ghost, top.get_index())
	ghost.global_position = source.global_position
	ghost.global_scale = source.global_scale
	var tween := ghost.create_tween()
	tween.tween_property(ghost, "modulate:a", 0.0, 0.22)
	tween.tween_callback(ghost.queue_free)


## Colour that cancels a night map's dark tint (white when there is none), so floating text and
## sparks stay readable at night.
func _lift() -> Color:
	for atmosphere in get_tree().get_nodes_in_group("night_atmosphere"):
		if atmosphere.has_method("lift_modulate"):
			return atmosphere.lift_modulate()
	return Color.WHITE


func _format_amount(amount: float) -> String:
	return str(maxi(int(round(amount)), 1))
