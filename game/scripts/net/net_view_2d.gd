class_name NetView2D
extends Node2D
## Shows everyone sharing our room in a 2D mini game (same cave, same sea).

var world: Node2D
var style := "dig"
var divers := {} # player id -> RemoteDiver


func setup(w: Node2D, s: String) -> void:
	world = w
	style = s
	z_index = 5


func _process(_delta: float) -> void:
	var here := {}
	if Net.is_online() and Net.room != "":
		for id in Net.room_peers():
			var st: Dictionary = Net.players[id].state
			here[id] = true
			if not divers.has(id):
				var d := RemoteDiver.new()
				add_child(d)
				d.setup(id, Net.players[id], style, world.light_tex() if world.has_method("light_tex") else world._light_tex())
				divers[id] = d
			var p: Vector3 = st.pos
			var f: Vector3 = st.fwd
			(divers[id] as RemoteDiver).push(Vector2(p.x, p.y), f.x, String(st.anim))
	for id in divers.keys():
		if not here.has(id):
			divers[id].queue_free()
			divers.erase(id)
