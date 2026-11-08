extends RefCounted
## Visual-only squash and stretch curves for the four-direction slime sprites.
## Every sample returns local sprite scale and elevation; collision stays unchanged.
const KEYS: Array[Vector4] = [
	# time, width, height, sprite Y (negative means up from the ground)
	Vector4(0.00, 1.00, 1.00, 0.0),
	Vector4(0.14, 1.16, 0.83, 2.0), # anticipate / squish
	Vector4(0.30, 0.91, 1.13, -4.0), # launch
	Vector4(0.53, 0.98, 1.04, -7.0), # top of arc
	Vector4(0.72, 0.94, 1.08, -3.0), # falling
	Vector4(0.83, 1.19, 0.80, 2.0), # landing splat
	Vector4(0.93, 0.96, 1.06, -1.0), # elastic rebound
	Vector4(1.00, 1.00, 1.00, 0.0),
]


static func sample(phase: float, amplitude: float = 1.0) -> Dictionary:
	var t := clampf(phase, 0.0, 1.0)
	var strength := clampf(amplitude, 0.0, 2.0)
	for i in range(KEYS.size() - 1):
		var left: Vector4 = KEYS[i]
		var right: Vector4 = KEYS[i + 1]
		if t > right.x:
			continue
		var alpha := clampf((t - left.x) / (right.x - left.x), 0.0, 1.0)
		alpha = alpha * alpha * (3.0 - 2.0 * alpha)
		var x := lerpf(left.y, right.y, alpha)
		var y := lerpf(left.z, right.z, alpha)
		var height := lerpf(left.w, right.w, alpha)
		return {
			"scale": Vector2(1.0 + (x - 1.0) * strength, 1.0 + (y - 1.0) * strength),
			"offset": height * strength,
			"airborne": clampf(-height / 7.0, 0.0, 1.0),
		}
	return {"scale": Vector2.ONE, "offset": 0.0, "airborne": 0.0}
