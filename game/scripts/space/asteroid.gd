class_name Asteroid
extends StaticBody3D
## A minable asteroid. The mining laser wears down its integrity; big rocks
## crack into smaller fragments, every break spills ore shards.

const LAYER := 8

var world: Node3D
var type := "rocky"
var def: Dictionary
var size := 4.0
var max_hp := 1.0
var hp := 1.0
var spin := Vector3.ZERO
var generation := 0 # 0 = original rock, 1 = fragment
var _visual: Node3D
var _label: Label3D
var _reveal := 0.0
var _flash := 0.0
var drift := Vector3.ZERO


func setup(w: Node3D, t: String, s: float, pos: Vector3, gen := 0) -> void:
	world = w
	type = t
	def = Db.ASTEROIDS[t]
	size = s
	generation = gen
	max_hp = size * 12.0 * float(def.hp)
	hp = max_hp
	collision_layer = LAYER
	collision_mask = 0
	var path := "res://assets/models/comet_nucleus.glb" if t == "comet" else "res://assets/models/asteroid_%d.glb" % (1 + randi() % 3)
	_visual = ModelUtil.instance(path)
	add_child(_visual)
	if t != "comet":
		ModelUtil.tint(_visual, "Rock", def.rock)
		ModelUtil.tint(_visual, "Vein", def.vein)
	_visual.scale = Vector3.ONE * size
	_visual.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = size * 0.95
	cs.shape = sp
	add_child(cs)
	spin = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(0.05, 0.25) / maxf(1.0, size * 0.25)
	position = pos


func _process(delta: float) -> void:
	if spin.length() > 0.0:
		_visual.rotate(spin.normalized(), spin.length() * delta)
	if drift.length() > 0.01:
		position += drift * delta
		drift = drift.lerp(Vector3.ZERO, delta * 0.4)
	if _flash > 0.0:
		_flash -= delta
		_visual.scale = Vector3.ONE * size * (1.0 + _flash * 0.12)
	if _reveal > 0.0:
		_reveal -= delta
		if _reveal <= 0.0 and _label:
			_label.visible = false
		elif _label and world.player:
			# full contents only when you're close; just the type from afar
			var d: float = global_position.distance_to(world.player.global_position)
			var i := info()
			_label.text = ("%s\n%s" % [i.name, i.items] if i.ok else "%s\nMining %d" % [i.name, i.req]) if d < 70.0 else i.name
			_label.modulate.a = clampf(1.4 - d / 300.0, 0.35, 1.0)


func info() -> Dictionary:
	var sk := Game.skill_level("mining")
	var items := ""
	for it in def.items:
		items += Db.item_name(it) + "  "
	return {"name": def.name, "ok": sk >= def.req, "req": def.req, "color": Db.difficulty_color(def.req, sk), "items": items.strip_edges()}


## Apply laser damage. Returns true when it breaks.
func mine(amount: float) -> bool:
	if hp <= 0.0:
		return false
	hp -= amount
	_flash = 0.15
	if hp <= 0.0:
		_break()
		return true
	return false


func _break() -> void:
	var sk := Game.skill_level("mining")
	Game.gain_skill_xp("mining", float(def.xp) * clampf(size / 5.0, 0.6, 3.0) * Db.difficulty_xp_mult(def.req, sk))
	Game._bounty_event("asteroid", 1)
	var yield_mult := clampf(size / 5.0, 0.6, 3.5)
	for it in def.items:
		var q := int(round(randi_range(def.items[it][0], def.items[it][1]) * yield_mult))
		q += Game.robot().yield_bonus.get("mining", 0) if it == def.items.keys()[0] else 0
		if q > 0:
			world.spawn_shards(global_position, it, q, size)
	if randf() < 0.08:
		world.spawn_shards(global_position, "stardust", 1, size)
	CombatFx.explosion(world, global_position, def.vein, clampf(size * 0.35, 0.8, 3.5))
	Sound.play_3d("rock_break", global_position, 2.0, 0.15, 30.0)
	# big rocks crack into smaller minable fragments
	if generation == 0 and size > 4.5:
		var n := 2 + (1 if size > 7.0 else 0)
		for i in n:
			var dir := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
			var frag: Asteroid = world.spawn_asteroid(type if type != "comet" else "icy", size * randf_range(0.38, 0.5), global_position + dir * size * 0.6, 1)
			frag.drift = dir * randf_range(2.0, 5.0)
	world.on_asteroid_broken(self)
	queue_free()


func reveal(duration: float) -> void:
	_reveal = duration
	if _label == null:
		_label = Label3D.new()
		_label.font = UiKit.body_font()
		_label.font_size = 24
		_label.outline_size = 8
		_label.fixed_size = true
		_label.pixel_size = 0.0011
		_label.no_depth_test = true
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(_label)
		_label.position = Vector3(0, size * 1.3, 0)
	var i := info()
	_label.text = "%s\n%s" % [i.name, i.items] if i.ok else "%s\nMining %d" % [i.name, i.req]
	_label.modulate = CombatFx.hdr(i.color, 1.5)
	_label.visible = true
