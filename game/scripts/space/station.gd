class_name OrbitalStation
extends Node3D
## A system's orbital trade station: rotating habitat ring, docking zone,
## and defence turrets that keep pirates at bay.

const DOCK_RANGE := 48.0
const SAFE_RADIUS := 230.0
const TURRET_RANGE := 280.0

var world: Node3D
var data: Dictionary
var _ring: Node3D
var _turret_cd := 0.0


func build(w: Node3D, st: Dictionary, pos: Vector3) -> void:
	world = w
	data = st
	var m := ModelUtil.instance("res://assets/models/orbital_station.glb")
	m.scale = Vector3.ONE * 0.5
	add_child(m)
	_ring = m.find_child("Ring", true, false)
	position = pos
	rotation = Vector3(0.35, randf() * TAU, 0.1)
	var label := Label3D.new()
	label.text = "⌬ %s\nTrade · Repair · Contracts" % st.name
	label.font = UiKit.body_font()
	label.font_size = 26
	label.outline_size = 8
	label.fixed_size = true
	label.pixel_size = 0.0011
	label.no_depth_test = true
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = CombatFx.hdr(Color("ffd98a"), 1.5)
	add_child(label)
	label.position = Vector3(0, 30, 0)
	var light := OmniLight3D.new()
	light.light_color = Color("ffe2a8")
	light.omni_range = 90.0
	light.light_energy = 1.2
	add_child(light)


func _process(delta: float) -> void:
	if _ring:
		_ring.rotation.z += delta * 0.08
	_turret_cd -= delta
	if _turret_cd > 0.0:
		return
	_turret_cd = 0.7
	# defence grid: shoot the nearest pirate inside range
	var best: SpaceEnemy = null
	var best_d := TURRET_RANGE
	for e in world.space_enemies:
		if e.is_alive():
			var d := global_position.distance_to(e.global_position)
			if d < best_d:
				best_d = d
				best = e
	if best:
		var from := global_position + (best.global_position - global_position).normalized() * 18.0
		CombatFx.tracer(world, from, best.global_position, Color("5ff7ff"))
		Sound.play_3d("turret_shot", from, -4.0, 0.1, 60.0)
		best.take_hit(22.0 + best.level * 5.0)
