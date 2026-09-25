class_name CombatFx
extends RefCounted
## Short-lived combat visuals: tracers, explosions, shockwaves, damage numbers.

## Boost a colour so unshaded 3D text survives the filmic tonemapper.
static func hdr(c: Color, k := 2.2) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, c.a)

static func _unshaded(color: Color, alpha := 1.0, additive := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func tracer(parent: Node3D, from: Vector3, to: Vector3, color: Color) -> void:
	var len := from.distance_to(to)
	if len < 0.1:
		return
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.07
	cyl.bottom_radius = 0.07
	cyl.height = len
	cyl.radial_segments = 6
	cyl.rings = 1
	mi.mesh = cyl
	var m := _unshaded(color * 2.5, 0.9)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	var mid := (from + to) * 0.5
	var y := (to - from).normalized()
	var ref := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var z := x.cross(y).normalized()
	mi.global_transform = Transform3D(Basis(x, y, z), mid)
	var t := mi.create_tween()
	t.tween_property(m, "albedo_color:a", 0.0, 0.12)
	t.tween_callback(mi.queue_free)
	# muzzle / impact sparks
	spark(parent, to, color, 0.5)


static func spark(parent: Node3D, pos: Vector3, color: Color, size: float) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = size
	sm.height = size * 2.0
	sm.radial_segments = 10
	sm.rings = 6
	mi.mesh = sm
	var m := _unshaded(color * 3.0, 0.9)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos
	var t := mi.create_tween().set_parallel()
	t.tween_property(mi, "scale", Vector3.ONE * 0.1, 0.18)
	t.tween_property(m, "albedo_color:a", 0.0, 0.18)
	t.chain().tween_callback(mi.queue_free)


static func explosion(parent: Node3D, pos: Vector3, color: Color, size: float) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	mi.mesh = sm
	var m := _unshaded(color * 2.5, 0.85)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * size * 0.3
	var t := mi.create_tween().set_parallel()
	t.tween_property(mi, "scale", Vector3.ONE * size * 1.6, 0.4).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(m, "albedo_color:a", 0.0, 0.4)
	t.chain().tween_callback(mi.queue_free)
	# debris
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = int(18 * size)
	p.lifetime = 0.9
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 5.0 * size
	p.initial_velocity_max = 11.0 * size
	p.gravity = Vector3.ZERO
	p.damping_min = 6.0
	p.damping_max = 9.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 0.25
	bm.material = _unshaded(color.lerp(Color(0.3, 0.3, 0.35), 0.4) * 1.6, 1.0, false)
	p.mesh = bm
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)


static func shockwave(parent: Node3D, center: Vector3, up: Vector3, radius: float, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.85
	tm.outer_radius = 1.0
	tm.rings = 32
	tm.ring_segments = 6
	mi.mesh = tm
	var m := _unshaded(color * 2.5, 0.9)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_transform = Transform3D(PlanetGen.align_basis(up), center + up * 0.4)
	mi.scale = Vector3(0.5, 1.0, 0.5)
	var t := mi.create_tween().set_parallel()
	t.tween_property(mi, "scale", Vector3(radius, 2.0, radius), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(m, "albedo_color:a", 0.0, 0.4)
	t.chain().tween_callback(mi.queue_free)


static func floating_text(parent: Node3D, pos: Vector3, up: Vector3, text: String, color: Color, big := false) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = UiKit.body_font()
	l.font_size = 72 if big else 52
	l.outline_size = 14
	l.modulate = hdr(color)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0009
	parent.add_child(l)
	var jitter := Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))
	l.global_position = pos + jitter
	var t := l.create_tween().set_parallel()
	t.tween_property(l, "global_position", pos + jitter + up * 2.0, 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.35)
	t.chain().tween_callback(l.queue_free)


## A flat warning disc on the ground that grows to full size over grow_time.
## The caller frees it when the attack lands.
static func ground_ring(parent: Node3D, center: Vector3, up: Vector3, radius: float, color: Color, grow_time: float) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.08
	cyl.radial_segments = 40
	ring.mesh = cyl
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	ring.material_override = m
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ring)
	ring.global_transform = Transform3D(PlanetGen.align_basis(up), center + up * 0.15)
	ring.scale = Vector3(0.2, 1, 0.2)
	ring.create_tween().tween_property(ring, "scale", Vector3.ONE, maxf(grow_time, 0.05))
	return ring


## A warning strip that hugs the planet: from start_dir along a great circle
## toward heading. world must have a PlanetGen in `gen`. It fades in over grow_time.
static func ground_lane(world: Node3D, start_dir: Vector3, heading: Vector3, length: float, width: float, color: Color, grow_time: float) -> MeshInstance3D:
	var gen: PlanetGen = world.gen
	var up0 := start_dir.normalized()
	var fwd := (heading - up0 * heading.dot(up0)).normalized()
	var axis := up0.cross(fwd).normalized()
	var steps := 16
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	for i in steps + 1:
		var ang := (length * float(i) / steps) / gen.radius
		var d := up0.rotated(axis, ang)
		var side := axis # the strip's width runs along the rotation axis
		var c := gen.surface_point(d) + d * 0.18
		var l := c - side * width * 0.5
		var r := c + side * width * 0.5
		if i > 0:
			st.add_vertex(prev_l)
			st.add_vertex(prev_r)
			st.add_vertex(l)
			st.add_vertex(prev_r)
			st.add_vertex(r)
			st.add_vertex(l)
		prev_l = l
		prev_r = r
	var lane := MeshInstance3D.new()
	lane.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(color.r, color.g, color.b, 0.0)
	lane.material_override = m
	lane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(lane)
	lane.global_transform = Transform3D.IDENTITY
	lane.create_tween().tween_property(m, "albedo_color:a", color.a, maxf(grow_time * 0.6, 0.05))
	return lane


## A jagged electric bolt from a to b (Arc chains).
static func arc_bolt(parent: Node3D, a: Vector3, b: Vector3, color: Color) -> void:
	var dir := b - a
	var side := dir.cross(Vector3.UP if absf(dir.normalized().y) < 0.9 else Vector3.RIGHT).normalized()
	var up := side.cross(dir).normalized()
	var prev := a
	var segs := 6
	for i in range(1, segs + 1):
		var k := float(i) / segs
		var next := a.lerp(b, k)
		if i < segs:
			next += (side * randf_range(-1, 1) + up * randf_range(-1, 1)) * dir.length() * 0.06
		tracer(parent, prev, next, color)
		prev = next
