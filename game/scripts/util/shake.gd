class_name CamShake
extends RefCounted
## Trauma-based camera shake (trauma^2 drives offset; decays over time).

var trauma := 0.0
var _t := 0.0
var _noise := FastNoiseLite.new()


func _init() -> void:
	_noise.frequency = 2.2
	_noise.seed = randi()


func add(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


## Returns (h_offset, v_offset, roll) for this frame.
func update(delta: float, strength := 0.45) -> Vector3:
	_t += delta * 30.0
	trauma = maxf(0.0, trauma - delta * 1.4)
	var s := trauma * trauma
	return Vector3(_noise.get_noise_2d(_t, 0.0), _noise.get_noise_2d(0.0, _t), _noise.get_noise_2d(_t, _t)) * s * strength
