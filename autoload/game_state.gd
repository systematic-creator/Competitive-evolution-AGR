extends Node
## Global simulation state (autoload: `GameState`).
##
## Owns the current zoom tier, the registered factions, the global tick
## clock, and the authoritative `SimWorld`. Pure data + timing only: never
## touches meshes or AR transforms.

enum ZoomTier { ORBIT, REGION, RTS, THIRD_PERSON }

## Seconds between simulation ticks.
const DEFAULT_TICK_INTERVAL: float = 1.0
## Match SkirmishCombat.STEP_SECONDS without naming that class from this autoload.
const COMBAT_STEP_SECONDS: float = 0.1

var _current_zoom_tier: ZoomTier = ZoomTier.ORBIT
var current_zoom_tier: ZoomTier:
	get:
		return _current_zoom_tier
	set(value):
		set_zoom_tier(value)

## Region currently locked on from the orbit globe (empty when none).
var selected_region_id: StringName = &""

## faction_id (StringName) -> SpeciesData (kept for smoke-test compatibility)
var factions: Dictionary = {}

var tick_interval: float = DEFAULT_TICK_INTERVAL
var tick_count: int = 0
var is_simulation_running: bool = false
var ai_enabled: bool = true
## When true and the zoom tier is RTS, the faint hex overlay is shown.
var build_or_claim_mode: bool = false

## Authoritative concept simulation. Null until `bootstrap_concept_world()`.
var world: SimWorld

## Player command facade, rebuilt alongside `world`.
var commands: CommandService

var _tick_accumulator: float = 0.0
var _combat_accumulator: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	EventBus.region_selected.connect(_on_region_selected)


func _process(delta: float) -> void:
	if not is_simulation_running:
		return
	if world != null and world.has_live_combat():
		# Tier 4 fight: hold the strategic tick and run fixed combat steps.
		_combat_accumulator += delta
		while _combat_accumulator >= COMBAT_STEP_SECONDS and world.has_live_combat():
			_combat_accumulator -= COMBAT_STEP_SECONDS
			world.step_combat()
		return
	_combat_accumulator = 0.0
	_tick_accumulator += delta
	while _tick_accumulator >= tick_interval:
		_tick_accumulator -= tick_interval
		step_ticks(1)


func set_zoom_tier(new_tier: ZoomTier) -> void:
	if new_tier == _current_zoom_tier:
		return
	var previous_tier: ZoomTier = _current_zoom_tier
	_current_zoom_tier = new_tier
	EventBus.zoom_tier_changed.emit(int(new_tier), int(previous_tier))


func set_build_or_claim_mode(active: bool) -> void:
	if build_or_claim_mode == active:
		return
	build_or_claim_mode = active
	EventBus.build_mode_changed.emit(active)


func start_simulation() -> void:
	is_simulation_running = true


func stop_simulation() -> void:
	is_simulation_running = false
	_tick_accumulator = 0.0
	_combat_accumulator = 0.0


func register_faction(faction_id: StringName, species: SpeciesData) -> void:
	assert(not factions.has(faction_id), "Faction already registered: %s" % faction_id)
	factions[faction_id] = species
	EventBus.faction_registered.emit(faction_id, species)


func get_faction_species(faction_id: StringName) -> SpeciesData:
	return factions.get(faction_id) as SpeciesData


func get_player_faction_id() -> StringName:
	if world == null:
		return &""
	return world.player_faction_id


## Advance the simulation `count` ticks immediately (used by tests and tools).
func step_ticks(count: int) -> void:
	for _i in count:
		tick_count += 1
		if world != null:
			world.step(tick_count, ai_enabled)
		EventBus.simulation_ticked.emit(tick_count)


## Advance live possession fights `count` combat steps immediately (tests/tools).
func step_combat(count: int) -> void:
	if world == null:
		return
	for _i in count:
		world.step_combat()


func bootstrap_concept_world(seed: int = 1) -> void:
	world = SimWorld.new()
	world.bootstrap_default(seed)
	commands = CommandService.new()
	commands.world = world
	world.commands = commands
	for faction_id: StringName in world.faction_ids():
		var sim_faction: SimFaction = world.get_faction(faction_id)
		if not factions.has(faction_id):
			register_faction(faction_id, sim_faction.species)
	EventBus.world_bootstrapped.emit()


func reset() -> void:
	stop_simulation()
	factions.clear()
	tick_count = 0
	selected_region_id = &""
	current_zoom_tier = ZoomTier.ORBIT
	world = null
	commands = null
	ai_enabled = true
	set_build_or_claim_mode(false)


func _on_region_selected(region_id: StringName) -> void:
	selected_region_id = region_id
