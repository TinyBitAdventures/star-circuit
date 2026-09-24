class_name NetView
extends Node3D
## Shows the other players who share this planet (walking robots) or this
## star system (flying robots), plus crates dropped on this planet.

var world: Node3D
var mode := "planet" # planet | space
var avatars := {} # player id -> RemotePlayer
var crates := {} # drop id -> NetCrate


func setup(w: Node3D, m: String) -> void:
	world = w
	mode = m
	Net.drops_changed.connect(_sync_drops)
	Net.look_changed.connect(func(id: int):
		if avatars.has(id) and Net.players.has(id):
			avatars[id].apply_look(Net.players[id].look))
	_sync_drops()


func _here(st: Dictionary) -> bool:
	if st.is_empty() or int(st.get("star", -1)) != Game.star_index:
		return false
	if mode == "planet":
		return st.scene == "planet" and int(st.planet) == Game.planet_index
	return st.scene == "space"


## Space positions arrive relative to the nearest planet (orbits depend on each
## player's own clock); rebuild them against this world's planet positions.
func _world_pos(st: Dictionary) -> Vector3:
	if mode == "planet":
		return st.pos
	var anchor := int(st.get("anchor", -1))
	var base := Vector3.ZERO
	if anchor >= 0 and anchor < Galaxy.star(Game.star_index).planets.size():
		base = Galaxy.orbit_pos(Galaxy.planet(Game.star_index, anchor), Game.play_time)
	return base + (st.pos as Vector3)


func _process(_delta: float) -> void:
	for id in Net.players:
		var p: Dictionary = Net.players[id]
		var st: Dictionary = p.state
		if _here(st):
			if not avatars.has(id):
				var a := RemotePlayer.new()
				add_child(a)
				a.setup(id, p, mode)
				avatars[id] = a
			(avatars[id] as RemotePlayer).push(_world_pos(st), st.fwd, String(st.anim))
		elif avatars.has(id):
			avatars[id].queue_free()
			avatars.erase(id)
	for id in avatars.keys():
		if not Net.players.has(id):
			avatars[id].queue_free()
			avatars.erase(id)


func _sync_drops() -> void:
	if mode != "planet":
		return
	for id in crates.keys():
		if not Net.drops.has(id):
			crates[id].queue_free()
			crates.erase(id)
	for id in Net.drops:
		var d: Dictionary = Net.drops[id]
		if crates.has(id) or int(d.star) != Game.star_index or int(d.planet) != Game.planet_index:
			continue
		var c := NetCrate.new()
		add_child(c)
		c.setup(d)
		crates[id] = c
		world.register_interactable(c)


## The robot nearest a point (for "give to the player next to me").
func nearest_player(pos: Vector3, max_dist: float) -> int:
	var best := 0
	var bd := max_dist
	for id in avatars:
		var d: float = avatars[id].global_position.distance_to(pos)
		if d < bd:
			bd = d
			best = id
	return best
