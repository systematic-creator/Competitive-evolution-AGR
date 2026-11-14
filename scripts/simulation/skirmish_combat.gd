class_name SkirmishCombat
extends RefCounted
## Deterministic fight for one Tier 4 possession skirmish.
##
## Pure simulation: no nodes, no RNG, no wall clock. `SimWorld.step_combat()`
## advances every live fight by one fixed combat step (`STEP_SECONDS`) while the
## strategic tick is held. The possessed unit moves only along the steering
## sector and strikes only when an attack is queued; both arrive as
## CommandService orders. Every other combatant (allies and enemies alike) is
## driven by the same simple rule set, so a replay of the command log
## reproduces the fight exactly.

## Wall-clock seconds per combat step (used by GameState for pacing only).
const STEP_SECONDS: float = 0.1
## Hard limit: after this many steps the fight is settled by remaining strength.
const MAX_STEPS: int = 600
## `SimUnit.speed` is metres per strategic tick; a combat step moves this share of it.
const MOVE_PER_STEP_SCALE: float = 0.1
const ATTACK_RANGE: float = 0.04
## The possessed unit gets a little extra reach so touch players can land hits.
const POSSESSED_ATTACK_RANGE: float = 0.05
const BASE_DAMAGE: float = 8.0
const ATTACK_COOLDOWN_STEPS: int = 6
const POSSESSED_DAMAGE_MULTIPLIER: float = 1.5
## A defending structure on the contested hex fights as a stationary guard.
const GUARD_HP: int = 60
const GUARD_RANGE: float = 0.07
const GUARD_DAMAGE: float = 4.0
const GUARD_COOLDOWN_STEPS: int = 8
## Steering is quantized so commands stay small and replay bit-exact.
const STEER_SECTORS: int = 16
## Arena: the contested hex plus its ring (radius 1), as a circle in metres.
const ARENA_RADIUS_HEXES: float = 2.6

## Must stay equal to ClaimSystem.STRUCTURE_DEFENSE (no class_name cycle).
const STRUCTURE_DEFENSE_WEIGHT: float = 0.75

var skirmish_id: int = -1
var attacker_id: StringName = &""
var defender_id: StringName = &""
var node_id: StringName = &""
var hex: Vector2i = Vector2i.ZERO
var center: Vector3 = Vector3.ZERO
var arena_radius: float = 0.16

var attackers: Array[int] = []
var defenders: Array[int] = []
## The unit the player is driving, or -1 (it died or was never set).
var possessed_unit_id: int = -1
var steer_sector: int = -1
var attack_queued: bool = false
## unit_id -> combat steps until the unit may strike again
var cooldowns: Dictionary = {}

var guard_hp: int = 0
var guard_max_hp: int = 0
var guard_cooldown: int = 0
var guard_building_id: int = -1
## Hold-time defense (Sylvari) scales defender damage.
var defender_damage_multiplier: float = 1.0

var steps: int = 0
var finished: bool = false
var winner_id: StringName = &""
var timed_out: bool = false

## Filled during `step()` for ClaimSystem to turn into EventBus signals.
## Each entry: {"unit_id": int, "hp": int, "max_hp": int} (unit_id -1 = guard)
var damage_events: Array[Dictionary] = []
var killed_this_step: Array[int] = []


static func sector_to_direction(sector: int) -> Vector3:
	if sector < 0:
		return Vector3.ZERO
	var angle: float = TAU * float(posmod(sector, STEER_SECTORS)) / float(STEER_SECTORS)
	# Sector 0 = -Z (north), increasing clockwise toward +X.
	return Vector3(sin(angle), 0.0, -cos(angle))


static func direction_to_sector(direction: Vector3) -> int:
	var flat := Vector2(direction.x, direction.z)
	if flat.length() < 0.2:
		return -1
	var angle: float = atan2(flat.x, -flat.y)
	return posmod(roundi(angle / TAU * float(STEER_SECTORS)), STEER_SECTORS)


## Godot yaw (rotation.y) that faces `direction` with the model's -Z forward.
static func yaw_for_direction(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)


