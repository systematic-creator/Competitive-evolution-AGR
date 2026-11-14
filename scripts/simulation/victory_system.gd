class_name VictorySystem
extends RefCounted
## Evaluates data-driven win conditions each tick and tracks hold progress.

var conditions: Array[WinConditionData] = []
## "faction_id|condition_id" -> consecutive qualifying ticks
var hold: Dictionary = {}
var winner_id: StringName = &""
var winner_condition_id: StringName = &""
## faction_id -> Array of {id, name, kind, progress, held, required}
var snapshot: Dictionary = {}


func setup(loaded: Array[WinConditionData]) -> void:
	conditions = loaded
	hold.clear()
	winner_id = &""
	winner_condition_id = &""
	snapshot.clear()


func evaluate(world: SimWorld) -> void:
	if world == null:
		return
	snapshot.clear()
	if winner_id != &"":
		_fill_frozen_snapshot(world)
		return
	var ids: Array[StringName] = world.faction_ids()
	ids.sort()
	for faction_id: StringName in ids:
		var faction: SimFaction = world.get_faction(faction_id)
		if faction == null or faction.species == null:
			continue
		var rows: Array[Dictionary] = []
		for condition: WinConditionData in conditions:
			if not faction.species.can_pursue_win(condition.condition_id):
				continue
			var progress: float = 0.0
			var qualifying: bool = false
			match condition.kind:
				&"domination":
					progress = _domination_progress(world, faction_id)
					qualifying = progress + 0.000001 >= condition.claimed_hex_percent
				&"superiority":
					progress = _superiority_progress(world, faction, condition)
					qualifying = progress >= 1.0
				&"destruction":
					progress = 1.0 if _rivals_eliminated(world, faction_id) else 0.0
					qualifying = progress >= 1.0
				_:
					pass
			var key: String = "%s|%s" % [String(faction_id), String(condition.condition_id)]
			var required: int = condition.required_hold_ticks()
			var held: int = int(hold.get(key, 0))
			if qualifying:
				held += 1
			else:
				held = 0
			hold[key] = held
			var row: Dictionary = {
				"id": condition.condition_id,
				"name": condition.display_name,
				"kind": condition.kind,
				"progress": progress,
				"held": held,
				"required": required,
				"qualifying": qualifying,
			}
			rows.append(row)
			EventBus.victory_progress.emit(faction_id, condition.condition_id, progress, held, required)
			if qualifying and held >= required:
				winner_id = faction_id
				winner_condition_id = condition.condition_id
				EventBus.victory_achieved.emit(faction_id, condition.condition_id, condition)
				snapshot[faction_id] = rows
				return
		snapshot[faction_id] = rows


func player_rows(world: SimWorld) -> Array[Dictionary]:
	var fid: StringName = &"" if world == null else world.player_faction_id
	var raw: Variant = snapshot.get(fid, [])
	var out: Array[Dictionary] = []
	for row in raw:
		out.append(row)
	return out


func _fill_frozen_snapshot(world: SimWorld) -> void:
	# Keep last rows for the HUD after a win; nothing else updates.
	if snapshot.is_empty():
		evaluate_readonly_not_needed(world)


func evaluate_readonly_not_needed(_world: SimWorld) -> void:
	pass


func _domination_progress(world: SimWorld, faction_id: StringName) -> float:
	if world.playable == null:
		return 0.0
	var total: int = 0
	var owned: int = 0
	for key: int in world.playable.hex_claims:
		total += 1
		if (world.playable.hex_claims[key] as StringName) == faction_id:
			owned += 1
	if total <= 0:
		return 0.0
	return float(owned) / float(total)


func _superiority_progress(world: SimWorld, faction: SimFaction, condition: WinConditionData) -> float:
	var rivals: int = 0
	var leads: int = 0
	var fid: StringName = faction.faction_id()
	var my_era: int = 0 if faction.era == null else faction.era.era_index
	var my_econ: int = economy_value(faction)
	for other_id: StringName in world.faction_ids():
		if other_id == fid:
			continue
		if world.faction_eliminated(other_id):
			continue
		rivals += 1
		var other: SimFaction = world.get_faction(other_id)
		if other == null:
			continue
		var other_era: int = 0 if other.era == null else other.era.era_index
		var era_ok: bool = my_era >= other_era + condition.era_lead
		var econ_ok: bool = float(my_econ) + 0.000001 >= float(economy_value(other)) * condition.economy_lead_ratio
		if era_ok and econ_ok:
			leads += 1
	if rivals <= 0:
		# Superiority requires at least one living rival; a clean wipe is Destruction.
		return 0.0
	return float(leads) / float(rivals)


func _rivals_eliminated(world: SimWorld, faction_id: StringName) -> bool:
	var saw_rival: bool = false
	for other_id: StringName in world.faction_ids():
		if other_id == faction_id:
			continue
		saw_rival = true
		if not world.faction_eliminated(other_id):
			return false
	return saw_rival


static func economy_value(faction: SimFaction) -> int:
	if faction == null:
		return 0
	var value: int = 0
	value += faction.get_resource(SimIds.FOOD)
	value += faction.get_resource(SimIds.WOOD)
	value += faction.get_resource(SimIds.STONE)
	value += faction.get_resource(SimIds.IRON) * 3
	value += faction.get_resource(SimIds.COAL) * 3
	return value
