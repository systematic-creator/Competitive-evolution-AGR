extends Node
## Global signal hub (autoload: `EventBus`).
##
## Simulation systems emit upward through these signals; visual nodes and UI
## connect to them instead of polling. This script holds no state and no logic.
##
## Zoom tiers are passed as `int` values of `GameState.ZoomTier` so this script
## has no parse-time dependency on other autoloads.

# --- Eras -------------------------------------------------------------------

## A faction advanced (or regressed) to a new era. Building/unit visuals swap
## their meshes from `new_era` while keeping grid coordinates and HP.
@warning_ignore("unused_signal")
signal era_changed(faction_id: StringName, new_era: EraData, previous_era: EraData)

# --- Camera / zoom ----------------------------------------------------------

## The active zoom tier changed. Values are `GameState.ZoomTier`.
@warning_ignore("unused_signal")
signal zoom_tier_changed(new_tier: int, previous_tier: int)

## Normalized progress (0.0 -> 1.0) of the ORBIT -> REGION crossfade.
@warning_ignore("unused_signal")
signal zoom_transition_progress(progress: float)

# --- World / selection ------------------------------------------------------

## A region pin on the orbit globe was tapped and locked on.
@warning_ignore("unused_signal")
signal region_selected(region_id: StringName)

## The AR world anchor was placed (or re-placed) in physical space.
@warning_ignore("unused_signal")
signal world_anchor_placed(anchor_transform: Transform3D)

# --- Simulation -------------------------------------------------------------

## Fired once per global simulation tick by `GameState`.
@warning_ignore("unused_signal")
signal simulation_ticked(tick: int)

## A faction joined the simulation.
@warning_ignore("unused_signal")
signal faction_registered(faction_id: StringName, species: SpeciesData)

## A faction's stockpile of a resource changed.
@warning_ignore("unused_signal")
signal faction_resource_changed(faction_id: StringName, resource_id: StringName, amount: int)

## A building was placed (possibly still under construction).
@warning_ignore("unused_signal")
signal building_placed(faction_id: StringName, building_id: int, building_type: StringName, grid_pos: Vector2i)

## A building finished construction.
@warning_ignore("unused_signal")
signal building_constructed(faction_id: StringName, building_id: int, building_type: StringName, grid_pos: Vector2i)

## A unit entered the simulation.
@warning_ignore("unused_signal")
signal unit_spawned(faction_id: StringName, unit_id: int, unit_type: StringName, position: Vector3)

## A unit was ordered to a new destination (move or gather).
@warning_ignore("unused_signal")
signal unit_destination_set(unit_id: int, destination: Vector3)

## The concept world finished bootstrapping (factions, region, starting units).
@warning_ignore("unused_signal")
signal world_bootstrapped()

# --- Third-person -----------------------------------------------------------

## The player possessed a unit (enter Tier 4). `unit` is the CharacterBody3D.
@warning_ignore("unused_signal")
signal unit_possessed(unit: Node3D)

## The player released the possessed unit (return to RTS tier).
@warning_ignore("unused_signal")
signal unit_released()
