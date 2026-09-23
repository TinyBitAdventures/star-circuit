class_name RelicPedestal
extends Node3D
## A relic on a pedestal (vaults) or a fossil slab (fossil beds). One-time pickup.

var world: Node3D
var item := "ancient_relic"
var key := ""
var _relic: Node3D
var _t := 0.0


func setup(w: Node3D, it: String, chamber_key: String) -> void:
	world = w
	item = it
	key = chamber_key + ":relic"
	var m := ModelUtil.instance("res://assets/models/cave_fossil.glb" if item == "fossil" else "res://assets/models/cave_pedestal.glb")
	if item == "resonance_crystal":
		ModelUtil.tint(m, "Glyph", Color("5ff7ff"))
	if item == "fossil":
		m.scale = Vector3.ONE * 1.4
	add_child(m)
	_relic = m.find_child("Relic", true, false)
	if taken() and _relic:
		_relic.visible = false
	var l := OmniLight3D.new()
	l.light_color = Db.item_color(item)
	l.omni_range = 6.0
	l.light_energy = 2.0 if not taken() else 0.3
	l.position.y = 2.0
	add_child(l)


func taken() -> bool:
	return Game.looted_pois.has(key) or (item == "resonance_crystal" and Game.boarded.has(key.trim_suffix(":relic")))


func _process(delta: float) -> void:
	_t += delta
	if _relic and _relic.visible:
		_relic.rotation.z = _t * 1.2
		_relic.position.z = 1.95 + sin(_t * 2.0) * 0.08


func interact_info() -> Dictionary:
	if taken():
		return {"text": "An empty %s" % ("pedestal" if item == "ancient_relic" else "slab"), "color": UiKit.MUTED, "instant": true}
	return {"text": "[E] Hold to recover the %s" % Db.item_name(item), "color": Db.item_color(item), "time": 2.2, "skill": "exploration", "ok": true}


func interact(_p: Node) -> void:
	if taken():
		return
	Game.looted_pois.append(key)
	if item == "resonance_crystal":
		Game.boarded.append(key.trim_suffix(":relic"))
		Game.add_item("resonance_crystal", 1, false, true)
		Game.add_credits(randi_range(60, 140))
		Sound.play("quest_complete", -4.0, 0.0, "UI")
		if _relic:
			_relic.visible = false
		world.hud.big("RESONANCE CRYSTAL", "Still humming on the Circuit's frequency. A dark relay can use this.", Color("5ff7ff"))
		return
	if item == "ancient_relic":
		Game.add_item("resonance_crystal", 1, false, true)
		Game.notify.emit("A Resonance Crystal was sealed in with the relic.", Color("5ff7ff"))
	Game.collect_relic(item)
	Sound.play("quest_complete", -4.0, 0.0, "UI")
	if _relic:
		_relic.visible = false
	var li := Game.learn_lore(hash(key))
	if li >= 0 and item == "ancient_relic":
		world.hud.show_lore(li)
	else:
		world.hud.big("%s RECOVERED" % Db.item_name(item).to_upper(), "Sell it to collectors, or keep it as a trophy", Db.item_color(item))