func setup(world: SimWorld, record: Dictionary, attacker_units: Array[SimUnit], defender_units: Array[SimUnit], possessed_id: int) -> void:
	var region: SimRegion = world.playable
	skirmish_id = int(record.get("id", -1))
	attacker_id = record.get("attacker", &"") as StringName
	defender_id = record.get("defender", &"") as StringName
	node_id = record.get("node_id", &"") as StringName
	hex = HexGrid.unpack(int(record.get("hex_key", 0)))
	center = region.hex_grid.axial_to_world(hex)
	arena_radius = region.hex_grid.hex_size * ARENA_RADIUS_HEXES
	possessed_unit_id = possessed_id
	for unit: SimUnit in attacker_units:
		_enlist(unit, attackers)
	for unit: SimUnit in defender_units:
		_enlist(unit, defenders)
	var structure: SimBuilding = region.structure_on_hex(hex)
	if structure != null and defender_id != &"" and structure.faction_id == defender_id:
		guard_building_id = structure.id
		guard_max_hp = GUARD_HP
		guard_hp = GUARD_HP
	if defender_id != &"":
		var faction: SimFaction = world.get_faction(defender_id)
		if faction != null and faction.species != null:
			defender_damage_multiplier = region.defense_multiplier(region.world_to_cell(center), faction.species)


func _enlist(unit: SimUnit, side: Array[int]) -> void:
	unit.in_combat = true
	unit.has_destination = false
	unit.assigned_node_id = &""
	# Pull stragglers onto the arena edge so everyone fights in the contested hex.
	unit.position = _clamp_to_arena(unit.position)
	cooldowns[unit.id] = 0
	side.append(unit.id)


func living(world: SimWorld, side: Array[int]) -> Array[SimUnit]:
	var out: Array[SimUnit] = []
	for unit_id: int in side:
		var unit: SimUnit = world.playable.get_unit(unit_id)
		if unit != null and unit.hp > 0:
			out.append(unit)
	return out


func is_attacker_unit(unit_id: int) -> bool:
	return attackers.has(unit_id)


func cooldown_of(unit_id: int) -> int:
	return int(cooldowns.get(unit_id, 0))


func can_possessed_attack() -> bool:
	return possessed_unit_id >= 0 and cooldown_of(possessed_unit_id) <= 0 and not attack_queued


func step(world: SimWorld) -> void:
	damage_events.clear()
	killed_this_step.clear()
	if finished:
		return
	steps += 1
	for unit_id: Variant in cooldowns.keys():
		cooldowns[unit_id] = maxi(0, int(cooldowns[unit_id]) - 1)
	guard_cooldown = maxi(0, guard_cooldown - 1)
	_step_possessed(world)
	for unit: SimUnit in living(world, attackers):
		if unit.id != possessed_unit_id:
			_step_ai(world, unit, true)
	for unit: SimUnit in living(world, defenders):
		_step_ai(world, unit, false)
	_step_guard(world)
	_cull_dead(world)
	_check_end(world)


func _step_possessed(world: SimWorld) -> void:
	if possessed_unit_id < 0:
		return
	var unit: SimUnit = world.playable.get_unit(possessed_unit_id)
	if unit == null or unit.hp <= 0:
		return
	var direction: Vector3 = sector_to_direction(steer_sector)
	if direction != Vector3.ZERO:
		unit.position = _clamp_to_arena(unit.position + direction * unit.speed * MOVE_PER_STEP_SCALE)
		unit.facing = yaw_for_direction(direction)
	if attack_queued and cooldown_of(unit.id) <= 0:
		attack_queued = false
		cooldowns[unit.id] = ATTACK_COOLDOWN_STEPS
		var target: SimUnit = _nearest_enemy(world, unit, true)
		if target != null and _flat_distance(unit.position, target.position) <= POSSESSED_ATTACK_RANGE:
			unit.facing = yaw_for_direction(target.position - unit.position)
			_damage_unit(target, _damage_for(unit, true, true))
		elif _guard_alive() and _flat_distance(unit.position, center) <= POSSESSED_ATTACK_RANGE + 0.02:
			_damage_guard(_damage_for(unit, true, true))
		# Otherwise the swing whiffs; the cooldown still applies.


func _step_ai(world: SimWorld, unit: SimUnit, is_attacker: bool) -> void:
	var target: SimUnit = _nearest_enemy(world, unit, is_attacker)
	var target_pos: Vector3
	var hits_guard: bool = false
	if target != null:
		target_pos = target.position
	elif is_attacker and _guard_alive():
		target_pos = center
		hits_guard = true
	else:
		return
	var distance: float = _flat_distance(unit.position, target_pos)
	var reach: float = ATTACK_RANGE + (0.02 if hits_guard else 0.0)
	if distance > reach:
		var offset: Vector3 = target_pos - unit.position
		offset.y = 0.0
		var step_len: float = minf(unit.speed * MOVE_PER_STEP_SCALE, distance - reach * 0.8)
		if step_len > 0.0:
			unit.position = _clamp_to_arena(unit.position + offset.normalized() * step_len)
			unit.facing = yaw_for_direction(offset)
		return
	if cooldown_of(unit.id) > 0:
		return
	cooldowns[unit.id] = ATTACK_COOLDOWN_STEPS
	unit.facing = yaw_for_direction(target_pos - unit.position)
	if hits_guard:
		_damage_guard(_damage_for(unit, is_attacker, false))
	else:
		_damage_unit(target, _damage_for(unit, is_attacker, false))


