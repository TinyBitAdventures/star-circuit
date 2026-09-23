class_name EnemyBolt
extends Node3D
## Slow, dodgeable plasma orb fired by Sentinels.

const SPEED := 24.0
const LIFE := 3.0

var world: Node3D
var velocity := Vector3.ZERO
var damage := 10.0
var _life := LIFE


func setup(w: Node3D, from: Vector3, to: Vector3, dmg: float, color: Color) -> void:
	world = w
	damage = dmg
	velocity = (to - from).normalized() * SPEED
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.32
	sm.height = 0.64
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color * 3.0
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var light := OmniLight3D.new()
	light.light_color = color
	light.omni_range = 4.0
	light.light_energy = 1.5
	add_child(light)
	w.add_child(self)
	global_position = from


func _physics_process(delta: float) -> void:
	_life -= delta
	global_position += velocity * delta
	var player: Node3D = world.player
	if player and not player.dead:
		var body: Vector3 = player.global_position + player.global_basis.y * 1.0
		if global_position.distance_to(body) < 1.25:
			world.damage_player(damage, null)
			world.explosion(global_position, Color("ff3d9a"), 0.6)
			queue_free()
			return
	var d := global_position.length()
	if _life <= 0.0 or d < world.gen.surface_radius(global_position / d):
		world.explosion(global_position, Color("ff3d9a"), 0.5)
		queue_free()
