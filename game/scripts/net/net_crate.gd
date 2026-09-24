class_name NetCrate
extends Node3D
## A crate another player (or you) dropped on a planet. Walk up and press E:
## the server hands it to whoever asks first.

var drop_id := 0
var items := {}
var by := ""
var _t := 0.0
var _box: Node3D


func setup(d: Dictionary) -> void:
	drop_id = int(d.id)
	items = d.items
	by = String(d.by)
	var up: Vector3 = (d.pos as Vector3).normalized()
	global_transform = Transform3D(PlanetGen.align_basis(up, float(drop_id) * 0.7), d.pos)
	_box = Node3D.new()
	add_child(_box)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 0.7, 0.9)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("2a3346")
	mat.metallic = 0.4
	mat.roughness = 0.5
	bm.material = mat
	mi.mesh = bm
	mi.position.y = 0.35
	_box.add_child(mi)
	# glowing bands so it reads as "someone left this for you"
	for y in [0.12, 0.58]:
		var band := MeshInstance3D.new()
		var b2 := BoxMesh.new()
		b2.size = Vector3(0.94, 0.07, 0.94)
		var gm := StandardMaterial3D.new()
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.albedo_color = Color("ffd23f")
		gm.emission_enabled = true
		gm.emission = Color("ffd23f")
		gm.emission_energy_multiplier = 2.0
		b2.material = gm
		band.mesh = b2
		band.position.y = y
		_box.add_child(band)
	var l := OmniLight3D.new()
	l.light_color = Color("ffd23f")
	l.light_energy = 0.8
	l.omni_range = 4.0
	l.position.y = 1.0
	add_child(l)
	var tag := Label3D.new()
	tag.text = "%s's crate" % by if by != "" else "Crate"
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.fixed_size = true
	tag.pixel_size = 0.0009
	tag.font_size = 26
	tag.outline_size = 8
	tag.modulate = Color("ffd23f")
	tag.font = UiKit.title_font()
	tag.position.y = 1.4
	add_child(tag)


func contents_text() -> String:
	var parts: Array[String] = []
	for k in items:
		parts.append("%d %s" % [int(items[k]), Db.item_name(k)])
	return ", ".join(parts)


func interact_info() -> Dictionary:
	return {"text": "[E] Pick up %s%s" % [contents_text(), ("  (left by %s)" % by) if by != "" else ""], "color": Color("ffd23f"), "instant": true}


func interact(_player: Node) -> void:
	Net.pickup(drop_id)


func _process(delta: float) -> void:
	_t += delta
	_box.position.y = 0.05 + sin(_t * 2.0) * 0.05
	_box.rotation.y += delta * 0.4
