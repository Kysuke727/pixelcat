extends Node
class_name NightAtmosphere

## The look of a night map: a dark blue tint over the WORLD (the HUD lives on its own canvas
## layers and is untouched), warm light on street lamps, a soft light that follows the cat, a
## glow at the exit, drifting fireflies and a faint vignette.
##
## Drop one NightAtmosphere node into a night scene (as the LAST child so the cat and the other
## nodes exist already). Everything is built at run time from what the scene contains:
##   * Sprite2D nodes named "StreetLamp*"  -> a warm light
##   * the node in group "player"          -> a soft light that follows it
##   * a node named "NightExit"            -> a cool glow
## Set `enabled = false` (or call set_enabled) for players who prefer a bright map.

@export var enabled: bool = true
@export var ambient_color: Color = Color("#5a6896")
@export var lamp_color: Color = Color("#ffc980")
@export var lamp_energy: float = 1.1
@export var lamp_texture_scale: float = 3.2
@export var player_color: Color = Color("#ffeacc")
@export var player_energy: float = 0.75
@export var player_texture_scale: float = 2.6
@export var exit_color: Color = Color("#9fe3ff")
@export var exit_energy: float = 0.9
@export var exit_texture_scale: float = 1.8
@export_range(0.0, 1.0) var vignette_strength: float = 0.35
## World rectangles where fireflies drift (the builders fill these from the map data).
@export var firefly_areas: Array[Rect2] = []
@export var fireflies_per_area: int = 10

var canvas_modulate: CanvasModulate
var lights: Array[PointLight2D] = []
var vignette_layer: CanvasLayer
var firefly_emitters: Array[CPUParticles2D] = []

static var _light_texture: GradientTexture2D


func _ready() -> void:
	add_to_group("night_atmosphere")
	if enabled:
		_build()


func is_active() -> bool:
	return enabled and canvas_modulate != null


## Turn the whole effect on or off at run time (a future settings menu can call this).
func set_enabled(value: bool) -> void:
	enabled = value
	if enabled and canvas_modulate == null:
		_build()
	if canvas_modulate != null:
		canvas_modulate.visible = enabled
		for light in lights:
			if is_instance_valid(light):
				light.visible = enabled
		for emitter in firefly_emitters:
			emitter.visible = enabled
		if vignette_layer != null:
			vignette_layer.visible = enabled


## Things drawn in the world (damage numbers, sparks) would be darkened by the tint too and become
## hard to read; multiplying them by this colour cancels the tint out.
func lift_modulate() -> Color:
	if not is_active():
		return Color.WHITE
	return Color(
		1.0 / maxf(ambient_color.r, 0.05),
		1.0 / maxf(ambient_color.g, 0.05),
		1.0 / maxf(ambient_color.b, 0.05),
		1.0
	)


func _build() -> void:
	var scene := get_parent()
	canvas_modulate = CanvasModulate.new()
	canvas_modulate.name = "AmbientTint"
	canvas_modulate.color = ambient_color
	add_child(canvas_modulate)

	for lamp in scene.find_children("StreetLamp*", "Sprite2D", true, false):
		var holder := lamp.get_parent()
		var light := _make_light(lamp_color, lamp_energy, lamp_texture_scale)
		light.name = "LampLight_" + str(lamp.name)
		holder.add_child(light)
		light.position = (lamp as Node2D).position + Vector2(0.0, -34.0)

	var player := get_tree().get_first_node_in_group("player")
	if player != null:
		var player_light := _make_light(player_color, player_energy, player_texture_scale)
		player_light.name = "CatLight"
		player.add_child(player_light)

	var exit_gate := scene.get_node_or_null("NightExit")
	if exit_gate != null:
		var exit_light := _make_light(exit_color, exit_energy, exit_texture_scale)
		exit_light.name = "ExitLight"
		exit_gate.add_child(exit_light)

	for area in firefly_areas:
		_add_fireflies(area)
	_add_vignette()


func _make_light(color: Color, energy: float, texture_scale: float) -> PointLight2D:
	var light := PointLight2D.new()
	light.texture = _get_light_texture()
	light.color = color
	light.energy = energy
	light.texture_scale = texture_scale
	light.shadow_enabled = false
	lights.append(light)
	return light


## A round, smoothly fading white blob: the shape of every light in the game.
static func _get_light_texture() -> GradientTexture2D:
	if _light_texture != null:
		return _light_texture
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(0.45, 0.45, 0.45, 1), Color(0, 0, 0, 1)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 256
	texture.height = 256
	_light_texture = texture
	return texture


func _add_fireflies(area: Rect2) -> void:
	var emitter := CPUParticles2D.new()
	emitter.name = "Fireflies"
	emitter.position = area.get_center()
	emitter.amount = maxi(fireflies_per_area, 1)
	emitter.lifetime = 5.0
	emitter.preprocess = 5.0
	emitter.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	emitter.emission_rect_extents = area.size / 2.0
	emitter.direction = Vector2.UP
	emitter.spread = 180.0
	emitter.gravity = Vector2.ZERO
	emitter.initial_velocity_min = 4.0
	emitter.initial_velocity_max = 12.0
	emitter.scale_amount_min = 1.5
	emitter.scale_amount_max = 2.4
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.75, 1.0])
	ramp.colors = PackedColorArray([Color(0.9, 1.0, 0.55, 0.0), Color(0.9, 1.0, 0.55, 1.0), Color(0.9, 1.0, 0.55, 1.0), Color(0.9, 1.0, 0.55, 0.0)])
	emitter.color_ramp = ramp
	emitter.z_index = 70
	# Fireflies glow, so cancel the darkening tint for them.
	emitter.modulate = lift_modulate()
	emitter.light_mask = 0
	add_child(emitter)
	firefly_emitters.append(emitter)


func _add_vignette() -> void:
	vignette_layer = CanvasLayer.new()
	vignette_layer.name = "Vignette"
	vignette_layer.layer = 3
	add_child(vignette_layer)
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	gradient.colors = PackedColorArray([Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0), Color(0.02, 0.03, 0.08, vignette_strength)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 256
	texture.height = 256
	var rect := TextureRect.new()
	rect.texture = texture
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	vignette_layer.add_child(rect)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
