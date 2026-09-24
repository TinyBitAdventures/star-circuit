class_name ResourceNode
extends Node3D
## A gatherable vein / plant / energy well.

var node_type := ""
var node_id := 0
var world: Node3D
var def: Dictionary
var _label: Label3D
var _beam: MeshInstance3D
var _reveal_time := 0.0
var _dying := false
var _model: Node3D
var _shake := 0.0


func setup(type: String, id: int, w: Node3D) -> void:
	node_type = type
	node_id = id
	world = w
	def = Db.NODES[type]
	var m := ModelUtil.instance(def.model)
	add_child(m)
	_model = m
	if def.item in ["biofiber", "sporegel"]:
		# plants take the planet's flora tint
		var tint: Color = world.flora_tint
		ModelUtil.tint(m, "Foliage", tint.lerp(Db.item_color(def.item), 0.5))
	scale = Vector3.ONE * def.scale * randf_range(0.9, 1.15)


func interact_info() -> Dictionary:
	var sk: int = Game.skill_level(def.skill)
	var verb: String = {"mining": "Mine", "botany": "Harvest", "siphoning": "Siphon"}[def.skill]
	var ok: bool = sk >= def.req
	var txt := "[E] Hold to %s %s" % [verb, def.name]
	if not ok:
		txt = "%s  -  requires %s %d" % [def.name, Db.SKILLS[def.skill].name, def.req]
	return {
		"text": txt, "color": Db.difficulty_color(def.req, sk), "time": def.time,
		"skill": def.skill, "ok": ok,
		"why": "Requires %s %d (you have %d)" % [Db.SKILLS[def.skill].name, def.req, sk],
	}


func interact(_player: Node) -> void:
	if _dying:
		return
	if Game.harvest(node_type):
		_dying = true
		Sound.play_3d({"mining": "rock_break", "botany": "plant_snap", "siphoning": "siphon_done"}[def.skill], global_position, 0.0)
		world.on_harvested(self)
		var t := create_tween()
		t.tween_property(self, "scale", scale * 1.25, 0.1)
		t.tween_property(self, "scale", Vector3.ONE * 0.01, 0.25)
		t.tween_callback(queue_free)


func reveal(duration: float) -> void:
	_reveal_time = duration
	if _label == null:
		_label = Label3D.new()
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.no_depth_test = true
		_label.fixed_size = true
		_label.pixel_size = 0.0012
		_label.font_size = 19
		_label.outline_size = 7
		_label.position = Vector3(0, 2.8, 0)
		_label.font = load("res://assets/fonts/Exo2.ttf")
		add_child(_label)
		_beam = MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.06
		cyl.bottom_radius = 0.06
		cyl.height = 40.0
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_color = Db.item_color(def.item) * Color(1, 1, 1, 0.5)
		cyl.material = mat
		_beam.mesh = cyl
		_beam.position = Vector3(0, 20, 0)
		_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_beam)
	var sk: int = Game.skill_level(def.skill)
	_label.text = "%s  L%d" % [def.name, def.req]
	_label.modulate = CombatFx.hdr(Db.difficulty_color(def.req, sk))
	_label.visible = true
	_beam.visible = true


func _process(delta: float) -> void:
	if _reveal_time > 0.0:
		_reveal_time -= delta
		if _reveal_time <= 0.0 and _label:
			_label.visible = false
			_beam.visible = false



## Where the robot's beam should land: the middle of the node, not its base.
func work_point() -> Vector3:
	return global_position + global_basis.y.normalized() * 0.9 * scale.y


## Feedback while being worked: rock shudders harder as it's about to
## crack, plants sway, energy wells pulse.
func work(progress: float, skill: String, delta: float) -> void:
	if _model == null or _dying:
		return
	if skill == "":
		_shake = move_toward(_shake, 0.0, delta * 4.0)
		_model.position = _model.position.lerp(Vector3.ZERO, clampf(delta * 10.0, 0.0, 1.0))
		_model.rotation = _model.rotation.lerp(Vector3.ZERO, clampf(delta * 10.0, 0.0, 1.0))
		_model.scale = _model.scale.lerp(Vector3.ONE, clampf(delta * 10.0, 0.0, 1.0))
		return
	_shake += delta
	match skill:
		"mining":
			var a := 0.025 + progress * 0.07
			_model.position = Vector3(randf_range(-a, a), randf_range(0.0, a), randf_range(-a, a))
			_model.scale = Vector3.ONE * (1.0 + progress * 0.08)
		"botany":
			_model.rotation = Vector3(sin(_shake * 9.0) * 0.12 * (0.4 + progress), 0, cos(_shake * 7.0) * 0.12 * (0.4 + progress))
		_:
			var s := 1.0 - progress * 0.25 + sin(_shake * 14.0) * 0.05
			_model.scale = Vector3(s, 1.0 + progress * 0.1, s)
