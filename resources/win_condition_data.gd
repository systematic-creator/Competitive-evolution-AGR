class_name WinConditionData
extends Resource
## Data definition for one victory path. Instances live as `.tres` files
## in `res://data/win_conditions/`. SpeciesData lists which IDs a species
## may pursue.

@export var condition_id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
## `&"domination"`, `&"superiority"`, or `&"destruction"`.
@export var kind: StringName = &"domination"

@export_group("Complete Domination")
## Share of all currently claimed hexes that must be held (0–1).
@export_range(0.0, 1.0, 0.01) var claimed_hex_percent: float = 0.6
@export var hold_ticks: int = 4

@export_group("Unbridgeable Superiority")
## Era index must lead every living rival by at least this much.
@export var era_lead: int = 1
## Economy score must be at least this ratio times each living rival.
@export_range(1.0, 10.0, 0.01, "or_greater") var economy_lead_ratio: float = 1.5
@export var superiority_hold_ticks: int = 4

@export_group("Utter Destruction")
## Ticks the "no living rivals" state must be held (usually 1).
@export var destruction_hold_ticks: int = 1


func required_hold_ticks() -> int:
	match kind:
		&"superiority":
			return maxi(1, superiority_hold_ticks)
		&"destruction":
			return maxi(1, destruction_hold_ticks)
		_:
			return maxi(1, hold_ticks)
