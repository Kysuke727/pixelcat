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

func melee_hit(world_position: Vector2, amount: float, is_finisher: bool = false, is_heavy: bool = false, is_crit: bool = false) -> void:
	if is_crit:
		_crit_hit(world_position, amount)
		return
	var big := is_finisher or is_heavy
	spark(world_position, GOLD if big else CREAM, 12 if is_heavy else (9 if is_finisher else 5), 150.0 if is_heavy else (130.0 if is_finisher else 100.0))
	damage_number(world_position, _format_amount(amount), GOLD if big else CREAM, 22 if is_heavy else (18 if is_finisher else 14))
	hit_stop(0.1 if is_heavy else (0.075 if is_finisher else 0.04))
	shake(0.45 if is_heavy else (0.32 if is_finisher else 0.16))


## A backstab crit: bigger, orange-red, longer freeze.
func _crit_hit(world_position: Vector2, amount: float) -> void:
	spark(world_position, CRIT, 14, 170.0)
	spark(world_position, CREAM, 6, 110.0)
	damage_number(world_position, "暴击 %s" % _format_amount(amount), CRIT, 22)
	hit_stop(0.11)
	shake(0.5)


func yarn_hit(world_position: Vector2, amount: float) -> void:
	spark(world_position, PINK, 5, 90.0)
	damage_number(world_position, _format_amount(amount), PINK, 13)
	shake(0.1)


func enemy_died(world_position: Vector2) -> void:
	spark(world_position, GREEN, 14, 150.0)
	spark(world_position, CREAM, 6, 90.0)
	hit_stop(0.09)
	shake(0.3)


func player_hurt(world_position: Vector2) -> void:
	spark(world_position, RED, 7, 110.0)
	hit_stop(0.06)
	shake(0.5)


func perfect_dodge(world_position: Vector2) -> void:
	spark(world_position, CYAN, 9, 130.0)
	damage_number(world_position + Vector2(0.0, -10.0), "闪避！", CYAN, 16)
	slow_motion(0.3, 0.3)
	shake(0.12)


func perfect_guard(world_position: Vector2) -> void:
	spark(world_position, GOLD, 10, 140.0)
	damage_number(world_position + Vector2(0.0, -10.0), "完美防御！", GOLD, 16)
	shake(0.25)


# ---------------------------------------------------------------------------
# Building blocks
# ---------------------------------------------------------------------------

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