func _step_guard(world: SimWorld) -> void:
	if not _guard_alive() or guard_cooldown > 0:
		return
	var best: SimUnit = null
	var best_d: float = GUARD_RANGE
	for unit: SimUnit in living(world, attackers):
		var d: float = _flat_distance(unit.position, center)
		if d <= best_d:
			best = unit
			best_d = d
	if best == null:
		return
	guard_cooldown = GUARD_COOLDOWN_STEPS
	_damage_unit(best, maxi(1, roundi(GUARD_DAMAGE * defender_damage_multiplier)))


func _nearest_enemy(world: SimWorld, unit: SimUnit, is_attacker: bool) -> SimUnit:
	var enemies: Array[SimUnit] = living(world, defenders if is_attacker else attackers)
	var best: SimUnit = null
	var best_d: float = INF
	for enemy: SimUnit in enemies:
		var d: float = _flat_distance(unit.position, enemy.position)
		# Strict < keeps the earliest-enlisted unit on ties (deterministic).
		if d < best_d:
			best = enemy
			best_d = d
	return best


func _damage_for(unit: SimUnit, is_attacker: bool, possessed: bool) -> int:
	var damage: float = BASE_DAMAGE * SimCatalog.unit_combat_power(unit.unit_type)
	if possessed:
		damage *= POSSESSED_DAMAGE_MULTIPLIER
	if not is_attacker:
		damage *= defender_damage_multiplier
	return maxi(1, roundi(damage))


func _damage_unit(target: SimUnit, amount: int) -> void:
	target.hp = maxi(0, target.hp - amount)
	damage_events.append({"unit_id": target.id, "hp": target.hp, "max_hp": target.max_hp})


func _damage_guard(amount: int) -> void:
	guard_hp = maxi(0, guard_hp - amount)
	damage_events.append({"unit_id": -1, "hp": guard_hp, "max_hp": guard_max_hp})


func _guard_alive() -> bool:
	return guard_hp > 0


func _cull_dead(world: SimWorld) -> void:
	for side: Array[int] in [attackers, defenders]:
		for unit_id: int in side:
			var unit: SimUnit = world.playable.get_unit(unit_id)
			if unit != null and unit.hp <= 0:
				killed_this_step.append(unit_id)
	for unit_id: int in killed_this_step:
		world.kill_unit(unit_id)
		if unit_id == possessed_unit_id:
			possessed_unit_id = -1
			attack_queued = false
			steer_sector = -1


func _check_end(world: SimWorld) -> void:
	var attackers_left: int = living(world, attackers).size()
	var defenders_left: int = living(world, defenders).size() + (1 if _guard_alive() else 0)
	if attackers_left == 0:
		_finish(defender_id)
	elif defenders_left == 0:
		_finish(attacker_id)
	elif steps >= MAX_STEPS:
		timed_out = true
		_finish(decide_by_strength(world))


## Remaining-strength verdict (timeout and the auto-battle fallback).
## Ties go to the defender, matching auto-battle.
func decide_by_strength(world: SimWorld) -> StringName:
	return attacker_id if side_strength(world, true) > side_strength(world, false) else defender_id


func side_strength(world: SimWorld, attacking: bool) -> float:
	var total: float = 0.0
	for unit: SimUnit in living(world, attackers if attacking else defenders):
		var ratio: float = 1.0 if unit.max_hp <= 0 else float(unit.hp) / float(unit.max_hp)
		total += SimCatalog.unit_combat_power(unit.unit_type) * ratio
	if not attacking:
		if _guard_alive() and guard_max_hp > 0:
			total += STRUCTURE_DEFENSE_WEIGHT * float(guard_hp) / float(guard_max_hp)
		total *= defender_damage_multiplier
	return total


## Release every surviving combatant back to normal sim control.
func release_units(world: SimWorld) -> void:
	for side: Array[int] in [attackers, defenders]:
		for unit_id: int in side:
			var unit: SimUnit = world.playable.get_unit(unit_id)
			if unit != null:
				unit.in_combat = false
	possessed_unit_id = -1
	steer_sector = -1
	attack_queued = false


func _finish(winner: StringName) -> void:
	finished = true
	winner_id = winner
	steer_sector = -1
	attack_queued = false


func _clamp_to_arena(position: Vector3) -> Vector3:
	var offset: Vector3 = position - center
	offset.y = 0.0
	if offset.length() > arena_radius:
		offset = offset.normalized() * arena_radius
	return Vector3(center.x + offset.x, 0.0, center.z + offset.z)


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
