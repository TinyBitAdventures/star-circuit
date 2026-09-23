class_name ArchivistNpc
extends Node3D
## The quest giver standing at the home outpost.

var world: Node3D
var _mark: Label3D
var _model: Node3D
var _t := 0.0


func setup(w: Node3D) -> void:
	world = w
	_model = ModelUtil.instance("res://assets/models/npc_archivist.glb")
	add_child(_model)
	_mark = Label3D.new()
	_mark.text = "!"
	_mark.font = load("res://assets/fonts/Exo2.ttf")
	_mark.font_size = 160
	_mark.outline_size = 24
	_mark.modulate = CombatFx.hdr(Color("ffd23f"))
	_mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_mark.position = Vector3(0, 3.7, 0)
	_mark.pixel_size = 0.01
	add_child(_mark)
	var nameplate := Label3D.new()
	nameplate.text = "The Archivist\n<Keeper of the Circuit>"
	nameplate.font = load("res://assets/fonts/Exo2.ttf")
	nameplate.font_size = 48
	nameplate.outline_size = 12
	nameplate.modulate = CombatFx.hdr(Color("9bd1ff"))
	nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	nameplate.position = Vector3(0, 3.05, 0)
	nameplate.pixel_size = 0.006
	add_child(nameplate)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.8
	cyl.height = 2.4
	cs.shape = cyl
	cs.position.y = 1.2
	body.add_child(cs)
	add_child(body)


func _process(delta: float) -> void:
	_t += delta
	_mark.visible = Game.quest_index == 0 and not Game.quest_accepted
	_mark.position.y = 3.7 + sin(_t * 3.0) * 0.12


func interact_info() -> Dictionary:
	return {"text": "[E] Talk to the Archivist", "color": Color("9bd1ff"), "instant": true}


func interact(_player: Node) -> void:
	world.hud.open_dialog()
