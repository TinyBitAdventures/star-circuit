class_name PlayerGrenade
extends Node3D
## A Cinder round: arcs under planet gravity, bursts on the ground or on
## contact with an enemy, burning everything in the blast.

const GRAVITY := 22.0
const LIFE := 3.0

var world: Node3D
var velocity := Vector3.ZERO
var damage := 10.0
var radius := 3.5
var burn_time := 3.0
var _life := LIFE
var _mesh: MeshInstance3D


static func launch(w: Node3D, from: Vector3, vel: Vector3, dmg: float, r: float, burn: float) -> PlayerGrenade:
	var g := PlayerGrenade.new()
	g.world = w
	g.velocity = vel
	g.damage = dmg
	g.radius = r
	g.burn_time = burn
	w.add_child(g)
	g.global_position = from
	g._build()
	return g


func _build() -> void:
	_mesh = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.25
	sm.height = 0.5
	_mesh.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.55, 0.15) * 3.0
	_mesh.material_override = m
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)


func _physics_process(delta: float) -> void:
	_life -= delta
	var up := global_position.normalized()
	velocity -= up * GRAVITY * delta
	global_position += velocity * delta
	var gen: PlanetGen = world.gen
	var ground := gen.surface_radius(up)
	if gen.has_liquid():
		ground = maxf(ground, gen.sea_radius())
	var hit_enemy := false
	for e in world.enemies_near(global_position, 1.6):
		hit_enemy = true
		break
	if _life <= 0.0 or hit_enemy or global_position.length() <= ground + 0.2:
		_burst()


func _burst() -> void:
	var at := global_position
	world.explosion(at, Color(1.0, 0.5, 0.15), radius * 0.45)
	world.shockwave(at, radius, Color(1.0, 0.55, 0.2))
	Sound.play_3d("fire_burst", at, -2.0, 0.08, 24.0)
	for e in world.enemies_near(at, radius):
		var falloff := clampf(1.0 - e.global_position.distance_to(at) / (radius * 1.4), 0.4, 1.0)
		e.take_hit(damage * falloff, false, "fire", at)
		if e.is_alive():
			e.apply_status("burn", burn_time, damage * 0.25)
			e.knockback((e.global_position - at).normalized() * 6.0)
	queue_free()
