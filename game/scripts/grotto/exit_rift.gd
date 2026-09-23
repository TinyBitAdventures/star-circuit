class_name ExitRift
extends Node3D
## Glowing rift that returns you to the dig tunnels.

var world: Node3D
var _ring: MeshInstance3D
var _t := 0.0


func setup(w: Node3D, col: Color) -> void:
	world = w
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.3
	tm.outer_radius = 1.5
	_ring.mesh = tm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col * 1.5
	_ring.material_override = m
	_ring.rotation.x = PI * 0.5
	_ring.position.y = 1.7
	add_child(_ring)
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.3
	cm.bottom_radius = 1.3
	cm.height = 0.02
	disc.mesh = cm
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.albedo_color = Color(col.r, col.g, col.b, 0.18)
	disc.material_override = dm
	disc.rotation.x = PI * 0.5
	disc.position.y = 1.7
	add_child(disc)
	var l := OmniLight3D.new()
	l.light_color = col
	l.omni_range = 7.0
	l.light_energy = 1.5
	l.position.y = 1.7
	add_child(l)


func _process(delta: float) -> void:
	_t += delta
	_ring.rotation.y = _t * 0.8


func interact_info() -> Dictionary:
	return {"text": "[E] Return to the tunnels", "color": Color("9bd1ff"), "instant": true}


func interact(_p: Node) -> void:
	Sound.play("warp", -10.0, 0.1)
	Game.leave_chamber()
