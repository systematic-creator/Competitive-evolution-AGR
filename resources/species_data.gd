class_name SpeciesData
extends Resource
## Data definition for a playable species: identity, traits, and starting
## bonuses. Instances live as `.tres` files in `res://data/species/`.

@export_group("Identity")
@export var species_id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var faction_color: Color = Color.WHITE

@export_group("Traits")
## Trait tags read by simulation systems (e.g. `&"nocturnal"`, `&"aquatic"`).
@export var traits: Array[StringName] = []

@export_group("Starting Bonuses")
## Era index this species starts in (see EraData.era_index).
@export var starting_era_index: int = 0
## Resource ID (StringName, e.g. `&"food"`) -> starting amount (int).
@export var starting_resources: Dictionary = {}
@export var starting_unit_count: int = 3

@export_group("Multipliers")
@export_range(0.0, 5.0, 0.01, "or_greater") var gather_rate_multiplier: float = 1.0
@export_range(0.0, 5.0, 0.01, "or_greater") var build_speed_multiplier: float = 1.0
@export_range(0.0, 5.0, 0.01, "or_greater") var research_speed_multiplier: float = 1.0
@export_range(0.0, 5.0, 0.01, "or_greater") var unit_health_multiplier: float = 1.0
@export_range(0.0, 5.0, 0.01, "or_greater") var unit_speed_multiplier: float = 1.0


func has_trait(trait_id: StringName) -> bool:
	return traits.has(trait_id)


func get_starting_resource(resource_id: StringName) -> int:
	return int(starting_resources.get(resource_id, 0))
