class_name Status
extends RefCounted
## Burn, chill (which stacks into a freeze) and shock, for enemies and the player.
## The owner calls tick() every frame and applies the damage it returns.

const CHILL_MAX := 3 # the next chill after this many freezes
const CHILL_SLOW := 0.18 # per stack
const FREEZE_TIME := 1.6
const SHOCK_BONUS := 0.25 # extra damage taken while shocked

var burn_t := 0.0
var burn_dps := 0.0
var chill_t := 0.0
var chill := 0 # stacks
var frozen_t := 0.0
var shock_t := 0.0
var _burn_acc := 0.0
var _freeze_immune := 0.0 # a short grace after thawing, so a frozen target can't be chain-frozen


## kind: burn (power = damage per second), chill (power = stacks to add), shock (power unused).
## resist: 0 = full effect, 1 = immune.
func apply(kind: String, duration: float, power := 1.0, resist := 0.0) -> String:
	if resist >= 1.0:
		return ""
	duration *= 1.0 - resist
	match kind:
		"burn":
			burn_t = maxf(burn_t, duration)
			burn_dps = maxf(burn_dps, power * (1.0 - resist))
			return "burn"
		"chill":
			if frozen_t > 0.0:
				return ""
			chill_t = maxf(chill_t, duration)
			chill += maxi(1, int(power))
			if chill > CHILL_MAX and _freeze_immune <= 0.0:
				chill = 0
				chill_t = 0.0
				frozen_t = FREEZE_TIME * (1.0 - resist)
				return "freeze"
			chill = mini(chill, CHILL_MAX)
			return "chill"
		"shock":
			shock_t = maxf(shock_t, duration)
			return "shock"
	return ""


## Advances the timers; returns burn damage due this frame (dealt in half-second pulses).
func tick(delta: float) -> float:
	var dmg := 0.0
	if burn_t > 0.0:
		burn_t -= delta
		_burn_acc += delta
		if _burn_acc >= 0.5:
			_burn_acc -= 0.5
			dmg = burn_dps * 0.5
		if burn_t <= 0.0:
			burn_dps = 0.0
			_burn_acc = 0.0
	if chill_t > 0.0:
		chill_t -= delta
		if chill_t <= 0.0:
			chill = 0
	if frozen_t > 0.0:
		frozen_t -= delta
		if frozen_t <= 0.0:
			_freeze_immune = 3.0
	_freeze_immune = maxf(0.0, _freeze_immune - delta)
	shock_t = maxf(0.0, shock_t - delta)
	return dmg


func frozen() -> bool:
	return frozen_t > 0.0


func burning() -> bool:
	return burn_t > 0.0


func shocked() -> bool:
	return shock_t > 0.0


## Movement and attack speed multiplier.
func speed_mult() -> float:
	if frozen_t > 0.0:
		return 0.0
	return 1.0 - CHILL_SLOW * chill


## Damage taken multiplier.
func damage_mult() -> float:
	return 1.0 + SHOCK_BONUS if shock_t > 0.0 else 1.0


func any() -> bool:
	return burn_t > 0.0 or chill > 0 or frozen_t > 0.0 or shock_t > 0.0


func clear() -> void:
	burn_t = 0.0
	burn_dps = 0.0
	chill_t = 0.0
	chill = 0
	frozen_t = 0.0
	shock_t = 0.0
	_burn_acc = 0.0


## Tint for the owner's model: strongest effect wins.
func tint() -> Color:
	if frozen_t > 0.0:
		return Color(0.55, 0.85, 1.0)
	if burn_t > 0.0:
		return Color(1.0, 0.55, 0.2)
	if shock_t > 0.0:
		return Color(0.75, 0.7, 1.0)
	if chill > 0:
		return Color(0.75, 0.9, 1.0)
	return Color.WHITE


## Short labels for a HUD line, e.g. ["Burning", "Chilled x2"].
func labels() -> Array[String]:
	var out: Array[String] = []
	if frozen_t > 0.0:
		out.append("Frozen")
	elif chill > 0:
		out.append("Chilled x%d" % chill)
	if burn_t > 0.0:
		out.append("Burning")
	if shock_t > 0.0:
		out.append("Shocked")
	return out
