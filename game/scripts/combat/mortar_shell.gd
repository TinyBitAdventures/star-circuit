class_name MortarShell
extends Node3D
## A lobbed shell: flies a high arc to a telegraphed spot, then bursts,
## burning whoever stands there and leaving a HazardPatch.

var world: Node3D
var damage := 10.0
var radius := 3.2
var _from := Vector3.ZERO
var _to_dir := Vector3.UP
var _to := Vector3.ZERO
var _t := 0.0
var _flight := 1.3
var _ring: MeshInstance3D
var _mesh: MeshInstance3D


static func fire(w: Node3D, from: Vector3, target_dir: Vector3, dmg: float, r: float, flight: float) -> MortarShell:
	var s := MortarShell.new()
	s.world = w
	s.damage = dmg
	s.radius = r
	s._flight = flight
	s._from = from
	s._to_dir = target_dir.normalized()
	s._to = w.gen.surface_point(s._to_dir)
	w.add_child(s)
	s._build()
	return s


func _build() -> void:
	_ring = CombatFx.ground_ring(world, _to, _to_dir, radius, Color(1.0, 0.45, 0.1, 0.35), _flight)
	_mesh = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.45
	sm.height = 0.9
	_mesh.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.5, 0.15) * 3.0
	_mesh.material_override = m
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	global_position = _from


func _physics_process(delta: float) -> void:
	_t += delta
	var k := clampf(_t / _flight, 0.0, 1.0)
	var up := (_from.normalized() + _to_dir).normalized()
	global_position = _from.lerp(_to, k) + up * sin(k * PI) * 12.0
	if k >= 1.0:
		_land()


func _land() -> void:
	if is_instance_valid(_ring):
		_ring.queue_free()
	world.explosion(_to, Color(1.0, 0.5, 0.15), 1.5)
	world.shockwave(_to, radius, Color(1.0, 0.5, 0.2))
	Sound.play_3d("fire_burst", _to, -2.0, 0.08, 24.0)
	var p: Node3D = world.player
	if p and not p.dead and p.global_position.distance_to(_to) < radius + 0.3:
		world.damage_player(damage, null, "burn", 3.0, damage * 0.25)
	HazardPatch.spawn(world, _to_dir, radius * 0.75, 3.5, damage * 0.3)
	queue_free()


func _exit_tree() -> void:
	if is_instance_valid(_ring):
		_ring.queue_free()
