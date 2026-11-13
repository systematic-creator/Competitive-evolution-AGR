extends Node
## Global simulation state (autoload: `GameState`).
##
## Owns the current zoom tier, the registered factions, and the global tick
## clock. Pure data + timing only: never touches meshes or AR transforms.

enum ZoomTier { ORBIT, REGION, RTS, THIRD_PERSON }

## Seconds between simulation ticks.
const DEFAULT_TICK_INTERVAL: float = 1.0

var current_zoom_tier: ZoomTier = ZoomTier.ORBIT:
	set = set_zoom_tier

## Region currently locked on from the orbit globe (empty when none).
var selected_region_id: StringName = &""

## faction_id (StringName) -> SpeciesData
var factions: Dictionary = {}

var tick_interval: float = DEFAULT_TICK_INTERVAL
var tick_count: int = 0
var is_simulation_running: bool = false

var _tick_accumulator: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	EventBus.region_selected.connect(_on_region_selected)


func _process(delta: float) -> void:
	if not is_simulation_running:
		return
	_tick_accumulator += delta
	while _tick_accumulator >= tick_interval:
		_tick_accumulator -= tick_interval
		tick_count += 1
		EventBus.simulation_ticked.emit(tick_count)


func set_zoom_tier(new_tier: ZoomTier) -> void:
	if new_tier == current_zoom_tier:
		return
	var previous_tier: ZoomTier = current_zoom_tier
	current_zoom_tier = new_tier
	EventBus.zoom_tier_changed.emit(new_tier, previous_tier)


func start_simulation() -> void:
	is_simulation_running = true


func stop_simulation() -> void:
	is_simulation_running = false
	_tick_accumulator = 0.0


func register_faction(faction_id: StringName, species: SpeciesData) -> void:
	assert(not factions.has(faction_id), "Faction already registered: %s" % faction_id)
	factions[faction_id] = species
	EventBus.faction_registered.emit(faction_id, species)


func get_faction_species(faction_id: StringName) -> SpeciesData:
	return factions.get(faction_id) as SpeciesData


func reset() -> void:
	stop_simulation()
	factions.clear()
	tick_count = 0
	selected_region_id = &""
	current_zoom_tier = ZoomTier.ORBIT


func _on_region_selected(region_id: StringName) -> void:
	selected_region_id = region_id
