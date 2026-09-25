class_name EnemyBehavior
extends RefCounted
## How one kind of enemy fights. Enemy runs the shared state machine (idle,
## chase, return, dead), statuses, leashing and death; a behaviour decides how
## it closes in, attacks, reacts to hits and animates. Db.ENEMIES[type].style
## picks the script (see Enemy.BEHAVIORS).

var e: Enemy


func setup(enemy: Enemy) -> void:
	e = enemy


## Runs before the state machine each frame. Return true while busy (a
## telegraph, a burrow): the enemy then skips its normal movement this frame.
func busy(_delta: float) -> bool:
	return false


## Closing in while engaged. The default walks up to 85% of its range.
func chase(delta: float, ppos: Vector3, dist: float) -> void:
	var want: float = e.def.range * 0.85
	if dist > want:
		e.move_toward_point(ppos, e.def.speed * (1.25 if dist > 15.0 else 1.0), delta)
	else:
		e.face(ppos, delta)


func attack(_player: Node3D, _dist: float) -> void:
	pass


## A hit is about to land: return the damage to take (0 = blocked).
## from: where the shot came from (Vector3.INF when unknown).
func on_hit(amount: float, _kind: String, _from: Vector3) -> float:
	return amount


## Called on leash, death and removal: free anything the behaviour spawned.
func cleanup() -> void:
	pass


## Extra hover above the ground.
func hover(_t: float) -> float:
	return 0.0


## Pose the model. Return true to skip the Enemy's default posing.
func animate(_delta: float, _engaged: bool) -> bool:
	return false


## Whether the plate and bar should show (a cloaked stalker hides them).
func visible_to_player() -> bool:
	return true
