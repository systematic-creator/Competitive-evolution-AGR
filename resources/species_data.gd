class_name SpeciesData
extends Resource
## Data definition for a playable species: identity, traits, starting bonuses,
## unique mechanics, and AI personality weights.
## Instances live as `.tres` files in `res://data/species/`.

@export_group("Identity")
@export var species_id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var faction_color: Color = Color.WHITE
## Optional per-species labels for era indices 0..n (e.g. Cogforged Clockwork
## -> Synthetics). Empty entries fall back to EraData.era_name.
@export var era_display_names: PackedStringArray = PackedStringArray()

@export_group("Traits")
## Trait tags read by simulation systems (e.g. `&"swarm"`, `&"synthetic"`).
@export var traits: Array[StringName] = []

@export_group("Starting Bonuses")
## Era index this species starts in (see EraData.era_index).
@export var starting_era_index: int = 0
## WinConditionData.condition_id values this species may pursue.
@export var allowed_win_condition_ids: Array[StringName] = []
## Resource ID (StringName, e.g. `&"food"`) -> starting amount (int).
@export var starting_resources: Dictionary = {}
@export var starting_unit_count: int = 3

@export_group("Multipliers")
@export_range(0.0, 5.0, 0.01, "or_greater") var gather_rate_multiplier: float = 1.0
@export_range(0.0, 5.0, 0.01, "or_greater") var build_speed_multiplier: float = 1.0
@export_range(0.0, 5.0, 0.01, "or_greater") var research_speed_multiplier: float = 1.0
@export_range(0.0, 5.0, 0.01, "or_greater") var unit_health_multiplier: float = 1.0
@export_range(0.0, 5.0, 0.01, "or_greater") var unit_speed_multiplier: float = 1.0
## Applied to worker and soldier resource costs (Kraal is cheaper).
@export_range(0.1, 5.0, 0.01, "or_greater") var unit_cost_multiplier: float = 1.0
## Applied to era-advance resource costs (Humans cheaper / faster; Kraal slower).
@export_range(0.1, 5.0, 0.01, "or_greater") var era_cost_multiplier: float = 1.0
@export_range(0.1, 5.0, 0.01, "or_greater") var train_speed_multiplier: float = 1.0

@export_group("Unique Mechanics")
## Sylvari: resource nodes on owned territory refill this much remaining per tick.
@export var territory_regen_per_tick: int = 0
## Sylvari: additive defense multiplier gained each tick a cell is continuously held.
@export_range(0.0, 1.0, 0.001) var defense_hold_bonus_per_tick: float = 0.0
@export_range(0.0, 5.0, 0.01) var max_hold_defense_bonus: float = 0.0
## Sylvari only: if true, `territory_regen_per_tick` applies solely to common nodes.
## (Always the case; rare nodes never regrow.)
## Kraal: extra yield when gathering from a node (they harvest faster).
@export_range(0.0, 5.0, 0.01, "or_greater") var harvest_speed_multiplier: float = 1.0
## Kraal: remaining on a node falls this much faster than the yield taken (over-harvest).
@export_range(0.1, 5.0, 0.01, "or_greater") var node_depletion_multiplier: float = 1.0
## Cogforged: extra production multiplier applied to building output (camps, foundry, TC).
@export_range(0.0, 5.0, 0.01) var industry_production_bonus: float = 0.0
## Cogforged: units are constructed (wood/stone costs) rather than born (food costs).
@export var units_are_constructed: bool = false
## Cogforged: may place Extractors adjacent to rare nodes.
@export var can_build_extractors: bool = false
## Cogforged: extra rare-node yield when an Extractor is adjacent (0.75 = +75%).
@export_range(0.0, 5.0, 0.01) var extractor_rare_yield_bonus: float = 0.0

@export_group("AI Personality")
## Relative weights used by FactionAI. Player species still carry them for
## consistency and for any future AI-controlled Human opponents.
@export_range(0.0, 5.0, 0.01) var ai_expand_weight: float = 1.0
@export_range(0.0, 5.0, 0.01) var ai_military_weight: float = 1.0
@export_range(0.0, 5.0, 0.01) var ai_economy_weight: float = 1.0
@export_range(0.0, 5.0, 0.01) var ai_era_weight: float = 1.0
@export_range(0.0, 5.0, 0.01) var ai_defense_weight: float = 1.0
## Preference for water/coast tiles when siting buildings and assigning gatherers.
@export_range(0.0, 5.0, 0.01) var ai_water_preference: float = 0.0
## How strongly the AI values and contests rare (iron / coal) nodes.
@export_range(0.0, 5.0, 0.01) var ai_rare_weight: float = 1.0
## Escalation personality: `&"aggressive"` (Kraal), `&"defensive"` (Sylvari),
## `&"methodical"` (Cogforged), or `&"balanced"` (Humans).
@export var ai_escalation_style: StringName = &"balanced"


func has_trait(trait_id: StringName) -> bool:
	return traits.has(trait_id)


func get_starting_resource(resource_id: StringName) -> int:
	return int(starting_resources.get(resource_id, 0))


func era_label(era: EraData) -> String:
	if era == null:
		return ""
	if era.era_index >= 0 and era.era_index < era_display_names.size():
		var label: String = era_display_names[era.era_index]
		if not label.is_empty():
			return label
	return era.era_name


func can_pursue_win(condition_id: StringName) -> bool:
	return allowed_win_condition_ids.has(condition_id)
