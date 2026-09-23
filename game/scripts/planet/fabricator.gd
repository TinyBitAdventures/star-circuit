class_name Fabricator
extends Node3D
## Outpost fabrication terminal: opens the crafting panel.

var world: Node3D


func setup(w: Node3D) -> void:
	world = w
	add_child(ModelUtil.instance("res://assets/models/prop_terminal.glb"))
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 1.7, 0.8)
	cs.shape = box
	cs.position.y = 0.85
	body.add_child(cs)
	add_child(body)


func interact_info() -> Dictionary:
	return {"text": "[E] Use Fabricator  (or press C anywhere)", "color": Color("39e5ff"), "instant": true}


func interact(_player: Node) -> void:
	world.hud.toggle_panel("crafting")
