extends Node2D

## One claw slash: a crescent that sweeps along an arc, bright at the head and fading to a thin
## tail, with a white core line. Purely visual; created by HitFeel.slash().
##
## The crescent is drawn in local space around the origin; `direction_angle` rotates it so the
## middle of the arc points where the cat is attacking.

var radius: float = 26.0
var thickness: float = 9.0
var half_arc: float = 1.2          # radians, half of the full arc
var color: Color = Color("#fff3c9")
var duration: float = 0.16
var sweep: float = 1.0             # +1 sweeps clockwise, -1 counter-clockwise
var full_circle: bool = false      # counter claw: a spinning ring

var _age: float = 0.0
const SEGMENTS := 14


func _process(delta: float) -> void:
	_age += delta
	if _age >= duration:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t := clampf(_age / duration, 0.0, 1.0)
	# The head runs along the arc (eased out); the tail follows a little behind it.
	var head := 1.0 - pow(1.0 - minf(t * 1.6, 1.0), 3.0)
	var tail := clampf((t - 0.25) / 0.75, 0.0, 1.0)
	tail = tail * tail
	if head <= tail + 0.01:
		return
	var span := TAU * 0.92 if full_circle else half_arc * 2.0
	var start_angle := (-span / 2.0) if not full_circle else 0.0
	var fade := 1.0 - t * t * t
	# a dark outline underneath keeps the slash readable on the bright lamp-lit ground
	_draw_band(start_angle, span, tail, head, thickness + 5.0, Color("#5c3a4b"), fade * 0.7)
	_draw_band(start_angle, span, tail, head, thickness, color, fade)
	# thin white core
	_draw_band(start_angle, span, maxf(tail, head - 0.35), head, maxf(thickness * 0.35, 2.0), Color(1, 1, 1), fade)


func _draw_band(start_angle: float, span: float, from_t: float, to_t: float, width: float, tint: Color, fade: float) -> void:
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var colors_outer := PackedColorArray()
	var colors_inner := PackedColorArray()
	for i in range(SEGMENTS + 1):
		var u := float(i) / float(SEGMENTS)
		var along := lerpf(from_t, to_t, u)          # 0..1 along the whole arc
		var angle := start_angle + span * (along if sweep >= 0.0 else 1.0 - along)
		# crescent: thickest at the head, thin at the tail
		var w := width * pow(u, 0.8)
		var direction := Vector2.from_angle(angle)
		outer.append(direction * (radius + w * 0.35))
		inner.append(direction * (radius - w * 0.65))
		var a := u * fade
		colors_outer.append(Color(tint.r, tint.g, tint.b, a))
		colors_inner.append(Color(tint.r, tint.g, tint.b, a))
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	for i in range(outer.size()):
		points.append(outer[i])
		colors.append(colors_outer[i])
	for i in range(inner.size() - 1, -1, -1):
		points.append(inner[i])
		colors.append(colors_inner[i])
	if points.size() >= 3:
		draw_polygon(points, colors)
