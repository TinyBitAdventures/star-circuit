class_name HazardPatch
extends Node3D
## A patch of burning ground left by mites and mortar shells. Standing in it
## burns you; it fades after a few seconds. Enemies don't mind it.

var world: Node3D
var radius := 2.0
var life := 4.0
var dps := 6.0
var _tick := 0.0
var _ring: MeshInstance3D
var _embers: CPUParticles3D


static func spawn(w: Node3D, dir: Vector3, r: float, seconds: float, burn_dps: float) -> HazardPatch:
	var p := HazardPatch.new()
	p.world = w
	p.radius = r
	p.life = seconds
	p.dps = burn_dps
	w.add_child(p)
	p._build(dir.normalized())
	return p


func _build(dir: Vector3) -> void:
	var center: Vector3 = world.gen.surface_point(dir)
	_ring = CombatFx.ground_ring(self, center, dir, radius, Color(1.0, 0.42, 0.1, 0.45), 0.12)
	_embers = CPUParticles3D.new()
	_embers.amount = int(10 + radius * 6)
	_embers.lifetime = 0.8
	_embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_embers.emission_sphere_radius = radius * 0.8
	_embers.direction = Vector3.UP
	_embers.spread = 20.0
	_embers.gravity = Vector3.ZERO
	_embers.initial_velocity_min = 1.0
	_embers.initial_velocity_max = 3.0
	_embers.scale_amount_min = 0.15
	_embers.scale_amount_max = 0.35
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.5)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = ModelUtil.soft_dot()
	m.albedo_color = Color(1.0, 0.55, 0.15, 0.9)
	q.material = m
	_embers.mesh = q
	add_child(_embers)
	_embers.global_transform = Transform3D(PlanetGen.align_basis(dir), center + dir * 0.3)
	global_position = center


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	if life < 1.0 and is_instance_valid(_ring):
		(_ring.material_override as StandardMaterial3D).albedo_color.a = 0.45 * life
		_embers.emitting = false
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.5
	var p: Node3D = world.player
	if p and not p.dead and p.global_position.distance_to(global_position) < radius + 0.4:
		world.damage_player(dps * 0.25, null, "burn", 2.0, dps)
