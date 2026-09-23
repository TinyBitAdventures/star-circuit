class_name SpaceBolt
extends Node3D
## A glowing energy bolt. Enemy bolts are dodgeable projectiles that hit the
## player; missiles (homing = true) are the player's guided weapon.

var world: Node3D
var velocity := Vector3.ZERO
var damage := 10.0
var hostile := true
var homing: SpaceEnemy = null
var _life := 3.5
var _speed := 0.0
var _trail: CPUParticles3D
var _hit_r := 2.8


func setup(w: Node3D, from: Vector3, dir: Vector3, speed: float, dmg: float, color: Color, is_missile: bool, size := 0.45) -> void:
	world = w
	damage = dmg
	_speed = speed
	hostile = not is_missile
	_hit_r = 2.2 + size * 2.4
	velocity = dir.normalized() * speed
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = size
	cap.height = size * (6.0 if not is_missile else 3.0)
	mi.mesh = cap
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color * 3.0
	mi.material_override = m
	mi.rotation.x = PI * 0.5 # capsule is Y-up; lay it along -Z
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var light := OmniLight3D.new()
	light.light_color = color
	light.omni_range = 8.0
	light.light_energy = 1.5
	add_child(light)
	if is_missile:
		_life = 7.0
		_trail = CPUParticles3D.new()
		_trail.amount = 60
		_trail.lifetime = 0.8
		_trail.local_coords = false
		_trail.gravity = Vector3.ZERO
		_trail.initial_velocity_min = 0.0
		_trail.initial_velocity_max = 1.0
		_trail.scale_amount_min = 1.0
		_trail.scale_amount_max = 2.2
		var q := QuadMesh.new()
		q.size = Vector2(0.9, 0.9)
		var tm := StandardMaterial3D.new()
		tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		tm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		tm.vertex_color_use_as_albedo = true
		tm.albedo_texture = ModelUtil.soft_dot()
		q.material = tm
		_trail.mesh = q
		var g := Gradient.new()
		g.set_color(0, Color(1, 0.8, 0.5, 0.8))
		g.set_color(1, Color(0.5, 0.5, 0.6, 0.0))
		_trail.color_ramp = g
		add_child(_trail)
	w.add_child(self)
	global_position = from
	look_at(from + velocity, Vector3.UP if absf(dir.normalized().y) < 0.98 else Vector3.RIGHT)


func _physics_process(delta: float) -> void:
	_life -= delta
	if homing and is_instance_valid(homing) and homing.is_alive():
		var want := (homing.global_position - global_position).normalized() * _speed
		velocity = velocity.lerp(want, clampf(delta * 3.5, 0.0, 1.0))
		_speed = minf(_speed + delta * 60.0, 260.0)
	global_position += velocity * delta
	if velocity.length() > 1.0:
		look_at(global_position + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.98 else Vector3.RIGHT)
	if hostile:
		var player: Node3D = world.player
		if player and not player.dead and global_position.distance_to(player.global_position) < _hit_r:
			world.damage_player(damage, null)
			CombatFx.spark(world, global_position, Color(1, 0.5, 0.3), 1.0)
			queue_free()
			return
	else:
		for e in world.space_enemies:
			if e.is_alive() and global_position.distance_to(e.global_position) < e.def.size + 2.5:
				e.take_hit(damage, true)
				CombatFx.explosion(world, global_position, Color(1.0, 0.7, 0.3), 1.6)
				if world.player and global_position.distance_to(world.player.global_position) < 90.0:
					world.player.shake.add(0.15)
				Sound.play_3d("slam", global_position, -6.0, 0.1, 40.0)
				queue_free()
				return
	if _life <= 0.0:
		if not hostile:
			CombatFx.explosion(world, global_position, Color(1.0, 0.7, 0.3), 1.0)
		queue_free()
